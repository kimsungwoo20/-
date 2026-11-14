extends SceneTree
# 온라인 대전 점검(데스크톱 연결). 방장과 참가자를 서로 다른 프로그램으로 띄운다. tools/net_test.sh 가 순서대로 실행한다.
#   방장:   godot --headless --path godot -s tests/net_test.gd -- host <포트> <ffa|team>
#   참가자: godot --headless --path godot -s tests/net_test.gd -- client <포트> <표> <first|rejoin>
const ConfigScript = preload("res://scripts/config.gd")

var fails = 0
var net

func check(cond, label):
	if cond:
		print("ok    ", label)
	else:
		fails += 1
		print("FAIL  ", label)

func wait(sec):
	for i in int(sec * 60.0):
		await physics_frame

func wait_until(cond, limit):
	var t = 0.0
	while t < limit:
		if cond.call():
			return true
		await wait(0.1)
		t += 0.1
	return cond.call()

func finish():
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)

func _initialize():
	await process_frame
	net = root.get_node("Net")
	var a = OS.get_cmdline_user_args()
	if a[0] == "host":
		await host(int(a[1]), a[2])
	else:
		await client(int(a[1]), a[2], a[3])
	finish()

func host(port, mode):
	net.my_name = "방장"
	check(net.host_direct(port) == OK, "방장: 방 열기 (포트 %d)" % port)
	check(await wait_until(func(): return net.peers.size() == 1, 20.0), "방장: 참가자 입장")
	var peer = net.peers.keys()[0]
	check(net.peers[peer]["name"] == "참가자", "방장: 참가자 이름 전달")
	var team = mode == "team"
	var cfg = {"mode": mode, "balance": false, "online": true, "me": 0, "slots": [
		{"type": "human", "faction": "fire", "team": 0, "diff": "normal", "name": "방장"},
		{"type": "remote", "peer": peer, "faction": "leaf", "team": 0 if team else 1, "diff": "normal", "name": "참가자"},
		{"type": "ai", "faction": "trap", "team": 1 if team else 2, "diff": "normal"}]}
	net.start_game(cfg)
	ConfigScript.setup = cfg
	var g = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	await wait(0.5)
	check(g.net_role == "host" and not g.players[1].is_ai and g.players[2].is_ai, "방장: 판 시작 (참가자 자리는 사람, 3번 자리는 인공지능)")
	check(g.ais.size() == 1, "방장: 인공지능은 1명만")
	# 참가자의 명령이 실행되는가
	var target = g.layout["starts"][1].lerp(Vector2(1600, 1000), 0.3)
	var moved = await wait_until(func():
		var n = 0
		for u in g.units:
			if u.pid == 1 and u.is_worker and u.position.distance_to(target) < 90.0:
				n += 1
		return n >= 3, 20.0)
	check(moved, "방장: 참가자가 보낸 이동 명령이 실행된다")
	# 남의 유닛 명령은 거부
	var mine_far = true
	for u in g.units:
		if u.pid == 0 and u.position.distance_to(Vector2(1600, 300)) < 120.0:
			mine_far = false
	check(mine_far, "방장: 참가자가 방장 유닛에 내린 명령은 무시된다")
	# 접속 종료
	check(await wait_until(func(): return not net.pid_peer.has(1), 20.0), "방장: 참가자 접속 종료 감지")
	await wait(0.3)
	if mode == "ffa":
		check(g.players[1].is_ai and g.ais.any(func(ai): return ai.pid == 1), "개인전: 접속이 끊긴 자리를 인공지능이 이어받는다")
	else:
		check(not g.players[1].is_ai and g.transfers.get(1, -1) == 0 and g.controls(1), "팀전: 접속이 끊긴 아군을 방장이 조종한다")
		var u1 = null
		for u in g.units:
			if u.pid == 1 and u.is_worker:
				u1 = u
				break
		g.act("move", [[u1], Vector2(2000, 1500), false])
		check(u1.state == u1.MOVE, "팀전: 넘겨받은 아군 유닛에 명령할 수 있다")
	# 재접속
	check(await wait_until(func(): return net.pid_peer.has(1), 25.0), "방장: 같은 사람의 재접속")
	await wait(0.3)
	check(not g.players[1].is_ai and not g.ais.any(func(ai): return ai.pid == 1) and not g.transfers.has(1), "방장: 재접속하면 조종권을 돌려준다")
	await wait(3.0)

func client(port, tok, phase):
	net.my_name = "참가자"
	net.token = tok
	check(net.join_direct("127.0.0.1:%d" % port) == OK, "참가자(%s): 연결 시작" % phase)
	check(await wait_until(func(): return net.game != null, 20.0), "참가자(%s): 판 시작 신호를 받아 게임 화면으로" % phase)
	var g = net.game
	check(await wait_until(func(): return g.units.size() > 10 and g.buildings.size() >= 3, 10.0), "참가자(%s): 방장이 보낸 상태로 유닛·건물이 나타난다" % phase)
	check(g.net_role == "client" and g.human_id == 1 and g.ais.is_empty(), "참가자(%s): 내 자리는 2번, 화면에서는 계산하지 않는다" % phase)
	check(g.res_nodes.size() > 10 and g.players[1].faction == "leaf", "참가자(%s): 자원 지점과 진영 정보" % phase)
	if phase == "rejoin":
		await wait(1.0)
		check(not g.players[1].is_ai, "참가자(rejoin): 다시 사람이 조종하는 자리로 돌아왔다")
		return
	var my = g.units.filter(func(u): return u.pid == 1 and u.is_worker)
	check(my.size() == 6, "참가자: 내 일꾼 6기")
	# 내 기지와 중앙 사이(방장 점검과 같은 계산)
	var target = g.layout["starts"][1].lerp(Vector2(1600, 1000), 0.3)
	g.act("move", [my, target, false])
	# 남의(방장) 유닛에 명령해 본다
	var theirs = g.units.filter(func(u): return u.pid == 0 and u.is_worker)
	g.act("move", [theirs, Vector2(1600, 300), false])
	var arrived = await wait_until(func():
		var n = 0
		for u in g.units:
			if u.pid == 1 and u.is_worker and u.position.distance_to(target) < 90.0:
				n += 1
		return n >= 3, 20.0)
	check(arrived, "참가자: 내 명령이 실행되어 화면에 반영된다")
	check(g.players[1].food > 0.0 and g.players[1].pop_cap >= 30.0, "참가자: 자원·인구 정보가 온다")
	await wait(1.0)
	net.leave()     # 접속을 끊는다
	await wait(0.5)
