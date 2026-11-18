extends RefCounted


const INK: = Color("eef5fa")
const MUTED: = Color("a9becb")
const PANEL: = Color("102431")
const SURFACE: = Color("1c3646")
const BORDER: = Color("395665")
const ACCENT: = Color("bde879")
const BLUE: = Color("84ceff")
const RED: = Color("ffab9c")

static func panel_style() -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0.015, 0.035, 0.05, 0.25)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	return style

static func button_style(color: Color) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func create() -> Theme:
	var result: = Theme.new()
	result.default_font_size = 20
	var font: = SystemFont.new()
	font.font_names = PackedStringArray(["Inter", "Segoe UI", "DejaVu Sans", "Arial", "sans-serif"])
	result.default_font = font
	result.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, button_style(SURFACE))
		result.set_stylebox("hover", type, button_style(Color("2d4c5e")))
		result.set_stylebox("pressed", type, button_style(Color("0a1923")))
		result.set_stylebox("disabled", type, button_style(Color("172b38")))
		var focus: = button_style(Color.TRANSPARENT)
		focus.border_color = ACCENT
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(state, type, INK)
		result.set_color("font_disabled_color", type, MUTED)
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track: = StyleBoxFlat.new()
		track.bg_color = BORDER if state == "slider" else ACCENT
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		track.set_corner_radius_all(4)
		result.set_stylebox(state, "HSlider", track)
	for type in ["TabContainer", "TabBar"]:
		result.set_stylebox("tab_selected", type, button_style(SURFACE))
		result.set_stylebox("tab_unselected", type, button_style(PANEL))
		result.set_stylebox("tab_hovered", type, button_style(Color("2d4c5e")))
		result.set_color("font_selected_color", type, ACCENT)
		result.set_color("font_unselected_color", type, MUTED)
	var tab_panel: = StyleBoxFlat.new()
	tab_panel.bg_color = PANEL
	tab_panel.content_margin_top = 20
	result.set_stylebox("panel", "TabContainer", tab_panel)
	return result
