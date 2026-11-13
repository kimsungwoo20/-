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

func clear_units(game):
	for u in game.units.duplicate():
		if not u.is_worker:
			u.dead = true
			game.remove_unit(u)

func first_hit(game, attacker_kind, pid):
	# 지정한 유닛이 무방비 일꾼을 처음 때린 피해량
	var far = Vector2(2400, 300)
	var a = game.spawn_unit(pid, attacker_kind, far)
	var v = game.spawn_unit(1 - pid, "worker", far + Vector2(16, 0))
	v.max_hp = 9999.0
	v.hp = 9999.0
	for i in 240:
		await physics_frame
		if v.hp < 9999.0:
			break
	var dmg = 9999.0 - v.hp
	a.dead = true
	game.remove_unit(a)
	v.dead = true
	game.remove_unit(v)
	return dmg

func research_checks(game, main):
	var p = game.players[0]
	p.mat = 50000.0
	p.food = 50000.0
	clear_units(game)
	var lab = game.start_build(0, "lab", main.position + Vector2(-170, 0), [])
	check(lab != null, "연구소 건설")
	lab.add_build(1000.0)
	check(game.start_build(0, "lab", main.position + Vector2(-170, 170), []) == null, "연구소는 하나만")

	# 상태 규칙
	main.tier = 1
	check(game.research_state(lab, "jaw1") == "ok", "큰턱 강화 I: 주 둥지 I 에서 가능")
	check(game.research_state(lab, "jaw2") == "tier", "큰턱 강화 II: 주 둥지 II 필요")
	check(game.research_state(lab, "multiqueen") == "tier", "고유 기술: 주 둥지 II 필요")
	check(game.enqueue_research(lab, "jaw1"), "큰턱 강화 I 예약")
	main.tier = 2
	check(game.research_state(lab, "jaw2") == "ok", "앞 단계가 예약되어 있으면 다음 단계 예약 가능")
	check(game.research_state(lab, "shell2") == "req", "외골격 경화 II: I 단계가 먼저 필요")
	check(game.enqueue_research(lab, "jaw2") and game.enqueue_research(lab, "shell1") and game.enqueue_research(lab, "carry1"), "예약 3개")
	check(not game.enqueue_research(lab, "spawn1"), "진행 1 + 예약 3 을 넘으면 예약 불가")
	var m0 = p.mat
	game.cancel_last(lab)
	check(p.mat == m0 + Data.RESEARCH["carry1"]["mat"], "예약 취소 시 전액 환불")
	main.tier = 3
	p.research["venom1"] = true
	game.enqueue_research(lab, "shell2")
	game.cancel_last(lab)
	lab.queue.clear()
	check(game.research_state(lab, "wave") == "ok" and game.research_state(lab, "burn") == "ok", "분기 진화 둘 다 선택 가능")
	game.enqueue_research(lab, "wave")
	check(game.research_state(lab, "burn") == "taken", "한쪽 분기를 예약하면 다른 쪽은 선택 불가")
	lab.queue.clear()
	p.research.erase("venom1")
	check(game.research_state(lab, "burn") == "req", "타오르는 독은 솔레놉신 독침이 먼저 필요")

	# 연구 진행과 완료
	Engine.time_scale = 8.0
	game.enqueue_research(lab, "colony1")
	await wait(0.1)
	var cap0 = p.pop_cap
	await wait(Data.RESEARCH["colony1"]["time"] / 8.0 + 1.0)
	Engine.time_scale = 1.0
	check(p.has("colony1") and p.pop_cap == cap0 + 10.0, "군체 확대 I 완료 후 인구 한도 +10")

	# 연구소 파괴: 완료 연구 유지, 진행 연구 환불
	game.enqueue_research(lab, "colony2")
	m0 = p.mat
	lab.take_damage(99999.0, null)
	await wait(0.1)
	check(p.mat == m0 + Data.RESEARCH["colony2"]["mat"], "연구소 파괴 시 진행 중 연구 환불")
	check(p.has("colony1"), "연구소 파괴 후에도 완료한 연구 유지")
	check(game.start_build(0, "lab", main.position + Vector2(-170, 0), []) != null, "연구소 재건 가능")

	# 능력치 효과
	var base = await first_hit(game, "stinger", 0)
	p.research["jaw1"] = true
	p.research["jaw2"] = true
	var up = await first_hit(game, "stinger", 0)
	check(abs(base - 5.0) < 0.01 and abs(up - 6.0) < 0.01, "큰턱 강화 II: 근접 피해 5 → 6 (실제 %.2f → %.2f)" % [base, up])
	var g0 = await first_hit(game, "sprayer", 0)
	p.research["gland1"] = true
	var g1 = await first_hit(game, "sprayer", 0)
	check(abs(g1 - g0 * 1.1) < 0.01, "분비샘 강화 I: 원거리 피해 +10%")
	var w = game.spawn_unit(0, "wall", Vector2(2400, 900))
	var h0 = w.max_hp
	p.research["size1"] = true
	game.on_research_done(0, "size1")
	check(abs(w.max_hp - h0 * 1.1) < 0.01 and abs(w.hp - w.max_hp) < 0.01, "체격 증대 I: 기존 유닛 체력도 +10%")
	p.research["shell1"] = true
	var hp1 = w.hp
	w.take_damage(100.0, null)
	check(abs((hp1 - w.hp) - 92.0) < 0.01, "외골격 경화 I: 받는 피해 -8%")
	w.dead = true
	game.remove_unit(w)
	var sp0 = game.spawn_unit(0, "stinger", Vector2(2400, 1200))
	check(abs(sp0.spd() - 100.0) < 0.01, "다리 근육 전 이동 속도 100")
	p.research["legs1"] = true
	check(abs(sp0.spd() - 110.0) < 0.01, "다리 근육: 이동 속도 +10%")
	sp0.dead = true
	game.remove_unit(sp0)
	check(abs(p.carry_amount() - 10.0) < 0.01, "운반량 기본 10")
	p.research["carry1"] = true
	p.research["carry2"] = true
	check(abs(p.carry_amount() - 14.0) < 0.01, "운반낭 발달 II: 운반량 14")

	# 유지비
	p.pop_used = 100.0
	var u0 = p.upkeep_mult()
	p.research["troph1"] = true
	var u1 = p.upkeep_mult()
	check(abs(u0 - 0.8) < 0.001 and abs(u1 - 0.85) < 0.001, "영양 교환 I: 식량 수입 80%% → 85%% (실제 %.2f → %.2f)" % [u0, u1])
	p.research.erase("troph1")

	# 독
	var vic = game.spawn_unit(1, "soldier", Vector2(2800, 1500))
	vic.max_hp = 9999.0
	vic.hp = 9999.0
	vic.add_venom(p.venom_cap(), false)
	check(vic.venom_stacks == 0, "솔레놉신 독침 없으면 독 없음")
	p.research["venom1"] = true
	for i in 9:
		vic.add_venom(p.venom_cap(), false)
	check(vic.venom_stacks == 5, "독 최대 5중첩")
	var vh = vic.hp
	await wait(1.0)
	check(abs((vh - vic.hp) - 5.0) < 0.3, "독 5중첩: 초당 피해 5 (실제 %.2f)" % (vh - vic.hp))
	vic.dead = true
	game.remove_unit(vic)
	var eb = game.spawn_building(1, "defense", Vector2(2800, 1700), true, false)
	eb.add_venom(p.venom_cap(), p.has("burn"))
	check(eb.venom_stacks == 0, "타오르는 독 없으면 건물에 독 없음")
	p.research["burn"] = true
	for i in 9:
		eb.add_venom(p.venom_cap(), p.has("burn"))
	check(eb.venom_stacks == 8, "타오르는 독: 건물에 독, 최대 8중첩")
	eb.take_damage(99999.0, null)
	p.research.erase("burn")

	# 끝없는 물결
	check(p.batch("stinger") == 2, "침병 기본 2기 한 조")
	p.research["wave"] = true
	check(p.batch("stinger") == 3 and p.batch("soldier") == 3 and p.batch("sprayer") == 1, "끝없는 물결: 침병·병정개미 3기 한 조")
	p.pop_used = 100.0
	check(abs(p.upkeep_mult() - 0.75) < 0.001, "끝없는 물결: 유지비 감소폭 1.25배 (80% → 75%)")
	p.research.erase("wave")

	# 경보 페로몬
	clear_units(game)
	p.research["alarm"] = true
	var a1 = game.spawn_unit(0, "stinger", Vector2(2000, 1700))
	var a2 = game.spawn_unit(0, "stinger", Vector2(2030, 1700))
	await wait(0.1)
	a2.take_damage(9999.0, null)
	check(a1.alarm_stacks == 1, "경보 페로몬: 아군이 죽으면 근처 아군 강화")
	await wait(Data.ALARM_TIME + 0.5)
	check(a1.alarm_stacks == 0, "경보 페로몬 5초 후 해제")
	clear_units(game)

	# 보모 개미
	var cb = null
	for b in game.buildings:
		if b.pid == 0 and b.kind == "combat":
			cb = b
	game.enqueue_unit(cb, "stinger")
	await wait(0.1)
	var pr0 = cb.queue[0]["progress"]
	var nurse = game.spawn_unit(0, "nurse", cb.position + Vector2(60, 0))
	var dying = game.spawn_unit(0, "stinger", cb.position + Vector2(80, 0))
	await wait(0.1)
	dying.take_damage(9999.0, null)
	check(cb.queue[0]["progress"] - pr0 >= Data.NURSE_REFUND, "보모 개미: 근처 침병이 죽으면 생산 진행 +2.5초")
	game.cancel_last(cb)
	nurse.dead = true
	game.remove_unit(nurse)

	# 다여왕 군체
	var sat = game.spawn_building(0, "nest", Vector2(800, 1600), true, false)
	p.research["multiqueen"] = true
	main.tier = 3
	main.take_damage(99999.0, null)
	await wait(0.1)
	check(sat.is_main and sat.tier == 3 and p.succession <= 0.0, "다여왕 군체: 즉시 계승, 등급 유지")

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
		check(not game.enqueue_unit(cb, "tyrant"), "폭군의 혈통 없이는 폭군 대병 생산 불가")
		p.research["tyrant_blood"] = true
		check(game.enqueue_unit(cb, "tyrant"), "주 둥지 III + 폭군의 혈통이면 폭군 대병 생산 가능")
		game.cancel_last(cb)
		p.research.erase("tyrant_blood")
	else:
		check(false, "전투 생산 건물 건설")

	await research_checks(game, main)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
