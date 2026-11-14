extends Control
# 방 화면: 자리 5개를 사람(나) / 인공지능 / 비움으로 정하고 진영·팀·난이도를 고른다.
# 사람끼리의 온라인 대전(11단계) 전까지는 사람 1명 + 인공지능 1~4명의 솔로 판이다.
const Data = preload("res://scripts/data.gd")
const ConfigScript = preload("res://scripts/config.gd")

const FACTION_CHOICES = ["random", "fire", "leaf", "weaver", "trap", "army"]
const DIFF_CHOICES = ["easy", "normal", "hard"]

var rows = []          # 자리마다 {type, faction, team, diff} 옵션 버튼
var mode_btn
var balance_chk
var info
var start_btn

func _ready():
	# 점검·자동 대전 실행이나, 주소로 진영을 정한 경우에는 방 화면을 건너뛴다
	var args = OS.get_cmdline_user_args()
	var skip = args.has("--autotest") or args.has("--sandbox")
	if OS.has_feature("web"):
		var q = str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("me=") or q.contains("ai="):
			skip = true
	if skip and ConfigScript.setup == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	_build()

func _label(text, size = 16):
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _option(items, selected):
	var o = OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(selected)
	o.custom_minimum_size = Vector2(140, 36)
	o.item_selected.connect(func(_i): _refresh())
	return o

func _build():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(_label("개미 RTS — 솔로 모드", 30))
	box.add_child(_label("자리를 정하고 시작하세요. 사람끼리의 온라인 대전은 아직 없습니다.", 14))

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	top.add_child(_label("대전 형태"))
	mode_btn = _option(["개인전", "팀전"], 0)
	top.add_child(mode_btn)
	balance_chk = CheckBox.new()
	balance_chk.text = "인원 불균형 보정"
	balance_chk.tooltip_text = "팀전에서 인원이 적은 팀의 채집 속도를 모자란 인원 1명당 +25%"
	balance_chk.toggled.connect(func(_b): _refresh())
	top.add_child(balance_chk)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for h in ["자리", "참가", "진영", "팀", "난이도"]:
		grid.add_child(_label(h, 14))
	var fnames = ["무작위"]
	for f in Data.FACTION_IDS:
		fnames.append(Data.FACTIONS[f]["name"])
	var dnames = []
	for d in DIFF_CHOICES:
		dnames.append(Data.DIFFS[d]["name"])
	for i in Data.MAX_PLAYERS:
		var swatch = HBoxContainer.new()
		var cr = ColorRect.new()
		cr.color = Data.PLAYER_COLORS[i]
		cr.custom_minimum_size = Vector2(18, 18)
		swatch.add_child(cr)
		swatch.add_child(_label(" 자리 %d" % (i + 1)))
		grid.add_child(swatch)
		var type = _option(["나"] if i == 0 else ["인공지능", "비움"], 0 if i <= 1 else 1)
		type.disabled = (i == 0)
		grid.add_child(type)
		var fac = _option(fnames, 1 if i == 0 else 2 if i == 1 else 0)
		grid.add_child(fac)
		var team = _option(["팀 1", "팀 2", "팀 3", "팀 4", "팀 5"], 0 if i == 0 else 1)
		grid.add_child(team)
		var diff = _option(dnames, 1)
		grid.add_child(diff)
		rows.append({"type": type, "faction": fac, "team": team, "diff": diff})

	info = _label("", 14)
	box.add_child(info)
	start_btn = Button.new()
	start_btn.text = "시작"
	start_btn.custom_minimum_size = Vector2(200, 48)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_start)
	box.add_child(start_btn)
	_refresh()

func _active(i):
	return i == 0 or rows[i]["type"].selected == 0

func _refresh():
	var team_mode = mode_btn.selected == 1
	balance_chk.visible = team_mode
	var n = 0
	var teams = {}
	for i in rows.size():
		var on = _active(i)
		# 격자 칸이 밀리지 않도록 숨기지 않고 비활성·투명 처리한다
		rows[i]["faction"].disabled = not on
		rows[i]["team"].disabled = not on or not team_mode
		rows[i]["team"].modulate.a = 1.0 if team_mode else 0.0
		rows[i]["diff"].disabled = not on or i == 0
		rows[i]["diff"].modulate.a = 0.0 if i == 0 else 1.0
		if on:
			n += 1
			teams[rows[i]["team"].selected if team_mode else i] = true
	var ok = n >= 2 and teams.size() >= 2
	start_btn.disabled = not ok
	var pop = int(Data.POP_MAX if n <= 3 else Data.POP_MAX_BIG)
	var t = "참가 %d명 · %d인용 지도 · 최대 인구 %d" % [n, n, pop]
	if n < 2:
		t += "\n인공지능을 1명 이상 넣어야 합니다"
	elif not ok:
		t += "\n팀전에는 두 팀 이상이 필요합니다"
	info.text = t

func _start():
	var team_mode = mode_btn.selected == 1
	var slots = []
	for i in rows.size():
		if not _active(i):
			continue
		var f = FACTION_CHOICES[rows[i]["faction"].selected]
		if f == "random":
			f = Data.FACTION_IDS[randi() % Data.FACTION_IDS.size()]
		slots.append({"type": "human" if i == 0 else "ai", "faction": f,
			"team": rows[i]["team"].selected, "diff": DIFF_CHOICES[rows[i]["diff"].selected]})
	ConfigScript.setup = {"mode": "team" if team_mode else "ffa", "slots": slots, "balance": team_mode and balance_chk.button_pressed}
	get_tree().change_scene_to_file("res://scenes/main.tscn")
