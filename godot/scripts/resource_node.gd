extends Node2D
const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")

var game
var kind = ""
var d = {}
var amount = 0.0
var users = []
var dormant = 0.0
var radius = 26.0
var gone = false
# 공격 대상이 될 때 유닛 코드가 읽는 값(진딧물 군락만 공격 가능)
var dead = false
var air = false
var pid = -1
var hp = 0.0
var max_hp = 0.0
var slain_t = 0.0      # 도살 후 재생까지 남은 시간
var decay = 0.0        # 사체가 썩어 없어지기까지 남은 시간
var calm = 0.0         # 마지막으로 공격받은 뒤 지난 시간
var nid = 0

func setup(g, k, pos):
	game = g
	kind = k
	d = Data.NODES[k]
	amount = d["amount"]
	radius = d["radius"]
	position = pos
	if k == "aphid":
		max_hp = Data.APHID_HP
		hp = max_hp
	if k == "corpse":
		decay = Data.CORPSE_DECAY

func set_amount(a):
	amount = a
	# 사체는 클수록 크게 그린다
	radius = clamp(14.0 + a / 60.0, 16.0, 40.0)

func attackable():
	return kind == "aphid" and not dead

func take_damage(dmg, attacker):
	if not attackable():
		return
	hp -= dmg
	calm = 0.0
	if hp <= 0.0:
		_slay(attacker)

func add_venom(_cap, _burn):
	pass

# 진딧물 도살: 처치한 쪽이 식량을 즉시 얻고, 군락은 일정 시간 뒤 다시 살아난다
func _slay(attacker):
	dead = true
	slain_t = Data.APHID_RESPAWN
	for u in users:
		if is_instance_valid(u):
			u.in_slot = false
	users.clear()
	if attacker != null and is_instance_valid(attacker) and attacker.pid >= 0:
		game.players[attacker.pid].food += Data.APHID_SLAY_FOOD
		game.on_aphid_slain(self, attacker.pid)

func res_type():
	return d["res"]

func available():
	if gone or dead or dormant > 0.0:
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

func _physics_process(delta):
	if game.net_role == "client":
		return
	if dead:
		slain_t -= delta
		if slain_t <= 0.0:
			dead = false
			hp = max_hp
	elif kind == "aphid" and hp < max_hp:
		# 5초 동안 공격받지 않으면 천천히 회복
		calm += delta
		if calm >= Data.APHID_REGEN_DELAY:
			hp = min(max_hp, hp + Data.APHID_REGEN * delta)
	if kind == "corpse":
		decay -= delta
		if decay <= 0.0:
			game.remove_res_node(self)
			return

func _process(delta):
	if d["regen"] > 0.0 and game.net_role != "client":
		if dormant > 0.0:
			dormant -= delta
			if dormant <= 0.0:
				amount = d["amount"] * 0.5
		else:
			amount = min(d["amount"], amount + d["regen"] / 60.0 * delta)
	queue_redraw()

func _draw():
	Art.draw_node(self, self, game.elapsed)
	var txt = d["name"]
	if dead:
		txt += " (도살됨, %d초)" % int(ceil(slain_t))
	elif d["infinite"]:
		txt += " ∞"
	elif kind == "corpse":
		txt += " %d (부패 %d초)" % [int(amount), int(ceil(decay))]
	elif dormant > 0.0:
		txt += " (휴면 %d초)" % int(ceil(dormant))
	else:
		txt += " %d" % int(amount)
	var font = ThemeDB.fallback_font
	if kind == "aphid" and not dead and hp < max_hp:
		draw_rect(Rect2(-radius, -radius - 8.0, radius * 2.0, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-radius, -radius - 8.0, radius * 2.0 * hp / max_hp, 3.0), Color(0.9, 0.4, 0.3))
	draw_string(font, Vector2(-70, radius + 16), txt, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1, 1, 1, 0.85))
