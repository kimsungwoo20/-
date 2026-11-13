extends RefCounted
const Data = preload("res://scripts/data.gd")

var id = 0
var label = ""
var color = Color.WHITE
var is_ai = false
var alive = true
var food = Data.START_FOOD
var mat = Data.START_MAT
var pop_used = 0.0
var pop_cap = 0.0
var succession = 0.0     # 여왕 계승 중 남은 시간(일꾼 생산 정지)
var research = {}        # 완료한 연구 id -> true

func can_afford(f, m):
	return food >= f and mat >= m

func pay(f, m):
	food -= f
	mat -= m

func has(id):
	return research.has(id)

# 연구 계열(예: "jaw")의 완료 단계 수
func level(line):
	var n = 0
	while research.has("%s%d" % [line, n + 1]):
		n += 1
	return n

# 같은 종류 유닛 1조의 생산 수. 끝없는 물결은 침병·병정개미를 3기 한 조로 만든다
func batch(kind):
	var b = Data.UNITS[kind]["batch"]
	if research.has("wave") and (kind == "stinger" or kind == "soldier"):
		return 3
	return b

func upkeep_mult():
	for row in Data.UPKEEP:
		if pop_used <= row[0]:
			var penalty = 1.0 - row[1]
			penalty *= Data.TROPH_PENALTY[level("troph")]
			if research.has("wave"):
				penalty *= Data.WAVE_PENALTY
			return clamp(1.0 - penalty, 0.0, 1.0)
	return 1.0

# 연구 효과 배율
func melee_mult():
	return 1.0 + 0.1 * level("jaw")

func ranged_mult():
	return 1.0 + 0.1 * level("gland")

func taken_mult():
	return 1.0 - 0.08 * level("shell")

func hp_mult(air):
	var m = 1.0 + 0.1 * level("size")
	if air and research.has("flight1"):
		m += 0.1
	return m

func speed_mult(air):
	if air:
		return 1.15 if research.has("flight1") else 1.0
	return 1.1 if research.has("legs1") else 1.0

func carry_amount():
	return Data.CARRY + 2.0 * level("carry")

func venom_cap():
	if not research.has("venom1"):
		return 0
	return Data.VENOM_STACKS_BURN if research.has("burn") else Data.VENOM_STACKS
