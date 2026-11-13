extends SceneTree
# 규칙 점검. 실행: godot --headless --path godot -s tests/smoke.gd -- --sandbox
const Data = preload("res://scripts/data.gd")

var fails = 0

func check(cond, label):
	if cond:
		print("ok    ", label)
	else:
		fails += 1
		print("FAIL  ", label)

func wait(sec):
	var n = int(sec * 60.0)
	for i in n:
		await physics_frame

func _initialize():
	Engine.time_scale = 1.0
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await wait(0.2)
	var far = Vector2(1600, 300)

	# 1. 근접 지상 유닛은 공중을 못 때린다
	var st = game.spawn_unit(0, "stinger", far)
	var sw = game.spawn_unit(1, "swarm", far + Vector2(20, 0))
	await wait(3.0)
	check(is_instance_valid(st) and st.hp < st.max_hp, "혼인비행 떼가 지상 침병을 공격한다")
	check(is_instance_valid(sw) and sw.hp == sw.max_hp, "침병(근접)은 공중 유닛을 공격하지 못한다")
	if is_instance_valid(st):
		st.take_damage(9999, null)
	# 2. 원거리 유닛은 공중을 때린다
	var sp = game.spawn_unit(0, "sprayer", far + Vector2(60, 0))
	await wait(4.0)
	check(not is_instance_valid(sw) or sw.dead or sw.hp < sw.max_hp, "분사병(원거리)은 공중 유닛을 공격한다")
	if is_instance_valid(sw) and not sw.dead:
		sw.take_damage(9999, null)
	sp.take_damage(9999, null)
	await wait(0.2)

	# 3. 정찰병은 싸우지 않는다
	var sc = game.spawn_unit(0, "scout", far)
	var dummy = game.spawn_unit(1, "worker", far + Vector2(15, 0))
	await wait(2.0)
	check(dummy.hp == dummy.max_hp, "날개 정찰병은 공격하지 않는다")
	sc.take_damage(9999, null)
	dummy.take_damage(9999, null)
	await wait(0.2)

	# 4. 거점화
	var w = game.spawn_unit(0, "wall", far)
	w.toggle_root()
	var before = w.position
	w.cmd_move(far + Vector2(300, 0))
	await wait(1.0)
	check(w.rooted and w.position.distance_to(before) < 1.0, "거점화한 방벽 개미는 이동하지 않는다")
	var hp0 = w.hp
	w.take_damage(10.0, null)
	check(abs((hp0 - w.hp) - 10.0 * Data.ROOT_DAMAGE_MULT) < 0.01, "거점화 중 받는 피해 감소")
	w.toggle_root()
	w.cmd_move(far + Vector2(300, 0))
	await wait(1.0)
	check(w.position.distance_to(before) > 20.0, "거점화를 풀면 이동한다")
	w.take_damage(9999, null)

	# 5. 폭군 대병의 침병 강화
	var s2 = game.spawn_unit(0, "stinger", far + Vector2(0, 200))
	await wait(1.0)
	check(not s2.buffed, "폭군 대병이 없으면 강화 없음")
	var ty = game.spawn_unit(0, "tyrant", far + Vector2(30, 200))
	await wait(1.0)
	check(s2.buffed, "폭군 대병 근처 침병 강화")
	s2.take_damage(9999, null)
	ty.take_damage(9999, null)

	# 6. 날개 산실은 주 둥지 II 가 필요하다
	var p = game.players[0]
	p.mat = 2000.0
	p.food = 2000.0
	var main = game.main_nest(0)
	var spot = main.position + Vector2(0, -160)
	check(game.start_build(0, "special", spot, []) == null, "주 둥지 I 에서는 날개 산실 건설 불가")
	main.tier = 2
	var sb = game.start_build(0, "special", spot, [])
	check(sb != null, "주 둥지 II 에서는 날개 산실 건설 가능")
	if sb != null:
		sb.add_build(1000.0)
		check(sb.built, "건설 완료")
		check(game.enqueue_unit(sb, "swarm"), "혼인비행 떼 생산 예약")
		Engine.time_scale = 8.0
		await wait(Data.UNITS["swarm"]["time"] / 8.0 + 2.0)
		Engine.time_scale = 1.0
		var n_sw = 0
		for u in game.units:
			if u.pid == 0 and u.kind == "swarm":
				n_sw += 1
		check(n_sw == 2, "혼인비행 떼 2기 한 조 생산 (실제 %d)" % n_sw)
	# 7. T3 는 주 둥지 III 필요
	var cb = game.start_build(0, "combat", main.position + Vector2(0, 170), [])
	if cb != null:
		cb.add_build(1000.0)
		check(not game.enqueue_unit(cb, "tyrant"), "주 둥지 II 에서는 폭군 대병 생산 불가")
		main.tier = 3
		check(game.enqueue_unit(cb, "tyrant"), "주 둥지 III 에서는 폭군 대병 생산 가능")
	else:
		check(false, "전투 생산 건물 건설")

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
