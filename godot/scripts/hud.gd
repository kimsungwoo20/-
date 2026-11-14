extends CanvasLayer
const Data = preload("res://scripts/data.gd")
const Minimap = preload("res://scripts/minimap.gd")
const UnitScript = preload("res://scripts/unit.gd")

const KEYS = ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V", "B"]

var game
var root
var top_label
var msg_label
var info_label
var grid
var buttons = []
var cmds = []
var last_ver = -1
var refresh_t = 0.0
var msg_t = 0.0
var over_panel

func setup(g):
	game = g
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	top_label = _label(16)
	top_label.position = Vector2(12, 8)
	root.add_child(top_label)

	msg_label = _label(18)
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	msg_label.offset_left = -400
	msg_label.offset_right = 400
	msg_label.offset_top = 44
	msg_label.offset_bottom = 74
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg_label)

	var panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -150
	panel.offset_bottom = 0
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.1, 0.08, 0.95)
	sb.border_color = Color(0.4, 0.3, 0.2)
	sb.border_width_top = 2
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var mm = Minimap.new()
	mm.game = game
	mm.position = Vector2(8, 8)
	mm.size = Vector2(214, 134)
	panel.add_child(mm)

	info_label = _label(14)
	info_label.position = Vector2(234, 8)
	info_label.size = Vector2(400, 134)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.clip_text = true
	panel.add_child(info_label)

	grid = GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(648, 6)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)

func _label(font_size):
	var l = Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func show_msg(text):
	msg_label.text = text
	msg_t = 3.0

func show_game_over(won):
	if over_panel != null:
		return
	over_panel = Panel.new()
	over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	over_panel.offset_left = -180
	over_panel.offset_right = 180
	over_panel.offset_top = -80
	over_panel.offset_bottom = 80
	root.add_child(over_panel)
	var l = _label(28)
	l.text = "승리!" if won else "패배"
	l.position = Vector2(0, 20)
	l.size = Vector2(360, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_panel.add_child(l)
	var b = Button.new()
	b.text = "다시 하기"
	b.position = Vector2(110, 95)
	b.size = Vector2(140, 44)
	b.pressed.connect(func(): game.get_tree().reload_current_scene())
	over_panel.add_child(b)

func press_button(i):
	if i < buttons.size() and not buttons[i].disabled:
		_on_btn(i)

func _on_btn(i):
	if i < cmds.size():
		cmds[i]["call"].call()
		refresh_t = 0.0

func _rebuild():
	for b in buttons:
		b.queue_free()
	buttons.clear()
	cmds = game.get_commands()
	for i in cmds.size():
		var b = Button.new()
		b.custom_minimum_size = Vector2(122, 43)
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_btn.bind(i))
		grid.add_child(b)
		buttons.append(b)
	_update_buttons()

func _update_buttons():
	for i in buttons.size():
		var c = cmds[i]
		var key = ""
		if i < KEYS.size() and KEYS[i] != "":
			key = "[%s] " % KEYS[i]
		buttons[i].text = key + c["text"]
		buttons[i].tooltip_text = c["tip"]
		buttons[i].disabled = not c["enabled"]
		# 빈칸은 자리만 차지하고 보이지 않는다(격자 위치 유지)
		buttons[i].modulate.a = 0.0 if c.get("blank", false) else 1.0
		if c.get("blank", false):
			buttons[i].text = ""

func _process(delta):
	var real = delta / max(Engine.time_scale, 0.001)
	var p = game.players[game.human_id]
	var up = int(round(p.upkeep_mult() * 100.0))
	var mins = int(game.elapsed) / 60
	var secs = int(game.elapsed) % 60
	top_label.text = "식량 %d    재료 %d    인구 %s / %d    식량 수입 %d%%    %02d:%02d" % [
		int(p.food), int(p.mat), _fmt(p.pop_used), int(p.pop_cap), up, mins, secs]
	if p.succession > 0.0:
		top_label.text += "    여왕 계승 중 %d초" % int(ceil(p.succession))
	if msg_t > 0.0:
		msg_t -= real
		if msg_t <= 0.0:
			msg_label.text = ""
	if game.sel_version != last_ver:
		last_ver = game.sel_version
		_rebuild()
		refresh_t = 0.0
	refresh_t -= real
	if refresh_t <= 0.0:
		refresh_t = 0.2
		var fresh = game.get_commands()
		if fresh.size() != buttons.size():
			_rebuild()
		else:
			cmds = fresh
			_update_buttons()
		info_label.text = _info()

func _fmt(v):
	if abs(v - round(v)) < 0.01:
		return str(int(round(v)))
	return "%.1f" % v

func _info():
	if game.build_mode != "":
		return "%s 건설: 지을 자리를 왼쪽 클릭 (오른쪽 클릭으로 취소)" % game.bdata(game.human_id, game.build_mode)["name"]
	if game.amove_armed:
		return "공격 이동: 목표 지점을 왼쪽 클릭"
	var b = game.sel_building()
	if b != null:
		var t = "%s\n체력 %d / %d" % [b.display_name(), int(b.hp), int(b.max_hp)]
		if b.pid != game.human_id:
			return t
		if b.mode != "camp":
			t += "\n" + {"packing": "행군 준비 중", "march": "행군 중 (오른쪽 클릭: 이동)", "unpacking": "야영 준비 중"}[b.mode]
		if not b.built:
			return t + "\n건설 중 %d%% (일꾼이 붙어 있어야 진행)" % int(b.build_progress / b.d["time"] * 100.0)
		if b.upgrade_t >= 0.0:
			t += "\n등급 상승 중 %d%%" % int(b.upgrade_t / Data.NEST_UPGRADE[b.tier + 1]["time"] * 100.0)
		if b.queue.size() > 0:
			var names = []
			for it in b.queue:
				if it["type"] == "unit":
					names.append(Data.UNITS[it["id"]]["name"])
				else:
					names.append(Data.RESEARCH[it["id"]]["name"])
			var first = b.queue[0]
			var st = "%d%%" % int(first["progress"] / first["time"] * 100.0)
			if not first["started"]:
				st = "대기 (인구 부족 또는 여왕 계승 중)"
			t += "\n생산: %s\n대기열: %s" % [st, ", ".join(names)]
		if b.d["produces"].size() > 0 and b.camped():
			t += "\n오른쪽 클릭: 집결 지점"
		return t
	var us = game.sel_units()
	if us.size() > 0:
		var counts = {}
		for u in us:
			counts[u.kind] = counts.get(u.kind, 0) + 1
		var parts = []
		for k in counts:
			parts.append("%s %d" % [Data.UNITS[k]["name"], counts[k]])
		var t2 = ", ".join(parts)
		if us.size() == 1:
			t2 += "\n체력 %d / %d" % [int(us[0].hp), int(us[0].max_hp)]
		t2 += "\n오른쪽 클릭: 이동 / 공격 / 채집 / 건설 지원\nA: 공격 이동   S: 정지"
		return t2
	return "왼쪽 클릭·드래그: 선택\n오른쪽 클릭: 명령\n방향키·가운데 버튼 드래그: 화면 이동\n휠: 확대/축소"
