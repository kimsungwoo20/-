extends RefCounted
# 그림: 외부 그림 파일 없이 코드로 그린다. 개미는 머리·가슴·배 세 마디에 다리 6개, 더듬이, 진영별 턱 모양.
# 몸통은 플레이어 색을 바탕으로 해서 누구 유닛인지 한눈에 보이고, 머리·턱·무늬로 진영과 병종을 구분한다.
# 모든 함수는 그리는 노드(ci)의 현재 변환(유닛은 바라보는 방향으로 회전)을 그대로 쓴다. +x 가 앞쪽.

const Data = preload("res://scripts/data.gd")

static var _ell = {}

# 타원 꼭짓점(크기별로 한 번만 만든다)
static func ell(rx, ry, n = 14):
	var key = Vector3(snappedf(rx, 0.25), snappedf(ry, 0.25), n)
	if _ell.has(key):
		return _ell[key]
	var pts = PackedVector2Array()
	for i in n:
		var a = i * TAU / n
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	_ell[key] = pts
	return pts

static func oval(ci, center, rx, ry, col):
	var src = ell(rx, ry)
	var pts = PackedVector2Array()
	pts.resize(src.size())
	for i in src.size():
		pts[i] = src[i] + center
	ci.draw_colored_polygon(pts, col)

# ---------- 개미 ----------

const BIG_HEAD = ["soldier", "major", "supermajor", "gate", "guardian", "king", "tyrant", "sickle", "warden", "pinner", "puller", "lord"]
const FACTION_HEAD = {
	"fire": Color(0.55, 0.12, 0.06), "leaf": Color(0.45, 0.25, 0.12), "weaver": Color(0.75, 0.48, 0.2),
	"trap": Color(0.28, 0.16, 0.1), "army": Color(0.2, 0.15, 0.12),
}

static func draw_ant(ci, r, pc, faction, kind, walk, worker = false):
	var dark = pc.darkened(0.55)
	var head_col = FACTION_HEAD.get(faction, Color(0.3, 0.2, 0.15)).lerp(pc, 0.25)
	var hs = 1.45 if BIG_HEAD.has(kind) else (0.85 if worker else 1.0)
	var legs_long = 1.25 if faction == "weaver" else 1.0
	# 다리 6개: 걸을 때 앞뒤로 흔든다
	for side in [-1.0, 1.0]:
		for k in 3:
			var base = Vector2((1 - k) * 0.28 * r, side * 0.18 * r)
			var swing = sin(walk + k * 2.1 + (PI if side > 0 else 0.0)) * 0.3 * r
			var knee = Vector2((1 - k) * 0.45 * r + swing * 0.5, side * 0.75 * r * legs_long)
			var foot = Vector2((1 - k) * 0.85 * r - 0.15 * r + swing, side * 1.2 * r * legs_long)
			ci.draw_polyline(PackedVector2Array([base, knee, foot]), dark, max(1.0, r * 0.13))
	# 배
	var ab = 1.25 if kind in ["tyrant", "king", "supermajor"] else 1.0
	oval(ci, Vector2(-0.95 * r, 0), 0.72 * r * ab, 0.55 * r * ab, pc)
	ci.draw_line(Vector2(-1.25 * r, -0.4 * r), Vector2(-1.25 * r, 0.4 * r), pc.darkened(0.3), max(1.0, r * 0.1))
	ci.draw_line(Vector2(-0.85 * r, -0.5 * r), Vector2(-0.85 * r, 0.5 * r), pc.darkened(0.3), max(1.0, r * 0.1))
	if faction == "fire":
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-1.65 * r, -0.12 * r), Vector2(-2.0 * r, 0), Vector2(-1.65 * r, 0.12 * r)]), dark)
	if kind in ["sprayer", "acid", "airsentry", "lord"]:
		oval(ci, Vector2(-1.0 * r, 0), 0.32 * r, 0.25 * r, Color(0.75, 1.0, 0.3))
	if kind in ["medic", "spore"]:
		for o in [Vector2(-1.1, -0.2), Vector2(-0.8, 0.2), Vector2(-1.2, 0.25)]:
			ci.draw_circle(o * r, 0.12 * r, Color(0.9, 0.95, 0.8))
	# 가슴
	oval(ci, Vector2(0, 0), 0.36 * r, 0.26 * r, pc.darkened(0.15))
	if faction == "leaf" and not worker:
		ci.draw_line(Vector2(0.05 * r, -0.2 * r), Vector2(-0.1 * r, -0.45 * r), dark, max(1.0, r * 0.1))
		ci.draw_line(Vector2(0.05 * r, 0.2 * r), Vector2(-0.1 * r, 0.45 * r), dark, max(1.0, r * 0.1))
	# 머리
	var hx = 0.5 * r + 0.32 * r * hs
	oval(ci, Vector2(hx, 0), 0.36 * r * hs, 0.34 * r * hs, head_col)
	ci.draw_circle(Vector2(hx + 0.12 * r * hs, -0.2 * r * hs), max(0.8, 0.08 * r * hs), Color(0, 0, 0))
	ci.draw_circle(Vector2(hx + 0.12 * r * hs, 0.2 * r * hs), max(0.8, 0.08 * r * hs), Color(0, 0, 0))
	# 더듬이
	var front = hx + 0.3 * r * hs
	for side in [-1.0, 1.0]:
		ci.draw_polyline(PackedVector2Array([Vector2(front - 0.1 * r, side * 0.15 * r), Vector2(front + 0.35 * r, side * 0.5 * r), Vector2(front + 0.65 * r, side * 0.38 * r)]), dark, max(1.0, r * 0.08))
	# 턱: 진영마다 다르다
	var jw = max(1.2, r * 0.14)
	var jc = dark.lightened(0.15)
	match faction:
		"trap":
			# 함정턱: 곧고 긴 턱 두 개
			for side in [-1.0, 1.0]:
				ci.draw_line(Vector2(front, side * 0.14 * r * hs), Vector2(front + 0.95 * r * hs, side * 0.12 * r * hs), jc, jw)
				ci.draw_line(Vector2(front + 0.95 * r * hs, side * 0.12 * r * hs), Vector2(front + 0.85 * r * hs, side * 0.0), jc, jw * 0.8)
		"army":
			# 낫 모양 턱
			for side in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([Vector2(front - 0.05 * r, side * 0.2 * r * hs), Vector2(front + 0.4 * r * hs, side * 0.35 * r * hs), Vector2(front + 0.6 * r * hs, side * 0.05 * r * hs)]), jc, jw)
		"leaf":
			# 톱니 턱(잎을 자른다)
			for side in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(front - 0.05 * r, side * 0.25 * r * hs), Vector2(front + 0.4 * r * hs, side * 0.12 * r * hs), Vector2(front, side * 0.05 * r)]), jc)
		_:
			for side in [-1.0, 1.0]:
				ci.draw_line(Vector2(front - 0.05 * r, side * 0.18 * r * hs), Vector2(front + 0.3 * r * hs, side * 0.05 * r * hs), jc, jw)

# 포식 대군: 개미 여러 마리가 덩어리로 움직인다
static func draw_horde(ci, r, pc, faction, walk, facing):
	for i in 9:
		var a = i * 2.39996
		var d = sqrt(float(i) / 9.0) * r * 0.85
		var off = Vector2(cos(a), sin(a)) * d
		ci.draw_set_transform(off.rotated(facing), facing, Vector2.ONE)
		draw_ant(ci, r * 0.32, pc, faction, "raider", walk + i, false)
	ci.draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)

# 짐: 식량은 씨앗, 재료는 잎 조각(잎꾼개미) 또는 나뭇가지
static func draw_carry(ci, r, res, faction):
	var p = Vector2(1.55 * r, 0)
	if res == "food":
		oval(ci, p, 0.32 * r + 1.0, 0.22 * r + 1.0, Color(0.95, 0.82, 0.4))
	elif faction == "leaf":
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.2 * r, 0), p + Vector2(0.3 * r, -0.9 * r), p + Vector2(0.6 * r, -0.2 * r)]), Color(0.35, 0.7, 0.3))
	else:
		ci.draw_line(p + Vector2(-0.1 * r, -0.4 * r), p + Vector2(0.2 * r, 0.4 * r), Color(0.6, 0.42, 0.22), max(1.5, r * 0.18))

# ---------- 중립 생물 ----------

static func draw_neutral(ci, kind, r, col, walk):
	var dark = col.darkened(0.45)
	match kind:
		"grub":
			for i in 5:
				oval(ci, Vector2((2 - i) * 0.32 * r, 0), 0.28 * r, 0.42 * r * (1.0 - abs(2 - i) * 0.12), Color(0.92, 0.88, 0.75).darkened(i * 0.04))
			oval(ci, Vector2(0.9 * r, 0), 0.22 * r, 0.25 * r, Color(0.55, 0.35, 0.2))
		"spider":
			for side in [-1.0, 1.0]:
				for k in 4:
					var sw = sin(walk + k * 1.6 + (PI if side > 0 else 0.0)) * 0.25 * r
					var base = Vector2((1.5 - k) * 0.18 * r, side * 0.2 * r)
					var knee = Vector2((1.5 - k) * 0.6 * r + sw * 0.4, side * 0.95 * r)
					var foot = Vector2((1.5 - k) * 0.9 * r + sw, side * 1.45 * r)
					ci.draw_polyline(PackedVector2Array([base, knee, foot]), dark, max(1.0, r * 0.1))
			oval(ci, Vector2(-0.55 * r, 0), 0.6 * r, 0.5 * r, col.darkened(0.2))
			oval(ci, Vector2(0.25 * r, 0), 0.32 * r, 0.3 * r, col)
			for o in [Vector2(0.45, -0.1), Vector2(0.45, 0.1), Vector2(0.5, -0.2), Vector2(0.5, 0.2)]:
				ci.draw_circle(o * r, 0.05 * r + 0.5, Color(0.9, 0.2, 0.1))
		"mantis":
			for side in [-1.0, 1.0]:
				for k in 2:
					var sw = sin(walk + k * 2.0 + (PI if side > 0 else 0.0)) * 0.2 * r
					ci.draw_polyline(PackedVector2Array([Vector2(-0.3 * r - k * 0.4 * r, 0), Vector2(-0.2 * r - k * 0.4 * r + sw, side * 0.6 * r), Vector2(-0.4 * r - k * 0.5 * r + sw, side * 1.0 * r)]), dark, max(1.0, r * 0.07))
			oval(ci, Vector2(-0.9 * r, 0), 0.75 * r, 0.25 * r, col.darkened(0.1))
			oval(ci, Vector2(0.1 * r, 0), 0.5 * r, 0.13 * r, col)
			oval(ci, Vector2(0.75 * r, 0), 0.2 * r, 0.25 * r, col.lightened(0.1))
			# 낫 같은 앞다리
			for side in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([Vector2(0.3 * r, side * 0.1 * r), Vector2(0.7 * r, side * 0.45 * r), Vector2(1.15 * r, side * 0.2 * r), Vector2(1.0 * r, side * 0.05 * r)]), col.lightened(0.25), max(1.5, r * 0.1))
		_:
			oval(ci, Vector2.ZERO, r, r * 0.7, col)

# ---------- 건물 ----------

const FACTION_BASE = {
	"fire": Color(0.5, 0.32, 0.2), "leaf": Color(0.42, 0.33, 0.24), "weaver": Color(0.3, 0.5, 0.22),
	"trap": Color(0.22, 0.17, 0.13), "army": Color(0.24, 0.18, 0.14),
}

static func draw_building(ci, b, pc, faction, a, t):
	var r = b.radius
	var base = FACTION_BASE.get(faction, Color(0.3, 0.22, 0.14))
	base.a = a
	var pcol = Color(pc.r, pc.g, pc.b, a)
	match faction:
		"fire":
			# 흙을 쌓은 둔덕: 동심원과 입구
			for i in 4:
				ci.draw_circle(Vector2(0, -i * r * 0.06), r * (1.0 - i * 0.2), base.lightened(i * 0.07))
			for o in [Vector2(-0.35, 0.1), Vector2(0.3, -0.25), Vector2(0.1, 0.35)]:
				oval(ci, o * r, r * 0.11, r * 0.08, Color(0.1, 0.06, 0.04, a))
		"leaf":
			# 균류 정원: 둥근 지붕 위 흰 균사 덩어리
			ci.draw_circle(Vector2.ZERO, r, base)
			for i in 9:
				var p = Vector2(cos(i * 2.4), sin(i * 2.4)) * r * (0.25 + 0.06 * i)
				ci.draw_circle(p, r * 0.16, Color(0.9, 0.9, 0.82, a))
		"weaver":
			# 잎을 비단으로 엮은 둥지
			for i in 7:
				var ang = i * TAU / 7.0
				var p = Vector2(cos(ang), sin(ang)) * r * 0.55
				var leaf = ell(r * 0.55, r * 0.28)
				var pts = PackedVector2Array()
				for q in leaf:
					pts.append(q.rotated(ang) + p)
				ci.draw_colored_polygon(pts, base.lightened(0.08 * (i % 2)))
			ci.draw_circle(Vector2.ZERO, r * 0.5, base.darkened(0.15))
			for i in 7:
				var ang = i * TAU / 7.0 + 0.45
				ci.draw_line(Vector2(cos(ang), sin(ang)) * r * 0.3, Vector2(cos(ang), sin(ang)) * r * 0.95, Color(0.95, 0.95, 0.9, 0.7 * a), 1.0)
		"trap":
			# 땅속 굴: 어두운 구덩이와 자갈
			ci.draw_circle(Vector2.ZERO, r, base.lightened(0.15))
			ci.draw_circle(Vector2.ZERO, r * 0.62, Color(0.05, 0.04, 0.03, a))
			for i in 8:
				ci.draw_circle(Vector2(cos(i * 0.8), sin(i * 0.8)) * r * 0.82, r * 0.08, Color(0.5, 0.45, 0.4, a))
		"army":
			# 개미 몸으로 만든 둥지: 수많은 개미가 엉켜 있다(행군 중이면 꿈틀거린다)
			var wob = 0.0 if b.mode == "camp" else 1.0
			for i in 26:
				var ang = i * 2.39996
				var d = sqrt(float(i) / 26.0) * r * 0.95
				var p = Vector2(cos(ang), sin(ang)) * d + Vector2(sin(t * 6.0 + i), cos(t * 5.0 + i)) * 2.0 * wob
				ci.draw_circle(p, r * 0.13, base.lightened(0.05 * (i % 3)))
		_:
			ci.draw_circle(Vector2.ZERO, r, base)
	# 주인 색 테두리와 종류 표시
	ci.draw_arc(Vector2.ZERO, r * 1.02, 0.0, TAU, 40, pcol, max(2.0, r * 0.09))
	var ic = Color(pc.r, pc.g, pc.b, a).lightened(0.15)
	match b.kind:
		"nest":
			if b.is_main:
				# 여왕
				oval(ci, Vector2(0, 0), r * 0.32, r * 0.2, ic)
				ci.draw_circle(Vector2(r * 0.3, 0), r * 0.12, ic.darkened(0.3))
			else:
				ci.draw_circle(Vector2.ZERO, r * 0.15, ic)
		"combat":
			ci.draw_line(Vector2(-0.25, -0.25) * r, Vector2(0.25, 0.25) * r, ic, max(2.0, r * 0.1))
			ci.draw_line(Vector2(-0.25, 0.25) * r, Vector2(0.25, -0.25) * r, ic, max(2.0, r * 0.1))
		"defense":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.22, -0.25) * r, Vector2(0.22, -0.25) * r, Vector2(0.2, 0.1) * r, Vector2(0, 0.3) * r, Vector2(-0.2, 0.1) * r]), ic)
		"special":
			oval(ci, Vector2(0, -0.15 * r), r * 0.28, r * 0.12, Color(1, 1, 1, 0.75 * a))
			oval(ci, Vector2(0, 0.15 * r), r * 0.28, r * 0.12, Color(1, 1, 1, 0.75 * a))
			ci.draw_circle(Vector2.ZERO, r * 0.1, ic)
		"lab":
			var hexp = PackedVector2Array()
			for i in 6:
				hexp.append(Vector2(cos(i * TAU / 6.0), sin(i * TAU / 6.0)) * r * 0.28)
			ci.draw_colored_polygon(hexp, ic)
			ci.draw_circle(Vector2.ZERO, r * 0.1, Color(0.8, 1.0, 0.3, a))
		"tent":
			ci.draw_circle(Vector2.ZERO, r * 0.2, ic)

# ---------- 자원 지점 ----------

static func draw_node(ci, n, t):
	var r = n.radius
	var dim = 0.45 if (n.dormant > 0.0 or n.dead) else 0.0
	match n.kind:
		"seed":
			for i in 11:
				var p = Vector2(cos(i * 2.4), sin(i * 2.4)) * r * sqrt(float(i) / 11.0) * 0.85
				var leaf = ell(r * 0.2, r * 0.13, 10)
				var pts = PackedVector2Array()
				for q in leaf:
					pts.append(q.rotated(i * 1.1) + p)
				ci.draw_colored_polygon(pts, Color(0.9, 0.76, 0.38).darkened(dim + 0.06 * (i % 3)))
		"litter":
			for i in 7:
				var ang = i * 0.9
				var p = Vector2(cos(i * 2.4), sin(i * 2.4)) * r * 0.45
				var leaf = ell(r * 0.42, r * 0.2, 10)
				var pts = PackedVector2Array()
				for q in leaf:
					pts.append(q.rotated(ang) + p)
				ci.draw_colored_polygon(pts, Color(0.62, 0.4, 0.2).lerp(Color(0.75, 0.55, 0.25), 0.15 * (i % 3)).darkened(dim))
				ci.draw_line(p - Vector2(cos(ang), sin(ang)) * r * 0.35, p + Vector2(cos(ang), sin(ang)) * r * 0.35, Color(0.4, 0.25, 0.12), 1.0)
		"aphid":
			# 진딧물 무리: 연두색 작은 벌레들이 꿈틀거린다
			ci.draw_circle(Vector2.ZERO, r, Color(0.3, 0.45, 0.2, 0.5).darkened(dim))
			for i in 12:
				var p = Vector2(cos(i * 2.4), sin(i * 2.4)) * r * sqrt(float(i) / 12.0) * 0.8
				p += Vector2(sin(t * 2.0 + i), cos(t * 1.7 + i)) * 0.8
				oval(ci, p, r * 0.15, r * 0.11, Color(0.6, 0.9, 0.45).darkened(dim))
		"plant":
			for i in 5:
				var ang = i * TAU / 5.0 + 0.3
				var p = Vector2(cos(ang), sin(ang)) * r * 0.45
				var leaf = ell(r * 0.5, r * 0.22, 10)
				var pts = PackedVector2Array()
				for q in leaf:
					pts.append(q.rotated(ang) + p)
				ci.draw_colored_polygon(pts, Color(0.25, 0.6, 0.25).lightened(0.05 * (i % 2)).darkened(dim))
			ci.draw_circle(Vector2.ZERO, r * 0.2, Color(0.35, 0.5, 0.2).darkened(dim))
		"deadwood":
			# 쓰러진 고목과 수지 방울
			var log = ell(r * 1.1, r * 0.45, 16)
			var pts = PackedVector2Array()
			for q in log:
				pts.append(q.rotated(0.4))
			ci.draw_colored_polygon(pts, Color(0.45, 0.3, 0.18).darkened(dim))
			for i in 4:
				ci.draw_line(Vector2(-0.8 + i * 0.5, -0.3).rotated(0.4) * r, Vector2(-0.6 + i * 0.5, 0.3).rotated(0.4) * r, Color(0.32, 0.2, 0.1), 1.5)
			for o in [Vector2(0.3, -0.35), Vector2(-0.4, 0.3)]:
				ci.draw_circle(o * r, r * 0.12, Color(0.95, 0.65, 0.2, 0.9))
		"corpse":
			# 딱정벌레 사체
			oval(ci, Vector2.ZERO, r * 0.9, r * 0.65, Color(0.35, 0.28, 0.3))
			ci.draw_line(Vector2(-0.8, 0) * r, Vector2(0.6, 0) * r, Color(0.2, 0.15, 0.17), 1.5)
			for side in [-1.0, 1.0]:
				for k in 3:
					ci.draw_line(Vector2((k - 1) * 0.35 * r, side * 0.5 * r), Vector2((k - 1) * 0.5 * r, side * 0.95 * r), Color(0.25, 0.2, 0.2), 1.2)
		_:
			ci.draw_circle(Vector2.ZERO, r, n.d["color"])
