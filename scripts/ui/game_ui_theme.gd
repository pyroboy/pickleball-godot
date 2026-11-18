extends RefCounted
## Shared desktop controls: readable text, visible focus, generous slider targets.

static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111c2b")
	style.border_color = Color("3a536b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

static func create() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("24364c") if state == "normal" else Color("365775")
			style.set_corner_radius_all(7)
			style.content_margin_left = 12
			style.content_margin_right = 12
			style.content_margin_top = 8
			style.content_margin_bottom = 8
			if state == "focus":
				style.bg_color = Color.TRANSPARENT
				style.border_color = Color("81d6ff")
				style.set_border_width_all(2)
			result.set_stylebox(state, type, style)
		result.set_color("font_color", type, Color("eff6ff"))
		result.set_color("font_disabled_color", type, Color("8da1b5"))
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("3a536b") if state == "slider" else Color("71c7ef")
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		track.set_corner_radius_all(4)
		result.set_stylebox(state, "HSlider", track)
	return result
