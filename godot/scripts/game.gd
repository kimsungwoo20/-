extends Node2D
# 시제품 범위: 공통 시스템(자원·건물·생산·인구·유지비·연구 일부) + 불개미 1진영, 사람 1 대 인공지능 1.

const Data = preload("res://scripts/data.gd")
const UnitScript = preload("res://scripts/unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const NodeScript = preload("res://scripts/resource_node.gd")
const PlayerScript = preload("res://scripts/player.gd")
const AIScript = preload("res://scripts/ai.gd")
const HudScript = preload("res://scripts/hud.gd")
const FogScript = preload("res://scripts/fog.gd")
const TerrainScript = preload("res://scripts/terrain.gd")

const CELL = 64.0
const HOTKEYS = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B]

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
var sandbox = false      # 점검용: 인공지능 없음, 승패 판정 없음
var report_t = 0.0

var camera
var hud
var overlay
var world
var decor = []
var fog
var terrain
var fog_t = 0.0
var camps = []           # {pos, kinds, units, respawn}
var drop_t = 0.0
var detectors = {}       # pid -> [[위치, 감지 반경], ...]
var drop_rng = RandomNumberGenerator.new()
var spore_zones = []     # [위치, 남은 시간, 주인 pid]
var zones = []           # 유닛에 피해를 주는 지대(농축 개미산): [위치, 남은 시간, 주인 pid, 반경, 초당 피해]
var terr_nodes = {}      # pid -> [{pos, r, ok, build, id}]  수관 영역 고리
var terr_lost = {}       # 고리 id -> 끊어진 뒤 지난 시간
var terr_t = 0.0
var curtains = []        # 펼쳐진 비단 장막: [위치, pid, 주인 영역 안인가]
var terr_layer

var build_mode = ""
var lab_tab = "body"
var amove_armed = false
var dragging = false
var drag_from = Vector2.ZERO
var pan_drag = false

func _ready():
	autotest = OS.get_cmdline_user_args().has("--autotest")
	sandbox = OS.get_cmdline_user_args().has("--sandbox")
	terrain = TerrainScript.new()
	terrain.setup()
	world = Node2D.new()
	add_child(world)
	terr_layer = Node2D.new()
	terr_layer.z_index = 1
	add_child(terr_layer)
	terr_layer.draw.connect(_draw_territory)
	overlay = Node2D.new()
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	fog = FogScript.new()
	fog.z_index = 30
	add_child(fog)
	fog.setup()
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.zoom = Vector2(1.25, 1.25)
	_setup_players()
	_setup_map()
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	var m = main_nest(human_id)
	if m != null:
		camera.position = m.position
	_update_fog()
	# 웹 주소 끝에 ?debug 를 붙이면 자원 5000 으로 시작(점검용)
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("debug"):
			players[human_id].food = 5000.0
			players[human_id].mat = 5000.0
	if autotest:
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 16
	else:
		msg("일꾼으로 자원을 모으고 독침 부화굴을 지어 적 둥지를 파괴하세요")

# ---------- 초기 배치 ----------

func _pick_factions():
	var f = ["fire", "leaf"]
	var args = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--p0="):
			f[0] = a.substr(5)
		elif a.begins_with("--p1="):
			f[1] = a.substr(5)
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		for part in q.trim_prefix("?").split("&"):
			var kv = part.split("=")
			if kv.size() == 2 and kv[0] == "me":
				f[human_id] = kv[1]
			elif kv.size() == 2 and kv[0] == "ai":
				f[1 - human_id] = kv[1]
	for i in 2:
		if not Data.FACTIONS.has(f[i]):
			f[i] = "fire"
	return f

func _setup_players():
	var defs = [["플레이어", Color(0.9, 0.25, 0.15)], ["인공지능", Color(0.25, 0.5, 0.95)]]
	var fs = _pick_factions()
	for i in defs.size():
		var p = PlayerScript.new()
		p.id = i
		p.label = defs[i][0]
		p.color = defs[i][1]
		p.faction = fs[i]
		p.is_ai = (i != human_id) or autotest
		players.append(p)
		if p.is_ai and not sandbox:
			var ai = AIScript.new()
			ai.setup(self, i)
			ais.append(ai)
	var np = PlayerScript.new()
	np.id = Data.NEUTRAL_ID
	np.label = "중립"
	np.color = Color(0.55, 0.6, 0.35)
	np.neutral = true
	players.append(np)

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
	# 중립 무리: 기지 근처 유충(소형), 측면 거미(중형), 중앙 고목을 지키는 사마귀(대형)
	for c in [[Vector2(640, 600), ["grub", "grub"]], [Vector2(640, 1400), ["grub", "grub"]],
			[Vector2(1200, 640), ["spider"]], [Vector2(1200, 1360), ["spider"]]]:
		_add_camp(c[0], c[1])
		_add_camp(_mirror(c[0]), c[1])
	_add_camp(Vector2(1600, 880), ["mantis"])
	drop_rng.seed = 11
	var starts = [start, _mirror(start)]
	for i in 2:
		var nest = spawn_building(i, "nest", starts[i], true, true)
		nest.rally_node = nearest_node(nest.position, "food", null)
		for k in Data.START_WORKERS:
			var u = spawn_unit(i, "worker", starts[i] + Vector2(60, 0).rotated(k * TAU / Data.START_WORKERS))
			if not players[i].is_ai:
				# 시작 일꾼 6기 중 4기는 식량, 2기는 재료로 보낸다
				var res = "food"
				if k >= 4:
					res = "mat"
				var n = nearest_node(nest.position, res, null)
				if n != null:
					u.cmd_gather(n)

func _add_node(kind, pos):
	var n = NodeScript.new()
	n.setup(self, kind, pos)
	world.add_child(n)
	res_nodes.append(n)
	return n

func _add_camp(pos, kinds):
	camps.append({"pos": pos, "kinds": kinds, "units": [], "respawn": 0.0})
	_spawn_camp(camps.size() - 1)

func _spawn_camp(ci):
	var c = camps[ci]
	c["units"] = []
	for k in c["kinds"].size():
		var off = Vector2(30, 0).rotated(k * TAU / max(1, c["kinds"].size())) if c["kinds"].size() > 1 else Vector2.ZERO
		var u = spawn_unit(Data.NEUTRAL_ID, c["kinds"][k], c["pos"] + off)
		u.camp = ci
		c["units"].append(u)

func alert_camp(ci, attacker):
	if ci < 0:
		return
	for u in camps[ci]["units"]:
		if is_instance_valid(u) and not u.dead and u.target == null and u.state != UnitScript.ATTACK:
			if u.position.distance_to(u.home) < 80.0:
				u.target = attacker
				u.resume_amove = false
				u.state = UnitScript.ATTACK

func spawn_corpse(pos, amount):
	# 다른 자원 지점과 겹치지 않게 살짝 비켜 놓는다
	for i in 8:
		var ok = true
		for n in res_nodes:
			if n.position.distance_to(pos) < n.radius + 30.0:
				ok = false
				break
		if ok:
			break
		pos += Vector2(30, 0).rotated(i * 1.7)
	var n = _add_node("corpse", pos)
	n.set_amount(amount)
	return n

func _tick_map(delta):
	for ci in camps.size():
		var c = camps[ci]
		var alive = false
		for u in c["units"]:
			if is_instance_valid(u) and not u.dead:
				alive = true
		if alive:
			continue
		if c["respawn"] <= 0.0:
			c["respawn"] = Data.NEUTRAL_RESPAWN
		else:
			c["respawn"] -= delta
			if c["respawn"] <= 0.0:
				_spawn_camp(ci)
	drop_t += delta
	if drop_t >= Data.CENTER_DROP_EVERY:
		drop_t = 0.0
		var pos = Vector2(1600 + drop_rng.randf_range(-160, 160), 1000 + drop_rng.randf_range(-320, 320))
		spawn_corpse(pos, Data.CENTER_DROP_AMOUNT)
		if not autotest:
			msg("맵 중앙에 큰 사체가 떨어졌습니다")

func on_aphid_slain(n, pid):
	if pid == human_id and not autotest:
		msg("진딧물 도살: 식량 +%d" % int(Data.APHID_SLAY_FOOD))
	elif not autotest and fog.is_explored_at(n.position):
		var mine = nearest_nest(human_id, n.position)
		if mine != null and mine.position.distance_to(n.position) < 700.0:
			msg("진딧물 군락이 도살당했습니다")

func spawn_unit(pid, kind, pos):
	var u = UnitScript.new()
	u.setup(self, pid, kind, pos)
	u.z_index = 5
	if u.air:
		u.z_index = 8
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
	for cu in u.cargo.duplicate():
		if is_instance_valid(cu) and not cu.dead:
			cu.dead = true
			remove_unit(cu)
	u.cargo.clear()
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
	if b.kind == "lab":
		# 완료한 연구는 유지되고, 진행 중이거나 예약한 연구는 전액 환불
		b.refund_queue()
	if b.kind == "nest" and b.is_main:
		# 여왕 계승: 가장 가까운 위성 둥지가 주 둥지가 되고 등급이 1단계 내려간다
		var best = null
		for o in buildings:
			if o.pid == b.pid and o.kind == "nest" and o.built:
				if best == null or o.position.distance_to(b.position) < best.position.distance_to(b.position):
					best = o
		if best != null:
			best.is_main = true
			if p.has("multiqueen"):
				best.tier = b.tier
				if b.pid == human_id:
					msg("주 둥지가 파괴되었습니다. 다여왕 군체: 즉시 계승")
			else:
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
	detectors.clear()
	for b in buildings:
		if b.kind == "nest" and b.built:
			if not detectors.has(b.pid):
				detectors[b.pid] = []
			detectors[b.pid].append([b.position, Data.DETECT_NEST])
	for u in units:
		if u.detect_range() > 0.0 and not u.carried:
			if not detectors.has(u.pid):
				detectors[u.pid] = []
			detectors[u.pid].append([u.position, u.detect_range()])
	for u in units:
		if u.carried:
			continue
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

func tyrant_near(pos, pid):
	for u in query_units(pos, Data.TYRANT_AURA):
		if u.pid == pid and u.kind == "tyrant":
			return true
	return false

func is_detected(e, by_pid):
	if not detectors.has(by_pid):
		return false
	for dd in detectors[by_pid]:
		if dd[0].distance_to(e.position) <= dd[1]:
			return true
	return false

# 공격할 수 있는 적인가: 은신 중이면 감지되어야 하고, 중립 생물은 나를 공격하고 있을 때만
func is_hostile_target(u, pid):
	if u.pid == pid or u.dead:
		return false
	if u.stealthed and not is_detected(u, pid):
		return false
	if u.is_neutral and pid != Data.NEUTRAL_ID:
		var t = u.target
		return t != null and is_instance_valid(t) and t.get("pid") == pid
	return true

func find_enemy_unit(pos, pid, r, hits_air = true):
	var best = null
	var bd = r
	for u in query_units(pos, r):
		if is_hostile_target(u, pid) and (hits_air or not u.air):
			var dd = u.position.distance_to(pos)
			if dd <= bd:
				bd = dd
				best = u
	return best

func find_enemy(pos, pid, r, hits_air = true):
	var u = find_enemy_unit(pos, pid, r, hits_air)
	if u != null:
		return u
	var best = null
	var bd = r
	for b in buildings:
		if b.pid != pid and not b.dead and pid != Data.NEUTRAL_ID and not (b.stealthed and not is_detected(b, pid)):
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

# ---------- 수관 영역 (베짜기개미) ----------

func has_territory(pid):
	return Data.FACTIONS[players[pid].faction].get("territory", false) if Data.FACTIONS.has(players[pid].faction) else false

func _update_territory(delta):
	terr_t -= delta
	if terr_t > 0.0:
		return
	var dt = 0.25 - terr_t
	terr_t = 0.25
	curtains.clear()
	for u in units:
		if u.rooted and u.d.get("curtain", false) and not u.dead:
			curtains.append([u.position, u.pid, u.terr >= 1])
	var alive_ids = {}
	for p in players:
		if p.neutral or not has_territory(p.id):
			terr_nodes.erase(p.id)
			continue
		var nodes = []
		var root = -1
		for b in buildings:
			if b.pid == p.id and b.built and not b.dead:
				if b.kind == "nest" and b.is_main:
					root = nodes.size()
				nodes.append({"pos": b.position, "r": Data.TERR_RADIUS[b.kind], "ok": false, "build": true, "id": b.get_instance_id(), "ent": b})
		for u in units:
			if u.pid == p.id and u.d.has("territory") and not u.dead and not u.carried:
				nodes.append({"pos": u.position, "r": u.d["territory"], "ok": false, "build": false, "id": u.get_instance_id(), "ent": null})
		# 주 둥지에서 출발해 영역이 맞닿은 고리를 따라 번져 나간다
		var mult = Data.CHAIN_LINK_MULT if p.has("living_chain") else 1.0
		if root >= 0:
			nodes[root]["ok"] = true
			var todo = [root]
			while todo.size() > 0:
				var i = todo.pop_back()
				for j in nodes.size():
					if not nodes[j]["ok"] and nodes[i]["pos"].distance_to(nodes[j]["pos"]) <= (nodes[i]["r"] + nodes[j]["r"]) * mult:
						nodes[j]["ok"] = true
						todo.append(j)
		for n in nodes:
			alive_ids[n["id"]] = true
			if n["ok"]:
				terr_lost.erase(n["id"])
			else:
				terr_lost[n["id"]] = terr_lost.get(n["id"], 0.0) + dt
				# 살아있는 사슬: 끊어진 뒤에도 잠시 보너스 유지
				if p.has("living_chain") and terr_lost[n["id"]] < Data.CHAIN_GRACE:
					n["ok"] = true
			if n["ent"] != null:
				n["ent"].net_ok = n["ok"]
		terr_nodes[p.id] = nodes
	for id in terr_lost.keys():
		if not alive_ids.has(id):
			terr_lost.erase(id)
	terr_layer.queue_redraw()

# 2 = 주 둥지와 연결된 영역 안, 1 = 끊어진 영역 안, 0 = 영역 밖, -1 = 영역을 쓰지 않는 진영
func territory_state(pid, pos):
	if not terr_nodes.has(pid):
		return -1 if not has_territory(pid) else 0
	var best = 0
	for n in terr_nodes[pid]:
		if pos.distance_to(n["pos"]) <= n["r"]:
			if n["ok"]:
				return 2
			best = 1
	return best

# 건물을 지을 수 있는 영역(건물이 만든 영역만. 수관 군주·유충 운반공의 임시 영역은 제외)
func in_build_territory(pid, pos):
	if not terr_nodes.has(pid):
		return false
	for n in terr_nodes[pid]:
		if n["build"] and pos.distance_to(n["pos"]) <= n["r"]:
			return true
	return false

func curtain_factor(u):
	for c in curtains:
		if c[1] != u.pid and c[0].distance_to(u.position) <= Data.CURTAIN_RADIUS:
			if not u.air:
				return Data.CURTAIN_SLOW
			elif c[2]:
				return Data.CURTAIN_AIR_SLOW
	return 1.0

func curtain_cover(u):
	for c in curtains:
		if c[1] == u.pid and c[0].distance_to(u.position) <= Data.CURTAIN_RADIUS:
			return true
	return false

# 범위 공격: 맞은 대상 주변의 다른 적에게 피해
func splash(attacker, target, radius, dmg):
	for u in query_units(target.position, radius):
		if u != target and is_hostile_target(u, attacker.pid) and (attacker.hits_air or not u.air):
			u.take_damage(dmg, attacker)

func add_zone(pos, time, pid, radius, dps, _kind):
	zones.append([pos, time, pid, radius, dps])

func _tick_zones(delta):
	for z in zones:
		z[1] -= delta
		for u in query_units(z[0], z[3]):
			if u.pid != z[2] and not u.air and not u.is_neutral:
				u.take_damage(z[4] * delta, null)
	zones = zones.filter(func(z): return z[1] > 0.0)

# 유충 운반공: 주변 아군 건물 수리
func carrier_pulse(m, dt):
	for b in buildings:
		if b.pid == m.pid and b.built and b.hp < b.max_hp and b.position.distance_to(m.position) <= Data.CARRIER_RADIUS + b.radius:
			b.hp = min(b.max_hp, b.hp + Data.CARRIER_REPAIR * dt)

func _draw_territory():
	for pid in terr_nodes:
		var mine = (pid == human_id)
		for n in terr_nodes[pid]:
			if not mine and not fog.is_visible_at(n["pos"]):
				continue
			var c = Color(0.3, 0.8, 0.35) if n["ok"] else Color(0.6, 0.6, 0.6)
			if not mine:
				c = players[pid].color
			terr_layer.draw_circle(n["pos"], n["r"], Color(c.r, c.g, c.b, 0.06))
			terr_layer.draw_arc(n["pos"], n["r"], 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.35), 1.5)

# ---------- 함정턱개미 ----------

func near_own_building(pos, pid, r):
	for b in buildings:
		if b.pid == pid and b.built and b.position.distance_to(pos) <= r + b.radius:
			return true
	return false

# 고독한 사냥꾼: 주변 아군 전투 유닛이 적을수록 강해진다
func lone_factor(u):
	if not players[u.pid].has("lone_hunter") or u.is_worker or not u.can_fight:
		return 1.0
	var n = 0
	for o in query_units(u.position, Data.LONE_RADIUS):
		if o != u and o.pid == u.pid and o.can_fight and not o.is_worker:
			n += 1
	return 1.0 + max(0.0, Data.LONE_BONUS - 0.1 * n)

# 대왕 포식자: 대상 뒤로 이어지는 직선 위의 적에게 피해
func snap_line(u, tpos, dmg, main_target):
	var dir = (tpos - u.position).normalized()
	var a = tpos
	var b = tpos + dir * Data.KING_LINE
	for o in query_units(tpos, Data.KING_LINE + 20.0):
		if o == main_target or not is_hostile_target(o, u.pid) or o.air:
			continue
		var q = Geometry2D.get_closest_point_to_segment(o.position, a, b)
		if q.distance_to(o.position) <= Data.KING_LINE_WIDTH + o.radius:
			o.take_damage(dmg, u)

# 사냥 무리: 짧은 시간 안에 가까이서 턱 타격이 3번 이상 나오면 충격파
var pack_log = []        # [시각, 위치, pid]
func pack_snap(u):
	pack_log = pack_log.filter(func(e): return elapsed - e[0] <= Data.PACK_WINDOW)
	pack_log.append([elapsed, u.position, u.pid])
	var near = pack_log.filter(func(e): return e[2] == u.pid and e[1].distance_to(u.position) <= Data.PACK_RADIUS)
	if near.size() >= Data.PACK_COUNT:
		var c = Vector2.ZERO
		for e in near:
			c += e[1]
		c /= near.size()
		for o in query_units(c, Data.PACK_SHOCK_RADIUS):
			if is_hostile_target(o, u.pid):
				o.take_damage(Data.PACK_SHOCK_DMG, u)
		add_zone(c, 0.3, u.pid, Data.PACK_SHOCK_RADIUS, 0.0, "shock")
		pack_log = pack_log.filter(func(e): return not near.has(e))
		return true
	return false

# 유인병: 주변 적이 일정 시간 자신을 공격하게 만든다
func use_lure(u):
	if u.lure_cd > 0.0 or u.dead:
		return false
	u.lure_cd = Data.LURE_CD
	var n = 0
	for o in query_units(u.position, Data.LURE_RADIUS):
		if o.pid != u.pid and not o.is_neutral and o.can_fight and o.immune_t <= 0.0 and o.can_hit(u):
			o._leave()
			o.target = u
			o.resume_amove = false
			o.state = UnitScript.ATTACK
			o.immune_t = Data.LURE_IMMUNE
			n += 1
	add_zone(u.position, 0.4, u.pid, Data.LURE_RADIUS, 0.0, "lure")
	return n

func bdata(pid, kind):
	return Data.faction_building(players[pid].faction, kind)

func can_place(kind, pos, pid = -1):
	if pid < 0:
		pid = human_id
	var weaver = has_territory(pid)
	# 베짜기개미는 영역 안에만 지을 수 있다(전진 둥지 제외). 대신 수목 위에도 지을 수 있다
	if weaver and kind != "tent" and not in_build_territory(pid, pos):
		return false
	var r = Data.BUILDINGS[kind]["radius"]
	if pos.x < r + 20 or pos.y < r + 20 or pos.x > Data.MAP_SIZE.x - r - 20 or pos.y > Data.MAP_SIZE.y - r - 20:
		return false
	for b in buildings:
		if b.position.distance_to(pos) < r + b.radius + 14.0:
			return false
	if not terrain.can_build(pos, r, weaver):
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
	var d = bdata(pid, kind)
	if kind == "lab":
		if count_buildings(pid, "lab") > 0:
			_say(pid, "연구소는 하나만 지을 수 있습니다")
			return null
		if not has_built(pid, "combat") and not has_built(pid, "defense"):
			_say(pid, "전투 또는 방어 생산 건물이 먼저 필요합니다")
			return null
	if main_tier(pid) < d.get("min_tier", 1):
		_say(pid, "주 둥지 등급이 부족합니다")
		return null
	if kind == "tent" and not p.has("spreading"):
		_say(pid, "뻗어가는 수관 연구가 필요합니다")
		return null
	if not can_place(kind, pos, pid):
		if has_territory(pid) and kind != "tent" and not in_build_territory(pid, pos):
			_say(pid, "수관 영역 안에만 지을 수 있습니다")
		else:
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
	if d.has("needs") and not p.has(d["needs"]):
		_say(b.pid, "%s 연구가 필요합니다" % Data.RESEARCH[d["needs"]]["name"])
		return false
	var food = p.unit_food(id)
	if not p.can_afford(food, d["mat"]):
		_say(b.pid, "자원이 부족합니다")
		return false
	p.pay(food, d["mat"])
	var n = p.batch(id)
	b.queue.append({"type": "unit", "id": id, "time": d["time"], "progress": 0.0, "started": false,
		"pop": d["pop"] / float(d["batch"]) * n, "batch": n, "food": food, "mat": d["mat"]})
	return true

func enqueue_research(b, id):
	var p = players[b.pid]
	var d = Data.RESEARCH[id]
	if not b.built or b.queue.size() >= Data.RESEARCH_QUEUE:
		return false
	var st = research_state(b, id)
	if st != "ok":
		_say(b.pid, research_reason(st, id))
		return false
	if not p.can_afford(d["food"], d["mat"]):
		_say(b.pid, "자원이 부족합니다")
		return false
	p.pay(d["food"], d["mat"])
	b.queue.append({"type": "research", "id": id, "time": d["time"], "progress": 0.0, "started": false,
		"pop": 0.0, "food": d["food"], "mat": d["mat"]})
	sel_version += 1
	return true

func _queued(b, id):
	for it in b.queue:
		if it["id"] == id:
			return true
	return false

# 연구 상태: done / queued / tier / req / taken(분기에서 다른 쪽 선택) / ok
func research_state(b, id):
	var p = players[b.pid]
	var r = Data.RESEARCH[id]
	if r.get("faction", "") != "" and r["faction"] != p.faction:
		return "faction"
	if p.has(id):
		return "done"
	if _queued(b, id):
		return "queued"
	if r["group"] != "":
		for other in Data.RESEARCH:
			if other != id and Data.RESEARCH[other]["group"] == r["group"] and (p.has(other) or _queued(b, other)):
				return "taken"
	if main_tier(b.pid) < r["tier"]:
		return "tier"
	# 선행 연구는 완료했거나 바로 앞에 예약되어 있으면 된다
	if r["req"] != "" and not p.has(r["req"]) and not _queued(b, r["req"]):
		return "req"
	return "ok"

func research_reason(st, id):
	var r = Data.RESEARCH[id]
	match st:
		"done":
			return "이미 완료한 연구입니다"
		"queued":
			return "이미 예약한 연구입니다"
		"taken":
			return "다른 분기 진화를 이미 선택했습니다"
		"faction":
			return "다른 진영의 연구입니다"
		"tier":
			return "주 둥지 %s 등급이 필요합니다" % ["I", "II", "III"][r["tier"] - 1]
		"req":
			return "%s 연구가 먼저 필요합니다" % Data.RESEARCH[r["req"]]["name"]
	return ""

func on_research_done(pid, id):
	if id == "fortress":
		for b in buildings:
			if b.pid == pid:
				b.hp *= Data.FORT_HP
				b.max_hp *= Data.FORT_HP
	if id == "size1" or id == "size2" or id == "flight1":
		for u in units:
			if u.pid == pid:
				u.refresh_hp()
	if pid == human_id and not autotest:
		msg("연구 완료: %s" % Data.RESEARCH[id]["name"])

func on_unit_death(u):
	if u.is_neutral:
		spawn_corpse(u.position, u.d["corpse"])
		return
	if u.is_worker:
		return
	var p = players[u.pid]
	if p.has("alarm"):
		for o in query_units(u.position, Data.ALARM_RADIUS):
			if o.pid == u.pid and o != u and not o.is_worker and o.can_fight:
				o.add_alarm()
	if u.kind == "stinger" or u.kind == "soldier":
		var nurse_near = false
		for o in query_units(u.position, Data.NURSE_RADIUS):
			if o.pid == u.pid and o.kind == "nurse":
				nurse_near = true
				break
		if nurse_near:
			# 가장 가까운, 유닛을 생산 중인 건물의 진행도를 앞당긴다
			var best = null
			for b in buildings:
				if b.pid == u.pid and b.built and b.kind != "lab" and b.queue.size() > 0 and b.queue[0]["started"] and b.queue[0]["type"] == "unit":
					if best == null or b.position.distance_to(u.position) < best.position.distance_to(u.position):
						best = b
			if best != null:
				best.queue[0]["progress"] += Data.NURSE_REFUND

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
		if not u.visible:
			continue
		var dd = u.position.distance_to(pos)
		if dd < bd:
			bd = dd
			best = u
	if best != null:
		return best
	for b in buildings:
		if b.visible and b.position.distance_to(pos) <= b.radius:
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
			txt += "\n식량 %d" % p.unit_food(id)
			if d["mat"] > 0:
				txt += " 재료 %d" % d["mat"]
			var n = p.batch(id)
			if n != d["batch"]:
				txt = txt.replace("×%d" % d["batch"], "×%d" % n)
			var tip = "인구 %s, %d초" % [str(d["pop"] / float(d["batch"]) * n), int(d["time"])]
			var ok = main_tier(human_id) >= d["tier"]
			if not ok:
				tip = "주 둥지 %s 등급 필요\n" % ["I", "II", "III"][d["tier"] - 1] + tip
			if d.has("needs") and not p.has(d["needs"]):
				ok = false
				tip = "%s 연구 필요\n" % Data.RESEARCH[d["needs"]]["name"] + tip
			cmds.append({"text": txt, "tip": tip, "enabled": ok, "call": enqueue_unit.bind(b, id)})
		if b.garden_slots() > 0:
			cmds.append({"text": "정원사 추가\n%d / %d" % [b.gardeners.size(), b.garden_slots()],
				"tip": "가장 가까운 일꾼을 균류 정원에 넣는다. 정원사 1기가 분당 재료 45 를 식량 %d 으로 바꾼다" % int(45 * p.garden_ratio()),
				"enabled": b.gardeners.size() < b.garden_slots(), "call": _add_gardener.bind(b)})
			cmds.append({"text": "정원사 빼기", "tip": "정원사 1기를 밖으로 내보낸다", "enabled": b.gardeners.size() > 0,
				"call": func(): b.release_gardener(); sel_version += 1})
		if b.kind == "nest" and b.is_main and p.has("war_fungus"):
			var txt2 = "포자 갑옷\n식량 %d" % Data.WAR_FUNGUS_FOOD
			if p.war_cd > 0.0:
				txt2 = "포자 갑옷\n%d초" % int(ceil(p.war_cd))
			cmds.append({"text": txt2, "tip": "전 병력이 피해 %d 을 흡수하는 갑옷을 %d초 동안 두른다" % [int(Data.WAR_FUNGUS_SHIELD), int(Data.WAR_FUNGUS_TIME)],
				"enabled": p.war_cd <= 0.0, "call": use_war_fungus.bind(b.pid)})
		if b.kind == "nest" and b.is_main and b.tier < 3 and b.upgrade_t < 0.0:
			var up = Data.NEST_UPGRADE[b.tier + 1]
			cmds.append({"text": "둥지 등급 상승\n재료 %d" % up["mat"], "tip": "상위 유닛과 인구 한도 해금",
				"enabled": true, "call": start_upgrade.bind(b)})
		if b.kind == "lab":
			for tab in [["body", "신체 진화"], ["colony", "군체 진화"], ["unique", "고유 진화"]]:
				var label = tab[1]
				if lab_tab == tab[0]:
					label = "▶ " + label
				cmds.append({"text": label, "tip": "", "enabled": true, "call": _set_lab_tab.bind(tab[0])})
			cmds.append({"text": "마지막 예약 취소", "tip": "전액 환불", "enabled": b.queue.size() > 0, "call": cancel_last.bind(b)})
			cmds.append({"text": "", "tip": "", "enabled": false, "blank": true, "call": func(): pass})
			var shown = {}
			for id in Data.RESEARCH:
				var r = Data.RESEARCH[id]
				if r["cat"] != lab_tab or shown.has(r["line"]):
					continue
				var st = research_state(b, id)
				if st == "done" or st == "queued" or st == "faction":
					continue
				# 단계가 있는 연구는 다음 단계 하나만 보여 준다
				shown[r["line"]] = true
				var t2 = "%s\n재료 %d" % [r["name"], r["mat"]]
				if r["food"] > 0:
					t2 += " 식량 %d" % r["food"]
				var tip = "%s (%d초)" % [r["tip"], int(r["time"])]
				if st != "ok":
					tip = research_reason(st, id) + "\n" + tip
				cmds.append({"text": t2, "tip": tip, "enabled": st == "ok", "call": enqueue_research.bind(b, id)})
			return cmds
		if b.queue.size() > 0:
			cmds.append({"text": "마지막 예약 취소", "tip": "전액 환불", "enabled": true, "call": cancel_last.bind(b)})
		return cmds
	var has_worker = false
	var has_root = false
	for u in sel_units():
		if u.is_worker:
			has_worker = true
		if u.d.get("root", false):
			has_root = true
	if has_worker:
		var kinds = ["nest", "combat", "defense", "special", "lab"]
		if p.has("spreading"):
			kinds.append("tent")
		for k in kinds:
			var d2 = bdata(human_id, k)
			var nm = d2["name"]
			if k == "nest":
				nm += " (위성)"
			cmds.append({"text": "%s\n재료 %d" % [nm, d2["mat"]], "tip": "지을 자리를 클릭",
				"enabled": main_tier(human_id) >= d2.get("min_tier", 1), "call": _enter_build.bind(k)})
	var has_cargo = false
	for u in sel_units():
		if u.cargo.size() > 0:
			has_cargo = true
	var lures = sel_units().filter(func(x): return x.d.get("lure", false))
	if lures.size() > 0:
		var ready = lures.filter(func(x): return x.lure_cd <= 0.0)
		var txt3 = "경보 페로몬"
		if ready.is_empty():
			txt3 += "\n%d초" % int(ceil(lures.map(func(x): return x.lure_cd).min()))
		cmds.append({"text": txt3, "tip": "주변 %d 안의 적이 %d초 동안 유인병을 공격한다. 같은 적은 %d초 동안 다시 끌리지 않는다" % [int(Data.LURE_RADIUS), int(Data.LURE_TIME), int(Data.LURE_IMMUNE)],
			"enabled": not ready.is_empty(), "call": func(): use_lure(ready[0]); sel_version += 1})
	if has_cargo:
		cmds.append({"text": "하선", "tip": "타고 있는 유닛을 주변 땅에 내린다", "enabled": true, "call": _unload})
	elif has_root:
		cmds.append({"text": "거점화 / 해제", "tip": "이동 불가, 받는 피해 60% 감소",
			"enabled": true, "call": _toggle_root})
	return cmds

func _unload():
	for u in sel_units():
		if u.cargo.size() > 0 and not u.unload():
			msg("땅 가까이에서만 내릴 수 있습니다")
	sel_version += 1

func _add_gardener(b):
	var best = null
	for u in units:
		if u.pid == b.pid and u.is_worker and not u.carried and u.state != UnitScript.BUILD and u.state != UnitScript.GARDEN:
			if best == null or u.position.distance_to(b.position) < best.position.distance_to(b.position):
				best = u
	if best == null:
		msg("내보낼 일꾼이 없습니다")
		return
	best.cmd_garden(b)

func use_war_fungus(pid):
	var p = players[pid]
	if not p.has("war_fungus") or p.war_cd > 0.0:
		return false
	if not p.can_afford(Data.WAR_FUNGUS_FOOD, 0):
		_say(pid, "식량이 부족합니다")
		return false
	p.pay(Data.WAR_FUNGUS_FOOD, 0)
	p.war_cd = Data.WAR_FUNGUS_COOLDOWN
	for u in units:
		if u.pid == pid and not u.is_worker and u.can_fight:
			u.shield = Data.WAR_FUNGUS_SHIELD
			u.shield_t = Data.WAR_FUNGUS_TIME
	sel_version += 1
	return true

# 공생균 살포병: 주변 아군 유닛(항생 공생균이면 건물도) 회복
func medic_pulse(m, dt):
	for u in query_units(m.position, Data.MEDIC_RADIUS):
		if u.pid == m.pid and u.hp < u.max_hp:
			u.hp = min(u.max_hp, u.hp + Data.MEDIC_HEAL * dt)
	if players[m.pid].has("antibiotic"):
		for b in buildings:
			if b.pid == m.pid and b.built and b.hp < b.max_hp and b.position.distance_to(m.position) <= Data.MEDIC_RADIUS + b.radius:
				b.hp = min(b.max_hp, b.hp + Data.MEDIC_HEAL * dt)

func pathfinder_near(pos, pid):
	for u in query_units(pos, Data.PATHFINDER_RADIUS):
		if u.pid == pid and u.kind == "pathfinder":
			return true
	return false

# 포자 지대: 적의 건물과 거점화 유닛에 지속 피해
func add_spore_zone(pos, pid):
	spore_zones.append([pos, Data.SPORE_ZONE_TIME, pid])

func _tick_spores(delta):
	for z in spore_zones:
		z[1] -= delta
		for b in buildings:
			if b.pid != z[2] and b.pid != Data.NEUTRAL_ID and not b.dead and b.position.distance_to(z[0]) <= Data.SPORE_ZONE_RADIUS + b.radius:
				b.take_damage(Data.SPORE_ZONE_DPS * delta, null)
		for u in query_units(z[0], Data.SPORE_ZONE_RADIUS):
			if u.pid != z[2] and u.rooted:
				u.take_damage(Data.SPORE_ZONE_DPS * delta, null)
	spore_zones = spore_zones.filter(func(z): return z[1] > 0.0)

func _set_lab_tab(tab):
	lab_tab = tab
	sel_version += 1

func _toggle_root():
	# 하나라도 풀려 있으면 전부 거점화, 모두 거점화 상태면 전부 해제
	var any_free = false
	for u in sel_units():
		if u.d.get("root", false) and not u.rooted:
			any_free = true
	for u in sel_units():
		if u.d.get("root", false) and u.rooted != any_free:
			u.toggle_root()

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
		var has_units = sel_units().size() > 0
		if ev.keycode == KEY_A and has_units:
			amove_armed = true
			build_mode = ""
		elif ev.keycode == KEY_S and has_units:
			for u in sel_units():
				u.cmd_stop()
		elif ev.keycode == KEY_ESCAPE:
			if build_mode != "" or amove_armed:
				build_mode = ""
				amove_armed = false
			else:
				set_selection([])
		elif HOTKEYS.has(ev.keycode):
			hud.press_button(HOTKEYS.find(ev.keycode))

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
		if u.pid == human_id and not u.carried and rect.has_point(u.position):
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
			elif e.attackable() and u.can_fight and u.can_hit(e):
				u.cmd_attack(e)
			else:
				rest.append(u)
		order_move(rest, wp, false)
	elif e != null and e is UnitScript and e.pid == human_id and e.kind == "raft":
		for u in us:
			if u != e:
				u.cmd_board(e)
	elif e != null and e is BuildingScript and e.pid == human_id and e.built and e.garden_slots() > 0 and us.any(func(x): return x.is_worker):
		for u in us:
			if u.is_worker:
				u.cmd_garden(e)
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
	fog_t -= real
	if fog_t <= 0.0:
		fog_t = 0.15
		_update_fog()
	overlay.queue_redraw()

func _update_fog():
	fog.recompute(self, human_id)
	for u in units:
		if u.carried:
			u.visible = false
		elif u.pid == human_id:
			u.visible = true
			u.modulate.a = 0.5 if u.stealthed else 1.0
		else:
			u.visible = fog.is_visible_at(u.position) and (not u.stealthed or is_detected(u, human_id))
	for b in buildings:
		if b.pid == human_id:
			b.visible = true
			b.modulate.a = 0.6 if b.stealthed else 1.0
		elif b.stealthed:
			# 은폐 건물은 감지 범위 안에서 지금 보일 때만 보인다(기억되지 않는다)
			b.visible = fog.is_visible_at(b.position) and is_detected(b, human_id)
		else:
			if fog.is_visible_at(b.position):
				b.seen = true
			b.visible = b.seen
	for n in res_nodes:
		# 사체는 지금 보이는 곳에서만 새로 나타난다
		if n.kind == "corpse" and not n.visible:
			n.visible = fog.is_visible_at(n.position)
		elif n.kind == "corpse" and not fog.is_explored_at(n.position):
			n.visible = false

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
		p.pop_cap += 10.0 * p.level("colony")
		p.pop_cap = min(p.pop_cap, Data.POP_MAX)
		if p.alive and not p.neutral and not has_nest[p.id] and not sandbox:
			_eliminate(p)
	_update_territory(delta)
	_tick_map(delta)
	_tick_spores(delta)
	_tick_zones(delta)
	for p in players:
		if p.war_cd > 0.0:
			p.war_cd -= delta
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
	if sandbox:
		return
	var alive = []
	for p in players:
		if p.alive and not p.neutral:
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
		if p.neutral:
			continue
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
		print("t=%d p%d(%s) food=%d mat=%d pop=%.1f/%d units=%d workers=%d buildings=%d research=%s" % [
			int(elapsed), p.id, p.faction, int(p.food), int(p.mat), p.pop_used, int(p.pop_cap), nu, nw, nb, str(p.research.keys())])

func add_shot(a, b, c):
	shots.append([a, b, 0.12, c])

# ---------- 그리기 ----------

func _draw():
	draw_rect(Rect2(Vector2.ZERO, Data.MAP_SIZE), Color(0.36, 0.29, 0.2))
	for e in decor:
		if terrain.kind_at(e[0]) == TerrainScript.GROUND:
			draw_circle(e[0], e[1], Color(0.36 + e[2], 0.29 + e[2], 0.2 + e[2]))
	var cs = Data.FOG_CELL
	for y in terrain.h:
		for x in terrain.w:
			var k = terrain.cells[y * terrain.w + x]
			if k == TerrainScript.GROUND:
				continue
			var r = Rect2(x * cs, y * cs, cs, cs)
			if k == TerrainScript.TREE:
				draw_rect(r, Color(0.3, 0.3, 0.17))
				draw_circle(r.position + Vector2(cs * 0.5, cs * 0.5), cs * 0.55, Color(0.2, 0.4, 0.18, 0.85))
				draw_circle(r.position + Vector2(cs * 0.3, cs * 0.3), cs * 0.3, Color(0.26, 0.48, 0.22, 0.9))
			else:
				draw_rect(r, terrain.color_of(k))
				if k == TerrainScript.WATER and (x + y) % 3 == 0:
					draw_line(r.position + Vector2(6, cs * 0.5), r.position + Vector2(cs - 6, cs * 0.5), Color(0.35, 0.55, 0.75), 1.5)
				if k == TerrainScript.CLIFF:
					draw_line(r.position + Vector2(4, cs - 4), r.position + Vector2(cs - 4, 4), Color(0.4, 0.37, 0.34), 2.0)
	for e in expansions:
		draw_arc(e, 44.0, 0.0, TAU, 32, Color(1, 1, 1, 0.08), 2.0)

func _draw_overlay():
	for z in zones:
		if fog.is_visible_at(z[0]):
			overlay.draw_circle(z[0], z[3], Color(0.8, 1.0, 0.3, 0.3 * clamp(z[1], 0.0, 1.0)))
	for z in spore_zones:
		if fog.is_visible_at(z[0]):
			overlay.draw_circle(z[0], Data.SPORE_ZONE_RADIUS, Color(0.7, 0.85, 0.4, 0.25 * clamp(z[1], 0.0, 1.0)))
	for s in shots:
		if fog.is_visible_at(s[0]) or fog.is_visible_at(s[1]):
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
