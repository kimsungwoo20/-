extends RefCounted
# 인원수·크기에 맞는 지도 배치. 2인·보통은 좌우 대칭 지도, 나머지는 기지를 타원 둘레에 고르게 놓는다.
# 지도가 클수록 기지 사이가 멀어지고, 기지마다 확장 지점과 중앙 자원이 늘어난다.
# 결과: {"starts": [...], "nodes": [[종류, 위치], ...], "expansions": [...], "camps": [[위치, [종류...]], ...],
#        "terrain": [[지형 종류, Rect2], ...]}
const Data = preload("res://scripts/data.gd")

const TerrainScript = preload("res://scripts/terrain.gd")
const RADII = {"seed": 28.0, "litter": 28.0, "aphid": 26.0, "plant": 24.0, "deadwood": 40.0}

# Data.MAP_SIZE 를 먼저 정해 두고 부른다
static func make(n, key = "medium"):
	if n <= 2 and key == "medium":
		return _two()
	return _radial(n, key)

static func _mirror(p):
	return Vector2(Data.MAP_SIZE.x - p.x, p.y)

static func _mirror_rect(r):
	return Rect2(Data.MAP_SIZE.x - r.end.x, r.position.y, r.size.x, r.size.y)

static func _two():
	var out = {"starts": [Vector2(420, 1000), _mirror(Vector2(420, 1000))], "nodes": [], "expansions": [], "camps": [], "terrain": []}
	var half = [
		["seed", Vector2(600, 880)], ["litter", Vector2(600, 1130)], ["aphid", Vector2(300, 760)],
		["aphid", Vector2(930, 330)], ["plant", Vector2(770, 290)],
		["aphid", Vector2(930, 1670)], ["plant", Vector2(770, 1710)],
		["plant", Vector2(1250, 1000)],
	]
	for e in half:
		out["nodes"].append(e)
		out["nodes"].append([e[0], _mirror(e[1])])
	for e in [["deadwood", Vector2(1600, 1000)], ["plant", Vector2(1600, 620)], ["plant", Vector2(1600, 1380)],
			["aphid", Vector2(1600, 250)], ["aphid", Vector2(1600, 1750)]]:
		out["nodes"].append(e)
	for e in [Vector2(840, 420), Vector2(840, 1580)]:
		out["expansions"].append(e)
		out["expansions"].append(_mirror(e))
	out["expansions"].append(Vector2(1600, 400))
	out["expansions"].append(Vector2(1600, 1600))
	for c in [[Vector2(640, 600), ["grub", "grub"]], [Vector2(640, 1400), ["grub", "grub"]],
			[Vector2(1200, 640), ["spider"]], [Vector2(1200, 1360), ["spider"]]]:
		out["camps"].append(c)
		out["camps"].append([_mirror(c[0]), c[1]])
	out["camps"].append([Vector2(1600, 880), ["mantis"]])
	for r in Data.TERRAIN:
		out["terrain"].append(r)
		out["terrain"].append([r[0], _mirror_rect(r[1])])
	return out

static func _clampv(p):
	return p.clamp(Vector2(70, 70), Data.MAP_SIZE - Vector2(70, 70))

# 기지마다 같은 모양: fwd = 중앙 방향, side = 옆 방향. 기지 0 은 왼쪽(사람 자리)
static func _radial(n, key):
	var out = {"starts": [], "nodes": [], "expansions": [], "camps": [], "terrain": []}
	var C = Data.MAP_SIZE / 2.0
	var rx = Data.MAP_SIZE.x * 0.39
	var ry = Data.MAP_SIZE.y * 0.36
	var big = key == "large" or key == "huge"
	for i in n:
		var ang = PI + i * TAU / n
		var s = C + Vector2(cos(ang) * rx, sin(ang) * ry)
		out["starts"].append(s)
	for i in n:
		var s = out["starts"][i]
		var fwd = (C - s).normalized()
		var side = fwd.rotated(PI / 2.0)
		var at = func(f, sd): return _clampv(s + fwd * f + side * sd)
		# 시작 자원
		out["nodes"].append(["seed", at.call(190, -120)])
		out["nodes"].append(["litter", at.call(190, 140)])
		out["nodes"].append(["aphid", at.call(-40, -230)])
		# 앞마당 확장: 진딧물과 식물
		var e = at.call(470, -330)
		out["expansions"].append(e)
		out["nodes"].append(["aphid", _clampv(e + fwd * 110 + side * -40)])
		out["nodes"].append(["plant", _clampv(e + fwd * -30 + side * -120)])
		# 기지 근처 유충 무리
		out["camps"].append([at.call(330, 260), ["grub", "grub"]])
		# 큰 지도: 반대편 옆으로 두 번째 확장 지점(진딧물·식물·낙엽)
		if big:
			var e2 = at.call(650, 520)
			out["expansions"].append(e2)
			out["nodes"].append(["aphid", _clampv(e2 + fwd * 110 + side * 40)])
			out["nodes"].append(["plant", _clampv(e2 + fwd * -30 + side * 130)])
			out["nodes"].append(["litter", _clampv(e2 + fwd * 120 + side * -110)])
			out["camps"].append([at.call(900, 250), ["spider"]])
		# 기지와 중앙 사이 작은 호수(돌아가거나 뗏목·공중으로), 기지 뒤 수목
		var lake = at.call(560, 160)
		out["terrain"].append([1, Rect2(lake - Vector2(56, 56), Vector2(112, 112))])
		var tree = at.call(-60, 240)
		out["terrain"].append([3, Rect2(tree - Vector2(48, 48), Vector2(96, 96))])
	# 이웃한 두 기지 사이: 거미 무리와 식물(분쟁 지역)
	for i in n:
		var a = out["starts"][i]
		var b = out["starts"][(i + 1) % n]
		var m = a.lerp(b, 0.5).lerp(C, 0.3)
		out["camps"].append([_clampv(m), ["spider"]])
		out["nodes"].append(["plant", _clampv(m + (C - m).normalized() * 130)])
	# 큰 지도: 중앙 둘레에 진딧물·식물 고리, 아주 큰 지도는 양옆에 고목을 하나씩 더
	if big:
		for i in 6:
			var ang = i * TAU / 6.0 + 0.3
			var p = C + Vector2(cos(ang) * rx * 0.42, sin(ang) * ry * 0.42)
			out["nodes"].append(["aphid" if i % 2 == 0 else "plant", _clampv(p)])
	if key == "huge":
		for side_x in [-1.0, 1.0]:
			out["nodes"].append(["deadwood", C + Vector2(side_x * rx * 0.55, 0)])
			out["camps"].append([C + Vector2(side_x * rx * 0.55, -110), ["mantis"]])
	# 중앙: 고목과 그것을 지키는 사마귀, 주위 식물
	out["nodes"].append(["deadwood", C])
	out["camps"].append([C + Vector2(0, -120), ["mantis"]])
	out["nodes"].append(["plant", C + Vector2(-260, 150)])
	out["nodes"].append(["plant", C + Vector2(260, 150)])
	out["terrain"].append([3, Rect2(C + Vector2(-200, -40), Vector2(64, 96))])
	out["terrain"].append([3, Rect2(C + Vector2(136, -40), Vector2(64, 96))])
	return _fixup(out)

# 물·수목 위에 놓였거나 다른 것과 겹치는 자원 지점·무리를 근처 빈자리로 옮긴다(옮길 곳이 없으면 뺀다)
static func _fixup(out):
	var T = TerrainScript.new()
	T.setup(out["terrain"])
	var taken = []      # [위치, 반경]
	for s in out["starts"]:
		taken.append([s, 80.0])
	for e in out["expansions"]:
		taken.append([e, 70.0])
	var nodes = []
	for e in out["nodes"]:
		var r = RADII[e[0]]
		var pos = _free_spot(T, e[1], r, taken)
		if pos != null:
			nodes.append([e[0], pos])
			taken.append([pos, r + 10.0])
	out["nodes"] = nodes
	var camps = []
	for c in out["camps"]:
		var pos = _free_spot(T, c[0], 20.0, taken)
		if pos != null:
			camps.append([pos, c[1]])
	out["camps"] = camps
	return out

static func _free_spot(T, pos, r, taken):
	for ring in 8:
		for k in max(1, ring * 6):
			var q = _clampv(pos + Vector2(ring * 24.0, 0).rotated(k * TAU / max(1, ring * 6)))
			if not T.can_build(q, r):
				continue
			var ok = true
			for t in taken:
				if q.distance_to(t[0]) < r + t[1] + 20.0:
					ok = false
					break
			if ok:
				return q
	return null
