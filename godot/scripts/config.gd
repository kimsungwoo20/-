extends RefCounted
# 방 화면에서 정한 판 설정을 게임 장면으로 넘기는 보관함.
# setup = {"mode": "ffa" | "team", "balance": bool,
#          "slots": [{"type": "human" | "ai", "faction": "fire"..., "team": 0..4, "diff": "easy" | "normal" | "hard"}, ...]}
static var setup = null
# 방 화면을 어떤 목적으로 열었는가: solo(혼자 하기) / online(온라인 대전). 메인 화면이 정한다
static var lobby_mode = "solo"
