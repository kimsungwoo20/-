extends RefCounted
# 화면 공통 테마: 흙빛 바탕에 호박색 강조. 게임 화면(HUD)과 방 화면이 함께 쓴다.

static func _box(bg, border, w = 1, radius = 4):
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

static func make():
	var t = Theme.new()
	t.set_stylebox("normal", "Button", _box(Color(0.24, 0.18, 0.12), Color(0.45, 0.34, 0.2)))
	t.set_stylebox("hover", "Button", _box(Color(0.32, 0.24, 0.14), Color(0.85, 0.65, 0.3)))
	t.set_stylebox("pressed", "Button", _box(Color(0.42, 0.3, 0.14), Color(0.95, 0.75, 0.35), 2))
	t.set_stylebox("disabled", "Button", _box(Color(0.17, 0.14, 0.11), Color(0.25, 0.2, 0.15)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.95, 0.9, 0.8))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.8))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.4))
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(k, "OptionButton", t.get_stylebox(k, "Button"))
	t.set_color("font_color", "OptionButton", Color(0.95, 0.9, 0.8))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.14, 0.11, 0.08), Color(0.45, 0.34, 0.2)))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.16, 0.12, 0.09), Color(0.95, 0.75, 0.35)))
	t.set_stylebox("panel", "Panel", _box(Color(0.13, 0.1, 0.07, 0.96), Color(0.5, 0.38, 0.22), 2, 0))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.16, 0.12, 0.09), Color(0.5, 0.38, 0.22)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.42, 0.3, 0.14), Color(0.95, 0.75, 0.35)))
	return t
