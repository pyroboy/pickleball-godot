extends Control
## Phone Pose Studio layout (iPhone, portrait), AutoPose only. Drives the same PoseStudio as the
## desktop window (pose_studio.gd, phone = true): AutoPose, undo, timeline, save all run there.
## Layout (wireframe "Mobile Pose Studio", claude.ai artifact PDK9TMrqEWTLk4L5HEzAE8):
##   top bar     menu (pose drawer), pose name, undo, redo, save
##   scene       the 3D preview, two thirds of the screen: rings, view buttons, AutoPose chips
##   lower third timeline (W / C / F keys, scrub, play), a small star row (opens big stars),
##               Notes / Versions; tapping a ring swaps it for that ring's options
## Canvas units (the project's 720-wide portrait canvas): 1 pt is about 1.85 units.

const Ui = preload("res://scripts/ui/game_ui_theme.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const StudioTheme = preload("res://scripts/studio/studio_theme.gd")
const PoseDiff = preload("res://scripts/studio/pose_diff_util.gd")
const Queue = preload("res://scripts/studio/phone_sync_queue.gd")
const ScrubTrack = preload("res://scripts/studio/studio_timeline.gd").ScrubTrack
const SpeedGraph = preload("res://scripts/studio/studio_speed_graph.gd")
const STAGE_COLORS := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
const STAGE_SHORT := ["W", "C", "F"]
const FONT := 28
const SMALL := 23
const TITLE := 32
const TAP := 80          # 44 pt touch target
const HEAD_H := 96
const GAP := 12
const VIEWS := ["front", "side", "back"]
const AP_NAMES := {"right_hand": "Right hand", "left_hand": "Left hand", "paddle_tip": "Paddle tip", "right_elbow": "Right elbow",
	"left_elbow": "Left elbow", "right_knee": "Right knee", "left_knee": "Left knee", "right_foot": "Right foot",
	"left_foot": "Left foot", "hips": "Hips", "chest": "Chest", "head": "Head", "right_shoulder": "Right shoulder",
	"left_shoulder": "Left shoulder", "right_hip": "Right hip", "left_hip": "Left hip", "paddle_edge_a": "Paddle edge", "paddle_edge_b": "Paddle edge"}
const LEVELS := [["Loose", 0.5], ["Normal", 1.0], ["Stiff", 2.0]]
const REGIONS := [["Arms", "arms"], ["Torso", "torso"], ["Legs", "legs"]]
const CURVES := [["Straight", 0.0], ["Natural", 0.5], ["Round", 1.0]]

var studio
var _col: VBoxContainer
var _top_fill: ColorRect      # behind the Dynamic Island / status bar (the top bar's colour)
var _bottom_fill: ColorRect   # behind the home indicator (the lower panel's colour)
var _drawer_pad: MarginContainer
var _star_pad: MarginContainer
var insets := Vector2.ZERO    # safe-area insets (top, bottom) in canvas units
var _lower_scroll: ScrollContainer
var _lower_pad: MarginContainer
var _third := 0.0
var _scene: Control
var _lower: VBoxContainer
var _sheet: VBoxContainer
var _title_sub: Label
var _title: Label
var _undo: Button
var _redo: Button
var _save: Button
var _keys: Array[Button] = []
var _scrub
var _play: Button
var _stars_row: Button
var _stars_label: Label
var _small_stars: Array[Label] = []
var _tab_notes: Button
var _tab_versions: Button
var _notes_box: VBoxContainer
var _versions_box: VBoxContainer
var _note_edit: LineEdit
var _toast: Label
var _toast_text := ""
var _toast_time := 0.0
var _chip_balance: Button
var _chip_look: Button
var _chip_pins: Button
var _chip_stiff: Button
var _view_btn: Button
var _view_i := 0
var _sheet_title: Label
var _sheet_pin: Button
var _sheet_note: Label
var _layers: VBoxContainer
var _layer_btns := {}        # "ghosts" | "arc" | "contact" -> Button
var _region_btns := {}       # region -> [Button x3]
var _swing: VBoxContainer     # swing sheet (replaces the lower third): curve, speed, timing
var _curve_btns: Array[Button] = []
var _speed: VBoxContainer       # speed sheet (replaces the lower third): the speed ramp graph
var _speed_graph                # its graph (studio_speed_graph.gd, finger-sized)
var _speed_del: Button          # Delete point (shown while a speed point is selected)
var _speed_how: Label           # one-line hint above the graph
var _swing_info: Label
var _path_info: Label
var _path_del: Button
var _path_clear: Button
var _path_auto: Button          # Auto curve: the selected key's tangent back to automatic
var _sel_path := -1.0   # progress of the path key tapped on the arc (-1 = none)
var _handle := ""
var _drawer: Control
var _drawer_list: VBoxContainer
var _drawer_open := {"Strokes": true, "Body stances": false, "Serves": false, "Ball actions": true}
var _search: LineEdit
var _star_popup: Control
var _big_stars: Array[Button] = []
var _tab := "notes"
var _sync_scrub := false
var _last_key := ""
var _last_stage := -1

func build(owner_studio) -> void:
	studio = owner_studio
	name = "PhoneStudio"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _theme()
	var bg := ColorRect.new(); bg.color = Ui.BACKDROP; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	_top_fill = ColorRect.new(); _top_fill.color = Ui.PANEL; _top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_fill.anchor_right = 1.0; add_child(_top_fill)
	_bottom_fill = ColorRect.new(); _bottom_fill.color = Ui.PANEL; _bottom_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_fill.anchor_right = 1.0; _bottom_fill.anchor_top = 1.0; _bottom_fill.anchor_bottom = 1.0; add_child(_bottom_fill)
	var col := VBoxContainer.new(); col.name = "Column"; col.add_theme_constant_override("separation", 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(col)
	_col = col
	_build_header(col)
	_scene = Control.new(); _scene.name = "Scene"; _scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene.clip_contents = true
	col.add_child(_scene)
	_lower = VBoxContainer.new(); _lower.name = "Lower"; _lower.add_theme_constant_override("separation", 0)
	col.add_child(_lower)
	_build_lower(_lower)
	_sheet = VBoxContainer.new(); _sheet.name = "RingSheet"; _sheet.visible = false
	_sheet.add_theme_constant_override("separation", GAP)
	col.add_child(_sheet)
	_build_sheet(_sheet)
	_swing = VBoxContainer.new(); _swing.name = "SwingSheet"; _swing.visible = false
	col.add_child(_swing)
	_build_swing(_swing)
	_speed = VBoxContainer.new(); _speed.name = "SpeedSheet"; _speed.visible = false
	col.add_child(_speed)
	_build_speed(_speed)
	_build_drawer()
	_build_star_popup()
	resized.connect(_fit)
	_fit.call_deferred()
	studio.handle_tapped.connect(_open_sheet)
	studio.pose_selected.connect(func(_k): _refresh_pose())
	studio.pose_saved.connect(func(_k, _v): _refresh_pose())
	studio.pose_edited.connect(func(_k): if _swing.visible: _refresh_swing.call_deferred())

## Safe area (iPhone: Dynamic Island / status bar on top, home indicator below): the column
## sits inside it and the strips outside take the bars' colour. The lower third (and the
## sheets in its place) is a third of the safe height. Mac test: --studio-safe=TOP,BOTTOM
## (canvas units; iPhone 15 Pro is about 108,62).
func _fit() -> void:
	insets = _safe_insets()
	_col.offset_top = insets.x; _col.offset_bottom = -insets.y
	_top_fill.offset_bottom = insets.x
	_bottom_fill.offset_top = -insets.y
	if _drawer_pad: _drawer_pad.add_theme_constant_override("margin_top", int(insets.x)); _drawer_pad.add_theme_constant_override("margin_bottom", int(insets.y))
	if _star_pad: _star_pad.add_theme_constant_override("margin_bottom", int(insets.y)); (_star_pad.get_parent() as Control).offset_top = -460 - insets.y
	var third: float = floor((size.y - insets.x - insets.y) / 3.0)
	_third = third
	_sheet.custom_minimum_size.y = third
	_swing.custom_minimum_size.y = third
	_speed.custom_minimum_size.y = third
	_fit_lower()

## The lower panel is as tall as its content (timeline, stars, tabs, the notes / versions shown),
## at most a third of the safe height (then the list scrolls): no empty band under short lists.
func _fit_lower() -> void:
	if _lower_scroll == null or _third <= 0.0: return
	var fixed := 0.0
	for c in _lower.get_children():
		if c != _lower_scroll and c is Control and c.visible: fixed += c.get_combined_minimum_size().y
	var want: float = fixed + _lower_pad.get_combined_minimum_size().y
	_lower.custom_minimum_size.y = minf(_third, ceilf(want))
	_lower.size_flags_vertical = Control.SIZE_FILL

func _safe_insets() -> Vector2:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--studio-safe="):
			var v := String(a).get_slice("=", 1).split(",")
			if v.size() == 2: return Vector2(float(v[0]), float(v[1]))
	if get_viewport() == null: return Vector2.ZERO
	var full := get_viewport().get_visible_rect()
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	return Vector2(maxf(safe.position.y - full.position.y, 0.0), maxf(full.end.y - safe.end.y, 0.0))

func mount_preview(pv: Control) -> void:
	pv.reparent(_scene, false)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene.move_child(pv, 0)
	_build_scene_overlay()
	_scene.resized.connect(_refit)

## The camera fits the pose once the scene has its real size (and again after a resize while
## it still follows the pose): fitting earlier, at the editor's start size, left it far away.
func _refit() -> void:
	var vi = studio._view_input
	if vi != null and vi.auto_fit and vi.drag == vi.Drag.NONE: vi.frame_pose()

## For the link / tests: the screen width, the column's needed width (wider = the layout is
## pushed off the right edge) and every visible control that ends past the screen.
func layout_state() -> Dictionary:
	var over: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			if not (c is Control) or not c.is_visible_in_tree(): continue
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 1.0 and (r.end.x > size.x + 1.0 or r.position.x < -1.0) and not (c.get_parent() is ScrollContainer):
				over.append({"name": String(c.name), "type": c.get_class(), "x0": r.position.x, "x1": r.end.x, "text": String(c.get("text")) if c.get("text") != null else ""})
			stack.append(c)
	return {"screen": size.x, "column_min": _col.get_combined_minimum_size().x, "column": _col.size.x, "off_screen": over.slice(0, 20)}

func studio_ready() -> void:
	var vi = studio.get("_view_input")
	if vi != null: vi.legend_lift = 64.0 + GAP * 2.0   # the speed legend sits above the AutoPose chips
	_refresh_pose()
	_refit.call_deferred()

# ---------------------------------------------------------------- look

func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = Ui.sans_font()
	t.default_font_size = FONT
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var b := StyleBoxFlat.new()
		b.bg_color = Ui.SURFACE_PRESSED if state in ["pressed", "hover_pressed"] else Ui.SURFACE_HOVER if state == "hover" else Ui.SURFACE
		if state == "focus": b.draw_center = false
		b.border_color = Ui.BORDER; b.set_border_width_all(2); b.set_corner_radius_all(16)
		b.content_margin_left = 18; b.content_margin_right = 18; b.content_margin_top = 8; b.content_margin_bottom = 8
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", Ui.INK); t.set_color("font_hover_color", "Button", Ui.INK)
	t.set_color("font_pressed_color", "Button", Ui.INK); t.set_color("font_disabled_color", "Button", Ui.MUTED)
	t.set_color("font_color", "Label", Ui.INK)
	var le := StyleBoxFlat.new(); le.bg_color = Ui.PANEL; le.border_color = Ui.BORDER; le.set_border_width_all(2)
	le.set_corner_radius_all(16); le.content_margin_left = 18; le.content_margin_right = 18
	t.set_stylebox("normal", "LineEdit", le); t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", Ui.INK); t.set_color("font_placeholder_color", "LineEdit", Ui.MUTED)
	return t

func _btn(text: String, cb: Callable, w := 0.0, h := TAP) -> Button:
	var b := Button.new(); b.text = text; b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(cb)
	return b

func _label(text: String, size_px := FONT, color := Ui.INK) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size_px); l.add_theme_color_override("font_color", color)
	return l

func _panel(color: Color, radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = color; s.set_corner_radius_all(radius)
	return s

func _tint(b: Button, on: bool, color := Ui.ACCENT) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color if on else Ui.SURFACE; s.border_color = color if on else Ui.BORDER
	s.set_border_width_all(2); s.set_corner_radius_all(16)
	s.content_margin_left = 18; s.content_margin_right = 18
	for st in ["normal", "hover", "pressed", "hover_pressed"]: b.add_theme_stylebox_override(st, s)
	var ink := Ui.PANEL if on else Ui.INK
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: b.add_theme_color_override(c, ink)

# ---------------------------------------------------------------- top bar

func _build_header(col: Control) -> void:
	var bar := PanelContainer.new(); bar.name = "TopBar"; bar.add_theme_stylebox_override("panel", _panel(Ui.PANEL))
	bar.custom_minimum_size.y = HEAD_H
	col.add_child(bar)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	row.add_child(_btn("☰", _toggle_drawer, TAP))
	var names := VBoxContainer.new(); names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER; names.add_theme_constant_override("separation", 0)
	var tap := Button.new(); tap.flat = true; tap.focus_mode = Control.FOCUS_NONE; tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tap.pressed.connect(_toggle_drawer)
	tap.add_child(names); names.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_sub = _label("", SMALL, Ui.MUTED); _title = _label("", TITLE)
	_title.clip_text = true; _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_title_sub); names.add_child(_title)
	row.add_child(tap)
	_undo = _btn("↶", func(): studio.undo(); _refresh_pose(), TAP); row.add_child(_undo)
	_redo = _btn("↷", func(): studio.redo(); _refresh_pose(), TAP); row.add_child(_redo)
	_save = _btn("Save", _do_save, 130); row.add_child(_save)
	_tint(_save, true, Ui.BLUE)

func _do_save() -> void:
	var r: Dictionary = studio.save("", "user")
	_show_toast(String(r.get("error", "")) if not r.get("ok", false) else
		("Nothing to save" if int(r.get("changed", 0)) == 0 else "Saved on the phone · %d change(s) · syncs to the Mac" % int(r.get("changed", 0))))
	_refresh_pose()

# ---------------------------------------------------------------- scene overlay

func _build_scene_overlay() -> void:
	var hint := _label("Ring: drag or tap · empty space: orbit · 2 fingers: pan, pinch", SMALL)
	var hp := PanelContainer.new(); hp.add_theme_stylebox_override("panel", _pill())
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE; hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.add_child(hint); _scene.add_child(hp)
	hp.position = Vector2(GAP, GAP)
	var views := HBoxContainer.new(); views.add_theme_constant_override("separation", 8)
	views.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); views.position.x -= 0
	views.add_child(_btn("Swing", func(): _open_sheet("swing"), 124, 64))
	var spb := _btn("Speed", func(): _open_sheet("speed"), 124, 64); spb.name = "SpeedButton"; views.add_child(spb)
	views.add_child(_btn("Layers", func(): _layers.visible = not _layers.visible; _refresh_layers(), 130, 64))
	_view_btn = _btn("Front", _next_view, 120, 64); views.add_child(_view_btn)
	views.add_child(_btn("⤢", func(): studio.frame_pose(), 64, 64))
	_scene.add_child(views)
	views.anchor_left = 1.0; views.anchor_right = 1.0; views.offset_left = -610; views.offset_right = -GAP; views.offset_top = 72
	_layers = VBoxContainer.new(); _layers.name = "Layers"; _layers.visible = false
	_layers.add_theme_constant_override("separation", 8)
	_layers.anchor_left = 1.0; _layers.anchor_right = 1.0; _layers.offset_left = -346; _layers.offset_right = -146; _layers.offset_top = 72 + 64 + 8
	for l in [["ghosts", "Ghosts"], ["arc", "Trajectory"], ["contact", "Contact box"]]:
		var b := _btn(l[1], _toggle_layer.bind(l[0]), 200, 64); b.add_theme_font_size_override("font_size", SMALL)
		_layer_btns[l[0]] = b; _layers.add_child(b)
	_scene.add_child(_layers)
	var chips := HBoxContainer.new(); chips.name = "AutoPoseChips"; chips.add_theme_constant_override("separation", 8)
	chips.anchor_left = 0.0; chips.anchor_right = 1.0; chips.anchor_top = 1.0; chips.anchor_bottom = 1.0
	chips.offset_left = GAP; chips.offset_right = -GAP; chips.offset_top = -64 - GAP; chips.offset_bottom = -GAP
	_chip_balance = _btn("Balance", func(): studio.set_autopose_balance(not studio.autopose_balance); _refresh_chips(), 0, 64)
	_chip_look = _btn("Look", func(): studio.set_autopose_look(not studio.autopose_look); _refresh_chips(), 0, 64)
	_chip_pins = _btn("Pins", func(): studio.reset_autopose_pins(); _refresh_chips(); _show_toast("Pins back to the feet"), 0, 64)
	_chip_stiff = _btn("Stiff 1×", _cycle_stiffness, 0, 64)
	var relax := _btn("Relax", _relax, 0, 64)
	for c in [_chip_balance, _chip_look, _chip_pins, _chip_stiff, relax]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.add_theme_font_size_override("font_size", SMALL); chips.add_child(c)
	_scene.add_child(chips)
	_toast = _label("", SMALL); _toast.visible = false; _toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", _pill())
	_toast.anchor_left = 0.0; _toast.anchor_right = 1.0; _toast.anchor_top = 1.0; _toast.anchor_bottom = 1.0
	_toast.offset_left = GAP * 2; _toast.offset_right = -GAP * 2; _toast.offset_top = -170; _toast.offset_bottom = -64 - GAP * 3
	_scene.add_child(_toast)
	_refresh_chips()

func _layer_on(what: String) -> bool:
	var pv = studio.preview
	match what:
		"ghosts": return pv != null and bool(pv._ghosts_visible) and int(pv.inbetween_count) > 0
		"arc": return pv != null and bool(pv._arc_visible)
		_: return bool(studio._contact_on)

## Ghosts (in-between poses), trajectory (the paddle's arc) and the contact box.
func _toggle_layer(what: String) -> void:
	var on := not _layer_on(what)
	if what == "ghosts": studio.set_ghost_count(3 if on else 0)
	studio.set_overlay(what, on)
	_refresh_layers()

func _refresh_layers() -> void:
	for w in _layer_btns: _tint(_layer_btns[w], _layer_on(w))

func _pill() -> StyleBoxFlat:
	var s := _panel(Color(Ui.PANEL, 0.88), 18)
	s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

func _next_view() -> void:
	_view_i = (_view_i + 1) % VIEWS.size()
	studio.view(VIEWS[_view_i])
	_view_btn.text = String(VIEWS[_view_i]).capitalize()

func _cycle_stiffness() -> void:
	var now: float = float(studio.autopose_stiffness.get("all", 1.0))
	var next := 2.0 if is_equal_approx(now, 1.0) else 0.5 if is_equal_approx(now, 2.0) else 1.0
	studio.set_autopose_stiffness("all", next)
	_refresh_chips()

func _relax() -> void:
	var r: Dictionary = studio.autopose_relax()
	_show_toast("Relaxed this key" if r.get("ok", false) else String(r.get("error", "Relax: nothing to do")))

func _refresh_chips() -> void:
	if _chip_balance == null: return
	_tint(_chip_balance, studio.autopose_balance)
	_tint(_chip_look, studio.autopose_look)
	var pins: int = (studio.autopose_pins as Dictionary).values().filter(func(v): return v).size()
	_chip_pins.text = "Pins %d" % pins
	var s: float = float(studio.autopose_stiffness.get("all", 1.0))
	_chip_stiff.text = "Stiff %s×" % ("½" if is_equal_approx(s, 0.5) else str(int(s)))

# ---------------------------------------------------------------- lower third

func _build_lower(lower: VBoxContainer) -> void:
	var tl := PanelContainer.new(); tl.add_theme_stylebox_override("panel", _row_box())
	lower.add_child(tl)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); tl.add_child(row)
	for i in 3:
		var b := _btn(STAGE_SHORT[i], studio.set_stage.bind(i), 72, 68)
		b.add_theme_color_override("font_color", STAGE_COLORS[i])
		_keys.append(b); row.add_child(b)
	_scrub = ScrubTrack.new(); _scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.custom_minimum_size = Vector2(120, 68)
	_scrub.value_changed.connect(func(t): if not _sync_scrub: studio._timeline.seek(t))
	_scrub.mark_moved.connect(studio._timeline._on_mark_moved)
	row.add_child(_scrub)
	# Icons, not "▶" text: the iPhone's font has no glyph for it (the button showed empty).
	_play = _btn("", func(): studio._timeline.toggle_play(), 80, 68); row.add_child(_play)
	_play.icon = StudioTheme.icon("play"); _play.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_play.expand_icon = true; _play.add_theme_constant_override("icon_max_width", 40)
	_stars_row = Button.new(); _stars_row.flat = true; _stars_row.focus_mode = Control.FOCUS_NONE
	_stars_row.custom_minimum_size.y = 60; _stars_row.add_theme_stylebox_override("normal", _row_box())
	_stars_row.pressed.connect(_open_stars)
	var sr := HBoxContainer.new(); sr.add_theme_constant_override("separation", 6); sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); sr.offset_left = 18
	_stars_row.add_child(sr)
	for i in 5:
		var st := _label("☆", 30, Ui.GOLD); st.mouse_filter = Control.MOUSE_FILTER_IGNORE; _small_stars.append(st); sr.add_child(st)
	_stars_label = _label("Tap to rate", SMALL, Ui.MUTED); _stars_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sr.add_child(_stars_label)
	lower.add_child(_stars_row)
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 0)
	_tab_notes = _btn("Notes", func(): _tab = "notes"; _refresh_tabs(), 0, 64)
	_tab_versions = _btn("Versions", func(): _tab = "versions"; _refresh_tabs(), 0, 64)
	for t in [_tab_notes, _tab_versions]: t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tabs.add_child(t)
	lower.add_child(tabs)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new(); pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + side, GAP)
	scroll.add_child(pad)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 8); pad.add_child(content)
	lower.add_child(scroll)
	_lower_scroll = scroll; _lower_pad = pad
	content.minimum_size_changed.connect(_fit_lower, CONNECT_DEFERRED)
	_notes_box = VBoxContainer.new(); _notes_box.add_theme_constant_override("separation", 8); content.add_child(_notes_box)
	var add := HBoxContainer.new(); add.add_theme_constant_override("separation", 8)
	_note_edit = LineEdit.new(); _note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_edit.custom_minimum_size.y = 72; _note_edit.placeholder_text = "Note on this moment…"
	_note_edit.text_submitted.connect(func(_t): _add_note())
	add.add_child(_note_edit); add.add_child(_btn("Add", _add_note, 110, 72))
	_notes_box.add_child(add)
	_versions_box = VBoxContainer.new(); _versions_box.add_theme_constant_override("separation", 6); content.add_child(_versions_box)

func _row_box() -> StyleBoxFlat:
	var s := _panel(Ui.PANEL)
	s.content_margin_left = GAP; s.content_margin_right = GAP; s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

func _add_note() -> void:
	var text := _note_edit.text.strip_edges()
	if text == "" or studio.key == "": return
	var tl = studio._timeline.state()
	Queue.enqueue("note", {"key": studio.key, "text": text, "stage": ["windup", "contact", "finish"][studio.stage],
		"time_on_timeline": float(tl.get("t", 0.0)) if bool(tl.get("active", false)) else null})
	_note_edit.text = ""
	_show_toast("Note kept on the phone · syncs to the Mac")
	_refresh_notes()

func _refresh_tabs() -> void:
	_tint(_tab_notes, _tab == "notes"); _tint(_tab_versions, _tab == "versions")
	_notes_box.visible = _tab == "notes"; _versions_box.visible = _tab == "versions"
	if _tab == "notes": _refresh_notes()
	else: _refresh_versions()

func _refresh_notes() -> void:
	for c in _notes_box.get_children():
		if c is Label or c is PanelContainer: c.queue_free()
	var notes: Array = Queue.notes_for(studio.key)
	if notes.is_empty(): _notes_box.add_child(_label("No notes on this pose yet", SMALL, Ui.MUTED)); return
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", _card())
		var v := VBoxContainer.new(); card.add_child(v)
		v.add_child(_label("%s · %s" % [String(n.get("stage", "")).capitalize(), n.get("status", "")], SMALL, Ui.MUTED))
		var t := _label(String(n.get("text", "")), FONT); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(t)
		var reply = n.get("reply")
		if reply is Dictionary and String(reply.get("text", "")) != "":
			var rl := _label("Reply: " + String(reply.text), SMALL, Ui.BLUE); rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(rl)
		_notes_box.add_child(card)

func _card() -> StyleBoxFlat:
	var s := _panel(Ui.SURFACE, 14); s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

func _refresh_versions() -> void:
	for c in _versions_box.get_children(): c.queue_free()
	var saves: Array = Queue.pending_for(studio.key, "save")
	if not saves.is_empty():
		_versions_box.add_child(_label("%d save(s) on the phone, waiting for the Mac sync" % saves.size(), SMALL, Ui.GOLD))
	var vs: Array = Queue.versions_for(studio.key)
	if vs.is_empty() and saves.is_empty(): _versions_box.add_child(_label("No versions synced to this phone yet", SMALL, Ui.MUTED))
	for i in range(vs.size() - 1, maxi(-1, vs.size() - 12), -1):
		var r: Dictionary = vs[i]
		var l := _label("v%03d · %s · %s" % [int(r.get("n", 0)), r.get("author", ""), r.get("message", "")], SMALL)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_versions_box.add_child(l)

# ---------------------------------------------------------------- ring sheet (tap a ring)

func _build_sheet(sheet: VBoxContainer) -> void:
	sheet.add_theme_constant_override("separation", 10)
	var bg := PanelContainer.new(); bg.add_theme_stylebox_override("panel", _row_box()); bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(bg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); bg.add_child(v)
	var head := HBoxContainer.new()
	_sheet_title = _label("", TITLE); _sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sheet_title); head.add_child(_btn("Done", _close_sheet, 130, 64)); v.add_child(head)
	var acts := HBoxContainer.new(); acts.add_theme_constant_override("separation", 8)
	_sheet_pin = _btn("Pin", _toggle_pin, 0); _sheet_pin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rp := _btn("Reset pins", func(): studio.reset_autopose_pins(); _refresh_sheet(); _refresh_chips(), 0); rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rx := _btn("Relax key", _relax, 0); rx.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _tint(rx, true, Ui.INK)
	for b in [_sheet_pin, rp, rx]: acts.add_child(b)
	v.add_child(acts)
	_sheet_note = _label("", SMALL, Ui.MUTED); _sheet_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sheet_note)
	v.add_child(_label("Stiffness · stiff = moves less (arms: body follows more)", SMALL, Ui.MUTED))
	for reg in REGIONS:
		var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 8)
		var name_l := _label(reg[0], SMALL); name_l.custom_minimum_size.x = 100; r.add_child(name_l)
		var bs: Array = []
		for lv in LEVELS:
			var b := _btn(lv[0], _set_region.bind(reg[1], lv[1]), 0, 60); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", SMALL); bs.append(b); r.add_child(b)
		_region_btns[reg[1]] = bs
		v.add_child(r)

func _open_sheet(id: String) -> void:
	if id.begins_with("pathkey:"):
		_sel_path = float(id.get_slice(":", 1)); id = "swing"
	elif id == "swing": _sel_path = -1.0
	if id == "speed":
		_handle = ""
		_lower.visible = false; _sheet.visible = false; _swing.visible = false; _speed.visible = true
		if not _layer_on("arc"): _toggle_layer("arc")
		_speed_graph.update_spans(); return
	if id == "swing":
		_handle = ""
		_lower.visible = false; _sheet.visible = false; _speed.visible = false; _swing.visible = true
		if not _layer_on("arc"): _toggle_layer("arc")
		_refresh_swing(); return
	_handle = id
	_lower.visible = false; _swing.visible = false; _speed.visible = false; _sheet.visible = true
	_refresh_sheet()

func _close_sheet() -> void:
	_handle = ""
	_sheet.visible = false; _swing.visible = false; _speed.visible = false; _lower.visible = true

# ---------------------------------------------------------------- swing (trajectory)

## Swing sheet: the momentum arc's options. The arc (Trajectory layer) is the swing the game
## plays at full charge, a dot per game tick: wide gaps = fast paddle. Drag its W / F points to
## move that key's paddle; Curve shapes the path between the keys (swing_path_blend).
func _build_swing(sheet: VBoxContainer) -> void:
	var bg := PanelContainer.new(); bg.add_theme_stylebox_override("panel", _row_box()); bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(bg)
	var sc := ScrollContainer.new(); sc.name = "SwingScroll"; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; bg.add_child(sc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(v)
	var head := HBoxContainer.new()
	var t := _label("Swing path", TITLE); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t); head.add_child(_btn("Done", _close_sheet, 130, 64)); v.add_child(head)
	var how := _label("Dots = game ticks, blue slow to red fast. Drag W / F to move that key's paddle, a pink square to bend the path; press a dot to add a key. A tapped key shows orange tangent handles: drag one to steer the curve through it.", SMALL, Ui.MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(how)
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 8)
	var cl := _label("Curve", SMALL); cl.custom_minimum_size.x = 100; r.add_child(cl)
	for c in CURVES:
		var b := _btn(c[0], _set_curve.bind(c[1]), 0, 64); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", SMALL); _curve_btns.append(b); r.add_child(b)
	v.add_child(r)
	var sp := _btn("Speed ramp…", func(): _open_sheet("speed"), 0, 64); sp.add_theme_font_size_override("font_size", SMALL)
	v.add_child(sp)
	var keys := HBoxContainer.new(); keys.add_theme_constant_override("separation", 8)
	for st in [0, 2]:
		var b := _btn("Edit " + ("Wind-up" if st == 0 else "Finish"), _edit_key.bind(st), 0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.add_theme_color_override("font_color", STAGE_COLORS[st])
		keys.add_child(b)
	v.add_child(keys)
	var pr := HBoxContainer.new(); pr.add_theme_constant_override("separation", 8)
	_path_info = _label("", SMALL); _path_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; pr.add_child(_path_info)
	_path_del = _btn("Delete key", _delete_path_key, 190, 64); _path_del.add_theme_font_size_override("font_size", SMALL); pr.add_child(_path_del)
	_path_auto = _btn("Auto curve", _auto_tangent, 190, 64); _path_auto.name = "PathAutoTangent"; _path_auto.add_theme_font_size_override("font_size", SMALL); pr.add_child(_path_auto)
	_path_clear = _btn("Clear", func(): studio.set_path_keys([]); _sel_path = -1.0; _refresh_swing(), 120, 64)
	_path_clear.add_theme_font_size_override("font_size", SMALL); pr.add_child(_path_clear)
	v.add_child(pr)
	_swing_info = _label("", SMALL, Ui.MUTED); _swing_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_swing_info)

## Speed sheet: the speed ramp graph (same as the desktop timeline's), the whole lower third.
## Drag a part's diamond up / down; Reset puts every free part back to its authored ease.
func _build_speed(sheet: VBoxContainer) -> void:
	var bg := PanelContainer.new(); bg.add_theme_stylebox_override("panel", _row_box()); bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(bg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); bg.add_child(v)
	# Header: title, then only the actions that apply (never wider than the screen).
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 8)
	var t := _label("Speed", TITLE); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.clip_text = true; head.add_child(t)
	_speed_del = _btn("Delete point", func(): if _speed_graph.delete_selected(): _show_toast("Speed point deleted"), 200, 64)
	_speed_del.name = "SpeedDeletePoint"; _speed_del.add_theme_font_size_override("font_size", SMALL); _speed_del.visible = false; head.add_child(_speed_del)
	var rs := _btn("Reset", func(): _speed_graph.reset_all(); _show_toast("Speed back to the original"), 120, 64)
	rs.name = "SpeedReset"; rs.add_theme_font_size_override("font_size", SMALL); head.add_child(rs)
	var dn := _btn("Done", _close_sheet, 120, 64); dn.name = "SpeedDone"; head.add_child(dn); v.add_child(head)
	_speed_how = _label(SPEED_HOW, SMALL, Ui.MUTED)
	_speed_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(_speed_how)
	# Always two lines tall: the graph below must not move when the hint changes.
	_speed_how.max_lines_visible = 2
	_speed_how.custom_minimum_size.y = ceilf(_speed_how.get_theme_font("font").get_height(SMALL) * 2.0) + 2.0
	_speed_how.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_speed_graph = SpeedGraph.new(); _speed_graph.name = "PhoneSpeedGraph"; _speed_graph.studio = studio
	_speed_graph.set_scale_k(2.2); _speed_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_speed_graph.lock_note = "locked · desktop only"
	_speed_graph.locked_pressed.connect(func(): _show_toast("Strike speed changes how shots play: edit it in the desktop studio"))
	v.add_child(_speed_graph)
	_speed_graph.selection_changed.connect(_refresh_speed)

const SPEED_HOW := "Tap the line to add a point. Drag a dot up = faster, down = slower."
## Header state for the selected speed point: Delete shows, the hint names the point.
func _refresh_speed() -> void:
	var sel: Vector2i = _speed_graph.selected
	_speed_del.visible = sel.x >= 0
	_speed_how.text = SPEED_HOW if sel.x < 0 else "Point selected: drag it, or Delete point. Tap elsewhere on the line for another."

func _set_curve(value: float) -> void:
	var r: Dictionary = studio.set_swing_curve(value)
	if not r.get("ok", false): _show_toast(String(r.get("error", "Curve: cannot change it here")))
	_refresh_swing()

## The selected key's tangent handles back to automatic.
func _auto_tangent() -> void:
	var vi = studio.get("_view_input")
	if vi == null: return
	vi.sel_key_t = _sel_path; vi.reset_tangent()
	_show_toast("Curve through this key: automatic"); _refresh_swing()

func _delete_path_key() -> void:
	var keys: Array = studio.path_keys().filter(func(k): return absf(float(k[0]) - _sel_path) > 0.001)
	studio.set_path_keys(keys)
	_sel_path = -1.0
	_refresh_swing()

func _edit_key(st: int) -> void:
	studio.set_stage(st)
	_close_sheet()

func _refresh_swing() -> void:
	if _swing_info == null or studio.key == "": return
	var cur: Resource = studio.engine._current
	var blend = cur.get("swing_path_blend") if cur else null
	for i in CURVES.size(): _tint(_curve_btns[i], blend != null and absf(float(blend) - float(CURVES[i][1])) < 0.17)
	var keys: Array = studio.path_keys()
	var sel: bool = keys.any(func(k): return absf(float(k[0]) - _sel_path) < 0.001)
	if not studio.path_keys_supported(): _path_info.text = "Path keys: strokes only"
	elif sel:
		var o: Vector3 = keys.filter(func(k): return absf(float(k[0]) - _sel_path) < 0.001)[0][1]
		_path_info.text = ("Key at %d%% of Ready → Wind-up · %.0f cm off the curve" % [roundi((_sel_path - studio.LEAD_IN) * 100.0), o.length() * 100.0]) if studio.is_lead_in(_sel_path) \
			else "Key at %d%% of the swing · %.0f cm off the curve" % [roundi(_sel_path * 100.0), o.length() * 100.0]
	else: _path_info.text = "Path keys: %d" % keys.size() + ("" if keys.is_empty() else " · tap one to delete it")
	_path_del.visible = sel
	var custom_tan: bool = sel and keys.any(func(k): return absf(float(k[0]) - _sel_path) < 0.001 and k.size() > 2 and (k[2] as Vector3).length_squared() > 1e-10)
	_path_auto.visible = custom_tan
	_path_clear.visible = not keys.is_empty() and not sel
	var pv = studio.preview
	var kt: PackedFloat32Array = pv.momentum_key_times
	if kt.size() < 3:
		_swing_info.text = "No swing arc for this pose (a single stance)." if not studio.engine._has_motion() else "Turn on Layers → Trajectory to see the arc."
		return
	_swing_info.text = "Strike peak %.1f m/s · Ready→Wind-up %.2f s · strike %.2f s · finish %.2f s (timing is gameplay: desktop studio)" % [
		float(pv.momentum_contact_speed), kt[0], kt[1] - kt[0], kt[2] - kt[1]]

func _toggle_pin() -> void:
	if _handle == "": return
	var r: Dictionary = studio.set_autopose_pin(_handle)
	if not r.get("ok", true): _show_toast(String(r.get("error", "")))
	_refresh_sheet(); _refresh_chips()

func _set_region(region: String, v: float) -> void:
	studio.set_autopose_stiffness(region, v)
	_refresh_sheet()

func _refresh_sheet() -> void:
	if _handle == "": return
	_sheet_title.text = String(AP_NAMES.get(_handle, _handle))
	var pinned: bool = studio.autopose_pinned(_handle)
	var why: String = studio.autopose_lock_reason(_handle)
	_sheet_pin.text = "Pinned · tap to free" if pinned else "Pin"
	_sheet_pin.disabled = why != ""
	_tint(_sheet_pin, pinned and why == "", Ui.INK)
	if why.contains("Gameplay edit"): why = "the paddle at Contact is gameplay (where the ball is hit); change it in the desktop studio"
	_sheet_note.text = ("Locked: " + why) if why != "" else ("Holds still while you drag other parts. Tap Pinned to free it." if pinned
		else "Pin it to hold it still while you drag other parts. Feet start pinned.")
	for region in _region_btns:
		var now: float = float(studio.autopose_stiffness.get(region, 1.0))
		var bs: Array = _region_btns[region]
		for i in LEVELS.size(): _tint(bs[i], is_equal_approx(now, float(LEVELS[i][1])))

# ---------------------------------------------------------------- stars

func _build_star_popup() -> void:
	_star_popup = Control.new(); _star_popup.visible = false
	_star_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := Button.new(); dim.flat = true; dim.focus_mode = Control.FOCUS_NONE
	dim.add_theme_stylebox_override("normal", _panel(Color(0, 0, 0, 0.45))); dim.add_theme_stylebox_override("hover", _panel(Color(0, 0, 0, 0.45)))
	dim.add_theme_stylebox_override("pressed", _panel(Color(0, 0, 0, 0.45)))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); dim.pressed.connect(func(): _star_popup.visible = false)
	_star_popup.add_child(dim)
	var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", _sheet_box())
	card.anchor_left = 0.0; card.anchor_right = 1.0; card.anchor_top = 1.0; card.anchor_bottom = 1.0
	card.offset_top = -460
	_star_popup.add_child(card)
	_star_pad = MarginContainer.new(); card.add_child(_star_pad)
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 18); _star_pad.add_child(v)
	var t := _label("Rate this pose", TITLE); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 10)
	for i in 5:
		var b := Button.new(); b.flat = true; b.focus_mode = Control.FOCUS_NONE; b.text = "☆"
		b.custom_minimum_size = Vector2(112, 112); b.add_theme_font_size_override("font_size", 88)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(c, Ui.GOLD)
		b.pressed.connect(_rate.bind(i + 1))
		_big_stars.append(b); row.add_child(b)
	v.add_child(row)
	var legend := _label("5 ship it · 4 small nit · 3 acceptable · 2 clearly wrong · 1 broken", SMALL, Ui.MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(legend)
	var later := _btn("Not now", func(): _star_popup.visible = false, 0, 72); v.add_child(later)
	add_child(_star_popup)

func _sheet_box() -> StyleBoxFlat:
	var s := _panel(Ui.PANEL); s.corner_radius_top_left = 28; s.corner_radius_top_right = 28
	s.content_margin_left = 24; s.content_margin_right = 24; s.content_margin_top = 24; s.content_margin_bottom = 32
	return s

func _open_stars() -> void:
	var n: int = Queue.stars_for(studio.key)
	for i in 5: _big_stars[i].text = "★" if i < n else "☆"
	_star_popup.visible = true

func _rate(n: int) -> void:
	Queue.enqueue("rate", {"key": studio.key, "stars": n})
	_star_popup.visible = false
	_refresh_stars()
	if n < 5:
		_tab = "notes"; _refresh_tabs()
		_show_toast("%d stars · add a note on what is off" % n)
	else: _show_toast("5 stars · ship it")

func _refresh_stars() -> void:
	var n: int = Queue.stars_for(studio.key)
	for i in 5: _small_stars[i].text = "★" if i < n else "☆"
	_stars_label.text = ("%d of 5" % n) if n > 0 else "Tap to rate"

# ---------------------------------------------------------------- pose drawer (menu)

func _build_drawer() -> void:
	_drawer = Control.new(); _drawer.visible = false
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := Button.new(); dim.flat = true; dim.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]: dim.add_theme_stylebox_override(st, _panel(Color(0, 0, 0, 0.45)))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); dim.pressed.connect(_toggle_drawer)
	_drawer.add_child(dim)
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel", _panel(Ui.PANEL))
	panel.anchor_right = 0.84; panel.anchor_bottom = 1.0
	_drawer.add_child(panel)
	_drawer_pad = MarginContainer.new(); panel.add_child(_drawer_pad)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); _drawer_pad.add_child(v)
	var head := HBoxContainer.new(); head.custom_minimum_size.y = HEAD_H
	var t := _label("  Poses", TITLE); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t); head.add_child(_btn("✕", _toggle_drawer, TAP)); v.add_child(head)
	var sp := MarginContainer.new(); for side in ["left", "right", "bottom"]: sp.add_theme_constant_override("margin_" + side, GAP)
	_search = LineEdit.new(); _search.placeholder_text = "Search name or key"; _search.custom_minimum_size.y = 72
	_search.text_changed.connect(func(_t): _fill_drawer())
	sp.add_child(_search); v.add_child(sp)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_list = VBoxContainer.new(); _drawer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_drawer_list); v.add_child(scroll)
	var foot := MarginContainer.new(); for side in ["left", "right", "top", "bottom"]: foot.add_theme_constant_override("margin_" + side, GAP)
	var fr := HBoxContainer.new(); fr.add_theme_constant_override("separation", 8)
	var pend := _btn("", func(): pass, 0); pend.name = "Pending"; pend.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pend.disabled = true
	fr.add_child(pend); fr.add_child(_btn("Exit", _exit, 140)); foot.add_child(fr); v.add_child(foot)
	add_child(_drawer)

func _toggle_drawer() -> void:
	_drawer.visible = not _drawer.visible
	if _drawer.visible: _fill_drawer()

func _groups() -> Array:
	var g := {"Strokes": [], "Body stances": [], "Serves": [], "Ball actions": []}
	for d in PostureLibrary.instance().all_definitions(): g["Strokes"].append(d)
	for d in BasePoseLibrary.instance().all_definitions(): g["Body stances"].append(d)
	for d in PoseDiff.ServeStore.all_definitions(): g["Serves"].append(d)
	for d in PoseDiff.BallActions.all_definitions(): g["Ball actions"].append(d)
	return [["Strokes", g["Strokes"]], ["Body stances", g["Body stances"]], ["Serves", g["Serves"]], ["Ball actions", g["Ball actions"]]]

func _fill_drawer() -> void:
	for c in _drawer_list.get_children(): c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	var unsaved: Array = studio.unsaved_keys()
	for grp in _groups():
		var name_s: String = grp[0]
		var defs: Array = grp[1].duplicate()
		defs.sort_custom(func(a, b): return PoseDiff.key_of(a) < PoseDiff.key_of(b))
		var rows: Array = []
		for d in defs:
			var k := PoseDiff.key_of(d)
			var label := "%s  %s" % [k, String(d.display_name)]
			if q == "" or label.to_lower().contains(q): rows.append([k, label])
		var open: bool = q != "" or bool(_drawer_open.get(name_s, false))
		var hb := _btn("%s   %d  %s" % [name_s.to_upper(), rows.size(), "▾" if open else "▸"], _toggle_group.bind(name_s), 0, 72)
		hb.alignment = HORIZONTAL_ALIGNMENT_LEFT; hb.add_theme_font_size_override("font_size", SMALL)
		_drawer_list.add_child(hb)
		if not open: continue
		for r in rows:
			var stars: int = Queue.stars_for(r[0])
			var badge := ("  ●" if r[0] in unsaved else "") + ("   " + "★".repeat(stars) if stars > 0 else "")
			var b := _btn(String(r[1]) + badge, _pick_pose.bind(r[0]), 0, TAP)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.clip_text = true
			if r[0] == studio.key: _tint(b, true, Ui.SURFACE_HOVER)
			_drawer_list.add_child(b)
	var pend = _drawer.find_child("Pending", true, false)
	if pend: pend.text = "%d waiting for the Mac sync" % Queue.pending().size()

func _toggle_group(n: String) -> void:
	_drawer_open[n] = not bool(_drawer_open.get(n, false))
	_fill_drawer()

func _pick_pose(k: String) -> void:
	_close_sheet()
	studio.select_pose(k)
	_drawer.visible = false

func _exit() -> void:
	_drawer.visible = false
	var game = get_tree().current_scene
	studio.queue_free()
	if game and game.has_method("_close_mobile_pose_editor"): game._close_mobile_pose_editor()

# ---------------------------------------------------------------- state

func _refresh_pose() -> void:
	if studio == null or studio.key == "": return
	var d: Resource = PoseDiff.live_def(studio.key)
	var groups := {"s": "Strokes", "b": "Body stances", "v": "Serves", "a": "Ball actions"}
	_title_sub.text = "%s · %s" % [groups.get(studio.key.substr(0, 1), ""), studio.key]
	_title.text = (String(d.display_name) if d else studio.key) + ("  ●" if studio.key in studio.unsaved_keys() else "")
	var names: Array = studio.stage_names()
	for i in 3:
		_keys[i].text = String(names[i]).substr(0, 1)
		_keys[i].disabled = not studio.engine._has_motion() and i != 1
		_tint(_keys[i], studio.stage == i, STAGE_COLORS[i])
	_refresh_stars(); _refresh_tabs(); _refresh_chips()
	if _handle != "": _refresh_sheet()
	if _swing.visible: _refresh_swing()

func _show_toast(t: String) -> void:
	if t == "": return
	_toast_text = t; _toast_time = 3.0
	if _toast: _toast.text = t; _toast.visible = true

func _process(delta: float) -> void:
	if studio == null or not studio.is_ready: return
	if studio.key != _last_key or studio.stage != _last_stage:
		_last_key = studio.key; _last_stage = studio.stage; _refresh_pose()
	var tl = studio._timeline
	if tl and _scrub:
		var st: Dictionary = tl.state()
		_sync_scrub = true
		if bool(st.get("active", false)): _scrub.set_value_no_signal(float(st.get("t", 0.0)))
		_scrub.set_marks(tl.scrubber.marks, tl.scrubber.duration)
		_scrub.marks_draggable = tl.scrubber.marks_draggable
		_scrub.queue_redraw()
		_sync_scrub = false
		var ic: Texture2D = StudioTheme.icon("pause" if bool(st.get("playing", false)) else "play")
		if _play.icon != ic: _play.icon = ic
	if _undo: _undo.disabled = (studio._undo as Array).is_empty()
	if _redo: _redo.disabled = (studio._redo as Array).is_empty()
	if _toast and _toast.visible:
		_toast_time -= delta
		if _toast_time <= 0.0: _toast.visible = false
