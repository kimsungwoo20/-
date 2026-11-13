extends Control
const Data = preload("res://scripts/data.gd")

var game

func _process(_delta):
	queue_redraw()

func _draw():
	var s = size / Data.MAP_SIZE
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.16, 0.1))
	for n in game.res_nodes:
		draw_rect(Rect2(n.position * s - Vector2(2, 2), Vector2(4, 4)), n.d["color"])
	for b in game.buildings:
		if b.visible:
			draw_rect(Rect2(b.position * s - Vector2(3, 3), Vector2(6, 6)), game.players[b.pid].color)
	for u in game.units:
		if u.visible:
			draw_rect(Rect2(u.position * s - Vector2(1, 1), Vector2(2, 2)), game.players[u.pid].color.lightened(0.3))
	draw_texture_rect(game.fog.tex, Rect2(Vector2.ZERO, size), false)
	var vs = get_viewport_rect().size / game.camera.zoom
	var tl = (game.camera.position - vs / 2.0) * s
	draw_rect(Rect2(tl, vs * s), Color(1, 1, 1, 0.8), false, 1.0)

func _gui_input(ev):
	var go = false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		go = true
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		go = true
	if go:
		game.camera.position = ev.position / (size / Data.MAP_SIZE)
		accept_event()
