extends Node2D
const Data = preload("res://scripts/data.gd")

var game
var pid = 0
var kind = ""
var d = {}
var hp = 1.0
var max_hp = 1.0
var radius = 30.0
var dead = false
var air = false
var selected = false
var built = false
var build_progress = 0.0
var is_main = false
var tier = 1
var upgrade_t = -1.0         # 0 이상이면 등급 상승 진행 중
var queue = []               # {type, id, time, progress, started, pop}
var reserved_pop = 0.0
var rally_pos = Vector2.ZERO
var rally_node = null
var atk_cd = 0.0
var venom_stacks = 0
var venom_t = 0.0
var seen = false        # 사람 플레이어가 한 번이라도 본 적 있는 적 건물만 보인다
var stealthed = false
var gardeners = []      # 균류 정원 안에서 일하는 일꾼(잎꾼개미)
var garden_buf = 0.0

func setup(g, p, k, pos, finished, main):
	game = g
	pid = p
	kind = k
	d = Data.faction_building(g.players[p].faction, k)
	max_hp = d["hp"]
	radius = d["radius"]
	position = pos
	is_main = main
	built = finished
	if built:
		hp = max_hp
		build_progress = d["time"]
	else:
		hp = max_hp * 0.1
	rally_pos = pos + (Data.MAP_SIZE / 2.0 - pos).normalized() * (radius + 40.0)

func garden_slots():
	var f = game.players[pid].faction
	var g = Data.FACTIONS[f]["garden"]
	if kind != "nest" or not built or g[0] == 0:
		return 0
	var n = g[tier - 1] if is_main else g[3]
	if game.players[pid].has("big_garden"):
		n = int(round(n * Data.BIG_GARDEN_MULT))
	return n

func garden_efficiency():
	if hp < max_hp * 0.5 and not game.players[pid].has("antibiotic"):
		return Data.GARDEN_DAMAGED_MULT
	return 1.0

func add_gardener(u):
	if gardeners.size() >= garden_slots():
		return false
	u._leave()
	gardeners.append(u)
	u.carried = true
	u.visible = false
	u.selected = false
	u.state = u.IDLE
	u.node = null
	u.carry = 0.0
	return true

func release_gardener():
	gardeners = gardeners.filter(func(x): return is_instance_valid(x) and not x.dead)
	if gardeners.is_empty():
		return null
	var u = gardeners.pop_back()
	u.carried = false
	u.visible = true
	u.position = game.terrain.nearest_open(position + Vector2(radius + 10.0, 0).rotated(randf() * TAU), "ground")
	u.state = u.IDLE
	return u

# 정원사 수만큼 재료를 식량으로 바꾼다. 재료가 모자라면 그만큼만 바꾼다
func _tick_garden(delta):
	if gardeners.is_empty():
		return
	var p = game.players[pid]
	var want = Data.GARDEN_MAT_PER_SEC * gardeners.size() * garden_efficiency() * delta
	var used = min(want, p.mat)
	if used <= 0.0:
		return
	p.mat -= used
	p.food += used * p.garden_ratio() * p.upkeep_mult()

func sight():
	return Data.SIGHT_NEST if kind == "nest" else Data.SIGHT_BUILDING

func display_name():
	if kind == "nest":
		if is_main:
			return "%s (주 둥지 %s)" % [d["name"], ["I", "II", "III"][tier - 1]]
		return "%s (위성 둥지)" % d["name"]
	return d["name"]

func add_build(delta):
	if built:
		return
	build_progress += delta
	hp = min(max_hp, hp + max_hp * 0.9 * delta / d["time"])
	if build_progress >= d["time"]:
		built = true
		game.on_building_done(self)

func add_venom(cap, burn):
	# 독은 "타오르는 독" 분기 진화가 있어야 건물에 들어간다
	if cap <= 0 or not burn:
		return
	venom_stacks = min(venom_stacks + 1, cap)
	venom_t = Data.VENOM_TIME

func _physics_process(delta):
	if dead:
		return
	if venom_stacks > 0:
		venom_t -= delta
		take_damage(Data.VENOM_DPS * venom_stacks * delta, null)
		if venom_t <= 0.0:
			venom_stacks = 0
		if dead:
			return
	if not built:
		queue_redraw()
		return
	var p = game.players[pid]
	if kind == "nest":
		_defend(delta)
		_tick_garden(delta)
	if upgrade_t >= 0.0:
		upgrade_t += delta
		if upgrade_t >= Data.NEST_UPGRADE[tier + 1]["time"]:
			tier += 1
			upgrade_t = -1.0
			game.on_building_done(self)
	if queue.size() > 0:
		var it = queue[0]
		var blocked = false
		if not it["started"]:
			if it["type"] == "unit":
				if kind == "nest" and p.succession > 0.0:
					blocked = true
				elif p.pop_used + it["pop"] > p.pop_cap + 0.001:
					blocked = true
				else:
					it["started"] = true
					reserved_pop = it["pop"]
					p.pop_used += it["pop"]
			else:
				it["started"] = true
		if not blocked:
			var speed = 1.0
			if it["type"] == "unit":
				if it["id"] == "worker":
					if not is_main and not p.has("multiqueen"):
						speed /= 1.5      # 위성 둥지는 여왕이 없어 일꾼 생산이 느리다
					speed /= 1.0 - 0.15 * p.level("spawn")
				else:
					speed /= 1.0 - 0.1 * p.level("nursery")
			it["progress"] += delta * speed
			if it["progress"] >= it["time"]:
				queue.pop_front()
				_complete(it)
	queue_redraw()

func _complete(it):
	if it["type"] == "unit":
		reserved_pop = 0.0
		var dir = (rally_pos - position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var n = it.get("batch", 1)
		for i in n:
			var off = dir.rotated((i - (n - 1) / 2.0) * 0.5) * (radius + 12.0)
			var u = game.spawn_unit(pid, it["id"], position + off)
			if not u.air:
				u.position = game.terrain.nearest_open(u.position, u.layer)
			if u.is_worker and game.players[pid].is_ai:
				continue
			if u.is_worker:
				# 집결 지점이 자원이면 바로 채집. 그 자원이 떨어졌으면 가까운 식량 지점으로 보낸다
				var rn = rally_node
				if rn == null or not is_instance_valid(rn) or not rn.available():
					rn = game.nearest_node(position, "food", u)
				if rn != null:
					u.cmd_gather(rn)
				else:
					u.cmd_move(rally_pos)
			else:
				u.cmd_move(rally_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
	elif it["type"] == "research":
		game.players[pid].research[it["id"]] = true
		game.on_research_done(pid, it["id"])
		game.on_building_done(self)

func _defend(delta):
	atk_cd -= delta
	if atk_cd > 0.0:
		return
	var t = game.find_enemy_unit(position, pid, 180.0)
	if t != null:
		atk_cd = 1.0
		game.add_shot(position, t.position, Color(1.0, 0.6, 0.2))
		t.take_damage(8.0, self)
	else:
		atk_cd = 0.3

func take_damage(amount, _attacker):
	if dead:
		return
	hp -= amount
	game.notify_attacked(self)
	if hp <= 0.0:
		dead = true
		# 정원 안의 일꾼은 둥지와 함께 죽는다
		for u in gardeners:
			if is_instance_valid(u):
				u.carried = false
				u.dead = true
				game.remove_unit(u)
		gardeners.clear()
		game.remove_building(self)

func refund_queue():
	var p = game.players[pid]
	for it in queue:
		p.food += it["food"]
		p.mat += it["mat"]
	queue.clear()
	reserved_pop = 0.0

func _draw():
	var c = game.players[pid].color
	var a = 1.0
	if not built:
		a = 0.55
	if selected:
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 40, Color(0.3, 1.0, 0.3), 2.0)
	var base = Color(0.3, 0.22, 0.14, a)
	draw_circle(Vector2.ZERO, radius, base)
	draw_circle(Vector2.ZERO, radius * 0.78, Color(c.r, c.g, c.b, a).darkened(0.35))
	match kind:
		"nest":
			draw_circle(Vector2.ZERO, radius * 0.45, Color(c.r, c.g, c.b, a))
			draw_circle(Vector2.ZERO, radius * 0.2, Color(0.1, 0.07, 0.05, a))
			if is_main:
				for i in tier:
					draw_circle(Vector2(-10 + i * 10, -radius - 8.0), 3.5, Color(1.0, 0.9, 0.3))
			var gs = garden_slots()
			for i in gs:
				var col = Color(0.85, 0.9, 0.7, a) if i < gardeners.size() else Color(0.3, 0.35, 0.25, a)
				draw_circle(Vector2(radius * 0.62, 0).rotated(i * TAU / gs), 3.0, col)
		"combat":
			for i in 3:
				draw_circle(Vector2(radius * 0.4, 0).rotated(i * TAU / 3.0), radius * 0.22, Color(c.r, c.g, c.b, a))
		"defense":
			draw_rect(Rect2(-radius * 0.4, -radius * 0.4, radius * 0.8, radius * 0.8), Color(c.r, c.g, c.b, a))
		"lab":
			draw_circle(Vector2.ZERO, radius * 0.4, Color(0.8, 1.0, 0.3, a))
		"special":
			draw_circle(Vector2(0, -radius * 0.3), radius * 0.3, Color(1, 1, 1, 0.6 * a))
			draw_circle(Vector2(0, radius * 0.3), radius * 0.3, Color(1, 1, 1, 0.6 * a))
			draw_circle(Vector2.ZERO, radius * 0.2, Color(c.r, c.g, c.b, a))
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(-80, radius + 16.0), d["name"], HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(1, 1, 1, 0.85))
	var w = radius * 2.0
	var y = -radius - 20.0
	if venom_stacks > 0:
		draw_circle(Vector2(radius * 0.7, -radius * 0.7), 3.0 + venom_stacks * 0.4, Color(0.7, 1.0, 0.2, 0.9))
	if hp < max_hp or selected:
		draw_rect(Rect2(-w / 2.0, y, w, 4.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2.0, y, w * clamp(hp / max_hp, 0.0, 1.0), 4.0), Color(0.3, 0.9, 0.3))
	var prog = -1.0
	if not built:
		prog = build_progress / d["time"]
	elif queue.size() > 0:
		prog = queue[0]["progress"] / queue[0]["time"]
	elif upgrade_t >= 0.0:
		prog = upgrade_t / Data.NEST_UPGRADE[tier + 1]["time"]
	if prog >= 0.0:
		draw_rect(Rect2(-w / 2.0, y + 6.0, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2.0, y + 6.0, w * clamp(prog, 0.0, 1.0), 3.0), Color(0.4, 0.7, 1.0))
