extends RefCounted
# 지형 격자와 길찾기. 칸 크기는 전장의 안개와 같다(32).
# 지상 유닛: 물·절벽 통과 불가, 수목은 느리게 통과. 뗏목: 절벽만 통과 불가. 공중: 제한 없음.
const Data = preload("res://scripts/data.gd")

const GROUND = 0
const WATER = 1
const CLIFF = 2
const TREE = 3

var w = 0
var h = 0
var cells = PackedByteArray()
var nav = {}             # "ground" / "raft" -> AStarGrid2D

func setup():
	w = int(ceil(Data.MAP_SIZE.x / Data.FOG_CELL))
	h = int(ceil(Data.MAP_SIZE.y / Data.FOG_CELL))
	cells.resize(w * h)
	cells.fill(GROUND)
	for r in Data.TERRAIN:
		_fill(r[0], r[1], false)
		_fill(r[0], r[1], true)
	_build_nav()

# 좌우 대칭으로 채운다
func _fill(kind, rect, mirror):
	var x0 = int(rect.position.x / Data.FOG_CELL)
	var y0 = int(rect.position.y / Data.FOG_CELL)
	var x1 = int(ceil(rect.end.x / Data.FOG_CELL))
	var y1 = int(ceil(rect.end.y / Data.FOG_CELL))
	for y in range(max(0, y0), min(h, y1)):
		for x in range(max(0, x0), min(w, x1)):
			var cx = x
			if mirror:
				cx = w - 1 - x
			cells[y * w + cx] = kind

func _build_nav():
	for layer in ["ground", "raft"]:
		var a = AStarGrid2D.new()
		a.region = Rect2i(0, 0, w, h)
		a.cell_size = Vector2(Data.FOG_CELL, Data.FOG_CELL)
		a.offset = Vector2(Data.FOG_CELL, Data.FOG_CELL) / 2.0
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.update()
		for y in h:
			for x in w:
				var k = cells[y * w + x]
				if not _open_kind(k, layer):
					a.set_point_solid(Vector2i(x, y), true)
				elif k == TREE and layer == "ground":
					a.set_point_weight_scale(Vector2i(x, y), 1.0 / Data.TREE_SPEED)
		nav[layer] = a

func _open_kind(k, layer):
	if layer == "raft":
		return k != CLIFF
	return k == GROUND or k == TREE

func cell(pos):
	return Vector2i(clamp(int(pos.x / Data.FOG_CELL), 0, w - 1), clamp(int(pos.y / Data.FOG_CELL), 0, h - 1))

func kind_at(pos):
	var c = cell(pos)
	return cells[c.y * w + c.x]

func passable(pos, layer):
	return _open_kind(kind_at(pos), layer)

func speed_mult(pos, layer):
	if layer == "ground" and kind_at(pos) == TREE:
		return Data.TREE_SPEED
	return 1.0

# 두 점 사이를 곧장 갈 수 있는가(16픽셀 간격으로 확인)
func line_clear(a, b, layer):
	var d = a.distance_to(b)
	var n = int(d / 16.0) + 1
	for i in range(1, n + 1):
		if not passable(a.lerp(b, float(i) / n), layer):
			return false
	return true

# 가장 가까운 통과 가능 칸의 중심. 이미 통과 가능하면 그대로 돌려준다
func nearest_open(pos, layer):
	if passable(pos, layer):
		return pos
	var c = cell(pos)
	for r in range(1, 14):
		var best = null
		var bd = 1e12
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				if max(abs(x - c.x), abs(y - c.y)) != r:
					continue
				if _open_kind(cells[y * w + x], layer):
					var p = Vector2((x + 0.5) * Data.FOG_CELL, (y + 0.5) * Data.FOG_CELL)
					var dd = p.distance_squared_to(pos)
					if dd < bd:
						bd = dd
						best = p
		if best != null:
			return best
	return pos

# 길찾기. 끝점이 막혀 있거나 닿을 수 없으면 가장 가까이 가는 길을 준다
func find_path(a, b, layer):
	var from = cell(nearest_open(a, layer))
	var to = cell(nearest_open(b, layer))
	var pts = nav[layer].get_point_path(from, to, true)
	var out = []
	for p in pts:
		out.append(p)
	if out.size() > 0:
		out.remove_at(0)       # 첫 점은 지금 서 있는 칸
	if passable(b, layer) and out.size() > 0 and cell(out[-1]) == cell(b):
		out[-1] = b            # 마지막은 칸 중심이 아니라 실제 목표 지점
	return out

func reachable(a, b, layer):
	var from = cell(nearest_open(a, layer))
	var to = cell(nearest_open(b, layer))
	return from == to or nav[layer].get_point_path(from, to, false).size() > 0

# 건물은 맨땅에만 지을 수 있다(물·절벽·수목 불가)
func can_build(pos, radius):
	for off in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius),
			Vector2(radius, radius) * 0.7, Vector2(-radius, radius) * 0.7, Vector2(radius, -radius) * 0.7, Vector2(-radius, -radius) * 0.7]:
		if kind_at(pos + off) != GROUND:
			return false
	return true

# 미니맵·바닥 그리기용 색
func color_of(k):
	match k:
		WATER:
			return Color(0.2, 0.4, 0.6)
		CLIFF:
			return Color(0.25, 0.23, 0.22)
		TREE:
			return Color(0.2, 0.36, 0.18)
	return Color(0.36, 0.29, 0.2)
