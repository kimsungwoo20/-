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
		if not u.is_worker and not u.is_neutral:
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

	await map_checks(game)

func camp_of(game, kind):
	for ci in game.camps.size():
		for u in game.camps[ci]["units"]:
			if is_instance_valid(u) and not u.dead and u.kind == kind:
				return ci
	return -1

func map_checks(game):
	var p = game.players[0]
	clear_units(game)
	await wait(0.2)

	# 중립 생물은 먼저 공격하지 않고, 아군도 자동으로 공격하지 않는다
	var ci = camp_of(game, "grub")
	var c = game.camps[ci]
	var g1 = c["units"][0]
	var g2 = c["units"][1]
	var st = game.spawn_unit(0, "stinger", g1.position + Vector2(40, 0))
	await wait(3.0)
	check(st.hp == st.max_hp and g1.hp == g1.max_hp, "중립 생물과 아군은 서로 먼저 공격하지 않는다")
	# 공격하면 같은 무리가 함께 반격한다
	st.max_hp = 9999.0
	st.hp = 9999.0
	st.cmd_attack(g1)
	await wait(2.0)
	check(g2.target == st, "무리 하나를 공격하면 같은 무리가 반격한다")
	check(st.hp < st.max_hp, "중립 생물이 반격한다")
	# 처치하면 사체가 남는다
	var n_corpse = 0
	for n in game.res_nodes:
		if n.kind == "corpse":
			n_corpse += 1
	g1.take_damage(99999.0, st)
	g2.take_damage(99999.0, st)
	await wait(0.1)
	var corpses = game.res_nodes.filter(func(n): return n.kind == "corpse")
	check(corpses.size() == n_corpse + 2, "유충 2마리 처치 → 사체 2개")
	check(corpses.size() > 0 and abs(corpses[-1].amount - 300.0) < 0.1, "유충 사체 식량 300")
	st.dead = true
	game.remove_unit(st)
	# 사체 채집
	var cp = corpses[-1]
	var wk = game.spawn_unit(0, "worker", cp.position + Vector2(30, 0))
	wk.cmd_gather(cp)
	Engine.time_scale = 4.0
	await wait(2.0)
	Engine.time_scale = 1.0
	check(cp.amount < 300.0, "사체에서 식량을 캔다")
	wk.dead = true
	game.remove_unit(wk)
	# 무리 재생성
	Engine.time_scale = 16.0
	await wait(Data.NEUTRAL_RESPAWN / 16.0 + 1.0)
	Engine.time_scale = 1.0
	var alive = 0
	for u in game.camps[ci]["units"]:
		if is_instance_valid(u) and not u.dead:
			alive += 1
	check(alive == 2, "전멸한 무리는 %d초 뒤 다시 나타난다" % int(Data.NEUTRAL_RESPAWN))
	check(not is_instance_valid(cp) or cp.gone, "사체는 %d초 뒤 썩어 사라진다" % int(Data.CORPSE_DECAY))

	# 끌려 나온 중립 생물은 둥지로 돌아간다
	var sp = game.camps[camp_of(game, "spider")]["units"][0]
	var bait = game.spawn_unit(0, "stinger", sp.position + Vector2(20, 0))
	bait.max_hp = 99999.0
	bait.hp = 99999.0
	sp.take_damage(1.0, bait)
	bait.cmd_move(sp.home + Vector2(700, 0))
	Engine.time_scale = 4.0
	await wait(4.0)
	Engine.time_scale = 1.0
	check(sp.target == null and sp.position.distance_to(sp.home) < Data.LEASH + 40.0, "멀리 끌려 나온 중립 생물은 추격을 멈추고 돌아간다")
	bait.dead = true
	game.remove_unit(bait)

	# 진딧물 도살
	var aph = null
	for n in game.res_nodes:
		if n.kind == "aphid" and n.position.x > 2000:
			aph = n
			break
	# 일꾼이 놀고 있는 플레이어 1 로 재야 채집 수입이 섞이지 않는다
	var p1 = game.players[1]
	var f0 = p1.food
	var killer = game.spawn_unit(1, "soldier", aph.position + Vector2(40, 0))
	killer.cmd_attack(aph)
	Engine.time_scale = 8.0
	await wait(Data.APHID_HP / 4.0 / 8.0 + 2.0)
	Engine.time_scale = 1.0
	check(aph.dead and not aph.available(), "진딧물 군락을 공격해 도살할 수 있다")
	check(abs(p1.food - f0 - Data.APHID_SLAY_FOOD) < 0.1, "도살한 쪽이 식량 +%d" % int(Data.APHID_SLAY_FOOD))
	Engine.time_scale = 16.0
	await wait(Data.APHID_RESPAWN / 16.0 + 1.0)
	Engine.time_scale = 1.0
	check(not aph.dead and aph.available(), "도살된 군락은 %d초 뒤 다시 채집 가능" % int(Data.APHID_RESPAWN))
	killer.dead = true
	game.remove_unit(killer)

	# 은신과 감지
	clear_units(game)
	var far = Vector2(1600, 1600)
	# 그림자 척후는 늘 은신한다
	var hidden = game.spawn_unit(1, "shade", far)
	await wait(0.05)
	var hunter = game.spawn_unit(0, "stinger", far + Vector2(60, 0))
	hunter.cmd_amove(far + Vector2(-200, 0))
	await wait(1.5)
	check(hidden.hp == hidden.max_hp, "감지하지 못한 은신 유닛은 공격하지 않는다")
	await wait(0.2)
	game._update_fog()
	check(not hidden.visible, "감지하지 못한 은신 유닛은 화면에 보이지 않는다")
	var eye = game.spawn_unit(0, "scout", far + Vector2(0, -100))
	hunter.cmd_attack(hidden)
	await wait(2.0)
	check(hidden.hp < hidden.max_hp or hidden.dead, "날개 정찰병이 감지하면 은신 유닛을 공격할 수 있다")
	game._update_fog()
	check(hidden.dead or hidden.visible, "감지된 은신 유닛은 보인다")

	# 전장의 안개
	clear_units(game)
	await wait(0.2)
	var enemy = game.spawn_unit(1, "soldier", Vector2(2400, 1850))
	game._update_fog()
	check(not enemy.visible, "시야 밖의 적 유닛은 보이지 않는다")
	var looker = game.spawn_unit(0, "stinger", Vector2(2300, 1850))
	await wait(0.1)
	game._update_fog()
	check(enemy.visible, "시야 안의 적 유닛은 보인다")
	var eb = game.spawn_building(1, "lab", Vector2(2400, 1760), true, false)
	await wait(0.1)
	game._update_fog()
	check(eb.visible, "시야 안의 적 건물은 보인다")
	looker.dead = true
	game.remove_unit(looker)
	await wait(0.1)
	game._update_fog()
	check(not enemy.visible and eb.visible, "시야를 잃으면 적 유닛은 사라지고, 본 적 있는 건물은 남는다")
	check(game.fog.is_explored_at(Vector2(2400, 1850)) and not game.fog.is_visible_at(Vector2(2400, 1850)), "한 번 본 곳은 '본 적 있음' 상태가 된다")

	# 맵 중앙 사체 낙하
	var before = game.res_nodes.filter(func(n): return n.kind == "corpse").size()
	game.drop_t = Data.CENTER_DROP_EVERY - 0.5
	await wait(1.0)
	var after = game.res_nodes.filter(func(n): return n.kind == "corpse")
	check(after.size() == before + 1 and abs(after[-1].amount - Data.CENTER_DROP_AMOUNT) < 0.1, "%d초마다 맵 중앙에 큰 사체가 떨어진다" % int(Data.CENTER_DROP_EVERY))

	await terrain_checks(game)

# 유닛을 목표까지 보내며 지나간 지형을 기록한다. [도착 여부, 물 위를 지났는가, 걸린 시간(초)]
func travel(game, u, to, limit):
	u.cmd_move(to)
	var wet = false
	var t0 = game.elapsed
	while game.elapsed - t0 < limit:
		await physics_frame
		if game.terrain.kind_at(u.position) == 1:
			wet = true
		if u.position.distance_to(to) < 12.0:
			return [true, wet, game.elapsed - t0]
	return [false, wet, game.elapsed - t0]

func terrain_checks(game):
	var T = game.terrain
	var p = game.players[0]
	clear_units(game)
	await wait(0.1)
	var start = Vector2(420, 1000)

	# 지도 배치 검증
	var bad = 0
	for n in game.res_nodes:
		if n.kind != "corpse" and (T.kind_at(n.position) == 1 or T.kind_at(n.position) == 2 or not T.reachable(start, n.position, "ground")):
			bad += 1
	check(bad == 0, "모든 자원 지점이 땅 위에 있고 시작 위치에서 걸어서 닿는다")
	bad = 0
	for e in game.expansions:
		if not T.can_build(e, 40.0) or not T.reachable(start, e, "ground"):
			bad += 1
	check(bad == 0, "모든 확장 지점에 둥지를 지을 수 있고 걸어서 닿는다")
	bad = 0
	for c in game.camps:
		if not T.passable(c["pos"], "ground") or not T.reachable(start, c["pos"], "ground"):
			bad += 1
	check(bad == 0, "모든 중립 무리가 땅 위에 있고 걸어서 닿는다")
	check(T.reachable(start, Vector2(Data.MAP_SIZE.x - 420, 1000), "ground"), "두 시작 위치가 육로로 이어져 있다")

	# 호수(x 960~1120)를 사이에 둔 이동
	Engine.time_scale = 4.0
	var a = Vector2(900, 1000)
	var b = Vector2(1180, 1000)
	var g = game.spawn_unit(0, "stinger", a)
	var rg = await travel(game, g, b, 30.0)
	check(rg[0] and not rg[1], "지상 유닛은 호수를 돌아서 간다 (물에 들어가지 않음, %.1f초)" % rg[2])
	var s = game.spawn_unit(0, "scout", a)
	var rs = await travel(game, s, b, 30.0)
	check(rs[0] and rs[1], "공중 유닛은 호수 위를 곧장 건넌다 (%.1f초)" % rs[2])
	check(rs[2] < rg[2] * 0.6, "공중 유닛이 훨씬 빨리 도착한다")
	# 절벽(y 480~544)
	var g2 = game.spawn_unit(0, "stinger", Vector2(1230, 440))
	var rc = await travel(game, g2, Vector2(1230, 590), 30.0)
	check(rc[0], "지상 유닛은 절벽을 돌아서 반대편에 도착한다 (%.1f초)" % rc[2])
	check(rc[2] > 150.0 / g2.spd() * 1.5, "절벽을 넘지 못해 직선보다 오래 걸린다")
	Engine.time_scale = 1.0
	clear_units(game)

	# 물로 가라는 명령은 가장 가까운 땅으로 바뀐다
	var g3 = game.spawn_unit(0, "stinger", a)
	g3.cmd_move(Vector2(1040, 1000))
	check(T.passable(g3.dest, "ground"), "물 한가운데로 이동 명령을 내리면 가까운 물가로 간다")
	g3.dead = true
	game.remove_unit(g3)

	# 수목: 느려진다
	var ts = game.spawn_unit(0, "soldier", Vector2(1390, 800))
	ts.cmd_move(Vector2(1495, 800))
	await wait(0.2)
	var x0 = ts.position.x
	await wait(0.5)
	var v = (ts.position.x - x0) / 0.5
	check(abs(v - ts.spd() * Data.TREE_SPEED) < ts.spd() * 0.08, "수목 지대에서 지상 유닛 속도 %d%% (실제 %.0f / %.0f)" % [int(Data.TREE_SPEED * 100), v, ts.spd()])
	ts.dead = true
	game.remove_unit(ts)

	# 건설 제한
	check(not game.can_place("combat", Vector2(1040, 1000)), "물 위에는 건설 불가")
	check(not game.can_place("combat", Vector2(1200, 512)), "절벽 위에는 건설 불가")
	check(not game.can_place("combat", Vector2(1440, 800)), "수목 지대에는 건설 불가")
	check(game.can_place("combat", Vector2(1300, 1250)), "맨땅에는 건설 가능")

	# 뗏목단
	var sb = null
	for bb in game.buildings:
		if bb.pid == 0 and bb.kind == "special":
			sb = bb
	p.food = 9999.0
	p.mat = 9999.0
	var nest0 = game.main_nest(0)
	nest0.tier = 3
	p.research.erase("raft_form")
	check(sb != null and not game.enqueue_unit(sb, "raft"), "뗏목 진형 없이는 뗏목단 생산 불가")
	p.research["raft_form"] = true
	check(sb != null and game.enqueue_unit(sb, "raft"), "뗏목 진형 연구 후 뗏목단 생산 가능")
	game.cancel_last(sb)
	var raft = game.spawn_unit(0, "raft", Vector2(930, 1000))
	var riders = []
	for i in 4:
		var r = game.spawn_unit(0, "stinger", Vector2(900, 960 + i * 20))
		r.cmd_board(raft)
		riders.append(r)
	await wait(2.0)
	check(raft.cargo.size() == 4 and riders[0].carried and not riders[0].visible, "유닛이 뗏목단에 탑승한다")
	var walls = []
	for i in 4:
		var wl = game.spawn_unit(0, "wall", Vector2(900, 960 + i * 20))
		wl.cmd_board(raft)
		walls.append(wl)
	await wait(2.0)
	var left = walls.filter(func(x): return not x.carried)
	check(abs(raft.cargo_pop() - 8.0) < 0.01 and left.size() == 1, "탑승 한도는 인구 8 (침병 4기 2 + 방벽 개미 3기 6, 1기는 거절)")
	for x in left:
		x.dead = true
		game.remove_unit(x)
	raft.cmd_move(Vector2(1040, 1000))
	Engine.time_scale = 4.0
	await wait(1.5)
	Engine.time_scale = 1.0
	check(T.kind_at(raft.position) == 1, "뗏목단은 물 위로 이동한다")
	check(not raft.unload() and raft.cargo.size() == 7, "물 한가운데에서는 하선 불가")
	Engine.time_scale = 4.0
	var rr = await travel(game, raft, Vector2(1150, 1000), 20.0)
	Engine.time_scale = 1.0
	check(rr[0] and rr[1], "뗏목단이 호수를 건너 반대편에 도착한다")
	check(raft.unload() and raft.cargo.is_empty(), "땅 가까이에서 하선")
	await wait(0.1)
	var landed = 0
	for r in riders:
		if not r.carried and r.visible and T.passable(r.position, "ground") and r.position.x > 1120.0:
			landed += 1
	check(landed == 4, "내린 유닛은 호수 건너편 땅 위에 있다 (%d / 4)" % landed)
	# 뗏목단이 죽으면 탑승 유닛도 죽는다
	riders[0].cmd_board(raft)
	await wait(1.5)
	var n0 = game.units.size()
	raft.take_damage(99999.0, null)
	await wait(0.1)
	check(not game.units.has(raft) and not game.units.has(riders[0]) and game.units.size() == n0 - 2, "뗏목단이 죽으면 타고 있던 유닛도 죽는다")
	clear_units(game)

	await leaf_checks(game)

func hit_once(game, attacker, victim):
	# attacker 가 victim 을 처음 때린 피해량
	var h0 = victim.hp
	attacker.cmd_attack(victim)
	for i in 300:
		await physics_frame
		if victim.hp < h0:
			break
	attacker.cmd_stop()
	return h0 - victim.hp

func leaf_checks(game):
	var L = game.players[1]
	var F = game.players[0]
	clear_units(game)
	check(L.faction == "leaf" and F.faction == "fire", "점검 환경: 플레이어 0 불개미, 플레이어 1 잎꾼개미")
	var nest = game.main_nest(1)
	check(nest.d["name"] == "균류 대정원" and game.bdata(1, "combat")["name"] == "대턱 육성방", "잎꾼개미 건물 이름")
	check(game.bdata(0, "nest")["mat"] == 175 and game.bdata(1, "nest")["mat"] == 250, "위성 둥지 비용: 불개미 175(분봉 -30%), 잎꾼개미 250")
	F.pop_used = 100.0
	L.pop_used = 100.0
	check(abs(F.upkeep_mult() - 0.8) < 0.001 and abs(L.upkeep_mult() - 0.85) < 0.001, "인구 100 식량 수입: 불개미 80%, 잎꾼개미 85%(공통)")
	check(L.carry_amount("mat") - L.carry_amount("food") == 5.0 and F.carry_amount("mat") == F.carry_amount("food"), "잎꾼개미 일꾼은 재료를 5 더 나른다")
	check(game.research_state(game.buildings.filter(func(b): return b.pid == 0 and b.kind == "lab")[0], "high_yield") == "faction", "불개미는 잎꾼개미 연구를 할 수 없다")
	check(game.main_nest(0).garden_slots() == 0, "불개미 둥지에는 균류 정원이 없다")

	# 균류 정원
	nest.tier = 1
	check(nest.garden_slots() == 4, "정원사 슬롯: 주 둥지 I 에서 4")
	nest.tier = 2
	check(nest.garden_slots() == 8, "정원사 슬롯: 주 둥지 II 에서 8")
	var ws = []
	for u in game.units:
		if u.pid == 1 and u.is_worker and not u.carried:
			ws.append(u)
	ws[0].cmd_garden(nest)
	ws[1].cmd_garden(nest)
	Engine.time_scale = 4.0
	await wait(2.0)
	Engine.time_scale = 1.0
	check(nest.gardeners.size() == 2 and ws[0].carried and not ws[0].visible, "일꾼이 균류 정원에 들어간다")
	L.mat = 1000.0
	L.food = 0.0
	L.pop_used = 10.0
	var t0 = game.elapsed
	await wait(5.0)
	var dt = game.elapsed - t0
	check(abs((1000.0 - L.mat) - 0.75 * 2 * dt) < 0.3, "정원사 2기: 초당 재료 1.5 소모 (실제 %.2f)" % ((1000.0 - L.mat) / dt))
	check(abs(L.food - (1000.0 - L.mat) * 2.0) < 0.3, "재료 1 → 식량 2")
	L.research["high_yield"] = true
	var m1 = L.mat
	var f1 = L.food
	await wait(2.0)
	check(abs((L.food - f1) - (m1 - L.mat) * 2.5) < 0.3, "고수확 균주: 재료 1 → 식량 2.5")
	L.mat = 0.0
	f1 = L.food
	await wait(1.0)
	check(L.food == f1, "재료가 없으면 정원이 멈춘다")
	L.mat = 1000.0
	nest.hp = nest.max_hp * 0.4
	m1 = L.mat
	await wait(2.0)
	var used_damaged = m1 - L.mat
	check(abs(used_damaged - 0.75 * 2 * 0.5 * 2.0) < 0.15, "본진 체력 50% 미만이면 정원 효율 절반")
	L.research["antibiotic"] = true
	m1 = L.mat
	await wait(2.0)
	check(abs((m1 - L.mat) - 0.75 * 2 * 2.0) < 0.15, "항생 공생균: 본진이 손상돼도 정원 효율 유지")
	nest.hp = nest.max_hp
	nest.tier = 1
	L.research["big_garden"] = true
	check(nest.garden_slots() == 6, "거대 정원: 슬롯 +50% (4 → 6)")
	L.research.erase("big_garden")
	var out = nest.release_gardener()
	check(out != null and not out.carried and out.visible and nest.gardeners.size() == 1, "정원사를 밖으로 내보낸다")
	# 정원 안의 일꾼은 공격 목표가 될 수 없다
	var inside = nest.gardeners[0]
	var biter = game.spawn_unit(0, "stinger", nest.position + Vector2(50, 0))
	biter.cmd_attack(inside)
	await wait(1.0)

	check(inside.hp == inside.max_hp and biter.target != inside, "정원 안의 일꾼은 공격받지 않는다")
	biter.dead = true
	game.remove_unit(biter)
	# 위성 둥지가 무너지면 정원사도 죽는다
	var sat = game.spawn_building(1, "nest", Vector2(2700, 400), true, false)
	check(sat.garden_slots() == 2, "위성 둥지 정원사 슬롯 2")
	check(sat.add_gardener(ws[2]) and sat.add_gardener(ws[3]) and not sat.add_gardener(ws[4]), "슬롯이 차면 더 넣을 수 없다")
	sat.take_damage(99999.0, null)
	await wait(0.1)
	check(not game.units.has(ws[2]) and not game.units.has(ws[3]), "둥지가 무너지면 안의 정원사도 죽는다")

	# 유닛 능력
	clear_units(game)
	var tb = game.spawn_building(0, "defense", Vector2(2300, 1250), true, false)
	var cu = game.spawn_unit(1, "cutter", tb.position + Vector2(50, 0))
	var d0 = await hit_once(game, cu, tb)
	L.research["shear1"] = true
	var d1 = await hit_once(game, cu, tb)
	check(abs(d0 - 7.0) < 0.01 and abs(d1 - 10.5) < 0.01, "절단 턱: 건물에 50%% 추가 피해 (%.1f → %.1f)" % [d0, d1])
	L.research.erase("shear1")
	L.research["jaw1"] = true
	var d2 = await hit_once(game, cu, tb)
	check(abs(d2 - 7.0 * 1.15) < 0.01, "절단병은 큰턱 강화 효과 1.5배 (+15%%, 실제 %.2f)" % d2)
	L.research.erase("jaw1")
	cu.dead = true
	game.remove_unit(cu)
	var sm = game.spawn_unit(1, "supermajor", tb.position + Vector2(60, 0))
	var d3 = await hit_once(game, sm, tb)
	check(abs(d3 - 26.0 * Data.SIEGE_MULT) < 0.01, "초대형 병정: 건물에 2.5배 피해 (%.0f)" % d3)
	sm.dead = true
	game.remove_unit(sm)
	var mn = game.spawn_unit(1, "minim", Vector2(2300, 1500))
	# 상대가 반격해 소형개미가 죽지 않게 체력을 크게 둔다
	mn.max_hp = 9999.0
	mn.hp = 9999.0
	var fly = game.spawn_unit(0, "swarm", Vector2(2320, 1500))
	fly.max_hp = 999.0
	fly.hp = 999.0
	var d4 = await hit_once(game, mn, fly)
	check(abs(d4 - 4.5 * F.taken_mult()) < 0.01, "호위 소형개미는 공중 유닛을 물고 1.5배 피해 (%.1f)" % d4)
	var slow = game.spawn_unit(0, "soldier", Vector2(2300, 1530))
	slow.max_hp = 999.0
	slow.hp = 999.0
	var d5 = await hit_once(game, mn, slow)
	check(abs(d5 - 3.0 * F.taken_mult()) < 0.01, "느린 지상 유닛에게는 추가 피해 없음 (%.1f)" % d5)
	clear_units(game)
	await wait(0.1)
	# 공생균 살포병
	var hurt = game.spawn_unit(1, "major", Vector2(2300, 1800))
	hurt.hp = 100.0
	var med = game.spawn_unit(1, "medic", Vector2(2340, 1800))
	await wait(2.0)
	check(hurt.hp > 104.0, "공생균 살포병이 주변 아군을 회복 (%.1f → %.1f)" % [100.0, hurt.hp])
	tb.hp = 100.0
	var ab = game.spawn_building(1, "combat", Vector2(2420, 1800), true, false)
	ab.hp = 100.0
	await wait(2.0)
	check(ab.hp > 104.0, "항생 공생균: 건물도 회복")
	# 길잡이 소형개미
	var wk = game.spawn_unit(1, "worker", Vector2(2000, 1850))
	await wait(0.6)
	var v0 = wk.spd()
	var pf = game.spawn_unit(1, "pathfinder", Vector2(2040, 1850))
	await wait(0.6)
	check(abs(wk.spd() - v0 * 1.2) < 0.01, "길잡이 소형개미 근처 일꾼 이동 속도 +20%")
	# 탑승 호위
	var att = game.spawn_unit(0, "stinger", Vector2(2000, 1880))
	att.max_hp = 999.0
	att.hp = 999.0
	L.research["hitchhiker"] = true
	var wh = wk.hp
	wk.take_damage(10.0, att)
	check(abs((wh - wk.hp) - 7.0) < 0.01 and abs(att.hp - (999.0 - Data.HITCH_REFLECT * F.taken_mult())) < 0.01, "탑승 호위: 일꾼 피해 -30%, 공격한 적에게 반격")
	clear_units(game)
	# 포자 살포 날개개미
	var target_b = game.spawn_building(0, "lab", Vector2(2600, 1700), true, false)
	var sp = game.spawn_unit(1, "spore", Vector2(2600, 1630))
	sp.cmd_attack(target_b)
	await wait(4.0)
	check(game.spore_zones.size() > 0, "포자 살포 날개개미의 공격이 포자 지대를 만든다")
	var bh = target_b.hp
	sp.cmd_stop()
	await wait(1.0)
	check(target_b.hp < bh - 4.0, "포자 지대가 건물에 지속 피해")
	sp.dead = true
	game.remove_unit(sp)
	target_b.take_damage(99999.0, null)
	# 초대형 계급
	var cb = game.spawn_building(1, "combat", Vector2(2700, 1000), true, false)
	nest.tier = 3
	L.food = 5000.0
	L.mat = 5000.0
	check(not game.enqueue_unit(cb, "supermajor"), "초대형 계급 없이는 초대형 병정 생산 불가")
	L.research["supermajor_caste"] = true
	check(game.enqueue_unit(cb, "supermajor"), "초대형 계급 연구 후 생산 가능")
	game.cancel_last(cb)
	# 전쟁 균류
	var army = [game.spawn_unit(1, "cutter", Vector2(2700, 1200)), game.spawn_unit(1, "major", Vector2(2720, 1200))]
	check(not game.use_war_fungus(1), "전쟁 균류 없이는 포자 갑옷 불가")
	L.research["war_fungus"] = true
	var fw = L.food
	check(game.use_war_fungus(1) and L.food == fw - Data.WAR_FUNGUS_FOOD, "포자 갑옷: 식량 %d 소모" % Data.WAR_FUNGUS_FOOD)
	check(army[0].shield == Data.WAR_FUNGUS_SHIELD and army[1].shield == Data.WAR_FUNGUS_SHIELD, "전 병력에 포자 갑옷")
	var ah = army[0].hp
	army[0].take_damage(30.0, null)
	check(army[0].hp == ah and abs(army[0].shield - 10.0) < 0.01, "포자 갑옷이 피해를 먼저 흡수")
	check(not game.use_war_fungus(1), "재사용 대기 중에는 다시 쓸 수 없다")
	clear_units(game)

	await weaver_checks(game)

func weaver_checks(game):
	# 점검 환경의 플레이어 1 을 베짜기개미로 바꿔서 확인한다
	var W = game.players[1]
	var F = game.players[0]
	W.faction = "weaver"
	W.research.clear()
	W.food = 99999.0
	W.mat = 99999.0
	clear_units(game)
	var nest = game.main_nest(1)
	var np = nest.position
	await wait(0.5)
	check(game.has_territory(1) and not game.has_territory(0), "베짜기개미만 수관 영역을 쓴다")
	check(game.territory_state(1, np + Vector2(0, 100)) == 2 and game.territory_state(1, np + Vector2(0, 700)) == 0, "주 둥지 주변은 연결된 영역, 멀리는 영역 밖")
	check(game.territory_state(0, np) == -1, "다른 진영에는 영역 상태가 없다")

	# 건설 규칙
	var pa = np + Vector2(0, 220)
	check(game.can_place("combat", pa, 1), "영역 안에는 건설 가능")
	check(not game.can_place("combat", np + Vector2(0, 420), 1), "영역 밖에는 건설 불가")
	check(game.can_place("combat", np + Vector2(0, 420), 0), "다른 진영은 영역과 무관하게 건설")
	var A = game.spawn_building(1, "combat", pa, true, false)
	await wait(0.5)
	check(game.can_place("combat", np + Vector2(0, 420), 1), "건물을 지으면 영역이 넓어져 그 너머에 지을 수 있다")
	var tree = Vector2(2900, 1330)
	check(game.terrain.kind_at(tree) == 3 and game.can_place("lab", tree, 1) and not game.terrain.can_build(tree, 28.0), "베짜기개미는 수목 위에도 지을 수 있다")

	# 네트워크 연결과 절단
	var pb = np + Vector2(0, 600)
	var B = game.spawn_building(1, "combat", pb, true, false)
	await wait(0.5)
	check(B.net_ok and game.territory_state(1, pb + Vector2(0, 100)) == 2, "영역이 맞닿으면 주 둥지와 이어진다")
	game.enqueue_unit(B, "acid")
	await wait(0.2)
	var pr = B.queue[0]["progress"]
	var e0 = game.elapsed
	await wait(2.0)
	var rate_ok = (B.queue[0]["progress"] - pr) / (game.elapsed - e0)
	A.take_damage(99999.0, null)
	await wait(0.5)
	check(not B.net_ok and game.territory_state(1, pb + Vector2(0, 100)) == 1, "중간 고리가 파괴되면 그 너머는 끊어진 영역이 된다")
	pr = B.queue[0]["progress"]
	e0 = game.elapsed
	await wait(2.0)
	var rate_cut = (B.queue[0]["progress"] - pr) / (game.elapsed - e0)
	check(abs(rate_ok - 1.0) < 0.03 and abs(rate_cut - Data.TERR_CUT_PRODUCTION) < 0.03, "끊어진 구역의 건물은 생산 속도 70%% (%.2f → %.2f)" % [rate_ok, rate_cut])
	game.cancel_last(B)

	# 유닛 보너스
	var u_in = game.spawn_unit(1, "pinner", np + Vector2(0, 150))
	var u_cut = game.spawn_unit(1, "pinner", pb + Vector2(0, 100))
	var u_out = game.spawn_unit(1, "pinner", Vector2(2400, 300))
	u_in.hp = 50.0
	u_cut.hp = 50.0
	await wait(1.1)
	check(u_in.terr == 2 and u_cut.terr == 1 and u_out.terr == 0, "유닛의 영역 상태: 연결 / 끊어짐 / 밖")
	check(abs(u_in.spd() - 75.0 * Data.TERR_SPEED_IN) < 0.01 and abs(u_cut.spd() - 75.0) < 0.01 and abs(u_out.spd() - 75.0 * Data.TERR_SPEED_OUT) < 0.01, "이동 속도: 연결된 영역 +15%, 끊어진 영역 그대로, 영역 밖 -15%")
	check(u_in.hp > 50.5 and u_cut.hp == 50.0, "연결된 영역 안에서만 체력 회복")
	W.research["silk_road"] = true
	check(abs(u_in.spd() - 75.0 * Data.TERR_SPEED_SILK) < 0.01, "비단길: 연결된 영역 안 이동 속도 +60%")
	W.research.erase("silk_road")
	# 살아있는 사슬
	W.research["living_chain"] = true
	await wait(0.5)
	check(B.net_ok, "살아있는 사슬: 연결 가능 거리 +25% 로 다시 이어진다")
	var D = game.spawn_building(1, "combat", Vector2(2000, 400), true, false)
	await wait(0.5)
	check(D.net_ok and game.terr_lost.has(D.get_instance_id()), "살아있는 사슬: 끊어진 구역도 잠시 보너스 유지")
	Engine.time_scale = 8.0
	await wait(Data.CHAIN_GRACE / 8.0 + 1.0)
	Engine.time_scale = 1.0
	check(not D.net_ok, "30초가 지나면 끊어진 구역의 보너스가 사라진다")
	# 유충 운반공: 임시 고리와 수리
	W.research.erase("living_chain")
	await wait(0.5)
	check(not B.net_ok, "살아있는 사슬이 없으면 다시 끊어진다")
	var car = game.spawn_unit(1, "carrier", np + Vector2(0, 340))
	await wait(0.5)
	check(B.net_ok, "유충 운반공이 사이에 서면 끊어진 네트워크가 이어진다")
	check(not game.in_build_territory(1, np + Vector2(120, 400)) or game.territory_state(1, np + Vector2(120, 400)) >= 1, "유충 운반공의 임시 영역")
	B.hp = 100.0
	car.position = pb + Vector2(60, 0)
	await wait(1.2)
	check(B.hp > 102.0, "유충 운반공이 건물을 수리한다")
	clear_units(game)

	# 전투 유닛
	var base = Vector2(2300, 700)
	var ac = game.spawn_unit(1, "acid", base)
	var v1 = game.spawn_unit(0, "soldier", base + Vector2(90, 0))
	var v2 = game.spawn_unit(0, "soldier", base + Vector2(90, 16))
	for v in [v1, v2]:
		v.max_hp = 9999.0
		v.hp = 9999.0
	var d1 = await hit_once(game, ac, v1)
	check(abs(d1 - 8.0 * F.taken_mult()) < 0.01 and abs((9999.0 - v2.hp) - 4.0 * F.taken_mult()) < 0.01, "산성 분사병: 대상 8, 주변 적 절반 피해")
	W.research["acid_pool"] = true
	await hit_once(game, ac, v1)
	check(game.zones.size() > 0, "농축 개미산: 바닥에 산성 지대")
	W.research.erase("acid_pool")
	clear_units(game)
	await wait(0.1)
	var pl = game.spawn_unit(1, "puller", base)
	var far = game.spawn_unit(0, "soldier", base + Vector2(120, 0))
	far.max_hp = 9999.0
	far.hp = 9999.0
	pl.cmd_attack(far)
	await wait(0.3)
	check(far.position.distance_to(pl.position) < 30.0, "사슬 견인병이 떨어진 적을 자기 앞으로 끌어온다")
	clear_units(game)
	var pn = game.spawn_unit(1, "pinner", base)
	var runner = game.spawn_unit(0, "soldier", base + Vector2(18, 0))
	runner.max_hp = 9999.0
	runner.hp = 9999.0
	await hit_once(game, pn, runner)
	var rp = runner.position
	runner.cmd_move(base + Vector2(400, 0))
	await wait(0.8)
	check(runner.position.distance_to(rp) < 2.0, "고정병에게 물린 적은 움직이지 못한다")
	clear_units(game)
	# 비단 장막
	var cur = game.spawn_unit(1, "curtain", base)
	cur.toggle_root()
	var walker = game.spawn_unit(0, "soldier", base + Vector2(50, 0))
	var flyer = game.spawn_unit(0, "scout", base + Vector2(-50, 0))
	var friend = game.spawn_unit(1, "pinner", base + Vector2(0, 40))
	var outsider = game.spawn_unit(1, "pinner", base + Vector2(0, 300))
	var shooter = game.spawn_unit(0, "sprayer", base + Vector2(600, 600))
	await wait(1.2)
	check(abs(walker.slow - Data.CURTAIN_SLOW) < 0.01, "비단 장막 안의 적 지상 유닛은 이동 속도 40%")
	check(flyer.slow == 1.0, "영역 밖의 장막은 공중 유닛을 늦추지 못한다")
	var fh = friend.hp
	friend.take_damage(10.0, shooter)
	var oh = outsider.hp
	outsider.take_damage(10.0, shooter)
	check(abs((fh - friend.hp) - 7.0) < 0.01 and abs((oh - outsider.hp) - 10.0) < 0.01, "장막 안 아군은 원거리 피해 -30%")
	clear_units(game)
	var cur2 = game.spawn_unit(1, "curtain", np + Vector2(100, -150))
	cur2.toggle_root()
	var flyer2 = game.spawn_unit(0, "scout", np + Vector2(130, -150))
	await wait(1.2)
	check(abs(flyer2.slow - Data.CURTAIN_AIR_SLOW) < 0.01, "영역 안의 장막(공중 장막)은 공중 유닛도 늦춘다")
	clear_units(game)
	# 감시병, 수관 군주
	var se_in = game.spawn_unit(1, "sentinel", np + Vector2(0, -100))
	var se_out = game.spawn_unit(1, "sentinel", Vector2(2300, 300))
	await wait(0.6)
	check(abs(se_in.sight() - 260.0 * Data.SENTINEL_TERR_SIGHT) < 0.01 and se_out.sight() == 260.0, "감시병은 영역 안에서 시야가 넓어진다")
	var cb = game.spawn_building(1, "combat", np + Vector2(-200, 0), true, false)
	nest.tier = 3
	check(not game.enqueue_unit(cb, "lord"), "수관의 군주 없이는 수관 군주 생산 불가")
	W.research["canopy_lord"] = true
	check(game.enqueue_unit(cb, "lord"), "수관의 군주 연구 후 생산 가능")
	game.cancel_last(cb)
	var lord_pos = Vector2(2300, 300)
	var lord = game.spawn_unit(1, "lord", lord_pos)
	await wait(0.6)
	check(game.territory_state(1, lord_pos + Vector2(100, 0)) >= 1, "수관 군주 주변에 이동식 영역이 생긴다")
	check(not game.can_place("combat", lord_pos + Vector2(100, 0), 1), "수관 군주의 임시 영역에는 건물을 지을 수 없다")
	clear_units(game)
	# 분기 진화
	var hp0 = cb.max_hp
	W.research["fortress"] = true
	game.on_research_done(1, "fortress")
	check(abs(cb.max_hp - hp0 * Data.FORT_HP) < 0.01, "철옹성: 건물 체력 +30%")
	cb.hp = 100.0
	await wait(1.0)
	check(cb.hp > 102.0, "철옹성: 연결된 영역 안 건물 회복")
	W.research.erase("fortress")
	var tp = Vector2(2150, 150)
	check(game.start_build(1, "tent", tp, []) == null, "뻗어가는 수관 없이는 전진 둥지 건설 불가")
	W.research["spreading"] = true
	var tent = game.start_build(1, "tent", tp, [])
	check(tent != null, "뻗어가는 수관: 영역 밖에 전진 둥지 건설")
	if tent != null:
		tent.add_build(1000.0)
		await wait(0.5)
		check(game.in_build_territory(1, tp + Vector2(120, 0)), "전진 둥지가 작은 영역을 만든다")

	await trap_checks(game)

func dummy(game, pid, kind, pos):
	# 맞기만 하고 반격하지 않는 표적
	var u = game.spawn_unit(pid, kind, pos)
	u.max_hp = 9999.0
	u.hp = 9999.0
	u.can_fight = false
	return u

func trap_checks(game):
	# 플레이어 1 을 함정턱개미로 바꿔서 확인한다
	var T = game.players[1]
	var F = game.players[0]
	T.faction = "trap"
	T.research.clear()
	T.food = 99999.0
	T.mat = 99999.0
	clear_units(game)
	await wait(0.2)
	var base = Vector2(2300, 700)
	var fm = F.taken_mult()

	# 진영 규칙
	check(T.unit_food("worker") == 75 and F.unit_food("worker") == 50, "함정턱개미 일꾼은 식량 75")
	check(T.carry_amount("food") - F.carry_amount("food") == 5.0 - 2.0 * F.level("carry"), "함정턱개미 일꾼은 무엇이든 5 더 나른다")
	var tw = game.spawn_unit(1, "worker", base)
	check(tw.d["dmg"] == 6.0 and game.spawn_unit(0, "worker", base + Vector2(0, 300)).d["dmg"] == 3.0, "함정턱개미 일꾼 공격력 6 (다른 진영 3)")
	clear_units(game)
	for u in game.units.duplicate():
		if u.is_worker and u.position.distance_to(base) < 400.0:
			u.dead = true
			game.remove_unit(u)
	var hb = game.spawn_building(1, "combat", Vector2(2500, 1000), true, false)
	var hn = game.spawn_building(1, "nest", Vector2(2700, 1000), true, false)
	check(hb.stealthed and not hn.stealthed, "본진 외 건물은 은폐")
	var raider = dummy(game, 0, "stinger", hb.position + Vector2(-60, 0))
	raider.can_fight = true
	raider.cmd_amove(hb.position + Vector2(200, 0))
	await wait(2.0)
	check(hb.hp == hb.max_hp, "감지하지 못한 은폐 건물은 공격받지 않는다")
	game._update_fog()
	check(not hb.visible, "감지하지 못한 은폐 건물은 보이지 않는다")
	var eye = game.spawn_unit(0, "scout", hb.position + Vector2(0, -80))
	raider.cmd_attack(hb)
	await wait(2.0)
	check(hb.hp < hb.max_hp, "감지하면 은폐 건물을 공격할 수 있다")
	game._update_fog()
	check(hb.visible, "감지하면 은폐 건물이 보인다")
	clear_units(game)
	hb.take_damage(99999.0, null)
	hn.take_damage(99999.0, null)
	await wait(0.1)

	# 턱 타격
	var h = game.spawn_unit(1, "hunter", base)
	var v = dummy(game, 0, "soldier", base + Vector2(20, 0))
	var d1 = await hit_once(game, h, v)
	check(abs(d1 - 36.0 * fm) < 0.01, "충전된 첫 공격은 턱 타격 3배 (%.1f)" % d1)
	check(v.position.x - base.x > 20.0 + Data.SNAP_KNOCK * 0.8, "턱 타격은 적을 밀쳐낸다")
	var d2 = await hit_once(game, h, v)
	check(abs(d2 - 12.0 * fm) < 0.01, "바로 다음 공격은 보통 피해 (%.1f)" % d2)
	h.cmd_stop()
	h.can_fight = false      # 기다리는 동안 옆의 표적을 저절로 공격하지 않게
	await wait(Data.SNAP_CHARGE + 0.2)
	h.can_fight = true
	check(h.snap_ready(), "%d초 동안 공격하지 않으면 다시 충전" % int(Data.SNAP_CHARGE))
	T.research["power_snap"] = true
	var x0 = v.position.x
	await hit_once(game, h, v)
	check(v.stun_t > 0.0 and v.position.x - x0 > Data.SNAP_KNOCK * 1.5, "강화 격발: 밀쳐내기 2배, 기절")
	var sp = v.position
	v.cmd_move(sp + Vector2(200, 0))
	await wait(0.4)
	check(v.position.distance_to(sp) < 1.0, "기절한 적은 움직이지 못한다")
	T.research.erase("power_snap")
	clear_units(game)

	# 연쇄 격발
	T.research["chain_snap"] = true
	h = game.spawn_unit(1, "hunter", base)
	var weak = game.spawn_unit(0, "stinger", base + Vector2(16, 0))
	weak.can_fight = false
	weak.max_hp = 20.0
	weak.hp = 20.0
	h.cmd_attack(weak)
	await wait(0.6)
	check(not game.units.has(weak) and h.snap_ready() and h.chain_n == 1, "연쇄 격발: 턱 타격으로 처치하면 즉시 재충전")
	T.research.erase("chain_snap")
	clear_units(game)

	# 대왕 포식자
	var kg = game.spawn_unit(1, "king", base)
	var front = dummy(game, 0, "soldier", base + Vector2(28, 0))
	var behind = dummy(game, 0, "soldier", base + Vector2(70, 0))
	var side = dummy(game, 0, "soldier", base + Vector2(28, 80))
	await hit_once(game, kg, front)
	check(behind.hp < 9999.0 and side.hp == 9999.0, "대왕 포식자: 대상 뒤 직선 위의 적만 함께 맞는다")
	clear_units(game)

	# 도약 사냥꾼
	var lp = game.spawn_unit(1, "leaper", base)
	var lv = dummy(game, 0, "soldier", base + Vector2(20, 0))
	var lp0 = lp.position
	await hit_once(game, lp, lv)
	await wait(0.05)
	check(lp.position.distance_to(lp0) > Data.LEAP_DIST * 0.7 and lp.position.x < lp0.x, "도약 사냥꾼: 턱 타격 후 뒤로 뛰어 이탈")
	check(lp.leap_cd > Data.LEAP_CD - 1.0, "턱 도약 재사용 대기 %d초" % int(Data.LEAP_CD))
	var fly = dummy(game, 0, "swarm", lp.position + Vector2(20, 0))
	var fd = await hit_once(game, lp, fly)
	check(fd > 0.0, "도약 사냥꾼은 공중 유닛도 공격")
	clear_units(game)
	# 숙련: 절벽 넘기
	var cliff_n = Vector2(2000, 440)
	var lp2 = game.spawn_unit(1, "leaper", cliff_n)
	check(not lp2.leap_back(cliff_n + Vector2(0, -50)), "숙련 없이는 절벽 너머로 도약 불가")
	T.research["leap_master"] = true
	check(lp2.leap_back(cliff_n + Vector2(0, -50)) and lp2.position.y > 544.0 and lp2.leap_cd > Data.LEAP_CD_MASTER - 1.0, "턱 도약 숙련: 절벽을 넘고 재사용 대기 %d초" % int(Data.LEAP_CD_MASTER))
	T.research.erase("leap_master")
	clear_units(game)

	# 덫지기와 은신
	var tr = game.spawn_unit(1, "trapper", base)
	await wait(0.1)
	check(not tr.stealthed, "덫지기는 움직일 수 있을 때는 보인다")
	tr.toggle_root()
	await wait(0.1)
	check(tr.stealthed, "덫지기는 거점화하면 은신")
	var walker = dummy(game, 0, "soldier", base + Vector2(16, 0))
	var td = await hit_once(game, tr, walker)
	check(abs(td - 20.0 * fm) < 0.01, "덫지기: 은신 중 첫 타격 2배 (%.1f)" % td)
	check(not tr.stealthed, "공격하면 은신이 풀린다")
	walker.dead = true
	game.remove_unit(walker)
	await wait(Data.STEALTH_REVEAL + 0.3)
	check(tr.stealthed, "%d초 뒤 다시 은신" % int(Data.STEALTH_REVEAL))
	clear_units(game)
	var sh = game.spawn_unit(1, "shade", base)
	sh.cmd_move(base + Vector2(200, 0))
	await wait(0.3)
	check(sh.stealthed and sh.state == sh.MOVE, "그림자 척후는 움직여도 은신")
	check(sh.detect_range() > 0.0, "그림자 척후는 은신을 감지")
	clear_units(game)
	var hh = game.spawn_unit(1, "hunter", base)
	await wait(Data.STILL_TIME + 0.3)
	check(not hh.stealthed, "완전 매복 없이는 멈춰 있어도 보인다")
	T.research["full_ambush"] = true
	await wait(0.1)
	check(hh.stealthed, "완전 매복: 멈춰 있는 전투 유닛 은신")
	var av = dummy(game, 0, "soldier", base + Vector2(16, 0))
	var ad = await hit_once(game, hh, av)
	check(abs(ad - 12.0 * 3.0 * 1.5 * fm) < 0.01, "완전 매복: 은신 중 턱 타격 1.5배 (%.1f)" % ad)
	T.research.erase("full_ambush")
	clear_units(game)

	# 굴 수호자
	var nb = game.spawn_building(1, "lab", Vector2(2500, 1500), true, false)
	var gu_in = game.spawn_unit(1, "guardian", nb.position + Vector2(60, 0))
	var gu_out = game.spawn_unit(1, "guardian", Vector2(2100, 1500))
	await wait(0.6)
	check(gu_in.snap_charge() == Data.SNAP_CHARGE_GUARD and gu_out.snap_charge() == Data.SNAP_CHARGE, "굴 수호자: 아군 건물 근처에서 턱 타격 충전 %d초" % int(Data.SNAP_CHARGE_GUARD))
	clear_units(game)
	nb.take_damage(99999.0, null)

	# 유인병
	var lu = game.spawn_unit(1, "lure", base)
	var e1 = dummy(game, 0, "soldier", base + Vector2(120, 0))
	var e2 = dummy(game, 0, "soldier", base + Vector2(-100, 60))
	var e3 = dummy(game, 0, "soldier", base + Vector2(400, 0))
	for e in [e1, e2, e3]:
		e.can_fight = true
	await wait(0.05)
	check(game.use_lure(lu) == 2, "경보 페로몬: 반경 안의 적 2기만 끌린다")
	check(e1.target == lu and e2.target == lu and e3.target != lu, "끌린 적은 유인병을 공격한다")
	check(not game.use_lure(lu), "재사용 대기 중에는 다시 쓸 수 없다")
	lu.lure_cd = 0.0
	check(game.use_lure(lu) == 0, "한 번 끌린 적은 %d초 동안 면역" % int(Data.LURE_IMMUNE))
	clear_units(game)

	# 낙하 사냥꾼
	var dv = game.spawn_unit(1, "diver", base)
	var dt = dummy(game, 0, "soldier", base + Vector2(18, 0))
	var dd = await hit_once(game, dv, dt)
	check(abs(dd - 42.0 * fm) < 0.01 and not dv.air, "낙하 사냥꾼: 급강하 턱 타격 후 착지 (%.1f)" % dd)
	var mel = dummy(game, 0, "stinger", dv.position + Vector2(-14, 0))
	check(mel.can_hit(dv), "착지한 낙하 사냥꾼은 근접 공격을 받는다")
	dv.cmd_stop()
	mel.cmd_stop()
	await wait(Data.DIVE_GROUND_TIME + 0.3)
	check(dv.air and not mel.can_hit(dv), "%d초 뒤 다시 날아오른다" % int(Data.DIVE_GROUND_TIME))
	clear_units(game)

	# 분기 진화
	T.research["lone_hunter"] = true
	var solo = game.spawn_unit(1, "hunter", base)
	await wait(0.6)
	check(abs(solo.lone_mult - 1.3) < 0.001 and abs(solo.spd() - 90.0 * 1.3) < 0.01, "고독한 사냥꾼: 혼자면 공격력·속도 +30%")
	var b1 = game.spawn_unit(1, "hunter", base + Vector2(30, 0))
	var b2 = game.spawn_unit(1, "hunter", base + Vector2(0, 30))
	await wait(0.6)
	check(abs(solo.lone_mult - 1.1) < 0.001, "아군 2기가 곁에 있으면 +10%")
	T.research.erase("lone_hunter")
	clear_units(game)
	T.research["pack"] = true
	var packers = []
	var victims = []
	for i in 3:
		packers.append(game.spawn_unit(1, "hunter", base + Vector2(0, i * 40)))
		victims.append(dummy(game, 0, "soldier", base + Vector2(18, i * 40)))
	var bystander = dummy(game, 0, "soldier", base + Vector2(40, 100))
	for i in 3:
		packers[i].cmd_attack(victims[i])
	await wait(0.5)
	check(bystander.hp <= 9999.0 - Data.PACK_SHOCK_DMG * fm + 0.01, "사냥 무리: 3기가 동시에 턱 타격하면 충격파")
	T.research.erase("pack")
	clear_units(game)
	var kc = game.spawn_building(1, "combat", Vector2(2700, 1300), true, false)
	game.main_nest(1).tier = 3
	check(not game.enqueue_unit(kc, "king"), "포식자의 왕 없이는 대왕 포식자 생산 불가")
	T.research["king_unlock"] = true
	check(game.enqueue_unit(kc, "king"), "포식자의 왕 연구 후 생산 가능")
	game.cancel_last(kc)

	await army_checks(game)

func army_checks(game):
	# 플레이어 1 을 군대개미로 바꿔서 확인한다
	var A = game.players[1]
	var F = game.players[0]
	A.faction = "army"
	A.research.clear()
	A.food = 99999.0
	A.mat = 99999.0
	clear_units(game)
	for b in game.buildings.duplicate():
		if b.pid == 1 and not (b.kind == "nest" and b.is_main):
			b.dead = true
			game.remove_building(b)
	await wait(0.3)
	var fm = F.taken_mult()
	var mn = game.main_nest(1)
	var T = game.terrain

	# 살아있는 건축
	check(game.bdata(1, "combat")["mat"] == 90 and game.bdata(1, "nest")["mat"] == 150 and game.bdata(0, "combat")["mat"] == 150, "건물 재료 비용 -40% (전투 생산 90, 위성 둥지 150)")
	var pop0 = A.pop_used
	var X = game.start_build(1, "combat", Vector2(2500, 1300), [])
	check(X != null, "약탈대 대열 건설")
	X.add_build(1000.0)
	await wait(0.1)
	check(abs(A.pop_used - pop0 - 3.0) < 0.01, "건물 1동이 인구 3 차지")
	var cap = A.pop_cap
	var filler = game.spawn_unit(1, "raider", Vector2(2900, 300))
	filler.pop = cap - A.pop_used - 1.0
	await wait(0.1)
	check(game.start_build(1, "defense", Vector2(2500, 1500), []) == null, "인구가 모자라면 건물을 지을 수 없다")
	filler.dead = true
	game.remove_unit(filler)
	await wait(0.1)

	# 야영과 행군
	check(X.camped() and X.is_mobile() and not game.main_nest(0).is_mobile(), "군대개미 건물만 행군할 수 있다")
	game.enqueue_unit(X, "raider")
	await wait(0.2)
	var pr = X.queue[0]["progress"]
	var e0 = game.elapsed
	await wait(1.0)
	var rate_camp = (X.queue[0]["progress"] - pr) / (game.elapsed - e0)
	check(X.pack() and X.mode == "packing", "행군 준비 시작")
	Engine.time_scale = 4.0
	await wait(Data.PACK_TIME / 4.0 + 0.3)
	Engine.time_scale = 1.0
	check(X.mode == "march", "%d초 뒤 행군 상태" % int(Data.PACK_TIME))
	pr = X.queue[0]["progress"]
	e0 = game.elapsed
	await wait(1.0)
	var rate_march = (X.queue[0]["progress"] - pr) / (game.elapsed - e0)
	check(abs(rate_camp - 1.0) < 0.03 and abs(rate_march - Data.MARCH_PRODUCTION) < 0.03, "행군 중 유닛 생산 속도 50%% (%.2f → %.2f)" % [rate_camp, rate_march])
	game.cancel_last(X)
	var x0 = X.position
	check(X.march_to(x0 + Vector2(0, 150)), "행군 이동 명령")
	e0 = game.elapsed
	await wait(2.0)
	var v = X.position.distance_to(x0) / (game.elapsed - e0)
	check(abs(v - Data.MARCH_SPEED) < 2.0, "행군 속도 %d (실제 %.1f)" % [int(Data.MARCH_SPEED), v])
	var hp0 = X.hp
	X.take_damage(100.0, null)
	check(abs((hp0 - X.hp) - 125.0) < 0.01, "행군 중인 건물은 피해를 25% 더 받는다")
	A.research["great_march"] = true
	x0 = X.position
	e0 = game.elapsed
	await wait(1.0)
	v = X.position.distance_to(x0) / (game.elapsed - e0)
	check(abs(v - Data.MARCH_SPEED_GREAT) < 2.0, "대행군: 행군 속도 %d (실제 %.1f)" % [int(Data.MARCH_SPEED_GREAT), v])
	A.research.erase("great_march")
	# 야영할 수 없는 자리
	X.position = Vector2(2900, 1340)      # 수목 위
	X.march_dest = null
	check(not X.unpack() and X.mode == "march", "수목 위에는 야영할 수 없다")
	X.position = Vector2(2500, 1300)
	check(X.unpack() and X.mode == "unpacking", "맨땅에서는 야영 준비 시작")
	Engine.time_scale = 4.0
	await wait(Data.UNPACK_TIME / 4.0 + 0.3)
	Engine.time_scale = 1.0
	check(X.camped(), "%d초 뒤 야영 상태" % int(Data.UNPACK_TIME))

	# 주 둥지 행군: 일꾼 생산·반납 정지, 군체 대형 이동
	var wk = game.spawn_unit(1, "worker", mn.position + Vector2(80, 0))
	await wait(0.1)
	check(game.nearest_nest(1, wk.position) == mn, "야영 중인 둥지는 반납 지점")
	game.pack_colony(1, true)
	Engine.time_scale = 4.0
	await wait(Data.PACK_TIME / 4.0 + 0.3)
	Engine.time_scale = 1.0
	check(mn.mode == "march" and X.mode == "march", "군체 전체 행군")
	check(game.nearest_nest(1, wk.position) == null, "행군 중인 둥지에는 자원을 반납할 수 없다")
	var porter = game.spawn_unit(1, "porter", wk.position + Vector2(40, 0))
	await wait(0.1)
	check(game.nearest_nest(1, wk.position) == porter, "운반병은 이동식 반납 지점")
	wk.carry = 10.0
	wk.carry_res = "food"
	wk.state = wk.RETURN
	var f0 = A.food
	await wait(1.5)
	check(wk.carry == 0.0 and A.food >= f0 + 10.0, "일꾼이 운반병에게 자원을 반납한다")
	game.enqueue_unit(mn, "worker")
	await wait(1.0)
	check(mn.queue[0]["progress"] == 0.0, "행군 중에는 일꾼 생산 정지")
	A.research["eternal_wander"] = true
	await wait(1.0)
	check(mn.queue[0]["progress"] > 0.0, "영원한 유랑: 행군 중에도 일꾼 생산")
	check(mn.pack_time() == Data.PACK_TIME_WANDER and mn.unpack_time() == Data.UNPACK_TIME_WANDER, "영원한 유랑: 전환 %d초 / %d초" % [int(Data.PACK_TIME_WANDER), int(Data.UNPACK_TIME_WANDER)])
	A.research.erase("eternal_wander")
	game.cancel_last(mn)
	var off = X.position - mn.position
	game.order_march(mn, mn.position + Vector2(-100, 0))
	await wait(0.1)
	check(X.march_dest != null and X.march_dest.distance_to(mn.march_dest + off) < 40.0, "주 둥지를 움직이면 다른 건물도 대형을 유지하며 따라온다")
	var foe = dummy(game, 0, "stinger", mn.position + Vector2(100, 0))
	foe.can_fight = false
	await wait(1.5)
	check(foe.hp == 9999.0, "행군 중인 둥지는 수비 공격을 하지 않는다")
	mn.march_dest = null
	X.march_dest = null
	game.pack_colony(1, false)
	Engine.time_scale = 4.0
	await wait(Data.UNPACK_TIME / 4.0 + 0.5)
	Engine.time_scale = 1.0
	check(mn.camped() and X.camped(), "군체 전체 야영")
	A.research["statary_brood"] = true
	check(mn.pack_time() == Data.PACK_TIME_STATARY, "정주기 산란: 행군 전환 %d초" % int(Data.PACK_TIME_STATARY))
	game.enqueue_unit(X, "raider")
	await wait(0.2)
	X.camp_t = Data.STATARY_AFTER + 1.0
	pr = X.queue[0]["progress"]
	e0 = game.elapsed
	await wait(1.0)
	check(abs((X.queue[0]["progress"] - pr) / (game.elapsed - e0) - Data.STATARY_SPEED) < 0.04, "정주기 산란: 야영 60초 뒤 생산 속도 1.5배")
	game.cancel_last(X)
	A.research.erase("statary_brood")
	clear_units(game)

	# 약탈
	var spot = Vector2(2300, 700)
	var rd = game.spawn_unit(1, "raider", spot)
	var prey = game.spawn_unit(0, "worker", spot + Vector2(14, 0))
	f0 = A.food
	prey.take_damage(9999.0, rd)
	check(abs(A.food - f0 - 10.0) < 0.01, "적 일꾼 처치: 식량 +10 (비용의 20%)")
	var loot_b = game.spawn_building(0, "combat", spot + Vector2(0, 200), true, false)
	f0 = A.food
	var m0 = A.mat
	loot_b.take_damage(99999.0, rd)
	check(abs(A.food - f0 - 30.0) < 0.01 and abs(A.mat - m0 - 30.0) < 0.01, "적 건물 파괴: 식량 +30, 재료 +30")
	var soldier = game.spawn_unit(0, "soldier", spot + Vector2(14, 0))
	f0 = A.food
	soldier.take_damage(9999.0, rd)
	check(A.food == f0, "전투 유닛 처치는 약탈 없음")
	A.research["loot_instinct"] = true
	soldier = game.spawn_unit(0, "soldier", spot + Vector2(14, 0))
	f0 = A.food
	soldier.take_damage(9999.0, rd)
	check(abs(A.food - f0 - 3.0) < 0.01, "약탈 본능: 전투 유닛 처치 시 비용의 10% (병정개미 1기 = 3)")
	prey = game.spawn_unit(0, "worker", spot + Vector2(14, 0))
	f0 = A.food
	prey.take_damage(9999.0, rd)
	check(abs(A.food - f0 - 17.5) < 0.01, "약탈 본능: 일꾼 약탈 35%")
	A.research.erase("loot_instinct")
	var fire_killer = game.spawn_unit(0, "stinger", spot + Vector2(0, 40))
	var my_worker = game.spawn_unit(1, "worker", spot + Vector2(14, 40))
	f0 = F.food
	my_worker.take_damage(9999.0, fire_killer)
	check(F.food == f0, "다른 진영은 약탈하지 못한다")
	clear_units(game)

	# 포식: 진딧물은 도살만
	var aph = null
	for n in game.res_nodes:
		if n.kind == "aphid" and n.attackable() and n.position.x > 2000:
			aph = n
			break
	var aw = game.spawn_unit(1, "worker", aph.position + Vector2(40, 0))
	aw.cmd_gather(aph)
	check(aw.state == aw.ATTACK and aw.target == aph, "군대개미 일꾼은 진딧물을 채집하지 않고 도살한다")
	var nn = game.nearest_node(aw.position, "food", aw)
	check(nn == null or nn.kind != "aphid", "가장 가까운 식량 지점 탐색에서 진딧물 제외")
	check(aw.fac.get("corpse_harvest", 1.0) == 0.6, "사체 채집 시간 60%")
	clear_units(game)

	# 시야, 공중 전용 공격
	var r2 = game.spawn_unit(1, "raider", spot)
	var vg = game.spawn_unit(1, "vanguard", spot)
	check(abs(r2.sight() - Data.SIGHT_UNIT * 0.7) < 0.01 and vg.sight() == 300.0, "군대개미는 시야가 좁고 선발 정찰병만 넓다")
	clear_units(game)
	var dr = game.spawn_unit(1, "drone", spot)
	var gtarget = dummy(game, 0, "soldier", spot + Vector2(20, 0))
	var atarget = dummy(game, 0, "swarm", spot + Vector2(-20, 0))
	await wait(2.0)
	check(gtarget.hp == 9999.0 and atarget.hp < 9999.0, "날개 수개미는 공중 유닛만 공격한다")
	clear_units(game)

	# 수호병
	var wd = game.spawn_unit(1, "warden", X.position + Vector2(80, 0))
	await wait(0.6)
	var wh = wd.hp
	wd.take_damage(10.0, null)
	check(abs((wh - wd.hp) - 10.0) < 0.01, "야영 중인 건물 옆에서는 수호병 보너스 없음")
	X.mode = "march"
	await wait(0.6)
	wh = wd.hp
	wd.take_damage(10.0, null)
	check(abs((wh - wd.hp) - 7.0) < 0.01, "행군 중인 건물 근처의 수호병은 피해 -30%")
	X.mode = "camp"
	clear_units(game)

	# 다리 개미: 절벽(x 1792~2144, y 480~544)을 잇는다
	var north = Vector2(2000, 450)
	var south = Vector2(2000, 580)
	var mid = Vector2(2000, 512)
	check(not T.passable(mid, "ground"), "절벽은 지상 유닛이 못 지나간다")
	var br = game.spawn_unit(1, "bridge", Vector2(2000, 464))
	br.toggle_root()
	check(T.passable(mid, "ground") and T.kind_at(mid) == 2, "거점화한 다리 개미 주변 절벽을 건널 수 있다")
	var walker = game.spawn_unit(1, "raider", north)
	Engine.time_scale = 4.0
	var res = await travel(game, walker, south, 8.0)
	Engine.time_scale = 1.0
	check(res[0] and res[2] < 3.0, "지상 유닛이 다리를 건너 절벽 반대편에 도착 (%.1f초)" % res[2])
	var sky = dummy(game, 0, "swarm", br.position + Vector2(60, 0))
	var grd = dummy(game, 0, "soldier", br.position + Vector2(60, -30))
	await wait(2.0)
	check(sky.hp < 9999.0 and grd.hp == 9999.0, "살아있는 탑: 거점화한 다리 개미가 가까운 공중 유닛을 공격")
	sky.dead = true
	game.remove_unit(sky)
	grd.dead = true
	game.remove_unit(grd)
	walker.position = mid
	br.toggle_root()
	check(not T.passable(mid, "ground"), "거점화를 풀면 다리가 사라진다")
	await wait(0.7)
	check(T.passable(walker.position, "ground"), "다리 위에 있던 유닛은 가까운 땅으로 옮겨진다")
	A.research["living_bridge"] = true
	br.toggle_root()
	check(br.bridge_r == Data.BRIDGE_RADIUS_LIVING, "살아있는 다리: 다리 범위 확대")
	walker.position = mid
	check(abs(walker.spd() - 125.0 * Data.BRIDGE_SPEED) < 0.01, "살아있는 다리: 다리 위 이동 속도 +30%")
	br.take_damage(99999.0, null)
	await wait(0.1)
	check(not T.passable(mid, "ground"), "다리 개미가 죽으면 다리도 사라진다")
	A.research.erase("living_bridge")
	clear_units(game)

	# 포식 대군, 갈고리 턱
	mn.tier = 3
	check(not game.enqueue_unit(X, "horde"), "포식의 물결 없이는 포식 대군 생산 불가")
	A.research["predator_wave"] = true
	check(game.enqueue_unit(X, "horde"), "포식의 물결 연구 후 생산 가능")
	game.cancel_last(X)
	var hd = game.spawn_unit(1, "horde", spot)
	var t1 = dummy(game, 0, "soldier", spot + Vector2(26, 0))
	var t2 = dummy(game, 0, "soldier", spot + Vector2(26, 20))
	var hd1 = await hit_once(game, hd, t1)
	check(abs(hd1 - 20.0 * fm) < 0.01 and abs((9999.0 - t2.hp) - 20.0 * fm) < 0.01, "포식 대군: 주변 적에게도 같은 피해")
	hd.hp = 300.0
	t1.hp = 5.0
	await hit_once(game, hd, t2)
	await wait(0.1)
	check(hd.hp >= 300.0 + 700.0 * Data.FEAST_HEAL - 1.0, "포식 대군: 처치하면 체력 회복 (%.0f)" % hd.hp)
	clear_units(game)
	A.research["hook_jaw"] = true
	var hk = game.spawn_unit(1, "raider", spot)
	var slowed = dummy(game, 0, "soldier", spot + Vector2(14, 0))
	var sp0 = slowed.spd()
	await hit_once(game, hk, slowed)
	check(abs(slowed.spd() - sp0 * Data.HOOK_SLOW) < 0.01, "갈고리 턱: 맞은 적 이동 속도 -30%")
	clear_units(game)

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
