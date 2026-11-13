extends Node2D
const Data = preload("res://scripts/data.gd")

enum {IDLE, MOVE, AMOVE, ATTACK, GATHER, RETURN, BUILD}

var game
var pid = 0
var kind = ""
var d = {}
var hp = 1.0
var max_hp = 1.0
var pop = 1.0
var radius = 6.0
var is_worker = false
var air = false
var can_fight = true
var hits_air = false
var rooted = false
var buffed = false
var aura_t = 0.0
var dead = false
var selected = false
var facing = 0.0

var state = IDLE
var dest = Vector2.ZERO
var target = null            # 공격 대상(유닛 또는 건물)
var resume_amove = false
var amove_dest = Vector2.ZERO
var node = null              # 채집 중인 자원 지점
var last_res = "food"
var in_slot = false
var work = 0.0
var carry = 0.0
var carry_res = ""
var build_target = null
var cd = 0.0
var think = 0.0

func setup(g, p, k, pos):
	game = g
	pid = p
	kind = k
	d = Data.UNITS[k]
	max_hp = d["hp"]
	hp = max_hp
	radius = d["radius"]
	pop = d["pop"] / float(d["batch"])
	is_worker = (k == "worker")
	air = d.get("air", false)
	can_fight = d["dmg"] > 0.0
	hits_air = d.get("hits_air", d["reach"] > 30.0)
	position = pos
	think = randf() * 0.3

# ---------- 명령 ----------

func _leave():
	if in_slot and node != null and is_instance_valid(node):
		node.release_slot(self)
	in_slot = false

func can_hit(t):
	return hits_air or not t.air

func toggle_root():
	if not d.get("root", false):
		return
	_leave()
	rooted = not rooted
	target = null
	state = IDLE

func cmd_move(p):
	if rooted:
		return
	_leave()
	state = MOVE
	dest = p
	target = null
	build_target = null

func cmd_amove(p):
	if rooted:
		return
	_leave()
	state = AMOVE
	dest = p
	amove_dest = p
	target = null
	build_target = null

func cmd_attack(t):
	_leave()
	target = t
	resume_amove = false
	build_target = null
	state = ATTACK

func cmd_gather(n):
	_leave()
	node = n
	last_res = n.res_type()
	build_target = null
	if carry > 0.0:
		state = RETURN
	else:
		state = GATHER

func cmd_build(b):
	_leave()
	build_target = b
	state = BUILD

func cmd_stop():
	_leave()
	target = null
	build_target = null
	state = IDLE

# ---------- 매 틱 ----------

func _physics_process(delta):
	if dead:
		return
	cd -= delta
	if kind == "stinger":
		aura_t -= delta
		if aura_t <= 0.0:
			aura_t = 0.5
			buffed = game.tyrant_near(position, pid)
	match state:
		IDLE:
			if not rooted:
				position += _separation() * delta
			if not is_worker and can_fight:
				_think(delta, false)
		MOVE:
			if _go(dest, delta, 6.0):
				state = IDLE
		AMOVE:
			if not _think(delta, true):
				if _go(dest, delta, 10.0):
					state = IDLE
		ATTACK:
			_do_attack(delta)
		GATHER:
			_do_gather(delta)
		RETURN:
			_do_return(delta)
		BUILD:
			_do_build(delta)
	queue_redraw()

func _valid(t):
	return t != null and is_instance_valid(t) and not t.dead

func _node_ok():
	return node != null and is_instance_valid(node) and node.available()

func _think(delta, from_amove):
	think -= delta
	if think > 0.0:
		return false
	think = 0.3
	var t = game.find_enemy(position, pid, Data.AGGRO, hits_air)
	if t == null:
		return false
	target = t
	resume_amove = from_amove
	state = ATTACK
	return true

func _do_attack(delta):
	if not _valid(target) or not can_fight or not can_hit(target):
		target = null
		if resume_amove:
			state = AMOVE
			dest = amove_dest
		else:
			state = IDLE
		return
	var reach = d["reach"] + radius + target.radius
	var dist = position.distance_to(target.position)
	if dist <= reach:
		facing = (target.position - position).angle()
		if not rooted:
			position += _separation() * delta
		if cd <= 0.0:
			cd = d["cd"]
			if buffed:
				cd *= Data.TYRANT_CD_MULT
			var dmg = d["dmg"]
			if d["reach"] <= 30.0 and game.players[pid].research.has("jaw1"):
				dmg *= 1.1
			if d["reach"] > 30.0:
				game.add_shot(position, target.position, Color(0.8, 1.0, 0.3))
			target.take_damage(dmg, self)
	elif rooted:
		# 거점화 중에는 쫓아가지 않는다
		target = null
		state = IDLE
	else:
		_go(target.position, delta, reach - 2.0)
		# 건물을 치러 가는 길에 적 유닛이 붙으면 그쪽을 먼저 상대한다
		think -= delta
		if think <= 0.0:
			think = 0.5
			var t = game.find_enemy_unit(position, pid, 60.0, hits_air)
			if t != null:
				target = t

func _do_gather(delta):
	if not _node_ok():
		_leave()
		node = game.nearest_node(position, last_res, self)
		if node == null:
			state = IDLE
		return
	var reach = node.radius + radius + 4.0
	if not _go(node.position, delta, reach):
		return
	if not in_slot:
		if node.take_slot(self):
			in_slot = true
			work = node.d["harvest_time"]
		return
	work -= delta
	if work <= 0.0:
		var cap = Data.CARRY
		if game.players[pid].research.has("carry1"):
			cap += 2.0
		carry_res = node.res_type()
		last_res = carry_res
		var n = node
		in_slot = false
		n.release_slot(self)
		carry = n.harvest(cap)
		state = RETURN

func _do_return(delta):
	var nest = game.nearest_nest(pid, position)
	if nest == null:
		state = IDLE
		return
	var reach = nest.radius + radius + 4.0
	if _go(nest.position, delta, reach):
		game.deposit(pid, carry_res, carry)
		carry = 0.0
		if not _node_ok():
			node = game.nearest_node(position, last_res, self)
		if node != null:
			state = GATHER
		else:
			state = IDLE

func _do_build(delta):
	if not _valid(build_target) or build_target.built:
		build_target = null
		if _node_ok():
			state = GATHER
		else:
			state = IDLE
		return
	var reach = build_target.radius + radius + 6.0
	if _go(build_target.position, delta, reach):
		build_target.add_build(delta)

# ---------- 이동 ----------

func _go(p, delta, stop):
	var to = p - position
	var dist = to.length()
	if dist <= stop:
		return true
	var v = to / dist * d["speed"] + _separation()
	position += v * delta
	position = position.clamp(Vector2(10, 10), Data.MAP_SIZE - Vector2(10, 10))
	facing = to.angle()
	return false

func _separation():
	var push = Vector2.ZERO
	for o in game.query_units(position, 18.0):
		if o == self or o.air != air:
			continue
		var off = position - o.position
		var dd = off.length()
		var minr = radius + o.radius
		if dd < minr:
			if dd < 0.01:
				off = Vector2.RIGHT.rotated(randf() * TAU)
				dd = 1.0
			push += off / dd * (minr - dd) * 8.0
	if is_worker:
		push *= 0.3
	return push.limit_length(80.0)

# ---------- 피해 ----------

func take_damage(amount, attacker):
	if dead:
		return
	if game.players[pid].research.has("shell1"):
		amount *= 0.92
	if rooted:
		amount *= Data.ROOT_DAMAGE_MULT
	hp -= amount
	if hp <= 0.0:
		dead = true
		_leave()
		game.remove_unit(self)
		return
	if not is_worker and can_fight and state == IDLE and _valid(attacker) and can_hit(attacker):
		target = attacker
		resume_amove = false
		state = ATTACK

# ---------- 그리기 ----------

func _draw():
	var c = game.players[pid].color
	if selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 20, Color(0.3, 1.0, 0.3), 1.5)
	var r = radius
	if air:
		draw_circle(Vector2(4, 10), r * 0.8, Color(0, 0, 0, 0.25))
	if rooted:
		draw_rect(Rect2(-r - 3, -r - 3, r * 2 + 6, r * 2 + 6), Color(0.85, 0.7, 0.4), false, 2.0)
	draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
	if air:
		draw_circle(Vector2(-r * 0.2, -r * 0.9), r * 0.7, Color(1, 1, 1, 0.45))
		draw_circle(Vector2(-r * 0.2, r * 0.9), r * 0.7, Color(1, 1, 1, 0.45))
	draw_circle(Vector2(-r * 0.9, 0), r * 0.75, c.darkened(0.3))
	draw_circle(Vector2.ZERO, r * 0.5, c)
	if kind == "soldier":
		draw_circle(Vector2(r * 0.85, 0), r * 0.75, c.lightened(0.1))
	else:
		draw_circle(Vector2(r * 0.8, 0), r * 0.55, c.lightened(0.15))
	if kind == "sprayer":
		draw_circle(Vector2(-r * 0.9, 0), r * 0.4, Color(0.8, 1.0, 0.3))
	if is_worker:
		draw_circle(Vector2.ZERO, r * 0.25, Color(1, 1, 1, 0.7))
	if carry > 0.0:
		var cc = Data.FOOD_COLOR
		if carry_res == "mat":
			cc = Data.MAT_COLOR
		draw_circle(Vector2(r * 1.6, 0), 3.0, cc)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < max_hp or selected:
		var w = radius * 2.4
		draw_rect(Rect2(-w / 2.0, -radius - 8.0, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2.0, -radius - 8.0, w * clamp(hp / max_hp, 0.0, 1.0), 3.0), Color(0.3, 0.9, 0.3))
