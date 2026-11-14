extends SceneTree
# 9~10단계 점검: 지도, 팀, 승패, 난이도, 방 화면, 인공지능 판단.
# 주의: 파괴된 건물·유닛을 지역 변수에 든 채로 await 하면 엔진(4.3)이 비정상 종료할 수 있다. 기다리기 전에 변수를 비운다.
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
	if OS.get_cmdline_user_args().has("--only-ai"):
		await ai_checks()
		print("RESULT fails=%d" % fails)
		quit(1 if fails > 0 else 0)
		return
	# 지도 검증(크기 4종 × 2~5인)
	for key in ["small", "medium", "large", "huge"]:
		for n in [2, 3, 4, 5]:
			if Data.map_key(key, n) != key:
				continue
			Data.MAP_SIZE = Data.MAP_SIZES[key]["size"]
			var L = MapGen.make(n, key)
			var T = TerrainScript.new()
			T.setup(L["terrain"])
			var s0 = L["starts"][0]
			var bad = 0
			for e in L["nodes"]:
				if T.kind_at(e[1]) != 0 or not T.reachable(s0, e[1], "ground"):
					bad += 1
			for e in L["expansions"] + L["starts"]:
				if not T.can_build(e, 40) or not T.reachable(s0, e, "ground"):
					bad += 1
			for c in L["camps"]:
				if not T.passable(c[0], "ground") or not T.reachable(s0, c[0], "ground"):
					bad += 1
			var md = 1e9
			for i in n:
				for j in range(i + 1, n):
					md = min(md, L["starts"][i].distance_to(L["starts"][j]))
			check(bad == 0 and md > 800.0, "%s %d인: 자원·확장·무리가 모두 쓸 수 있고 기지 사이 %d 이상" % [Data.MAP_SIZES[key]["name"], n, int(md)])
	check(Data.map_key("small", 5) == "medium" and Data.map_key("auto", 2) == "medium" and Data.map_key("auto", 4) == "large", "작게는 4~5인에서 보통으로, 자동은 2~3인 보통·4~5인 크게")
	var big2 = MapGen.make(2, "large")
	Data.MAP_SIZE = Data.MAP_SIZES["medium"]["size"]
	check(big2["expansions"].size() > MapGen.make(3, "medium")["expansions"].size() / 3 * 2, "큰 지도에는 기지마다 확장 지점이 더 있다")
	Data.MAP_SIZE = Data.MAP_SIZES["medium"]["size"]
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

	# 판마다 지도 크기가 정해진다
	var gm = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf"]), "balance": false, "map": "huge"})
	check(Data.MAP_SIZE == Vector2(6400, 4000) and gm.terrain.w == 200 and gm.fog.w == 200, "아주 크게: 지도·지형·안개가 6400×4000")
	await end_game(gm)
	gm = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf"]), "balance": false})
	check(Data.MAP_SIZE == Vector2(3200, 2000), "다음 판은 다시 자동 크기(2인 보통)")
	await end_game(gm)

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
	var cfg = lobby.make_setup()
	lobby.queue_free()
	check(cfg != null and cfg["mode"] == "team" and cfg["slots"].size() == 3, "시작하면 3자리 팀전 설정이 만들어진다")
	check(cfg["slots"][2]["faction"] == "trap" and cfg["slots"][2]["diff"] == "hard" and cfg["slots"][2]["team"] == 1, "자리별 진영·난이도·팀이 그대로 넘어간다")
	check(Data.FACTIONS.has(cfg["slots"][1]["faction"]), "무작위 진영은 실제 진영 하나로 정해진다")
	ConfigScript.setup = null

	await ai_checks()
	await title_checks()

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func ai_of(g, pid):
	for ai in g.ais:
		if ai.pid == pid:
			return ai
	return null

# 인공지능 점검: 인공지능 1명의 판단 함수를 직접 불러 확인한다
func ai_checks():
	# 전장의 안개
	var g = await start_game({"mode": "ffa", "slots": slots(["fire", "trap"]), "balance": false})
	var ai = ai_of(g, 1)
	ai.t = -99999.0
	ai._update_knowledge()
	check(ai.known.is_empty(), "인공지능은 처음에 상대 건물을 모른다(전장의 안개)")
	var goal = ai.attack_goal(g.main_nest(1))
	check(goal != null and goal.distance_to(g.layout["starts"][0]) < 1.0, "아는 것이 없으면 상대 시작 위치로 정찰을 간다")
	var mine = g.spawn_building(0, "combat", Vector2(900, 1000), true, false)
	ai._update_knowledge()
	check(not ai.known.has(mine.get_instance_id()), "보지 못한 건물은 모른다")
	var eye = g.spawn_unit(1, "worker", mine.position + Vector2(80, 0))
	ai._update_knowledge()
	check(ai.known.has(mine.get_instance_id()), "시야 안에 들어온 건물은 기억한다")
	eye.dead = true
	g.remove_unit(eye)
	ai._update_knowledge()
	check(ai.known.has(mine.get_instance_id()), "시야를 잃어도 본 건물은 기억한다")
	var mine_id = mine.get_instance_id()
	mine.take_damage(99999.0, null)
	# 파괴된 객체를 지역 변수에 든 채로 await 하면 엔진이 비정상 종료할 수 있어 미리 비운다
	mine = null
	eye = null
	await wait(0.1)
	ai._update_knowledge()
	check(not ai.known.has(mine_id), "파괴된 건물은 잊는다")
	await end_game(g)
	# 은폐 건물은 감지해야 안다
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "trap"]), "balance": false})
	ai = ai_of(g, 1)
	ai.t = -99999.0
	var hidden = g.spawn_building(1, "lab", Vector2(2500, 1300), true, false)
	g.players[0].is_ai = true
	var A0 = load("res://scripts/ai.gd").new()
	A0.setup(g, 0)
	var peek = g.spawn_unit(0, "stinger", hidden.position + Vector2(90, 0))
	await wait(0.1)
	A0._update_knowledge()
	check(not A0.known.has(hidden.get_instance_id()), "보이는 곳이어도 감지하지 못한 은폐 건물은 모른다")
	var sc = g.spawn_unit(0, "scout", hidden.position + Vector2(60, 0))
	await wait(0.1)
	A0._update_knowledge()
	check(A0.known.has(hidden.get_instance_id()), "감지하면 은폐 건물도 기억한다")
	await end_game(g)

	# 인구가 차면 둥지 등급을 올린다
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "leaf"]), "balance": false})
	ai = ai_of(g, 1)
	var L = g.players[1]
	g.spawn_building(1, "combat", g.main_nest(1).position + Vector2(0, 170), true, false)
	L.mat = 2000.0
	L.food = 2000.0
	var filler = g.spawn_unit(1, "major", g.main_nest(1).position + Vector2(-150, 0))
	filler.pop = 27.0
	ai.t = -99999.0
	await wait(0.1)
	check(L.pop_used >= L.pop_cap - 3.0, "점검 준비: 인구가 거의 찼다 (%.0f / %.0f)" % [L.pop_used, L.pop_cap])
	ai.t = 99.0
	ai.tick(0.0)
	check(g.main_nest(1).upgrade_t >= 0.0, "인구가 차면 둥지 등급 상승부터 한다")
	await end_game(g)

	# 지원 유닛과 유인병
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "trap"]), "balance": false})
	ai = ai_of(g, 1)
	var army = []
	for i in 4:
		army.append(g.spawn_unit(1, "hunter", Vector2(2000, 1600) + Vector2(i * 15, 0)))
	var lure = g.spawn_unit(1, "lure", Vector2(2600, 1000))
	ai._command_support([lure], army, g.main_nest(1))
	check(lure.state == lure.MOVE and lure.dest.distance_to(Vector2(2022, 1600)) < 40.0, "지원 유닛은 병력 한가운데로 따라간다")
	lure.position = Vector2(2000, 1600)
	var enemy = g.spawn_unit(0, "soldier", Vector2(2100, 1600))
	await wait(0.1)
	ai._command_support([lure], army, g.main_nest(1))
	check(lure.lure_cd > 0.0 and enemy.target == lure, "적이 가까이 오면 유인병이 경보 페로몬을 쓴다")
	await end_game(g)

	# 군대개미 약탈 무리
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "army"]), "balance": false})
	ai = ai_of(g, 1)
	ai.t = -99999.0
	var rs = []
	for i in 8:
		rs.append(g.spawn_unit(1, "raider", Vector2(2600, 1000) + Vector2(0, i * 12)))
	var rest = ai._raid(rs, g.main_nest(1))
	check(ai.raiders.size() == 6 and rest.size() == 2, "약탈병 6기를 약탈 무리로 떼어 낸다")
	check(ai.raiders[0].state == ai.raiders[0].AMOVE and ai.raiders[0].amove_dest.distance_to(g.layout["starts"][0]) < 450.0, "약탈 무리는 상대 기지 쪽으로 간다")
	await end_game(g)

	# 군대개미 이주: 이주를 시작한 뒤에 완성된 건물이 있어도 끝까지 옮겨 정착한다
	g = await start_game({"mode": "ffa", "slots": slots(["fire", "army"]), "balance": false})
	ai = ai_of(g, 1)
	ai.t = -99999.0
	var amain = g.main_nest(1)
	g.spawn_building(1, "combat", amain.position + Vector2(0, 170), true, false)
	var late = g.spawn_building(1, "defense", amain.position + Vector2(0, -170), false, false)
	var dest = ai._find_spot("nest", amain.position + Vector2(-350, 0))
	ai.migrate_to = dest
	ai.migrating = true
	ai.migrate_phase = "pack"
	g.pack_colony(1, true)
	Engine.time_scale = 8.0
	var started = g.elapsed
	var built_late = false
	while ai.migrating and g.elapsed - started < 150.0:
		await wait(0.25)
		if not built_late and g.elapsed - started > 3.0:
			late.add_build(1000.0)
			built_late = true
		ai._nomad(amain)
	Engine.time_scale = 1.0
	check(not ai.migrating, "이주가 끝난다 (%.0f초)" % (g.elapsed - started))
	var all_camp = true
	for b in g.buildings:
		if b.pid == 1 and not b.camped():
			all_camp = false
	check(all_camp and amain.position.distance_to(dest) < 100.0, "모든 건물이 새 자리에 야영한다(이주 중 완성된 건물 포함)")
	await end_game(g)

	# 불개미 뗏목 상륙
	g = await start_game({"mode": "ffa", "slots": slots(["leaf", "fire"]), "balance": false})
	ai = ai_of(g, 1)
	ai.t = -99999.0
	var raft = g.spawn_unit(1, "raft", Vector2(2500, 1000))
	var st = []
	for i in 4:
		st.append(g.spawn_unit(1, "stinger", Vector2(2520, 980 + i * 12)))
	ai.attacking = true
	ai._command_raft(raft, st)
	check(ai.raft_drop != null and st[0].state == st[0].BOARD, "공격을 시작하면 침병이 뗏목단에 탄다")
	await wait(2.5)
	check(raft.cargo.size() == 4, "침병 4기 탑승 (%d)" % raft.cargo.size())
	ai._command_raft(raft, st)
	await wait(0.1)
	check(raft.state == raft.MOVE, "뗏목단이 목표로 출발한다")
	await end_game(g)


# 메인 화면
func title_checks():
	ConfigScript.setup = null
	var t = load("res://scripts/title.gd").new()
	root.add_child(t)
	await wait(0.2)
	var names = []
	for b in t.find_children("*", "Button", true, false):
		names.append(b.text)
	check(names.has("혼자 하기") and names.has("온라인 대전") and names.has("진영 소개") and names.has("조작법") and names.has("설정"), "메인 화면: 혼자 하기·온라인 대전·진영 소개·조작법·설정")
	t.open_window("factions")
	check(t.windows["factions"].visible and not t.windows["help"].visible, "진영 소개 창이 열린다")
	var ok = true
	for f in Data.FACTION_IDS:
		t.show_faction(f)
		await wait(0.05)
		if t.preview.faction != f or t.info_box.get_child_count() < 6:
			ok = false
	check(ok, "다섯 진영 모두 소개(그림·콘셉트·강점·약점·상성·대표 유닛)")
	t.show_faction("trap")
	await wait(0.05)
	var texts = t.info_box.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return c.text)
	check(texts.any(func(x): return x.contains("군대개미 에 강하고") and x.contains("불개미 에 약하다")), "상성 문구가 기획서 순환과 같다(함정턱개미: 군대개미에 강하고 불개미에 약하다)")
	t.open_window("help")
	check(t.windows["help"].visible and not t.windows["factions"].visible, "조작법 창")
	t.open_window("settings")
	check(t.windows["settings"].visible, "설정 창")
	t.queue_free()
	await wait(0.1)
