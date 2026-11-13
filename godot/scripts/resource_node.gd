extends Node2D
const Data = preload("res://scripts/data.gd")

var game
var kind = ""
var d = {}
var amount = 0.0
var users = []
var dormant = 0.0
var radius = 26.0
var gone = false

func setup(g, k, pos):
	game = g
	kind = k
	d = Data.NODES[k]
	amount = d["amount"]
	radius = d["radius"]
	position = pos

func res_type():
	return d["res"]

func available():
	if gone or dormant > 0.0:
		return false
	return d["infinite"] or amount > 0.0

func take_slot(u):
	users = users.filter(func(x): return is_instance_valid(x) and not x.dead and x.node == self and x.in_slot)
	if users.has(u):
		return true
	if users.size() >= d["slots"] or not available():
		return false
	users.append(u)
	return true

func release_slot(u):
	users.erase(u)

func harvest(n):
	if d["infinite"]:
		return n
	var got = min(n, amount)
	amount -= got
	if amount <= 0.0:
		amount = 0.0
		if d["regen"] > 0.0:
			dormant = d["dormancy"]
		else:
			game.remove_res_node(self)
	return got

func _process(delta):
	if d["regen"] > 0.0:
		if dormant > 0.0:
			dormant -= delta
			if dormant <= 0.0:
				amount = d["amount"] * 0.5
		else:
			amount = min(d["amount"], amount + d["regen"] / 60.0 * delta)
	queue_redraw()

func _draw():
	var c = d["color"]
	if dormant > 0.0:
		c = c.darkened(0.6)
	draw_circle(Vector2.ZERO, radius, c.darkened(0.35))
	draw_circle(Vector2(-radius * 0.3, -radius * 0.2), radius * 0.55, c)
	draw_circle(Vector2(radius * 0.35, radius * 0.25), radius * 0.45, c.lightened(0.1))
	draw_circle(Vector2(radius * 0.1, -radius * 0.45), radius * 0.3, c.lightened(0.2))
	var txt = d["name"]
	if d["infinite"]:
		txt += " ∞"
	elif dormant > 0.0:
		txt += " (휴면 %d초)" % int(ceil(dormant))
	else:
		txt += " %d" % int(amount)
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(-70, radius + 16), txt, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1, 1, 1, 0.85))
