extends Sprite2D
# 전장의 안개(사람 플레이어 기준). 칸마다 0 = 지금 보임, 1 = 본 적 있음, 2 = 본 적 없음
const Data = preload("res://scripts/data.gd")

var w = 0
var h = 0
var vis = PackedByteArray()
var explored = PackedByteArray()
var img
var tex

func setup():
	w = int(ceil(Data.MAP_SIZE.x / Data.FOG_CELL))
	h = int(ceil(Data.MAP_SIZE.y / Data.FOG_CELL))
	vis.resize(w * h)
	explored.resize(w * h)
	vis.fill(0)
	explored.fill(0)
	centered = false
	scale = Vector2(Data.FOG_CELL, Data.FOG_CELL)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img = Image.create(w, h, false, Image.FORMAT_LA8)
	img.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(img)
	texture = tex

func reveal(pos, r):
	var cx0 = max(0, int((pos.x - r) / Data.FOG_CELL))
	var cx1 = min(w - 1, int((pos.x + r) / Data.FOG_CELL))
	var cy0 = max(0, int((pos.y - r) / Data.FOG_CELL))
	var cy1 = min(h - 1, int((pos.y + r) / Data.FOG_CELL))
	var r2 = r * r
	for y in range(cy0, cy1 + 1):
		var py = (y + 0.5) * Data.FOG_CELL - pos.y
		for x in range(cx0, cx1 + 1):
			var px = (x + 0.5) * Data.FOG_CELL - pos.x
			if px * px + py * py <= r2:
				vis[y * w + x] = 1

func _idx(pos):
	var x = clamp(int(pos.x / Data.FOG_CELL), 0, w - 1)
	var y = clamp(int(pos.y / Data.FOG_CELL), 0, h - 1)
	return y * w + x

func is_visible_at(pos):
	return vis[_idx(pos)] == 1

func is_explored_at(pos):
	return explored[_idx(pos)] == 1

func recompute(game, pid):
	vis.fill(0)
	for u in game.units:
		if u.pid == pid and not u.dead:
			reveal(u.position, u.sight())
	for b in game.buildings:
		if b.pid == pid and not b.dead:
			reveal(b.position, b.sight())
	var data = PackedByteArray()
	data.resize(w * h * 2)
	for i in w * h:
		if vis[i] == 1:
			explored[i] = 1
			data[i * 2 + 1] = 0
		elif explored[i] == 1:
			data[i * 2 + 1] = 140
		else:
			data[i * 2 + 1] = 245
	img = Image.create_from_data(w, h, false, Image.FORMAT_LA8, data)
	tex.update(img)
