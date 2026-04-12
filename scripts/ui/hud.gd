extends CanvasLayer
class_name Hud
## HUD layer — owns every Label in the UI plus the CanvasLayer root they sit on.
##
## SCOPE DECISION (Phase 4):
##   This class *creates* all HUD widgets and exposes them as public fields.
##   game.gd still writes to them directly (score_label.text = ...) and still
##   hosts the _show_X helper methods. A full method-based extraction would
##   require rewriting ~50 call sites — too risky for a visual-polish phase.
##
## VISUAL STYLE (Phase 4b):
##   - SystemFont with bold weight + sans-serif fallback chain — distinctive
##     yet portable across macOS / Windows / Linux / mobile.
##   - Rounded panel backgrounds behind the score chip and status strip for
##     visual grouping and contrast against the 3D scene.
##   - Consistent color palette:
##       blue team: #4a90e2   red team: #e25555
##       success:   #4aea90   warning:  #f5c04a   fault: #ff3c3c
##   - Subtle drop shadows + slight letter spacing via content scale.

const AI_DIFFICULTY_COLORS: Array[Color] = [
	Color(0.29, 0.91, 0.56, 1.0),  # EASY   - green
	Color(0.96, 0.75, 0.29, 1.0),  # MEDIUM - amber
	Color(0.98, 0.33, 0.33, 1.0),  # HARD   - red
]

const COL_BLUE: Color = Color(0.29, 0.62, 0.95, 1.0)
const COL_RED: Color = Color(0.95, 0.33, 0.33, 1.0)
const COL_WHITE: Color = Color(1, 1, 1, 1)
const COL_AMBER: Color = Color(1.0, 0.82, 0.25, 1.0)
const COL_CYAN: Color = Color(0.29, 0.85, 1.0, 1.0)
const COL_SHADOW: Color = Color(0, 0, 0, 0.85)

var score: Label
var state: Label
var difficulty: Label
var debug: Label
var fault: Label
var out_text: Label
var zone: Label
var speed: Label
var shot_type: Label
var posture_debug: Label

# Panels
var _score_panel: Panel
var _status_panel: Panel

# Shared fonts
var _font_regular: SystemFont
var _font_bold: SystemFont
var _font_black: SystemFont

func _ready() -> void:
	name = "UI"
	_build_fonts()
	_build_panels()
	_build_labels()

# ── Fonts ────────────────────────────────────────────────────────────────────

func _build_fonts() -> void:
	# Sans-serif stack. SystemFont falls through the list until one resolves
	# on the host OS. These cover macOS, iOS, Android, Windows, and Linux.
	var family_stack := PackedStringArray([
		"SF Pro Display",
		"Helvetica Neue",
		"Inter",
		"Roboto",
		"Segoe UI",
		"Arial",
		"sans-serif",
	])

	_font_regular = SystemFont.new()
	_font_regular.font_names = family_stack
	_font_regular.font_weight = 500
	_font_regular.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font_regular.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF

	_font_bold = SystemFont.new()
	_font_bold.font_names = family_stack
	_font_bold.font_weight = 700
	_font_bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font_bold.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF

	_font_black = SystemFont.new()
	_font_black.font_names = family_stack
	_font_black.font_weight = 900
	_font_black.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font_black.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF

func _apply_font(label: Label, font: SystemFont) -> void:
	label.add_theme_font_override("font", font)

# ── Panels ───────────────────────────────────────────────────────────────────

func _make_rounded_stylebox(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb

func _build_panels() -> void:
	# Top score chip background.
	_score_panel = Panel.new()
	_score_panel.name = "ScorePanel"
	_score_panel.anchor_left = 0.5
	_score_panel.anchor_right = 0.5
	_score_panel.anchor_top = 0.0
	_score_panel.offset_left = -260
	_score_panel.offset_right = 260
	_score_panel.offset_top = 20
	_score_panel.offset_bottom = 124
	_score_panel.add_theme_stylebox_override("panel",
		_make_rounded_stylebox(Color(0.05, 0.07, 0.12, 0.75), Color(1, 1, 1, 0.15), 22))
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_panel)

	# Status strip under the score.
	_status_panel = Panel.new()
	_status_panel.name = "StatusPanel"
	_status_panel.anchor_left = 0.08
	_status_panel.anchor_right = 0.92
	_status_panel.anchor_top = 0.0
	_status_panel.offset_top = 140
	_status_panel.offset_bottom = 216
	_status_panel.add_theme_stylebox_override("panel",
		_make_rounded_stylebox(Color(0.07, 0.09, 0.15, 0.55), Color(1, 1, 1, 0.08), 16))
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_panel)

# ── Labels ───────────────────────────────────────────────────────────────────

func _build_labels() -> void:
	score = Label.new()
	score.text = "0 - 0"
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 72)
	score.add_theme_color_override("font_color", COL_WHITE)
	score.add_theme_color_override("font_shadow_color", COL_SHADOW)
	score.add_theme_constant_override("shadow_offset_x", 3)
	score.add_theme_constant_override("shadow_offset_y", 3)
	score.anchor_left = 0.5
	score.anchor_right = 0.5
	score.anchor_top = 0.0
	score.offset_left = -260
	score.offset_right = 260
	score.offset_top = 36
	score.offset_bottom = 124
	_apply_font(score, _font_black)
	add_child(score)

	difficulty = Label.new()
	difficulty.text = "EASY"
	difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	difficulty.add_theme_font_size_override("font_size", 30)
	difficulty.add_theme_color_override("font_color", AI_DIFFICULTY_COLORS[0])
	difficulty.add_theme_color_override("font_shadow_color", COL_SHADOW)
	difficulty.add_theme_constant_override("shadow_offset_x", 2)
	difficulty.add_theme_constant_override("shadow_offset_y", 2)
	difficulty.anchor_left = 0.0
	difficulty.anchor_top = 0.0
	difficulty.offset_left = 26
	difficulty.offset_top = 28
	difficulty.offset_right = 220
	difficulty.offset_bottom = 72
	_apply_font(difficulty, _font_bold)
	add_child(difficulty)

	state = Label.new()
	state.text = "Hold SPACE to charge serve"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_font_size_override("font_size", 30)
	state.add_theme_color_override("font_color", Color(1, 0.95, 0.55, 1))
	state.add_theme_color_override("font_shadow_color", COL_SHADOW)
	state.add_theme_constant_override("shadow_offset_x", 2)
	state.add_theme_constant_override("shadow_offset_y", 2)
	state.anchor_left = 0.08
	state.anchor_right = 0.92
	state.anchor_top = 0.0
	state.offset_top = 150
	state.offset_bottom = 210
	_apply_font(state, _font_bold)
	add_child(state)

	debug = Label.new()
	debug.text = ""
	debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug.add_theme_font_size_override("font_size", 22)
	debug.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8, 0.92))
	debug.add_theme_color_override("font_shadow_color", COL_SHADOW)
	debug.add_theme_constant_override("shadow_offset_x", 1)
	debug.add_theme_constant_override("shadow_offset_y", 1)
	debug.anchor_left = 0.0
	debug.anchor_right = 0.6
	debug.anchor_top = 1.0
	debug.anchor_bottom = 1.0
	debug.offset_top = -230
	debug.offset_left = 20
	_apply_font(debug, _font_regular)
	add_child(debug)

	fault = Label.new()
	fault.text = ""
	fault.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fault.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fault.add_theme_font_size_override("font_size", 88)
	fault.add_theme_color_override("font_color", Color(1.0, 0.22, 0.22, 1.0))
	fault.add_theme_color_override("font_shadow_color", COL_SHADOW)
	fault.add_theme_constant_override("shadow_offset_x", 4)
	fault.add_theme_constant_override("shadow_offset_y", 4)
	fault.anchor_left = 0.0
	fault.anchor_right = 1.0
	fault.anchor_top = 0.0
	fault.anchor_bottom = 1.0
	fault.modulate.a = 0.0
	_apply_font(fault, _font_black)
	add_child(fault)

	out_text = Label.new()
	out_text.text = "OUT!"
	out_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	out_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	out_text.add_theme_font_size_override("font_size", 160)
	out_text.add_theme_color_override("font_color", Color(1.0, 0.42, 0.0, 1.0))
	out_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	out_text.add_theme_constant_override("shadow_offset_x", 6)
	out_text.add_theme_constant_override("shadow_offset_y", 6)
	out_text.anchor_left = 0.0
	out_text.anchor_right = 1.0
	out_text.anchor_top = 0.2
	out_text.anchor_bottom = 0.8
	out_text.modulate.a = 0.0
	_apply_font(out_text, _font_black)
	add_child(out_text)

	zone = Label.new()
	zone.text = ""
	zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone.add_theme_font_size_override("font_size", 56)
	zone.add_theme_color_override("font_color", COL_CYAN)
	zone.add_theme_color_override("font_shadow_color", COL_SHADOW)
	zone.add_theme_constant_override("shadow_offset_x", 3)
	zone.add_theme_constant_override("shadow_offset_y", 3)
	zone.anchor_left = 0.0
	zone.anchor_right = 1.0
	zone.anchor_top = 0.0
	zone.anchor_bottom = 1.0
	zone.offset_top = 240
	zone.modulate.a = 0.0
	_apply_font(zone, _font_bold)
	add_child(zone)

	speed = Label.new()
	speed.text = ""
	speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed.add_theme_font_size_override("font_size", 52)
	speed.add_theme_color_override("font_color", COL_AMBER)
	speed.add_theme_color_override("font_shadow_color", COL_SHADOW)
	speed.add_theme_constant_override("shadow_offset_x", 3)
	speed.add_theme_constant_override("shadow_offset_y", 3)
	speed.anchor_left = 0.55
	speed.anchor_right = 1.0
	speed.anchor_top = 0.0
	speed.offset_top = 28
	speed.offset_right = -26
	speed.offset_bottom = 100
	speed.modulate.a = 0.0
	_apply_font(speed, _font_black)
	add_child(speed)

	shot_type = Label.new()
	shot_type.text = ""
	shot_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shot_type.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shot_type.add_theme_font_size_override("font_size", 72)
	shot_type.add_theme_color_override("font_shadow_color", COL_SHADOW)
	shot_type.add_theme_constant_override("shadow_offset_x", 3)
	shot_type.add_theme_constant_override("shadow_offset_y", 3)
	shot_type.anchor_left = 0.0
	shot_type.anchor_right = 1.0
	shot_type.anchor_top = 0.0
	shot_type.anchor_bottom = 0.0
	shot_type.offset_top = 120
	shot_type.offset_bottom = 220
	shot_type.offset_left = 0
	shot_type.offset_right = 0
	shot_type.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot_type.modulate.a = 0.0
	_apply_font(shot_type, _font_bold)
	add_child(shot_type)

	posture_debug = Label.new()
	posture_debug.name = "PostureDebugLabel"
	posture_debug.text = ""
	posture_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	posture_debug.add_theme_font_size_override("font_size", 26)
	posture_debug.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7, 1.0))
	posture_debug.add_theme_color_override("font_shadow_color", COL_SHADOW)
	posture_debug.add_theme_constant_override("shadow_offset_x", 1)
	posture_debug.add_theme_constant_override("shadow_offset_y", 1)
	posture_debug.anchor_left = 0.55
	posture_debug.anchor_right = 1.0
	posture_debug.anchor_top = 0.0
	posture_debug.offset_top = 300
	posture_debug.offset_right = -26
	posture_debug.offset_bottom = 360
	_apply_font(posture_debug, _font_regular)
	add_child(posture_debug)

func set_gameplay_elements_visible(p_visible: bool) -> void:
	score.visible = p_visible
	state.visible = p_visible
	difficulty.visible = p_visible
	_score_panel.visible = p_visible
	_status_panel.visible = p_visible
	# We don't necessarily hide the others as they are transient/debug,
	# but we could if needed. ScoreboardUI might manage those better.
