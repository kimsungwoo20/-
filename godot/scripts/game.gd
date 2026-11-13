extends Node2D
# 시제품 범위: 공통 시스템(자원·건물·생산·인구·유지비·연구 일부) + 불개미 1진영, 사람 1 대 인공지능 1.

const Data = preload("res://scripts/data.gd")
const UnitScript = preload("res://scripts/unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const NodeScript = preload("res://scripts/resource_node.gd")
const PlayerScript = preload("res://scripts/player.gd")
const AIScript = preload("res://scripts/ai.gd")
const HudScript = preload("res://scripts/hud.gd")

const CELL = 64.0

var players = []
var units = []
var buildings = []
var res_nodes = []
var expansions = []
var grid = {}
var shots = []
var selection = []
var sel_version = 0
var ais = []
var human_id = 0
var elapsed = 0.0
var game_over = false
var winner = -1
var autotest = false
var report_t = 0.0

var camera
var hud
var overlay
var world
var decor = []

var build_mode = ""
var amove_armed = false
var dragging = false
var drag_from = Vector2.ZERO
var pan_drag = false

func _ready():
	autotest = OS.get_cmdline_user_args().has("--autotest")
	world = Node2D.new()
	add_child(world)
	overlay = Node2D.new()
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_setup_players()
	_setup_map()
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	var m = main_nest(human_id)
	if m != null:
		camera.position = m.position
	if autotest:
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 16
	else:
		msg("일꾼으로 자원을 모으고 독침 부화굴을 지어 적 둥지를 파괴하세요")

# ---------- 초기 배치 ----------

func _setup_players():
	var defs = [["플레이어", Color(0.9, 0.25, 0.15)], ["인공지능", Color(0.25, 0.5, 0.95)]]
	for i in defs.size():
		var p = PlayerScript.new()
		p.id = i
		p.label = defs[i][0]
		p.color = defs[i][1]
		p.is_ai = (i != human_id) or autotest
		players.append(p)
		if p.is_ai:
			var ai = AIScript.new()
			ai.setup(self, i)
			ais.append(ai)

func _mirror(p):
	return Vector2(Data.MAP_SIZE.x - p.x, p.y)

func _setup_map():
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		decor.append([Vector2(rng.randf() * Data.MAP_SIZE.x, rng.randf() * Data.MAP_SIZE.y), rng.randf_range(2.0, 7.0), rng.randf_range(-0.05, 0.05)])
	var start = Vector2(420, 1000)
	var half = [
		["seed", Vector2(600, 880)], ["litter", Vector2(600, 1130)], ["aphid", Vector2(300, 760)],
		["aphid", Vector2(930, 330)], ["plant", Vector2(770, 290)],
		["aphid", Vector2(930, 1670)], ["plant", Vector2(770, 1710)],
		["plant", Vector2(1250, 1000)],
	]
	for e in half:
		_add_node(e[0], e[1])
		_add_node(e[0], _mirror(e[1]))
	_add_node("deadwood", Vector2(1600, 1000))
	_add_node("plant", Vector2(1600, 620))
	_add_node("plant", Vector2(1600, 1380))
	_add_node("aphid", Vector2(1600, 250))
	_add_node("aphid", Vector2(1600, 1750))
	for e in [Vector2(840, 420), Vector2(840, 1580), Vector2(1600, 400), Vector2(1600, 1600)]:
		expansions.append(e)
		if e.x < 1500:
			expansions.append(_mirror(e))
	var starts = [start, _mirror(start)]
	for i in players.size():
		var nest = spawn_building(i, "nest", starts[i], true, true)
		nest.rally_node = nearest_node(nest.position, "food", null)
		for k in Data.START_WORKERS:
			var u = spawn_unit(i, "worker", starts[i] + Vector2(60, 0).rotated(k * TAU / Data.START_WORKERS))
			if not players[i].is_ai and nest.rally_node != null:
				u.cmd_gather(nest.rally_node)

func _add_node(kind, pos):
	var n = NodeScript.new()
	n.setup(self, kind, pos)
	world.add_child(n)
	res_nodes.append(n)

func spawn_unit(pid, kind, pos):
	var u = UnitScript.new()
	u.setup(self, pid, kind, pos)
	u.z_index = 5
	world.add_child(u)
	units.append(u)
	return u

func spawn_building(pid, kind, pos, finished, main):
	var b = BuildingScript.new()
	b.setup(self, pid, kind, pos, finished, main)
	b.z_index = 2
	world.add_child(b)
	buildings.append(b)
	return b

# ---------- 제거 ----------

func remove_unit(u):
	units.erase(u)
	if selection.has(u):
		selection.erase(u)
		sel_version += 1
	u.queue_free()

func remove_res_node(n):
	n.gone = true
	res_nodes.erase(n)
	n.queue_free()

func remove_building(b):
	buildings.erase(b)
	if selection.has(b):
		selection.erase(b)
	sel_version += 1
	var p = players[b.pid]
	if b.kind == "nest" and b.is_main:
		# 여왕 계승: 가장 가까운 위성 둥지가 주 둥지가 되고 등급이 1단계 내려간다
		var best = null
		for o in buildings:
			if o.pid == b.pid and o.kind == "nest" and o.built:
				if best == null or o.position.distance_to(b.position) < best.position.distance_to(b.position):
					best = o
		if best != null:
			best.is_main = true
			best.tier = max(1, b.tier - 1)
			p.succession = Data.SUCCESSION_TIME
			if b.pid == human_id:
				msg("주 둥지가 파괴되었습니다. 여왕 계승 중 (일꾼 생산 60초 정지)")
	b.queue_free()

func on_building_done(_b):
	sel_version += 1

func notify_attacked(b):
	for ai in ais:
		if ai.pid == b.pid:
			ai.on_attacked(b)

# ---------- 조회 ----------

func _cell(p):
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))

func _rebuild_grid():
	grid.clear()
	for u in units:
		var c = _cell(u.position)
		if grid.has(c):
			grid[c].append(u)
		else:
			grid[c] = [u]

func query_units(pos, r):
	var out = []
	var a = _cell(pos - Vector2(r, r))
	var b = _cell(pos + Vector2(r, r))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var c = Vector2i(x, y)
			if grid.has(c):
				for u in grid[c]:
					if not u.dead and u.position.distance_to(pos) <= r:
						out.append(u)
	return out

func find_enemy_unit(pos, pid, r):
	var best = null
	var bd = r
	for u in query_units(pos, r):
		if u.pid != pid:
			var dd = u.position.distance_to(pos)
			if dd <= bd:
				bd = dd
				best = u
	return best

func find_enemy(pos, pid, r):
	var u = find_enemy_unit(pos, pid, r)
	if u != null:
		return u
	var best = null
	var bd = r
	for b in buildings:
		if b.pid != pid and not b.dead:
			var dd = b.position.distance_to(pos) - b.radius
			if dd <= bd:
				bd = dd
				best = b
	return best

func nearest_nest(pid, pos):
	var best = null
	var bd = 1e12
	for b in buildings:
		if b.pid == pid and b.kind == "nest" and b.built and not b.dead:
			var dd = b.position.distance_squared_to(pos)
			if dd < bd:
				bd = dd
				best = b
	return best

func main_nest(pid):
	for b in buildings:
		if b.pid == pid and b.kind == "nest" and b.is_main and not b.dead:
			return b
	return null

func main_tier(pid):
	var m = main_nest(pid)
	if m == null:
		return 1
	return m.tier

func node_load(n):
	var c = 0
	for u in units:
		if u.node == n and (u.state == UnitScript.GATHER or u.state == UnitScript.RETURN):
			c += 1
	return c

# 가장 가까운 채집 가능 지점. 이미 일꾼이 몰린 지점은 뒤로 미룬다.
func nearest_node(pos, res, _who):
	var best = null
	var bs = 1e12
	for n in res_nodes:
		if n.res_type() != res or not n.available():
			continue
		var score = n.position.distance_to(pos)
		if node_load(n) >= n.d["slots"] + 2:
			score += 600.0
		if score < bs:
			bs = score
			best = n
	return best

func count_buildings(pid, kind):
	var c = 0
	for b in buildings:
		if b.pid == pid and b.kind == kind:
			c += 1
	return c

func has_built(pid, kind):
	for b in buildings:
		if b.pid == pid and b.kind == kind and b.built:
			return true
	return false

# ---------- 경제 ----------

func deposit(pid, res, amount):
	var p = players[pid]
	if res == "food":
		p.food += amount * p.upkeep_mult()
	else:
		p.mat += amount

func can_place(kind, pos):
	var r = Data.BUILDINGS[kind]["radius"]
	if pos.x < r + 20 or pos.y < r + 20 or pos.x > Data.MAP_SIZE.x - r - 20 or pos.y > Data.MAP_SIZE.y - r - 20:
		return false
	for b in buildings:
		if b.position.distance_to(pos) < r + b.radius + 14.0:
			return false
	for n in res_nodes:
		if n.position.distance_to(pos) < r + n.radius + 30.0:
			return false
	return true

func _say(pid, text):
	if pid == human_id and not autotest:
		msg(text)

func start_build(pid, kind, pos, builders):
	var p = players[pid]
	var d = Data.BUILDINGS[kind]
	if kind == "lab":
		if count_buildings(pid, "lab") > 0:
			_say(pid, "연구소는 하나만 지을 수 있습니다")
			return null
		if not has_built(pid, "combat") and not has_built(pid, "defense"):
			_say(pid, "전투 또는 방어 생산 건물이 먼저 필요합니다")
			return null
	if not can_place(kind, pos):
		_say(pid, "그 자리에는 지을 수 없습니다")
		return null
	if not p.can_afford(0, d["mat"]):
		_say(pid, "재료가 부족합니다")
		return null
	p.pay(0, d["mat"])
	var b = spawn_building(pid, kind, pos, false, false)
	for u in builders:
		if u.is_worker:
			u.cmd_build(b)
	sel_version += 1
	return b

func enqueue_unit(b, id):
	var p = players[b.pid]
	var d = Data.UNITS[id]
	if not b.built:
		return false
	if b.queue.size() >= Data.QUEUE_MAX:
		_say(b.pid, "대기열이 가득 찼습니다")
		return false
	if main_tier(b.pid) < d["tier"]:
		_say(b.pid, "주 둥지 등급이 부족합니다")
		return false
	if not p.can_afford(d["food"], d["mat"]):
		_say(b.pid, "자원이 부족합니다")
		return false
	p.pay(d["food"], d["mat"])
	b.queue.append({"type": "unit", "id": id, "time": d["time"], "progress": 0.0, "started": false,
		"pop": d["pop"], "food": d["food"], "mat": d["mat"]})
	return true

func enqueue_research(b, id):
	var p = players[b.pid]
	var d = Data.RESEARCH[id]
	if not b.built or p.research.has(id) or b.queue.size() >= 3:
		return false
	for it in b.queue:
		if it["id"] == id:
			return false
	if not p.can_afford(d["food"], d["mat"]):
		_say(b.pid, "자원이 부족합니다")
		return false
	p.pay(d["food"], d["mat"])
	b.queue.append({"type": "research", "id": id, "time": d["time"], "progress": 0.0, "started": false,
		"pop": 0.0, "food": d["food"], "mat": d["mat"]})
	sel_version += 1
	return true

func start_upgrade(b):
	var p = players[b.pid]
	if not b.is_main or b.tier >= 3 or b.upgrade_t >= 0.0:
		return false
	var cost = Data.NEST_UPGRADE[b.tier + 1]["mat"]
	if not p.can_afford(0, cost):
		_say(b.pid, "재료가 부족합니다")
		return false
	p.pay(0, cost)
	b.upgrade_t = 0.0
	sel_version += 1
	return true

func cancel_last(b):
	if b.queue.is_empty():
		return
	var it = b.queue.pop_back()
	var p = players[b.pid]
	p.food += it["food"]
	p.mat += it["mat"]
	if b.queue.is_empty():
		b.reserved_pop = 0.0
	sel_version += 1

# ---------- 명령 ----------

func order_move(us, pos, attack):
	var i = 0
	for u in us:
		var off = Vector2.RIGHT.rotated(i * 2.4) * 14.0 * sqrt(float(i))
		if attack and not u.is_worker:
			u.cmd_amove(pos + off)
		else:
			u.cmd_move(pos + off)
		i += 1

func sel_units():
	var out = []
	for e in selection:
		if is_instance_valid(e) and e is UnitScript and e.pid == human_id and not e.dead:
			out.append(e)
	return out

func sel_building():
	if selection.size() == 1 and is_instance_valid(selection[0]) and selection[0] is BuildingScript:
		return selection[0]
	return null

func set_selection(arr):
	for e in selection:
		if is_instance_valid(e):
			e.selected = false
	selection = arr
	for e in selection:
		e.selected = true
	sel_version += 1
	build_mode = ""
	amove_armed = false

func _entity_at(pos):
	var best = null
	var bd = 1e9
	for u in query_units(pos, 16.0):
		var dd = u.position.distance_to(pos)
		if dd < bd:
			bd = dd
			best = u
	if best != null:
		return best
	for b in buildings:
		if b.position.distance_to(pos) <= b.radius:
			return b
	for n in res_nodes:
		if n.position.distance_to(pos) <= n.radius:
			return n
	return null

# HUD 가 그릴 명령 버튼 목록
func get_commands():
	var cmds = []
	var p = players[human_id]
	var b = sel_building()
	if b != null and b.pid == human_id:
		if not b.built:
			return cmds
		for id in b.d["produces"]:
			var d = Data.UNITS[id]
			var txt = d["name"]
			if d["batch"] > 1:
				txt += " ×%d" % d["batch"]
			txt += "\n식량 %d" % d["food"]
			if d["mat"] > 0:
				txt += " 재료 %d" % d["mat"]
			cmds.append({"text": txt, "tip": "인구 %s, %d초" % [str(d["pop"]), int(d["time"])],
				"enabled": main_tier(human_id) >= d["tier"], "call": enqueue_unit.bind(b, id)})
		if b.kind == "nest" and b.is_main and b.tier < 3 and b.upgrade_t < 0.0:
			var up = Data.NEST_UPGRADE[b.tier + 1]
			cmds.append({"text": "둥지 등급 상승\n재료 %d" % up["mat"], "tip": "상위 유닛과 인구 한도 해금",
				"enabled": true, "call": start_upgrade.bind(b)})
		if b.kind == "lab":
			for id in Data.RESEARCH:
				if p.research.has(id):
					continue
				var queued = false
				for it in b.queue:
					if it["id"] == id:
						queued = true
				if queued:
					continue
				var r = Data.RESEARCH[id]
				var t2 = "%s\n재료 %d" % [r["name"], r["mat"]]
				if r["food"] > 0:
					t2 += " 식량 %d" % r["food"]
				cmds.append({"text": t2, "tip": r["tip"], "enabled": true, "call": enqueue_research.bind(b, id)})
		if b.queue.size() > 0:
			cmds.append({"text": "마지막 예약 취소", "tip": "전액 환불", "enabled": true, "call": cancel_last.bind(b)})
		return cmds
	var has_worker = false
	for u in sel_units():
		if u.is_worker:
			has_worker = true
	if has_worker:
		for k in ["nest", "combat", "defense", "lab"]:
			var d2 = Data.BUILDINGS[k]
			var nm = d2["name"]
			if k == "nest":
				nm += " (위성)"
			cmds.append({"text": "%s\n재료 %d" % [nm, d2["mat"]], "tip": "지을 자리를 클릭",
				"enabled": true, "call": _enter_build.bind(k)})
	return cmds

func _enter_build(kind):
	build_mode = kind
	amove_armed = false

func msg(text):
	if hud != null:
		hud.show_msg(text)

# ---------- 입력 ----------

func _unhandled_input(ev):
	if game_over or autotest:
		return
	if ev is InputEventMouseButton:
		var wp = get_global_mouse_position()
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom(1.1)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom(1.0 / 1.1)
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			pan_drag = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if build_mode != "":
					var workers = sel_units().filter(func(u): return u.is_worker)
					if start_build(human_id, build_mode, wp, workers) != null:
						build_mode = ""
				elif amove_armed:
					order_move(sel_units(), wp, true)
					amove_armed = false
				else:
					dragging = true
					drag_from = wp
			elif dragging:
				_finish_drag(wp)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			if build_mode != "" or amove_armed:
				build_mode = ""
				amove_armed = false
			else:
				_right_click(wp)
	elif ev is InputEventMouseMotion and pan_drag:
		camera.position -= ev.relative / camera.zoom.x
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_A:
				if sel_units().size() > 0:
					amove_armed = true
					build_mode = ""
			KEY_S:
				for u in sel_units():
					u.cmd_stop()
			KEY_ESCAPE:
				if build_mode != "" or amove_armed:
					build_mode = ""
					amove_armed = false
				else:
					set_selection([])
			KEY_Q:
				hud.press_button(0)
			KEY_W:
				hud.press_button(1)
			KEY_E:
				hud.press_button(2)
			KEY_R:
				hud.press_button(3)
			KEY_T:
				hud.press_button(4)

func _zoom(f):
	var z = clamp(camera.zoom.x * f, 0.45, 1.8)
	camera.zoom = Vector2(z, z)

func _finish_drag(wp):
	dragging = false
	var rect = Rect2(drag_from, wp - drag_from).abs()
	if rect.size.length() < 8.0:
		var e = _entity_at(wp)
		if e != null and (e is UnitScript or e is BuildingScript) and e.pid == human_id:
			set_selection([e])
		else:
			set_selection([])
		return
	var picked = []
	var any_army = false
	for u in units:
		if u.pid == human_id and rect.has_point(u.position):
			picked.append(u)
			if not u.is_worker:
				any_army = true
	if any_army:
		picked = picked.filter(func(u): return not u.is_worker)
	set_selection(picked)

func _right_click(wp):
	var e = _entity_at(wp)
	var b = sel_building()
	if b != null and b.pid == human_id:
		b.rally_pos = wp
		b.rally_node = null
		if e != null and e is NodeScript:
			b.rally_node = e
		msg("집결 지점 지정")
		return
	var us = sel_units()
	if us.is_empty():
		return
	if e != null and (e is UnitScript or e is BuildingScript) and e.pid != human_id:
		for u in us:
			u.cmd_attack(e)
	elif e != null and e is NodeScript:
		var rest = []
		for u in us:
			if u.is_worker:
				u.cmd_gather(e)
			else:
				rest.append(u)
		order_move(rest, wp, false)
	elif e != null and e is BuildingScript and e.pid == human_id and not e.built:
		for u in us:
			if u.is_worker:
				u.cmd_build(e)
	else:
		order_move(us, wp, false)

# ---------- 매 프레임 ----------

func _process(delta):
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_drag(get_global_mouse_position())
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		pan_drag = false
	var mv = Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		mv.y += 1
	var real = delta / max(Engine.time_scale, 0.001)
	camera.position += mv * 700.0 * real / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, Data.MAP_SIZE)
	for s in shots:
		s[2] -= delta
	shots = shots.filter(func(s): return s[2] > 0.0)
	overlay.queue_redraw()

func _physics_process(delta):
	if game_over:
		return
	elapsed += delta
	_rebuild_grid()
	for p in players:
		p.pop_used = 0.0
		p.pop_cap = 0.0
		if p.succession > 0.0:
			p.succession -= delta
	for u in units:
		players[u.pid].pop_used += u.pop
	var has_nest = []
	for p in players:
		has_nest.append(false)
	for b in buildings:
		var p = players[b.pid]
		p.pop_used += b.reserved_pop
		if b.kind == "nest" and b.built:
			has_nest[b.pid] = true
			if b.is_main:
				p.pop_cap += Data.NEST_POP[b.tier - 1]
			else:
				p.pop_cap += Data.SAT_POP
	for p in players:
		if p.research.has("colony1"):
			p.pop_cap += 10.0
		p.pop_cap = min(p.pop_cap, Data.POP_MAX)
		if p.alive and not has_nest[p.id]:
			_eliminate(p)
	for ai in ais:
		ai.tick(delta)
	_check_end()
	if autotest:
		report_t += delta
		if report_t >= 60.0:
			report_t = 0.0
			_report()
		if elapsed > 1200.0:
			print("AUTOTEST timeout")
			_report()
			get_tree().quit()

func _eliminate(p):
	p.alive = false
	for u in units.duplicate():
		if u.pid == p.id:
			u.dead = true
			remove_unit(u)
	for b in buildings.duplicate():
		if b.pid == p.id:
			b.dead = true
			remove_building(b)

func _check_end():
	var alive = []
	for p in players:
		if p.alive:
			alive.append(p.id)
	var over = alive.size() <= 1
	if not autotest and not players[human_id].alive:
		over = true
	if not over:
		return
	game_over = true
	winner = -1
	if alive.size() == 1:
		winner = alive[0]
	if autotest:
		print("AUTOTEST over winner=%d t=%d" % [winner, int(elapsed)])
		_report()
		get_tree().quit()
	else:
		hud.show_game_over(winner == human_id)

func _report():
	for p in players:
		var nu = 0
		var nw = 0
		for u in units:
			if u.pid == p.id:
				nu += 1
				if u.is_worker:
					nw += 1
		var nb = 0
		for b in buildings:
			if b.pid == p.id:
				nb += 1
		print("t=%d p%d food=%d mat=%d pop=%.1f/%d units=%d workers=%d buildings=%d research=%s" % [
			int(elapsed), p.id, int(p.food), int(p.mat), p.pop_used, int(p.pop_cap), nu, nw, nb, str(p.research.keys())])

func add_shot(a, b, c):
	shots.append([a, b, 0.12, c])

# ---------- 그리기 ----------

func _draw():
	draw_rect(Rect2(Vector2.ZERO, Data.MAP_SIZE), Color(0.36, 0.29, 0.2))
	for e in decor:
		draw_circle(e[0], e[1], Color(0.36 + e[2], 0.29 + e[2], 0.2 + e[2]))
	for e in expansions:
		draw_arc(e, 44.0, 0.0, TAU, 32, Color(1, 1, 1, 0.08), 2.0)

func _draw_overlay():
	for s in shots:
		overlay.draw_line(s[0], s[1], s[3], 2.0)
	if dragging:
		var r = Rect2(drag_from, get_global_mouse_position() - drag_from).abs()
		overlay.draw_rect(r, Color(0.3, 1.0, 0.3, 0.15))
		overlay.draw_rect(r, Color(0.3, 1.0, 0.3, 0.9), false, 1.5)
	if build_mode != "":
		var mp = get_global_mouse_position()
		var ok = can_place(build_mode, mp)
		var c = Color(0.3, 1.0, 0.3, 0.4)
		if not ok:
			c = Color(1.0, 0.3, 0.3, 0.4)
		overlay.draw_circle(mp, Data.BUILDINGS[build_mode]["radius"], c)
	var b = sel_building()
	if b != null and b.pid == human_id and b.built and b.d["produces"].size() > 0:
		overlay.draw_line(b.position, b.rally_pos, Color(1, 1, 1, 0.3), 1.0)
		overlay.draw_circle(b.rally_pos, 4.0, Color(1, 1, 1, 0.6))
