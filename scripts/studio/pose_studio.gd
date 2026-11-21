extends CanvasLayer
## Desktop Pose Studio (docs/POSE_STUDIO_SPEC.md section 4, stage 1): full-window desktop pose
## editor. The mobile pose editor (scripts/ui/mobile_pose_editor.gd) is the ENGINE: the studio
## opens it like pose_studio_link.gd, hides its phone UI, moves its 3D preview (gizmo, orbit,
## ghosts, arc, contact box) into the centre and drives its members. No pose maths here.
## Saves go through tools/pose_notes.py save (text edits to the .tres), never ResourceSaver
## and never the engine's _save_current (user:// overrides).
## Booted by perf_monitor.gd on user arg --pose-studio=<port> (with the TCP link).
## Data checks: ui_dump() / ui_action(); keyboard map: SHORTCUTS (also the '?' overlay).

signal pose_selected(key)
signal stage_changed(stage)
signal pose_edited(key)
signal pose_saved(key, version)
signal pose_reloaded(key)
## Phone mode: an AutoPose drag released without moving (a tap on the ring).
signal handle_tapped(id)
signal notice(text)   # a short message for the user (the phone shows a toast; the desktop its status line)

const Ui = preload("res://scripts/ui/game_ui_theme.gd")
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const SpeedRamp = preload("res://scripts/stroke_speed_ramp.gd")
const ReadyCurve = preload("res://scripts/ready_windup_curve.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const ViewSettings = preload("res://scripts/mobile_pose_view_settings.gd")
const PoseDiff = preload("res://scripts/studio/pose_diff_util.gd")
const ViewportInput = preload("res://scripts/studio/studio_viewport.gd")
const PaddleDims = preload("res://scripts/paddle_dimensions.gd")
const AutoPose = preload("res://scripts/studio/autopose_solver.gd")
const TimelineBar = preload("res://scripts/studio/studio_timeline.gd")
const Inspector = preload("res://scripts/studio/studio_inspector.gd")
const Theme_ = preload("res://scripts/studio/studio_theme.gd")
const GizmoAxes = preload("res://scripts/ui/mobile_pose_gizmo_axes.gd")
const POS := ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul"]   # engine POS (paddle head, metres)
const AIM_ITERS := 6          # tip aim: damped Gauss-Newton steps per mouse move (at most)
const AIM_BUDGET_USEC := 5000 # ... and no new step once a mouse move has used this much time
const AIM_TOL_PX := 1.0       # stop when the solved tip is this close to the mouse
const AIM_STEP_DEG := 20.0    # largest pitch / yaw change per step
const AIM_DAMP := 0.05        # Levenberg-Marquardt damping (fraction of each column's own weight)
const STAGES := ["windup", "contact", "finish"]
const PANEL_DIR := "res://scripts/studio/panels/"
const PANELS := [["Metrics", "metrics_panel.gd"], ["Notes", "notes_panel.gd"], ["Rating", "rating_panel.gd"],
	["Versions", "versions_panel.gd"], ["Queue", "queue_panel.gd"], ["Bench", "bench_panel.gd"]]
const PDF := "res://docs/PICKLEBALL_2.5D_PROPOSAL.pdf"
const UNDO_LIMIT := 200
const LAYOUT_CFG := "user://pose_studio_layout.cfg"
const WINDOW_MIN := Vector2i(1280, 760)   # points
const LEFT_MIN := 200.0
const LEFT_DEFAULT := 240.0
const RIGHT_MIN := 410.0
const CENTRE_MIN := 420.0
const TABS_MIN := 180.0
## Below the window minimum (a window the OS opened smaller, a small screen) the columns shrink
## to these instead of pushing the right side off the window; full sizes again from 1280 pt.
const COMPACT_W := 1000.0
const LEFT_COMPACT := 160.0
const RIGHT_COMPACT := 320.0
const CENTRE_COMPACT := 340.0
const TABS_COMPACT := 140.0
const COL_DOT := 0
const COL_KEY := 1
const COL_NAME := 2
const COL_SCORE := 3
const COL_STARS := 4
## Copy of GAMEPLAY in tools/pose_check.py (fields gameplay reads beyond the look); keep in sync.
const GAMEPLAY_FIELDS := ["paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset", "has_zone", "zone_x_min",
	"zone_x_max", "zone_y_min", "zone_y_max", "zone_forward_offset", "paddle_floor_clearance",
	"charge_duration", "ft_duration_strike", "ft_duration_sweep", "ft_duration_settle", "ft_duration_hold", "speed_strike_start", "speed_strike_end", "speed_strike_points"]
## Paddle face at Contact: the contact quality reads it, so the Gameplay edit lock covers it too.
const FACE_FIELDS := ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg", "paddle_in_hand_rotation_deg",
	"paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg",
	"paddle_pitch_sign_source", "paddle_yaw_sign_source", "paddle_roll_sign_source"]
const GAMEPLAY_TIP := "Gameplay edit: off = the studio changes the animation only. Contact paddle position and face, zones, floor clearance and timing are locked (they change how shots play). On (red) = those edits are allowed."
const AIM_LAMBDA := 0.5       # tip aim: proximity weight (px^2 per deg^2) to the previous move's angles: 1 px -> <= 1/(2 sqrt(lambda)) = 0.71 deg
const AIM_MOVE_DEG := 25.0    # tip aim: largest pitch / yaw change in one mouse move
const AIM_FINE_PX := 3.0      # tip aim: a mouse move this short (since the last aim) is fine control ...
const AIM_FINE_DEG := 0.9     # ... and turns the paddle at most this much per pixel moved
const AIM_HOLD_LAMBDA := 0.025 # tip aim: proximity weight when the mouse is held still (same point again): settle on the mouse
const AP_BUDGET_USEC := 6000   # AutoPose drag: no new solver iteration once a mouse move has used this much time
const ElbowSwivel = preload("res://scripts/elbow_swivel.gd")
const AP_MIN_MOBILITY := 1e-3  # m per scale unit: a handle no free animation field moves this much is not draggable here
const AP_USEC_KEEP := 4000     # per-move timings kept in last_autopose
## Keyboard and mouse map (shown on '?', returned by ui_dump). Text-entry fields keep their keys
## except Cmd+S and Esc.
const SHORTCUTS := [
	["Cmd+S", "save (message from the top bar)", "save"],
	["Cmd+Z / Shift+Cmd+Z", "undo / redo (one drag = one step)", "undo"],
	["Space", "play / pause", "play"],
	[", / .", "step one game tick back / forward", "step"],
	["Tab / Shift+Tab", "next / previous key (wind-up, contact, finish)", "stage_cycle"],
	["Alt+1 / Alt+2 / Alt+3", "wind-up / contact / finish key", "stage"],
	["1 / 3 / 7 (or numpad)", "front / side / back view; Ctrl = opposite side", "view"],
	["F", "frame the pose: orbit centre back to the hips, refit zoom; the view then follows pose switches until you zoom or pan", "frame"],
	["W / E", "gizmo move / rotate (toolbar shows the mode)", "gizmo"],
	["L", "loop playback", "loop"],
	["Up/Down (focused field)", "nudge one step; Shift = 0.1x", "nudge"],
	["Left-drag empty space / middle-drag", "orbit around the orbit centre (hips); Shift = pan", "orbit"],
	["Shift+middle-drag", "pan (moves the orbit centre)", "pan"],
	["Ctrl+middle-drag / wheel", "zoom", "zoom"],
	["Trackpad: two-finger scroll", "orbit; Shift = pan; pinch = zoom", "trackpad"],
	["Left-click joint dot", "select joint, show its gizmo and fields", "pick"],
	["Left-drag gizmo handle", "edit (one undo step)", "gizmo_drag"],
	["Paddle hand Move arrows", "move hand + paddle along forehand side / up / toward net", "hand_move"],
	["Hold Alt (Option) on the paddle hand", "Move shows the old grip slide along the handle", "hand_slide"],
	["Left-drag paddle tip (orange diamond)", "aim the paddle: grip stays, tip follows the mouse; Shift = move the paddle", "tip_aim"],
	["P (toolbar AutoPose)", "AutoPose mode on / off: handles replace the joint dots and gizmo", "autopose"],
	["AutoPose: left-drag a handle", "move it in the screen plane, the whole body follows (one undo step)", "autopose_drag"],
	["AutoPose: hold Shift while dragging", "mouse up / down = away from / toward the camera (depth)", "autopose_depth"],
	["AutoPose bar", "Balance · Look at ball · Stiffness (Regions; double-click = 1.0x) · Relax = settle by the checker rules (one undo step)", "autopose_balance"],
	["AutoPose: lock by a handle (or Alt+click)", "pin / unpin: a pinned handle holds while you drag others (feet by default)", "autopose_pin"],
	["AutoPose: drag an elbow", "wind-up / finish: forearm, hand, paddle go along; Contact: paddle stays", "autopose_elbow"],
	["Hold A/B on a field", "show the saved value while held", "compare"],
	["?", "this help", "help"],
	["Esc / right-click during a drag", "cancel the drag (back to the pose before it)", "cancel_drag"],
	["Esc", "close help, leave a text field", "escape"],
]

var engine = null               # mobile_pose_editor.gd node
var key := ""                   # "s13" / "b04"
var stage := 1
var selected_field := ""        # last edited field (read by the notes panel)
var is_ready := false
## Phone (iPhone) mode, set before the node enters the tree: the phone layout
## (scripts/studio/phone_studio_ui.gd) instead of the desktop window, on-device pose overrides
## stay applied, and Save queues the edit for the Mac (scripts/studio/phone_sync_queue.gd).
var phone := false
var phone_ui = null
var layout_override := Vector2i.ZERO   # link `window` emulate: lay out at this canvas size (tests, no real resize)
var link_driving := false        # set by the link around ui_action / key / mouse: no ratings, no Verify
var preview = null              # engine._preview (moved into the centre)
var metrics_panel = null

var _root: Control
var _workspace: OptionButton
var _pose_title: Label
var _message: LineEdit
var _save_btn: Button
var _revert_btn: Button
var _undo_btn: Button
var _redo_btn: Button
var _dirty_label: Label
var _link_label: Label
var _pose_list: Tree
var _pose_filter: LineEdit
var _pose_count: Label
var _left: VBoxContainer
var _split: HSplitContainer
var _split2: HSplitContainer
var _vsplit: VSplitContainer
var _centre: VBoxContainer
var _layout := {"left": -1.0, "right": -1.0, "inspector": -1.0}
var _hint: PanelContainer
var _any_score := false
var _any_stars := false
var _views: HBoxContainer
var _view_input
var _second: TextureRect
var _vp2: SubViewport
var _cam2: Camera3D
var _second_angle: OptionButton
var _second_toggle: Button
var _ghost_toggle: Button
var _ghost_count: SpinBox
var _arc_toggle: Button
var _contact_toggle: Button
var _move_btn: Button
var _rotate_btn: Button
var _joint_label: Label
var _status: Label
var _timeline
var _inspector
var _tabs: TabContainer
var _help: PanelContainer
var _contact_on := false          # studio-only view state: overlays start off (never written to ViewSettings)
var _mode_note := ""             # hint when a joint lacks the chosen gizmo mode
var _note_joint := ""
var _wanted_mode := 0             # last W/E choice; restored on joints that have it
var _overlays_set := false       # overlays start off once; later the user's choice is kept
var _disk: Dictionary = {}       # key -> fresh normalized copy of the file on disk
var _undo: Array = []            # {key, stage, field, axis, old, new, label, before, after}
var _redo: Array = []
var _txn = null
var _compare = null
var _known := {}                 # {key, sig, snap}: last state the studio saw (external-edit detection)
var _needs_sync := false
var _needs_list := false         # top bar + pose list row (held back during a viewport drag)
var _badges: Dictionary = {}     # key -> {unsaved, score, stars, stale, version}
var _badge_clock := 0.0
var _link = null
var _poll_frames := 0
var gameplay_edit := false        # top bar "Gameplay edit": off = gameplay fields locked (see gameplay_locked)
var _gameplay_btn: Button
var _autopose = null              # AutoPose solver (autopose_solver.gd), made on first use
var autopose_on := false          # AutoPose mode (toolbar AutoPose, key P): handles replace the joint dots and gizmo
var last_autopose := {}           # last AutoPose UI drag: {handle, key, stage, moves, usec, last, result, release}
var _ap_toggle: Button
var autopose_balance := true      # AutoPose drags keep the centre of gravity (solver opts.balance; AutoPose bar Balance)
var _ap_balance: Button
var autopose_look := true         # AutoPose: the head looks at the ball / contact point after each solve (bar Look at ball)
var autopose_pins := {"right_foot": true, "left_foot": true}   # pinned AutoPose handles (lock icons); feet by default
var autopose_paddle_free := false # Contact paddle unpinned (only while Gameplay edit is on)
var autopose_stiffness := {"all": 1.0, "arms": 1.0, "torso": 1.0, "legs": 1.0}   # bar sliders (solver opts.stiffness)
var last_relax := {}              # last Relax: the solver's relax() report + release
var _ap_bar: HFlowContainer
var _ap_look: Button
var _ap_regions: Button
var _ap_region_seg: Control
var _ap_sliders := {}             # stiffness id -> [HSlider, value Label]
var _ap_pin_label: Label
var hand_slide := false          # Alt held: paddle-hand Move = the engine's grip slide along the handle
var last_aim := {}               # last tip-aim solve: {usec, iters, err_px, refresh_usec}
var _aim := {}                   # tip drag: {grip_local (paddle space), pin (world)}
var _aim_flush_queued := false
var _engine_hint := ""           # last engine gizmo hint seen (view hint follows it)
var _list_guard := false

func _ready() -> void:
	name = "PoseStudio"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pose_studio")
	if not phone:
		# Studio process only: closing the window asks about unsaved working copies first.
		get_tree().set_auto_accept_quit(false)
		Store.skip_overrides = true
		PoseDiff.BallActions.skip_overrides = true
		if PostureLibrary._singleton != null: PostureLibrary._singleton.load_or_default()
		if BasePoseLibrary._singleton != null: BasePoseLibrary._singleton.load_or_default()
		_apply_window_min()
		_apply_desktop_scale()
		get_tree().root.size_changed.connect(_apply_desktop_scale)
	_build_ui()
	if phone: _root.visible = false   # the desktop controls stay (the studio logic reads them), hidden
	else: _mount_panels()
	_setup.call_deferred()

## The project stretches a 720x1280 phone canvas; on the desktop the studio uses the window's
## own size instead (UI in screen points, scaled up a little on very tall windows), so text
## and rows keep desktop sizes from 1280x800 up to 4K. Studio runs only (its own process).
func _apply_desktop_scale() -> void:
	var win := get_tree().root
	if layout_override != Vector2i.ZERO:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		if win.content_scale_size != layout_override: win.content_scale_size = layout_override
		return
	var px: Vector2i = win.size
	if px.x < 2 or px.y < 2: return
	var ui: float = maxf(DisplayServer.screen_get_scale() if DisplayServer.get_name() != "headless" else 1.0, px.y / 1400.0)
	ui = maxf(ui, 1.0)
	var want := Vector2i(maxi(1, roundi(px.x / ui)), maxi(1, roundi(px.y / ui)))
	if win.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS: win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if win.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND: win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if win.content_scale_size != want: win.content_scale_size = want

## Studio window minimum: WINDOW_MIN points (pixels = points x screen scale), never more
## than the usable screen.
func _apply_window_min() -> void:
	if DisplayServer.get_name() == "headless": return
	var s := DisplayServer.screen_get_scale()
	var usable := DisplayServer.screen_get_usable_rect().size
	var px := Vector2i(roundi(WINDOW_MIN.x * s), roundi(WINDOW_MIN.y * s))
	if usable.x > 0 and usable.y > 0: px = Vector2i(mini(px.x, usable.x), mini(px.y, usable.y))
	get_tree().root.min_size = px

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _setup() -> void:
	var game: Node = null
	for i in 1200:
		await _frames(1)
		game = get_tree().current_scene
		if game and game.has_method("open_mobile_pose_editor") and game.get("player_left"): break
	if game == null or not game.has_method("open_mobile_pose_editor"):
		push_error("PoseStudio: game scene not found (launch res://scenes/game.tscn)"); return
	await _frames(30)
	game.open_mobile_pose_editor()   # no-op when the link already opened it
	await _frames(20)
	adopt(game.mobile_pose_editor)

## Take over an open mobile editor: hide its phone UI, move its preview into the centre.
func adopt(ed) -> void:
	if ed == null or not is_instance_valid(ed): push_error("PoseStudio: no mobile pose editor"); return
	engine = ed
	ed._root.visible = false
	preview = ed._preview
	if phone:
		var dropped: Array = load("res://scripts/studio/phone_sync_queue.gd").cleanup_overrides()
		if not dropped.is_empty(): print("[PoseStudio] phone: the build has the synced edits of %s; on-device copies dropped" % ", ".join(dropped))
		phone_ui = load("res://scripts/studio/phone_studio_ui.gd").new()
		add_child(phone_ui)
		phone_ui.build(self)
		phone_ui.mount_preview(preview)
	else:
		preview.reparent(_views, false)
		_views.move_child(preview, 0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_stretch_ratio = 1.0
	_view_input = ViewportInput.new()
	_view_input.attach(self, preview)
	preview.gizmo.dragged.connect(_on_gizmo_dragged)
	preview.gizmo.show_disabled = true   # handles stay on the joint while scrubbing / playing (dimmed)
	engine.studio_gizmo_override = _gizmo_override
	engine.studio_edit_guard = _edit_guard
	preview.joint_selected.connect(_on_joint_selected)
	get_viewport().size_changed.connect(_fix_preview_layout, CONNECT_DEFERRED)
	_fix_preview_layout()
	_build_view_hint()
	ed._gizmo_show.set_pressed_no_signal(true)   # not _toggle_gizmo: that writes user:// view settings
	if not phone: _setup_second_view()
	is_ready = true
	preview.set_momentum(true)   # the Trajectory arc is the swing the game plays (tick dots)
	select_pose("s00")
	if phone:
		_view_input.touch = true
		set_autopose_mode(true)
		phone_ui.studio_ready()
	_view_input.frame_pose()
	_set_status("Studio ready. Press ? for keys.")
	print("[PoseStudio] ready")

func _fix_preview_layout() -> void:
	# The engine's _layout re-applies phone sizes on resize; the studio only needs these.
	if preview == null: return
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(200, 160)

# ================================================================ UI
# Look and spacing: docs/POSE_STUDIO_SPEC.md 4.2 (numbers in studio_theme.gd).

func _btn(parent: Node, n: String, text: String, tip: String, cb: Callable = Callable(), toggle := false) -> Button:
	var b := Button.new(); b.name = n; b.text = text; b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE; b.toggle_mode = toggle
	if cb.is_valid():
		if toggle: b.toggled.connect(cb)
		else: b.pressed.connect(cb)
	parent.add_child(b); return b

## Flat tool / icon button (toolbar segments, top bar icons).
func _tool(parent: Node, n: String, text: String, icon_name: String, tip: String, cb: Callable = Callable(), toggle := false) -> Button:
	var b := Theme_.tool_button(n, text, icon_name, tip, toggle)
	if cb.is_valid():
		if toggle: b.toggled.connect(cb)
		else: b.pressed.connect(cb)
	parent.add_child(b); return b

func _label(parent: Node, n: String, text := "", muted := false) -> Label:
	var l := Label.new(); l.name = n; l.text = text
	if muted: l.theme_type_variation = &"SmallLabel"
	parent.add_child(l); return l

func _build_ui() -> void:
	_root = Control.new(); _root.name = "StudioRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme_.create(); _root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new(); bg.name = "Background"; bg.color = Theme_.APP_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var margin := MarginContainer.new(); margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, Theme_.SP2)
	_root.add_child(margin)
	var main := VBoxContainer.new(); main.name = "Main"; main.add_theme_constant_override("separation", Theme_.SP2)
	margin.add_child(main)
	_build_top_bar(main)
	_split = HSplitContainer.new(); _split.name = "Split"; _split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_split)
	_build_left(_split)
	_split2 = HSplitContainer.new(); _split2.name = "Split2"; _split2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.add_child(_split2)
	_build_centre(_split2)
	_build_right(_split2)
	for s in [_split, _split2, _vsplit]: s.drag_ended.connect(_save_layout)
	if not phone:   # phone: the desktop panes stay hidden, never laid out
		_load_layout()
		_root.resized.connect(_queue_layout)
	_build_help()

func _build_top_bar(main: Control) -> void:
	var bar := HBoxContainer.new(); bar.name = "TopBar"; bar.add_theme_constant_override("separation", Theme_.SP2)
	main.add_child(bar)
	var title := Theme_.header_label("StudioTitle", "Pose Studio")
	title.add_theme_color_override("font_color", Ui.MUTED)
	bar.add_child(title)
	_workspace = OptionButton.new(); _workspace.name = "Workspace"; _workspace.focus_mode = Control.FOCUS_NONE
	_workspace.add_item("Strokes"); _workspace.add_item("Body stances"); _workspace.add_item("Serves"); _workspace.add_item("Ball actions")
	_workspace.tooltip_text = "Pose type: strokes, body stances, serves (save to data/serve_tuning.json) or ball actions (pickup and throw between points, data/ball_actions)"
	_workspace.item_selected.connect(_on_workspace)
	bar.add_child(_workspace)
	_pose_title = Theme_.header_label("PoseTitle", "")
	_pose_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _pose_title.clip_text = true
	_pose_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pose_title.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_pose_title)
	_dirty_label = Theme_.small_label("DirtyMarker", "")
	_dirty_label.add_theme_color_override("font_color", Ui.RED)
	bar.add_child(_dirty_label)
	var hist := Theme_.segment(bar, "HistorySeg")
	_undo_btn = _tool(hist, "UndoButton", "", "undo", "Undo (Cmd+Z)", undo)
	_redo_btn = _tool(hist, "RedoButton", "", "redo", "Redo (Shift+Cmd+Z)", redo)
	_message = LineEdit.new(); _message.name = "SaveMessage"; _message.placeholder_text = "Save message"
	_message.custom_minimum_size.x = 170
	_message.tooltip_text = "Optional message for the version Save records"
	_message.text_submitted.connect(func(_t): _message.release_focus())
	bar.add_child(_message)
	_save_btn = _btn(bar, "SaveButton", "Save", "Write the edits to the pose file and record a version (Cmd+S)", func(): commit_pending_text(); save(_message.text))
	_save_btn.theme_type_variation = &"PrimaryButton"
	_revert_btn = _btn(bar, "RevertButton", "Revert", "Drop unsaved edits of this pose (undoable)", revert)
	_gameplay_btn = _btn(bar, "GameplayEdit", "Gameplay edit", GAMEPLAY_TIP, set_gameplay_edit, true)
	var misc := Theme_.segment(bar, "MiscSeg")
	_tool(misc, "PdfButton", "PDF", "doc", "Open docs/PICKLEBALL_2.5D_PROPOSAL.pdf", _open_pdf)
	_tool(misc, "HelpButton", "", "help", "Keys and mouse (?)", toggle_help)
	var pill := PanelContainer.new(); pill.name = "LinkPill"; pill.theme_type_variation = &"Pill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(pill)
	_link_label = Theme_.small_label("LinkStatus", "link -")
	pill.add_child(_link_label)

func _build_left(split: Control) -> void:
	_left = VBoxContainer.new(); _left.name = "Left"; _left.custom_minimum_size.x = LEFT_MIN
	_left.add_theme_constant_override("separation", Theme_.SP2)
	split.add_child(_left)
	var head := HBoxContainer.new(); head.name = "LeftHead"; _left.add_child(head)
	var t := Theme_.header_label("PoseListTitle", "Poses")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(t)
	_pose_count = Theme_.small_label("PoseCount", ""); head.add_child(_pose_count)
	_pose_filter = LineEdit.new(); _pose_filter.name = "PoseFilter"; _pose_filter.placeholder_text = "Filter key or name"
	_pose_filter.right_icon = Theme_.icon("search"); _pose_filter.clear_button_enabled = true
	_pose_filter.tooltip_text = "Show poses whose key or name contains this text"
	_pose_filter.text_changed.connect(func(_t): _fill_list())
	_pose_filter.text_submitted.connect(func(_t): _pose_filter.release_focus())
	_left.add_child(_pose_filter)
	_pose_list = Tree.new(); _pose_list.name = "PoseList"; _pose_list.columns = 5
	_pose_list.hide_root = true; _pose_list.select_mode = Tree.SELECT_ROW
	_pose_list.column_titles_visible = false
	for c in 5: _pose_list.set_column_expand(c, c == COL_NAME)
	_pose_list.set_column_custom_minimum_width(COL_DOT, 16)
	_pose_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pose_list.focus_mode = Control.FOCUS_CLICK
	_pose_list.item_selected.connect(_on_list_selected)
	_pose_list.tooltip_text = "● unsaved · number = checker score (logs/pose_check/latest.json) · ★ stars on the current version; ~ = stale (rate again)"
	_left.add_child(_pose_list)

func _build_centre(split2: Control) -> void:
	var centre := VBoxContainer.new(); centre.name = "Centre"; centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", Theme_.SP2)
	centre.custom_minimum_size.x = CENTRE_MIN
	split2.add_child(centre)
	_centre = centre
	var tools := HFlowContainer.new(); tools.name = "ViewToolbar"
	tools.add_theme_constant_override("h_separation", Theme_.SP2); tools.add_theme_constant_override("v_separation", Theme_.SP1)
	centre.add_child(tools)
	var views := Theme_.segment(tools, "ViewSeg")
	_tool(views, "ViewFront", "Front", "", "Front view (1)", view.bind("front"))
	_tool(views, "ViewSide", "Side", "", "Side view (3)", view.bind("side"))
	_tool(views, "ViewBack", "Back", "", "Back view (7)", view.bind("back"))
	_tool(views, "FrameButton", "", "frame", "Frame the pose: clear pan and zoom; the view follows pose switches again until you zoom or pan (F)", frame_pose)
	var giz := Theme_.segment(tools, "GizmoSeg")
	_move_btn = _tool(giz, "GizmoMove", "", "move", "Gizmo move (W)", set_gizmo_mode.bind(0).unbind(1), true)
	_rotate_btn = _tool(giz, "GizmoRotate", "", "rotate", "Gizmo rotate (E)", set_gizmo_mode.bind(1).unbind(1), true)
	var aps := Theme_.segment(tools, "AutoPoseSeg")
	_ap_toggle = _tool(aps, "AutoPoseToggle", "AutoPose", "", "AutoPose (P): drag a hand, elbow, knee, foot, hips, chest, head or the paddle tip and the whole body follows; shoulder and hip rings turn the upper body / hips, paddle edge diamonds roll the face (animation only; Shift = depth, Esc / right-click cancels). Its options show in the bar below.", func(on): set_autopose_mode(on), true)
	var over := Theme_.segment(tools, "OverlaySeg")
	_ghost_toggle = _tool(over, "GhostsToggle", "", "ghosts", "Show in-between ghosts", func(on): set_overlay("ghosts", on), true)
	_ghost_count = SpinBox.new(); _ghost_count.name = "GhostCount"; _ghost_count.min_value = 0
	_ghost_count.max_value = ViewSettings.MAX_INBETWEEN_COUNT; _ghost_count.step = 1
	_ghost_count.custom_minimum_size.x = 56
	_ghost_count.tooltip_text = "Ghosts per gap (wind-up -> contact, contact -> finish)"
	_ghost_count.value_changed.connect(func(v): set_ghost_count(int(v)))
	over.add_child(_ghost_count)
	_arc_toggle = _tool(over, "ArcToggle", "", "arc", "Show the paddle motion arc", func(on): set_overlay("arc", on), true)
	_contact_toggle = _tool(over, "ContactToggle", "", "contact", "Show the contact box", func(on): set_overlay("contact", on), true)
	var two := Theme_.segment(tools, "SecondSeg")
	_second_toggle = _tool(two, "SecondViewToggle", "", "split", "Two views: a second camera on the same preview, side by side", func(on): set_second_view(on), true)
	_second_angle = OptionButton.new(); _second_angle.name = "SecondViewAngle"; _second_angle.focus_mode = Control.FOCUS_NONE
	_second_angle.theme_type_variation = &"ToolButton"
	for a in ["Side", "Front", "Back", "Top"]: _second_angle.add_item(a)
	_second_angle.tooltip_text = "Second view angle"
	two.add_child(_second_angle)
	_build_autopose_bar(centre)
	var frame := PanelContainer.new(); frame.name = "ViewFrame"; frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var fs := StyleBoxFlat.new(); fs.bg_color = Color("08141c"); fs.border_color = Color("1f3a4a"); fs.set_border_width_all(1)
	fs.set_corner_radius_all(4); fs.set_content_margin_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	centre.add_child(frame)
	_views = HBoxContainer.new(); _views.name = "Views"; _views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_views.add_theme_constant_override("separation", 2)
	frame.add_child(_views)
	_second = TextureRect.new(); _second.name = "SecondView"; _second.visible = false
	_second.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _second.stretch_mode = TextureRect.STRETCH_SCALE
	_second.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _second.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_second.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_views.add_child(_second)
	_status = Theme_.small_label("StatusLine", "Starting…")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	centre.add_child(_status)
	_timeline = TimelineBar.new(); centre.add_child(_timeline); _timeline.build(self)

## AutoPose options (shown in AutoPose mode, under the view toolbar): soft balance, head look-at,
## stiffness (all + Arms / Torso / Legs), pins, Relax. docs/POSE_STUDIO_SPEC.md Stage 6b.
func _build_autopose_bar(centre: Control) -> void:
	_ap_bar = HFlowContainer.new(); _ap_bar.name = "AutoPoseBar"; _ap_bar.visible = false
	_ap_bar.add_theme_constant_override("h_separation", Theme_.SP2); _ap_bar.add_theme_constant_override("v_separation", Theme_.SP1)
	centre.add_child(_ap_bar)
	var opt := Theme_.segment(_ap_bar, "ApOptionSeg")
	_ap_balance = _tool(opt, "AutoPoseBalance", "Balance", "", "Soft balance (on): drags keep the centre of gravity over the feet (never further off than max(5 cm, where it started)); Relax pulls it to 9 cm. Off: handles reach further, balance may get worse.", set_autopose_balance, true)
	_ap_balance.set_pressed_no_signal(autopose_balance)
	_ap_look = _tool(opt, "AutoPoseLook", "Look at ball", "", "Head looks at the ball (on): after each drag or Relax the head turns to the preview ball at this key (incoming at wind-up, the contact point at contact, outgoing at finish; head turn / tilt fields only). Body stances have no ball.", set_autopose_look, true)
	_ap_look.set_pressed_no_signal(autopose_look)
	var st := Theme_.segment(_ap_bar, "ApStiffSeg")
	_ap_slider(st, "all", "Stiffness", "How much the body resists a drag (all regions). Left = everything follows more, right = stiffer. 1.0x = tuned default.")
	_ap_regions = _tool(st, "ApRegionsToggle", "Regions", "", "Per-region stiffness: arms, torso (chest, head), legs (hips, knees, feet)", set_autopose_regions_shown, true)
	var rs := Theme_.segment(_ap_bar, "ApRegionSeg")
	_ap_region_seg = rs.get_parent(); _ap_region_seg.visible = false
	for g in [["arms", "Arms", "Arms and paddle: lower = the arm takes more of a drag"], ["torso", "Torso", "Chest and head: lower = the chest turns and leans more"],
			["legs", "Legs", "Hips, knees and feet: lower = the hips shift and the knees bend more"]]:
		_ap_slider(rs, g[0], g[1], g[2])
	var pins := Theme_.segment(_ap_bar, "ApPinSeg")
	_ap_pin_label = Theme_.small_label("ApPinCount", "Pins: 2"); _ap_pin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ap_pin_label.custom_minimum_size.x = 52
	_ap_pin_label.tooltip_text = "Click the lock next to a handle (or Alt+click the handle) to pin it: a pinned handle holds its place while you drag others."
	_ap_pin_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pins.add_child(_ap_pin_label)
	_tool(pins, "ApResetPins", "Reset pins", "", "Pins back to the default: both feet (and the paddle at Contact)", reset_autopose_pins)
	var rx := Theme_.segment(_ap_bar, "ApRelaxSeg")
	_tool(rx, "AutoPoseRelax", "Relax", "", "Relax this key: nudge the body toward a natural pose by the pose checker's rules (balance, knee bend, no locked arm, wrist, lean, no pop-up) with pins and gameplay fields held. One undo step.", func(): autopose_relax())

func _ap_slider(parent: Control, id: String, text: String, tip: String) -> void:
	var l := Theme_.small_label("ApStiffLabel_" + id, text); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.tooltip_text = tip; l.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(l)
	var s := HSlider.new(); s.name = "ApStiff_" + id
	s.min_value = 0.25; s.max_value = 4.0; s.exp_edit = true; s.step = 0.01; s.value = float(autopose_stiffness.get(id, 1.0))
	s.custom_minimum_size = Vector2(84, Theme_.TARGET); s.scrollable = false; s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = tip + " (double-click: back to 1.0x)"
	s.value_changed.connect(func(v): set_autopose_stiffness(id, v))
	s.gui_input.connect(func(e): if e is InputEventMouseButton and e.double_click and e.button_index == MOUSE_BUTTON_LEFT: s.value = 1.0; s.accept_event())
	parent.add_child(s)
	var v := Theme_.small_label("ApStiffValue_" + id, "1.0x"); v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.custom_minimum_size.x = 34
	parent.add_child(v)
	_ap_sliders[id] = [s, v]
	set_autopose_stiffness(id, s.value)

func _build_right(split2: Control) -> void:
	_vsplit = VSplitContainer.new(); _vsplit.name = "Right"; _vsplit.custom_minimum_size.x = RIGHT_MIN
	_vsplit.size_flags_horizontal = Control.SIZE_FILL
	split2.add_child(_vsplit)
	_inspector = Inspector.new(); _inspector.size_flags_vertical = Control.SIZE_FILL
	_vsplit.add_child(_inspector); _inspector.build(self)
	_inspector.content_changed.connect(_queue_layout)
	_tabs = TabContainer.new(); _tabs.name = "Panels"; _tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = TABS_MIN
	_vsplit.add_child(_tabs)

## Status pill inside the viewport's bottom-left corner: the selected joint and gizmo hint.
## Sized to its text (wraps when the viewport is narrow); ignores the mouse.
func _build_view_hint() -> void:
	_hint = PanelContainer.new(); _hint.name = "ViewHint"; _hint.theme_type_variation = &"OverlayPill"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joint_label = Theme_.small_label("JointLabel", "")
	_joint_label.add_theme_color_override("font_color", Ui.INK)
	_joint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(_joint_label)
	preview.add_child(_hint)
	preview.resized.connect(_layout_hint)
	if phone: _hint.visible = false   # desktop keys / mouse hints; the phone layout has its own

func _set_hint(t: String) -> void:
	if _joint_label == null or _joint_label.text == t: return
	_joint_label.text = t
	_layout_hint()

func _layout_hint() -> void:
	if _hint == null or preview == null: return
	var pad := Theme_.SP4
	var sb := _hint.get_theme_stylebox("panel")
	var inner := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb else 20.0
	var maxw := maxf(60.0, preview.size.x - pad * 2.0)
	var font := _joint_label.get_theme_font("font")
	var tw := font.get_string_size(_joint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _joint_label.get_theme_font_size("font_size")).x
	var wrap := tw + inner > maxw
	_joint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	_joint_label.custom_minimum_size.x = (maxw - inner) if wrap else 0.0
	_hint.visible = _joint_label.text != "" and not phone
	_hint.reset_size()
	(func() -> void:
		if _hint == null or preview == null: return
		_hint.reset_size()
		_hint.position = Vector2(pad, preview.size.y - _hint.size.y - pad)).call_deferred()

func _build_help() -> void:
	_help = PanelContainer.new(); _help.name = "HelpOverlay"; _help.visible = false
	var st := Ui.panel_style(); st.content_margin_left = 18; st.content_margin_right = 18
	_help.add_theme_stylebox_override("panel", st)
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH; _help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_help)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", Theme_.SP2); _help.add_child(v)
	var t := Theme_.header_label("HelpTitle", "Keys and mouse  (? or Esc closes)")
	v.add_child(t)
	var grid := GridContainer.new(); grid.name = "HelpGrid"; grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", Theme_.SP1)
	v.add_child(grid)
	for s in SHORTCUTS:
		var k := Label.new(); k.text = s[0]; k.add_theme_color_override("font_color", Ui.BLUE); grid.add_child(k)
		var d := Label.new(); d.text = s[1]; grid.add_child(d)

func _mount_panels() -> void:
	for p in PANELS:
		var path: String = PANEL_DIR + p[1]
		if not ResourceLoader.exists(path): continue
		var s = load(path)
		if s == null or not (s is Script) or not s.can_instantiate(): continue
		var panel = s.new()
		if panel is Control: add_panel(p[0], panel)
		if p[1] == "metrics_panel.gd": metrics_panel = panel

## Right-side tab container (panels bind to the studio here).
## Each panel sits in a ScrollContainer so a tall panel never pushes the window layout.
func add_panel(title: String, panel: Control) -> void:
	var sc := ScrollContainer.new(); sc.name = "Tab_" + title.replace(" ", "")
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(panel)
	_tabs.add_child(sc)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)
	if panel.has_method("bind") and panel.get("studio") == null: panel.bind(self)

func _setup_second_view() -> void:
	_vp2 = SubViewport.new(); _vp2.name = "SecondViewport"
	_vp2.world_3d = preview.viewport.find_world_3d()
	_vp2.size = Vector2i(320, 240); _vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_second.add_child(_vp2)
	_cam2 = Camera3D.new(); _cam2.fov = 40; _vp2.add_child(_cam2); _cam2.current = true
	_second.texture = _vp2.get_texture()

# ---------------------------------------------------------------- split layout (remembered)

## Sizes the user dragged (points; -1 = default). Defaults: pose list fits its longest row
## (>= ~240), inspector ~22 % of the width (>= RIGHT_MIN), inspector fields as tall as their
## content up to the remembered height (so no gap above the tabs).
func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_CFG) == OK:
		for k in _layout: _layout[k] = float(cfg.get_value("split", k, -1.0))

func _save_layout() -> void:
	_layout.left = _left.size.x
	_layout.right = _vsplit.size.x
	_layout.inspector = _inspector.size.y
	var cfg := ConfigFile.new()
	for k in _layout: cfg.set_value("split", k, _layout[k])
	cfg.save(LAYOUT_CFG)
	_queue_layout()

var _layout_queued := false
var _layout_after_drag := false
func _queue_layout() -> void:
	if phone or _layout_queued: return   # phone: the desktop panes are hidden, never laid out
	_layout_queued = true
	_apply_layout.call_deferred()

## Move each split so its fixed child gets the wanted size (works for any split_offset
## convention: measure, correct, re-check next frame until within 1 pt; at most 3 passes).
func _apply_layout(pass_n := 0) -> void:
	_layout_queued = false
	if _root == null or _split == null: return
	if _view_input and _view_input.drag in [_view_input.Drag.GIZMO, _view_input.Drag.TIP]:
		_layout_after_drag = true   # a column move resizes the preview and would cancel the drag
		return
	var w := _root.size.x
	var full := clampf((w - COMPACT_W) / (float(WINDOW_MIN.x) - COMPACT_W), 0.0, 1.0)   # 0 at <= 1000 pt, 1 at >= 1280 pt
	var left_min := lerpf(LEFT_COMPACT, LEFT_MIN, full)
	var right_min := lerpf(RIGHT_COMPACT, RIGHT_MIN, full)
	var tabs_min := lerpf(TABS_COMPACT, TABS_MIN, clampf((_root.size.y - 628.0) / (float(WINDOW_MIN.y) - 628.0), 0.0, 1.0))
	_left.custom_minimum_size.x = left_min
	_vsplit.custom_minimum_size.x = right_min
	_centre.custom_minimum_size.x = lerpf(CENTRE_COMPACT, CENTRE_MIN, full)
	_tabs.custom_minimum_size.y = tabs_min
	var want_left: float = _layout.left if _layout.left > 0 else maxf(lerpf(LEFT_COMPACT + 10.0, LEFT_DEFAULT, full), w * 0.125)
	var want_right: float = _layout.right if _layout.right > 0 else clampf(w * 0.22, right_min, 520.0)
	# A remembered size from a bigger window never pushes the columns past the window.
	var room := w - Theme_.SP2 * 2.0 - 24.0 - _centre.custom_minimum_size.x
	want_right = clampf(want_right, right_min, maxf(right_min, room - left_min))
	want_left = clampf(want_left, left_min, maxf(left_min, room - want_right))
	var rh := _vsplit.size.y
	var pref: float = _layout.inspector if _layout.inspector > 0 else rh * 0.55
	var want_insp: float = clampf(minf(pref, _inspector.content_height()), 140.0, maxf(140.0, rh - tabs_min - Theme_.SP2))
	var moved := _fit(_split, _left, want_left, true, false)
	moved = _fit(_split2, _vsplit, want_right, false, false) or moved
	moved = _fit(_vsplit, _inspector, want_insp, true, true) or moved
	if moved and pass_n < 3:
		await get_tree().process_frame
		_apply_layout(pass_n + 1)

func _fit(s: SplitContainer, child: Control, want: float, first: bool, vertical: bool) -> bool:
	var have := child.size.y if vertical else child.size.x
	var d := roundi(want - have)
	if absi(d) <= 1: return false
	var before := s.split_offset
	s.split_offset += d if first else -d
	s.clamp_split_offset()
	return s.split_offset != before

# ================================================================ engine helpers

func _ok() -> bool: return engine != null and is_instance_valid(engine)

## What the working copy is compared with (unsaved dot, Save's diff): the pose file on disk; on
## the phone, the pose as last saved on the device (the packaged file plus its on-device
## override), so each queued save carries only the edits since the previous one.
func _baseline(k: String) -> Resource:
	if not phone: return PoseDiff.load_disk(k)
	var live: Resource = PoseDiff.live_def(k)
	if live == null: return null
	var r: Resource = live.duplicate(true)
	if not (r is BasePoseDefinition): PoseDiff.PaddleRotation.normalize_pose(r)
	return r

func _copy_key(k: String) -> String: return PoseDiff.copy_key(k)

func _key_from_copy(ck: String) -> String:
	if ck.begins_with("stroke:"): return "s%02d" % int(ck.substr(7))
	if ck.begins_with("base:"): return "b%02d" % int(ck.substr(5))
	if ck.begins_with("serve:"): return "v%02d" % int(ck.substr(6))
	if ck.begins_with("action:"): return "a%02d" % int(ck.substr(7))
	return ""

func _index_of(k: String) -> int:
	for i in engine._definitions.size():
		if PoseDiff.key_of(engine._definitions[i]) == k: return i
	return -1

func _reselect(st: int) -> void:
	var idx := _index_of(key)
	if idx < 0: return
	engine._select_pose(idx)
	if st != 1 and engine._has_motion(): engine._select_stage(st)
	stage = engine._stage

func _is_timing(field: String) -> bool:
	for d in Fields.fields(5, engine._base):
		if d.field == field: return true
	return false

func _descriptor(field: String) -> Dictionary:
	for g in 6:
		for d in Fields.fields(g, engine._base):
			if d.field == field: return d
	return {}

## Value of a field at a stage (endpoints resolve keyframe dict + charge/ft deltas).
func _at(def: Resource, st: int, field: String, cache: Dictionary):
	if def == null: return null
	if def is BasePoseDefinition or st == 1 or _is_timing(field): return def.get(field)
	if not cache.has(st): cache[st] = Path.endpoint(def, st)
	return cache[st].get(field)

func _value_of(field: String, axis: int):
	var target: Resource = engine._current if _is_timing(field) else engine._edit
	var v = target.get(field)
	return v[axis] if axis >= 0 and v is Vector3 else v

## Signature of a working copy (all stored values incl. keyframe dicts), for change checks.
func _sig(r: Resource) -> String:
	if r == null: return ""
	var parts := PackedStringArray()
	for n in PoseDiff.storage_props(r):
		var v = r.get(n)
		if v is Resource: parts.append(n + "=" + (var_to_str(v.get("values")) if v.get("values") != null else "res"))
		else: parts.append(n + "=" + var_to_str(v))
	return "|".join(parts)

func _remember() -> void:
	if not _ok() or key == "": _known = {}; return
	_known = {"key": key, "sig": _sig(engine._current), "snap": engine._current.duplicate(true)}

## Field data for the inspector: field -> {value, keys: [w, c, f], saved}.
func field_values(fields: Array) -> Dictionary:
	var out := {}
	if not _ok() or key == "": return out
	var cur: Resource = engine._current
	var disk: Resource = _disk.get(key)
	var motion: bool = engine._has_motion()
	var wc := {}
	var dc := {}
	for field in fields:
		var timing := _is_timing(field)
		var target: Resource = cur if timing else engine._edit
		if target == null or target.get(field) == null: continue
		var keys: Array = []
		for st in 3: keys.append(_at(cur, st, field, wc) if (motion or st == 1) else null)
		out[field] = {"value": target.get(field), "keys": keys, "saved": _at(disk, engine._stage, field, dc)}
	return out

# ================================================================ public API

func select_pose(k: String) -> bool:
	if not _ok(): return false
	stop_drag()
	if _txn != null: end_edit()
	if _compare != null: compare_end()
	var live := PoseDiff.live_def(k)
	if live == null: _set_status("Unknown pose " + k); return false
	var ws := _workspace_of(k)
	if engine._serve != (ws == 2) or engine._base != (ws == 1) or engine._action != (ws == 3): engine._select_workspace(ws)
	engine._group.select(6)
	key = k
	var idx := _index_of(k)
	if idx < 0: return false
	engine._select_pose(idx)
	stage = engine._stage
	if not _disk.has(k) or _disk[k] == null: _disk[k] = _baseline(k)
	_workspace.select(ws)
	_pose_title.text = "%s  %s" % [k, String(live.display_name)]
	_pose_title.tooltip_text = PoseDiff.file_of(k)
	_remember()
	_fill_list()
	_inspector.rebuild()
	_reset_view_state()
	_after_change(false)
	pose_selected.emit(k)
	stage_changed.emit(stage)
	return true

## Studio defaults on open and on every pose switch (studio state only, nothing saved): arc,
## ghosts and contact box off, hips selected with its gizmo in Move mode (or the mode it has),
## orbit centre on the hips (zoom kept).
func _reset_view_state() -> void:
	if preview == null: return
	if not _overlays_set:
		_overlays_set = true
		set_overlay("arc", phone)   # phone: the momentum arc (Trajectory) starts on
		set_overlay("ghosts", false)
		set_ghost_count(0)
		set_overlay("contact", false)
	engine._gizmo_show.set_pressed_no_signal(true)
	engine._gizmo_mode.select(_wanted_mode)   # not _select_gizmo_mode: that writes user:// view settings
	_note_joint = ""
	select_joint("hips")
	if autopose_on: _apply_autopose_view()
	if _view_input:
		if _view_input.auto_fit: _view_input.follow_pose(false)
		else:
			preview.camera_target = _view_input.pose_centre()
			preview.update_camera()

func set_stage(i: int) -> void:
	if not _ok() or key == "": return
	stop_drag()
	if _compare != null: compare_end()
	engine._select_stage(clampi(i, 0, 2))
	stage = engine._stage
	if _view_input: _view_input.follow_pose(true)
	_inspector.sync(); _timeline.refresh()
	stage_changed.emit(stage)

## Same path as the link 'set' (engine _changed with the foot-plant check). One undo step
## unless inside begin_edit / end_edit. Returns {ok, value, clamped, stopped}.
## `force` (the link's set: Claude follows the gameplay rule itself) skips the Gameplay edit lock.
## `refresh` false: the engine applies the value without refreshing the preview (a batch writer
## such as the AutoPose commit refreshes itself before the next foot-plant check and at the end).
func set_field(field: String, axis, value, force := false, refresh := true) -> Dictionary:
	if not _ok() or key == "": return {"ok": false, "error": "no pose selected"}
	var d := _descriptor(field)
	if d.is_empty(): return {"ok": false, "error": "unknown field: " + field}
	if not force and gameplay_locked(field):
		_set_status("Locked: the Grab hand is where the ball is (the game puts it there). Edit Reach or Rise instead." if engine.get("_action") \
			else "Locked: %s is a gameplay field here. Turn on Gameplay edit (top bar) to change it." % field)
		_needs_sync = true
		return {"ok": false, "error": "gameplay field locked: " + field, "locked": true}
	var timing := _is_timing(field)
	var target: Resource = engine._current if timing else engine._edit
	if target.get(field) == null: return {"ok": false, "error": "field not on this pose: " + field}
	var ax: int = -1 if axis == null else int(axis)
	if d.type == "vector" and (ax < 0 or ax > 2): return {"ok": false, "error": "vector field needs axis 0..2"}
	if d.type != "vector": ax = -1
	var clamped := false
	var v
	var current
	if d.type == "option":
		var n := clampi(int(value), 0, d.items.size() - 1)
		clamped = float(n) != float(value)
		v = n; current = int(target.get(field))
	else:
		if not (value is float or value is int): return {"ok": false, "error": "value must be a number"}
		var fv: float = Fields.body_input_value(d, float(value))
		if not is_finite(fv): return {"ok": false, "error": "value must be finite"}
		clamped = not is_equal_approx(fv, float(value))
		v = fv
		current = float(target.get(field)) if ax < 0 else float(target.get(field)[ax])
	selected_field = field
	if is_equal_approx(float(v), float(current)):
		return {"ok": true, "value": current, "clamped": clamped, "stopped": null}
	if field in engine.FOOT_GUARDED_FIELDS:
		var reason: String = engine._body_edit_limit(d, ax, float(v))
		if reason != "":
			_set_status("Foot-plant check stopped %s at %.3f (asked %.3f): %s" % [field, float(current), float(v), reason])
			_needs_sync = true
			return {"ok": true, "value": current, "clamped": clamped, "stopped": {"reason": reason, "at": current}}
	var own := _txn == null
	if own: begin_edit("set " + field)
	if _txn.field == "": _txn.field = field; _txn.axis = ax; _txn.old = current
	elif _txn.field != field or _txn.axis != ax: _txn["fields"] = int(_txn.get("fields", 1)) + 1
	var prev_group: int = engine._group.selected
	engine._group.select(5 if timing else 6)
	if ax < 0: engine._changed(field, v, refresh)
	else:
		var vec: Vector3 = target.get(field); vec[ax] = v; engine._changed(field, vec, refresh)
	engine._group.select(prev_group)
	var now = target.get(field)
	var applied = now if ax < 0 else now[ax]
	if not _txn.has("fields"): _txn.new = applied
	if own: end_edit()
	else: _after_change(true)
	return {"ok": true, "value": applied, "clamped": clamped, "stopped": null}

## Start one undo step (slider drag, gizmo drag). Nested calls are ignored.
func begin_edit(label: String = "edit") -> void:
	if not _ok() or key == "" or _txn != null: return
	if _compare != null: compare_end()
	_txn = {"label": label, "key": key, "stage": stage, "field": "", "axis": -1, "old": null, "new": null,
		"before": engine._current.duplicate(true), "before_sig": _sig(engine._current)}

func end_edit() -> void:
	if _txn == null: return
	var t: Dictionary = _txn
	_txn = null
	if not _ok(): return
	var sig := _sig(engine._current)
	if sig == t.before_sig: _after_change(false); return
	t.erase("before_sig")
	if t.field != "" and t.old == null:   # gizmo drags: values from the snapshots
		var o = _at(t.before, t.stage, t.field, {})
		var nv = _value_of(t.field, -1)
		t.old = o[t.axis] if t.axis >= 0 and o is Vector3 else o
		t.new = nv[t.axis] if t.axis >= 0 and nv is Vector3 else nv
	t["after"] = engine._current.duplicate(true)
	_undo.append(t)
	if _undo.size() > UNDO_LIMIT: _undo.pop_front()
	_redo.clear()
	_known = {"key": key, "sig": sig, "snap": t.after}
	_after_change(true)

func cancel_edit() -> void:
	_txn = null

## Abandon the open step (Esc during a gizmo drag, focus loss): restore the pose from
## before it; nothing goes on the undo stack.
func abort_edit() -> void:
	if _txn == null: return
	var t: Dictionary = _txn
	_txn = null
	if not _ok() or t.key != key: return
	if t.before_sig == _sig(engine._current): return
	engine._copies[_copy_key(key)] = t.before.duplicate(true)
	_reselect(t.stage)
	_update_dirty_flag()
	_remember()
	_after_change(true)

func undo() -> bool:
	if _editing_drag(): _set_status("Finish the drag first (release, or Esc to cancel), then undo"); return false
	if _txn != null: end_edit()
	if _undo.is_empty(): return false
	var e: Dictionary = _undo.pop_back()
	_redo.append(e)
	_restore(e.key, e.before, e.stage)
	_set_status("Undo: %s" % _describe(e))
	return true

func redo() -> bool:
	if _editing_drag(): _set_status("Finish the drag first (release, or Esc to cancel), then redo"); return false
	if _redo.is_empty(): return false
	var e: Dictionary = _redo.pop_back()
	_undo.append(e)
	_restore(e.key, e.after, e.stage)
	_set_status("Redo: %s" % _describe(e))
	return true

func _describe(e: Dictionary) -> String:
	if e.field == "": return e.label
	if e.has("fields"): return "%s (%d fields)" % [e.label, int(e.fields)]
	return "%s%s %s -> %s" % [e.field, "" if e.axis < 0 else "[%d]" % e.axis, str(e.old), str(e.new)]

func _restore(k: String, snap: Resource, st: int) -> void:
	if k != key: select_pose(k)
	engine._copies[_copy_key(k)] = snap.duplicate(true)
	_reselect(st)
	_update_dirty_flag()
	_remember()
	_after_change(true)

func _update_dirty_flag() -> void:
	var ck := _copy_key(key)
	if diff().is_empty(): engine._dirty.erase(ck)
	else: engine._dirty[ck] = true

## Field rows that differ from the file: [{stage, field, text}] (pose_diff_util).
func diff() -> Array:
	if not _ok() or key == "": return []
	# Serves: always a fresh build (code + tuning file); a cached one can share key data with the copy.
	if PoseDiff.is_serve_key(key): return PoseDiff.diff(engine._current, _baseline(key), false)
	if _disk.get(key) == null: _disk[key] = _baseline(key)
	return PoseDiff.diff(engine._current, _disk[key], engine._base)

## author: "user" (studio UI) or "claude" (link 'save').
func save(message: String = "", author: String = "user") -> Dictionary:
	if not (author in ["user", "claude"]): return {"ok": false, "error": "bad author: " + author}
	if not _ok() or key == "": return {"ok": false, "error": "no pose selected"}
	if _txn != null: end_edit()
	if _compare != null: compare_end()
	var changes := diff()
	if changes.is_empty():
		_set_status("Nothing to save for " + key)
		return {"ok": true, "key": key, "changed": 0, "message": "no changes"}
	var msg := message.strip_edges()
	if msg == "": msg = "studio edit: " + ", ".join(changes.map(func(c): return c.field))
	if phone: return _save_on_phone(changes, msg)
	var path := ProjectSettings.globalize_path("user://pose_studio_changes_%s.json" % key)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return {"ok": false, "error": "cannot write " + path}
	f.store_string(JSON.stringify({"key": key, "changes": changes})); f.close()
	var r := run_cli(PackedStringArray(["apply", "--style", str(int(key.substr(1))), "--changes", path]), "res://tools/pose_studio/serve_tuning.py") \
		if PoseDiff.is_serve_key(key) else run_cli(PackedStringArray(["save", key, "--changes", path, "--message=" + msg, "--author", author]))
	DirAccess.remove_absolute(path)
	if not r.get("ok", false):
		_set_status("Save failed: " + str(r.get("error", "?")))
		return r
	var k := key
	reload(k)
	var ver := int(r.get("version", -1)) if r.get("version") != null else -1
	_message.text = ""
	_set_status("Saved %s: %d change(s)%s" % [k, changes.size(), "" if ver < 0 else ", v%03d" % ver])
	_load_badges(); _fill_list()
	pose_saved.emit(k, ver)
	return r

## Phone save: queue the edit for the Mac (tools/phone_sync.sh applies it to the repo with
## pose_notes.py, as the desktop Save does), then save it on the device so the game uses it now.
func _save_on_phone(changes: Array, msg: String) -> Dictionary:
	var Queue = load("res://scripts/studio/phone_sync_queue.gd")
	var id: String = Queue.enqueue("save", {"key": key, "changes": changes, "message": msg})
	if id == "": return {"ok": false, "error": "could not write the phone save queue"}
	var ck := _copy_key(key)
	var ok := true
	if PoseDiff.is_action_key(key):
		ok = PoseDiff.BallActions.save_override(int(key.substr(1)), engine._copies[ck])
	else:
		ok = engine._save_key(ck)
	if not ok: return {"ok": false, "error": "queued for the Mac, but the on-device save failed", "queued": id}
	var k := key
	# Work on the pose exactly as stored on the device (the store rounds values when it encodes
	# them), so the saved pose and its baseline match and the pose reads as saved.
	engine._copies.erase(ck); engine._dirty.erase(ck)
	_disk[k] = _baseline(k)
	_reselect(stage)
	_remember()
	_after_change(false)
	_set_status("Saved %s on the phone: %d change(s), waiting for the Mac sync" % [k, changes.size()])
	pose_saved.emit(k, -1)
	return {"ok": true, "key": k, "changed": changes.size(), "queued": id}

## Drop the working copy and reload from disk (undoable: the old copy is kept on the stack).
func revert() -> void:
	if not _ok() or key == "": return
	if _editing_drag(): _set_status("Finish the drag first (release, or Esc to cancel), then revert"); return
	if _compare != null: compare_end()
	var st := stage
	begin_edit("revert")
	# Reload the live library resource too: the working copy is rebuilt from it, and an
	# outside write (pose_set.py, pose_notes.py, git) must not come back as the old pose.
	PoseDiff.reload_live(key)
	engine._copies.erase(engine._key); engine._dirty.erase(engine._key)
	_disk[key] = _baseline(key)
	_reselect(st)
	end_edit()
	_set_status("Reverted " + key)
	pose_reloaded.emit(key)

## Reload a pose from disk ignoring the resource cache, into the live library resource the
## game holds (link 'reload'), and drop its working copy.
func reload(k: String = "") -> bool:
	if not _ok(): return false
	if k == "": k = key
	if not PoseDiff.reload_live(k): return false
	engine._copies.erase(_copy_key(k)); engine._dirty.erase(_copy_key(k))
	_disk[k] = _baseline(k)
	if PoseDiff.is_serve_key(k) and engine._serve:
		var st := stage
		engine._select_workspace(2)   # its serve list holds the old serve objects: rebuild from the store
		if k == key: _reselect(st)
	if k == key:
		_reselect(stage)
		_remember()
		_after_change(false)
	pose_reloaded.emit(k)
	return true

## python3 tools/pose_notes.py <args> --json; one JSON object back ({ok:false,error} on failure).
func run_cli(args: PackedStringArray, tool := "res://tools/pose_notes.py") -> Dictionary:
	var script := ProjectSettings.globalize_path(tool)
	var full := PackedStringArray([script]); full.append_array(args); full.append("--json")
	var out: Array = []
	var code := -1
	for py in ["python3", "/usr/bin/python3"]:
		out.clear()
		code = OS.execute(py, full, out, false)
		if code != -1 and code != 127: break
	var text := str(out[0]) if not out.is_empty() else ""
	var parsed = JSON.parse_string(text.strip_edges())
	if parsed == null:
		# Take the last line that parses (tolerates stray output before the JSON).
		var lines := text.strip_edges().split("\n")
		for i in range(lines.size() - 1, -1, -1):
			parsed = JSON.parse_string(lines[i])
			if parsed != null: break
	if parsed is Dictionary:
		if not parsed.has("ok"): parsed["ok"] = code == 0
		return parsed
	return {"ok": false, "error": "pose_notes.py exit %d: %s" % [code, text.strip_edges().right(300)]}

func select_joint(id: String) -> void:
	if not _ok() or not (id in Fields.JOINT_IDS): return
	engine._joint_chosen(id)
	_ensure_gizmo_mode()
	_inspector.jump_to_joint(id)
	_update_joint_label()

## A joint without a channel for the chosen mode switches to the mode it has (and the
## view hint says so) instead of showing no gizmo.
func _ensure_gizmo_mode() -> void:
	var id: String = preview.selected_joint
	if id != _note_joint: _mode_note = ""; _note_joint = id
	engine._sync_selected_gizmo()
	var gm: OptionButton = engine._gizmo_mode
	if gm.selected != _wanted_mode and not gm.is_item_disabled(_wanted_mode):
		gm.select(_wanted_mode)   # back to the user's W/E choice
		engine._sync_selected_gizmo()
	var m: int = gm.selected
	if id != "" and gm.is_item_disabled(m) and not gm.is_item_disabled(1 - m):
		gm.select(1 - m)   # not _select_gizmo_mode: that writes user:// view settings
		engine._sync_selected_gizmo()
		_mode_note = "no %s gizmo, showing %s" % [["move", "rotate"][m], ["Move", "Rotate"][1 - m]]

func set_gizmo_mode(mode: int) -> void:
	if not _ok(): return
	if _view_input and _view_input.drag != _view_input.Drag.NONE: return   # no mode switch mid-drag
	mode = clampi(mode, 0, 1)
	_wanted_mode = mode
	_note_joint = preview.selected_joint
	if engine._gizmo_mode.is_item_disabled(mode):
		_mode_note = "no %s gizmo for this joint" % ["move", "rotate"][mode]
		_set_status("%s has no %s gizmo" % [String(preview.JOINT_NAMES.get(preview.selected_joint, "This joint")), ["move", "rotate"][mode]])
	else:
		_mode_note = ""
		engine._gizmo_mode.select(mode)   # not _select_gizmo_mode: that writes user:// view settings
	preview.cancel_gesture()
	engine._sync_selected_gizmo()
	_update_joint_label()

## front / side / back (Blender numpad 1 / 3 / 7), *_opposite = Ctrl; reset = phone default.
const VIEW_YAW := {"front": PI, "side": PI * 0.5, "back": 0.0, "front_opposite": 0.0, "side_opposite": -PI * 0.5, "back_opposite": PI}
func view(n: String) -> void:
	if preview == null: return
	if _view_input and VIEW_YAW.has(n): _view_input.set_view(VIEW_YAW[n])
	else: preview.view(n)

func frame_pose() -> void:
	if _view_input: _view_input.frame_pose()

func set_overlay(what: String, on: bool) -> void:
	if preview == null: return
	match what:
		"ghosts": preview.set_ghosts_visible(on); _ghost_toggle.set_pressed_no_signal(on)
		"arc": preview.set_arc_visible(on); _arc_toggle.set_pressed_no_signal(on)
		"contact":
			_contact_on = on; _contact_toggle.set_pressed_no_signal(on)
			if preview.contact_preview: preview.contact_preview.visible = on and preview._contact_enabled

## Swing curve between the keys (swing_path_blend): 0 straight lines, 1 the full curve.
func set_swing_curve(v: float) -> Dictionary:
	return set_field("swing_path_blend", null, clampf(v, 0.0, 1.0))

## Paddle path keys (swing arc): [[progress, Vector3 offset], ...] sorted by progress. Strokes only
## (serves, stances and ball actions have none). Progress 0..1 = Wind-up -> Finish
## (paddle_path_*); LEAD_IN + v (v 0..1 = Ready -> Wind-up) = the grey lead-in (ready_path_*).
const LEAD_IN := 1.0
static func is_lead_in(t: float) -> bool: return t > LEAD_IN
func path_keys_supported() -> bool:
	return _ok() and key != "" and not engine._base and not engine._serve and not engine.get("_action") and engine._has_motion()

func path_keys() -> Array:
	var out: Array = []
	if not path_keys_supported(): return out
	var c: Resource = engine._current
	var tan := func(arr: PackedVector3Array, i: int) -> Vector3: return arr[i] if i < arr.size() else Vector3.ZERO
	for i in mini(c.paddle_path_times.size(), c.paddle_path_offsets.size()): out.append([c.paddle_path_times[i], c.paddle_path_offsets[i], tan.call(c.paddle_path_tangents, i)])
	for i in mini(c.ready_path_times.size(), c.ready_path_offsets.size()): out.append([LEAD_IN + c.ready_path_times[i], c.ready_path_offsets[i], tan.call(c.ready_path_tangents, i)])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

## Replace the path keys [[progress, offset, tangent?], ...] (one undo step unless a drag's
## begin_edit is open). Progress is kept off Wind-up / Contact / Finish (at least 0.02 away);
## offsets at most 0.8 m; tangent (offset slope per unit progress, zero = automatic) at most 4.
func set_path_keys(keys: Array, refresh := true) -> Dictionary:
	if not path_keys_supported(): return {"ok": false, "error": "path keys: strokes only"}
	var times := PackedFloat32Array(); var offs := PackedVector3Array(); var tans := PackedVector3Array()
	var lead_times := PackedFloat32Array(); var lead_offs := PackedVector3Array(); var lead_tans := PackedVector3Array()
	var sorted := keys.duplicate(); sorted.sort_custom(func(a, b): return a[0] < b[0])
	for k in sorted:
		if is_lead_in(float(k[0])):
			var o: Vector3 = k[1]
			lead_times.append(clampf(float(k[0]) - LEAD_IN, 0.03, 0.97)); lead_offs.append(o.limit_length(0.8))
			lead_tans.append(_key_tangent(k))
			continue
		var t: float = clampf(float(k[0]), 0.02, 0.98)
		if absf(t - 0.5) < 0.02: t = 0.48 if t < 0.5 else 0.52
		var o: Vector3 = k[1]
		times.append(t); offs.append(o.limit_length(0.8)); tans.append(_key_tangent(k))
	var own := _txn == null
	if own: begin_edit("path keys")
	var prev_group: int = engine._group.selected
	engine._group.select(5)
	engine._changed("paddle_path_times", times, false)
	engine._changed("ready_path_times", lead_times, false)
	engine._changed("ready_path_offsets", lead_offs, false)
	engine._changed("paddle_path_tangents", tans, false)
	engine._changed("ready_path_tangents", lead_tans, false)
	engine._changed("paddle_path_offsets", offs, refresh)
	engine._group.select(prev_group)
	selected_field = "paddle_path_offsets"
	if own: end_edit()
	else: _after_change(true)
	return {"ok": true, "keys": path_keys().size()}

func _key_tangent(k: Array) -> Vector3:
	var v: Vector3 = k[2] if k.size() > 2 and k[2] is Vector3 else Vector3.ZERO
	return v.limit_length(4.0)

## The slope the curve uses at a path key now (automatic or its tangent), offset per unit progress.
func path_key_slope(t: float) -> Vector3:
	if not path_keys_supported(): return Vector3.ZERO
	var c: Resource = engine._current
	if is_lead_in(t): return ReadyCurve.key_slope(Path.sample(c, 0.0), t - LEAD_IN)
	return Path.path_key_slope(c, t)

## Speed points of one motion part (stroke_speed_ramp.gd): [(time fraction, speed, 0)], at most
## 4, x kept inside 0.02..0.98, speed 0..3. One undo step unless a drag's begin_edit is open.
func set_speed_points(part: int, pts, refresh := true) -> Dictionary:
	if not path_keys_supported(): return {"ok": false, "error": "speed points: strokes only"}
	var field: String = SpeedRamp.POINTS[part]
	if gameplay_locked(field):
		_set_status("Locked: the strike's speed is gameplay timing. Turn on Gameplay edit (top bar) to change it.")
		return {"ok": false, "error": "gameplay field locked: " + field, "locked": true}
	var out := PackedVector3Array()
	for p in pts:
		if out.size() >= SpeedRamp.MAX_POINTS: break
		var v := Vector3(p[0], p[1], 0.0) if p is Array else Vector3(p.x, p.y, 0.0)
		out.append(Vector3(clampf(v.x, 0.02, 0.98), clampf(v.y, 0.0, SpeedRamp.MAX_SPEED), 0.0))
	var own := _txn == null
	if own: begin_edit("speed points")
	var prev_group: int = engine._group.selected
	engine._group.select(5)
	engine._changed(field, out, refresh)
	engine._group.select(prev_group)
	selected_field = field
	if own: end_edit()
	else: _after_change(true)
	return {"ok": true, "points": out.size()}

## Not engine._ghost_count_changed: that writes user:// view settings.
func set_ghost_count(n: int) -> void:
	if preview == null: return
	preview.set_inbetween_count(n)
	engine._ghost_slider.set_value_no_signal(preview.inbetween_count); engine._update_ghost_label()
	_ghost_count.set_value_no_signal(preview.inbetween_count)

func set_second_view(on: bool) -> void:
	_second_toggle.set_pressed_no_signal(on)
	_second.visible = on and _vp2 != null
	if _vp2: _vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _second.visible else SubViewport.UPDATE_DISABLED

func toggle_help() -> void:
	_help.visible = not _help.visible
	if _help.visible: _help.reset_size(); _help.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

# ---------------------------------------------------------------- hold-to-compare

func compare_begin(field: String, axis: int) -> void:
	if not _ok() or key == "" or _txn != null or _compare != null: return
	var saved = _at(_disk.get(key), stage, field, {})
	if saved == null: return
	_compare = {"key": key, "stage": stage, "snap": engine._current.duplicate(true), "dirty": engine._dirty.has(engine._key)}
	var timing := _is_timing(field)
	var prev_group: int = engine._group.selected
	engine._group.select(5 if timing else 6)
	var v = saved
	if axis >= 0:
		var vec: Vector3 = (engine._current if timing else engine._edit).get(field); vec[axis] = saved[axis]; v = vec
	engine._changed(field, v)
	engine._group.select(prev_group)
	_set_status("Showing saved %s (release to go back)" % field)
	_inspector.sync()

func compare_end() -> void:
	if _compare == null: return
	var c: Dictionary = _compare
	_compare = null
	if not _ok(): return
	engine._copies[_copy_key(c.key)] = c.snap
	_reselect(c.stage)
	if c.dirty: engine._dirty[engine._key] = true
	else: engine._dirty.erase(engine._key)
	_remember()
	_inspector.sync()
	_set_status("")

# ================================================================ events

func _after_change(edited: bool) -> void:
	_needs_sync = true
	if edited: pose_edited.emit(key)

func _on_gizmo_dragged(axis: int, _amount: float) -> void:
	if _txn != null and _txn.field == "":
		var ch = engine._gizmo_channels.get("axes", [])
		if ch is Array and axis < ch.size() and ch[axis] is Dictionary and not ch[axis].is_empty():
			_txn.field = str(ch[axis].field); _txn.axis = int(ch[axis].get("component", -1))
			selected_field = _txn.field
	_after_change(true)

func _on_joint_selected(id: String) -> void:
	_ensure_gizmo_mode()
	_inspector.jump_to_joint(id)
	_update_joint_label()

func _on_workspace(i: int) -> void:
	select_pose(["s00", "b00", "v00", "a00"][clampi(i, 0, 3)])

## Workspace index of a pose key: 0 strokes, 1 body stances, 2 serves, 3 ball actions.
func _workspace_of(k: String) -> int:
	return 1 if k.begins_with("b") else 2 if PoseDiff.is_serve_key(k) else 3 if PoseDiff.is_action_key(k) else 0

## Key names on the timeline: wind-up / contact / finish, or the ball action's own keys.
func stage_names() -> Array:
	if _ok() and engine.get("_action") and engine._current != null:
		return PoseDiff.BallActions.KEY_NAMES[int(engine._current.action_id)]
	return ["Wind-up", "Contact", "Finish"]

func _on_list_selected() -> void:
	if _list_guard: return
	var it := _pose_list.get_selected()
	if it == null: return
	var k := str(it.get_metadata(0))
	# Deferred: select_pose refills this Tree, which Tree refuses inside its own item_selected.
	if k != key: select_pose.call_deferred(k)

func stage_preview_changed() -> void:
	_needs_sync = true

func _open_pdf() -> void:
	OS.shell_open(ProjectSettings.globalize_path(PDF))

# ================================================================ quit guard

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_quit()

## Poses whose working copy differs from the file on disk (fresh load).
func unsaved_keys() -> Array:
	var out: Array = []
	if not _ok(): return out
	for ck in engine._dirty.keys():
		var k := _key_from_copy(str(ck))
		var cp = engine._copies.get(ck)
		if k == "" or cp == null: continue
		if not PoseDiff.diff(cp, _baseline(k), k.begins_with("b")).is_empty(): out.append(k)
	out.sort()
	return out

var _quit_dlg: ConfirmationDialog
## Window close, Cmd+Q, link 'quit': quit at once when nothing is unsaved, else ask
## Save all / Discard / Cancel. Returns the unsaved keys.
func request_quit() -> Array:
	if _txn != null: abort_edit()
	if _compare != null: compare_end()
	var keys := unsaved_keys()
	if keys.is_empty():
		get_tree().quit()
		return keys
	if _quit_dlg == null:
		_quit_dlg = ConfirmationDialog.new()
		_quit_dlg.name = "QuitDialog"
		_quit_dlg.title = "Unsaved poses"
		_quit_dlg.get_ok_button().text = "Save all"
		_quit_dlg.get_ok_button().name = "QuitDialog_SaveAll"
		_quit_dlg.get_cancel_button().name = "QuitDialog_Cancel"
		_quit_dlg.add_button("Discard", true, "discard").name = "QuitDialog_Discard"
		_quit_dlg.confirmed.connect(_quit_save_all)
		_quit_dlg.custom_action.connect(func(a: StringName) -> void:
			if a == &"discard": _quit_dlg.hide(); get_tree().quit())
		_root.add_child(_quit_dlg)
	_quit_dlg.dialog_text = "Unsaved edits in %s.\nSave them before closing?" % ", ".join(keys)
	_quit_dlg.popup_centered()
	return keys

func _quit_save_all() -> void:
	for k in unsaved_keys():
		if not select_pose(k): _set_status("Quit cancelled: cannot open " + k); return
		var r := save("")
		if not r.get("ok", false): _set_status("Quit cancelled: save of %s failed" % k); return
	get_tree().quit()

func _set_status(t: String) -> void:
	if _status: _status.text = t

## A message the user must see wherever they are (status line and the phone's toast).
func notify(t: String) -> void:
	_set_status(t)
	notice.emit(t)

# ---------------------------------------------------------------- "my keys play"
## How this stroke's Wind-up / Finish keys reach play (drive_serve_motion.gd):
##   "always"  the game plays the authored keys anyway (two-hand backhands, strokes without a drive build)
##   "on"      play_authored_keys: the whole authored pose plays
##   "off"     the game builds the Wind-up / Finish body; only the paddle position of the keys plays
##   ""        not a stroke
func keys_play_state() -> String:
	if not path_keys_supported(): return ""
	var c: PostureDefinition = engine._current
	if c.play_authored_keys == 1: return "on"
	if c.family == 1 and c.left_hand_mode == 1: return "always"
	if Motion.motion_kind(c, 1.0) == "DRIVE" and is_zero_approx(Motion.drive_strength(c, 1.0)): return "always"
	return "off"

## mode "on" / "off": the switch alone (the keys as they are). "bake": first copy the Wind-up and
## Finish the game builds now into the keys, then switch on, so play looks the same until an edit.
## One undo step.
func set_keys_play(mode: String) -> Dictionary:
	if not path_keys_supported(): return {"ok": false, "error": "strokes only"}
	if _txn != null: end_edit()
	stop_drag()
	if mode == "bake":
		var st: int = stage
		begin_edit("my keys play")
		engine._copies[_copy_key(key)] = Motion.baked_keys(engine._current)
		_reselect(st)
		_update_dirty_flag()
		end_edit()
		notify("Wind-up and Finish keys now hold the game's poses, and they are what plays. Pose them freely.")
		return {"ok": true, "state": keys_play_state()}
	var r: Dictionary = set_field("play_authored_keys", null, 1 if mode == "on" else 0, true)
	if r.get("ok", false):
		notify("Your Wind-up and Finish keys now play (whole pose)." if mode == "on" else "Wind-up and Finish bodies are built by the game again (your keys are kept).")
	r["state"] = keys_play_state()
	return r

## The key (0 Wind-up, 1 Contact, 2 Finish) nearest in time to where the timeline is.
func nearest_key_stage() -> int:
	if not _ok() or not engine._has_motion(): return 1
	var tl = engine._timeline
	if not tl.active or not tl._configure(): return stage
	var s = tl.sequence
	var times := [s.prefix_seconds, s.prefix_seconds + s.release_seconds, s.prefix_seconds + s.stroke_seconds]
	var best := 0
	for i in 3: if absf(times[i] - tl.elapsed) < absf(times[best] - tl.elapsed): best = i
	return best

func _update_joint_label() -> void:
	if preview == null: return
	var id: String = preview.selected_joint
	var mode: int = engine._gizmo_mode.selected
	_move_btn.set_pressed_no_signal(mode == 0); _rotate_btn.set_pressed_no_signal(mode == 1)
	_move_btn.disabled = engine._gizmo_mode.is_item_disabled(0); _rotate_btn.disabled = engine._gizmo_mode.is_item_disabled(1)
	if autopose_on:
		_refresh_ap_pins()
		_set_hint(_autopose_hint()); return
	if id == "": _set_hint("Click a joint dot to edit it · drag empty space to orbit · wheel zoom"); return
	var parts: Array = [String(preview.JOINT_NAMES.get(id, id)), ["Move", "Rotate"][mode]]
	if _mode_note != "": parts.append(_mode_note)
	var note: String = engine._gizmo_hint.text.trim_suffix(" · drag elsewhere to orbit")   # phone text; the studio orbits with the middle button
	if note != "": parts.append(note)
	var warn := drag_warning()
	if warn != "": parts.push_front("LOCK " + warn)
	_set_hint(" · ".join(parts))

func _process(delta: float) -> void:
	if not _ok():
		if is_ready: is_ready = false; _set_status("Engine closed. Restart the studio.")
		return
	var pv = preview
	pv.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not _contact_on and pv.contact_preview and pv.contact_preview.visible: pv.contact_preview.visible = false
	if _second.visible: _update_second_camera()
	_timeline.tick()
	_update_action_ball()
	if engine._gizmo_hint.text != _engine_hint:   # scrub / play / key: "preview only" note
		_engine_hint = engine._gizmo_hint.text; _update_joint_label()
	_poll_frames += 1
	if _poll_frames % 15 == 0: _poll_external()
	# During a viewport drag the pose list (badge columns) and top bar wait: a list column that
	# appears re-widths the left column, resizes the preview and would cancel the drag.
	var dragging: bool = _view_input != null and _view_input.drag in [_view_input.Drag.GIZMO, _view_input.Drag.TIP, _view_input.Drag.AUTOPOSE, _view_input.Drag.PATH]
	if dragging and not _drag_valid(): stop_drag(); dragging = false   # play / scrub / switch from anywhere
	if _needs_sync:
		_needs_sync = false
		_inspector.sync()
		_needs_list = true
	if _needs_list and not dragging:
		_needs_list = false
		_refresh_top()
		_refresh_list_row(key)
	_badge_clock += delta
	if _badge_clock > 5.0 and not dragging:
		_badge_clock = 0.0
		_load_badges(); _refresh_list_badges()
		_refresh_link()

## Ball actions: a ball in the preview (on the floor until the Grab, in the hand while carried,
## gone after the Release). Lives beside the preview player, never under it (camera fit, metrics).
var _action_ball: MeshInstance3D = null
func _update_action_ball() -> void:
	var on: bool = bool(engine.get("_action")) and preview != null and is_instance_valid(preview.player) and engine._current != null
	if not on:
		if _action_ball: _action_ball.visible = false
		return
	var pl = preview.player
	if _action_ball == null or not is_instance_valid(_action_ball):
		_action_ball = MeshInstance3D.new(); _action_ball.name = "StudioActionBall"
		var m := SphereMesh.new(); m.radius = 0.0375; m.height = 0.075
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color("e8f04a"); m.material = mat
		_action_ball.mesh = m
		pl.get_parent().add_child(_action_ball)
	var pickup: bool = int(engine._current.action_id) == PoseDiff.BallActions.PICKUP
	var tl = engine._timeline
	var where := ""   # floor / hand / ""
	if tl.active and not tl.sample.is_empty():
		var phase := String(tl.sample.get("phase", ""))
		var t: float = tl.elapsed
		var times: Array = tl.sequence.times if tl.sequence.get("times") != null else []
		if pickup: where = "floor" if times.is_empty() or t <= times[1] else "hand"
		else: where = "hand" if times.is_empty() or t < times[1] else ""
		if phase == "": where = ""
	else:
		where = ("floor" if engine._stage <= 1 else "hand") if pickup else ("hand" if engine._stage <= 1 else "")
	_action_ball.visible = where != ""
	if where == "floor":
		var b: Vector3 = PoseDiff.BallActions.PICKUP_BALL
		_action_ball.global_position = pl.global_position + pl._get_forehand_axis() * b.x + pl._get_forward_axis() * b.z + Vector3.UP * b.y
	elif where == "hand":
		var h: Vector3 = preview.joint_world_position("left_hand")
		if h.is_finite(): _action_ball.global_position = h + Vector3.UP * 0.06
		else: _action_ball.visible = false

## Edits made outside the studio UI (the TCP link) become undo steps and refresh the UI.
func _poll_external() -> void:
	if _txn != null or _compare != null or key == "": return
	var ek: String = _key_from_copy(engine._key)
	if ek != "" and ek != key:
		key = ek; stage = engine._stage
		if _disk.get(key) == null: _disk[key] = _baseline(key)
		_workspace.select(_workspace_of(key))
		_remember(); _fill_list(); _inspector.rebuild(); _after_change(false)
		pose_selected.emit(key)
		return
	if engine._stage != stage:
		stage = engine._stage; _needs_sync = true; stage_changed.emit(stage)
	if _known.is_empty() or _known.key != key: _remember(); return
	var sig := _sig(engine._current)
	if sig == _known.sig: return
	_undo.append({"label": "external edit", "key": key, "stage": stage, "field": "", "axis": -1, "old": null,
		"new": null, "before": _known.snap, "after": engine._current.duplicate(true)})
	if _undo.size() > UNDO_LIMIT: _undo.pop_front()
	_redo.clear()
	_remember()
	_after_change(true)

func _update_second_camera() -> void:
	var size := Vector2i(maxi(2, roundi(_second.size.x)), maxi(2, roundi(_second.size.y)))
	if _vp2.size != size: _vp2.size = size
	var cam: Camera3D = preview.camera
	var target: Vector3 = preview.camera_target
	var dist: float = cam.global_position.distance_to(target)
	var yaw: float = [PI * 0.5, PI, 0.0, 0.0][_second_angle.selected]
	var pitch: float = 1.45 if _second_angle.selected == 3 else 0.08
	_cam2.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	_cam2.look_at(target, Vector3.FORWARD if _second_angle.selected == 3 else Vector3.UP)

func _refresh_top() -> void:
	if not _ok() or key == "": return
	var n := diff().size()
	var dirty: bool = engine._dirty.has(engine._key)
	_dirty_label.text = ("● unsaved (%d)" % n) if n > 0 else ("● edited" if dirty else "")
	_save_btn.disabled = n == 0
	_revert_btn.disabled = n == 0 and not dirty
	_undo_btn.disabled = _undo.is_empty(); _redo_btn.disabled = _redo.is_empty()
	_undo_btn.tooltip_text = "Undo (Cmd+Z)" + ("" if _undo.is_empty() else ": " + _describe(_undo[-1]))
	_redo_btn.tooltip_text = "Redo (Shift+Cmd+Z)" + ("" if _redo.is_empty() else ": " + _describe(_redo[-1]))
	_update_joint_label()

func _refresh_link() -> void:
	if _link == null or not is_instance_valid(_link):
		_link = null
		var pm = get_node_or_null("/root/PerfMonitor")
		if pm:
			for c in pm.get_children():
				var s = c.get_script()
				if s and String(s.resource_path).ends_with("pose_studio_link.gd"): _link = c
	if _link == null: _set_link("link off", Ui.MUTED); return
	var srv = _link.get("_server")
	var peer = _link.get("_peer")
	var listening: bool = srv != null and srv.is_listening()
	var client: bool = peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	_set_link("● link :%s · %s" % [str(_link.get("port")), "client" if client else ("listening" if listening else "down")],
		Ui.ACCENT if client else (Ui.BLUE if listening else Ui.RED))

func _set_link(t: String, c: Color) -> void:
	if _link_label.text == t: return
	_link_label.text = t
	_link_label.add_theme_color_override("font_color", c)

# ---------------------------------------------------------------- pose list

func _store_dir() -> String:
	var d := OS.get_environment("POSE_STUDIO_ROOT")
	if d != "": return d.trim_suffix("/")
	var r := OS.get_environment("POSE_STUDIO_REPO")
	return (r.trim_suffix("/") if r != "" else ProjectSettings.globalize_path("res://").trim_suffix("/")) + "/pose_studio"

func _json(path: String, fallback):
	if not FileAccess.file_exists(path): return fallback
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return fallback if v == null else v

func _load_badges() -> void:
	var repo := OS.get_environment("POSE_STUDIO_REPO")
	var root := repo.trim_suffix("/") if repo != "" else ProjectSettings.globalize_path("res://").trim_suffix("/")
	var checker = _json(root + "/logs/pose_check/latest.json", {})
	var ratings = _json(_store_dir() + "/ratings.json", [])
	if not (checker is Dictionary): checker = {}
	if not (ratings is Array): ratings = []
	_badges.clear()
	for k in _all_keys():
		var b := {"score": null, "stars": null, "stale": false, "version": -1}
		if checker.get(k) is Dictionary: b.score = checker[k].get("score")
		var vdir: String = _store_dir() + "/versions/" + str(k)
		if DirAccess.dir_exists_absolute(vdir):
			for f in DirAccess.get_files_at(vdir):
				if f.begins_with("v") and f.ends_with(".json") and f.substr(1, f.length() - 6).is_valid_int():
					b.version = maxi(b.version, int(f.substr(1, f.length() - 6)))
		var last = null
		var on_cur = null
		for r in ratings:
			if r is Dictionary and r.get("pose") == k:
				last = r
				if int(r.get("version", -2)) == b.version: on_cur = r
		if on_cur != null: b.stars = int(on_cur.get("stars", 0))
		elif last != null: b.stars = int(last.get("stars", 0)); b.stale = true
		_badges[k] = b

func _all_keys() -> Array:
	var out: Array = []
	for d in PostureLibrary.instance().all_definitions(): out.append(PoseDiff.key_of(d))
	for d in BasePoseLibrary.instance().all_definitions(): out.append(PoseDiff.key_of(d))
	for d in PoseDiff.BallActions.all_definitions(): out.append(PoseDiff.key_of(d))
	return out

func _list_defs() -> Array:
	var base := key.begins_with("b")
	var defs: Array = BasePoseLibrary.instance().all_definitions() if base else PoseDiff.ServeStore.all_definitions() if PoseDiff.is_serve_key(key) else PoseDiff.BallActions.all_definitions() if PoseDiff.is_action_key(key) else PostureLibrary.instance().all_definitions()
	var out := defs.duplicate()
	out.sort_custom(func(a, b): return PoseDiff.key_of(a) < PoseDiff.key_of(b))
	return out

func _fill_list() -> void:
	if _badges.is_empty(): _load_badges()
	_list_guard = true
	_pose_list.clear()
	var root := _pose_list.create_item()
	var q := _pose_filter.text.strip_edges().to_lower() if _pose_filter else ""
	var defs := _list_defs()
	var shown := 0
	for d in defs:
		var k: String = PoseDiff.key_of(d)
		var nm := String(d.display_name)
		if q != "" and not (k.to_lower().contains(q) or nm.to_lower().contains(q)): continue
		shown += 1
		var it := _pose_list.create_item(root)
		it.set_metadata(0, k)
		it.set_text(COL_KEY, k)
		it.set_custom_font_size(COL_KEY, Theme_.FONT_SMALL)
		it.set_custom_color(COL_KEY, Ui.MUTED)
		it.set_text(COL_NAME, nm)
		var tip := "%s  %s\n%s" % [k, nm, d.resource_path.trim_prefix("res://")]
		for c in 5: it.set_tooltip_text(c, tip)
		it.set_custom_color(COL_DOT, Ui.RED)
		it.set_custom_font_size(COL_DOT, Theme_.FONT_SMALL)
		for c in [COL_SCORE, COL_STARS]:
			it.set_custom_font_size(c, Theme_.FONT_SMALL)
			it.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		if k == key: it.select(0)
	_badge_columns()
	for it in _list_rows(): _set_badges(it, str(it.get_metadata(0)))
	_list_guard = false
	_pose_count.text = ("%d" % shown) if q == "" else ("%d of %d" % [shown, defs.size()])
	_fit_list_columns()
	var sel := _pose_list.get_selected()
	if sel: _pose_list.scroll_to_item(sel)

## Key, score and stars columns are as wide as their widest cell (0 when empty); the name
## column takes the rest. The pose list column never gets narrower than its longest name.
func _fit_list_columns() -> void:
	var font := _pose_list.get_theme_font("font")
	var fs := _pose_list.get_theme_font_size("font_size")
	var pad := _pose_list.get_theme_constant("inner_item_margin_left") + _pose_list.get_theme_constant("inner_item_margin_right") + 2
	var widths := [0.0, 0.0, 0.0, 0.0, 0.0]
	var root := _pose_list.get_root()
	var it := root.get_first_child() if root else null
	while it != null:
		for c in 5:
			var t := it.get_text(c)
			if t == "": continue
			var f := it.get_custom_font_size(c)
			widths[c] = maxf(widths[c], font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, f if f > 0 else fs).x + pad)
		it = it.get_next()
	widths[COL_DOT] = maxf(widths[COL_DOT], 16.0)
	for c in [COL_DOT, COL_KEY, COL_SCORE, COL_STARS]:
		_pose_list.set_column_custom_minimum_width(c, ceili(widths[c]))
	# Whole-list minimum: every column + panel margins + a scroll bar.
	var sb := _pose_list.get_theme_stylebox("panel")
	var frame := (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)) if sb else 4.0
	var bar := 12.0 + _pose_list.get_theme_constant("scrollbar_h_separation")
	var need := ceilf(widths[0] + widths[1] + widths[2] + widths[3] + widths[4] + frame + bar + 4.0)
	_pose_list.set_column_custom_minimum_width(COL_NAME, ceili(widths[COL_NAME]))
	if absf(_left.custom_minimum_size.x - maxf(LEFT_MIN, need)) > 0.5:
		_left.custom_minimum_size.x = maxf(LEFT_MIN, need)
		_queue_layout()

## Score / stars columns: shown only when some pose in the list has one; then a pose
## without one shows a dim dash (no mostly-empty columns).
func _badge_columns() -> void:
	_any_score = false; _any_stars = false
	for it in _list_rows():
		var b: Dictionary = _badges.get(str(it.get_metadata(0)), {})
		if b.get("score") != null: _any_score = true
		if b.get("stars") != null: _any_stars = true

func _set_badges(it: TreeItem, k: String) -> void:
	var b: Dictionary = _badges.get(k, {})
	var unsaved: bool = _ok() and engine._dirty.has(_copy_key(k))
	var dot := "●" if unsaved else ""
	if it.get_text(COL_DOT) != dot: it.set_text(COL_DOT, dot)
	var score := ("–" if _any_score else "") if b.get("score") == null else str(b.score)
	if it.get_text(COL_SCORE) != score:
		it.set_text(COL_SCORE, score)
		it.set_custom_color(COL_SCORE, Color(Ui.MUTED, 0.45 if score == "–" else 1.0))
	var s = b.get("stars")
	var stale: bool = b.get("stale", false)
	var stars := ("–" if _any_stars else "") if s == null else ("★%d%s" % [s, "~" if stale else ""])
	if it.get_text(COL_STARS) != stars:
		it.set_text(COL_STARS, stars)
		it.set_custom_color(COL_STARS, Color(Ui.MUTED, 0.45) if s == null else (Ui.MUTED if stale else Color("ffdc62")))
		if stale: it.set_tooltip_text(COL_STARS, "stale: rated on an older version, rate again")

func _list_rows() -> Array:
	var out: Array = []
	var root := _pose_list.get_root()
	if root: out = root.get_children()
	return out

func _refresh_list_row(k: String) -> void:
	var root := _pose_list.get_root()
	if root == null: return
	var it := root.get_first_child()
	while it != null:
		if str(it.get_metadata(0)) == k: _set_badges(it, k)
		it = it.get_next()

func _refresh_list_badges() -> void:
	var root := _pose_list.get_root()
	if root == null: return
	_badge_columns()
	var it := root.get_first_child()
	while it != null:
		_set_badges(it, str(it.get_metadata(0)))
		it = it.get_next()
	_fit_list_columns()

func _list_state() -> Dictionary:
	var items: Array = []
	for it in _list_rows():
		items.append({"key": str(it.get_metadata(0)), "text": "%s  %s" % [it.get_text(COL_KEY), it.get_text(COL_NAME)],
			"unsaved": it.get_text(COL_DOT) != "", "score": it.get_text(COL_SCORE).replace("–", ""),
			"stars": it.get_text(COL_STARS).replace("–", "")})
	var sel := _pose_list.get_selected()
	return {"items": items, "selected": str(sel.get_metadata(0)) if sel else "", "filter": _pose_filter.text}

# ================================================================ keyboard

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed: return
	var e: InputEventKey = event
	var cmd := e.is_command_or_control_pressed()
	var focus := _root.get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	if _is(e, KEY_ESCAPE):
		# Always handled here: PauseController's Esc would close the engine.
		if _help.visible: _help.visible = false
		elif typing: focus.release_focus()
		elif _view_input: _view_input.cancel()
		_handled(); return
	if cmd and _is(e, KEY_S):
		commit_pending_text()
		save(_message.text); _handled(); return
	if typing: return
	if cmd and _is(e, KEY_Z):
		if e.shift_pressed: redo()
		else: undo()
		_handled(); return
	if cmd and not (e.ctrl_pressed and _view_key(e) >= 0): return   # Ctrl+1/3/7 (Ctrl is cmd off macOS)
	var act := shortcut_action(e)
	if act == "": return
	if e.echo and not (act in ["step_back", "step_forward"]): _handled(); return
	run_shortcut(act)
	_handled()

## A SpinBox applies typed text only on Enter or focus exit: apply it before a save so the
## typed value is part of it (Cmd+S, Save button).
func commit_pending_text() -> void:
	var focus := _root.get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.get_parent() is SpinBox: focus.get_parent().apply()

func _is(e: InputEventKey, k: int) -> bool:
	return e.keycode == k or (e.keycode == KEY_NONE and e.physical_keycode == k)

## 0 front, 1 side, 2 back for 1 / 3 / 7 on the main row or the numpad; -1 otherwise.
func _view_key(e: InputEventKey) -> int:
	for i in 3:
		if _is(e, [KEY_1, KEY_3, KEY_7][i]) or _is(e, [KEY_KP_1, KEY_KP_3, KEY_KP_7][i]): return i
	return -1

## Map a key event (no Cmd) to an action id; "" when not a studio key.
func shortcut_action(e: InputEventKey) -> String:
	if e.unicode == 63 or (_is(e, KEY_SLASH) and e.shift_pressed): return "help"
	if e.alt_pressed:
		for i in 3:
			if _is(e, [KEY_1, KEY_2, KEY_3][i]) or e.physical_keycode == [KEY_1, KEY_2, KEY_3][i]: return "stage_%d" % i
		return ""
	if _is(e, KEY_TAB): return "stage_prev" if e.shift_pressed else "stage_next"
	if _is(e, KEY_SPACE): return "play"
	if _is(e, KEY_COMMA): return "step_back"
	if _is(e, KEY_PERIOD): return "step_forward"
	var v := _view_key(e)
	if v >= 0: return ["view_front", "view_side", "view_back"][v] + ("_opposite" if e.ctrl_pressed else "")
	if _is(e, KEY_F): return "frame"
	if _is(e, KEY_W): return "gizmo_move"
	if _is(e, KEY_E): return "gizmo_rotate"
	if _is(e, KEY_L): return "loop"
	if _is(e, KEY_P): return "autopose"
	return ""

func run_shortcut(act: String) -> void:
	match act:
		"help": toggle_help()
		"stage_0", "stage_1", "stage_2": set_stage(int(act.right(1)))
		"stage_next", "stage_prev":
			if _ok() and engine._has_motion(): set_stage(posmod(stage + (1 if act == "stage_next" else -1), 3))
		"play": _timeline.toggle_play()
		"step_back": _timeline.step(-1)
		"step_forward": _timeline.step(1)
		"view_front", "view_side", "view_back", "view_front_opposite", "view_side_opposite", "view_back_opposite":
			view(act.trim_prefix("view_"))
		"frame": frame_pose()
		"gizmo_move": set_gizmo_mode(0)
		"gizmo_rotate": set_gizmo_mode(1)
		"autopose": set_autopose_mode(not autopose_on)
		"loop": _timeline.loop_toggle.button_pressed = not _timeline.loop_toggle.button_pressed
		"undo": undo()
		"redo": redo()
		"save":
			commit_pending_text()
			save(_message.text)

func _handled() -> void:
	_root.get_viewport().set_input_as_handled()

# ================================================================ paddle hand, paddle tip

## The paddle hand id on a stroke pose ("" on body stances / serves: no paddle channels there).
func main_hand_id() -> String:
	if not _ok() or engine._edit == null or engine._base: return ""
	return "left_hand" if int(engine._edit.get("paddle_hand")) == 1 else "right_hand"

## engine.studio_gizmo_override: the paddle hand's Move gizmo becomes the paddle's own X / Y / Z
## (POS fields, engine _drag_selected_gizmo path: stage routing, clamps) in the stance frame,
## so the arrows never turn with the paddle. Alt (hand_slide) keeps the engine's grip slide.
func _gizmo_override(id: String, mode: int, _channels: Dictionary) -> Dictionary:
	if mode != 0 or hand_slide or id == "" or id != main_hand_id(): return {}
	var axes: Array = []
	for i in 3:
		if engine._edit.get(POS[i]) == null: return {}
		axes.append({"field": POS[i], "component": -1, "label": ["X", "Y", "Z"][i]})
	var world: Array[Vector3] = GizmoAxes.for_selection(preview.player, preview.pose, "paddle", false)
	var note := "Hand + paddle: forehand side / up / toward net · hold Alt to slide the grip along the handle"
	if gameplay_locked(POS[0]): note = "Locked at Contact (gameplay: contact point) · turn on Gameplay edit to move · " + note
	return {"channels": {"axes": axes, "space": "stance", "note": note}, "axes": world}

func set_hand_slide(on: bool) -> void:
	if on == hand_slide or not _ok(): return
	if _view_input and _view_input.drag != _view_input.Drag.NONE: return   # fixed for the whole drag
	hand_slide = on
	if preview.selected_joint == main_hand_id():
		engine._sync_selected_gizmo(); _update_joint_label()

## Gameplay lock (user rule: posing changes the animation only). Without Gameplay edit:
## paddle position and face fields at Contact (wind-up / finish store animation deltas: free),
## and zones / floor clearance / timing at every key (one value for the whole stroke).
func gameplay_locked(field: String) -> bool:
	if not _ok(): return false
	# Ball actions: only the pickup Grab hand is fixed (the game puts it on the ball).
	if engine.get("_action"): return field == "left_hand_offset" and engine._stage == 1 and int(engine._current.action_id) == 0
	if gameplay_edit: return false
	if field in POS or field in FACE_FIELDS: return not engine._base and engine._stage == 1
	return field in GAMEPLAY_FIELDS

func set_gameplay_edit(on: bool) -> void:
	gameplay_edit = on
	autopose_paddle_free = on   # Gameplay edit on frees the Contact paddle for AutoPose (re-pin with its lock); off pins it again
	_refresh_ap_pins()
	if _gameplay_btn:
		_gameplay_btn.set_pressed_no_signal(on)
		for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			if on: _gameplay_btn.add_theme_color_override(c, Ui.RED)
			else: _gameplay_btn.remove_theme_color_override(c)
		_gameplay_btn.text = "Gameplay edit ON" if on else "Gameplay edit"
	_set_status("Gameplay edit ON: contact paddle, zones and timing can change (changes how shots play)." if on
		else "Gameplay edit off: animation only.")
	_needs_sync = true
	if _ok(): engine._sync_selected_gizmo(); _update_joint_label()

## End the open viewport drag (gizmo / paddle tip) as one undo step: called before a stage or
## pose switch and play / scrub, so no drag keeps writing into another key.
func stop_drag() -> void:
	if _view_input != null and _view_input.drag in [_view_input.Drag.GIZMO, _view_input.Drag.TIP, _view_input.Drag.AUTOPOSE, _view_input.Drag.PATH]:
		_view_input.finish_drag()
	if _autopose != null and _autopose.active: _autopose.release(false)   # a link-driven solve (no UI drag)
	_aim = {}

## AutoPose solver (Stage 6b; link `autopose`, drag UI in AutoPose mode).
func autopose_solver():
	if _autopose == null: _autopose = AutoPose.new(self)
	return _autopose

# ---------------------------------------------------------------- AutoPose mode (drag UI)

## AutoPose mode: the viewport shows AutoPose handles instead of joint dots, the tip diamond and
## the gizmo (studio view state only; the engine's gizmo setting is not written).
func set_autopose_mode(on: bool) -> void:
	if not _ok(): return
	if _view_input and _view_input.drag != _view_input.Drag.NONE:   # no mode switch mid-drag
		if _ap_toggle: _ap_toggle.set_pressed_no_signal(autopose_on)
		return
	autopose_on = on
	if _ap_toggle: _ap_toggle.set_pressed_no_signal(on)
	if _ap_bar: _ap_bar.visible = on
	_refresh_ap_pins()
	_apply_autopose_view()
	_set_status("AutoPose on: drag a handle and the body follows (animation only). P or the toolbar button leaves." if on
		else "AutoPose off: joint dots and gizmo.")
	if _view_input:
		_view_input.hover_joint = ""; _view_input.hover_ap = ""; _view_input.queue_redraw()
	_update_joint_label()

func set_autopose_balance(on: bool) -> void:
	autopose_balance = on
	if _ap_balance: _ap_balance.set_pressed_no_signal(on)
	if _ok(): _update_joint_label()

func set_autopose_look(on: bool) -> void:
	autopose_look = on
	if _ap_look: _ap_look.set_pressed_no_signal(on)
	if _ok(): _update_joint_label()

func set_autopose_regions_shown(on: bool) -> void:
	if _ap_regions: _ap_regions.set_pressed_no_signal(on)
	if _ap_region_seg: _ap_region_seg.visible = on

## Stiffness multiplier for "all", "arms", "torso" or "legs" (0.25 .. 4, 1 = tuned default).
func set_autopose_stiffness(id: String, v: float) -> void:
	if not autopose_stiffness.has(id): return
	v = clampf(v, 0.25, 4.0)
	autopose_stiffness[id] = v
	var row: Array = _ap_sliders.get(id, [])
	if not row.is_empty():
		if not is_equal_approx(row[0].value, v): row[0].set_value_no_signal(v)
		row[1].text = "%.2fx" % v

## Solver options for an AutoPose drag / Relax from the bar: balance, stiffness, pins (user pins;
## feet default on; the Contact paddle stays pinned unless Gameplay edit is on and it was
## unpinned), head look-at point.
func autopose_options() -> Dictionary:
	var pins: Array = []
	for id in autopose_pins:
		if autopose_pins[id]: pins.append({"joint": id})
	var unpin: Array = []
	for f in ["right_foot", "left_foot"]:
		if not autopose_pins.get(f, false): unpin.append(f)
	if autopose_paddle_free and gameplay_edit: unpin.append("paddle")
	var o := {"balance": autopose_balance, "stiffness": autopose_stiffness.duplicate(), "pins": pins, "unpin": unpin}
	if autopose_look:
		var lp := autopose_look_point()
		if lp.is_finite(): o["look_at"] = lp
	return o

## Where the head looks (Look at ball): the ball of the engine's contact illustration
## (mobile_pose_contact_preview.gd ball_position_at, from the solved Contact paddle) at this
## key: wind-up = the incoming ball (1.65 m out along the face), contact = the contact point,
## finish = the outgoing ball (1.8 m toward the net). INF on a body stance (no ball).
func autopose_look_point() -> Vector3:
	if not _ok() or engine._base or preview == null or preview.player == null: return Vector3.INF
	if engine._motion_dirty: engine._refresh_preview()
	var gt: Array = preview.ghost_transforms
	if gt.size() != 3: return Vector3.INF
	var t1: Transform3D = gt[1]
	var fwd: Vector3 = preview.player._get_forward_axis().normalized()
	var n: Vector3 = t1.basis.z.normalized()
	if n.dot(fwd) < 0.0: n = -n
	var c: Vector3 = t1 * PaddleDims.HEAD_OFFSET + n * (PaddleDims.HEAD_HALF_THICKNESS + Ball.BALL_RADIUS)
	match engine._stage:
		0: return c + n * 1.65    # incoming (contact preview ball_position_at(0))
		2: return c + fwd * 1.8   # outgoing (ball_position_at(1))
	return c

## The handle is pinned at this key: user pins, plus at Contact the paddle hand and tip (the
## contact point) unless Gameplay edit is on and the paddle was unpinned.
func autopose_pinned(id: String) -> bool:
	if _contact_paddle_handle(id): return not (autopose_paddle_free and gameplay_edit)
	return bool(autopose_pins.get(id, false))

func _contact_paddle_handle(id: String) -> bool:
	if not _ok() or engine._base or engine._stage != 1: return false
	var main := main_hand_id()
	return id == "paddle_tip" or id in ViewportInput.AP_EDGES or (main != "" and id == main)

## Pin / unpin an AutoPose handle (lock icon click; link toggle autopose_pin). on = null flips.
## The Contact paddle (paddle hand, paddle tip) unpins only with Gameplay edit on.
func set_autopose_pin(id: String, on = null) -> Dictionary:
	if not (id in ViewportInput.AP_IDS): return {"ok": false, "error": "unknown handle: " + id}
	if _editing_drag(): return {"ok": false, "error": "pins change between drags"}
	var nm: String = String(ViewportInput.AP_NAMES.get(id, id))
	var want: bool = (not autopose_pinned(id)) if on == null else bool(on)
	if _contact_paddle_handle(id):
		if not want and not gameplay_edit:
			_set_status("The Contact paddle is the contact point (gameplay). Turn on Gameplay edit to move it with AutoPose.")
			return {"ok": false, "error": "Contact paddle is pinned (gameplay): turn on Gameplay edit to unpin it", "locked": true, "pinned": true}
		autopose_paddle_free = not want
		_set_status("Contact paddle unpinned: AutoPose drags may move the contact point (gameplay)." if not want else "Contact paddle pinned.")
	else:
		if want: autopose_pins[id] = true
		else: autopose_pins.erase(id)
		_set_status("%s pinned: it holds its place while you drag other handles." % nm if want else "%s unpinned." % nm)
	_refresh_ap_pins()
	return {"ok": true, "handle": id, "pinned": autopose_pinned(id)}

## AutoPose bar state (link `autopose {config}` / `autopose_handles`).
func autopose_config() -> Dictionary:
	var eff: Array = []
	for id in ViewportInput.AP_IDS:
		if autopose_pinned(id): eff.append(id)
	var lp := autopose_look_point() if autopose_look else Vector3.INF
	return {"balance": autopose_balance, "look": autopose_look, "stiffness": autopose_stiffness.duplicate(),
		"pins": eff, "user_pins": autopose_pins.keys(), "paddle_free": autopose_paddle_free and gameplay_edit,
		"look_point": [lp.x, lp.y, lp.z] if lp.is_finite() else null, "regions_shown": _ap_region_seg != null and _ap_region_seg.visible}

## A viewport drag that edits the pose is open (gizmo, paddle tip, AutoPose; not orbit / pan).
func _editing_drag() -> bool:
	return _view_input != null and _view_input.drag in [ViewportInput.Drag.GIZMO, ViewportInput.Drag.TIP, ViewportInput.Drag.AUTOPOSE]

func reset_autopose_pins() -> void:
	if _editing_drag(): return
	autopose_pins = {"right_foot": true, "left_foot": true}
	autopose_paddle_free = false
	_refresh_ap_pins()
	_set_status("Pins reset: both feet%s." % (" and the Contact paddle" if _contact_paddle_handle("paddle_tip") else ""))

func _refresh_ap_pins() -> void:
	if _ap_pin_label != null:
		var names: Array = []
		for id in ViewportInput.AP_IDS:
			if autopose_pinned(id): names.append(String(ViewportInput.AP_NAMES[id]))
		_ap_pin_label.text = "Pins: %d" % names.size()
		_ap_pin_label.tooltip_text = ("Pinned: " + ", ".join(names) if not names.is_empty() else "Nothing pinned") \
			+ ". Click the lock next to a handle (or Alt+click the handle) to pin it: a pinned handle holds its place while you drag others."
	if _view_input: _view_input.queue_redraw()

## Relax (AutoPose bar): re-settle the current key toward the checker's rules (solver relax())
## with pins and gameplay fields held, committed as one undo step ("relax"). Reply: the solver
## report (rules_before / rules_after, violations, cost) + release.
func autopose_relax() -> Dictionary:
	if not _ok() or key == "": return {"ok": false, "error": "no pose selected"}
	if not at_key(): 
		_set_status("Relax: go to a key (wind-up, contact, finish) first")
		return {"ok": false, "error": "go to a key (wind-up, contact, finish) to relax"}
	if _editing_drag():
		_set_status("Relax: finish the drag first")
		return {"ok": false, "error": "finish the drag first"}
	if _compare != null: compare_end()
	if _txn != null: end_edit()
	var ap = autopose_solver()
	if ap.active: ap.release(false)
	var r: Dictionary = ap.relax(autopose_options())
	if not r.get("ok", false):
		_set_status("Relax: " + str(r.get("error", "failed")))
		return r
	var t_rel := Time.get_ticks_usec()
	var rel: Dictionary = ap.release(int(r.get("fields", 0)) > 0, true)
	r["release_usec"] = Time.get_ticks_usec() - t_rel
	var keep := {}
	for k in ["committed", "changes", "stopped", "first_stops", "kept", "commit_vs_prediction_m"]:
		if rel.has(k): keep[k] = rel[k]
	r["release"] = keep
	if rel.has("first_stops") or not (rel.get("stopped", []) as Array).is_empty():
		# Cut short: report the pose that was committed, not the solver's prediction.
		var now: Dictionary = ap.flags_now()
		r["predicted_flags_after"] = r.flags_after; r["predicted_rules_after"] = r.rules_after
		r.flags_after = now.flags; r.rules_after = now.rules
	last_relax = r
	_needs_sync = true
	# Checker flags (tools/pose_check.py thresholds) fixed / left, in words.
	var fixed: Array = (r.flags_before as Array).filter(func(v): return not (v in r.flags_after)).map(func(v): return str(v).replace("_", " "))
	var left: Array = (r.flags_after as Array).map(func(v): return str(v).replace("_", " "))
	if int(r.get("fields", 0)) == 0:
		_set_status("Relax: nothing to change at this key" + (" (still flagged: %s, held by pins or limits)" % ", ".join(left) if not left.is_empty() else " (checker rules met)"))
	else:
		_set_status("Relax: %d field(s)%s%s%s · Cmd+Z undoes it" % [int(rel.get("changes", 0)),
			(", fixed " + ", ".join(fixed)) if not fixed.is_empty() else "", (", still flagged " + ", ".join(left)) if not left.is_empty() else "",
			(", kept %d%% (foot-plant / reach check stopped %s)" % [roundi(float(rel.get("kept", 1.0)) * 100.0),
				", ".join((rel.first_stops as Array).map(func(x): return str(x.field)))]) if rel.has("first_stops") else ""])
	_update_joint_label()
	return r

func _apply_autopose_view() -> void:
	if not _ok(): return
	preview.cancel_gesture()
	engine._gizmo_show.set_pressed_no_signal(not autopose_on)   # not _toggle_gizmo: that writes user:// view settings
	engine._sync_selected_gizmo()

## Why a handle cannot be dragged at this key ("" = it can). Gameplay rule: at Contact the paddle
## hand and paddle tip are the contact point: AutoPose moves them only with Gameplay edit on and the
## paddle unpinned (user decision 2026-11-21: edit contact points in AutoPose).
func autopose_lock_reason(h: String) -> String:
	if not _ok() or key == "": return "no pose"
	var edge: bool = h in ViewportInput.AP_EDGES
	if (h == "paddle_tip" or edge) and not tip_available(): return "no paddle on this pose"
	var main := "left" if main_hand_id() == "left_hand" else "right"
	if engine._stage == 1 and not engine._base and (h == main + "_hand" or h == "paddle_tip" or edge) and not (gameplay_edit and autopose_paddle_free):
		return "Contact paddle (gameplay): turn on Gameplay edit to %s" % ("roll the contact face" if edge else "move the contact point")
	return ""

func _autopose_hint() -> String:
	var vi = _view_input
	if not at_key(): return "AutoPose · go to a key (wind-up, contact, finish) to pose · P leaves"
	var contact: bool = not engine._base and engine._stage == 1
	if vi != null and vi.drag == vi.Drag.AUTOPOSE:
		var parts: Array = ["AutoPose", String(vi.AP_NAMES.get(vi.ap_handle, vi.ap_handle))]
		var main := "left" if main_hand_id() == "left_hand" else "right"
		if vi.ap_handle == main + "_elbow":
			parts.append("paddle fixed: arm and torso reshape around it" if contact else "forearm, hand and paddle go along")
		var last: Dictionary = last_autopose.get("last", {})
		if not last.is_empty():
			parts.append("%.1f cm off" % (float(last.get("target_err_m", 0.0)) * 100.0))
		if autopose_balance and str(last.get("stop", "")) == "converged" and float(last.get("target_err_m", 0.0)) > 0.01 \
				and float(last.get("balance_after_m", 0.0)) >= maxf(0.05, float(last.get("balance_before_m", 0.0))) - 0.001:
			parts.append("held by Balance")
		parts.append("Shift = depth · Esc / right-click cancels")
		return " · ".join(parts)
	var t := "AutoPose · drag a handle, the body follows · lock icon (or Alt+click) pins · Shift = depth · Esc / right-click cancels · P leaves"
	if contact: t += (" · Contact point free (Gameplay edit): dragging the hand or tip moves it" if gameplay_edit and autopose_paddle_free else " · Contact: paddle pinned (Gameplay edit frees it)")
	return t

## Start a viewport AutoPose drag on handle `h` (the solver's begin). Refused when locked, not at
## a key, or when no animation field moves the handle at this pose.
func autopose_drag_begin(h: String) -> Dictionary:
	if not _ok() or key == "": return {"ok": false, "error": "no pose selected"}
	if not at_key(): return {"ok": false, "error": "go to a key (wind-up, contact, finish) to pose"}
	var why := autopose_lock_reason(h)
	var hn: String = String(ViewportInput.AP_NAMES.get(h, h))
	if why != "": return {"ok": false, "error": "%s is locked: %s" % [hn, why], "locked": true}
	if _compare != null: compare_end()
	if _txn != null: end_edit()
	var ap = autopose_solver()
	var opts := autopose_options()
	# The contact point moves only when its own handle (paddle hand / tip) is dragged; other
	# handles reshape the body around it, as without Gameplay edit.
	if not _contact_paddle_handle(h): (opts.unpin as Array).erase("paddle")
	var b: Dictionary = ap.begin(h, opts)
	if not b.get("ok", false): return b
	var mob: float = ap.handle_mobility()
	if mob < AP_MIN_MOBILITY:
		ap.release(false)
		return {"ok": false, "immobile": true, "mobility": mob,
			"error": "%s cannot move at this pose: no animation field moves it (it rides the gameplay paddle)" % hn}
	ap.budget_usec = AP_BUDGET_USEC
	last_autopose = {"handle": h, "key": key, "stage": STAGES[engine._stage], "moves": 0, "usec": [], "last": {},
		"result": "dragging", "balance": autopose_balance, "carry": b.get("carry", false), "grab_usec": b.get("grab_usec", 0), "n_params": b.get("n", 0),
		"contact_excluded": (b.get("contact_excluded", []) as Array).size(), "mobility": mob, "handle_start": b.get("handle_start")}
	_update_joint_label()
	return b

## One mouse move of the viewport drag: the solver moves the handle toward `target` (world).
func autopose_drag_move(target: Vector3) -> Dictionary:
	if _autopose == null or not _autopose.active: return {"ok": false, "error": "no AutoPose drag"}
	var r: Dictionary = _autopose.move(target)
	if r.get("ok", false):
		last_autopose.moves = int(last_autopose.get("moves", 0)) + 1
		var us: Array = last_autopose.get("usec", [])
		if us.size() < AP_USEC_KEEP: us.append(int(r.usec))
		var keep := {}
		for k in ["target_err_m", "feet_drift_m", "paddle_drift_m", "balance_before_m", "balance_after_m", "stop", "iters", "evals", "usec", "clamped"]:
			keep[k] = r.get(k)
		keep["target"] = target; keep["handle_at"] = r.get("handle_at")
		last_autopose.last = keep
		_update_joint_label()
	else:
		last_autopose.result = "ended: " + str(r.get("error", ""))
	return r

## End the viewport drag. commit: one undo step (the solver's release through set_field), only
## while the drag still edits its own key (same pose, key, working copy); else the preview goes
## back to the pose from before the drag and nothing is written.
func autopose_drag_end(commit: bool, why: String) -> Dictionary:
	if _autopose == null or not _autopose.active: return {}
	var ap = _autopose
	var valid: bool = ap.key == key and ap.stage == engine._stage and at_key() and _sig(engine._current) == ap._sig
	var t_rel := Time.get_ticks_usec()
	var r: Dictionary = ap.release(commit and valid, true)
	last_autopose.release_usec = Time.get_ticks_usec() - t_rel
	last_autopose.result = why if (commit and valid) or not commit else why + " (not committed: the key changed)"
	var keep := {}
	for k in ["committed", "changes", "stopped", "first_stops", "kept", "backoff_usec", "commit_vs_prediction_m", "handle_commit_vs_prediction_m", "restore_vs_grab_m"]:
		if r.has(k): keep[k] = r[k]
	last_autopose.release = keep
	_needs_sync = true
	_update_joint_label()
	if commit and valid:
		var st: Array = r.get("stopped", [])
		var kept := float(r.get("kept", 1.0))
		var nm: String = String(_view_input.AP_NAMES.get(ap.handle, ap.handle)) if _view_input else ap.handle
		if r.has("first_stops"):
			_set_status("AutoPose %s: the foot-plant check stopped %s, so %d%% of the drag was kept%s · Cmd+Z undoes it" % [nm,
				str((r.first_stops as Array).map(func(x): return str(x.field))), roundi(kept * 100.0), "" if st.is_empty() else " (%d still stopped)" % st.size()])
		else:
			_set_status("AutoPose %s: %d field(s) changed · Cmd+Z undoes the drag" % [nm, int(r.get("changes", 0))] if int(r.get("changes", 0)) > 0
				else ("AutoPose %s: click and drag to move it" % nm if int(last_autopose.get("moves", 0)) == 0
				else "AutoPose %s: nothing changed (the drag was held by Balance or a limit)" % nm))
	elif not commit: _set_status("AutoPose drag cancelled: pose back to before the drag")
	return r

## The drag still edits the key it began on (same pose, same stage, at that key).
func _drag_valid() -> bool:
	if not at_key(): return false
	if _txn != null and (_txn.key != key or int(_txn.stage) != engine._stage): return false
	return true

## engine.studio_edit_guard: one gizmo drag step on `field`; false refuses it (nothing written).
func _edit_guard(field: String) -> bool:
	if not _drag_valid():
		stop_drag.call_deferred(); return false
	if gameplay_locked(field):
		_set_status("Locked: %s is a gameplay field at Contact. Turn on Gameplay edit (top bar) to change it." % field)
		return false
	return true

## Edits only at a key (same rule as the engine's gizmo).
func at_key() -> bool:
	return _ok() and not engine._playing and not engine._timeline.active and engine._variant_mode == 0 \
		and is_equal_approx(engine._progress, float(engine._stage) * 0.5)

func tip_available() -> bool:
	return main_hand_id() != "" and engine._edit.get("paddle_pitch_base_deg") != null

## Drag-time warning for the view hint: at Contact the paddle position (and face) are gameplay.
func drag_warning() -> String:
	if _view_input == null or not _ok() or engine._base or engine._stage != 1: return ""
	var lock := "" if gameplay_edit else " (locked: Gameplay edit off)"
	match _view_input.drag_kind:
		"pos": return "gameplay field: contact point" + lock
		"rot": return "gameplay field: contact point / face" + lock
	return ""

## Hint only (an overlay on the preview): a status-line change can re-wrap it and resize the
## preview, which cancels the engine gizmo's drag.
func drag_changed() -> void:
	_update_joint_label()
	if _layout_after_drag and _view_input.drag == _view_input.Drag.NONE:
		_layout_after_drag = false; _queue_layout()

## Shift+tip drag: move the whole paddle by a world offset, split on the paddle gizmo's stance
## axes and applied like its Move arrows (engine _changed per POS field, field range clamp).
func move_paddle(delta: Vector3) -> void:
	if not _ok(): return
	if not _drag_valid(): stop_drag(); return
	if gameplay_locked(POS[0]):
		_set_status("Locked: the Contact paddle position is gameplay. Turn on Gameplay edit (top bar) to move it."); return
	var prev_group: int = engine._group.selected
	engine._group.select(6)
	var changed := _shift_paddle(delta)
	engine._group.select(prev_group)
	if changed:
		engine._refresh_preview(); engine._refresh_status()
		_after_change(true)

## Tip drag start: remember the grip (paddle hand, in paddle space) and where it must stay.
func aim_begin() -> void:
	var t: Transform3D = preview.player.paddle_node.global_transform
	var hand: Vector3 = preview.joint_world_position(main_hand_id())
	_aim = {"grip_local": t.affine_inverse() * hand, "pin": hand, "key": key, "stage": engine._stage,
		"prev": Vector2(float(engine._edit.get("paddle_pitch_base_deg")), float(engine._edit.get("paddle_yaw_base_deg")))}

## Tip drag: aim the paddle so its tip lands on `target` (preview points), pitch / yaw only (roll
## untouched). Continuity: every mouse move starts from the previous move's angles (the working
## copy) and minimises  err_px^2 + AIM_LAMBDA * |angles - start|^2  (deg), so the branch nearest
## the previous solution wins and an out-of-reach target settles (a step is kept only when that
## cost drops: no 2-cycles at a fixed point); the change per move is capped at AIM_MOVE_DEG, and
## for a mouse move under AIM_FINE_PX at AIM_FINE_DEG per pixel moved (a 1 px wiggle turns the
## paddle under 1 degree). A mouse held still (the same point again) solves with the small
## AIM_HOLD_LAMBDA instead, so the tip settles on the mouse in a move or two and then stays (a
## fixed point: no creep). Candidates: a closed-form seed on the
## engine's gizmo axes (both pitch branches), then damped Gauss-Newton (at most AIM_ITERS steps /
## AIM_BUDGET_USEC). Each step goes through the ROT gizmo's own setter (_rotate_paddle_axis: stage
## routing, wrist seating), then the POS fields re-seat the grip on the pin (like the Move arrows),
## so the grip stays put and the arm follows through the engine's IK. Evaluation uses the engine's
## own paddle placement (Path.world_transform of the edited key); the preview refreshes once per frame.
func aim_paddle_tip(target: Vector2) -> Dictionary:
	if not _ok() or _view_input == null or _aim.is_empty(): return {}
	if not _drag_valid() or str(_aim.get("key", "")) != key or int(_aim.get("stage", -1)) != engine._stage:
		stop_drag(); return {}
	if gameplay_locked("paddle_pitch_base_deg"):
		_set_status("Locked: the Contact paddle face is gameplay. Turn on Gameplay edit (top bar) to aim it."); return {}
	var t0 := Time.get_ticks_usec()
	var player = preview.player
	var grip_local: Vector3 = _aim.grip_local
	var pin: Vector3 = _aim.pin
	var prev_group: int = engine._group.selected
	engine._group.select(6)
	engine._rotation_refresh_pending = true   # the engine queues no flush; _aim_flush runs once per frame
	var iters := 0
	var start: Vector2 = _aim_angles_now()     # previous move's solution: warm start + proximity anchor
	var last_px: Vector2 = _aim.get("last_px", Vector2.INF)
	var moved_px: float = last_px.distance_to(target) if last_px.is_finite() else INF
	_aim["last_px"] = target
	var held: bool = moved_px < 0.01
	var cap_deg: float = AIM_MOVE_DEG if moved_px > AIM_FINE_PX or held else AIM_FINE_DEG * moved_px
	var lam: float = AIM_HOLD_LAMBDA if held else AIM_LAMBDA
	var err: Vector2 = _aim_err(target)
	if not err.is_finite():
		engine._group.select(prev_group); engine._rotation_refresh_pending = false; return {}
	var cost: float = err.length_squared()
	if err.length() <= AIM_TOL_PX:   # already on the mouse: hold still (no drift along the free direction)
		engine._group.select(prev_group); engine._rotation_refresh_pending = false
		last_aim = {"usec": Time.get_ticks_usec() - t0, "iters": 0, "err_px": err.length(), "refresh_usec": last_aim.get("refresh_usec"),
			"pitch": start.x, "yaw": start.y, "turn_deg": 0.0}
		return last_aim
	# 1) Closed-form aim on the engine's own axes (pitch about the forehand axis, yaw about the
	#    pitched up axis: GizmoAxes): the tip goes to where the mouse ray meets the sphere the
	#    tip can reach around the grip. Rigid prediction; the cost keeps the nearest branch.
	var t_now: Transform3D = Path.world_transform(player, engine._edit)
	var v: Vector3 = t_now * _view_input.TIP_LOCAL - t_now * grip_local
	var axes0: Array[Vector3] = GizmoAxes.for_selection(player, engine._edit, "paddle", true)
	var ab := Vector2.ZERO
	var ab_cost := cost
	var exact := Vector2.INF        # uncapped candidate with the smallest predicted error (branch switch when stuck)
	var exact_err := INF
	for goal in _sphere_points(target, pin, v.length()):
		for cand in _aim_angles(v, goal - pin, axes0[0], axes0[1]):
			var dd := Vector2(rad_to_deg(cand.x), rad_to_deg(cand.y))
			var full_tip: Vector3 = pin + v.rotated(axes0[1].normalized(), cand.y).rotated(axes0[0].normalized(), cand.x)
			var fe: float = preview._world_screen_position(full_tip).distance_to(target)
			if fe < exact_err: exact_err = fe; exact = dd
			if dd.length() > cap_deg: dd = dd * (cap_deg / dd.length())
			var r := Vector2(deg_to_rad(dd.x), deg_to_rad(dd.y))
			var tip: Vector3 = pin + v.rotated(axes0[1].normalized(), r.y).rotated(axes0[0].normalized(), r.x)
			var c: float = preview._world_screen_position(tip).distance_squared_to(target) + lam * dd.length_squared()
			if c < ab_cost: ab_cost = c; ab = dd
	if ab.length() > 0.03:
		var snap := _aim_state()
		_aim_turn(ab, grip_local, pin)
		var e1: Vector2 = _aim_err(target)
		var c1: float = e1.length_squared() + lam * _angle_gap(_aim_angles_now(), start).length_squared() if e1.is_finite() else INF
		if c1 < cost: cost = c1; err = e1; iters += 1
		else: _aim_restore(snap)
	# 2) Damped Gauss-Newton on  err^2 + lambda |angles - start|^2  for what the engine's limits
	#    leave over; a step that does not lower the cost is undone and ends the move.
	for i in AIM_ITERS:
		if err.length() <= AIM_TOL_PX or Time.get_ticks_usec() - t0 > AIM_BUDGET_USEC: break
		var t: Transform3D = Path.world_transform(player, engine._edit)
		var tip: Vector3 = t * _view_input.TIP_LOCAL
		var s: Vector2 = preview._world_screen_position(tip)
		if not s.is_finite(): break
		# Screen Jacobian (points per degree): the engine's own angular axes for pitch / yaw,
		# turning about the grip.
		var r: Vector3 = tip - t * grip_local
		var axes: Array[Vector3] = GizmoAxes.for_selection(player, engine._edit, "paddle", true)
		var ja: Vector2 = preview._world_screen_position(tip + axes[0].cross(r) * deg_to_rad(1.0)) - s
		var jb: Vector2 = preview._world_screen_position(tip + axes[1].cross(r) * deg_to_rad(1.0)) - s
		if not (ja.is_finite() and jb.is_finite()): break
		var off: Vector2 = _angle_gap(_aim_angles_now(), start)
		# Marquardt damping (per column) + the proximity weight (also the near-singular floor).
		var a11: float = ja.dot(ja) * (1.0 + AIM_DAMP) + lam
		var a12: float = ja.dot(jb)
		var a22: float = jb.dot(jb) * (1.0 + AIM_DAMP) + lam
		var det: float = a11 * a22 - a12 * a12
		if det <= 1e-9: break
		var b1: float = ja.dot(err) - lam * off.x
		var b2: float = jb.dot(err) - lam * off.y
		var step := Vector2((a22 * b1 - a12 * b2) / det, (a11 * b2 - a12 * b1) / det)
		if step.length() > AIM_STEP_DEG: step = step.normalized() * AIM_STEP_DEG
		var total: Vector2 = off + step
		if total.length() > cap_deg: step = total * (cap_deg / total.length()) - off
		if step.length() < 0.001: break
		var snap2 := _aim_state()
		_aim_turn(step, grip_local, pin)
		var e2: Vector2 = _aim_err(target)
		var c2: float = e2.length_squared() + lam * _angle_gap(_aim_angles_now(), start).length_squared() if e2.is_finite() else INF
		if c2 >= cost - 1e-4: _aim_restore(snap2); break
		cost = c2; err = e2; iters += 1
	# 3) Stuck on a branch that cannot reach the mouse while the other one can: switch once (kept
	#    only if the real error drops 4x, so the error never grows at a fixed mouse point: no cycles).
	if iters == 0 and moved_px > AIM_FINE_PX and err.length() > 8.0 and exact.is_finite() and exact_err < 2.0:
		var snap3 := _aim_state()
		_aim_turn(exact, grip_local, pin)
		var e3: Vector2 = _aim_err(target)
		if e3.is_finite() and e3.length() < 0.25 * err.length(): err = e3; iters += 1
		else: _aim_restore(snap3)
	engine._group.select(prev_group)
	if iters > 0 and not _aim_flush_queued:
		_aim_flush_queued = true; _aim_flush.call_deferred()
	elif iters == 0: engine._rotation_refresh_pending = false
	var usec := Time.get_ticks_usec() - t0
	PerfMonitor.record("studio.tip_aim", usec)
	var now: Vector2 = _aim_angles_now()
	last_aim = {"usec": usec, "iters": iters, "err_px": err.length() if err.is_finite() else null, "refresh_usec": last_aim.get("refresh_usec"),
		"pitch": now.x, "yaw": now.y, "turn_deg": _angle_gap(now, start).length()}
	if iters > 0: _after_change(true)
	return last_aim

func _aim_angles_now() -> Vector2:
	return Vector2(float(engine._edit.get("paddle_pitch_base_deg")), float(engine._edit.get("paddle_yaw_base_deg")))

## Wrapped difference of two (pitch, yaw) pairs in degrees.
func _angle_gap(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(wrapf(a.x - b.x, -180.0, 180.0), wrapf(a.y - b.y, -180.0, 180.0))

## Tip error (preview points) of the edited key's paddle as the engine places it.
func _aim_err(target: Vector2) -> Vector2:
	var t: Transform3D = Path.world_transform(preview.player, engine._edit)
	var s: Vector2 = preview._world_screen_position(t * _view_input.TIP_LOCAL)
	return target - s if s.is_finite() else Vector2.INF

## Turn pitch / yaw by `d` degrees through the ROT gizmo setter, then re-seat the grip on the pin.
func _aim_turn(d: Vector2, grip_local: Vector3, pin: Vector3) -> void:
	if absf(d.x) > 1e-6: engine._rotate_paddle_axis(0, d.x)
	if absf(d.y) > 1e-6: engine._rotate_paddle_axis(1, d.y)
	_shift_paddle(pin - Path.world_transform(preview.player, engine._edit) * grip_local)

## Paddle ROT + POS of the edited key (to undo a rejected aim step exactly).
func _aim_state() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for f in engine.ROT + POS: out.append(float(engine._edit.get(f)))
	return out

func _aim_restore(st: PackedFloat64Array) -> void:
	var names: Array = engine.ROT + POS
	for i in names.size():
		if not is_equal_approx(float(engine._edit.get(names[i])), st[i]): engine._changed(names[i], st[i], false)

## Points on the sphere (centre, radius) under the preview point: both ray hits, or the
## sphere's closest point to the ray when it misses (silhouette).
func _sphere_points(point: Vector2, centre: Vector3, radius: float) -> Array[Vector3]:
	var cam: Camera3D = preview.camera
	var pixel: Vector2 = point * Vector2(preview.viewport.size) / preview.size
	var o: Vector3 = cam.project_ray_origin(pixel)
	var d: Vector3 = cam.project_ray_normal(pixel)
	var m: Vector3 = o - centre
	var b: float = m.dot(d)
	var disc: float = b * b - (m.length_squared() - radius * radius)
	if disc >= 0.0:
		var q := sqrt(disc)
		return [o + d * (-b - q), o + d * (-b + q)]
	var closest: Vector3 = o + d * (-b) - centre
	if closest.length_squared() < 1e-12: return []
	return [centre + closest.normalized() * radius]

## Pitch / yaw changes (radians) that turn v toward t, where the paddle turns as
## Rot(f, pitch) * Rot(u, yaw) * current (f = forehand axis, u = pitched up axis, both from
## GizmoAxes): one per pitch branch. Out of reach (fixed roll): the nearest pitch.
func _aim_angles(v: Vector3, t: Vector3, f: Vector3, u: Vector3) -> Array[Vector2]:
	f = f.normalized(); u = u.normalized()
	t = t.normalized() * v.length()
	var u_par: Vector3 = f * u.dot(f)
	var u_perp: Vector3 = u - u_par
	var A: float = t.dot(u_perp)
	var B: float = t.dot(f.cross(u_perp))
	var C: float = v.dot(u) - t.dot(u_par)
	var r := sqrt(A * A + B * B)
	var pitches: Array[float] = [0.0]
	if r > 1e-9:
		var base := atan2(B, A)
		var spread := acos(clampf(C / r, -1.0, 1.0))
		pitches = [base + spread, base - spread]
	var out: Array[Vector2] = []
	for a0 in pitches:
		var a: float = wrapf(a0, -PI, PI)
		var w: Vector3 = t.rotated(f, -a)
		var vp: Vector3 = v - u * v.dot(u)
		var wp: Vector3 = w - u * w.dot(u)
		if vp.length_squared() < 1e-12 or wp.length_squared() < 1e-12: out.append(Vector2(a, 0.0)); continue
		out.append(Vector2(a, atan2(u.dot(vp.cross(wp)), vp.dot(wp))))
	return out

## Test hook (link `aim_probe`, read-only): the best tip error any pitch / yaw could give for
## `target` with roll and the grip pin as in the current tip drag (or as now): brute-force grid
## over the same model the solver uses. Returns {err_px, pitch, yaw} (absolute base degrees).
func aim_probe(target: Vector2) -> Dictionary:
	if not _ok() or _view_input == null: return {}
	var player = preview.player
	var grip_local: Vector3
	var pin: Vector3
	if _aim.is_empty():
		var t0: Transform3D = player.paddle_node.global_transform
		pin = preview.joint_world_position(main_hand_id()); grip_local = t0.affine_inverse() * pin
	else:
		grip_local = _aim.grip_local; pin = _aim.pin
	var cand: Resource = engine._edit.duplicate(true)
	var best := {"err_px": INF, "pitch": 0.0, "yaw": 0.0}
	var p0 := -180.0; var y0 := -180.0; var span := 360.0; var step := 3.0
	for pass_n in 3:
		var bp: float = best.pitch; var by: float = best.yaw
		var n := int(span / step)
		for i in n + 1:
			for j in n + 1:
				var p := p0 + i * step
				var y := y0 + j * step
				cand.set("paddle_pitch_base_deg", p); cand.set("paddle_yaw_base_deg", y)
				var t: Transform3D = Path.world_transform(player, cand)
				var tip: Vector3 = t * _view_input.TIP_LOCAL + (pin - t * grip_local)
				var e: float = preview._world_screen_position(tip).distance_to(target)
				if e < best.err_px: best = {"err_px": e, "pitch": p, "yaw": y}
		span = step * 4.0; step = span / 40.0
		p0 = best.pitch - span * 0.5; y0 = best.yaw - span * 0.5
	return best

## Once per frame during a tip drag: the engine's own rotation refresh (preview, status, arcs).
func _aim_flush() -> void:
	_aim_flush_queued = false
	if not _ok(): return
	var t0 := Time.get_ticks_usec()
	engine._flush_rotation_preview()
	last_aim["refresh_usec"] = Time.get_ticks_usec() - t0

## Add a world offset to the paddle POS fields (stance axes, field range clamp), engine _changed
## without a refresh. Shared by the tip aim's grip re-seat and the Shift+tip move.
func _shift_paddle(delta: Vector3) -> bool:
	if delta.length_squared() < 1e-14: return false
	var axes: Array[Vector3] = GizmoAxes.for_selection(preview.player, engine._edit, "paddle", false)
	var changed := false
	for i in 3:
		var amount: float = delta.dot(axes[i])
		if absf(amount) < 1e-8: continue
		var d := _descriptor(POS[i])
		var cur := float(engine._edit.get(POS[i]))
		var v := clampf(cur + amount, float(d.get("min", -INF)), float(d.get("max", INF)))
		if not is_equal_approx(v, cur): engine._changed(POS[i], v, false); changed = true
	return changed

# ================================================================ data checks

## Tree of named studio controls (names, types, visibility, values) for checks without images.
func ui_dump() -> Dictionary:
	var tree := _dump(phone_ui if phone and phone_ui else _root)
	var pv := {}
	if preview:
		var gz = preview.gizmo
		var t: Vector3 = preview.camera_target
		var cp: Vector3 = preview.camera.global_position
		pv = {"selected_joint": preview.selected_joint, "yaw": preview.yaw, "pitch": preview.pitch,
			"distance": _view_input.current_distance() if _view_input else preview.distance, "manual_zoom": preview._manual_zoom,
			"target": [t.x, t.y, t.z], "camera": [cp.x, cp.y, cp.z], "size": [preview.size.x, preview.size.y],
			"gizmo_mode": engine._gizmo_mode.selected, "gizmo_enabled": gz.enabled, "gizmo_shown": gz.visible and gz.enabled and is_instance_valid(gz.scene_root) and gz.scene_root.visible,
			"gizmo_modes_available": [not engine._gizmo_mode.is_item_disabled(0), not engine._gizmo_mode.is_item_disabled(1)],
			"ghosts": preview.inbetween_count, "ghosts_visible": preview._ghosts_visible, "arc": preview._arc_visible,
			"contact": _contact_on, "contact_visible": preview.contact_preview != null and preview.contact_preview.visible,
			"second_view": _second.visible, "drag": ViewportInput.Drag.keys()[_view_input.drag] if _view_input else "",
			"hover": _view_input.hover_joint if _view_input else "", "dots": _view_input.dots_state() if _view_input else [],
			"autopose": _view_input.autopose_state() if _view_input else {}, "momentum": _view_input.arc_state() if _view_input else {}}
	return {"ok": true, "ready": is_ready, "key": key, "stage": STAGES[stage], "dirty": _ok() and engine._dirty.has(engine._key),
		"unsaved": unsaved_keys(), "quit_dialog": _quit_dlg != null and _quit_dlg.visible, "undo": _undo.size(), "redo": _redo.size(), "window": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"preview": pv, "timeline": _timeline.state(), "phone_speed_graph": phone_ui._speed_graph.state() if phone and phone_ui and phone_ui._speed_graph else {}, "phone_layout": phone_ui.layout_state() if phone and phone_ui else {}, "phone_scrub": {"size": [phone_ui._scrub.size.x, phone_ui._scrub.size.y], "info": phone_ui._tl_info.text, "key_marks": phone_ui._scrub.key_marks, "at_stage": phone_ui._scrub.at_stage, "marks": phone_ui._scrub.marks, "sel_path": phone_ui._sel_path} if phone and phone_ui else {}, "shortcuts": SHORTCUTS.map(func(s): return {"keys": s[0], "does": s[1], "id": s[2]}),
		"controls": tree}

func _dump(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if not (c is Control): continue
		if c == preview:
			if _view_input: out.append({"name": "Preview", "type": "TextureRect", "visible": c.is_visible_in_tree(),
				"children": [{"name": "JointLabel", "type": "Label", "visible": _joint_label != null and _joint_label.is_visible_in_tree(),
					"text": _joint_label.text if _joint_label else ""}]})
			continue
		var kids := _dump(c)
		if String(c.name).begins_with("@"):
			# Unnamed: keep its children; an unnamed text leaf (a table cell) keeps its text.
			if kids.is_empty() and (c is Label or (c is Button and not c is OptionButton)):
				out.append({"name": "", "type": c.get_class(), "visible": c.is_visible_in_tree(), "text": c.text})
			else: out.append_array(kids)
			continue
		var e := {"name": String(c.name), "type": c.get_class(), "visible": c.is_visible_in_tree()}
		if c is BaseButton:
			e["disabled"] = c.disabled
			if c.toggle_mode: e["pressed"] = c.button_pressed
		if c is OptionButton:
			e["selected"] = c.selected; e["text"] = c.get_item_text(c.selected) if c.selected >= 0 else ""
		elif c is Button: e["text"] = c.text
		elif c is Label: e["text"] = c.text
		elif c is LineEdit: e["text"] = c.text
		if c is Range: e["value"] = c.value
		if c is TabContainer:
			e["current"] = c.current_tab
			var titles: Array = []
			for i in c.get_tab_count(): titles.append(c.get_tab_title(i))
			e["tabs"] = titles
		if c == _pose_list: e.merge(_list_state())
		if c.has_method("state") and c != _inspector: e["state"] = c.state()
		if not kids.is_empty(): e["children"] = kids
		out.append(e)
	return out

## Act on a named control like a user: press (button / toggle), set (range, line edit,
## checkbox), select (option button, pose list by key or index, tab container).
func ui_action(control_name: String, action: String, value = null) -> Dictionary:
	var c: Node = (phone_ui if phone and phone_ui else _root).find_child(control_name, true, false)
	if c == null: return {"ok": false, "error": "no control named " + control_name}
	match action:
		"press":
			if not (c is BaseButton): return {"ok": false, "error": control_name + " is not a button"}
			if c.disabled: return {"ok": false, "error": control_name + " is disabled"}
			# Like a click: a toggle flips (toggled) and then emits pressed.
			if c.toggle_mode: c.button_pressed = (not c.button_pressed) if value == null else bool(value)
			c.pressed.emit()
		"set":
			if c is SpinBox or c is Range: c.value = float(value)
			elif c is LineEdit:   # like typing, then Enter
				c.text = str(value); c.text_changed.emit(c.text); c.text_submitted.emit(c.text)
			elif c is BaseButton and c.toggle_mode: c.button_pressed = bool(value)
			else: return {"ok": false, "error": "cannot set " + control_name}
		"select":
			if c == _pose_list:
				var k := str(value)
				if value is int or value is float or str(value).is_valid_int():
					var defs := _list_defs(); var i := int(value)
					if i < 0 or i >= defs.size(): return {"ok": false, "error": "index out of range"}
					k = PoseDiff.key_of(defs[i])
				var row: TreeItem = null
				if _pose_list.get_root():
					for it in _pose_list.get_root().get_children():
						if str(it.get_metadata(0)) == k: row = it
				if row != null: row.select(0)   # like a click: item_selected -> _on_list_selected (deferred select)
				elif not select_pose(k): return {"ok": false, "error": "cannot select " + k}
			elif c is OptionButton:
				var idx := _option_index(c, value)
				if idx < 0: return {"ok": false, "error": "no item %s in %s" % [str(value), control_name]}
				c.select(idx); c.item_selected.emit(idx)
			elif c is TabContainer: c.current_tab = int(value)
			else: return {"ok": false, "error": "cannot select in " + control_name}
		_: return {"ok": false, "error": "bad action: " + action}
	var after := {"ok": true, "name": control_name}
	var d := _dump(c.get_parent())
	for e in d:
		if e.name == control_name: after["control"] = e
	return after

func _option_index(o: OptionButton, value) -> int:
	if value is int or value is float: return int(value) if int(value) < o.item_count else -1
	for i in o.item_count:
		if o.get_item_text(i) == str(value): return i
	return int(value) if str(value).is_valid_int() and int(value) < o.item_count else -1

# ---------------------------------------------------------------- elbow bake (stage 6c step 2)

## The paddle arm's solved elbow at this key as an elbow swivel angle (scripts/elbow_swivel.gd):
## the value that reproduces it with elbow_swivel_weight 1. deg = null when the arm is straight.
## {ok, field, deg, elbow}
func elbow_bake_target() -> Dictionary:
	if not _ok() or key == "" or not at_key(): return {"ok": false, "error": "go to a key"}
	var p = preview.player
	var left: bool = main_hand_id() == "left_hand"
	var arm = p.left_arm_node if left else p.right_arm_node
	var sh: Vector3 = arm.upper_pivot.global_position
	var el: Vector3 = ElbowSwivel.visual_elbow_now(arm)   # drawn elbow
	var wr: Vector3 = arm.anatomical_wrist_world
	var fr: Array = ElbowSwivel.frame(preview.pose, p._get_forehand_axis(), p._get_forward_axis(), left)
	var deg: float = ElbowSwivel.angle(sh, wr, el, fr[0], fr[1], left)
	return {"ok": true, "field": "left_elbow_swivel_deg" if left else "right_elbow_swivel_deg",
		"deg": null if is_nan(deg) else deg, "elbow": [el.x, el.y, el.z]}

## Write a swivel angle (and weight 1) into this key (one undo step "elbow swivel").
func elbow_set_swivel(deg: float) -> Dictionary:
	if not _ok() or key == "" or not at_key(): return {"ok": false, "error": "go to a key"}
	var field := "left_elbow_swivel_deg" if main_hand_id() == "left_hand" else "right_elbow_swivel_deg"
	if _txn != null: end_edit()
	begin_edit("elbow swivel")
	var a := set_field("elbow_swivel_weight", null, 1.0, false, false)
	var b := set_field(field, null, deg, false, false)
	end_edit()
	engine._refresh_preview()
	return {"ok": a.get("ok", false) and b.get("ok", false), "weight": a, "swivel": b}

## The solved paddle elbow at this key (world), for before / after checks.
func elbow_now() -> Array:
	var p = preview.player
	var arm = p.left_arm_node if main_hand_id() == "left_hand" else p.right_arm_node
	var e: Vector3 = ElbowSwivel.visual_elbow_now(arm)
	return [e.x, e.y, e.z]
