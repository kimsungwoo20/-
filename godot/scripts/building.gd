extends Node2D
const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")

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
var net_ok = true       # 베짜기개미: 주 둥지와 영역이 이어져 있는가
# 군대개미: camp(야영) / packing(행군 준비) / march(행군) / unpacking(야영 준비)
var mode = "camp"
var mode_t = 0.0
var camp_t = 0.0        # 야영이 이어진 시간
var march_dest = null
var path = []
var nav_t = 0.0
var pop_cost = 0.0      # 군대개미: 건물이 차지하는 인구
var nid = 0
var net_gardeners = 0   # 참가자 화면: 방장이 알려 준 정원사 수

func setup(g, p, k, pos, finished, main):
	game = g
	pid = p
	kind = k
	d = Data.faction_building(g.players[p].faction, k)
	max_hp = d["hp"]
	if g.players[p].has("fortress"):
		max_hp *= Data.FORT_HP
	radius = d["radius"]
	position = pos
	is_main = main
	pop_cost = d.get("pop", 0.0)
	# 함정턱개미: 본진 외 건물은 은폐
	if kind != "nest" and Data.FACTIONS.get(g.players[p].faction, {}).get("hidden_buildings", false):
		stealthed = true
	built = finished
	if built:
		hp = max_hp
		build_progress = d["time"]
	else:
		hp = max_hp * 0.1
	rally_pos = pos + (Data.MAP_SIZE / 2.0 - pos).normalized() * (radius + 40.0)

# ---------- 야영과 행군 (군대개미) ----------

func is_mobile():
	return Data.FACTIONS.get(game.players[pid].faction, {}).get("mobile", false)

func camped():
	return mode == "camp"

func pack_time():
	var p = game.players[pid]
	if p.has("eternal_wander"):
		return Data.PACK_TIME_WANDER
	if p.has("statary_brood"):
		return Data.PACK_TIME_STATARY
	return Data.PACK_TIME

func unpack_time():
	return Data.UNPACK_TIME_WANDER if game.players[pid].has("eternal_wander") else Data.UNPACK_TIME

# 행군 준비 시작
func pack():
	if not built or not is_mobile() or mode != "camp":
		return false
	mode = "packing"
	mode_t = pack_time()
	camp_t = 0.0
	return true

# 야영 준비 시작. 지을 수 없는 자리면 실패
func unpack():
	if mode != "march":
		return false
	if not game.can_camp(self):
		return false
	mode = "unpacking"
	mode_t = unpack_time()
	march_dest = null
	path = []
	return true

func march_to(pos):
	if mode != "march" and mode != "packing":
		return false
	march_dest = game.terrain.nearest_open(pos, "ground")
	path = []
	nav_t = 0.0
	return true

func _tick_mobile(delta):
	if mode == "camp":
		camp_t += delta
		return
	if mode == "packing":
		mode_t -= delta
		if mode_t <= 0.0:
			mode = "march"
			game.on_building_done(self)
	elif mode == "unpacking":
		mode_t -= delta
		if mode_t <= 0.0:
			mode = "camp"
			camp_t = 0.0
			rally_pos = position + (Data.MAP_SIZE / 2.0 - position).normalized() * (radius + 40.0)
			game.on_building_done(self)
	elif mode == "march" and march_dest != null:
		var t = game.terrain
		nav_t -= delta
		if nav_t <= 0.0:
			nav_t = 0.5
			if t.line_clear(position, march_dest, "ground"):
				path = []
			else:
				path = t.find_path(position, march_dest, "ground")
		while path.size() > 0 and position.distance_to(path[0]) < 14.0:
			path.remove_at(0)
		var aim = march_dest
		if path.size() > 0:
			aim = path[0]
		var to = aim - position
		if position.distance_to(march_dest) < 6.0:
			march_dest = null
			return
		var sp = Data.MARCH_SPEED_GREAT if game.players[pid].has("great_march") else Data.MARCH_SPEED
		var np = position + to.normalized() * min(sp * delta, to.length())
		if t.passable(np, "ground"):
			position = np

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
	var s = Data.SIGHT_NEST if kind == "nest" else Data.SIGHT_BUILDING
	if game.has_territory(pid):
		s = max(s, Data.TERR_RADIUS[kind])
	return s

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
		if game.controls(pid):
			game.play("built")
		game.on_building_done(self)

func add_venom(cap, burn):
	# 독은 "타오르는 독" 분기 진화가 있어야 건물에 들어간다
	if cap <= 0 or not burn:
		return
	venom_stacks = min(venom_stacks + 1, cap)
	venom_t = Data.VENOM_TIME

func garden_count():
	return net_gardeners if game.net_role == "client" else gardeners.size()

func _physics_process(delta):
	if game.net_role == "client":
		queue_redraw()
		return
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
	_tick_mobile(delta)
	if net_ok and hp < max_hp and p.has("fortress"):
		hp = min(max_hp, hp + Data.FORT_REGEN * delta)
	if kind == "nest":
		if camped():
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
		# 행군 중: 연구와 일꾼 생산 정지(영원한 유랑이면 일꾼은 생산), 유닛 생산은 느려진다
		var moving = not camped()
		if moving and (it["type"] == "research" or (it["id"] == "worker" and not p.has("eternal_wander"))):
			blocked = true
		elif not it["started"]:
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
			if moving:
				speed *= Data.MARCH_PRODUCTION_GREAT if p.has("great_march") else Data.MARCH_PRODUCTION
			elif p.has("statary_brood") and camp_t >= Data.STATARY_AFTER:
				speed *= Data.STATARY_SPEED
			if not net_ok:
				speed *= Data.TERR_CUT_PRODUCTION     # 끊어진 구역의 건물은 생산이 느리다
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
		if game.controls(pid):
			game.play("ready")
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

func take_damage(amount, attacker):
	if dead:
		return
	if not camped():
		amount *= Data.MARCH_TAKEN      # 야영 중이 아닌 건물은 약하다
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
		game.on_kill(attacker, self)
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
	if mode != "camp":
		# 행군 중인 건물: 흩어진 개미 무리처럼 점선 테두리
		for i in 12:
			draw_arc(Vector2.ZERO, radius + 2.0, i * TAU / 12.0, i * TAU / 12.0 + 0.3, 4, Color(1, 1, 1, 0.7), 2.0)
		if mode != "march":
			var total = pack_time() if mode == "packing" else unpack_time()
			draw_arc(Vector2.ZERO, radius + 9.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - mode_t / total), 24, Color(1.0, 0.8, 0.3), 2.5)
		if march_dest != null and selected:
			draw_line(Vector2.ZERO, march_dest - position, Color(1, 1, 1, 0.35), 1.0)
	Art.draw_building(self, self, c, game.players[pid].faction, a, game.elapsed)
	if kind == "nest":
		if is_main:
			for i in tier:
				draw_circle(Vector2(-10 + i * 10, -radius - 8.0), 3.5, Color(1.0, 0.9, 0.3))
		var gs = garden_slots()
		for i in gs:
			var col = Color(0.85, 0.9, 0.7, a) if i < garden_count() else Color(0.3, 0.35, 0.25, a)
			draw_circle(Vector2(radius * 0.72, 0).rotated(i * TAU / gs), 3.0, col)
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
