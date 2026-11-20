extends RefCounted
## Desktop Pose Studio look (docs/POSE_STUDIO_SPEC.md 4.2): one theme, three font sizes, a
## 4 / 8 / 12 / 16 spacing scale, 28 pt targets, button kinds as theme type variations
## (ToolButton, PrimaryButton, Segment) and small stroke icons drawn from SVG text (cached;
## no image assets). Colours come from scripts/ui/game_ui_theme.gd.

const Ui = preload("res://scripts/ui/game_ui_theme.gd")

const FONT_BODY := 15
const FONT_SMALL := 13
const FONT_HEAD := 16
const SP1 := 4
const SP2 := 8
const SP3 := 12
const SP4 := 16
const TARGET := 28.0
const TOOL_MX := 5           # side padding of tool buttons (icon-only = 18 + 2 x 5 = 28)
const ICON := 18
const STAGE_COLORS := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
const FIELD_BG := Color("0d1f2b")
const HOVER := Color("2d4c5e")
const ACTIVE_BG := Color("2c4a2a")     # accent-tinted fill of a pressed toggle
const APP_BG := Color("0c1b25")

static var _icons: Dictionary = {}
static var margin_y := 5      # vertical content margin of body-size buttons (set by create())

static func _box(bg: Color, border := Color.TRANSPARENT, bw := 0, radius := 4, mx := 10, my := 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx; s.content_margin_right = mx
	s.content_margin_top = my; s.content_margin_bottom = my
	s.anti_aliasing = true
	return s

## Vertical content margin that makes a one-line control at least TARGET tall.
static func _my(font: Font, fs: int) -> int:
	var h := font.get_height(fs) if font != null else fs * 1.25
	return maxi(4, ceili((TARGET - h) * 0.5))

static func create() -> Theme:
	var t: Theme = Ui.create()
	t.default_font_size = FONT_BODY
	var font: Font = t.default_font
	var my := _my(font, FONT_BODY)
	margin_y = my
	# --- buttons (standard)
	for type in ["Button", "OptionButton", "CheckBox", "MenuButton"]:
		t.set_stylebox("normal", type, _box(Ui.SURFACE, Ui.BORDER, 1, 4, 10, my))
		t.set_stylebox("hover", type, _box(HOVER, Ui.BORDER, 1, 4, 10, my))
		t.set_stylebox("pressed", type, _box(ACTIVE_BG, Ui.ACCENT, 1, 4, 10, my))
		t.set_stylebox("hover_pressed", type, _box(ACTIVE_BG.lightened(0.08), Ui.ACCENT, 1, 4, 10, my))
		t.set_stylebox("disabled", type, _box(Color("152835"), Color("223b4a"), 1, 4, 10, my))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, Ui.BLUE, 1, 4, 10, my))
		t.set_color("font_color", type, Ui.INK)
		t.set_color("font_hover_color", type, Ui.INK)
		t.set_color("font_focus_color", type, Ui.INK)
		t.set_color("font_pressed_color", type, Ui.ACCENT)
		t.set_color("font_hover_pressed_color", type, Ui.ACCENT)
		t.set_color("font_disabled_color", type, Color(Ui.MUTED, 0.45))
		t.set_color("icon_normal_color", type, Ui.INK)
		t.set_color("icon_pressed_color", type, Ui.ACCENT)
		t.set_color("icon_hover_pressed_color", type, Ui.ACCENT)
		t.set_color("icon_disabled_color", type, Color(Ui.MUTED, 0.4))
		t.set_constant("icon_max_width", type, ICON)
		t.set_constant("h_separation", type, 6)
		t.set_constant("align_to_largest_stylebox", type, 1)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var cb := StyleBoxEmpty.new(); cb.content_margin_left = 2; cb.content_margin_right = 4
		cb.content_margin_top = my; cb.content_margin_bottom = my
		t.set_stylebox(st, "CheckBox", cb)
	# --- toolbar toggle / icon button: flat until hovered or pressed
	t.set_type_variation("ToolButton", "Button")
	t.set_stylebox("normal", "ToolButton", _box(Color.TRANSPARENT, Color.TRANSPARENT, 1, 4, TOOL_MX, my))
	t.set_stylebox("hover", "ToolButton", _box(HOVER, Color.TRANSPARENT, 1, 4, TOOL_MX, my))
	t.set_stylebox("pressed", "ToolButton", _box(ACTIVE_BG, Ui.ACCENT, 1, 4, TOOL_MX, my))
	t.set_stylebox("hover_pressed", "ToolButton", _box(ACTIVE_BG.lightened(0.08), Ui.ACCENT, 1, 4, TOOL_MX, my))
	t.set_stylebox("disabled", "ToolButton", _box(Color.TRANSPARENT, Color.TRANSPARENT, 1, 4, TOOL_MX, my))
	t.set_stylebox("focus", "ToolButton", StyleBoxEmpty.new())
	# --- primary action (Save)
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(Ui.BLUE, Ui.BLUE.darkened(0.25), 1, 4, 14, my))
	t.set_stylebox("hover", "PrimaryButton", _box(Ui.BLUE.lightened(0.15), Ui.BLUE.darkened(0.25), 1, 4, 14, my))
	t.set_stylebox("pressed", "PrimaryButton", _box(Ui.BLUE.darkened(0.2), Ui.BLUE.darkened(0.35), 1, 4, 14, my))
	t.set_stylebox("disabled", "PrimaryButton", _box(Color("152835"), Color("223b4a"), 1, 4, 14, my))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "PrimaryButton", Ui.PANEL)
	# --- segmented group: a dark plate holding ToolButtons
	t.set_type_variation("Segment", "PanelContainer")
	t.set_stylebox("panel", "Segment", _box(Color("0f2230"), Color("1f3a4a"), 1, 5, 2, 2))
	# --- status pill
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", _box(Color("0f2230"), Color("1f3a4a"), 1, 10, 10, 3))
	t.set_type_variation("OverlayPill", "PanelContainer")
	t.set_stylebox("panel", "OverlayPill", _box(Color(0.03, 0.08, 0.11, 0.78), Color(1, 1, 1, 0.08), 1, 6, 10, 5))
	# --- text fields
	for type in ["LineEdit"]:
		t.set_stylebox("normal", type, _box(FIELD_BG, Ui.BORDER, 1, 4, 8, my))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, Ui.BLUE, 1, 4, 8, my))
		t.set_stylebox("read_only", type, _box(Color("132a37"), Ui.BORDER, 1, 4, 8, my))
		t.set_color("font_color", type, Ui.INK)
		t.set_color("font_placeholder_color", type, Color(Ui.MUTED, 0.6))
		t.set_color("caret_color", type, Ui.BLUE)
		t.set_color("selection_color", type, Color(Ui.BLUE, 0.3))
	# --- labels
	t.set_color("font_color", "Label", Ui.INK)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", FONT_HEAD)
	t.set_color("font_color", "HeaderLabel", Ui.INK)
	t.set_type_variation("SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", FONT_SMALL)
	t.set_color("font_color", "SmallLabel", Ui.MUTED)
	# --- tree (pose list, bench table)
	t.set_stylebox("panel", "Tree", _box(Color("0d1f2b"), Color("1f3a4a"), 1, 4, 2, 2))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var sel := _box(ACTIVE_BG, Ui.ACCENT, 0, 3, 0, 0); sel.border_width_left = 2
	for st in ["selected", "selected_focus"]: t.set_stylebox(st, "Tree", sel)
	t.set_stylebox("hovered", "Tree", _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 3, 0, 0))
	t.set_stylebox("hovered_selected", "Tree", sel)
	t.set_stylebox("hovered_selected_focus", "Tree", sel)
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	t.set_color("font_color", "Tree", Ui.INK)
	t.set_color("font_selected_color", "Tree", Ui.INK)
	t.set_color("font_hovered_color", "Tree", Ui.INK)
	t.set_color("guide_color", "Tree", Color(1, 1, 1, 0.04))
	t.set_constant("v_separation", "Tree", 6)
	t.set_constant("h_separation", "Tree", 4)
	t.set_constant("inner_item_margin_left", "Tree", 4)
	t.set_constant("inner_item_margin_right", "Tree", 4)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_stylebox("title_button_normal", "Tree", _box(Color("132a37"), Color.TRANSPARENT, 0, 0, 4, 3))
	t.set_stylebox("title_button_hover", "Tree", _box(HOVER, Color.TRANSPARENT, 0, 0, 4, 3))
	t.set_stylebox("title_button_pressed", "Tree", _box(HOVER, Color.TRANSPARENT, 0, 0, 4, 3))
	t.set_color("title_button_color", "Tree", Ui.MUTED)
	t.set_font_size("title_button_font_size", "Tree", FONT_SMALL)
	# --- tabs
	for type in ["TabContainer", "TabBar"]:
		var ts := _box(Ui.PANEL, Color.TRANSPARENT, 0, 4, 9, 6)
		ts.border_width_top = 2; ts.border_color = Ui.ACCENT
		ts.corner_radius_bottom_left = 0; ts.corner_radius_bottom_right = 0
		t.set_stylebox("tab_selected", type, ts)
		t.set_stylebox("tab_unselected", type, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 9, 6))
		t.set_stylebox("tab_hovered", type, _box(HOVER, Color.TRANSPARENT, 0, 4, 9, 6))
		t.set_stylebox("tab_disabled", type, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 9, 6))
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_color("font_selected_color", type, Ui.ACCENT)
		t.set_color("font_unselected_color", type, Ui.MUTED)
		t.set_color("font_hovered_color", type, Ui.INK)
		t.set_font_size("font_size", type, FONT_BODY)
		t.set_constant("side_margin", type, 0)
	t.set_stylebox("panel", "TabContainer", _box(Ui.PANEL, Color.TRANSPARENT, 0, 4, SP2, SP2))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	# --- panels
	t.set_stylebox("panel", "PanelContainer", _box(Ui.PANEL, Color("1f3a4a"), 1, 6, SP2, SP2))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(Ui.SURFACE, Ui.BORDER, 1, 4, SP2, 6))
	# --- sliders, scroll bars, splits, separators
	var rail := _box(Color("23404f"), Color.TRANSPARENT, 0, 2, 0, 2)
	t.set_stylebox("slider", "HSlider", rail)
	var fill := _box(Color(Ui.BLUE, 0.55), Color.TRANSPARENT, 0, 2, 0, 2)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Color(Ui.BLUE, 0.75), Color.TRANSPARENT, 0, 2, 0, 2))
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("scroll_focus", sb, _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber", sb, _box(Color("2f4d5e"), Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber_highlight", sb, _box(Color("3d6176"), Color.TRANSPARENT, 0, 3, 3, 3))
		t.set_stylebox("grabber_pressed", sb, _box(Color("4a7189"), Color.TRANSPARENT, 0, 3, 3, 3))
	for sp in ["HSplitContainer", "VSplitContainer", "SplitContainer"]:
		t.set_constant("separation", sp, SP2)
		t.set_constant("minimum_grab_thickness", sp, SP2)
	var line := StyleBoxLine.new(); line.color = Color("1f3a4a"); line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new(); vline.color = Color("2a4757"); vline.thickness = 1; vline.vertical = true
	vline.grow_begin = -6; vline.grow_end = -6
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "VSeparator", SP3)
	# --- popups and tooltips
	t.set_stylebox("panel", "PopupMenu", _box(Color("10242f"), Ui.BORDER, 1, 4, 4, 4))
	t.set_stylebox("hover", "PopupMenu", _box(HOVER, Color.TRANSPARENT, 0, 3, 6, 3))
	t.set_font_size("font_size", "PopupMenu", FONT_BODY)
	t.set_color("font_color", "PopupMenu", Ui.INK)
	t.set_color("font_hover_color", "PopupMenu", Ui.INK)
	t.set_stylebox("panel", "TooltipPanel", _box(Color("0a1720"), Ui.BORDER, 1, 4, 8, 5))
	t.set_color("font_color", "TooltipLabel", Ui.INK)
	t.set_font_size("font_size", "TooltipLabel", FONT_SMALL)
	t.set_stylebox("background", "ProgressBar", _box(Color("0d1f2b"), Color.TRANSPARENT, 0, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(Ui.ACCENT, 0.6), Color.TRANSPARENT, 0, 3, 0, 0))
	t.set_font_size("font_size", "ProgressBar", FONT_SMALL)
	return t

## Tool button: flat, optional icon (text "" = icon only, square 28), tooltip names the key.
static func tool_button(n: String, text: String, icon_name: String, tip: String, toggle := false) -> Button:
	var b := Button.new(); b.name = n; b.text = text; b.tooltip_text = tip
	b.theme_type_variation = &"ToolButton"; b.focus_mode = Control.FOCUS_NONE; b.toggle_mode = toggle
	if icon_name != "": b.icon = icon(icon_name)
	if text == "": b.custom_minimum_size = Vector2(TARGET, TARGET); b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

## Dark plate grouping tool buttons (a segmented control). Returns the inner HBox.
static func segment(parent: Node, n: String) -> HBoxContainer:
	var p := PanelContainer.new(); p.name = n; p.theme_type_variation = &"Segment"
	parent.add_child(p)
	var h := HBoxContainer.new(); h.name = n + "Row"; h.add_theme_constant_override("separation", 2)
	p.add_child(h)
	return h

static func small_label(n: String, text := "") -> Label:
	var l := Label.new(); l.name = n; l.text = text; l.theme_type_variation = &"SmallLabel"
	return l

static func header_label(n: String, text := "") -> Label:
	var l := Label.new(); l.name = n; l.text = text; l.theme_type_variation = &"HeaderLabel"
	return l

# ---------------------------------------------------------------- icons

const _PATHS := {
	"undo": '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
	"redo": '<path d="m15 14 5-5-5-5"/><path d="M20 9H10a6 6 0 0 0 0 12h3"/>',
	"frame": '<path d="M3 8V4a1 1 0 0 1 1-1h4M16 3h4a1 1 0 0 1 1 1v4M21 16v4a1 1 0 0 1-1 1h-4M8 21H4a1 1 0 0 1-1-1v-4"/><circle cx="12" cy="12" r="2.5"/>',
	"move": '<path d="M12 2v20M2 12h20M12 2l-3 3m3-3 3 3M12 22l-3-3m3 3 3-3M2 12l3-3m-3 3 3 3M22 12l-3-3m3 3-3 3"/>',
	"rotate": '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 3v5h-5"/>',
	"ghosts": '<circle cx="6" cy="8" r="2.5" stroke-opacity=".45"/><circle cx="12" cy="8" r="2.5" stroke-opacity=".7"/><circle cx="18" cy="8" r="2.5"/><path d="M6 13v7M12 13v7M18 13v7" /><path d="M6 13v7" stroke-opacity=".45"/>',
	"arc": '<path d="M3 18C6 6 18 6 21 18"/><circle cx="21" cy="18" r="1.6" fill="#eef5fa"/><circle cx="3" cy="18" r="1.6"/>',
	"contact": '<rect x="4" y="4" width="16" height="16" rx="2" stroke-dasharray="3 2.5"/><circle cx="12" cy="12" r="3" fill="#eef5fa"/>',
	"split": '<rect x="2.5" y="4" width="8.5" height="16" rx="1.5"/><rect x="13" y="4" width="8.5" height="16" rx="1.5"/>',
	"step_back": '<path d="M6 5v14"/><path d="M19 5 9 12l10 7Z" fill="#eef5fa"/>',
	"step_forward": '<path d="M18 5v14"/><path d="m5 5 10 7-10 7Z" fill="#eef5fa"/>',
	"play": '<path d="m7 4 13 8-13 8Z" fill="#eef5fa"/>',
	"pause": '<rect x="6" y="4" width="4" height="16" rx="1" fill="#eef5fa"/><rect x="14" y="4" width="4" height="16" rx="1" fill="#eef5fa"/>',
	"loop": '<path d="M17 2l4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15"/><path d="m7 22-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/>',
	"reset": '<path d="M4 10a8 8 0 1 1 1 8"/><path d="M4 4v6h6"/>',
	"compare": '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M12 5v14"/><path d="M5.5 15l2-6 2 6M6.2 13h2.6"/><path d="M14.5 9h2.2a1.5 1.5 0 0 1 0 3h-2.2Zm0 3h2.6a1.5 1.5 0 0 1 0 3h-2.6Z"/>',
	"help": '<circle cx="12" cy="12" r="9.5"/><path d="M9.2 9a3 3 0 0 1 5.8 1c0 2-3 2.5-3 4.5"/><circle cx="12" cy="18" r=".6" fill="#eef5fa"/>',
	"doc": '<path d="M6 2h8l5 5v15H6Z"/><path d="M14 2v5h5M9 13h7M9 17h5"/>',
	"search": '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/>',
	"chev_down": '<path d="m6 9 6 6 6-6"/>',
	"chev_right": '<path d="m9 6 6 6-6 6"/>',
	"refresh": '<path d="M20 11a8 8 0 0 0-14.6-4.5L4 8"/><path d="M4 3v5h5"/><path d="M4 13a8 8 0 0 0 14.6 4.5L20 16"/><path d="M20 21v-5h-5"/>',
}

## Stroke icon, 2x raster (36 px) so it stays sharp on a retina window; drawn at ICON pt.
static func icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name): return _icons[icon_name]
	var path: String = _PATHS.get(icon_name, "")
	if path == "": return null
	var img := Image.new()
	img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#eef5fa" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">' + path + '</g></svg>', 1.5)
	var tex := ImageTexture.create_from_image(img)
	_icons[icon_name] = tex
	return tex
