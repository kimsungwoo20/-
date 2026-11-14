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
	var hidden = game.spawn_unit(1, "soldier", far)
	hidden.stealthed = true
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
