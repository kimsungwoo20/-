extends RefCounted
# 단순 규칙 기반 인공지능. 사람과 같은 규칙으로 플레이한다(단, 아직 전장의 안개를 무시한다).
# 진영별 차이는 PLANS 의 유닛·연구 목록으로만 둔다. 진영별 운영은 10단계에서 다듬는다.
const Data = preload("res://scripts/data.gd")
const UnitScript = preload("res://scripts/unit.gd")

var game
var pid = 0
var t = 0.0
var wave_size = 8          # 공격을 시작하는 병력 인구
var attacking = false
var defend_pos = Vector2.ZERO
var defend_t = 0.0
var branch_pick = ""
var plan = {}
# t1/t2/t3: 전투 생산 건물 유닛, def: 방어 생산 건물 유닛, air: 특수 생산 건물 유닛
# research 의 "branch" 자리에서 분기 진화(둘 중 무작위)를 고른다
const PLANS = {
	"fire": {"t1": "stinger", "t2": "sprayer", "t3": "tyrant", "def": "soldier", "air": "swarm",
		"branches": ["wave", "burn"],
		"research": ["carry1", "jaw1", "shell1", "spawn1", "colony1", "multiqueen", "alarm", "jaw2",
			"venom1", "shell2", "carry2", "nursery1", "colony2", "gland1", "size1", "tyrant_blood", "branch",
			"jaw3", "shell3", "troph1", "legs1", "size2", "nursery2", "gland2", "troph2", "flight1", "spawn2", "gland3"]},
	"leaf": {"t1": "cutter", "t2": "major", "t3": "supermajor", "def": "minim", "air": "spore",
		"branches": ["big_garden", "war_fungus"],
		"research": ["high_yield", "carry1", "jaw1", "shell1", "hitchhiker", "colony1", "spawn1", "jaw2",
			"shear1", "shell2", "antibiotic", "carry2", "nursery1", "colony2", "size1", "supermajor_caste", "branch",
			"jaw3", "shell3", "troph1", "legs1", "size2", "nursery2", "troph2", "flight1", "spawn2"]},
	"trap": {"t1": "hunter", "t2": "leaper", "t3": "king", "def": "guardian", "air": "diver",
		"branches": ["lone_hunter", "pack"], "max_workers": 20,
		"research": ["carry1", "jaw1", "shell1", "chain_snap", "colony1", "full_ambush", "jaw2", "power_snap",
			"shell2", "leap_master", "carry2", "nursery1", "size1", "king_unlock", "branch", "jaw3", "shell3",
			"size2", "legs1", "nursery2", "flight1", "spawn1", "colony2"]},
	"weaver": {"t1": "acid", "t2": "puller", "t3": "lord", "def": "pinner", "air": "airsentry",
		"branches": ["fortress", "spreading"],
		"research": ["carry1", "gland1", "shell1", "silk_road", "colony1", "spawn1", "living_chain", "gland2",
			"acid_pool", "shell2", "acid_sat", "carry2", "nursery1", "colony2", "size1", "canopy_lord", "branch",
			"gland3", "shell3", "jaw1", "troph1", "size2", "nursery2", "troph2", "flight1", "spawn2"]},
}

func setup(g, id):
	game = g
	pid = id
	plan = PLANS[game.players[id].faction]
	branch_pick = plan["branches"][randi() % 2]

func on_attacked(b):
	defend_pos = b.position
	defend_t = 6.0

func tick(delta):
	t += delta
	defend_t -= delta
	if t < 1.0:
		return
	t = 0.0
	var p = game.players[pid]
	if not p.alive:
		return
	var main = game.main_nest(pid)
	if main == null:
		return
	var workers = []
	var army = []
	for u in game.units:
		if u.pid == pid:
			if u.is_worker:
				if not u.carried:
					workers.append(u)
			elif u.can_fight:
				army.append(u)
	var nests = []
	var combats = []
	var defenses = []
	var lab = null
	var specials = []
	var unbuilt = []
	for b in game.buildings:
		if b.pid != pid:
			continue
		if not b.built:
			unbuilt.append(b)
			continue
		match b.kind:
			"nest":
				nests.append(b)
			"combat":
				combats.append(b)
			"defense":
				defenses.append(b)
			"lab":
				lab = b
			"special":
				specials.append(b)

	_assign_workers(workers)

	# 일꾼 생산
	var queued = 0
	for n in nests:
		queued += n.queue.size()
	var want = min(14 + 6 * (nests.size() - 1), plan.get("max_workers", 40))
	for n in nests:
		if workers.size() + queued < want and n.queue.is_empty():
			if game.enqueue_unit(n, "worker"):
				queued += 1

	# 짓다 만 건물에 일꾼 붙이기
	for b in unbuilt:
		var has_builder = false
		for w in workers:
			if w.build_target == b:
				has_builder = true
		if not has_builder and workers.size() > 0:
			_nearest(workers, b.position).cmd_build(b)

	# 건설 순서
	var e = game.elapsed
	var n_combat = game.count_buildings(pid, "combat")
	var n_def = game.count_buildings(pid, "defense")
	var n_nest = game.count_buildings(pid, "nest")
	var n_lab = game.count_buildings(pid, "lab")
	if unbuilt.is_empty() and workers.size() > 0:
		if n_combat == 0:
			_build("combat", main.position, workers)
		elif n_nest < 2 and e > 150.0:
			_expand(main, workers)
		elif n_def == 0 and e > 200.0:
			_build("defense", main.position, workers)
		elif n_lab == 0 and e > 260.0:
			_build("lab", main.position, workers)
		elif main.tier < 2 and e > 320.0:
			game.start_upgrade(main)
		elif n_combat < 2 and e > 380.0:
			_build("combat", main.position, workers)
		elif main.tier >= 2 and game.count_buildings(pid, "special") == 0 and e > 420.0:
			_build("special", main.position, workers)
		elif n_nest < 3 and e > 480.0:
			_expand(main, workers)
		elif n_combat < 3 and e > 600.0 and p.food > 400.0:
			_build("combat", main.position, workers)
		elif main.tier < 3 and e > 700.0:
			game.start_upgrade(main)
		elif n_combat < 6 and p.food > 600.0:
			# 식량이 남아돌면 생산 건물을 늘려 소비한다
			_build("combat", main.position, workers)

	# 연구: 우선순위 목록에서 지금 예약할 수 있는 첫 연구
	if lab != null and lab.queue.size() < 2:
		for id in plan["research"]:
			if id == "branch":
				id = branch_pick
			var r = Data.RESEARCH[id]
			if game.research_state(lab, id) == "ok":
				if p.can_afford(r["food"], r["mat"] + 100):
					game.enqueue_research(lab, id)
				break

	# 병력 생산
	var t3 = Data.UNITS[plan["t3"]]
	for b in combats:
		if b.queue.size() < 2:
			if main.tier >= 3 and p.has(t3["needs"]) and p.mat >= t3["mat"] + 50 and p.food >= t3["food"] + 50 and randf() < 0.3:
				game.enqueue_unit(b, plan["t3"])
			elif main.tier >= 2 and p.mat >= 80.0 and randf() < 0.4:
				game.enqueue_unit(b, plan["t2"])
			elif p.food >= Data.UNITS[plan["t1"]]["food"]:
				game.enqueue_unit(b, plan["t1"])
	for b in specials:
		if b.queue.is_empty() and p.mat >= 150.0 and p.food >= 150.0:
			game.enqueue_unit(b, plan["air"])
	for b in defenses:
		if b.queue.is_empty() and p.food >= 160.0:
			game.enqueue_unit(b, plan["def"])

	_tend_garden(nests, workers, p)
	if attacking and p.has("war_fungus") and p.war_cd <= 0.0 and p.food > 500.0:
		game.use_war_fungus(pid)

	_command_army(army, main)

# 잎꾼개미: 재료가 넉넉하면 정원사를 늘리고, 바닥나면 줄인다
func _tend_garden(nests, workers, p):
	for n in nests:
		var slots = n.garden_slots()
		if slots == 0:
			continue
		var want = min(slots, int(workers.size() / 3))
		if p.mat < 30.0 and n.gardeners.size() > 0:
			n.release_gardener()
		elif p.mat > 120.0 and n.gardeners.size() < want:
			var going = 0
			for w in workers:
				if w.state == UnitScript.GARDEN:
					going += 1
			if going == 0:
				var free = workers.filter(func(w): return not w.carried and w.state != UnitScript.BUILD)
				if free.size() > 0:
					_nearest(free, n.position).cmd_garden(n)

func _assign_workers(workers):
	var n_mat = 0
	var idle = []
	for w in workers:
		if w.state == UnitScript.IDLE:
			idle.append(w)
		elif w.last_res == "mat" and (w.state == UnitScript.GATHER or w.state == UnitScript.RETURN):
			n_mat += 1
	var want_mat = int(ceil(workers.size() * 0.35))
	for w in idle:
		var res = "food"
		if n_mat < want_mat:
			res = "mat"
		var n = game.nearest_node(w.position, res, w)
		if n == null:
			if res == "food":
				n = game.nearest_node(w.position, "mat", w)
			else:
				n = game.nearest_node(w.position, "food", w)
		if n != null:
			w.cmd_gather(n)
			if n.res_type() == "mat":
				n_mat += 1

func _nearest(arr, pos):
	var best = arr[0]
	for x in arr:
		if x.position.distance_squared_to(pos) < best.position.distance_squared_to(pos):
			best = x
	return best

func _find_spot(kind, center):
	for r in [130.0, 180.0, 240.0, 300.0]:
		for k in 10:
			var pos = center + Vector2(r, 0).rotated(k * TAU / 10.0 + r)
			if game.can_place(kind, pos, pid):
				return pos
	return null

func _build(kind, center, workers):
	if game.players[pid].mat < game.bdata(pid, kind)["mat"]:
		return
	var pos = _find_spot(kind, center)
	if pos == null:
		return
	game.start_build(pid, kind, pos, [_nearest(workers, pos)])

func _expand(main, workers):
	if game.players[pid].mat < game.bdata(pid, "nest")["mat"]:
		return
	var best = null
	var bd = 1e12
	for e in game.expansions:
		var taken = false
		for b in game.buildings:
			if b.kind == "nest" and b.position.distance_to(e) < 250.0:
				taken = true
		if taken:
			continue
		var dd = e.distance_to(main.position)
		if dd < bd:
			bd = dd
			best = e
	if best == null:
		return
	# 베짜기개미는 영역이 닿아야 지을 수 있으므로, 닿지 않으면 그쪽으로 초소를 하나 이어 붙인다
	if game.has_territory(pid) and not game.in_build_territory(pid, best):
		_weaver_step(best, workers)
		return
	var pos = best
	if not game.can_place("nest", pos, pid):
		pos = _find_spot("nest", best)
	if pos != null:
		game.start_build(pid, "nest", pos, [_nearest(workers, pos)])

func _weaver_step(goal, workers):
	if game.players[pid].mat < game.bdata(pid, "defense")["mat"]:
		return
	var node = null
	for n in game.terr_nodes.get(pid, []):
		if n["build"] and (node == null or n["pos"].distance_to(goal) < node["pos"].distance_to(goal)):
			node = n
	if node == null:
		return
	var dir = (goal - node["pos"]).normalized()
	for back in [0.93, 0.8, 0.65]:
		for ang in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9]:
			var pos = node["pos"] + dir.rotated(ang) * node["r"] * back
			if game.can_place("defense", pos, pid):
				game.start_build(pid, "defense", pos, [_nearest(workers, pos)])
				return

func _command_army(army, main):
	if army.is_empty():
		attacking = false
		return
	if defend_t > 0.0:
		for u in army:
			if u.state == UnitScript.IDLE or u.state == UnitScript.MOVE:
				u.cmd_amove(defend_pos)
		return
	var army_pop = 0.0
	for u in army:
		army_pop += u.pop
	if not attacking and army_pop >= wave_size:
		attacking = true
	if attacking and army.size() < 4:
		attacking = false
		wave_size = min(wave_size + 5, 50)
	if attacking:
		var tgt = null
		var bd = 1e12
		for b in game.buildings:
			# 감지하지 못한 은폐 건물은 공격 목표로 삼지 않는다
			if b.pid != pid and not b.dead and not (b.stealthed and not game.is_detected(b, pid)):
				var dd = b.position.distance_squared_to(main.position)
				if dd < bd:
					bd = dd
					tgt = b
		if tgt != null:
			for u in army:
				if u.state == UnitScript.IDLE:
					u.cmd_amove(tgt.position)
	else:
		# 쉬는 병력이 충분하면 가까운 유충·거미 무리를 사냥해 사체(식량)를 얻는다
		if army.size() >= 6:
			var prey = _nearest_prey(main.position)
			if prey != null:
				for u in army:
					if u.state == UnitScript.IDLE or u.state == UnitScript.MOVE:
						u.cmd_attack(prey)
				return
		var home = main.position + (Data.MAP_SIZE / 2.0 - main.position).normalized() * 140.0
		for u in army:
			if u.state == UnitScript.IDLE and u.position.distance_to(home) > 260.0:
				u.cmd_move(home + Vector2(randf_range(-60, 60), randf_range(-60, 60)))

func _nearest_prey(pos):
	var best = null
	var bd = 1000.0
	for c in game.camps:
		for u in c["units"]:
			if is_instance_valid(u) and not u.dead and u.kind != "mantis":
				var dd = u.position.distance_to(pos)
				if dd < bd:
					bd = dd
					best = u
	return best
