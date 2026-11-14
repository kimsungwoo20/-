extends Node
# 온라인 대전 연결(자동 로드 노드, 장면이 바뀌어도 남는다).
# 방장(host)이 판 전체를 계산하고, 참가자(client)는 명령을 보내고 상태를 받아 그린다.
# 연결: 브라우저에서는 연결 중개 서버(server/signaling.js)를 거쳐 브라우저끼리 직접(WebRTC),
#       데스크톱·점검에서는 주소:포트로 직접(ENet).
const Data = preload("res://scripts/data.gd")

signal lobby_changed          # 방 상태가 바뀌었다(참가자 입장·퇴장, 방장 설정)
signal status(text)           # 화면에 보여 줄 연결 상태
signal left(reason)           # 방에서 나가게 됐다(연결 실패, 방장 퇴장 등)

const DEFAULT_PORT = 7777
const SNAP_EVERY = 0.15       # 상태 전송 간격(초)

var role = "offline"          # offline / host / client
var my_name = "플레이어"
var token = ""                # 재접속 때 같은 사람인지 확인하는 표
var room_code = ""
var signal_url = ""

# 방장
var peers = {}                # peer_id -> {"name", "token"}
var token_pid = {}            # 판 시작 후: token -> pid
var pid_peer = {}             # 판 시작 후: pid -> peer_id
var config = null             # 시작한 판 설정
# 참가자
var lobby = {}                # 방장이 보내 준 방 상태
var game = null               # 진행 중인 게임 장면(game.gd 가 스스로 등록)
var in_game = false

# WebRTC
var ws = null
var rtc = null
var conns = {}
var pending = []

func _ready():
	randomize()
	token = _load_token()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("연결하지 못했습니다"))
	multiplayer.server_disconnected.connect(func(): _fail("방장과의 연결이 끊겼습니다"))

func _load_token():
	var t = ""
	if OS.has_feature("web"):
		t = str(JavaScriptBridge.eval("window.localStorage.getItem('ant_rts_token') || ''", true))
	if t == "" or t == "null":
		t = "%08x%08x" % [randi(), randi()]
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.localStorage.setItem('ant_rts_token', '%s')" % t, true)
	return t

func is_online():
	return role != "offline"

func is_host():
	return role == "host"

func is_client():
	return role == "client"

func leave():
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if ws != null:
		ws.close()
	ws = null
	rtc = null
	conns.clear()
	pending.clear()
	role = "offline"
	peers.clear()
	token_pid.clear()
	pid_peer.clear()
	lobby = {}
	config = null
	in_game = false
	room_code = ""

func _fail(reason):
	var was = role
	leave()
	if was != "offline":
		left.emit(reason)

# ---------- 방 만들기·참가 ----------

# 데스크톱·점검용: 포트로 방을 연다
func host_direct(port = DEFAULT_PORT):
	leave()
	var p = ENetMultiplayerPeer.new()
	var err = p.create_server(port, Data.MAX_PLAYERS)
	if err != OK:
		status.emit("방을 열지 못했습니다 (포트 %d)" % port)
		return err
	multiplayer.multiplayer_peer = p
	role = "host"
	room_code = "127.0.0.1:%d" % port
	status.emit("방을 열었습니다: %s" % room_code)
	lobby_changed.emit()
	return OK

func join_direct(address):
	leave()
	var parts = address.split(":")
	var host = parts[0] if parts[0] != "" else "127.0.0.1"
	var port = int(parts[1]) if parts.size() > 1 else DEFAULT_PORT
	var p = ENetMultiplayerPeer.new()
	var err = p.create_client(host, port)
	if err != OK:
		status.emit("연결하지 못했습니다")
		return err
	multiplayer.multiplayer_peer = p
	role = "client"
	room_code = address
	status.emit("연결 중...")
	return OK

# 브라우저용: 연결 중개 서버를 거친다
func host_online(url):
	leave()
	signal_url = url
	role = "host"
	rtc = WebRTCMultiplayerPeer.new()
	rtc.create_server()
	multiplayer.multiplayer_peer = rtc
	_open_ws(url, {"t": "host"})
	status.emit("연결 중개 서버에 연결 중...")

func join_online(url, code):
	leave()
	signal_url = url
	role = "client"
	room_code = code.to_upper().strip_edges()
	_open_ws(url, {"t": "join", "code": room_code})
	status.emit("방 %s 에 참가 중..." % room_code)

func _open_ws(url, first):
	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(url)
	if err != OK:
		_fail("연결 중개 서버 주소가 잘못됐습니다")
		return
	pending = [first]

func _ws_send(msg):
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
	else:
		pending.append(msg)

func _process(_delta):
	if ws == null:
		return
	ws.poll()
	var st = ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		while pending.size() > 0:
			ws.send_text(JSON.stringify(pending.pop_front()))
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(m) == TYPE_DICTIONARY:
				_on_signal(m)
	elif st == WebSocketPeer.STATE_CLOSED:
		ws = null
		# 판이 시작된 뒤에는 중개 서버가 끊겨도 브라우저끼리의 연결은 유지된다
		if not in_game and role != "offline" and multiplayer.get_peers().is_empty():
			_fail("연결 중개 서버에 연결하지 못했습니다")

func _on_signal(m):
	match m.get("t", ""):
		"room":
			room_code = m["code"]
			status.emit("방 코드: %s" % room_code)
			lobby_changed.emit()
		"joined":
			rtc = WebRTCMultiplayerPeer.new()
			rtc.create_client(int(m["id"]))
			multiplayer.multiplayer_peer = rtc
			_make_conn(1, false)
		"peer":
			_make_conn(int(m["id"]), true)
		"offer", "answer":
			var c = conns.get(int(m["from"]))
			if c != null:
				c.set_remote_description(m["t"], m["sdp"])
		"cand":
			var c = conns.get(int(m["from"]))
			if c != null:
				c.add_ice_candidate(m["mid"], int(m["idx"]), m["sdp"])
		"peer_left":
			var id = int(m["id"])
			conns.erase(id)
			if rtc != null and rtc.has_peer(id):
				rtc.remove_peer(id)
		"closed":
			if not in_game:
				_fail("방장이 방을 닫았습니다")
		"error":
			_fail(m.get("msg", "오류"))

func _make_conn(id, offer):
	var c = WebRTCPeerConnection.new()
	c.initialize({"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]})
	c.session_description_created.connect(func(type, sdp):
		c.set_local_description(type, sdp)
		_ws_send({"t": type, "to": id, "sdp": sdp}))
	c.ice_candidate_created.connect(func(mid, idx, sdp):
		_ws_send({"t": "cand", "to": id, "mid": mid, "idx": idx, "sdp": sdp}))
	conns[id] = c
	rtc.add_peer(c, id)
	if offer:
		c.create_offer()

# ---------- 접속과 퇴장 ----------

func _on_connected():
	status.emit("방에 들어왔습니다. 방장이 시작하기를 기다리는 중")
	_c_hello.rpc_id(1, my_name, token)

func _on_peer_connected(_id):
	pass

func _on_peer_disconnected(id):
	if not is_host():
		return
	if in_game:
		for pid in pid_peer.keys():
			if pid_peer[pid] == id:
				pid_peer.erase(pid)
				if game != null:
					game.on_player_left(pid)
	if peers.has(id):
		peers.erase(id)
		lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _c_hello(name, tok):
	if not is_host():
		return
	var id = multiplayer.get_remote_sender_id()
	# 판 진행 중: 같은 표를 가진 사람이면 재접속, 아니면 거절
	if in_game:
		if token_pid.has(tok) and game != null:
			var pid = token_pid[tok]
			pid_peer[pid] = id
			peers[id] = {"name": name, "token": tok}
			var cfg = config.duplicate(true)
			cfg["me"] = pid
			_s_start.rpc_id(id, cfg)
			game.on_player_rejoined(pid)
		else:
			_s_refuse.rpc_id(id, "이미 시작한 판입니다")
		return
	peers[id] = {"name": name, "token": tok}
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _s_refuse(reason):
	_fail(reason)

# ---------- 방 상태 ----------

# 방장: 방 화면이 바뀔 때마다 모두에게 보낸다
func send_lobby(state):
	if is_host():
		_s_lobby.rpc(state)

@rpc("authority", "call_remote", "reliable")
func _s_lobby(state):
	lobby = state
	lobby_changed.emit()

func my_peer_id():
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1

# 방장: 판 시작. slots 의 "remote" 자리에는 "peer" 가 들어 있다
func start_game(cfg):
	config = cfg
	in_game = true
	token_pid.clear()
	pid_peer.clear()
	for pid in cfg["slots"].size():
		var sl = cfg["slots"][pid]
		if sl["type"] == "remote":
			var peer = sl["peer"]
			pid_peer[pid] = peer
			token_pid[peers[peer]["token"]] = pid
			var c = cfg.duplicate(true)
			c["me"] = pid
			_s_start.rpc_id(peer, c)

@rpc("authority", "call_remote", "reliable")
func _s_start(cfg):
	in_game = true
	config = cfg
	var Config = load("res://scripts/config.gd")
	Config.setup = cfg
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ---------- 판 진행 중 ----------

func send_cmd(name, args):
	_c_cmd.rpc_id(1, name, args)

@rpc("any_peer", "call_remote", "reliable")
func _c_cmd(name, args):
	if not is_host() or game == null:
		return
	var id = multiplayer.get_remote_sender_id()
	for pid in pid_peer:
		if pid_peer[pid] == id:
			game.net_command(pid, name, args)
			return

func send_snapshot(snap):
	for pid in pid_peer:
		_s_snap.rpc_id(pid_peer[pid], snap)

@rpc("authority", "call_remote", "unreliable_ordered")
func _s_snap(snap):
	if game != null:
		game.apply_snapshot(snap)

func send_msg(pid, text):
	if pid_peer.has(pid):
		_s_msg.rpc_id(pid_peer[pid], text)

@rpc("authority", "call_remote", "reliable")
func _s_msg(text):
	if game != null:
		game.msg(text)
