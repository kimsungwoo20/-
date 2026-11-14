extends RefCounted
const Data = preload("res://scripts/data.gd")

var id = 0
var label = ""
var color = Color.WHITE
var is_ai = false
var alive = true
var neutral = false     # 중립 생물 전용 가상 플레이어
var faction = "fire"
var war_cd = 0.0         # 전쟁 균류 재사용 대기
var looted = 0.0         # 약탈로 얻은 자원 합계
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
	var table = Data.UPKEEP_COMMON
	if Data.FACTIONS.has(faction):
		table = Data.FACTIONS[faction]["upkeep"]
	for row in table:
		if pop_used <= row[0]:
			var penalty = 1.0 - row[1]
			penalty *= Data.TROPH_PENALTY[level("troph")]
			if research.has("wave"):
				penalty *= Data.WAVE_PENALTY
			return clamp(1.0 - penalty, 0.0, 1.0)
	return 1.0

# 연구 효과 배율
# upg: 연구 효과 배율(잎꾼개미 절단병은 1.5)
func melee_mult(upg = 1.0):
	return 1.0 + 0.1 * level("jaw") * upg

func ranged_mult(upg = 1.0):
	return 1.0 + 0.1 * level("gland") * upg

func taken_mult(upg = 1.0):
	return 1.0 - 0.08 * level("shell") * upg

func hp_mult(air):
	var m = 1.0 + 0.1 * level("size")
	if air and research.has("flight1"):
		m += 0.1
	return m

func speed_mult(air):
	if air:
		return 1.15 if research.has("flight1") else 1.0
	return 1.1 if research.has("legs1") else 1.0

func carry_amount(res = "food"):
	var n = Data.CARRY + 2.0 * level("carry")
	if Data.FACTIONS.has(faction):
		if res == "mat":
			n += Data.FACTIONS[faction]["mat_carry_bonus"]
		n += Data.FACTIONS[faction].get("carry_bonus", 0.0)
	return n

# 유닛 식량 비용(함정턱개미 일꾼은 75)
func unit_food(kind):
	if kind == "worker" and Data.FACTIONS.has(faction):
		return Data.FACTIONS[faction].get("worker_food", Data.UNITS["worker"]["food"])
	return Data.UNITS[kind]["food"]

func garden_ratio():
	return Data.GARDEN_RATIO_HIGH if research.has("high_yield") else Data.GARDEN_RATIO

func venom_cap():
	if not research.has("venom1"):
		return 0
	return Data.VENOM_STACKS_BURN if research.has("burn") else Data.VENOM_STACKS
