extends RefCounted
# 단순 규칙 기반 인공지능(불개미 운영). 사람과 같은 규칙으로 플레이한다.
const Data = preload("res://scripts/data.gd")
const UnitScript = preload("res://scripts/unit.gd")

var game
var pid = 0
var t = 0.0
var wave_size = 10
var attacking = false
var defend_pos = Vector2.ZERO
var defend_t = 0.0

func setup(g, id):
	game = g
	pid = id

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
				workers.append(u)
			else:
				army.append(u)
	var nests = []
	var combats = []
	var defenses = []
	var lab = null
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

	_assign_workers(workers)

	# 일꾼 생산
	var queued = 0
	for n in nests:
		queued += n.queue.size()
	var want = min(14 + 6 * (nests.size() - 1), 40)
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
		elif n_nest < 3 and e > 480.0:
			_expand(main, workers)
		elif n_combat < 3 and e > 600.0 and p.food > 400.0:
			_build("combat", main.position, workers)
		elif main.tier < 3 and e > 700.0:
			game.start_upgrade(main)
		elif n_combat < 6 and p.food > 600.0:
			# 식량이 남아돌면 생산 건물을 늘려 소비한다
			_build("combat", main.position, workers)

	# 연구
	if lab != null and lab.queue.is_empty():
		for id in ["carry1", "jaw1", "shell1", "colony1"]:
			if not p.research.has(id):
				game.enqueue_research(lab, id)
				break

	# 병력 생산
	for b in combats:
		if b.queue.size() < 2:
			if main.tier >= 2 and p.mat >= 80.0 and randf() < 0.4:
				game.enqueue_unit(b, "sprayer")
			elif p.food >= 50.0:
				game.enqueue_unit(b, "stinger")
	for b in defenses:
		if b.queue.is_empty() and p.food >= 160.0:
			game.enqueue_unit(b, "soldier")

	_command_army(army, main)

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
			if game.can_place(kind, pos):
				return pos
	return null

func _build(kind, center, workers):
	if game.players[pid].mat < Data.BUILDINGS[kind]["mat"]:
		return
	var pos = _find_spot(kind, center)
	if pos == null:
		return
	game.start_build(pid, kind, pos, [_nearest(workers, pos)])

func _expand(main, workers):
	if game.players[pid].mat < Data.BUILDINGS["nest"]["mat"]:
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
	var pos = best
	if not game.can_place("nest", pos):
		pos = _find_spot("nest", best)
	if pos != null:
		game.start_build(pid, "nest", pos, [_nearest(workers, pos)])

func _command_army(army, main):
	if army.is_empty():
		attacking = false
		return
	if defend_t > 0.0:
		for u in army:
			if u.state == UnitScript.IDLE or u.state == UnitScript.MOVE:
				u.cmd_amove(defend_pos)
		return
	if not attacking and army.size() >= wave_size:
		attacking = true
	if attacking and army.size() < 4:
		attacking = false
		wave_size = min(wave_size + 6, 60)
	if attacking:
		var tgt = null
		var bd = 1e12
		for b in game.buildings:
			if b.pid != pid and not b.dead:
				var dd = b.position.distance_squared_to(main.position)
				if dd < bd:
					bd = dd
					tgt = b
		if tgt != null:
			for u in army:
				if u.state == UnitScript.IDLE:
					u.cmd_amove(tgt.position)
	else:
		var home = main.position + (Data.MAP_SIZE / 2.0 - main.position).normalized() * 140.0
		for u in army:
			if u.state == UnitScript.IDLE and u.position.distance_to(home) > 260.0:
				u.cmd_move(home + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
