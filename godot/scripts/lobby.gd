extends Control
# 방 화면: 자리 5개를 나 / 인공지능 / 비움 / 사람(참가자)으로 정하고 진영·팀·난이도를 고른다.
# 혼자 하기: 나 + 인공지능. 온라인: "방 만들기"로 방장이 되거나, 방 코드로 "참가"한다.
# 브라우저에서는 연결 중개 서버 주소가 필요하다(주소 끝 ?signal=wss://... 또는 아래 DEFAULT_SIGNAL).
const Data = preload("res://scripts/data.gd")
const ConfigScript = preload("res://scripts/config.gd")

const FACTION_CHOICES = ["random", "fire", "leaf", "weaver", "trap", "army"]
const DIFF_CHOICES = ["easy", "normal", "hard"]
const DEFAULT_SIGNAL = "wss://ant-rts-signaling.onrender.com"     # 배포한 연결 중개 서버 주소(예: wss://example.com). 비어 있으면 주소의 ?signal= 을 쓴다
const T_AI = 0
const T_EMPTY = 1
const T_PEOPLE = 2

var rows = []          # 자리마다 {type, faction, team, diff} 옵션 버튼
var mode_btn
var map_btn
var balance_chk
var info
var start_btn
var net
var name_edit
var code_edit
var host_btn
var join_btn
var net_status
var slot_peer = {}     # 방장: 자리 번호 -> 참가자 peer_id
var names = []         # 자리 이름 표시 라벨

func _ready():
	# 점검·자동 대전 실행이나, 주소로 진영을 정한 경우에는 방 화면을 건너뛴다
	var args = OS.get_cmdline_user_args()
	var skip = args.has("--autotest") or args.has("--sandbox")
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("me=") or q.contains("ai="):
			skip = true
	if skip and ConfigScript.setup == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	net = get_node("/root/Net")
	_build()
	net.lobby_changed.connect(_on_lobby_changed)
	net.status.connect(func(t): net_status.text = t)
	net.left.connect(func(reason):
		net_status.text = reason
		slot_peer.clear()
		_refresh())

func _back():
	if net != null and net.is_online():
		net.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")

func _label(text, size = 16):
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _option(items, selected):
	var o = OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(selected)
	o.custom_minimum_size = Vector2(140, 36)
	o.item_selected.connect(func(_i): _refresh())
	return o

func _build():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://scripts/ui_theme.gd").make()
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var online_mode = ConfigScript.lobby_mode == "online"
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var back = Button.new()
	back.text = "← 처음 화면"
	back.pressed.connect(_back)
	head.add_child(back)
	head.add_child(_label("온라인 대전" if online_mode else "혼자 하기", 30))
	box.add_child(_label("방을 만들어 방 코드를 친구에게 알려 주거나, 받은 방 코드로 참가하세요." if online_mode else "자리마다 인공지능을 넣고 진영·팀·난이도를 고른 뒤 시작하세요.", 14))

	var online = HBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	online.visible = online_mode
	box.add_child(online)
	online.add_child(_label("이름"))
	name_edit = LineEdit.new()
	name_edit.text = "개미%d" % (randi() % 900 + 100)
	name_edit.custom_minimum_size = Vector2(110, 34)
	online.add_child(name_edit)
	host_btn = Button.new()
	host_btn.text = "방 만들기"
	host_btn.pressed.connect(_host)
	online.add_child(host_btn)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "방 코드" if OS.has_feature("web") else "주소:포트"
	code_edit.custom_minimum_size = Vector2(130, 34)
	online.add_child(code_edit)
	join_btn = Button.new()
	join_btn.text = "참가"
	join_btn.pressed.connect(_join)
	online.add_child(join_btn)
	net_status = _label("", 14)
	net_status.visible = online_mode
	box.add_child(net_status)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	top.add_child(_label("대전 형태"))
	mode_btn = _option(["개인전", "팀전"], 0)
	top.add_child(mode_btn)
	balance_chk = CheckBox.new()
	balance_chk.text = "인원 불균형 보정"
	balance_chk.tooltip_text = "팀전에서 인원이 적은 팀의 채집 속도를 모자란 인원 1명당 +25%"
	balance_chk.toggled.connect(func(_b): _refresh())
	top.add_child(balance_chk)
	top.add_child(_label("   지도 크기"))
	var mnames = ["자동"]
	for k in Data.MAP_SIZE_IDS.slice(1):
		var sz = Data.MAP_SIZES[k]["size"]
		mnames.append("%s (%d×%d)" % [Data.MAP_SIZES[k]["name"], int(sz.x), int(sz.y)])
	map_btn = _option(mnames, 0)
	map_btn.custom_minimum_size = Vector2(190, 36)
	top.add_child(map_btn)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for h in ["자리", "참가", "진영", "팀", "난이도"]:
		grid.add_child(_label(h, 14))
	var fnames = ["무작위"]
	for f in Data.FACTION_IDS:
		fnames.append(Data.FACTIONS[f]["name"])
	var dnames = []
	for d in DIFF_CHOICES:
		dnames.append(Data.DIFFS[d]["name"])
	for i in Data.MAX_PLAYERS:
		var swatch = HBoxContainer.new()
		var cr = ColorRect.new()
		cr.color = Data.PLAYER_COLORS[i]
		cr.custom_minimum_size = Vector2(18, 18)
		swatch.add_child(cr)
		var nl = _label(" 자리 %d" % (i + 1))
		names.append(nl)
		swatch.add_child(nl)
		grid.add_child(swatch)
		# 혼자 하기에서는 참가자 자리를 고를 수 없다(오지 않을 사람을 기다리게 되므로)
		var kinds = ["인공지능", "비움", "사람(참가자)"] if online_mode else ["인공지능", "비움"]
		var type = _option(["나"] if i == 0 else kinds, 0 if i <= 1 else 1)
		type.disabled = (i == 0)
		grid.add_child(type)
		var fac = _option(fnames, 1 if i == 0 else 2 if i == 1 else 0)
		grid.add_child(fac)
		var team = _option(["팀 1", "팀 2", "팀 3", "팀 4", "팀 5"], 0 if i == 0 else 1)
		grid.add_child(team)
		var diff = _option(dnames, 1)
		grid.add_child(diff)
		rows.append({"type": type, "faction": fac, "team": team, "diff": diff})

	info = _label("", 14)
	box.add_child(info)
	start_btn = Button.new()
	start_btn.text = "시작"
	start_btn.custom_minimum_size = Vector2(200, 48)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_start)
	box.add_child(start_btn)
	_refresh()

func _active(i):
	return i == 0 or rows[i]["type"].selected != T_EMPTY

# ---------- 온라인 ----------

func _signal_url():
	var url = DEFAULT_SIGNAL
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		for part in q.trim_prefix("?").split("&"):
			var kv = part.split("=")
			if kv.size() == 2 and kv[0] == "signal":
				url = kv[1].uri_decode()
	return url

func _host():
	net.my_name = name_edit.text.strip_edges()
	slot_peer.clear()
	if OS.has_feature("web"):
		var url = _signal_url()
		if url == "":
			net_status.text = "연결 중개 서버 주소가 설정되지 않았습니다(주소 끝에 ?signal=wss://... 를 붙이세요)"
			return
		net.host_online(url)
	else:
		net.host_direct()
	_refresh()

func _join():
	net.my_name = name_edit.text.strip_edges()
	var code = code_edit.text.strip_edges()
	if code == "":
		net_status.text = "방 코드를 입력하세요"
		return
	if OS.has_feature("web"):
		var url = _signal_url()
		if url == "":
			net_status.text = "연결 중개 서버 주소가 설정되지 않았습니다(주소 끝에 ?signal=wss://... 를 붙이세요)"
			return
		net.join_online(url, code)
	else:
		net.join_direct(code)
	_refresh()

# 방장: 들어온 참가자를 "사람" 자리에(없으면 빈자리에) 앉히고, 나간 참가자의 자리를 비운다
func _seat_peers():
	for i in slot_peer.keys():
		if not net.peers.has(slot_peer[i]):
			slot_peer.erase(i)
			rows[i]["type"].select(T_EMPTY)
	for id in net.peers:
		if slot_peer.values().has(id):
			continue
		var seat = -1
		for i in range(1, rows.size()):
			if rows[i]["type"].selected == T_PEOPLE and not slot_peer.has(i):
				seat = i
				break
		if seat < 0:
			for i in range(1, rows.size()):
				if rows[i]["type"].selected == T_EMPTY:
					seat = i
					break
		if seat >= 0:
			slot_peer[seat] = id
			rows[seat]["type"].select(T_PEOPLE)

func _on_lobby_changed():
	if net.is_host():
		_seat_peers()
	elif net.is_client() and not net.lobby.is_empty():
		# 참가자: 방장이 보낸 상태를 그대로 보여 준다
		var st = net.lobby
		mode_btn.select(st["mode"])
		balance_chk.button_pressed = st["balance"]
		map_btn.select(st.get("map", 0))
		for i in rows.size():
			var r = st["rows"][i]
			rows[i]["type"].select(r["type"])
			rows[i]["faction"].select(r["faction"])
			rows[i]["team"].select(r["team"])
			rows[i]["diff"].select(r["diff"])
			names[i].text = " " + r["name"]
	_refresh()

func _lobby_state():
	var rs = []
	for i in rows.size():
		var nm = "자리 %d" % (i + 1)
		if i == 0:
			nm = net.my_name + " (방장)"
		elif slot_peer.has(i):
			nm = net.peers[slot_peer[i]]["name"]
		rs.append({"type": rows[i]["type"].selected, "faction": rows[i]["faction"].selected,
			"team": rows[i]["team"].selected, "diff": rows[i]["diff"].selected, "name": nm})
	return {"mode": mode_btn.selected, "balance": balance_chk.button_pressed, "map": map_btn.selected, "rows": rs}

func _refresh():
	var client = net != null and net.is_client()
	var host = net != null and net.is_host()
	if host:
		var st = _lobby_state()
		for i in rows.size():
			names[i].text = " " + st["rows"][i]["name"]
		net.send_lobby(st)
	elif not client:
		for i in rows.size():
			names[i].text = " 자리 %d" % (i + 1)
	if net != null:
		host_btn.disabled = net.is_online()
		join_btn.disabled = net.is_online()
	mode_btn.disabled = client
	balance_chk.disabled = client
	map_btn.disabled = client
	var team_mode = mode_btn.selected == 1
	balance_chk.visible = team_mode
	var n = 0
	var teams = {}
	for i in rows.size():
		var on = _active(i)
		# 격자 칸이 밀리지 않도록 숨기지 않고 비활성·투명 처리한다
		var people = i > 0 and rows[i]["type"].selected == T_PEOPLE
		rows[i]["type"].disabled = i == 0 or client
		rows[i]["faction"].disabled = not on or client
		rows[i]["team"].disabled = not on or not team_mode or client
		rows[i]["team"].modulate.a = 1.0 if team_mode else 0.0
		rows[i]["diff"].disabled = not on or i == 0 or people or client
		rows[i]["diff"].modulate.a = 0.0 if i == 0 or people else 1.0
		if on:
			n += 1
			teams[rows[i]["team"].selected if team_mode else i] = true
	var ok = n >= 2 and teams.size() >= 2
	var waiting = 0
	for i in range(1, rows.size()):
		if rows[i]["type"].selected == T_PEOPLE and not slot_peer.has(i):
			waiting += 1
	start_btn.disabled = not ok or client or waiting > 0
	start_btn.visible = not client
	var pop = int(Data.POP_MAX if n <= 3 else Data.POP_MAX_BIG)
	var choice = Data.MAP_SIZE_IDS[map_btn.selected]
	var key = Data.map_key(choice, n)
	var sz = Data.MAP_SIZES[key]["size"]
	var t = "참가 %d명 · %d인용 지도 %s(%d×%d) · 최대 인구 %d" % [n, n, Data.MAP_SIZES[key]["name"], int(sz.x), int(sz.y), pop]
	if choice == "small" and key != "small":
		t += "\n작은 지도는 4~5인에게 좁아서 보통 크기로 합니다"
	if n < 2:
		t += "\n인공지능이나 참가자를 1명 이상 넣어야 합니다"
	elif not ok:
		t += "\n팀전에는 두 팀 이상이 필요합니다"
	elif waiting > 0:
		t += "\n참가자 %d명을 기다리는 중" % waiting
	if client:
		t += "\n방장이 시작하기를 기다리는 중"
	info.text = t

func _start():
	var cfg = make_setup()
	if net != null and net.is_host():
		cfg["online"] = true
		cfg["me"] = 0
		net.start_game(cfg)
	ConfigScript.setup = cfg
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func make_setup():
	var team_mode = mode_btn.selected == 1
	var slots = []
	for i in rows.size():
		if not _active(i):
			continue
		var f = FACTION_CHOICES[rows[i]["faction"].selected]
		if f == "random":
			f = Data.FACTION_IDS[randi() % Data.FACTION_IDS.size()]
		var sl = {"type": "human" if i == 0 else "ai", "faction": f,
			"team": rows[i]["team"].selected, "diff": DIFF_CHOICES[rows[i]["diff"].selected]}
		if i == 0 and net != null and net.is_online():
			sl["name"] = net.my_name
		if i > 0 and rows[i]["type"].selected == T_PEOPLE and slot_peer.has(i):
			sl["type"] = "remote"
			sl["peer"] = slot_peer[i]
			sl["name"] = net.peers[slot_peer[i]]["name"]
		slots.append(sl)
	return {"mode": "team" if team_mode else "ffa", "slots": slots, "balance": team_mode and balance_chk.button_pressed,
		"map": Data.MAP_SIZE_IDS[map_btn.selected]}
