extends RefCounted
## Shared UI kit: semi pixel art, clean and modern.
## - Display text (titles, eyebrows, buttons, scores) uses the original 5x7 pixel font
##   (assets/fonts/arjo_pixel.fnt, built by tools/make_pixel_font.py), scaled by whole pixels.
## - Body copy stays in a clean system sans for readability.
## - Panels and buttons: crisp edges (no anti-aliasing), small stepped corners, a chunky
##   darker lower bevel instead of black outlines; buttons sink into the bevel when pressed.

const INK: = Color("f2f6ee")
const MUTED: = Color("a3b8c2")
const PANEL: = Color("0f2230")
const SURFACE: = Color("1b3445")
const SURFACE_HOVER: = Color("26475b")
const SURFACE_PRESSED: = Color("10212d")
const BORDER: = Color("355a6d")
const ACCENT: = Color("c4ef6b")      # pickleball lime
const ACCENT_HOVER: = Color("d6f88f")
const GOLD: = Color("ffd46b")
const BLUE: = Color("84ceff")
const RED: = Color("ff9f8c")
const BACKDROP: = Color("0b1a24")

const PIXEL_FONT_PATH: = "res://assets/fonts/arjo_pixel.fnt"
const PIXEL_UNIT: = 9        # the pixel font's native size; display sizes are whole multiples
const BEVEL: = 5
const PRESS_SINK: = 3

static var _pixel_font: Font
static var _sans: SystemFont

static func sans_font() -> Font:
	if _sans == null:
		_sans = SystemFont.new()
		_sans.font_names = PackedStringArray(["Inter", "SF Pro Text", "Segoe UI", "DejaVu Sans", "Arial", "sans-serif"])
	return _sans

## The pixel display font, with the sans as fallback for any glyph it does not draw.
static func pixel_font() -> Font:
	if _pixel_font == null:
		var base = load(PIXEL_FONT_PATH)
		if base is FontFile:
			var font: FontFile = base.duplicate()
			font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
			font.fallbacks = [sans_font()]
			_pixel_font = font
		else:
			_pixel_font = sans_font()
	return _pixel_font

## Nearest whole-pixel size for the pixel font (it only scales by integers).
static func pixel_size(px: float) -> int:
	return maxi(PIXEL_UNIT, roundi(px / PIXEL_UNIT) * PIXEL_UNIT)

## Pixel text keeps hard edges: filter the subtree with nearest sampling.
static func crisp(node: CanvasItem) -> void:
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Switch a Label / Button to the pixel display font at a whole-pixel size.
static func use_pixel(control: Control, px: float) -> void:
	control.add_theme_font_override("font", pixel_font())
	control.add_theme_font_size_override("font_size", pixel_size(px))
	crisp(control)

static func panel_style() -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.anti_aliasing = false
	style.set_border_width_all(2)
	style.border_width_bottom = BEVEL + 1
	style.set_corner_radius_all(4)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0.0, 0.03, 0.06, 0.45)
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, 6)
	return style

## Score pill: dark chunky plate with a lighter bevel.
static func pill_style(scale_f: float = 1.0) -> StyleBoxFlat:
	var style: = panel_style()
	style.bg_color = Color("13293a")
	style.border_color = Color("4a6c90")
	style.set_border_width_all(maxi(2, roundi(2.0 * scale_f)))
	style.border_width_bottom = maxi(4, roundi(6.0 * scale_f))
	style.set_corner_radius_all(roundi(8.0 * scale_f))
	return style

static func button_style(color: Color, pressed: bool = false) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.anti_aliasing = false
	style.border_color = color.darkened(0.42)   # bevel: darker chunky lower edge, not an outline
	style.border_width_bottom = 1 if pressed else BEVEL
	style.set_corner_radius_all(4)
	style.content_margin_left = 18
	style.content_margin_right = 18
	# Pressed buttons sink into their bevel: the label moves down with the face.
	style.content_margin_top = 10 + (PRESS_SINK if pressed else 0)
	style.content_margin_bottom = 10
	style.expand_margin_top = -(BEVEL - 1) if pressed else 0
	return style

## Lime primary action (dark ink on the accent).
static func make_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style(ACCENT))
	button.add_theme_stylebox_override("hover", button_style(ACCENT_HOVER))
	button.add_theme_stylebox_override("pressed", button_style(ACCENT.darkened(0.08), true))
	button.add_theme_stylebox_override("hover_pressed", button_style(ACCENT.darkened(0.08), true))
	button.add_theme_stylebox_override("disabled", button_style(Color("2a3f2e")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, PANEL)
	button.add_theme_color_override("font_disabled_color", MUTED)

## Quiet destructive / exit action: flat, coral text.
static func make_quiet(button: Button, color: Color = RED) -> void:
	var flat: = button_style(Color(SURFACE, 0.0))
	flat.border_color = Color(color, 0.35)
	flat.border_width_bottom = 2
	button.add_theme_stylebox_override("normal", flat)
	var hover: = button_style(Color(color, 0.12))
	hover.border_color = Color(color, 0.5)
	hover.border_width_bottom = 2
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", button_style(Color(color, 0.2), true))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)

static func create() -> Theme:
	var result: = Theme.new()
	result.default_font_size = 20
	result.default_font = sans_font()
	result.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		result.set_font("font", type, pixel_font())
		result.set_stylebox("normal", type, button_style(SURFACE))
		result.set_stylebox("hover", type, button_style(SURFACE_HOVER))
		result.set_stylebox("pressed", type, button_style(SURFACE_PRESSED, true))
		result.set_stylebox("hover_pressed", type, button_style(SURFACE_PRESSED, true))
		result.set_stylebox("disabled", type, button_style(Color("15283a")))
		var focus: = StyleBoxFlat.new()
		focus.draw_center = false
		focus.anti_aliasing = false
		focus.border_color = ACCENT
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(5)
		focus.set_expand_margin_all(3)
		result.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			result.set_color(state, type, INK)
		result.set_color("font_disabled_color", type, MUTED)
	# Pixel display label variations: theme_type_variation = "PixelLabel" / "Eyebrow".
	result.set_type_variation("PixelLabel", "Label")
	result.set_font("font", "PixelLabel", pixel_font())
	result.set_font_size("font_size", "PixelLabel", 27)
	result.set_type_variation("Eyebrow", "Label")
	result.set_font("font", "Eyebrow", pixel_font())
	result.set_font_size("font_size", "Eyebrow", 18)
	result.set_color("font_color", "Eyebrow", ACCENT)
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track: = StyleBoxFlat.new()
		track.anti_aliasing = false
		track.bg_color = BORDER if state == "slider" else ACCENT
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		track.set_corner_radius_all(2)
		result.set_stylebox(state, "HSlider", track)
	for type in ["TabContainer", "TabBar"]:
		result.set_font("font", type, pixel_font())
		result.set_stylebox("tab_selected", type, button_style(SURFACE))
		result.set_stylebox("tab_unselected", type, button_style(PANEL))
		result.set_stylebox("tab_hovered", type, button_style(SURFACE_HOVER))
		result.set_color("font_selected_color", type, ACCENT)
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_hovered_color", type, INK)
	var tab_panel: = StyleBoxFlat.new()
	tab_panel.bg_color = PANEL
	tab_panel.content_margin_top = 20
	result.set_stylebox("panel", "TabContainer", tab_panel)
	# Chunky pixel scrollbars and progress bars.
	var bar_bg: = StyleBoxFlat.new()
	bar_bg.bg_color = Color(BORDER, 0.35)
	bar_bg.anti_aliasing = false
	bar_bg.set_corner_radius_all(2)
	var grab: = StyleBoxFlat.new()
	grab.bg_color = BORDER
	grab.anti_aliasing = false
	grab.set_corner_radius_all(2)
	var grab_hi: = grab.duplicate()
	grab_hi.bg_color = MUTED
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, bar_bg)
		result.set_stylebox("grabber", type, grab)
		result.set_stylebox("grabber_highlight", type, grab_hi)
		result.set_stylebox("grabber_pressed", type, grab_hi)
	var progress_bg: = bar_bg.duplicate()
	progress_bg.bg_color = SURFACE
	progress_bg.border_color = SURFACE.darkened(0.4)
	progress_bg.border_width_bottom = 3
	var progress_fill: = StyleBoxFlat.new()
	progress_fill.bg_color = ACCENT
	progress_fill.anti_aliasing = false
	progress_fill.border_color = ACCENT.darkened(0.3)
	progress_fill.border_width_bottom = 3
	progress_fill.set_corner_radius_all(2)
	result.set_stylebox("background", "ProgressBar", progress_bg)
	result.set_stylebox("fill", "ProgressBar", progress_fill)
	result.set_font("font", "ProgressBar", pixel_font())
	result.set_color("font_color", "ProgressBar", INK)
	var popup: = panel_style()
	popup.set_content_margin_all(8)
	result.set_stylebox("panel", "PopupMenu", popup)
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", PANEL)
	var popup_hover: = StyleBoxFlat.new()
	popup_hover.bg_color = ACCENT
	popup_hover.anti_aliasing = false
	popup_hover.set_corner_radius_all(2)
	result.set_stylebox("hover", "PopupMenu", popup_hover)
	return result
