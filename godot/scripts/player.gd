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
var research = {}

func can_afford(f, m):
	return food >= f and mat >= m

func pay(f, m):
	food -= f
	mat -= m

func upkeep_mult():
	for row in Data.UPKEEP:
		if pop_used <= row[0]:
			return row[1]
	return 1.0
