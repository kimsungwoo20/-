extends RefCounted
# 공통 규칙 수치. docs/system-design.md 의 [권장] 초기값을 그대로 옮긴 것이다.
# 현재는 불개미 한 진영만 구현되어 있어 불개미 고유 수정치가 이미 반영된 값이 섞여 있다(주석 표시).

const MAP_SIZE = Vector2(3200, 2000)
const POP_MAX = 200.0
const NEST_POP = [30, 60, 90]          # 주 둥지 등급 I / II / III
const SAT_POP = 15                     # 위성 둥지
const NEST_UPGRADE = {
	2: {"mat": 200, "time": 40.0},
	3: {"mat": 400, "time": 60.0},
}
# 유지비: [인구 상한, 식량 수입 배율]. 불개미 고유값(공통은 0.85 / 0.70).
const UPKEEP = [[60.0, 1.0], [120.0, 0.8], [99999.0, 0.6]]
const QUEUE_MAX = 5
const CARRY = 10.0
const START_FOOD = 200.0
const START_MAT = 100.0
const START_WORKERS = 6
const SUCCESSION_TIME = 60.0
const AGGRO = 150.0
const ROOT_DAMAGE_MULT = 0.4
const TYRANT_AURA = 120.0
const TYRANT_CD_MULT = 0.8

# reach: 공격 사거리(양쪽 반지름 제외). 30 이하는 근접.
# batch: 1회 생산 수. 불개미 T1 은 2기 한 조.
const UNITS = {
	"worker": {"name": "일꾼", "food": 50, "mat": 0, "pop": 1.0, "time": 12.0, "tier": 1,
		"hp": 40.0, "dmg": 3.0, "cd": 1.0, "reach": 4.0, "speed": 75.0, "radius": 6.0, "batch": 1},
	"stinger": {"name": "침병", "food": 50, "mat": 0, "pop": 1.0, "time": 12.5, "tier": 1,
		"hp": 32.0, "dmg": 5.0, "cd": 0.8, "reach": 4.0, "speed": 100.0, "radius": 5.0, "batch": 2},
	"soldier": {"name": "병정개미", "food": 60, "mat": 0, "pop": 1.0, "time": 15.0, "tier": 1,
		"hp": 75.0, "dmg": 4.0, "cd": 1.0, "reach": 4.0, "speed": 78.0, "radius": 6.5, "batch": 2},
	"sprayer": {"name": "분사병", "food": 110, "mat": 30, "pop": 2.0, "time": 39.0, "tier": 2,
		"hp": 55.0, "dmg": 10.0, "cd": 1.3, "reach": 115.0, "speed": 82.0, "radius": 7.0, "batch": 1},
	# 폭군 대병: 주변 침병의 공격 속도를 올린다. (고유 진화 "폭군의 혈통" 요구 조건은 연구 단계에서 추가)
	"tyrant": {"name": "폭군 대병", "food": 250, "mat": 150, "pop": 4.0, "time": 60.0, "tier": 3,
		"hp": 420.0, "dmg": 22.0, "cd": 1.1, "reach": 6.0, "speed": 70.0, "radius": 11.0, "batch": 1},
	# 방벽 개미: 거점화(root)하면 이동 불가, 받는 피해 60% 감소
	"wall": {"name": "방벽 개미", "food": 100, "mat": 30, "pop": 2.0, "time": 36.0, "tier": 2,
		"hp": 150.0, "dmg": 5.0, "cd": 1.0, "reach": 4.0, "speed": 70.0, "radius": 8.0, "batch": 1, "root": true},
	# 공중 유닛. air: 지형 무시, 근접 지상 유닛에게 공격받지 않는다
	"scout": {"name": "날개 정찰병", "food": 40, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 35.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 140.0, "radius": 5.0, "batch": 1, "air": true},
	"swarm": {"name": "혼인비행 떼", "food": 80, "mat": 70, "pop": 2.0, "time": 30.0, "tier": 2,
		"hp": 30.0, "dmg": 5.0, "cd": 0.9, "reach": 12.0, "speed": 120.0, "radius": 5.0, "batch": 2, "air": true,
		"hits_air": false},
}

# nest 의 mat/time 은 위성 둥지 기준이며 불개미 할인(-30%)이 반영된 값이다(공통 250M / 50초).
const BUILDINGS = {
	"nest": {"name": "불둔덕", "mat": 175, "time": 35.0, "hp": 1500.0, "radius": 40.0,
		"produces": ["worker"]},
	"combat": {"name": "독침 부화굴", "mat": 150, "time": 30.0, "hp": 650.0, "radius": 30.0,
		"produces": ["stinger", "sprayer", "tyrant"]},
	"defense": {"name": "병정 굴", "mat": 150, "time": 30.0, "hp": 750.0, "radius": 30.0,
		"produces": ["soldier", "wall"]},
	"special": {"name": "날개 산실", "mat": 200, "time": 40.0, "hp": 550.0, "radius": 30.0,
		"produces": ["scout", "swarm"], "min_tier": 2},
	"lab": {"name": "독샘 방", "mat": 200, "time": 40.0, "hp": 550.0, "radius": 28.0,
		"produces": []},
}

const RESEARCH = {
	"jaw1": {"name": "큰턱 강화 I", "mat": 100, "food": 50, "time": 60.0, "tip": "근접 공격력 +10%"},
	"shell1": {"name": "외골격 경화 I", "mat": 100, "food": 50, "time": 60.0, "tip": "받는 피해 -8%"},
	"carry1": {"name": "운반낭 발달 I", "mat": 150, "food": 0, "time": 60.0, "tip": "일꾼 운반량 +2"},
	"colony1": {"name": "군체 확대 I", "mat": 150, "food": 0, "time": 60.0, "tip": "인구 한도 +10"},
}

const NODES = {
	"seed": {"name": "씨앗 더미", "res": "food", "amount": 2000.0, "slots": 8, "infinite": false,
		"regen": 0.0, "dormancy": 0.0, "radius": 28.0, "harvest_time": 2.0, "color": Color(0.85, 0.75, 0.35)},
	"aphid": {"name": "진딧물 군락", "res": "food", "amount": 1.0, "slots": 6, "infinite": true,
		"regen": 0.0, "dormancy": 0.0, "radius": 26.0, "harvest_time": 2.5, "color": Color(0.55, 0.85, 0.45)},
	"litter": {"name": "낙엽 더미", "res": "mat", "amount": 1500.0, "slots": 6, "infinite": false,
		"regen": 0.0, "dormancy": 0.0, "radius": 28.0, "harvest_time": 2.0, "color": Color(0.6, 0.42, 0.22)},
	"plant": {"name": "살아있는 식물", "res": "mat", "amount": 600.0, "slots": 4, "infinite": false,
		"regen": 40.0, "dormancy": 60.0, "radius": 24.0, "harvest_time": 2.0, "color": Color(0.25, 0.6, 0.25)},
	"deadwood": {"name": "고목·수지", "res": "mat", "amount": 5000.0, "slots": 10, "infinite": false,
		"regen": 0.0, "dormancy": 0.0, "radius": 40.0, "harvest_time": 2.0, "color": Color(0.45, 0.3, 0.18)},
}

const FOOD_COLOR = Color(1.0, 0.85, 0.3)
const MAT_COLOR = Color(0.75, 0.55, 0.3)
