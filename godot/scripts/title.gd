extends Control
# 메인 화면: 다섯 군체의 개미 행렬이 지나가는 배경 위에 메뉴.
# 혼자 하기 / 온라인 대전 → 방 화면, 진영 소개 / 조작법 / 설정은 이 화면 안의 창으로 연다.
const Data = preload("res://scripts/data.gd")
const Art = preload("res://scripts/art.gd")
const ConfigScript = preload("res://scripts/config.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

const INFO = {
	"fire": {"title": "붉은 군단", "concept": "대량 생산 · 빠른 확장 · 물량 공세",
		"strong": "침병·병정개미를 2기 한 조로 뽑는다. 위성 둥지가 싸다. 공격에 쌓이는 독",
		"weak": "인구가 늘수록 식량 수입이 크게 줄어든다. 확장을 멈추면 진다",
		"units": "침병 · 분사병 · 폭군 대병 · 방벽 개미 · 혼인비행 떼 · 뗏목단"},
	"leaf": {"title": "녹색 농업 제국", "concept": "농업 · 경제 성장 · 장기전",
		"strong": "균류 정원에서 재료를 식량으로 바꾼다. 재료를 더 나른다. 공생균으로 회복",
		"weak": "재료 채집선이 끊기면 정원도 멈춘다. 본진이 다치면 정원 효율이 반",
		"units": "절단병 · 대턱 병정 · 초대형 병정 · 문지기 · 공생균 살포병 · 포자 살포 날개개미"},
	"weaver": {"title": "수목의 지배자", "concept": "방어 · 영역 장악 · 지형 활용",
		"strong": "영역 안에서 빠르고 회복한다. 수목 위에도 짓는다. 장막·고정·끌어당기기",
		"weak": "영역 안에만 지을 수 있다. 가운데 고리가 끊기면 그 너머가 약해진다",
		"units": "산성 분사병 · 사슬 견인병 · 수관 군주 · 고정병 · 장막 방직병 · 날개 파수꾼"},
	"trap": {"title": "순간의 포식자", "concept": "정예 · 매복 · 순간 화력",
		"strong": "충전된 턱 타격이 큰 피해와 밀쳐내기. 매복 은신, 숨겨진 건물, 턱 도약",
		"weak": "비싸고 수가 적어 물량에 약하다. 한 번 크게 지면 회복이 느리다",
		"units": "격발병 · 도약 사냥꾼 · 대왕 포식자 · 덫지기 · 유인병 · 낙하 사냥꾼"},
	"army": {"title": "이동하는 포식 군단", "concept": "기동 · 습격 · 이동식 군체",
		"strong": "건물이 행군해 군체째 옮겨 다닌다. 적을 처치하면 약탈. 살아있는 다리",
		"weak": "행군 중에는 생산이 느리고 연구가 멈춘다. 진딧물을 기르지 못한다",
		"units": "약탈병 · 낫턱 병정 · 포식 대군 · 수호병 · 다리 개미 · 운반병"},
}
const BEATS = {"fire": "trap", "trap": "army", "army": "leaf", "leaf": "weaver", "weaver": "fire"}

# 배경: 개미 행렬
class March extends Control:
	var t = 0.0
	var lanes = []

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng = RandomNumberGenerator.new()
		rng.seed = 5
		for i in 7:
			var f = Data.FACTION_IDS[i % 5]
			lanes.append({"y": 0.12 + i * 0.13, "speed": rng.randf_range(35, 60) * (1 if i % 2 == 0 else -1),
				"faction": f, "color": Data.PLAYER_COLORS[i % 5], "n": rng.randi_range(5, 9),
				"gap": rng.randf_range(38, 60), "off": rng.randf_range(0, 400), "r": rng.randf_range(7, 11)})

	func _process(delta):
		t += delta
		queue_redraw()

	func _draw():
		var sz = size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.19, 0.15, 0.11))
		# 흙 무늬
		for i in 160:
			var p = Vector2(fmod(i * 197.3, sz.x), fmod(i * 131.7, sz.y))
			draw_circle(p, 2.0 + fmod(i * 7.1, 5.0), Color(0.24, 0.19, 0.14))
		for L in lanes:
			var span = sz.x + 400.0
			for k in L["n"]:
				var x = fmod(L["off"] + t * L["speed"] + k * L["gap"], span)
				if x < 0:
					x += span
				x -= 200.0
				var y = L["y"] * sz.y + sin(t * 2.0 + k) * 3.0
				var ang = 0.0 if L["speed"] > 0 else PI
				draw_set_transform(Vector2(x, y), ang, Vector2.ONE)
				var kind = "worker" if k % 3 != 0 else ("soldier" if L["faction"] == "fire" else "major")
				Art.draw_ant(self, L["r"], L["color"].darkened(0.25), L["faction"], kind, t * 9.0 + k, kind == "worker")
				if kind == "worker":
					Art.draw_carry(self, L["r"], "food" if k % 2 == 0 else "mat", L["faction"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 가운데를 어둡게 해서 메뉴가 잘 보이게
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.06, 0.04, 0.55))

# 진영 소개 그림: 일꾼·병정 개미와 둥지
class Preview extends Control:
	var faction = "fire"
	var t = 0.0
	class FakeNest:
		var radius = 46.0
		var kind = "nest"
		var is_main = true
		var mode = "camp"

	func _process(delta):
		t += delta
		queue_redraw()

	func _draw():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.24, 0.17))
		var c = Data.PLAYER_COLORS[Data.FACTION_IDS.find(faction)]
		draw_set_transform(Vector2(size.x * 0.25, size.y * 0.5), 0.0, Vector2.ONE)
		Art.draw_building(self, FakeNest.new(), c, faction, 1.0, t)
		draw_set_transform(Vector2(size.x * 0.58, size.y * 0.32), -0.3, Vector2.ONE)
		Art.draw_ant(self, 16.0, c, faction, "worker", t * 6.0, true)
		Art.draw_carry(self, 16.0, "mat", faction)
		draw_set_transform(Vector2(size.x * 0.75, size.y * 0.68), 0.25, Vector2.ONE)
		var soldier = {"fire": "soldier", "leaf": "major", "weaver": "puller", "trap": "hunter", "army": "sickle"}[faction]
		Art.draw_ant(self, 22.0, c, faction, soldier, t * 6.0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var sfx
var windows = {}
var preview
var info_box
var tab_buttons = []

func _ready():
	# 점검·자동 대전 실행이나, 주소로 판을 정한 경우에는 바로 게임으로 간다
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

func _label(text, size = 16, col = Color(0.95, 0.9, 0.8)):
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text, call, w = 260):
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(func():
		sfx.play("select")
		call.call())
	return b

func _build():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	sfx = SfxScript.new()
	add_child(sfx)
	var bg = March.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	var title = _label("개미 RTS", 64, Color(1.0, 0.85, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
	box.add_child(title)
	var sub = _label("다섯 군체의 전쟁", 22, Color(0.9, 0.82, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())
	var menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(menu)
	for item in [["혼자 하기", go_solo], ["온라인 대전", go_online], ["진영 소개", open_window.bind("factions")],
			["조작법", open_window.bind("help")], ["설정", open_window.bind("settings")]]:
		var b = _button(item[0], item[1])
		b.name = item[0]
		menu.add_child(b)
	if not OS.has_feature("web"):
		menu.add_child(_button("끝내기", func(): get_tree().quit()))
	var foot = _label("불개미 · 잎꾼개미 · 베짜기개미 · 함정턱개미 · 군대개미", 13, Color(0.75, 0.68, 0.58))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(foot)

	windows["factions"] = _factions_window()
	windows["help"] = _help_window()
	windows["settings"] = _settings_window()

func go_solo():
	ConfigScript.lobby_mode = "solo"
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func go_online():
	ConfigScript.lobby_mode = "online"
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func open_window(name):
	for k in windows:
		windows[k].visible = (k == name)

func _window(title_text, w, h):
	var cover = ColorRect.new()
	cover.color = Color(0, 0, 0, 0.55)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.visible = false
	add_child(cover)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(w, h)
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.position = Vector2(20, 14)
	box.size = Vector2(w - 40, h - 28)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head = HBoxContainer.new()
	box.add_child(head)
	var t = _label(title_text, 26, Color(1.0, 0.85, 0.45))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_button("닫기", func(): cover.visible = false, 90))
	return [cover, box]

func _factions_window():
	var wb = _window("진영 소개", 860, 420)
	var box = wb[1]
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	for f in Data.FACTION_IDS:
		var b = _button(Data.FACTIONS[f]["name"], show_faction.bind(f), 150)
		b.toggle_mode = true
		tabs.add_child(b)
		tab_buttons.append(b)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	preview = Preview.new()
	preview.custom_minimum_size = Vector2(300, 220)
	row.add_child(preview)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 8)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_box)
	show_faction("fire")
	return wb[0]

func show_faction(f):
	preview.faction = f
	for i in tab_buttons.size():
		tab_buttons[i].button_pressed = Data.FACTION_IDS[i] == f
	for c in info_box.get_children():
		c.queue_free()
	var d = INFO[f]
	info_box.add_child(_label("%s — %s" % [Data.FACTIONS[f]["name"], d["title"]], 22, Color(1.0, 0.85, 0.45)))
	info_box.add_child(_label(d["concept"], 16, Color(0.9, 0.85, 0.75)))
	info_box.add_child(_label("강점  " + d["strong"], 15))
	info_box.add_child(_label("약점  " + d["weak"], 15))
	var loses_to = ""
	for k in BEATS:
		if BEATS[k] == f:
			loses_to = k
	info_box.add_child(_label("상성  %s 에 강하고, %s 에 약하다" % [Data.FACTIONS[BEATS[f]]["name"], Data.FACTIONS[loses_to]["name"]], 15, Color(0.85, 0.95, 0.75)))
	info_box.add_child(_label("대표 유닛  " + d["units"], 14, Color(0.85, 0.8, 0.7)))

func _help_window():
	var wb = _window("조작법", 700, 520)
	var box = wb[1]
	var rows = [
		["왼쪽 클릭 / 드래그", "선택"],
		["오른쪽 클릭", "이동 · 공격 · 채집 · 건설 지원 · 탑승 · 정원사 · 집결 지점"],
		["A 후 왼쪽 클릭", "공격 이동 (가는 길의 적과 싸운다)"],
		["S", "정지"],
		["Q W E R T / A S D F G / Z X C V B", "아래 명령 버튼 (건물·일꾼 선택 시)"],
		["방향키 · 가운데 버튼 드래그 · 미니맵", "화면 이동"],
		["휠", "확대 / 축소"],
		["M", "소리 끄기 / 켜기"],
		["Esc", "선택 해제 · 건설 취소"],
	]
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for r in rows:
		grid.add_child(_label(r[0], 16, Color(1.0, 0.85, 0.45)))
		grid.add_child(_label(r[1], 16))
	box.add_child(_label("일꾼으로 식량과 재료를 모아 생산 건물을 짓고, 상대의 본진을 모두 무너뜨리면 이긴다. 주 둥지가 무너져도 위성 둥지가 있으면 여왕이 옮겨 간다.", 14, Color(0.85, 0.8, 0.7)))
	return wb[0]

func _settings_window():
	var wb = _window("설정", 520, 300)
	var box = wb[1]
	var mute = CheckBox.new()
	mute.text = "소리 끄기"
	mute.button_pressed = SfxScript.muted
	mute.toggled.connect(func(on): SfxScript.muted = on)
	box.add_child(mute)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_label("음량", 16))
	var vol = HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.custom_minimum_size = Vector2(280, 24)
	vol.value_changed.connect(func(v):
		AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.001)))
		sfx.play("order"))
	row.add_child(vol)
	box.add_child(_label("게임 중에도 M 키로 소리를 끄고 켤 수 있다.", 14, Color(0.85, 0.8, 0.7)))
	return wb[0]
