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
const RESEARCH_QUEUE = 4               # 진행 1 + 예약 3
const VENOM_DPS = 1.0
const VENOM_TIME = 5.0
const VENOM_STACKS = 5
const VENOM_STACKS_BURN = 8
const ALARM_RADIUS = 150.0
const ALARM_TIME = 5.0
const ALARM_STACKS = 3
const NURSE_RADIUS = 200.0
const NURSE_REFUND = 2.5               # 죽은 유닛 1기당 앞당기는 생산 시간(초)
const TROPH_PENALTY = [1.0, 0.75, 0.5] # 영양 교환 단계별 유지비 감소폭 배율
const WAVE_PENALTY = 1.25

# ---- 지도 요소 (3단계) ----
const NEUTRAL_ID = 2                   # players[2] 는 중립 생물 전용 가상 플레이어
const LEASH = 260.0                    # 중립 생물이 둥지에서 이만큼 끌려 나오면 돌아간다
const NEUTRAL_RESPAWN = 180.0
const CORPSE_DECAY = 180.0
const CENTER_DROP_EVERY = 240.0        # 맵 중앙에 사체가 떨어지는 주기
const CENTER_DROP_AMOUNT = 800.0
const APHID_HP = 300.0
const APHID_SLAY_FOOD = 150.0
const APHID_RESPAWN = 120.0
const APHID_REGEN = 2.0
const APHID_REGEN_DELAY = 5.0
const FOG_CELL = 32.0
const SIGHT_UNIT = 170.0
const SIGHT_WORKER = 140.0
const SIGHT_BUILDING = 220.0
const SIGHT_NEST = 300.0
const DETECT_NEST = 300.0              # 본진은 은신 유닛을 감지한다

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
	# 폭군 대병: 주변 침병의 공격 속도를 올린다. 고유 진화 "폭군의 혈통" 필요
	"tyrant": {"name": "폭군 대병", "food": 250, "mat": 150, "pop": 4.0, "time": 60.0, "tier": 3,
		"hp": 420.0, "dmg": 22.0, "cd": 1.1, "reach": 6.0, "speed": 70.0, "radius": 11.0, "batch": 1,
		"needs": "tyrant_blood"},
	# 보모 개미: 근처에서 아군 침병·병정개미가 죽으면 가까운 생산 건물의 진행도를 앞당긴다
	"nurse": {"name": "보모 개미", "food": 50, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 40.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 90.0, "radius": 5.0, "batch": 1},
	# 방벽 개미: 거점화(root)하면 이동 불가, 받는 피해 60% 감소
	"wall": {"name": "방벽 개미", "food": 100, "mat": 30, "pop": 2.0, "time": 36.0, "tier": 2,
		"hp": 150.0, "dmg": 5.0, "cd": 1.0, "reach": 4.0, "speed": 70.0, "radius": 8.0, "batch": 1, "root": true},
	# 공중 유닛. air: 지형 무시, 근접 지상 유닛에게 공격받지 않는다
	"scout": {"name": "날개 정찰병", "food": 40, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 35.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 140.0, "radius": 5.0, "batch": 1, "air": true,
		"sight": 320.0, "detect": 320.0},
	# 날개 정찰병은 은신 감지(detect)와 넓은 시야
	"swarm": {"name": "혼인비행 떼", "food": 80, "mat": 70, "pop": 2.0, "time": 30.0, "tier": 2,
		"hp": 30.0, "dmg": 5.0, "cd": 0.9, "reach": 12.0, "speed": 120.0, "radius": 5.0, "batch": 2, "air": true,
		"hits_air": false},
}

# 중립 생물. 먼저 공격하지 않고, 공격받으면 같은 무리가 함께 반격한다. 죽으면 사체(식량)를 남긴다
const NEUTRALS = {
	"grub": {"name": "딱정벌레 유충", "food": 0, "mat": 0, "pop": 0.0, "time": 0.0, "tier": 1, "batch": 1,
		"hp": 120.0, "dmg": 4.0, "cd": 1.2, "reach": 4.0, "speed": 45.0, "radius": 8.0, "corpse": 300.0},
	"spider": {"name": "거미", "food": 0, "mat": 0, "pop": 0.0, "time": 0.0, "tier": 1, "batch": 1,
		"hp": 400.0, "dmg": 10.0, "cd": 1.0, "reach": 6.0, "speed": 70.0, "radius": 11.0, "corpse": 700.0},
	"mantis": {"name": "사마귀", "food": 0, "mat": 0, "pop": 0.0, "time": 0.0, "tier": 1, "batch": 1,
		"hp": 1200.0, "dmg": 22.0, "cd": 1.4, "reach": 14.0, "speed": 60.0, "radius": 16.0, "corpse": 1500.0},
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
		"produces": ["scout", "swarm", "nurse"], "min_tier": 2},
	"lab": {"name": "독샘 방", "mat": 200, "time": 40.0, "hp": 550.0, "radius": 28.0,
		"produces": []},
}

# 연구. tier: 필요한 주 둥지 등급, req: 선행 연구, group: 같은 group 은 하나만 선택(분기 진화)
const RESEARCH = {
	"jaw1": {"name": "큰턱 강화 I", "cat": "body", "line": "jaw", "lvl": 1, "tier": 1, "mat": 100, "food": 50, "time": 60.0,
		"tip": "근접 공격력 +10%", "req": "", "group": ""},
	"jaw2": {"name": "큰턱 강화 II", "cat": "body", "line": "jaw", "lvl": 2, "tier": 2, "mat": 175, "food": 100, "time": 90.0,
		"tip": "근접 공격력 +10%", "req": "jaw1", "group": ""},
	"jaw3": {"name": "큰턱 강화 III", "cat": "body", "line": "jaw", "lvl": 3, "tier": 3, "mat": 250, "food": 150, "time": 120.0,
		"tip": "근접 공격력 +10%", "req": "jaw2", "group": ""},
	"gland1": {"name": "분비샘 강화 I", "cat": "body", "line": "gland", "lvl": 1, "tier": 1, "mat": 100, "food": 50, "time": 60.0,
		"tip": "원거리 공격력 +10%", "req": "", "group": ""},
	"gland2": {"name": "분비샘 강화 II", "cat": "body", "line": "gland", "lvl": 2, "tier": 2, "mat": 175, "food": 100, "time": 90.0,
		"tip": "원거리 공격력 +10%", "req": "gland1", "group": ""},
	"gland3": {"name": "분비샘 강화 III", "cat": "body", "line": "gland", "lvl": 3, "tier": 3, "mat": 250, "food": 150, "time": 120.0,
		"tip": "원거리 공격력 +10%", "req": "gland2", "group": ""},
	"shell1": {"name": "외골격 경화 I", "cat": "body", "line": "shell", "lvl": 1, "tier": 1, "mat": 100, "food": 50, "time": 60.0,
		"tip": "받는 피해 -8%", "req": "", "group": ""},
	"shell2": {"name": "외골격 경화 II", "cat": "body", "line": "shell", "lvl": 2, "tier": 2, "mat": 175, "food": 100, "time": 90.0,
		"tip": "받는 피해 -8%", "req": "shell1", "group": ""},
	"shell3": {"name": "외골격 경화 III", "cat": "body", "line": "shell", "lvl": 3, "tier": 3, "mat": 250, "food": 150, "time": 120.0,
		"tip": "받는 피해 -8%", "req": "shell2", "group": ""},
	"size1": {"name": "체격 증대 I", "cat": "body", "line": "size", "lvl": 1, "tier": 2, "mat": 150, "food": 100, "time": 75.0,
		"tip": "체력 +10%", "req": "", "group": ""},
	"size2": {"name": "체격 증대 II", "cat": "body", "line": "size", "lvl": 2, "tier": 3, "mat": 250, "food": 150, "time": 105.0,
		"tip": "체력 +10%", "req": "size1", "group": ""},
	"legs1": {"name": "다리 근육", "cat": "body", "line": "legs", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 75.0,
		"tip": "지상 유닛 이동 속도 +10%", "req": "", "group": ""},
	"flight1": {"name": "비행 근육", "cat": "body", "line": "flight", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 75.0,
		"tip": "공중 유닛 이동 속도 +15%, 체력 +10%", "req": "", "group": ""},
	"venom1": {"name": "솔레놉신 독침", "cat": "body", "line": "venom", "lvl": 1, "tier": 2, "mat": 200, "food": 100, "time": 90.0,
		"tip": "전투 유닛의 공격이 중첩 독(초당 1, 5초, 최대 5중첩)을 남긴다", "req": "", "group": ""},
	"spawn1": {"name": "산란 촉진 I", "cat": "colony", "line": "spawn", "lvl": 1, "tier": 1, "mat": 100, "food": 0, "time": 60.0,
		"tip": "일꾼 생산 시간 -15%", "req": "", "group": ""},
	"spawn2": {"name": "산란 촉진 II", "cat": "colony", "line": "spawn", "lvl": 2, "tier": 2, "mat": 175, "food": 0, "time": 90.0,
		"tip": "일꾼 생산 시간 -15%", "req": "spawn1", "group": ""},
	"carry1": {"name": "운반낭 발달 I", "cat": "colony", "line": "carry", "lvl": 1, "tier": 1, "mat": 150, "food": 0, "time": 60.0,
		"tip": "일꾼 운반량 +2", "req": "", "group": ""},
	"carry2": {"name": "운반낭 발달 II", "cat": "colony", "line": "carry", "lvl": 2, "tier": 2, "mat": 250, "food": 0, "time": 90.0,
		"tip": "일꾼 운반량 +2", "req": "carry1", "group": ""},
	"colony1": {"name": "군체 확대 I", "cat": "colony", "line": "colony", "lvl": 1, "tier": 1, "mat": 150, "food": 0, "time": 60.0,
		"tip": "인구 한도 +10", "req": "", "group": ""},
	"colony2": {"name": "군체 확대 II", "cat": "colony", "line": "colony", "lvl": 2, "tier": 2, "mat": 250, "food": 0, "time": 90.0,
		"tip": "인구 한도 +10", "req": "colony1", "group": ""},
	"nursery1": {"name": "육아 효율 I", "cat": "colony", "line": "nursery", "lvl": 1, "tier": 1, "mat": 150, "food": 0, "time": 60.0,
		"tip": "전투 유닛 생산 시간 -10%", "req": "", "group": ""},
	"nursery2": {"name": "육아 효율 II", "cat": "colony", "line": "nursery", "lvl": 2, "tier": 2, "mat": 250, "food": 0, "time": 90.0,
		"tip": "전투 유닛 생산 시간 -10%", "req": "nursery1", "group": ""},
	"troph1": {"name": "영양 교환 I", "cat": "colony", "line": "troph", "lvl": 1, "tier": 2, "mat": 200, "food": 0, "time": 75.0,
		"tip": "유지비로 줄어드는 식량 수입 25%p씩 완화", "req": "", "group": ""},
	"troph2": {"name": "영양 교환 II", "cat": "colony", "line": "troph", "lvl": 2, "tier": 3, "mat": 300, "food": 0, "time": 105.0,
		"tip": "유지비로 줄어드는 식량 수입 25%p씩 완화", "req": "troph1", "group": ""},
	"multiqueen": {"name": "다여왕 군체", "cat": "unique", "line": "multiqueen", "lvl": 1, "tier": 2, "mat": 200, "food": 0, "time": 75.0,
		"tip": "위성 둥지 일꾼 생산 감속 제거. 주 둥지가 파괴되면 계승이 즉시 이루어지고 등급이 떨어지지 않음", "req": "", "group": ""},
	"alarm": {"name": "경보 페로몬", "cat": "unique", "line": "alarm", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "아군 전투 유닛이 죽으면 주변 아군 공격 속도 +10% (5초, 최대 3중첩)", "req": "", "group": ""},
	"tyrant_blood": {"name": "폭군의 혈통", "cat": "unique", "line": "tyrant_blood", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "폭군 대병 생산 가능", "req": "", "group": ""},
	"wave": {"name": "[분기] 끝없는 물결", "cat": "unique", "line": "wave", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "침병·병정개미가 3기 한 조로 생산. 유지비 감소폭 1.25배. 타오르는 독과 동시 선택 불가", "req": "", "group": "branch"},
	"burn": {"name": "[분기] 타오르는 독", "cat": "unique", "line": "burn", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "독이 건물에도 들어가고 최대 중첩 5→8. 끝없는 물결과 동시 선택 불가", "req": "venom1", "group": "branch"},
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
	"corpse": {"name": "사체", "res": "food", "amount": 500.0, "slots": 6, "infinite": false,
		"regen": 0.0, "dormancy": 0.0, "radius": 22.0, "harvest_time": 2.0, "color": Color(0.7, 0.5, 0.45)},
	"deadwood": {"name": "고목·수지", "res": "mat", "amount": 5000.0, "slots": 10, "infinite": false,
		"regen": 0.0, "dormancy": 0.0, "radius": 40.0, "harvest_time": 2.0, "color": Color(0.45, 0.3, 0.18)},
}

const FOOD_COLOR = Color(1.0, 0.85, 0.3)
const MAT_COLOR = Color(0.75, 0.55, 0.3)
