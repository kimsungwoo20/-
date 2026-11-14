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
const ConfigScript = preload("res://scripts/config.gd")
const MapGen = preload("res://scripts/mapgen.gd")
const SfxScript = preload("res://scripts/sfx.gd")

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
var has_depots = {}      # pid -> 운반병이 있는가
var match_mode = "ffa"
var n_players = 2
var pop_max = 200.0
var layout = {}
var map_choice = "auto"
var map_key = "medium"
# ---- 온라인 대전 ----
var net_role = "offline"   # offline / host / client
var ents = {}              # 고유 번호 -> 유닛·건물·자원 지점
var next_nid = 1
var controlled = {}        # 내가 조종할 수 있는 다른 pid(접속이 끊긴 아군)
var transfers = {}         # 방장: 끊긴 pid -> 대신 조종하는 pid
var snap_t = 0.0
var net_research_ver = {}
var lost_shown = false
var camera_set = false
# ---- 그림과 소리 ----
var sfx
var effects = []         # [위치, 남은 시간, 종류, 색]
var pings = []           # 미니맵 경고 표시: [위치, 남은 시간]
var alarm_t = -99.0

var build_mode = ""
var lab_tab = "body"
var amove_armed = false
var dragging = false
var drag_from = Vector2.ZERO
var pan_drag = false

func _ready():
	autotest = OS.get_cmdline_user_args().has("--autotest")
	sandbox = OS.get_cmdline_user_args().has("--sandbox")
	var net = get_node_or_null("/root/Net")
	if net != null and net.is_online() and ConfigScript.setup != null and ConfigScript.setup.get("online", false):
		net_role = net.role
		net.game = self
		tree_exiting.connect(func(): if net.game == self: net.game = null)
		net.left.connect(_on_net_left)
	_setup_players()
	map_key = Data.map_key(map_choice, n_players)
	Data.MAP_SIZE = Data.MAP_SIZES[map_key]["size"]
	layout = MapGen.make(n_players, map_key)
	terrain = TerrainScript.new()
	terrain.setup(layout["terrain"])
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
	sfx = SfxScript.new()
	add_child(sfx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.zoom = Vector2(1.25, 1.25)
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

# 판 설정: 방 화면(Config.setup) > 실행 인자 > 웹 주소 > 기본값(나 불개미, 상대 잎꾼개미)
# 실행 인자: --p0=leaf --p1=fire / --players=fire,leaf,trap --teams=0,0,1 --diffs=hard,easy,normal
func _match_setup():
	if ConfigScript.setup != null:
		return ConfigScript.setup
	var slots = [{"type": "human", "faction": "fire", "team": 0, "diff": "normal"},
		{"type": "ai", "faction": "leaf", "team": 1, "diff": "normal"}]
	var mode = "ffa"
	var map_arg = "auto"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--p0="):
			slots[0]["faction"] = a.substr(5)
		elif a.begins_with("--p1="):
			slots[1]["faction"] = a.substr(5)
		elif a.begins_with("--players="):
			var fs = a.substr(10).split(",")
			slots = []
			for i in fs.size():
				slots.append({"type": "human" if i == 0 else "ai", "faction": fs[i], "team": i, "diff": "normal"})
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--teams="):
			var ts = a.substr(8).split(",")
			mode = "team"
			for i in min(ts.size(), slots.size()):
				slots[i]["team"] = int(ts[i])
		elif a.begins_with("--diffs="):
			var ds = a.substr(8).split(",")
			for i in min(ds.size(), slots.size()):
				slots[i]["diff"] = ds[i]
		elif a.begins_with("--map="):
			map_arg = a.substr(6)
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		for part in q.trim_prefix("?").split("&"):
			var kv = part.split("=")
			if kv.size() == 2 and kv[0] == "me":
				slots[0]["faction"] = kv[1]
			elif kv.size() == 2 and kv[0] == "ai":
				slots[1]["faction"] = kv[1]
			elif kv.size() == 2 and kv[0] == "map":
				map_arg = kv[1]
	return {"mode": mode, "slots": slots, "balance": false, "map": map_arg}

func _setup_players():
	var cfg = _match_setup()
	human_id = cfg.get("me", 0)
	map_choice = cfg.get("map", "auto")
	var slots = cfg["slots"]
	match_mode = cfg["mode"]
	n_players = slots.size()
	pop_max = Data.POP_MAX if n_players <= 3 else Data.POP_MAX_BIG
	for i in Data.MAX_PLAYERS:
		var p = PlayerScript.new()
		p.id = i
		p.color = Data.PLAYER_COLORS[i]
		if i < n_players:
			var sl = slots[i]
			p.faction = sl["faction"] if Data.FACTIONS.has(sl["faction"]) else Data.FACTION_IDS[randi() % Data.FACTION_IDS.size()]
			p.team = sl["team"] if match_mode == "team" else i
			p.diff = sl.get("diff", "normal") if Data.DIFFS.has(sl.get("diff", "normal")) else "normal"
			# human: 이 화면의 사람, remote: 다른 화면의 사람(온라인), ai: 인공지능
			p.is_ai = sl["type"] == "ai" or (autotest and sl["type"] == "human")
			p.label = "인공지능 %d" % i if p.is_ai else sl.get("name", "나")
			if i == human_id and not p.is_ai:
				p.label = "나"
			p.gather_mult = Data.DIFFS[p.diff]["gather"] if p.is_ai else 1.0
		else:
			p.active = false
			p.alive = false
			p.team = 100 + i
		players.append(p)
	# 인원 불균형 보정(팀전): 인원이 적은 팀의 채집 속도를 올린다
	if match_mode == "team" and cfg.get("balance", false):
		var sizes = {}
		for p in players:
			if p.active:
				sizes[p.team] = sizes.get(p.team, 0) + 1
		var biggest = sizes.values().max()
		for p in players:
			if p.active:
				p.gather_mult *= 1.0 + Data.BALANCE_GATHER * (biggest - sizes[p.team])
	for p in players:
		if p.active and p.is_ai and not sandbox and net_role != "client":
			var ai = AIScript.new()
			ai.setup(self, p.id)
			ais.append(ai)
	var np = PlayerScript.new()
	np.id = Data.NEUTRAL_ID
	np.label = "중립"
	np.color = Color(0.55, 0.6, 0.35)
	np.neutral = true
	np.team = 99
	players.append(np)

# 이 플레이어의 팀이 지금 그 자리를 보고 있는가(인공지능이 전장의 안개를 따르는 데 쓴다)
func team_sees(pid, pos):
	for u in units:
		if not u.dead and not u.carried and not u.is_neutral and not is_enemy(u.pid, pid) and u.position.distance_to(pos) <= u.sight():
			return true
	for b in buildings:
		if not b.dead and not is_enemy(b.pid, pid) and b.position.distance_to(pos) <= b.sight():
			return true
	return false

# 서로 적인가: 다른 팀이면 적. 중립 생물은 모두와 적
func is_enemy(a, b):
	return a != b and players[a].team != players[b].team

func _mirror(p):
	return Vector2(Data.MAP_SIZE.x - p.x, p.y)

func _setup_map():
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	# 바닥 장식은 지도 넓이에 비례
	for i in int(400 * Data.MAP_SIZE.x * Data.MAP_SIZE.y / (3200.0 * 2000.0)):
		decor.append([Vector2(rng.randf() * Data.MAP_SIZE.x, rng.randf() * Data.MAP_SIZE.y), rng.randf_range(2.0, 7.0), rng.randf_range(-0.05, 0.05)])
	expansions = layout["expansions"].duplicate()
	# 참가자 화면: 자원 지점·유닛·건물은 방장이 보내는 상태로 만든다
	if net_role == "client":
		return
	for e in layout["nodes"]:
		_add_node(e[0], e[1])
	# 중립 무리: 기지 근처 유충(소형), 기지 사이 거미(중형), 중앙 고목을 지키는 사마귀(대형)
	for c in layout["camps"]:
		_add_camp(c[0], c[1])
	drop_rng.seed = 11
	var starts = layout["starts"]
	for i in n_players:
		var nest = spawn_building(i, "nest", starts[i], true, true)
		nest.rally_node = nearest_node(nest.position, "food", null, i)
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

func _new_nid(e, nid):
	if nid == 0:
		nid = next_nid
		next_nid += 1
	e.nid = nid
	ents[nid] = e

func _add_node(kind, pos, nid = 0):
	var n = NodeScript.new()
	n.setup(self, kind, pos)
	_new_nid(n, nid)
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
		var pos = Data.MAP_SIZE / 2.0 + Vector2(drop_rng.randf_range(-160, 160), drop_rng.randf_range(-320, 320))
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

func spawn_unit(pid, kind, pos, nid = 0):
	var u = UnitScript.new()
	u.setup(self, pid, kind, pos)
	_new_nid(u, nid)
	u.z_index = 5
	if u.air:
		u.z_index = 8
	world.add_child(u)
	units.append(u)
	return u

func spawn_building(pid, kind, pos, finished, main, nid = 0):
	var b = BuildingScript.new()
	b.setup(self, pid, kind, pos, finished, main)
	_new_nid(b, nid)
	b.set_blocking(true)
	b.z_index = 2
	world.add_child(b)
	buildings.append(b)
	return b

# ---------- 제거 ----------

func remove_unit(u):
	u.drop_bridge()
	for cu in u.cargo.duplicate():
		if is_instance_valid(cu) and not cu.dead:
			cu.dead = true
			remove_unit(cu)
	u.cargo.clear()
	units.erase(u)
	ents.erase(u.nid)
	if selection.has(u):
		selection.erase(u)
		sel_version += 1
	u.queue_free()

func remove_res_node(n):
	n.gone = true
	res_nodes.erase(n)
	ents.erase(n.nid)
	n.queue_free()

func remove_building(b):
	b.set_blocking(false)
	buildings.erase(b)
	ents.erase(b.nid)
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
	if controls(b.pid) and not autotest and elapsed - alarm_t > 10.0:
		alarm_t = elapsed
		msg("%s 이(가) 공격받고 있습니다" % b.d["name"])
		play("alarm")
		pings.append([b.position, 3.0])
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
	has_depots.clear()
	for u in units:
		if u.d.get("depot", false):
			has_depots[u.pid] = true
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

# 감지는 팀이 함께 쓴다
func is_detected(e, by_pid):
	for q in detectors:
		if q != by_pid and is_enemy(q, by_pid):
			continue
		for dd in detectors[q]:
			if dd[0].distance_to(e.position) <= dd[1]:
				return true
	return false

# 공격할 수 있는 적인가: 은신 중이면 감지되어야 하고, 중립 생물은 나를 공격하고 있을 때만
func is_hostile_target(u, pid):
	if u.dead or not is_enemy(u.pid, pid):
		return false
	if u.stealthed and not is_detected(u, pid):
		return false
	if u.is_neutral and pid != Data.NEUTRAL_ID:
		# 중립 생물은 우리 팀을 공격하고 있을 때만 자동으로 상대한다
		var t = u.target
		return t != null and is_instance_valid(t) and t.get("pid") != null and not is_enemy(t.pid, pid)
	return true

func find_enemy_unit(pos, pid, r, hits_air = true, air_only = false):
	var best = null
	var bd = r
	for u in query_units(pos, r):
		if is_hostile_target(u, pid) and (hits_air or not u.air) and (u.air or not air_only):
			var dd = u.position.distance_to(pos)
			if dd <= bd:
				bd = dd
				best = u
	return best

func find_enemy(pos, pid, r, hits_air = true, air_only = false):
	var u = find_enemy_unit(pos, pid, r, hits_air, air_only)
	if u != null or air_only:
		return u
	var best = null
	var bd = r
	for b in buildings:
		if is_enemy(b.pid, pid) and not b.dead and pid != Data.NEUTRAL_ID and not (b.stealthed and not is_detected(b, pid)):
			var dd = b.position.distance_to(pos) - b.radius
			if dd <= bd:
				bd = dd
				best = b
	return best

func nearest_nest(pid, pos):
	var best = null
	var bd = 1e12
	for b in buildings:
		if b.pid == pid and b.kind == "nest" and b.built and not b.dead and b.camped():
			var dd = b.position.distance_squared_to(pos)
			if dd < bd:
				bd = dd
				best = b
	# 운반병은 이동식 반납 지점이다
	if has_depots.get(pid, false):
		for u in units:
			if u.pid == pid and u.d.get("depot", false) and not u.dead and not u.carried:
				var dd = u.position.distance_squared_to(pos)
				if dd < bd:
					bd = dd
					best = u
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
func nearest_node(pos, res, who, pid = -1):
	if who != null:
		pid = who.pid
	var no_aphid = pid >= 0 and Data.FACTIONS.get(players[pid].faction, {}).get("no_aphid", false)
	var best = null
	var bs = 1e12
	for n in res_nodes:
		if n.res_type() != res or not n.available():
			continue
		if no_aphid and n.kind == "aphid":
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
	amount *= p.gather_mult
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
		if is_enemy(c[1], u.pid) and c[0].distance_to(u.position) <= Data.CURTAIN_RADIUS:
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
			if is_enemy(u.pid, z[2]) and not u.air and not u.is_neutral:
				u.take_damage(z[4] * delta, null)
	zones = zones.filter(func(z): return z[1] > 0.0)

# 유충 운반공: 주변 아군 건물 수리
func carrier_pulse(m, dt):
	for b in buildings:
		if b.pid == m.pid and b.built and b.hp < b.max_hp and b.position.distance_to(m.position) <= Data.CARRIER_RADIUS + b.radius:
			b.hp = min(b.max_hp, b.hp + Data.CARRIER_REPAIR * dt)

func _draw_bridges():
	var t = terrain
	var cs = Data.FOG_CELL
	for y in t.h:
		for x in t.w:
			if t.bridged[y * t.w + x] > 0:
				var r = Rect2(x * cs, y * cs, cs, cs)
				terr_layer.draw_rect(r, Color(0.55, 0.4, 0.22, 0.9))
				terr_layer.draw_line(r.position + Vector2(0, cs * 0.5), r.position + Vector2(cs, cs * 0.5), Color(0.35, 0.25, 0.12), 2.0)

func _draw_territory():
	_draw_bridges()
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

# ---------- 군대개미 ----------

func near_marching_building(pos, pid, r):
	for b in buildings:
		if b.pid == pid and b.built and not b.camped() and b.position.distance_to(pos) <= r + b.radius:
			return true
	return false

# 행군 중인 건물이 지금 자리에 야영할 수 있는가
func can_camp(b):
	if not terrain.can_build(b.position, b.radius):
		return false
	for o in buildings:
		if o != b and o.camped() and o.position.distance_to(b.position) < b.radius + o.radius + 8.0:
			return false
	for n in res_nodes:
		if n.position.distance_to(b.position) < b.radius + n.radius + 20.0:
			return false
	return true

# 약탈: 군대개미가 적 일꾼·건물(약탈 본능이면 전투 유닛도)을 처치하면 자원을 얻는다
func on_kill(attacker, victim):
	if attacker == null or not is_instance_valid(attacker) or attacker.get("pid") == null:
		return
	var ap = attacker.pid
	# 포식 대군: 무엇이든 처치하면 회복(범위 피해로 처치해도)
	if attacker.get("d") != null and attacker.d.get("feast", false) and not attacker.dead:
		attacker.hp = min(attacker.max_hp, attacker.hp + attacker.max_hp * Data.FEAST_HEAL)
	if ap == Data.NEUTRAL_ID or victim.pid == Data.NEUTRAL_ID or not is_enemy(ap, victim.pid):
		return
	var p = players[ap]
	if not Data.FACTIONS.get(p.faction, {}).get("loot", false):
		return
	var rate = Data.LOOT_RATE_INSTINCT if p.has("loot_instinct") else Data.LOOT_RATE
	var food = 0.0
	var mat = 0.0
	if victim is BuildingScript:
		var cost = Data.BUILDINGS[victim.kind]["mat"]
		food = cost * rate
		mat = cost * rate
	elif victim.is_worker:
		food = players[victim.pid].unit_food("worker") * rate
	elif p.has("loot_instinct") and victim.can_fight:
		food = victim.d["food"] / float(victim.d["batch"]) * Data.LOOT_COMBAT_RATE
	if food > 0.0 or mat > 0.0:
		p.food += food
		p.mat += mat
		p.looted += food + mat

func pack_colony(pid, do_pack):
	for b in buildings:
		if b.pid == pid and b.built:
			if do_pack:
				b.pack()
			elif b.mode == "march" and not b.unpack() and pid == human_id:
				msg("%s: 여기에는 야영할 수 없습니다" % b.d["name"])
	sel_version += 1

# 행군 명령. 주 둥지를 움직이면 행군 중인 다른 건물도 대형을 유지하며 따라온다
func order_march(b, pos):
	if b.kind == "nest" and b.is_main:
		for o in buildings:
			if o.pid == b.pid and o != b and (o.mode == "march" or o.mode == "packing"):
				o.march_to(pos + (o.position - b.position))
	return b.march_to(pos)

func _mobile_cmds(b):
	var out = []
	if not b.is_mobile():
		return out
	match b.mode:
		"camp":
			out.append({"text": "행군 준비\n%d초" % int(b.pack_time()), "tip": "건물이 이동할 수 있게 된다. 행군 중에는 생산이 느려지고 일꾼 생산·연구·자원 반납이 멈춘다",
				"enabled": true, "call": act.bind("pack", [b])})
		"packing":
			out.append({"text": "행군 준비 중\n%d초" % int(ceil(b.mode_t)), "tip": "", "enabled": false, "call": func(): pass})
		"march":
			out.append({"text": "야영\n%d초" % int(b.unpack_time()), "tip": "지금 자리에 자리를 잡는다. 오른쪽 클릭으로 이동",
				"enabled": true, "call": act.bind("unpack", [b])})
		"unpacking":
			out.append({"text": "야영 준비 중\n%d초" % int(ceil(b.mode_t)), "tip": "", "enabled": false, "call": func(): pass})
	if b.kind == "nest" and b.is_main:
		out.append({"text": "군체 전체 행군", "tip": "모든 건물이 행군을 준비한다. 주 둥지를 움직이면 다른 건물도 따라온다",
			"enabled": true, "call": act.bind("pack_all", [b])})
		out.append({"text": "군체 전체 야영", "tip": "행군 중인 모든 건물이 지금 자리에 야영한다",
			"enabled": true, "call": act.bind("camp_all", [b])})
	return out

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
		if is_enemy(o.pid, u.pid) and not o.is_neutral and o.can_fight and o.immune_t <= 0.0 and o.can_hit(u):
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
	if autotest:
		return
	if pid == human_id or controlled.has(pid):
		msg(text)
		play("error")
	elif net_role == "host":
		get_node("/root/Net").send_msg(pid, text)

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
	if d.get("pop", 0.0) > 0.0 and p.pop_used + d["pop"] > p.pop_cap + 0.001:
		_say(pid, "인구가 부족합니다 (건물 1동이 인구 %d 차지)" % int(d["pop"]))
		return null
	p.pay(0, d["mat"])
	p.pop_used += d.get("pop", 0.0)
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
		play("research")

func on_unit_death(u):
	play("death", u.position)
	add_effect(u.position, "death", players[u.pid].color if not u.is_neutral else Color(0.6, 0.6, 0.4))
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

# 이 화면의 사람이 조종할 수 있는 pid 인가(자기 자신 + 접속이 끊긴 아군)
func controls(pid):
	return pid == human_id or controlled.has(pid)

func sel_units():
	var out = []
	for e in selection:
		if is_instance_valid(e) and e is UnitScript and controls(e.pid) and not e.dead:
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
	if b != null and controls(b.pid):
		p = players[b.pid]
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
			cmds.append({"text": txt, "tip": tip, "enabled": ok, "call": act.bind("enqueue", [b, id])})
		if b.garden_slots() > 0:
			cmds.append({"text": "정원사 추가\n%d / %d" % [b.garden_count(), b.garden_slots()],
				"tip": "가장 가까운 일꾼을 균류 정원에 넣는다. 정원사 1기가 분당 재료 45 를 식량 %d 으로 바꾼다" % int(45 * p.garden_ratio()),
				"enabled": b.garden_count() < b.garden_slots(), "call": act.bind("garden_add", [b])})
			cmds.append({"text": "정원사 빼기", "tip": "정원사 1기를 밖으로 내보낸다", "enabled": b.garden_count() > 0,
				"call": act.bind("garden_out", [b])})
		if b.kind == "nest" and b.is_main and p.has("war_fungus"):
			var txt2 = "포자 갑옷\n식량 %d" % Data.WAR_FUNGUS_FOOD
			if p.war_cd > 0.0:
				txt2 = "포자 갑옷\n%d초" % int(ceil(p.war_cd))
			cmds.append({"text": txt2, "tip": "전 병력이 피해 %d 을 흡수하는 갑옷을 %d초 동안 두른다" % [int(Data.WAR_FUNGUS_SHIELD), int(Data.WAR_FUNGUS_TIME)],
				"enabled": p.war_cd <= 0.0, "call": act.bind("fungus", [b])})
		if b.kind == "nest" and b.is_main and b.tier < 3 and b.upgrade_t < 0.0:
			var up = Data.NEST_UPGRADE[b.tier + 1]
			cmds.append({"text": "둥지 등급 상승\n재료 %d" % up["mat"], "tip": "상위 유닛과 인구 한도 해금",
				"enabled": true, "call": act.bind("upgrade", [b])})
		if b.kind == "lab":
			for tab in [["body", "신체 진화"], ["colony", "군체 진화"], ["unique", "고유 진화"]]:
				var label = tab[1]
				if lab_tab == tab[0]:
					label = "▶ " + label
				cmds.append({"text": label, "tip": "", "enabled": true, "call": _set_lab_tab.bind(tab[0])})
			cmds.append({"text": "마지막 예약 취소", "tip": "전액 환불", "enabled": b.queue.size() > 0, "call": act.bind("cancel", [b])})
			var mc = _mobile_cmds(b)
			if mc.size() > 0:
				cmds.append(mc[0])
			else:
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
				cmds.append({"text": t2, "tip": tip, "enabled": st == "ok", "call": act.bind("research", [b, id])})
			return cmds
		if b.queue.size() > 0:
			cmds.append({"text": "마지막 예약 취소", "tip": "전액 환불", "enabled": true, "call": act.bind("cancel", [b])})
		cmds.append_array(_mobile_cmds(b))
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
			"enabled": not ready.is_empty(), "call": act.bind("lure", [ready[0]])})
	if has_cargo:
		cmds.append({"text": "하선", "tip": "타고 있는 유닛을 주변 땅에 내린다", "enabled": true, "call": func(): act("unload", [sel_units()])})
	elif has_root:
		cmds.append({"text": "거점화 / 해제", "tip": "이동 불가, 받는 피해 60% 감소",
			"enabled": true, "call": func(): act("root", [sel_units()])})
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
			if is_enemy(b.pid, z[2]) and b.pid != Data.NEUTRAL_ID and not b.dead and b.position.distance_to(z[0]) <= Data.SPORE_ZONE_RADIUS + b.radius:
				b.take_damage(Data.SPORE_ZONE_DPS * delta, null)
		for u in query_units(z[0], Data.SPORE_ZONE_RADIUS):
			if is_enemy(u.pid, z[2]) and u.rooted:
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
					var owner = workers[0].pid if workers.size() > 0 else human_id
					if can_place(build_mode, wp, owner):
						act("build", [build_mode, wp, workers])
						build_mode = ""
					else:
						msg("그 자리에는 지을 수 없습니다")
				elif amove_armed:
					act("move", [sel_units(), wp, true])
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
			act("stop", [sel_units()])
		elif ev.keycode == KEY_M:
			SfxScript.muted = not SfxScript.muted
			msg("소리 끔" if SfxScript.muted else "소리 켬")
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
		if e != null and (e is UnitScript or e is BuildingScript) and controls(e.pid):
			set_selection([e])
			play("select")
		else:
			set_selection([])
		return
	var picked = []
	var any_army = false
	for u in units:
		if controls(u.pid) and not u.carried and rect.has_point(u.position):
			picked.append(u)
			if not u.is_worker:
				any_army = true
	if any_army:
		picked = picked.filter(func(u): return not u.is_worker)
	set_selection(picked)
	if picked.size() > 0:
		play("select")

func _right_click(wp):
	var e = _entity_at(wp)
	var b = sel_building()
	if b != null and controls(b.pid) and b.mode == "camp":
		msg("집결 지점 지정")
	act("rclick", [sel_units(), wp, e, b])

# 오른쪽 클릭의 실제 처리(방장·혼자 하기에서 실행). pid 는 명령을 내린 사람
func _do_rclick(pid, us, wp, e, b):
	if b != null and _owns(pid, b) and (b.mode == "march" or b.mode == "packing"):
		order_march(b, wp)
		return
	if b != null and _owns(pid, b):
		b.rally_pos = wp
		b.rally_node = null
		if e != null and e is NodeScript:
			b.rally_node = e
		return
	if us.is_empty():
		return
	var me = us[0].pid
	if e != null and (e is UnitScript or e is BuildingScript) and is_enemy(e.pid, me):
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
	elif e != null and e is UnitScript and e.pid == me and e.kind == "raft":
		for u in us:
			if u != e:
				u.cmd_board(e)
	elif e != null and e is BuildingScript and e.pid == me and e.built and e.garden_slots() > 0 and us.any(func(x): return x.is_worker):
		for u in us:
			if u.is_worker:
				u.cmd_garden(e)
	elif e != null and e is BuildingScript and e.pid == me and not e.built:
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
	for e in effects:
		e[1] -= delta
	effects = effects.filter(func(e): return e[1] > 0.0)
	for pg in pings:
		pg[1] -= real
	pings = pings.filter(func(pg): return pg[1] > 0.0)
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
		elif not is_enemy(u.pid, human_id):
			u.visible = true
			u.modulate.a = 0.5 if u.stealthed else 1.0
		else:
			u.visible = fog.is_visible_at(u.position) and (not u.stealthed or is_detected(u, human_id))
	for b in buildings:
		if not is_enemy(b.pid, human_id):
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
	if net_role == "client":
		# 참가자: 계산하지 않고 방장이 보낸 상태를 그린다
		_rebuild_grid()
		_update_territory(delta)
		return
	if game_over:
		return
	elapsed += delta
	if net_role == "host":
		snap_t -= delta
		if snap_t <= 0.0:
			snap_t = get_node("/root/Net").SNAP_EVERY
			get_node("/root/Net").send_snapshot(build_snapshot())
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
		p.pop_used += b.reserved_pop + b.pop_cost
		if b.kind == "nest" and b.built:
			has_nest[b.pid] = true
			if b.is_main:
				p.pop_cap += Data.NEST_POP[b.tier - 1]
			else:
				p.pop_cap += Data.SAT_POP
	for p in players:
		p.pop_cap += 10.0 * p.level("colony")
		p.pop_cap = min(p.pop_cap, pop_max)
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
	if not autotest and p.id != human_id:
		msg("%s 탈락" % p.label)
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
	var teams = {}
	for p in players:
		if p.active and p.alive and not p.neutral:
			teams[p.team] = true
	var over = teams.size() <= 1
	# 사람이 탈락하면 그 사람에게는 판이 끝난다(관전 없음)
	if not autotest and not players[human_id].alive:
		if net_role == "host" and not over:
			# 방장은 다른 사람들의 판을 계속 계산해야 하므로 결과만 보여 주고 멈추지 않는다
			if not lost_shown:
				lost_shown = true
				hud.show_game_over(false)
			return
		over = true
	if not over:
		return
	game_over = true
	winner = -1
	if teams.size() == 1:
		winner = teams.keys()[0]
	if autotest:
		print("AUTOTEST over winner_team=%d t=%d" % [winner, int(elapsed)])
		_report()
		get_tree().quit()
	else:
		hud.show_game_over(players[human_id].alive and winner == players[human_id].team)

func _report():
	for p in players:
		if p.neutral:
			continue
		var nu = 0
		var nw = 0
		var army = 0.0
		for u in units:
			if u.pid == p.id:
				nu += 1
				if u.is_worker:
					nw += 1
				elif u.can_fight:
					army += (u.d["food"] + u.d["mat"]) / float(u.d["batch"])
		var nb = 0
		for b in buildings:
			if b.pid == p.id:
				nb += 1
		if not p.active:
			continue
		print("t=%d p%d(%s, 팀 %d, %s) food=%d mat=%d pop=%.1f/%d units=%d workers=%d army=%d spent=%d buildings=%d research=%s" % [
			int(elapsed), p.id, p.faction, p.team, p.diff, int(p.food), int(p.mat), p.pop_used, int(p.pop_cap), nu, nw, int(army), int(p.spent), nb, str(p.research.keys())])

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
			elif k == TerrainScript.WATER:
				# 물: 물가(땅과 닿은 칸)는 밝게, 가운데는 짙게
				var shore = false
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx = x + dd.x
					var ny = y + dd.y
					if nx >= 0 and ny >= 0 and nx < terrain.w and ny < terrain.h and terrain.cells[ny * terrain.w + nx] != TerrainScript.WATER:
						shore = true
				draw_rect(r, Color(0.25, 0.47, 0.62) if shore else Color(0.17, 0.35, 0.52))
				if (x * 7 + y * 3) % 5 == 0:
					draw_arc(r.position + Vector2(cs * 0.5, cs * 0.55), cs * 0.25, PI * 1.15, PI * 1.85, 6, Color(0.55, 0.75, 0.9, 0.6), 1.2)
			else:
				# 절벽: 바위 덩어리
				draw_rect(r, Color(0.27, 0.25, 0.24))
				var h = (x * 13 + y * 7) % 4
				draw_circle(r.position + Vector2(cs * (0.3 + 0.1 * h), cs * 0.4), cs * 0.32, Color(0.36, 0.34, 0.32))
				draw_circle(r.position + Vector2(cs * 0.7, cs * (0.65 - 0.05 * h)), cs * 0.26, Color(0.31, 0.29, 0.28))
				draw_arc(r.position + Vector2(cs * (0.3 + 0.1 * h), cs * 0.4), cs * 0.32, PI * 1.1, PI * 1.6, 5, Color(0.5, 0.48, 0.45), 1.5)
	for e in expansions:
		draw_arc(e, 44.0, 0.0, TAU, 32, Color(1, 1, 1, 0.08), 2.0)

func _draw_overlay():
	for z in zones:
		if fog.is_visible_at(z[0]):
			overlay.draw_circle(z[0], z[3], Color(0.8, 1.0, 0.3, 0.3 * clamp(z[1], 0.0, 1.0)))
	for z in spore_zones:
		if fog.is_visible_at(z[0]):
			overlay.draw_circle(z[0], Data.SPORE_ZONE_RADIUS, Color(0.7, 0.85, 0.4, 0.25 * clamp(z[1], 0.0, 1.0)))
	for e in effects:
		var k = e[1] / 0.5
		if e[2] == "death":
			# 흩어지는 조각
			for i in 6:
				var dir = Vector2(cos(i * 1.05 + e[0].x), sin(i * 1.05 + e[0].y))
				overlay.draw_circle(e[0] + dir * (1.0 - k) * 18.0, 2.2 * k + 0.5, Color(e[3].r, e[3].g, e[3].b, k))
		else:
			overlay.draw_circle(e[0], 3.0 + (1.0 - k) * 6.0, Color(e[3].r, e[3].g, e[3].b, k * 0.8))
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
	if b != null and b.pid == human_id and b.built and b.camped() and b.d["produces"].size() > 0:
		overlay.draw_line(b.position, b.rally_pos, Color(1, 1, 1, 0.3), 1.0)
		overlay.draw_circle(b.rally_pos, 4.0, Color(1, 1, 1, 0.6))


# ---------- 명령 통로 ----------
# 사람의 모든 명령은 여기를 거친다. 참가자 화면에서는 방장에게 보내고, 방장·혼자 하기에서는 바로 실행한다.

func play(name, pos = null):
	if sfx != null and not autotest:
		sfx.play(name, pos, camera if pos != null else null)

func add_effect(pos, kind, col):
	if autotest or not fog.is_visible_at(pos):
		return
	effects.append([pos, 0.5, kind, col])

func act(name, args = []):
	if name in ["move", "stop", "rclick", "build", "enqueue", "research", "upgrade", "root", "unload", "lure", "pack", "unpack", "pack_all", "camp_all", "garden_add", "garden_out", "fungus"]:
		play("order")
	if net_role == "client":
		get_node("/root/Net").send_cmd(name, _encode(args))
		return
	_do_act(human_id, name, args)
	sel_version += 1

func _encode(v):
	if v is Array:
		var out = []
		for x in v:
			out.append(_encode(x))
		return out
	if v is Object and v != null and is_instance_valid(v) and v.get("nid") != null:
		return {"e": v.nid}
	return v

func _decode(v):
	if v is Array:
		var out = []
		for x in v:
			var d = _decode(x)
			if d != null or not (x is Dictionary):
				out.append(d)
		return out
	if v is Dictionary and v.has("e"):
		var e = ents.get(int(v["e"]))
		return e if e != null and is_instance_valid(e) and not e.get("dead") else null
	return v

# pid 가 이 개체를 조종할 수 있는가(자기 것 + 접속이 끊겨 넘겨받은 아군 것)
func _owns(pid, e):
	return e != null and is_instance_valid(e) and (e.pid == pid or transfers.get(e.pid, -1) == pid or (pid == human_id and controlled.has(e.pid)))

func _mine(pid, arr):
	var out = []
	for u in arr:
		if u is UnitScript and _owns(pid, u) and not u.dead:
			out.append(u)
	return out

# 방장: 참가자가 보낸 명령
func net_command(pid, name, args):
	if players[pid].alive:
		_do_act(pid, name, _decode(args))

func _do_act(pid, name, a):
	match name:
		"move":
			order_move(_mine(pid, a[0]), a[1], a[2])
		"stop":
			for u in _mine(pid, a[0]):
				u.cmd_stop()
		"rclick":
			var b = a[3] if a.size() > 3 and _owns(pid, a[3]) else null
			_do_rclick(pid, _mine(pid, a[0]), a[1], a[2], b)
		"build":
			var ws = _mine(pid, a[2])
			var owner = ws[0].pid if ws.size() > 0 else pid
			start_build(owner, a[0], a[1], ws)
		"enqueue":
			if _owns(pid, a[0]):
				enqueue_unit(a[0], a[1])
		"research":
			if _owns(pid, a[0]):
				enqueue_research(a[0], a[1])
		"upgrade":
			if _owns(pid, a[0]):
				start_upgrade(a[0])
		"cancel":
			if _owns(pid, a[0]):
				cancel_last(a[0])
		"root":
			var us = _mine(pid, a[0])
			var any_free = us.any(func(u): return u.d.get("root", false) and not u.rooted)
			for u in us:
				if u.d.get("root", false) and u.rooted != any_free:
					u.toggle_root()
		"unload":
			for u in _mine(pid, a[0]):
				if u.cargo.size() > 0 and not u.unload():
					_say(pid, "땅 가까이에서만 내릴 수 있습니다")
		"garden_add":
			if _owns(pid, a[0]):
				_add_gardener(a[0])
		"garden_out":
			if _owns(pid, a[0]):
				a[0].release_gardener()
		"fungus":
			if _owns(pid, a[0]):
				use_war_fungus(a[0].pid)
		"lure":
			var us = _mine(pid, a)
			if us.size() > 0:
				use_lure(us[0])
		"pack":
			if _owns(pid, a[0]):
				a[0].pack()
		"unpack":
			if _owns(pid, a[0]) and not a[0].unpack():
				_say(pid, "여기에는 야영할 수 없습니다")
		"pack_all":
			if _owns(pid, a[0]):
				pack_colony(a[0].pid, true)
		"camp_all":
			if _owns(pid, a[0]):
				pack_colony(a[0].pid, false)

# ---------- 접속 종료와 재접속 (방장) ----------

func on_player_left(pid):
	if not players[pid].alive:
		return
	# 팀전에서 접속 중인 아군 사람이 있으면 그 아군이 조종한다. 없으면 인공지능이 이어받는다
	var net = get_node("/root/Net")
	var ally = -1
	if match_mode == "team":
		for q in players:
			if q.active and q.alive and q.id != pid and not q.is_ai and not is_enemy(q.id, pid):
				if q.id == human_id or net.pid_peer.has(q.id):
					ally = q.id
					break
	if ally >= 0:
		transfers[pid] = ally
		if ally == human_id:
			controlled[pid] = true
		_announce("%s 의 접속이 끊겨 %s 이(가) 대신 조종합니다" % [players[pid].label, players[ally].label])
	else:
		players[pid].is_ai = true
		var ai = AIScript.new()
		ai.setup(self, pid)
		ais.append(ai)
		_announce("%s 의 접속이 끊겨 인공지능이 대신합니다" % players[pid].label)

func on_player_rejoined(pid):
	transfers.erase(pid)
	controlled.erase(pid)
	ais = ais.filter(func(ai): return ai.pid != pid)
	players[pid].is_ai = false
	_announce("%s 이(가) 다시 들어왔습니다" % players[pid].label)

func _announce(text):
	msg(text)
	var net = get_node_or_null("/root/Net")
	if net != null and net.is_host():
		for pid in net.pid_peer:
			net.send_msg(pid, text)

# ---------- 상태 전송 ----------

const U_FIELDS = 12
const B_FIELDS = 18
const N_FIELDS = 9
var _ukinds = []
var _bkinds = ["nest", "combat", "defense", "special", "lab", "tent"]
var _nkinds = []
const MODES = ["camp", "packing", "march", "unpacking"]

func _kind_tables():
	if _ukinds.is_empty():
		_ukinds = Data.UNITS.keys() + Data.NEUTRALS.keys()
		_nkinds = Data.NODES.keys()

func build_snapshot():
	_kind_tables()
	var uf = PackedFloat32Array()
	for u in units:
		var flags = 0
		if u.rooted: flags |= 1
		if u.stealthed: flags |= 2
		if u.air: flags |= 4
		if u.carried: flags |= 8
		if u.carry > 0.0 and u.carry_res == "food": flags |= 16
		if u.carry > 0.0 and u.carry_res == "mat": flags |= 32
		if u.stun_t > 0.0: flags |= 64
		if u.snap_ready(): flags |= 128
		if u.alarm_stacks > 0: flags |= 256
		if u.pinned_t > 0.0: flags |= 512
		var extra = 0.0
		if u.kind == "raft":
			extra = u.cargo.size()
		elif u.d.get("lure", false):
			extra = max(0.0, u.lure_cd)
		elif u.d.get("bridge", false):
			extra = u.bridge_r
		uf.append_array([u.nid, _ukinds.find(u.kind), u.pid, u.position.x, u.position.y, u.facing,
			u.hp, u.max_hp, flags, extra, u.shield, u.venom_stacks])
	var bf = PackedFloat32Array()
	var queues = {}
	for b in buildings:
		var flags = 0
		if b.built: flags |= 1
		if b.is_main: flags |= 2
		if b.stealthed: flags |= 4
		if b.net_ok: flags |= 8
		bf.append_array([b.nid, _bkinds.find(b.kind), b.pid, b.position.x, b.position.y, b.hp, b.max_hp, flags,
			b.tier, MODES.find(b.mode), b.mode_t, b.build_progress, b.upgrade_t, b.gardeners.size(), b.venom_stacks,
			b.rally_pos.x, b.rally_pos.y, b.pop_cost])
		if b.queue.size() > 0:
			var q = []
			for it in b.queue:
				q.append([it["type"], it["id"], it["progress"], it["time"], it["started"]])
			queues[b.nid] = q
	var nf = PackedFloat32Array()
	for n in res_nodes:
		var flags = 0
		if n.dead: flags |= 1
		nf.append_array([n.nid, _nkinds.find(n.kind), n.position.x, n.position.y, n.amount, flags, n.dormant, n.decay, n.hp])
	var pl = []
	for p in players:
		pl.append([p.food, p.mat, p.pop_used, p.pop_cap, p.alive, p.succession, p.war_cd, p.research.keys(), p.is_ai])
	var zs = PackedFloat32Array()
	for z in zones:
		zs.append_array([z[0].x, z[0].y, z[3], z[1]])
	for z in spore_zones:
		zs.append_array([z[0].x, z[0].y, Data.SPORE_ZONE_RADIUS, z[1]])
	var bridged = PackedInt32Array()
	for i in terrain.bridged.size():
		if terrain.bridged[i] > 0:
			bridged.append(i)
	return {"t": elapsed, "u": uf, "b": bf, "q": queues, "n": nf, "p": pl, "z": zs, "br": bridged,
		"over": game_over, "win": winner, "tr": transfers}

# 참가자: 방장이 보낸 상태대로 개체를 만들고, 고치고, 지운다
func apply_snapshot(s):
	_kind_tables()
	elapsed = s["t"]
	var seen = {}
	var uf = s["u"]
	for i in range(0, uf.size(), U_FIELDS):
		var nid = int(uf[i])
		seen[nid] = true
		var kind = _ukinds[int(uf[i + 1])]
		var pid = int(uf[i + 2])
		var pos = Vector2(uf[i + 3], uf[i + 4])
		var u = ents.get(nid)
		if u == null or not is_instance_valid(u):
			u = spawn_unit(pid, kind, pos, nid)
			u.prev_pos = pos
			if controls(pid) and camera_set:
				play("ready")
		u.net_pos = pos
		u.facing = uf[i + 5]
		u.hp = uf[i + 6]
		u.max_hp = uf[i + 7]
		var f = int(uf[i + 8])
		u.rooted = (f & 1) != 0
		u.stealthed = (f & 2) != 0
		if u.air != ((f & 4) != 0):
			u.air = (f & 4) != 0
			u.z_index = 8 if u.air else 5
		u.carried = (f & 8) != 0
		u.carry = 10.0 if (f & 48) != 0 else 0.0
		u.carry_res = "food" if (f & 16) != 0 else "mat"
		u.stun_t = 1.0 if (f & 64) != 0 else 0.0
		u.snap_t = 999.0 if (f & 128) != 0 else 0.0
		u.alarm_stacks = 1 if (f & 256) != 0 else 0
		u.pinned_t = 1.0 if (f & 512) != 0 else 0.0
		u.net_extra = uf[i + 9]
		if u.d.get("lure", false):
			u.lure_cd = uf[i + 9]
		if u.d.get("bridge", false):
			u.bridge_r = uf[i + 9]
		u.shield = uf[i + 10]
		u.venom_stacks = int(uf[i + 11])
	var bf = s["b"]
	var q = s["q"]
	for i in range(0, bf.size(), B_FIELDS):
		var nid = int(bf[i])
		seen[nid] = true
		var kind = _bkinds[int(bf[i + 1])]
		var pid = int(bf[i + 2])
		var pos = Vector2(bf[i + 3], bf[i + 4])
		var f = int(bf[i + 7])
		var b = ents.get(nid)
		if b == null or not is_instance_valid(b):
			b = spawn_building(pid, kind, pos, (f & 1) != 0, (f & 2) != 0, nid)
		b.position = pos
		if controls(pid) and camera_set:
			if bf[i + 5] < b.hp - 0.5:
				notify_attacked(b)
			if not b.built and (f & 1) != 0:
				play("built")
		b.hp = bf[i + 5]
		b.max_hp = bf[i + 6]
		b.built = (f & 1) != 0
		b.is_main = (f & 2) != 0
		b.stealthed = (f & 4) != 0
		b.net_ok = (f & 8) != 0
		b.tier = int(bf[i + 8])
		b.mode = MODES[int(bf[i + 9])]
		b.mode_t = bf[i + 10]
		b.build_progress = bf[i + 11]
		b.upgrade_t = bf[i + 12]
		b.net_gardeners = int(bf[i + 13])
		b.venom_stacks = int(bf[i + 14])
		b.rally_pos = Vector2(bf[i + 15], bf[i + 16])
		b.pop_cost = bf[i + 17]
		b.queue = []
		for it in q.get(nid, []):
			b.queue.append({"type": it[0], "id": it[1], "progress": it[2], "time": it[3], "started": it[4]})
	var nf = s["n"]
	for i in range(0, nf.size(), N_FIELDS):
		var nid = int(nf[i])
		seen[nid] = true
		var n = ents.get(nid)
		if n == null or not is_instance_valid(n):
			n = _add_node(_nkinds[int(nf[i + 1])], Vector2(nf[i + 2], nf[i + 3]), nid)
		n.amount = nf[i + 4]
		if n.kind == "corpse":
			n.set_amount(n.amount)
		n.dead = (int(nf[i + 5]) & 1) != 0
		n.dormant = nf[i + 6]
		n.decay = nf[i + 7]
		n.hp = nf[i + 8]
	for nid in ents.keys():
		if not seen.has(nid):
			var e = ents[nid]
			ents.erase(nid)
			if is_instance_valid(e):
				if e is UnitScript and e.visible and not e.carried:
					play("death", e.position)
					add_effect(e.position, "death", players[e.pid].color if not e.is_neutral else Color(0.6, 0.6, 0.4))
				units.erase(e)
				buildings.erase(e)
				res_nodes.erase(e)
				if selection.has(e):
					selection.erase(e)
					sel_version += 1
				e.queue_free()
	for i in s["p"].size():
		var d = s["p"][i]
		var p = players[i]
		p.food = d[0]
		p.mat = d[1]
		p.pop_used = d[2]
		p.pop_cap = d[3]
		p.alive = d[4]
		p.succession = d[5]
		p.war_cd = d[6]
		var r = {}
		for id in d[7]:
			r[id] = true
		if i == human_id and r.size() > p.research.size() and camera_set:
			play("research")
		p.research = r
		p.is_ai = d[8]
	zones = []
	spore_zones = []
	var zs = s["z"]
	for i in range(0, zs.size(), 4):
		zones.append([Vector2(zs[i], zs[i + 1]), zs[i + 3], -1, zs[i + 2], 0.0])
	var br = {}
	for i in s["br"]:
		br[i] = true
	for i in terrain.bridged.size():
		var want = 1 if br.has(i) else 0
		if terrain.bridged[i] != want:
			terrain.bridged[i] = want
	# 첫 상태를 받으면 카메라를 내 둥지로
	if not camera_set:
		var m = main_nest(human_id)
		if m != null:
			camera.position = m.position
			camera_set = true
	controlled.clear()
	for pid in s["tr"]:
		if s["tr"][pid] == human_id:
			controlled[int(pid)] = true
	# 결과
	if not lost_shown and not players[human_id].alive:
		lost_shown = true
		hud.show_game_over(false)
	elif s["over"] and not game_over:
		game_over = true
		hud.show_game_over(players[human_id].alive and s["win"] == players[human_id].team)

# 참가자: 방장과의 연결이 끊기면 알리고 방 화면으로 돌아간다
func _on_net_left(reason):
	if not is_inside_tree():
		return
	msg(reason + " — 방 화면으로 돌아갑니다")
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
