extends RefCounted
# 공통 규칙 수치. docs/system-design.md 의 [권장] 초기값을 그대로 옮긴 것이다.
# 진영별로 다른 값은 FACTIONS 와, 유닛·연구의 "faction" 항목에 있다.

const MAP_SIZE = Vector2(3200, 2000)
const POP_MAX = 200.0
const POP_MAX_BIG = 150.0              # 4~5인 판의 최대 인구(화면 안 유닛 수 관리)
const MAX_PLAYERS = 5
const PLAYER_COLORS = [Color(0.9, 0.25, 0.15), Color(0.25, 0.5, 0.95), Color(0.95, 0.8, 0.2),
	Color(0.7, 0.35, 0.9), Color(0.2, 0.85, 0.8)]
const FACTION_IDS = ["fire", "leaf", "weaver", "trap", "army"]
# 인공지능 난이도: tick = 판단 간격(초), workers = 일꾼 수 배율, wave = 첫 공격 병력 인구, gather = 채집 배율
const DIFFS = {
	"easy": {"name": "쉬움", "tick": 2.5, "workers": 0.6, "wave": 14, "gather": 1.0},
	"normal": {"name": "보통", "tick": 1.0, "workers": 1.0, "wave": 8, "gather": 1.0},
	"hard": {"name": "어려움", "tick": 0.6, "workers": 1.0, "wave": 8, "gather": 1.2},
}
const BALANCE_GATHER = 0.25            # 인원 불균형 보정: 모자란 인원 1명당 채집 +25%
const NEST_POP = [30, 60, 90]          # 주 둥지 등급 I / II / III
const SAT_POP = 15                     # 위성 둥지
const NEST_UPGRADE = {
	2: {"mat": 200, "time": 40.0},
	3: {"mat": 400, "time": 60.0},
}
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
const NEUTRAL_ID = 5                   # players[5] 는 중립 생물 전용 가상 플레이어(0~4 는 자리)
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

# ---- 지형 (4단계) ----
# [종류, 영역]. 왼쪽 절반만 적고 좌우 대칭으로 복사된다. 종류: 1 물, 2 절벽, 3 수목
const TREE_SPEED = 0.7                 # 수목 지대에서 지상 유닛 이동 속도 배율
const TERRAIN = [
	[1, Rect2(960, 800, 160, 400)],        # 기지와 중앙 사이의 호수: 돌아가거나 뗏목·공중으로 건넌다
	[2, Rect2(1056, 480, 352, 64)],        # 위쪽 길목을 만드는 절벽
	[2, Rect2(1056, 1456, 352, 64)],       # 아래쪽 길목을 만드는 절벽
	[3, Rect2(1376, 736, 128, 128)],       # 중앙 고목 주변 수목
	[3, Rect2(1376, 1136, 128, 128)],
	[3, Rect2(160, 1280, 192, 128)],       # 기지 뒤편 수목
	[3, Rect2(160, 560, 160, 96)],
]
const RAFT_CAPACITY = 8.0              # 뗏목단 탑승 한도(인구 기준)
const BOARD_REACH = 26.0

# reach: 공격 사거리(양쪽 반지름 제외). 30 이하는 근접.
# batch: 1회 생산 수. 불개미 T1 은 2기 한 조.
const UNITS = {
	# ---- 공통 ----
	"worker": {"name": "일꾼", "food": 50, "mat": 0, "pop": 1.0, "time": 12.0, "tier": 1,
		"hp": 40.0, "dmg": 3.0, "cd": 1.0, "reach": 4.0, "speed": 75.0, "radius": 6.0, "batch": 1},
	# ---- 불개미 ----
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
	# 뗏목단: 물 위를 다니는 수송 유닛. 고유 진화 "뗏목 진형" 필요
	"raft": {"name": "뗏목단", "food": 100, "mat": 50, "pop": 3.0, "time": 44.0, "tier": 2,
		"hp": 220.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 65.0, "radius": 13.0, "batch": 1,
		"amphibious": true, "needs": "raft_form"},
	# ---- 잎꾼개미 ----
	# 절단병: 평범하지만 공격·방어 연구 효과가 1.5배(upg)
	"cutter": {"name": "절단병", "food": 60, "mat": 0, "pop": 2.0, "time": 15.0, "tier": 1,
		"hp": 70.0, "dmg": 7.0, "cd": 1.0, "reach": 4.0, "speed": 85.0, "radius": 6.5, "batch": 1, "upg": 1.5},
	"major": {"name": "대턱 병정", "food": 140, "mat": 50, "pop": 3.0, "time": 50.0, "tier": 2,
		"hp": 240.0, "dmg": 16.0, "cd": 1.2, "reach": 5.0, "speed": 72.0, "radius": 9.5, "batch": 1},
	# 초대형 병정: 건물·거점화 유닛에 큰 피해, 긴 근접 사거리. 고유 진화 "초대형 계급" 필요
	"supermajor": {"name": "초대형 병정", "food": 300, "mat": 200, "pop": 6.0, "time": 60.0, "tier": 3,
		"hp": 650.0, "dmg": 26.0, "cd": 1.5, "reach": 20.0, "speed": 58.0, "radius": 14.0, "batch": 1,
		"siege": true, "needs": "supermajor_caste"},
	# 문지기: 거점화하면 통로를 막는다
	"gate": {"name": "문지기", "food": 70, "mat": 0, "pop": 2.0, "time": 17.5, "tier": 1,
		"hp": 130.0, "dmg": 4.0, "cd": 1.0, "reach": 4.0, "speed": 65.0, "radius": 8.0, "batch": 1, "root": true},
	# 호위 소형개미: 뛰어올라 공중 유닛도 문다. 빠른 적·공중 적에게 추가 피해
	"minim": {"name": "호위 소형개미", "food": 40, "mat": 0, "pop": 1.0, "time": 10.0, "tier": 1,
		"hp": 30.0, "dmg": 3.0, "cd": 0.8, "reach": 4.0, "speed": 100.0, "radius": 4.5, "batch": 1,
		"hits_air": true, "minim": true},
	# 길잡이 소형개미: 은신 감지, 주변 아군 일꾼 이동 속도 증가
	"pathfinder": {"name": "길잡이 소형개미", "food": 40, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 35.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 110.0, "radius": 4.5, "batch": 1,
		"sight": 300.0, "detect": 300.0},
	# 공생균 살포병: 주변 아군 회복
	"medic": {"name": "공생균 살포병", "food": 80, "mat": 40, "pop": 2.0, "time": 30.0, "tier": 2,
		"hp": 60.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 80.0, "radius": 6.5, "batch": 1},
	# 포자 살포 날개개미: 느린 공중 폭격기. 포자 지대가 건물·거점화 유닛에 지속 피해. 공중 공격 불가
	"spore": {"name": "포자 살포 날개개미", "food": 100, "mat": 100, "pop": 3.0, "time": 50.0, "tier": 2,
		"hp": 90.0, "dmg": 4.0, "cd": 2.0, "reach": 60.0, "speed": 60.0, "radius": 8.0, "batch": 1,
		"air": true, "hits_air": false, "spore": true},
	# ---- 베짜기개미 ----
	# 산성 분사병: 원거리, 작은 범위 피해(aoe)
	"acid": {"name": "산성 분사병", "food": 70, "mat": 0, "pop": 2.0, "time": 17.5, "tier": 1,
		"hp": 55.0, "dmg": 8.0, "cd": 1.2, "reach": 100.0, "speed": 82.0, "radius": 6.5, "batch": 1, "aoe": 22.0, "acid": true},
	# 사슬 견인병: 떨어진 적 1기를 자기 앞으로 끌어당긴다
	"puller": {"name": "사슬 견인병", "food": 120, "mat": 40, "pop": 3.0, "time": 45.0, "tier": 2,
		"hp": 180.0, "dmg": 10.0, "cd": 1.0, "reach": 5.0, "speed": 78.0, "radius": 9.0, "batch": 1, "pull": true},
	# 수관 군주: 주변에 이동식 임시 영역. 고유 진화 "수관의 군주" 필요
	"lord": {"name": "수관 군주", "food": 300, "mat": 200, "pop": 6.0, "time": 60.0, "tier": 3,
		"hp": 600.0, "dmg": 24.0, "cd": 1.2, "reach": 90.0, "speed": 60.0, "radius": 14.0, "batch": 1,
		"aoe": 30.0, "acid": true, "territory": 160.0, "needs": "canopy_lord"},
	# 고정병: 물고 늘어져 적을 이동 불가로 만든다
	"pinner": {"name": "고정병", "food": 70, "mat": 0, "pop": 2.0, "time": 17.5, "tier": 1,
		"hp": 120.0, "dmg": 4.0, "cd": 1.0, "reach": 4.0, "speed": 75.0, "radius": 7.5, "batch": 1, "pin": 1.5},
	# 장막 방직병: 거점화하면 비단 장막. 지나가는 적 감속, 장막 안 아군이 받는 원거리 피해 감소
	"curtain": {"name": "장막 방직병", "food": 90, "mat": 30, "pop": 2.0, "time": 34.0, "tier": 2,
		"hp": 110.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 70.0, "radius": 7.0, "batch": 1,
		"root": true, "curtain": true},
	"sentinel": {"name": "감시병", "food": 40, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 35.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 105.0, "radius": 4.5, "batch": 1,
		"sight": 260.0, "detect": 260.0},
	# 유충 운반공: 건물 수리, 끊어진 네트워크를 잇는 임시 고리
	"carrier": {"name": "유충 운반공", "food": 80, "mat": 40, "pop": 2.0, "time": 30.0, "tier": 2,
		"hp": 70.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 75.0, "radius": 7.0, "batch": 1,
		"repair": true, "territory": 150.0},
	"airsentry": {"name": "날개 파수꾼", "food": 90, "mat": 80, "pop": 2.0, "time": 38.0, "tier": 2,
		"hp": 70.0, "dmg": 9.0, "cd": 1.2, "reach": 95.0, "speed": 105.0, "radius": 7.0, "batch": 1,
		"air": true, "acid": true},
	# ---- 함정턱개미 ----
	# snap: 턱 타격(충전되면 3배 피해 + 밀쳐내기)
	"hunter": {"name": "격발병", "food": 100, "mat": 0, "pop": 2.0, "time": 25.0, "tier": 1,
		"hp": 100.0, "dmg": 12.0, "cd": 1.0, "reach": 4.0, "speed": 90.0, "radius": 7.0, "batch": 1, "snap": true},
	# 도약 사냥꾼: 턱 타격 후 뒤로 크게 뛰어 이탈. 뛰어올라 공중도 공격
	"leaper": {"name": "도약 사냥꾼", "food": 150, "mat": 50, "pop": 3.0, "time": 50.0, "tier": 2,
		"hp": 150.0, "dmg": 16.0, "cd": 1.0, "reach": 5.0, "speed": 95.0, "radius": 8.0, "batch": 1,
		"snap": true, "leap": true, "hits_air": true},
	# 대왕 포식자: 턱 타격이 대상 뒤로 직선 범위 피해. 고유 진화 "포식자의 왕" 필요
	"king": {"name": "대왕 포식자", "food": 320, "mat": 200, "pop": 6.0, "time": 60.0, "tier": 3,
		"hp": 600.0, "dmg": 30.0, "cd": 1.3, "reach": 8.0, "speed": 75.0, "radius": 13.0, "batch": 1,
		"snap": true, "line": true, "needs": "king_unlock"},
	# 덫지기: 거점화하면 은신. 은신 중 첫 타격 2배
	"trapper": {"name": "덫지기", "food": 100, "mat": 0, "pop": 2.0, "time": 25.0, "tier": 1,
		"hp": 110.0, "dmg": 10.0, "cd": 1.0, "reach": 4.0, "speed": 70.0, "radius": 7.0, "batch": 1,
		"root": true, "ambush": true},
	# 굴 수호자: 아군 건물 근처에서 턱 타격 충전이 빠르다
	"guardian": {"name": "굴 수호자", "food": 180, "mat": 50, "pop": 4.0, "time": 55.0, "tier": 2,
		"hp": 320.0, "dmg": 18.0, "cd": 1.1, "reach": 5.0, "speed": 70.0, "radius": 10.0, "batch": 1,
		"snap": true, "guard": true},
	# 그림자 척후: 움직여도 은신, 은신 감지
	"shade": {"name": "그림자 척후", "food": 50, "mat": 25, "pop": 1.0, "time": 19.0, "tier": 2,
		"hp": 40.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 115.0, "radius": 4.5, "batch": 1,
		"sight": 260.0, "detect": 250.0, "cloak": true},
	# 유인병: 버튼으로 주변 적을 자신에게 끌어들인다
	"lure": {"name": "유인병", "food": 80, "mat": 30, "pop": 2.0, "time": 32.0, "tier": 2,
		"hp": 140.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 85.0, "radius": 7.0, "batch": 1, "lure": true},
	# 낙하 사냥꾼: 공중에서 급강하 턱 타격. 타격 후 착지해 잠시 지상 유닛이 된다
	"diver": {"name": "낙하 사냥꾼", "food": 140, "mat": 100, "pop": 3.0, "time": 50.0, "tier": 2,
		"hp": 110.0, "dmg": 14.0, "cd": 1.2, "reach": 6.0, "speed": 120.0, "radius": 7.0, "batch": 1,
		"air": true, "hits_air": true, "snap": true, "dive": true},
	# ---- 군대개미 ----
	"raider": {"name": "약탈병", "food": 50, "mat": 0, "pop": 1.0, "time": 12.5, "tier": 1,
		"hp": 45.0, "dmg": 6.0, "cd": 0.8, "reach": 4.0, "speed": 125.0, "radius": 5.5, "batch": 1},
	"sickle": {"name": "낫턱 병정", "food": 120, "mat": 40, "pop": 3.0, "time": 45.0, "tier": 2,
		"hp": 130.0, "dmg": 22.0, "cd": 1.0, "reach": 5.0, "speed": 95.0, "radius": 8.5, "batch": 1},
	# 포식 대군: 주변 범위 피해, 처치할 때마다 회복. 고유 진화 "포식의 물결" 필요
	"horde": {"name": "포식 대군", "food": 300, "mat": 200, "pop": 6.0, "time": 60.0, "tier": 3,
		"hp": 700.0, "dmg": 20.0, "cd": 0.9, "reach": 8.0, "speed": 80.0, "radius": 15.0, "batch": 1,
		"aoe": 34.0, "aoe_mult": 1.0, "feast": true, "needs": "predator_wave"},
	# 수호병: 행군 중인 아군 건물 근처에서 받는 피해 감소
	"warden": {"name": "수호병", "food": 70, "mat": 0, "pop": 2.0, "time": 17.5, "tier": 1,
		"hp": 140.0, "dmg": 6.0, "cd": 1.0, "reach": 4.0, "speed": 85.0, "radius": 7.5, "batch": 1, "escort": true},
	# 다리 개미: 거점화하면 주변 물·절벽이 건널 수 있는 다리가 되고, 가까운 공중 유닛을 공격한다
	"bridge": {"name": "다리 개미", "food": 90, "mat": 30, "pop": 2.0, "time": 34.0, "tier": 2,
		"hp": 160.0, "dmg": 6.0, "cd": 1.0, "reach": 4.0, "speed": 75.0, "radius": 8.0, "batch": 1,
		"root": true, "bridge": true},
	"vanguard": {"name": "선발 정찰병", "food": 40, "mat": 20, "pop": 1.0, "time": 17.0, "tier": 2,
		"hp": 35.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 130.0, "radius": 4.5, "batch": 1,
		"sight": 300.0, "detect": 280.0},
	# 운반병: 이동식 반납 지점
	"porter": {"name": "운반병", "food": 80, "mat": 40, "pop": 2.0, "time": 30.0, "tier": 2,
		"hp": 120.0, "dmg": 0.0, "cd": 1.0, "reach": 0.0, "speed": 80.0, "radius": 9.0, "batch": 1, "depot": true},
	# 날개 수개미: 가장 빠른 공중 유닛. 공중 유닛만 공격
	"drone": {"name": "날개 수개미", "food": 80, "mat": 70, "pop": 2.0, "time": 34.0, "tier": 2,
		"hp": 60.0, "dmg": 10.0, "cd": 0.9, "reach": 14.0, "speed": 150.0, "radius": 6.0, "batch": 1,
		"air": true, "hits_air": true, "air_only": true, "sight": 300.0},
	# ---- 불개미 ----
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

# 공통 건물 규칙. 이름과 생산 목록은 진영(FACTIONS)이 정한다. nest 의 mat/time 은 위성 둥지 값
const BUILDINGS = {
	"nest": {"mat": 250, "time": 50.0, "hp": 1500.0, "radius": 40.0},
	"combat": {"mat": 150, "time": 30.0, "hp": 650.0, "radius": 30.0},
	"defense": {"mat": 150, "time": 30.0, "hp": 750.0, "radius": 30.0},
	"special": {"mat": 200, "time": 40.0, "hp": 550.0, "radius": 30.0, "min_tier": 2},
	"lab": {"mat": 200, "time": 40.0, "hp": 550.0, "radius": 28.0},
	# 전진 둥지: 베짜기개미 분기 진화 "뻗어가는 수관" 전용. 영역만 만들고 생산은 못 한다
	"tent": {"mat": 75, "time": 15.0, "hp": 300.0, "radius": 18.0},
}

const UPKEEP_COMMON = [[60.0, 1.0], [120.0, 0.85], [99999.0, 0.7]]

# 진영별 차이. 공통 규칙에서 바꾸는 값만 적는다(기획서 부록 A)
const FACTIONS = {
	"fire": {
		"name": "불개미",
		"buildings": {
			"nest": {"name": "불둔덕", "produces": ["worker"]},
			"combat": {"name": "독침 부화굴", "produces": ["stinger", "sprayer", "tyrant"]},
			"defense": {"name": "병정 굴", "produces": ["soldier", "wall"]},
			"special": {"name": "날개 산실", "produces": ["scout", "swarm", "nurse", "raft"]},
			"lab": {"name": "독샘 방", "produces": []},
		},
		"sat_nest_mult": 0.7,              # 분봉: 위성 둥지 비용·건설 시간 -30%
		"upkeep": [[60.0, 1.0], [120.0, 0.8], [99999.0, 0.6]],   # 왕성한 식욕: 유지비 가중
		"mat_carry_bonus": 0.0,
		"garden": [0, 0, 0, 0],
	},
	"leaf": {
		"name": "잎꾼개미",
		"buildings": {
			"nest": {"name": "균류 대정원", "produces": ["worker"]},
			"combat": {"name": "대턱 육성방", "produces": ["cutter", "major", "supermajor"]},
			"defense": {"name": "수문 병영", "produces": ["gate", "minim"]},
			"special": {"name": "공생균 배양방", "produces": ["pathfinder", "medic", "spore"]},
			"lab": {"name": "균사 연구실", "produces": []},
		},
		"sat_nest_mult": 1.0,
		"upkeep": UPKEEP_COMMON,
		"mat_carry_bonus": 5.0,            # 잎꾼 일꾼은 재료를 15 씩 나른다
		"garden": [4, 8, 12, 2],           # 정원사 슬롯: 주 둥지 I / II / III, 위성 둥지
	},
	"weaver": {
		"name": "베짜기개미",
		"buildings": {
			"nest": {"name": "잎 궁전", "produces": ["worker"]},
			"combat": {"name": "산성 둥지", "produces": ["acid", "puller", "lord"]},
			"defense": {"name": "수관 초소", "produces": ["pinner", "curtain"]},
			"special": {"name": "유충 방직실", "produces": ["sentinel", "carrier", "airsentry"]},
			"lab": {"name": "비단 직조실", "produces": []},
			"tent": {"name": "전진 둥지", "produces": []},
		},
		"sat_nest_mult": 1.0,
		"upkeep": UPKEEP_COMMON,
		"mat_carry_bonus": 0.0,
		"garden": [0, 0, 0, 0],
		"territory": true,                 # 건물이 수관 영역을 만들고, 영역 안에만 건설 가능
	},
	"trap": {
		"name": "함정턱개미",
		"buildings": {
			"nest": {"name": "고요한 굴", "produces": ["worker"]},
			"combat": {"name": "사냥꾼 굴", "produces": ["hunter", "leaper", "king"]},
			"defense": {"name": "덫지기 굴", "produces": ["trapper", "guardian"]},
			"special": {"name": "그림자 방", "produces": ["shade", "lure", "diver"]},
			"lab": {"name": "턱근 단련실", "produces": []},
		},
		"sat_nest_mult": 1.0,
		"upkeep": UPKEEP_COMMON,
		"mat_carry_bonus": 0.0,
		"carry_bonus": 5.0,                # 단독 사냥꾼: 일꾼이 무엇이든 5 더 나른다
		"worker_food": 75,                 # 일꾼이 비싸다
		"worker_dmg": 6.0,                 # 약한 자체 전투력
		"hidden_buildings": true,          # 본진 외 건물은 은폐(감지 범위 안에서만 보이고 공격받는다)
		"garden": [0, 0, 0, 0],
	},
	"army": {
		"name": "군대개미",
		"buildings": {
			"nest": {"name": "비부악", "produces": ["worker"]},
			"combat": {"name": "약탈대 대열", "produces": ["raider", "sickle", "horde"]},
			"defense": {"name": "호위대 대열", "produces": ["warden", "bridge"]},
			"special": {"name": "선발대 대열", "produces": ["vanguard", "porter", "drone"]},
			"lab": {"name": "여왕 근위 회랑", "produces": []},
		},
		"sat_nest_mult": 1.0,
		"upkeep": UPKEEP_COMMON,
		"mat_carry_bonus": 0.0,
		"garden": [0, 0, 0, 0],
		"mobile": true,                    # 모든 건물이 야영 ↔ 행군 전환
		"building_mult": 0.6,              # 살아있는 건축: 건물 재료 비용 -40%
		"building_pop": 3.0,               # 대신 본진 외 건물 1동당 인구 3 점유
		"loot": true,                      # 약탈: 적 일꾼·건물 처치 시 자원
		"no_aphid": true,                  # 포식: 진딧물은 채집하지 못하고 도살만
		"corpse_harvest": 0.6,             # 사체 채집 시간 배율
		"sight_mult": 0.7,                 # 시야가 좁다(선발 정찰병·날개 수개미 제외)
	},
}

# ---- 야영과 행군 (군대개미) ----
const PACK_TIME = 10.0                 # 야영 → 행군 전환
const UNPACK_TIME = 15.0               # 행군 → 야영 전환
const PACK_TIME_WANDER = 2.0           # 영원한 유랑
const UNPACK_TIME_WANDER = 3.0
const PACK_TIME_STATARY = 20.0         # 정주기 산란
const MARCH_SPEED = 35.0
const MARCH_SPEED_GREAT = 55.0         # 대행군
const MARCH_PRODUCTION = 0.5           # 행군 중 유닛 생산 속도
const MARCH_PRODUCTION_GREAT = 0.75
const MARCH_TAKEN = 1.25               # 야영 중이 아닌 건물이 받는 피해
const STATARY_AFTER = 60.0             # 정주기 산란: 야영이 이만큼 이어지면
const STATARY_SPEED = 1.5              # 생산 속도 배율
const LOOT_RATE = 0.2                  # 약탈: 대상 비용의 20%
const LOOT_RATE_INSTINCT = 0.35        # 약탈 본능
const LOOT_COMBAT_RATE = 0.1           # 약탈 본능: 전투 유닛 처치 시
const ESCORT_RADIUS = 200.0
const ESCORT_TAKEN = 0.7               # 수호병: 행군 중인 아군 건물 근처에서 받는 피해
const BRIDGE_RADIUS = 80.0
const BRIDGE_RADIUS_LIVING = 120.0     # 살아있는 다리
const BRIDGE_SPEED = 1.3               # 살아있는 다리: 다리 위 아군 이동 속도
const TOWER_REACH = 110.0              # 살아있는 탑: 거점화한 다리 개미의 대공 사거리
const FEAST_HEAL = 0.15                # 포식 대군: 처치 시 최대 체력의 15% 회복
const HOOK_TIME = 2.0
const HOOK_SLOW = 0.7

# ---- 턱 타격 (함정턱개미) ----
const SNAP_MULT = 3.0                  # 충전된 턱 타격 피해 배율
const SNAP_CHARGE = 4.0                # 공격하지 않고 이만큼 지나면 턱 타격 충전
const SNAP_CHARGE_GUARD = 2.0          # 굴 수호자: 아군 건물 근처에서 충전 시간
const GUARD_RADIUS = 200.0
const SNAP_KNOCK = 40.0                # 밀쳐내기 거리
const SNAP_KNOCK_POWER = 80.0          # 강화 격발
const SNAP_STUN = 1.0                  # 강화 격발: 기절 시간
const KING_LINE = 70.0                 # 대왕 포식자: 대상 뒤로 이어지는 직선 범위 길이
const KING_LINE_WIDTH = 22.0
const KING_LINE_MULT = 0.6
const LEAP_DIST = 120.0
const LEAP_CD = 10.0
const LEAP_CD_MASTER = 6.0
const STEALTH_REVEAL = 3.0             # 공격하면 은신이 풀리고 이만큼 지나야 다시 숨는다
const STILL_TIME = 1.5                 # 완전 매복: 이만큼 멈춰 있으면 은신
const AMBUSH_MULT = 2.0                # 덫지기: 은신 중 첫 타격 배율
const FULL_AMBUSH_MULT = 1.5           # 완전 매복: 은신 중 턱 타격 추가 배율
const CHAIN_MAX = 2
const LONE_RADIUS = 200.0
const LONE_BONUS = 0.3                 # 고독한 사냥꾼: 주변 아군 0 기일 때 +30%, 1 기당 -10%p
const PACK_WINDOW = 0.5
const PACK_RADIUS = 150.0
const PACK_COUNT = 3
const PACK_SHOCK_DMG = 40.0
const PACK_SHOCK_RADIUS = 80.0
const LURE_RADIUS = 180.0
const LURE_TIME = 4.0
const LURE_CD = 20.0
const LURE_IMMUNE = 10.0
const DIVE_GROUND_TIME = 5.0           # 낙하 사냥꾼이 착지해 지상에 머무는 시간

# ---- 수관 영역 (베짜기개미) ----
const TERR_RADIUS = {"nest": 280.0, "combat": 220.0, "defense": 300.0, "special": 220.0, "lab": 220.0, "tent": 160.0}
const TERR_SPEED_IN = 1.15             # 주 둥지와 연결된 영역 안 이동 속도
const TERR_SPEED_SILK = 1.6            # 비단길 연구 후
const TERR_SPEED_OUT = 0.85            # 영역 밖
const TERR_SPEED_OUT_FORT = 0.75       # 철옹성 선택 시 영역 밖
const TERR_REGEN = 1.0                 # 연결된 영역 안 유닛 초당 회복
const TERR_GATHER = 1.2                # 연결된 영역 안 채집 속도
const TERR_CUT_PRODUCTION = 0.7        # 끊어진 구역 건물의 생산 속도
const CHAIN_LINK_MULT = 1.25           # 살아있는 사슬: 연결 가능 거리
const CHAIN_GRACE = 30.0               # 살아있는 사슬: 끊어진 뒤 보너스 유지 시간
const ACID_SAT_RANGE = 1.25
const ACID_SAT_AOE = 1.5
const ACID_POOL_TIME = 3.0
const ACID_POOL_DPS = 3.0
const ACID_POOL_RADIUS = 25.0
const AOE_SPLASH = 0.5                 # 범위 공격이 주변 적에게 주는 피해 비율
const PULL_RANGE = 140.0
const PULL_COOLDOWN = 8.0
const CURTAIN_RADIUS = 90.0
const CURTAIN_SLOW = 0.4
const CURTAIN_AIR_SLOW = 0.5
const CURTAIN_RANGED_TAKEN = 0.7
const CARRIER_RADIUS = 120.0
const CARRIER_REPAIR = 5.0
const SENTINEL_TERR_SIGHT = 1.6
const AIRSENTRY_TERR_CD = 0.77
const FORT_HP = 1.3
const FORT_REGEN = 3.0

# 균류 정원: 정원사 1기가 초당 재료 0.75 를 식량으로 바꾼다(분당 재료 45 → 식량 90)
const GARDEN_MAT_PER_SEC = 0.75
const GARDEN_RATIO = 2.0
const GARDEN_RATIO_HIGH = 2.5          # 고수확 균주
const GARDEN_DAMAGED_MULT = 0.5        # 본진 체력 50% 미만이면 정원 효율 절반
const BIG_GARDEN_MULT = 1.5            # 분기: 거대 정원
const MEDIC_RADIUS = 120.0
const MEDIC_HEAL = 3.0                 # 초당 회복
const PATHFINDER_RADIUS = 150.0
const PATHFINDER_WORKER_SPEED = 1.2
const SHEAR_MULT = 1.5                 # 절단 턱: 건물·거점화 유닛에 추가 피해
const SIEGE_MULT = 2.5                 # 초대형 병정: 건물·거점화 유닛에 큰 피해
const MINIM_BONUS = 1.5                # 호위 소형개미: 빠른 적·공중 적에게 추가 피해
const FAST_SPEED = 100.0
const SPORE_ZONE_TIME = 6.0
const SPORE_ZONE_RADIUS = 50.0
const SPORE_ZONE_DPS = 6.0
const HITCH_TAKEN = 0.7                # 탑승 호위: 일꾼이 받는 피해 -30%
const HITCH_REFLECT = 2.0              # 탑승 호위: 일꾼을 때린 적에게 반격 피해
const WAR_FUNGUS_FOOD = 300
const WAR_FUNGUS_SHIELD = 40.0
const WAR_FUNGUS_TIME = 20.0
const WAR_FUNGUS_COOLDOWN = 90.0

static func faction_building(f, kind):
	var out = BUILDINGS[kind].duplicate()
	var fd = FACTIONS[f]
	out.merge(fd["buildings"][kind], true)
	if kind == "nest":
		out["mat"] = int(round(out["mat"] * fd["sat_nest_mult"]))
		out["time"] = out["time"] * fd["sat_nest_mult"]
	out["mat"] = int(round(out["mat"] * fd.get("building_mult", 1.0)))
	# 본진 외 건물이 차지하는 인구(군대개미)
	out["pop"] = fd.get("building_pop", 0.0) if kind != "nest" else 0.0
	return out

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
		"tip": "전투 유닛의 공격이 중첩 독(초당 1, 5초, 최대 5중첩)을 남긴다", "req": "", "group": "", "faction": "fire"},
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
		"tip": "위성 둥지 일꾼 생산 감속 제거. 주 둥지가 파괴되면 계승이 즉시 이루어지고 등급이 떨어지지 않음", "req": "", "group": "", "faction": "fire"},
	"alarm": {"name": "경보 페로몬", "cat": "unique", "line": "alarm", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "아군 전투 유닛이 죽으면 주변 아군 공격 속도 +10% (5초, 최대 3중첩)", "req": "", "group": "", "faction": "fire"},
	"raft_form": {"name": "뗏목 진형", "cat": "unique", "line": "raft_form", "lvl": 1, "tier": 2, "mat": 150, "food": 0, "time": 60.0,
		"tip": "뗏목단 생산 가능. 물을 건너 유닛을 실어 나른다", "req": "", "group": "", "faction": "fire"},
	"shear1": {"name": "절단 턱", "cat": "body", "line": "shear", "lvl": 1, "tier": 2, "mat": 200, "food": 100, "time": 90.0,
		"tip": "전투 유닛이 건물과 거점화 유닛에 50% 추가 피해", "req": "", "group": "", "faction": "leaf"},
	"high_yield": {"name": "고수확 균주", "cat": "unique", "line": "high_yield", "lvl": 1, "tier": 2, "mat": 200, "food": 0, "time": 75.0,
		"tip": "균류 정원 변환 비율 재료 1 → 식량 2.5", "req": "", "group": "", "faction": "leaf"},
	"hitchhiker": {"name": "탑승 호위", "cat": "unique", "line": "hitchhiker", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "일꾼이 받는 피해 -30%, 일꾼을 공격한 적에게 반격 피해", "req": "", "group": "", "faction": "leaf"},
	"antibiotic": {"name": "항생 공생균", "cat": "unique", "line": "antibiotic", "lvl": 1, "tier": 2, "mat": 150, "food": 0, "time": 60.0,
		"tip": "공생균 살포병이 건물도 회복. 본진이 손상돼도 정원 효율 유지", "req": "", "group": "", "faction": "leaf"},
	"supermajor_caste": {"name": "초대형 계급", "cat": "unique", "line": "supermajor_caste", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "초대형 병정 생산 가능", "req": "", "group": "", "faction": "leaf"},
	"big_garden": {"name": "[분기] 거대 정원", "cat": "unique", "line": "big_garden", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "정원사 슬롯 +50%. 전쟁 균류와 동시 선택 불가", "req": "", "group": "branch", "faction": "leaf"},
	"war_fungus": {"name": "[분기] 전쟁 균류", "cat": "unique", "line": "war_fungus", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "주 둥지에서 식량 300 으로 전 병력에 포자 갑옷(피해 40 흡수, 20초) 부여. 재사용 90초. 거대 정원과 동시 선택 불가", "req": "", "group": "branch", "faction": "leaf"},
	"acid_pool": {"name": "농축 개미산", "cat": "body", "line": "acid_pool", "lvl": 1, "tier": 2, "mat": 200, "food": 100, "time": 90.0,
		"tip": "산성 공격이 바닥에 3초간 남아 지나가는 적에게 피해", "req": "", "group": "", "faction": "weaver"},
	"silk_road": {"name": "비단길", "cat": "unique", "line": "silk_road", "lvl": 1, "tier": 2, "mat": 200, "food": 0, "time": 75.0,
		"tip": "연결된 영역 안 이동 속도 +15% → +60%", "req": "", "group": "", "faction": "weaver"},
	"living_chain": {"name": "살아있는 사슬", "cat": "unique", "line": "living_chain", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "영역 연결 가능 거리 +25%. 끊어진 구역이 30초간 보너스 유지", "req": "", "group": "", "faction": "weaver"},
	"acid_sat": {"name": "개미산 포화", "cat": "unique", "line": "acid_sat", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "연결된 영역 안에서 산성 공격 사거리 +25%, 범위 +50%", "req": "", "group": "", "faction": "weaver"},
	"canopy_lord": {"name": "수관의 군주", "cat": "unique", "line": "canopy_lord", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "수관 군주 생산 가능", "req": "", "group": "", "faction": "weaver"},
	"fortress": {"name": "[분기] 철옹성", "cat": "unique", "line": "fortress", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "건물 체력 +30%, 연결된 영역 안 건물 초당 3 회복. 영역 밖 이동 속도 불이익 증가. 뻗어가는 수관과 동시 선택 불가", "req": "", "group": "branch", "faction": "weaver"},
	"spreading": {"name": "[분기] 뻗어가는 수관", "cat": "unique", "line": "spreading", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "일꾼이 영역 밖에도 전진 둥지(작은 영역, 생산 불가)를 지을 수 있다. 철옹성과 동시 선택 불가", "req": "", "group": "branch", "faction": "weaver"},
	"power_snap": {"name": "강화 격발", "cat": "body", "line": "power_snap", "lvl": 1, "tier": 2, "mat": 200, "food": 100, "time": 90.0,
		"tip": "턱 타격의 밀쳐내기 거리 2배, 밀려난 적 1초 기절", "req": "", "group": "", "faction": "trap"},
	"full_ambush": {"name": "완전 매복", "cat": "unique", "line": "full_ambush", "lvl": 1, "tier": 2, "mat": 200, "food": 50, "time": 75.0,
		"tip": "모든 전투 유닛이 1.5초 멈춰 있으면 은신. 은신 중 턱 타격 피해 1.5배", "req": "", "group": "", "faction": "trap"},
	"leap_master": {"name": "턱 도약 숙련", "cat": "unique", "line": "leap_master", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "턱 도약으로 절벽과 물을 넘는다. 재사용 대기 10초 → 6초", "req": "", "group": "", "faction": "trap"},
	"chain_snap": {"name": "연쇄 격발", "cat": "unique", "line": "chain_snap", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "턱 타격으로 적을 처치하면 즉시 재충전(연속 2회까지)", "req": "", "group": "", "faction": "trap"},
	"king_unlock": {"name": "포식자의 왕", "cat": "unique", "line": "king_unlock", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "대왕 포식자 생산 가능", "req": "", "group": "", "faction": "trap"},
	"lone_hunter": {"name": "[분기] 고독한 사냥꾼", "cat": "unique", "line": "lone_hunter", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "주변 200 안에 아군이 없으면 공격력·이동 속도 +30%, 아군 1기당 -10%p. 사냥 무리와 동시 선택 불가", "req": "", "group": "branch", "faction": "trap"},
	"pack": {"name": "[분기] 사냥 무리", "cat": "unique", "line": "pack", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "0.5초 안에 3기 이상이 가까이서 턱 타격을 하면 충격파(범위 80, 피해 40). 고독한 사냥꾼과 동시 선택 불가", "req": "", "group": "branch", "faction": "trap"},
	"hook_jaw": {"name": "갈고리 턱", "cat": "body", "line": "hook_jaw", "lvl": 1, "tier": 2, "mat": 200, "food": 100, "time": 90.0,
		"tip": "전투 유닛에게 맞은 적은 2초 동안 이동 속도 -30%", "req": "", "group": "", "faction": "army"},
	"great_march": {"name": "대행군", "cat": "unique", "line": "great_march", "lvl": 1, "tier": 2, "mat": 200, "food": 0, "time": 75.0,
		"tip": "행군 속도 증가, 행군 중 생산 속도 50% → 75%", "req": "", "group": "", "faction": "army"},
	"loot_instinct": {"name": "약탈 본능", "cat": "unique", "line": "loot_instinct", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "약탈 20% → 35%. 적 전투 유닛을 처치해도 비용의 10% 를 식량으로 얻는다", "req": "", "group": "", "faction": "army"},
	"living_bridge": {"name": "살아있는 다리", "cat": "unique", "line": "living_bridge", "lvl": 1, "tier": 2, "mat": 150, "food": 50, "time": 60.0,
		"tip": "다리 개미가 더 넓은 범위를 잇고, 다리 위 아군 이동 속도 +30%", "req": "", "group": "", "faction": "army"},
	"predator_wave": {"name": "포식의 물결", "cat": "unique", "line": "predator_wave", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "포식 대군 생산 가능", "req": "", "group": "", "faction": "army"},
	"eternal_wander": {"name": "[분기] 영원한 유랑", "cat": "unique", "line": "eternal_wander", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "야영·행군 전환 10초/15초 → 2초/3초. 행군 중에도 일꾼 생산. 정주기 산란과 동시 선택 불가", "req": "", "group": "branch", "faction": "army"},
	"statary_brood": {"name": "[분기] 정주기 산란", "cat": "unique", "line": "statary_brood", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "야영이 60초 넘게 이어지면 모든 생산 속도 1.5배. 행군 전환 10초 → 20초. 영원한 유랑과 동시 선택 불가", "req": "", "group": "branch", "faction": "army"},
	"tyrant_blood": {"name": "폭군의 혈통", "cat": "unique", "line": "tyrant_blood", "lvl": 1, "tier": 3, "mat": 250, "food": 0, "time": 90.0,
		"tip": "폭군 대병 생산 가능", "req": "", "group": "", "faction": "fire"},
	"wave": {"name": "[분기] 끝없는 물결", "cat": "unique", "line": "wave", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "침병·병정개미가 3기 한 조로 생산. 유지비 감소폭 1.25배. 타오르는 독과 동시 선택 불가", "req": "", "group": "branch", "faction": "fire"},
	"burn": {"name": "[분기] 타오르는 독", "cat": "unique", "line": "burn", "lvl": 1, "tier": 3, "mat": 300, "food": 150, "time": 120.0,
		"tip": "독이 건물에도 들어가고 최대 중첩 5→8. 끝없는 물결과 동시 선택 불가", "req": "venom1", "group": "branch", "faction": "fire"},
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
