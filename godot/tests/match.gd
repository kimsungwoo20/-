extends SceneTree
# 9단계 점검: 지도, 팀, 승패, 난이도, 방 화면.
# 실행: godot --headless --path godot -s tests/match.gd   (인공지능과 승패 판정이 필요하므로 --sandbox 없이)
const Data = preload("res://scripts/data.gd")
const MapGen = preload("res://scripts/mapgen.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const ConfigScript = preload("res://scripts/config.gd")

var fails = 0

func check(cond, label):
	if cond:
		print("ok    ", label)
	else:
		fails += 1
		print("FAIL  ", label)

func wait(sec):
	for i in int(sec * 60.0):
		await physics_frame

func start_game(setup):
	ConfigScript.setup = setup
	var g = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	await wait(0.3)
	return g

func end_game(g):
	g.queue_free()
	ConfigScript.setup = null
	await wait(0.1)

func slots(fs, teams = null):
	var out = []
	for i in fs.size():
		out.append({"type": "human" if i == 0 else "ai", "faction": fs[i], "team": teams[i] if teams != null else i, "diff": "normal"})
	return out

func _initialize():
	# 지도 검증(2~5인)
	for n in [2, 3, 4, 5]:
		var L = MapGen.make(n)
		var T = TerrainScript.new()
		T.setup(L["terrain"])
		var s0 = L["starts"][0]
		var bad = 0
		for e in L["nodes"]:
			if T.kind_at(e[1]) != 0 or not T.reachable(s0, e[1], "ground"):
				bad += 1
			for s in L["starts"]:
				if e[1].distance_to(s) < 40 + MapGen.RADII[e[0]] + 40:
					bad += 1
		for s in L["starts"]:
			if not T.can_build(s, 40) or not T.reachable(s0, s, "ground"):
				bad += 1
		for e in L["expansions"]:
			if not T.can_build(e, 40) or not T.reachable(s0, e, "ground"):
				bad += 1
		for c in L["camps"]:
			if not T.passable(c[0], "ground") or not T.reachable(s0, c[0], "ground"):
				bad += 1
		check(L["starts"].size() == n and bad == 0, "%d인 지도: 시작 위치 %d, 자원·확장·무리 모두 땅 위에 있고 서로 닿는다" % [n, n])
		var per = {}
		for e in L["nodes"]:
			for i in n:
				if e[1].distance_to(L["starts"][i]) < 320.0:
					per[i] = per.get(i, []) + [e[0]]
		var fair = true
		for i in n:
			var k = per.get(i, [])
			if not (k.has("seed") and k.has("litter") and k.has("aphid")):
				fair = false
		check(fair, "%d인 지도: 모든 기지 옆에 씨앗·낙엽·진딧물" % n)
	check(MapGen.make(2)["nodes"].size() == 21, "2인 지도는 기존 대칭 지도 그대로")

	# 5인 개인전
	var g = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf", "weaver", "trap", "army"]), "balance": false})
	for ai in g.ais:
		ai.t = -99999.0
	var act = g.players.filter(func(p): return p.active and not p.neutral)
	check(act.size() == 5 and g.ais.size() == 4 and not g.players[0].is_ai, "5인 개인전: 사람 1 + 인공지능 4")
	check(g.pop_max == Data.POP_MAX_BIG, "4~5인 판 최대 인구 %d" % int(Data.POP_MAX_BIG))
	var nests = 0
	for b in g.buildings:
		if b.kind == "nest" and b.is_main:
			nests += 1
	check(nests == 5, "참가자마다 주 둥지")
	check(g.is_enemy(1, 2) and g.is_enemy(0, 4), "개인전: 모두가 적")
	await end_game(g)

	# 3인 판 최대 인구
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf", "trap"]), "balance": false})
	check(g.pop_max == Data.POP_MAX, "2~3인 판 최대 인구 %d" % int(Data.POP_MAX))
	await end_game(g)

	# 팀전 2 대 2
	g = await start_game({"mode": "team", "slots": slots(["fire", "leaf", "weaver", "trap"], [0, 0, 1, 1]), "balance": false})
	check(not g.is_enemy(0, 1) and g.is_enemy(0, 2) and not g.is_enemy(2, 3), "팀전: 같은 팀은 적이 아니다")
	for ai in g.ais:
		ai.t = -99999.0      # 점검하는 동안 인공지능을 멈춘다
	var spot = Vector2(1600, 300)
	var a = g.spawn_unit(0, "stinger", spot)
	var ally = g.spawn_unit(1, "cutter", spot + Vector2(20, 0))
	await wait(2.0)
	check(a.hp == a.max_hp and ally.hp == ally.max_hp, "같은 팀 유닛끼리는 공격하지 않는다")
	var foe = g.spawn_unit(2, "acid", spot + Vector2(60, 0))
	await wait(2.0)
	check(foe.hp < foe.max_hp or foe.dead, "다른 팀 유닛은 공격한다")
	# 시야와 감지 공유
	var far_ally = g.spawn_unit(1, "worker", Vector2(1600, 1800))
	var near_foe = g.spawn_unit(3, "hunter", Vector2(1640, 1800))
	near_foe.can_fight = false
	await wait(0.4)
	g._update_fog()
	check(g.fog.is_visible_at(far_ally.position) and near_foe.visible, "아군 유닛의 시야를 함께 본다")
	var shade = g.spawn_unit(3, "shade", Vector2(1600, 1700))
	await wait(0.2)
	check(not g.is_detected(shade, 0), "아무도 감지하지 못하면 은신 유닛은 감지되지 않는다")
	var eye = g.spawn_unit(1, "pathfinder", Vector2(1600, 1660))
	await wait(0.2)
	check(g.is_detected(shade, 0), "아군의 감지를 함께 쓴다")
	# 아군을 오른쪽 클릭해도 공격하지 않는다
	g.set_selection([a])
	g._right_click(ally.position)
	check(a.target != ally, "아군을 오른쪽 클릭하면 공격하지 않는다")
	# 승패: 한 팀이 모두 탈락해야 끝난다
	g._eliminate(g.players[2])
	await wait(0.1)
	check(not g.game_over, "상대 팀이 1명 남아 있으면 계속된다")
	g._eliminate(g.players[1])
	await wait(0.1)
	check(not g.game_over and g.players[0].alive, "아군이 탈락해도 내가 살아 있으면 계속된다")
	g._eliminate(g.players[3])
	await wait(0.1)
	check(g.game_over and g.winner == 0, "상대 팀이 전부 탈락하면 우리 팀 승리")
	await end_game(g)

	# 사람이 탈락하면 판이 끝난다(관전 없음)
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf", "trap"]), "balance": false})
	g._eliminate(g.players[0])
	await wait(0.1)
	check(g.game_over, "사람이 탈락하면 다른 인공지능이 남아 있어도 판이 끝난다")
	await end_game(g)

	# 인원 불균형 보정
	g = await start_game({"mode": "team", "slots": slots(["fire", "leaf", "trap"], [0, 1, 1]), "balance": true})
	check(abs(g.players[0].gather_mult - 1.25) < 0.001 and g.players[1].gather_mult == 1.0, "인원 불균형 보정: 1명 팀 채집 +25%")
	var f0 = g.players[0].food
	g.deposit(0, "food", 10.0)
	check(abs(g.players[0].food - f0 - 12.5) < 0.01, "보정된 채집량이 반납에 적용된다")
	await end_game(g)

	# 난이도
	var sl = slots(["fire", "leaf", "trap", "weaver"])
	sl[1]["diff"] = "easy"
	sl[2]["diff"] = "normal"
	sl[3]["diff"] = "hard"
	g = await start_game({"mode": "ffa", "slots": sl, "balance": false})
	var by = {}
	for ai in g.ais:
		by[g.players[ai.pid].diff] = ai
	check(by["easy"].diff["tick"] > by["normal"].diff["tick"] and by["hard"].diff["tick"] < by["normal"].diff["tick"], "난이도별 판단 간격: 쉬움 > 보통 > 어려움")
	check(by["easy"].wave_size > by["normal"].wave_size, "쉬움은 더 큰 병력이 모일 때까지 공격하지 않는다")
	check(g.players[3].gather_mult == 1.2 and g.players[2].gather_mult == 1.0 and g.players[0].gather_mult == 1.0, "어려움만 채집 +20%, 보통·사람은 보너스 없음")
	await end_game(g)

	# 방 화면
	ConfigScript.setup = null
	var lobby = load("res://scripts/lobby.gd").new()
	root.add_child(lobby)
	check(lobby.rows.size() == 5 and lobby.rows[0]["type"].disabled, "방 화면: 자리 5개, 1번 자리는 나")
	check(not lobby.start_btn.disabled, "기본(나 + 인공지능 1)으로 시작할 수 있다")
	lobby.rows[1]["type"].select(1)
	lobby._refresh()
	check(lobby.start_btn.disabled, "인공지능이 없으면 시작할 수 없다")
	lobby.rows[1]["type"].select(0)
	lobby.rows[2]["type"].select(0)
	lobby.mode_btn.select(1)
	for i in 3:
		lobby.rows[i]["team"].select(0)
	lobby._refresh()
	check(lobby.start_btn.disabled, "팀전에서 모두 같은 팀이면 시작할 수 없다")
	lobby.rows[2]["team"].select(1)
	lobby.rows[2]["diff"].select(2)
	lobby.rows[2]["faction"].select(4)
	lobby._refresh()
	check(not lobby.start_btn.disabled, "두 팀이 되면 시작할 수 있다")
	lobby._start()
	var cfg = ConfigScript.setup
	check(cfg != null and cfg["mode"] == "team" and cfg["slots"].size() == 3, "시작하면 3자리 팀전 설정이 만들어진다")
	check(cfg["slots"][2]["faction"] == "trap" and cfg["slots"][2]["diff"] == "hard" and cfg["slots"][2]["team"] == 1, "자리별 진영·난이도·팀이 그대로 넘어간다")
	check(Data.FACTIONS.has(cfg["slots"][1]["faction"]), "무작위 진영은 실제 진영 하나로 정해진다")
	ConfigScript.setup = null

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
