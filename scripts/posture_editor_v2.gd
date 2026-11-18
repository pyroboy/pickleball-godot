class_name PostureEditorV2 extends Control

## Posture Editor v2 — clean-slate rewrite.
## CP4: posture list + selection.

signal editor_opened()
signal editor_closed()
signal posture_selected(def) # emits PostureDefinition or BasePoseDefinition

var _title_label: Label
var _close_button: Button
var _workspace_button: Button
var _posture_list: ItemList
var _status_label: Label
var _selection_label: Label
var _preview_state_label: Label
var _reach_label: Label
var _save_dialog: ConfirmationDialog
var _camera_rig: CameraRig
var _reach_visual: MeshInstance3D

# Data
var _library: PostureLibrary
var _base_pose_library: BasePoseLibrary
var _current_def = null
var _is_base_pose_mode: bool = false

## posture_id → definition for postures that have been modified but not yet saved.
var _dirty_defs: Dictionary = {}

# Player / Preview / Gizmos / Transport
var _player = null
var _pose_trigger = null
var _preview_button: Button
var _swing_button: Button
var _save_button: Button
var _save_all_button: Button
var _zone_move_button: Button
var _gizmo_controller: GizmoControllerV2 = null
var _zone_move_mode: bool = false
var _transition_player: TransitionPlayer = null
var _pose_transition_tween: Tween = null
var _transition_from_def: PostureDefinition = null
var _transition_ready_def: PostureDefinition = null
var _transition_to_def: PostureDefinition = null
var _transition_use_ready: bool = false

# Window geometry save/restore (ported from v1)
var _prev_window_mode: int = Window.MODE_WINDOWED
var _prev_window_size: Vector2i = Vector2i.ZERO
var _prev_window_position: Vector2i = Vector2i.ZERO
var _window_geometry_saved: bool = false

func _init() -> void:
	name = "PostureEditorV2"
	visible = false

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const SwingPath = preload("res://scripts/stroke_swing_path.gd")
const BodyKeyframe = preload("res://scripts/stroke_body_keyframe.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
var _keyframe_index: int = 1
var _keyframe_buttons: Array[Button] = []
var _edit_def: Resource
const KEYFRAME_NAMES = ["Wind-up", "Contact", "Follow-through"]
const PADDLE_POSITION_FIELDS = ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul"]
const PADDLE_ROTATION_FIELDS = ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]
const SwingVisual = preload("res://scripts/posture_editor_v2/swing_path_visual.gd")
var _swing_visual: Node3D
var _swing_controls: PanelContainer
var _swing_scrub: HSlider
var _swing_speed: OptionButton
var _show_reach_limits: CheckButton
var _show_swing_path: CheckButton
var _loop_swing: CheckButton
var _scrubbing: bool = false
var _pose_picker: OptionButton
var _section_picker: OptionButton
var _section_help: Label
var _contact_tab: SimpleInspector
var _help_box: VBoxContainer
var _restore_posture_id: int = -1
var _saved_snapshots: Dictionary = {}
var _revert_button: Button

func _ready() -> void:
	theme = UiTheme.create()
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -610
	offset_right = -12
	offset_top = 12
	offset_bottom = -12
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title_label = Label.new()
	_title_label.text = "Edit poses"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_close_button = _button(header, "Close", close)
	_close_button.tooltip_text = "Close the editor (Esc, E or Q). Unsaved edits ask you to save or discard."

	var mode_row := HBoxContainer.new()
	vbox.add_child(mode_row)
	_workspace_button = _button(mode_row, "Stroke poses", _on_toggle_workspace)
	_workspace_button.tooltip_text = "Switch between the 21 paddle strokes and the body stance library."
	_button(mode_row, "How to use", _toggle_help)
	_help_box = VBoxContainer.new()
	_help_box.visible = false
	vbox.add_child(_help_box)
	var guide := Label.new()
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.text = "Choose a pose and settings section. Paddle grip selects the main hand and whether the other hand joins or releases.\n\nSelect Wind-up, Contact or Follow-through below the court, then edit Body or Paddle. Each button is an editable keyframe. Scrub previews the blended motion; Play swing animates it. Curve blending is in Follow-through.\n\nLeft drag arrows to move or rings to rotate. The box is the contact area; the Reach switch shows the reach limit. Save pose or Save all keeps your edits."
	_help_box.add_child(guide)
	var camera_row := HBoxContainer.new()
	vbox.add_child(camera_row)
	for view in ["Front", "Side", "Top"]:
		_button(camera_row, view, _set_camera_view.bind(view.to_lower()))
	_button(camera_row, "Focus F", _focus_camera)
	_button(camera_row, "Reset R", _reset_camera)
	var camera_help := Label.new()
	camera_help.text = "In court view: right drag orbit · middle drag pan · wheel zoom"
	camera_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camera_help.add_theme_font_size_override("font_size", 18)
	vbox.add_child(camera_help)

	var pose_row := HBoxContainer.new()
	vbox.add_child(pose_row)
	_button(pose_row, "‹", _step_pose.bind(-1)).tooltip_text = "Previous pose"
	_pose_picker = OptionButton.new()
	_pose_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pose_picker.item_selected.connect(_on_posture_selected)
	pose_row.add_child(_pose_picker)
	_button(pose_row, "›", _step_pose.bind(1)).tooltip_text = "Next pose"
	# Keep the selection model independent of the visible picker.
	_posture_list = ItemList.new()
	_posture_list.visible = false
	_posture_list.item_selected.connect(_on_posture_selected)
	add_child(_posture_list)
	_selection_label = Label.new()
	_selection_label.text = "Choose a pose"
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_selection_label)

	_section_picker = OptionButton.new()
	_section_picker.item_selected.connect(_select_section)
	vbox.add_child(_section_picker)
	_section_help = Label.new()
	_section_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section_help.add_theme_font_size_override("font_size", 18)
	_section_help.add_theme_color_override("font_color", Color("bfd4e8"))
	vbox.add_child(_section_help)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.tabs_visible = false
	tabs.tab_changed.connect(_on_tab_changed)
	vbox.add_child(tabs)
	_build_tabs(tabs)
	for title in ["Body & stance", "Paddle position & angle", "Wind-up", "Follow-through", "Contact area"]:
		_section_picker.add_item(title)
	_section_picker.select(1)
	tabs.current_tab = 1

	_zone_move_button = _button(vbox, "Resize contact area", _on_toggle_zone_move)
	_zone_move_button.visible = false
	_preview_state_label = Label.new()
	_preview_state_label.text = "Preview: contact pose"
	vbox.add_child(_preview_state_label)
	_reach_label = Label.new()
	_reach_label.text = "Shared paddle reach: 1.35 m"
	_reach_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_reach_label)
	var preview_row := HBoxContainer.new()
	vbox.add_child(preview_row)
	_preview_button = _button(preview_row, "Show pose", _on_preview_pose)
	_swing_button = _button(preview_row, "Play swing", _on_preview_swing)
	var save_row := HBoxContainer.new()
	vbox.add_child(save_row)
	_save_button = _button(save_row, "Save pose", _on_save)
	_revert_button = _button(save_row, "Revert pose", _on_revert_pose)
	_revert_button.tooltip_text = "Restore this pose to its last saved settings."
	_save_all_button = _button(save_row, "Save all", _on_save_all)
	_status_label = Label.new()
	_status_label.text = "Changes appear live. Save when ready."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_status_label)
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "Unsaved pose changes"
	_save_dialog.dialog_text = "Save edited poses before returning to the game?"
	_save_dialog.ok_button_text = "Save all"
	_save_dialog.cancel_button_text = "Keep editing"
	_save_dialog.add_button("Discard edits", true, "discard")
	_save_dialog.confirmed.connect(_save_and_close)
	_save_dialog.custom_action.connect(_on_close_action)
	add_child(_save_dialog)
	_library = PostureLibrary.instance()
	_base_pose_library = BasePoseLibrary.instance()
	_populate_list()
	_apply_readable_controls(self)
	_on_tab_changed(1)
	_build_swing_controls()

func _build_swing_controls() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	_swing_controls = PanelContainer.new()
	_swing_controls.theme = theme
	_swing_controls.add_theme_stylebox_override("panel", UiTheme.panel_style())
	get_parent().add_child(_swing_controls)
	_swing_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_swing_controls.offset_left = 16
	_swing_controls.offset_right = 656
	_swing_controls.offset_top = -164
	_swing_controls.offset_bottom = -16
	_swing_controls.hide()
	tree_exiting.connect(_swing_controls.queue_free)
	var box := VBoxContainer.new()
	_swing_controls.add_child(box)
	var legend := HBoxContainer.new()
	box.add_child(legend)
	for i in range(3):
		var button := Button.new()
		button.text = KEYFRAME_NAMES[i]
		button.toggle_mode = true
		button.button_pressed = i == _keyframe_index
		button.add_theme_color_override("font_color", [SwingVisual.WINDUP, SwingVisual.CONTACT, SwingVisual.FINISH][i])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Edit this keyframe in Body or Paddle. Scrubbing previews the blended motion."
		button.pressed.connect(_select_keyframe.bind(i))
		legend.add_child(button)
		_keyframe_buttons.append(button)
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = "Scrub swing"
	row.add_child(label)
	_swing_scrub = HSlider.new()
	_swing_scrub.max_value = 1.0
	_swing_scrub.step = 0.001
	_swing_scrub.custom_minimum_size.y = 36
	_swing_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swing_scrub.value = 0.5
	_swing_scrub.value_changed.connect(_on_swing_scrubbed)
	row.add_child(_swing_scrub)
	var options := HBoxContainer.new()
	box.add_child(options)
	_show_swing_path = CheckButton.new()
	_show_swing_path.text = "Paddle trail"
	_show_swing_path.button_pressed = true
	_show_swing_path.toggled.connect(func(on):
		if _swing_visual: _swing_visual.visible = on and visible and not _is_base_pose_mode
	)
	options.add_child(_show_swing_path)
	_loop_swing = CheckButton.new()
	_loop_swing.text = "Loop"
	_loop_swing.toggled.connect(func(on):
		if _transition_player: _transition_player.set_loop(on)
	)
	options.add_child(_loop_swing)
	_swing_speed = OptionButton.new()
	for speed in ["¼ speed", "½ speed", "Normal speed"]:
		_swing_speed.add_item(speed)
	_swing_speed.select(1)
	_swing_speed.item_selected.connect(func(index):
		if _transition_player: _transition_player.set_speed([0.25, 0.5, 1.0][index])
	)
	options.add_child(_swing_speed)
	_show_reach_limits = CheckButton.new()
	_show_reach_limits.text = "Reach"
	_show_reach_limits.tooltip_text = "Show the shoulder's reachable area. Reach limits are always enforced."
	_show_reach_limits.toggled.connect(func(on):
		if _reach_visual: _reach_visual.visible = on and visible and not _is_base_pose_mode
	)
	options.add_child(_show_reach_limits)

func _refresh_swing_path() -> void:
	if _swing_controls:
		_swing_controls.visible = visible and not _is_base_pose_mode
	if _player == null or not _current_def is PostureDefinition:
		if _swing_visual: _swing_visual.hide()
		return
	if not _swing_visual and _player.get_parent():
		_swing_visual = SwingVisual.new()
		_player.get_parent().add_child(_swing_visual)
		tree_exiting.connect(_swing_visual.queue_free)
	if _swing_visual:
		_swing_visual.rebuild(_player, _current_def)
		_swing_visual.visible = visible and (_show_swing_path == null or _show_swing_path.button_pressed)

func _on_swing_scrubbed(value: float) -> void:
	if _player == null or not _current_def is PostureDefinition:
		return
	if _transition_player: _transition_player.pause()
	if _pose_transition_tween and _pose_transition_tween.is_valid(): _pose_transition_tween.kill()
	_pose_transition_tween = null
	_scrubbing = true
	if _gizmo_controller: _gizmo_controller.clear_all_gizmos()
	var preview: PostureDefinition = SwingPath.sample(_current_def, value)
	_player.posture.transition_pose_blend = preview
	_player.posture.force_posture_update(preview)
	_preview_state_label.text = "Preview: %s · %d%%" % ["wind-up → contact" if value < 0.5 else "contact → follow-through", roundi(value * 100)]
	_swing_button.text = "Play swing"

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _toggle_help() -> void:
	_help_box.visible = not _help_box.visible

func _step_pose(direction: int) -> void:
	if _pose_picker.item_count > 0:
		_on_posture_selected(wrapi(_pose_picker.selected + direction, 0, _pose_picker.item_count))

func _select_section(index: int) -> void:
	_tab_container.current_tab = index

func _apply_readable_controls(node: Node) -> void:
	if node is Control:
		var control: Control = node
		if control is Label or control is Button or control is OptionButton or control is CheckButton or control is ItemList or control is SpinBox or control is LineEdit or control is TabBar:
			control.add_theme_font_size_override("font_size", maxi(control.get_theme_font_size("font_size"), 20))
		if control is Button or control is OptionButton or control is CheckButton:
			control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 38.0)
		elif control is SpinBox:
			control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 38.0)
		elif control is HSlider:
			control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 34.0)
	for child in node.get_children():
		_apply_readable_controls(child)

func open() -> void:
	if visible:
		return
	visible = true
	_saved_snapshots.clear()
	for def in _library.all_definitions() + _base_pose_library.all_definitions():
		_saved_snapshots[_dirty_key(def)] = def.duplicate(true)
	if _player:
		_restore_posture_id = _player.paddle_posture
	if _reach_visual:
		_reach_visual.visible = not _is_base_pose_mode and _show_reach_limits != null and _show_reach_limits.button_pressed
	if _player and _player.posture:
		_player.posture.editor_preview_mode = true
		# Sync ALL posture ghosts and zone meshes to their saved definitions immediately.
		# This prevents ghosts and zone bounds from lingering at stale gameplay positions.
		if _library != null:
			for def in _library.all_definitions():
				if def is PostureDefinition:
					_sync_ghost_to_definition(def)
					_update_zone_mesh_from_def(def)
		# Auto-select the player's current posture so gizmos appear.
		if _posture_list != null and not _is_base_pose_mode:
			var current_posture_id: int = _player.paddle_posture
			var defs: Array = _library.all_definitions()
			for i in range(defs.size()):
				if defs[i].posture_id == current_posture_id:
					_posture_list.select(i)
					_on_posture_selected(i)
					break
	editor_opened.emit()

func close() -> void:
	if not visible:
		return
	if not _dirty_defs.is_empty():
		_save_dialog.popup_centered()
		return
	_finish_close()

func _finish_close() -> void:
	# Kill any running pose transition
	if _pose_transition_tween and _pose_transition_tween.is_valid():
		_pose_transition_tween.kill()
		_pose_transition_tween = null
	# Clear gizmos
	if _gizmo_controller:
		_gizmo_controller.clear_all_gizmos()
	# Clear editor solo posture so ghosts return to normal
	if _player and _player.posture:
		_player.posture.set_editor_solo_posture_id(-1)
		_player.posture.editor_preview_mode = false
		_player.posture.transition_pose_blend = null
	if _transition_player:
		_transition_player.stop()
	if _player and _restore_posture_id >= 0:
		_player.paddle_posture = _restore_posture_id
	visible = false
	_scrubbing = false
	if _swing_controls: _swing_controls.hide()
	if _swing_visual: _swing_visual.hide()
	if _reach_visual:
		_reach_visual.visible = false
	editor_closed.emit()

func _save_and_close() -> void:
	_on_save_all()
	if _dirty_defs.is_empty():
		_finish_close()

func _on_close_action(action: StringName) -> void:
	if action != &"discard":
		return
	_save_dialog.hide()
	_dirty_defs.clear()
	_library.load_or_default()
	_base_pose_library.load_or_default()
	_current_def = null
	if _player and _player.posture:
		_player.posture.refresh_posture_zones()
	if _player and _player.pose_controller:
		_player.pose_controller.invalidate_cache()
	_populate_list()
	_update_save_all_button()
	_finish_close()

func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig

func _set_camera_view(view: String) -> void:
	if _camera_rig:
		_camera_rig.set_editor_view(view)

func _focus_camera() -> void:
	if _camera_rig == null or _player == null:
		return
	var target: Vector3 = _player.global_position + Vector3.UP * 0.15
	if _current_def is PostureDefinition:
		var def: PostureDefinition = _current_def
		target = _player.global_position + def.resolve_paddle_offset(_player._get_forehand_axis(), _player._get_forward_axis())
	_camera_rig.focus_editor_view(target)

func _reset_camera() -> void:
	if _camera_rig and _player:
		_camera_rig.reset_editor_view(_player.global_position)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed):
		if event.shift_pressed:
			_on_save_all()
		else:
			_on_save()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F:
		_focus_camera()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R:
		_reset_camera()
		get_viewport().set_input_as_handled()

func _expand_window() -> void:
	var window: Window = get_window() if is_inside_tree() else null
	if window == null:
		return
	_prev_window_mode = window.mode
	if _prev_window_mode != Window.MODE_WINDOWED:
		_window_geometry_saved = false
		return
	_prev_window_size = window.size
	_prev_window_position = window.position
	_window_geometry_saved = true
	window.mode = Window.MODE_MAXIMIZED

func _restore_window() -> void:
	var window: Window = get_window() if is_inside_tree() else null
	if window == null:
		return
	window.mode = _prev_window_mode as Window.Mode
	if not _window_geometry_saved:
		return
	window.size = _prev_window_size
	window.position = _prev_window_position
	_window_geometry_saved = false

## True if screen-space pos is inside the editor panel while visible.
func contains_screen_point(pos: Vector2) -> bool:
	if not visible:
		return false
	if _save_dialog and _save_dialog.visible:
		return true
	if _swing_controls and _swing_controls.visible and _swing_controls.get_global_rect().has_point(pos):
		return true
	return get_global_rect().has_point(pos)

func set_player(player) -> void:
	_player = player
	if _player and _player.get_parent():
		_reach_visual = MeshInstance3D.new()
		_reach_visual.name = "PaddleReachLimit"
		var reach_mesh := SphereMesh.new()
		reach_mesh.radius = PaddleReach.MAX_HEAD_DISTANCE
		reach_mesh.height = PaddleReach.MAX_HEAD_DISTANCE * 2.0
		_reach_visual.mesh = reach_mesh
		var reach_material := StandardMaterial3D.new()
		reach_material.albedo_color = Color(0.1, 0.9, 0.7, 0.035)
		reach_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		reach_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reach_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_reach_visual.material_override = reach_material
		_player.get_parent().add_child(_reach_visual)
		_reach_visual.visible = false
		_gizmo_controller = GizmoControllerV2.new()
		_gizmo_controller.name = "GizmoControllerV2"
		_player.get_parent().add_child(_gizmo_controller)
		var camera: Camera3D = _player.get_viewport().get_camera_3d() if _player else null
		if camera:
			_gizmo_controller.set_camera(camera)
		_gizmo_controller.set_ui(self )
		_gizmo_controller.set_player(_player)
		_gizmo_controller.gizmo_moved.connect(_on_gizmo_moved)
		_gizmo_controller.gizmo_rotated.connect(_on_gizmo_rotated)
		_gizmo_controller.ghost_selected.connect(_on_ghost_selected)
		_gizmo_controller.ghost_moved.connect(_on_ghost_moved)
		_gizmo_controller.zone_selected.connect(_on_zone_selected)
		_gizmo_controller.drag_ended.connect(_on_drag_ended)

func _process(_delta: float) -> void:
	if not visible:
		return
	if _transition_player and _transition_player.is_playing() and _swing_scrub:
		var phase: int = _transition_player.get_current_phase()
		var factor: float = _transition_player.get_phase_progress()
		var progress: float = 0.0
		if phase == TransitionPlayer.Phase.CONTACT: progress = SwingPath.release_progress(_current_def, 0, factor)
		elif phase == TransitionPlayer.Phase.FOLLOW_THROUGH: progress = SwingPath.release_progress(_current_def, 1, factor)
		elif phase == TransitionPlayer.Phase.SETTLE: progress = 1.0
		_swing_scrub.set_value_no_signal(progress)
		_preview_state_label.text = "Preview: %s · %d%%" % [TransitionPlayer.Phase.keys()[phase].capitalize().replace("_", " "), roundi(progress * 100)]
	if _reach_visual and visible and _player:
		_reach_visual.global_position = PaddleReach.shoulder_world(_player)
	if _player and _player.paddle_node and _current_def is PostureDefinition:
		var shoulder: Vector3 = PaddleReach.shoulder_world(_player)
		var preview = _player.posture.transition_pose_blend
		var distance: float = PaddleReach.head_world(_player).distance_to(shoulder)
		var requested: Vector3 = _player.global_position + preview.resolve_paddle_offset(_player._get_forehand_axis(), _player._get_forward_axis()) if preview else PaddleReach.head_world(_player)
		_reach_label.text = "Paddle reach: %.2f / %.2f m%s" % [distance, PaddleReach.MAX_HEAD_DISTANCE, " (limited)" if requested.distance_to(PaddleReach.head_world(_player)) > 0.01 else ""]
	if _pose_trigger:
		_pose_trigger.update()
	# Keep the workspace focused on the selected pose rather than its whole family.
	if _player and _player.posture:
		var selected_id: int = _current_def.posture_id if _current_def is PostureDefinition else -1
		for id in _player.posture.posture_ghosts:
			_player.posture.posture_ghosts[id].visible = id == selected_id and _tab_container.current_tab == 4
		for id in _player.posture._posture_zone_bounds:
			_player.posture._posture_zone_bounds[id].visible = id == selected_id and _tab_container.current_tab == 4
		if _player.posture.has_method("set_follow_through_visible"):
			_player.posture.set_follow_through_visible(false)
	# Keep paddle gizmo synced with GHOST head center.
	# Sync ghost to definition FIRST, then gizmo to ghost, so stale gameplay positions
	# don't drift the gizmo. Skip while actively dragging.
	if _gizmo_controller and _current_def is PostureDefinition and _player and _player.posture:
		var paddle_gizmo = _gizmo_controller.get_node_or_null("paddle_position")
		if paddle_gizmo and not _gizmo_controller.is_dragging() and not _scrubbing:
			var stage_pose: PostureDefinition = SwingPath.endpoint(_current_def, _keyframe_index)
			var transform: Transform3D = SwingPath.world_transform(_player, stage_pose)
			paddle_gizmo.global_position = transform.origin + transform.basis.y * 0.4
		# Keep zone handles synced to definition (one source of truth)
		# Skip while dragging a zone handle so the handle doesn't snap back before
		# _physics_process() has a chance to update the mesh.
		if not _gizmo_controller.is_dragging_zone_handle():
			var bounds := _get_zone_world_bounds(_current_def)
			if _zone_move_mode:
				var center_gizmo = _gizmo_controller.get_node_or_null("zone_center")
				if center_gizmo:
					center_gizmo.global_position = bounds.center
			else:
				var face_names := ["zone_left","zone_right","zone_bottom","zone_top","zone_front","zone_back"]
				var face_keys := ["left","right","bottom","top","front","back"]
				for i in range(6):
					var gizmo = _gizmo_controller.get_node_or_null(face_names[i])
					if gizmo:
						gizmo.global_position = bounds[face_keys[i]]
	# After transition finishes, snap paddle to match ghost so all three align
	if _keyframe_index == 1 and not _scrubbing and _pose_transition_tween == null and _current_def is PostureDefinition and _player and _player.posture and _player.paddle_node and not (_transition_player and _transition_player.is_playing()) and _tab_container.current_tab not in [2, 3]:
		var ghost = _player.posture.posture_ghosts.get(_current_def.posture_id)
		if ghost:
			var ghost_head: Vector3 = ghost.global_position + ghost.global_transform.basis.y * 0.4
			_player.paddle_node.global_position = ghost_head - _player.paddle_node.global_transform.basis.y * 0.4
			# Also sync the orange debug marker so it doesn't lag behind
			if _player.posture._paddle_head_marker:
				_player.posture._paddle_head_marker.global_position = ghost_head

func toggle() -> void:
	if visible: close()
	else: open()

# ── List & Selection ──────────────────────────────────────────────────────────

func _on_toggle_workspace() -> void:
	_is_base_pose_mode = not _is_base_pose_mode
	_workspace_button.text = "Body poses" if _is_base_pose_mode else "Stroke poses"
	_populate_list()
	_current_def = null
	_status_label.text = "Select a %s to edit" % ("base pose" if _is_base_pose_mode else "stroke posture")
	# Hide stroke-only tabs in base-pose mode
	_set_tab_hidden("Paddle", _is_base_pose_mode)
	_set_tab_hidden("Charge", _is_base_pose_mode)
	_set_tab_hidden("Follow-Through", _is_base_pose_mode)
	_set_tab_hidden("Contact", _is_base_pose_mode)
	for i in range(_section_picker.item_count):
		_section_picker.set_item_disabled(i, _is_base_pose_mode and i != 0)
	_select_section(0 if _is_base_pose_mode else 1)
	# Clear inspectors and gizmos
	_body_tab.set_definition(null)
	_paddle_tab.set_definition(null)
	_charge_tab.set_definition(null)
	_ft_tab.set_definition(null)
	if _gizmo_controller:
		_gizmo_controller.clear_all_gizmos()
	_update_save_all_button()
	_selection_label.text = "No pose selected"
	_preview_state_label.text = "Preview: idle"
	if _reach_visual:
		_reach_visual.visible = visible and not _is_base_pose_mode and _show_reach_limits != null and _show_reach_limits.button_pressed
	_zone_move_button.visible = not _is_base_pose_mode
	_save_button.disabled = true
	if _posture_list.item_count > 0:
		_on_posture_selected(0)

func _on_toggle_zone_move() -> void:
	_zone_move_mode = not _zone_move_mode
	_zone_move_button.text = "Move whole contact area" if _zone_move_mode else "Resize contact area"
	# Refresh gizmos to show/hide zone handles
	if _current_def and _gizmo_controller:
		_refresh_gizmos()
		_status_label.text = "Zone move mode: %s" % ("ON" if _zone_move_mode else "OFF")

func _set_tab_hidden(tab_name: String, is_hidden: bool) -> void:
	if _tab_container == null:
		return
	for i in range(_tab_container.get_tab_count()):
		if _tab_container.get_tab_title(i) == tab_name:
			_tab_container.set_tab_hidden(i, is_hidden)
			return

func _populate_list() -> void:
	if _posture_list == null:
		return
	_posture_list.clear()
	if _pose_picker:
		_pose_picker.clear()
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	for def in defs:
		var text: String = ("● " if _dirty_defs.has(_dirty_key(def)) else "") + def.display_name
		_posture_list.add_item(text)
		if _pose_picker:
			_pose_picker.add_item(text)

func _on_posture_selected(index: int) -> void:
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	if index < 0 or index >= defs.size():
		return
	_current_def = defs[index]
	_keyframe_index = 0 if _tab_container.current_tab == 2 else (2 if _tab_container.current_tab == 3 else 1)
	_posture_list.select(index)
	if _pose_picker:
		_pose_picker.select(index)
	_selection_label.text = "Selected: %s%s" % [_current_def.display_name, " • Unsaved" if _dirty_defs.has(_dirty_key(_current_def)) else ""]
	_status_label.text = "Selected: %s" % _current_def.display_name
	posture_selected.emit(_current_def)
	print("[EDITOR V2] Selected ", _current_def.display_name)
	if _current_def is PostureDefinition:
		print("[VERIFIED LOAD] %s | fh=%.4f fwd=%.4f y=%.4f zone=[%.3f..%.3f] y=[%.3f..%.3f] z=%.3f" % [
			_current_def.display_name,
			_current_def.paddle_forehand_mul, _current_def.paddle_forward_mul, _current_def.paddle_y_offset,
			_current_def.zone_x_min, _current_def.zone_x_max, _current_def.zone_y_min, _current_def.zone_y_max, _current_def.zone_forward_offset
		])
	# Populate inspectors
	_bind_keyframe_inspectors()
	_charge_tab.set_definition(_current_def)
	_ft_tab.set_definition(_current_def)
	if _contact_tab:
		_contact_tab.set_definition(_current_def)
	if _current_def is PostureDefinition and _player:
		_clamp_current_paddle()
	# Enable preview for stroke postures only
	if _preview_button:
		_preview_button.disabled = false
	if _swing_button:
		_swing_button.disabled = _is_base_pose_mode
		_swing_button.text = "Play swing"
	if _save_button:
		_save_button.disabled = false
	_update_save_all_button()
	# Auto-preview pose for stroke postures
	_trigger_pose_preview()
	_apply_section_preview()
	# Update gizmos
	_refresh_gizmos()
	# Show relevant ghosts for the selected posture
	if _player and _player.posture:
		_player.posture.set_editor_solo_posture_id(_current_def.posture_id if _current_def is PostureDefinition else -1)

func _trigger_pose_preview() -> void:
	if _player == null or _current_def == null:
		return
	if _is_base_pose_mode:
		_apply_section_preview()
		return
	# Stop swing preview if running
	if _transition_player and _transition_player.is_playing():
		_transition_player.stop()
		if _swing_button:
			_swing_button.text = "Play swing"
	
	var target_def = _current_def as PostureDefinition
	if target_def == null:
		return

	var current_posture_id: int = _player.paddle_posture
	var ready_posture_id: int = _player.PaddlePosture.READY

	var current_def: PostureDefinition = _library.get_def(current_posture_id)
	var ready_def: PostureDefinition = _library.get_def(ready_posture_id)
	# Always sync ghost and zone mesh to definition so _refresh_gizmos / _process read correct positions.
	# Even if already at target posture, the definition fields may have changed (edit/undo).
	if _player.posture:
		_player.posture.force_posture_update(target_def)
		_sync_ghost_to_definition(target_def)
		_update_zone_mesh_from_def(target_def)
	
	# Already at target — no transition needed, but ghost sync above ensures consistency
	if current_posture_id == target_def.posture_id:
		return
	
	# Kill any existing transition
	if _pose_transition_tween and _pose_transition_tween.is_valid():
		_pose_transition_tween.kill()
		_pose_transition_tween = null
	
	# Simple single-stage lerp if we don't have current/ready defs, or target is READY
	if current_def == null or ready_def == null or target_def.posture_id == ready_posture_id:
		_player.paddle_posture = target_def.posture_id
		_status_label.text = "Previewing static pose for %s" % _current_def.display_name
		return
	
	# Determine if this is a cross-side switch (needs READY) or same-side (direct)
	var same_family: bool = (current_def.family == target_def.family) and current_def.family <= 1
	_transition_use_ready = not same_family
	
	# Compute paddle distance for duration scaling
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var current_offset: Vector3 = current_def.resolve_paddle_offset(forehand_axis, forward_axis)
	var target_offset: Vector3 = target_def.resolve_paddle_offset(forehand_axis, forward_axis)
	var total_distance: float = current_offset.distance_to(target_offset)
	if _transition_use_ready and ready_def != null:
		var ready_offset: Vector3 = ready_def.resolve_paddle_offset(forehand_axis, forward_axis)
		total_distance = current_offset.distance_to(ready_offset) + ready_offset.distance_to(target_offset)
	var duration: float = clampf(0.1 + total_distance * 0.4, 0.12, 0.45)
	
	_transition_from_def = current_def
	_transition_ready_def = ready_def
	_transition_to_def = target_def
	_pose_transition_tween = create_tween()
	_pose_transition_tween.set_trans(Tween.TRANS_SINE)
	_pose_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_pose_transition_tween.tween_method(_on_pose_transition_step, 0.0, 1.0, duration)
	_pose_transition_tween.finished.connect(func() -> void:
		# Leave transition_pose_blend set so arm/leg IK keeps using the explicit def
		# (it is already target_def from the last step call)
		# Bypass setter to avoid composed-pose flicker; skeleton is applied directly below
		_player.posture.paddle_posture = target_def.posture_id
		# Ensure skeleton shows pure target pose, not base+stroke composition
		_player.posture._apply_full_body_posture(target_def)
		_pose_transition_tween = null
	)
	_status_label.text = "Previewing static pose for %s" % _current_def.display_name

func _on_pose_transition_step(progress: float) -> void:
	var blended_def: PostureDefinition
	if _transition_use_ready:
		if progress < 0.5:
			var t: float = progress * 2.0
			blended_def = _transition_from_def.lerp_with(_transition_ready_def, t)
		else:
			var t: float = (progress - 0.5) * 2.0
			blended_def = _transition_ready_def.lerp_with(_transition_to_def, t)
	else:
		blended_def = _transition_from_def.lerp_with(_transition_to_def, progress)
	if _player and _player.posture:
		# Bypass the player.gd paddle_posture setter to avoid its internal
		# _apply_full_body_posture() snap with the library definition.
		# Instead we set the blend override and apply the skeleton directly.
		_player.posture.transition_pose_blend = blended_def
		_player.posture.paddle_posture = blended_def.posture_id
		if _player.pose_controller:
			_player.pose_controller.invalidate_cache()
		_player.posture._apply_full_body_posture(blended_def)

func _on_preview_pose() -> void:
	_apply_section_preview()
	_refresh_gizmos()

func _on_preview_swing() -> void:
	if _player == null or _current_def == null or _is_base_pose_mode:
		return
	if _transition_player == null:
		_transition_player = TransitionPlayer.new()
		add_child(_transition_player)
		_transition_player.playback_finished.connect(_on_preview_pose)
	if _transition_player.is_playing():
		_transition_player.pause()
		_swing_button.text = "Play swing"
		_preview_state_label.text = "Preview: swing paused"
		return
	if _pose_transition_tween and _pose_transition_tween.is_valid():
		_pose_transition_tween.kill()
		_pose_transition_tween = null
	# Build transition defs
	var def := _current_def as PostureDefinition
	if def == null:
		return
	var ready_def: PostureDefinition = def
	var charge_def: PostureDefinition = SwingPath.endpoint(def, 0)
	var ft_def: PostureDefinition = SwingPath.endpoint(def, 2)
	_scrubbing = true
	if _gizmo_controller: _gizmo_controller.clear_all_gizmos()
	_transition_player.setup(_player, ready_def, charge_def, def, [ft_def])
	_transition_player.set_loop(_loop_swing.button_pressed if _loop_swing else false)
	_transition_player.set_speed([0.25, 0.5, 1.0][_swing_speed.selected] if _swing_speed else 0.5)
	if _transition_player.is_playing():
		_transition_player.pause()
		_swing_button.text = "Play swing"
		_status_label.text = "Paused swing preview"
		_preview_state_label.text = "Preview: swing paused"
	else:
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.release_pose()
		_transition_player.play()
		_swing_button.text = "Pause Swing"
		_status_label.text = "Playing swing preview"
		_preview_state_label.text = "Preview: swing playing"

func _dirty_key(def) -> Variant:
	return "base:%d" % def.base_pose_id if def is BasePoseDefinition else def.posture_id

func _mark_dirty() -> void:
	if _current_def == null:
		return
	_dirty_defs[_dirty_key(_current_def)] = _current_def
	_update_save_all_button()

func _update_save_all_button() -> void:
	if _save_button:
		_save_button.disabled = _current_def == null or not _dirty_defs.has(_dirty_key(_current_def))
	if _revert_button:
		_revert_button.disabled = _current_def == null or not _dirty_defs.has(_dirty_key(_current_def))
	if _save_all_button:
		_save_all_button.text = "Save All (%d)" % _dirty_defs.size()
		_save_all_button.disabled = _dirty_defs.is_empty()
	if _posture_list and _library and _base_pose_library:
		var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
		for i in range(mini(defs.size(), _posture_list.get_item_count())):
			var text: String = ("● " if _dirty_defs.has(_dirty_key(defs[i])) else "") + defs[i].display_name
			_posture_list.set_item_text(i, text)
			if _pose_picker and i < _pose_picker.item_count:
				_pose_picker.set_item_text(i, text)
	if _selection_label and _current_def:
		_selection_label.text = "Selected: %s%s" % [_current_def.display_name, " • Unsaved" if _dirty_defs.has(_dirty_key(_current_def)) else ""]

## Save a single definition to disk. Returns true on success.
func _save_definition(def) -> bool:
	var path: String = ""
	var filename: String = ""
	if def is BasePoseDefinition:
		var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		filename = "%02d_%s.tres" % [def.base_pose_id, base]
		path = "res://data/base_poses/" + filename
	else:
		var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		filename = "%02d_%s.tres" % [def.posture_id, base]
		path = "res://data/postures/" + filename
	print("[EDITOR V2 SAVE] saving ", path)

	# Ensure directory exists
	var dir_path := ProjectSettings.globalize_path(path.get_base_dir()).rstrip("/")
	if not DirAccess.dir_exists_absolute(dir_path):
		var err_mkdir := DirAccess.make_dir_recursive_absolute(dir_path)
		if err_mkdir != OK:
			push_warning("PostureEditorV2: failed to create directory %s (error %d)" % [dir_path, err_mkdir])
			return false

	var err := ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err == OK:
		_saved_snapshots[_dirty_key(def)] = def.duplicate(true)
		def.resource_path = path
		print("[EDITOR V2 SAVE] SUCCESS: ", path)
		return true

	push_warning("PostureEditorV2: failed to save %s (error %d)" % [path, err])
	return false

func _on_save() -> void:
	if _current_def == null:
		_status_label.text = "Save: nothing selected"
		return
	var filename: String = _def_to_filename(_current_def)
	if _save_definition(_current_def):
		_status_label.text = "Saved: %s" % filename
		_verify_save(_current_def, filename)
		# Do NOT reload library here — in-memory _current_def is source of truth.
		# Reloading would replace it with a disk-rounded instance, causing drift.
		_dirty_defs.erase(_dirty_key(_current_def))
		_update_save_all_button()
	else:
		_status_label.text = "Save failed for %s" % filename

func _def_to_filename(def) -> String:
	if def is BasePoseDefinition:
		var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		return "%02d_%s.tres" % [def.base_pose_id, base]
	else:
		var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		return "%02d_%s.tres" % [def.posture_id, base]

func _verify_save(def, filename: String) -> void:
	var path: String = def.resource_path
	if path == "" or not path.ends_with(".tres"):
		return
	var disk_res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if disk_res != null and disk_res is PostureDefinition:
		var disk: PostureDefinition = disk_res
		var ok := true
		if not is_equal_approx(disk.paddle_forehand_mul, def.paddle_forehand_mul):
			print("[VERIFIED SAVE] MISMATCH paddle_forehand_mul: memory=%.6f disk=%.6f" % [def.paddle_forehand_mul, disk.paddle_forehand_mul]); ok = false
		if not is_equal_approx(disk.paddle_forward_mul, def.paddle_forward_mul):
			print("[VERIFIED SAVE] MISMATCH paddle_forward_mul: memory=%.6f disk=%.6f" % [def.paddle_forward_mul, disk.paddle_forward_mul]); ok = false
		if not is_equal_approx(disk.paddle_y_offset, def.paddle_y_offset):
			print("[VERIFIED SAVE] MISMATCH paddle_y_offset: memory=%.6f disk=%.6f" % [def.paddle_y_offset, disk.paddle_y_offset]); ok = false
		if not is_equal_approx(disk.zone_x_min, def.zone_x_min):
			print("[VERIFIED SAVE] MISMATCH zone_x_min: memory=%.6f disk=%.6f" % [def.zone_x_min, disk.zone_x_min]); ok = false
		if not is_equal_approx(disk.zone_x_max, def.zone_x_max):
			print("[VERIFIED SAVE] MISMATCH zone_x_max: memory=%.6f disk=%.6f" % [def.zone_x_max, disk.zone_x_max]); ok = false
		if not is_equal_approx(disk.zone_y_min, def.zone_y_min):
			print("[VERIFIED SAVE] MISMATCH zone_y_min: memory=%.6f disk=%.6f" % [def.zone_y_min, disk.zone_y_min]); ok = false
		if not is_equal_approx(disk.zone_y_max, def.zone_y_max):
			print("[VERIFIED SAVE] MISMATCH zone_y_max: memory=%.6f disk=%.6f" % [def.zone_y_max, disk.zone_y_max]); ok = false
		if not is_equal_approx(disk.zone_forward_offset, def.zone_forward_offset):
			print("[VERIFIED SAVE] MISMATCH zone_forward_offset: memory=%.6f disk=%.6f" % [def.zone_forward_offset, disk.zone_forward_offset]); ok = false
		if ok:
			print("[VERIFIED SAVE] %s — all key fields match disk" % filename)
	else:
		print("[VERIFIED SAVE] WARNING: could not reload disk copy for verification")

func _on_save_all() -> void:
	if _dirty_defs.is_empty():
		_status_label.text = "Nothing to save"
		return
	var saved_names: Array[String] = []
	var failed_names: Array[String] = []
	for def in _dirty_defs.values():
		var _fname: String = _def_to_filename(def)
		if _save_definition(def):
			saved_names.append(def.display_name)
			_dirty_defs.erase(_dirty_key(def))
		else:
			failed_names.append(def.display_name)
	# Do NOT reload library after saving — in-memory definitions are source of truth.
	# Reloading would swap _current_def with a disk-rounded instance, causing drift.
	if _current_def != null:
		_bind_keyframe_inspectors()
		_charge_tab.set_definition(_current_def)
		_ft_tab.set_definition(_current_def)
	if _contact_tab:
		_contact_tab.set_definition(_current_def)
	_update_save_all_button()
	if failed_names.is_empty():
		_status_label.text = "Saved %d poses." % saved_names.size()
		print("[EDITOR V2 SAVE] Saved %d postures: %s" % [saved_names.size(), ", ".join(saved_names)])
	else:
		_status_label.text = "Saved %d, failed %d" % [saved_names.size(), failed_names.size()]
		print("[EDITOR V2 SAVE] Saved %d postures, failed %d: %s" % [saved_names.size(), failed_names.size(), ", ".join(failed_names)])

# ── Tabs ──────────────────────────────────────────────────────────────────────

var _tab_container: TabContainer
var _body_tab: SimpleInspector
var _paddle_tab: SimpleInspector
var _charge_tab: SimpleInspector
var _ft_tab: SimpleInspector

func _build_tabs(tc: TabContainer) -> void:
	_tab_container = tc

	# ── Body tab (shared) ──
	_body_tab = SimpleInspector.new()
	_body_tab.name = "Body"
	_body_tab.build(
		[
			"__stance", "stance_width", "front_foot_forward", "back_foot_back",
			"right_foot_yaw_deg", "left_foot_yaw_deg",
			"__leg_details", "right_knee_pole", "left_knee_pole",
			"right_foot_offset", "left_foot_offset",
			"lead_foot", "crouch_amount", "weight_shift",
			"__body", "hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg",
			"body_yaw_deg", "body_pitch_deg", "body_roll_deg",
			"__head", "head_yaw_deg", "head_pitch_deg", "head_track_ball_weight",
			"__grip", "left_hand_mode", "__arms", "right_hand_offset", "left_hand_offset", "right_shoulder_rotation_deg", "left_shoulder_rotation_deg",
			"right_elbow_pole", "left_elbow_pole",
			"__runtime", "stroke_overlay_mix", "recovery_time", "landing_lockout_time", "jump_window", "split_step_hop_height", "lunge_distance",
		],
		{
			"__stance": {"label": "Stance", "type": "section"},
			"__leg_details": {"label": "Advanced feet & knees", "type": "section", "collapsible": true},
			"__body": {"label": "Body orientation (degrees)", "type": "section"},
			"__head": {"label": "Head", "type": "section", "collapsible": true},
			"__grip": {"label": "Support hand", "type": "section"},
			"__arms": {"label": "Advanced arm controls", "type": "section", "collapsible": true},
			"__runtime": {"label": "Body pose timing", "type": "section", "collapsible": true},
			"right_shoulder_rotation_deg": {"label": "Right shoulder (degrees)", "type": "vector3", "min": -180.0, "max": 180.0, "step": 1.0},
			"left_shoulder_rotation_deg": {"label": "Left shoulder (degrees)", "type": "vector3", "min": -180.0, "max": 180.0, "step": 1.0},
			"stroke_overlay_mix": {"label": "Blend with stroke", "min": 0.0, "max": 1.0},
			"recovery_time": {"label": "Recovery (s)", "min": 0.0, "max": 1.0},
			"landing_lockout_time": {"label": "Landing pause (s)", "min": 0.0, "max": 1.0},
			"jump_window": {"label": "Jump window (s)", "min": 0.0, "max": 1.0},
			"split_step_hop_height": {"label": "Split step height (m)", "min": 0.0, "max": 0.5},
			"lunge_distance": {"label": "Lunge distance (m)", "min": 0.0, "max": 2.0},
			"stance_width": {"label": "Stance Width", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
			"front_foot_forward": {"label": "Front Foot Fwd", "type": "float", "min": - 0.5, "max": 0.5, "step": 0.01},
			"back_foot_back": {"label": "Back Foot Back", "type": "float", "min": - 0.5, "max": 0.5, "step": 0.01},
			"right_foot_yaw_deg": {"label": "Right Foot Yaw", "type": "float", "min": - 90.0, "max": 90.0, "step": 1.0},
			"left_foot_yaw_deg": {"label": "Left Foot Yaw", "type": "float", "min": - 90.0, "max": 90.0, "step": 1.0},
			"right_knee_pole": {"label": "Right Knee", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"left_knee_pole": {"label": "Left Knee", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"right_foot_offset": {"label": "Right Foot Offset", "type": "vector3", "min": - 1.0, "max": 1.0, "step": 0.01},
			"left_foot_offset": {"label": "Left Foot Offset", "type": "vector3", "min": - 1.0, "max": 1.0, "step": 0.01},
			"lead_foot": {"label": "Lead Foot", "type": "option", "items": ["Right", "Left"]},
			"crouch_amount": {"label": "Crouch", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
			"weight_shift": {"label": "Weight Shift", "type": "float", "min": - 1.0, "max": 1.0, "step": 0.01},
			"hip_yaw_deg": {"label": "Hip Yaw", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"torso_yaw_deg": {"label": "Torso Yaw", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"torso_pitch_deg": {"label": "Torso Pitch", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"torso_roll_deg": {"label": "Torso Roll", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"spine_curve_deg": {"label": "Spine Curve", "type": "float", "min": - 30.0, "max": 30.0, "step": 1.0},
			"body_yaw_deg": {"label": "Body Yaw", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"body_pitch_deg": {"label": "Body Pitch", "type": "float", "min": - 30.0, "max": 30.0, "step": 1.0},
			"body_roll_deg": {"label": "Body Roll", "type": "float", "min": - 30.0, "max": 30.0, "step": 1.0},
			"head_yaw_deg": {"label": "Head Yaw", "type": "float", "min": - 45.0, "max": 45.0, "step": 1.0},
			"head_pitch_deg": {"label": "Head Pitch", "type": "float", "min": - 60.0, "max": 60.0, "step": 1.0},
			"head_track_ball_weight": {"label": "Head Track Ball", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
			"right_hand_offset": {"label": "Right Hand", "type": "vector3", "min": - 1.0, "max": 1.0, "step": 0.01},
			"left_hand_offset": {"label": "Left Hand", "type": "vector3", "min": - 1.0, "max": 1.0, "step": 0.01},
			"right_elbow_pole": {"label": "Right Elbow", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"left_elbow_pole": {"label": "Left Elbow", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"left_hand_mode": {"label": "Other hand", "type": "option", "items": ["Auto by pose", "Both hands on paddle", "Across chest", "Lift overhead", "Free / released"], "help": "Auto releases on forehand and joins on backhand. Free always releases; Both hands always grips."},
		}
	)
	_body_tab.field_changed.connect(_on_keyframe_field_changed)
	_add_scroll_tab("Body", _body_tab)

	# ── Paddle tab (stroke only) ──
	_paddle_tab = SimpleInspector.new()
	_paddle_tab.name = "Paddle"
	_paddle_tab.build(
		[
			"__grip", "paddle_hand", "left_hand_mode",
			"__position",
			"paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset",
			"__angle",
			"paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg",
			"__advanced_rotation",
			"paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg",
			"paddle_pitch_sign_source", "paddle_yaw_sign_source", "paddle_roll_sign_source",
			"paddle_floor_clearance",
		],
		{
			"__grip": {"label": "Paddle grip", "type": "section"},
			"paddle_hand": {"label": "Paddle hand", "type": "option", "items": ["Right hand", "Left hand"], "help": "Choose which hand holds the handle. Pose positions stay as authored; the other arm becomes the support arm."},
			"left_hand_mode": {"label": "Other hand", "type": "option", "items": ["Auto by pose", "Both hands on paddle", "Across chest", "Lift overhead", "Free / released"], "help": "Auto releases on forehand and joins on backhand. Choose Free to always release or Both hands to always grip."},
			"__position": {"label": "Paddle position (m)", "type": "section"},
			"__angle": {"label": "Paddle angle (°)", "type": "section"},
			"__advanced_rotation": {"label": "Advanced rotation", "type": "section", "collapsible": true},
			"__contact_area": {"label": "Reach and contact area", "type": "section"},
			"paddle_forehand_mul": {"label": "Side to side", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_forward_mul": {"label": "Forward / back", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_y_offset": {"label": "Height", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_pitch_base_deg": {"label": "Pitch", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_yaw_base_deg": {"label": "Yaw", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_roll_base_deg": {"label": "Roll", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_pitch_signed_deg": {"label": "Pitch Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_yaw_signed_deg": {"label": "Yaw Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_roll_signed_deg": {"label": "Roll Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_pitch_sign_source": {"label": "Pitch Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_yaw_sign_source": {"label": "Yaw Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_roll_sign_source": {"label": "Roll Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_floor_clearance": {"label": "Minimum floor height", "type": "float", "min": 0.0, "max": 0.8, "step": 0.01},
			"has_zone": {"label": "Enable contact area", "type": "bool"},
			"zone_x_min": {"label": "Left edge", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"zone_x_max": {"label": "Right edge", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"zone_y_min": {"label": "Low edge", "type": "float", "min": - 1.0, "max": 2.0, "step": 0.01},
			"zone_y_max": {"label": "High edge", "type": "float", "min": - 1.0, "max": 2.5, "step": 0.01},
			"zone_forward_offset": {"label": "Forward depth", "type": "float", "min": - 1.0, "max": 3.0, "step": 0.01},
		}
	)
	_paddle_tab.field_changed.connect(_on_keyframe_field_changed)
	_add_scroll_tab("Paddle", _paddle_tab)

	# ── Charge tab (stroke only) ──
	_charge_tab = SimpleInspector.new()
	_charge_tab.name = "Charge"
	_charge_tab.build(
		[
			"charge_paddle_offset", "charge_paddle_rotation_deg",
			"charge_body_rotation_deg", "charge_hip_coil_deg", "charge_back_foot_load", "charge_duration",
		],
		{
			"charge_paddle_offset": {"label": "Paddle Offset", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"charge_paddle_rotation_deg": {"label": "Paddle Rotation", "type": "vector3", "min": - 180.0, "max": 180.0, "step": 1.0},
			"charge_body_rotation_deg": {"label": "Body Rotation", "type": "float", "min": - 60.0, "max": 120.0, "step": 1.0},
			"charge_hip_coil_deg": {"label": "Hip Coil", "type": "float", "min": - 60.0, "max": 60.0, "step": 1.0},
			"charge_duration": {"label": "Wind-up time (s)", "min": 0.05, "max": 1.0, "step": 0.01},
			"charge_back_foot_load": {"label": "Back Foot Load", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		}
	)
	_charge_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Charge", _charge_tab)

	# ── Follow-Through tab (stroke only) ──
	_ft_tab = SimpleInspector.new()
	_ft_tab.name = "Follow-Through"
	_ft_tab.build(
		[
			"ft_paddle_offset", "ft_paddle_rotation_deg",
			"ft_hip_uncoil_deg", "ft_front_foot_load",
			"swing_path_blend", "ft_duration_strike", "ft_duration_sweep", "ft_duration_settle", "ft_duration_hold", "ft_ease_curve",
		],
		{
			"ft_paddle_offset": {"label": "Paddle Offset", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"ft_paddle_rotation_deg": {"label": "Paddle Rotation", "type": "vector3", "min": - 180.0, "max": 180.0, "step": 1.0},
			"ft_hip_uncoil_deg": {"label": "Hip Uncoil", "type": "float", "min": - 60.0, "max": 60.0, "step": 1.0},
			"ft_front_foot_load": {"label": "Front Foot Load", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
			"ft_ease_curve": {"label": "Swing easing", "type": "option", "items": ["Fast release", "Smooth release", "Ease in and out"]},
			"swing_path_blend": {"label": "Curve blending", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01, "help": "0 joins the three poses with straight segments. 1 blends them into a continuous curved swing; contact remains exact."},
			"ft_duration_strike": {"label": "Strike time (s)", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_sweep": {"label": "Sweep time (s)", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_settle": {"label": "Settle time (s)", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_hold": {"label": "Hold time (s)", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
		}
	)
	_ft_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Follow-Through", _ft_tab)

	_contact_tab = SimpleInspector.new()
	_contact_tab.build(
		["has_zone", "zone_x_min", "zone_x_max", "zone_y_min", "zone_y_max", "zone_forward_offset"],
		{
			"has_zone": {"label": "Use this pose for ball contact", "type": "bool"},
			"zone_x_min": {"label": "Left edge (m)", "min": -2.0, "max": 2.0},
			"zone_x_max": {"label": "Right edge (m)", "min": -2.0, "max": 2.0},
			"zone_y_min": {"label": "Bottom above court (m)", "min": 0.0, "max": 2.5},
			"zone_y_max": {"label": "Top above court (m)", "min": 0.0, "max": 2.5},
			"zone_forward_offset": {"label": "Forward distance (m)", "min": -1.0, "max": 2.0},
		})
	_contact_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Contact", _contact_tab)

func _add_scroll_tab(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(margin)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	_tab_container.add_child(scroll)

func _on_tab_changed(index: int) -> void:
	if index in [2, 3, 4]:
		_keyframe_index = {2: 0, 3: 2, 4: 1}[index]
	_bind_keyframe_inspectors()
	if _section_picker and index < _section_picker.item_count:
		_section_picker.select(index)
	if _section_help:
		_section_help.text = [
			"Editing %s: feet, hips, torso, head and hands." % KEYFRAME_NAMES[_keyframe_index],
			"Editing %s: paddle head in metres; face angle in degrees." % KEYFRAME_NAMES[_keyframe_index],
			"Wind-up offsets and timing. Select Body or Paddle to edit the whole wind-up keyframe.",
			"Finish offsets, curve and timing. Select Body or Paddle to edit the whole finish keyframe.",
			"This box defines where the ball can meet this pose. Drag its edges to resize or switch to moving the whole box."
		][index]
	if _zone_move_button:
		_zone_move_button.visible = index == 4 and not _is_base_pose_mode
	_apply_section_preview()
	_refresh_gizmos()

func _apply_section_preview() -> void:
	_scrubbing = false
	if _player == null or _current_def == null:
		return
	if _pose_transition_tween and _pose_transition_tween.is_valid():
		_pose_transition_tween.kill()
		_pose_transition_tween = null
	if _transition_player and _transition_player.is_playing():
		_transition_player.pause()
	var preview: PostureDefinition
	if _current_def is BasePoseDefinition:
		preview = _current_def.to_preview_posture(_library.get_def(20))
	else:
		preview = SwingPath.endpoint(_current_def, _keyframe_index)
	if preview and _player.posture:
		_player.posture.transition_pose_blend = preview
		_player.posture.force_posture_update(preview)
		if _preview_state_label:
			_preview_state_label.text = "Preview: " + ("body stance" if _is_base_pose_mode else KEYFRAME_NAMES[_keyframe_index] + " keyframe")
		if _swing_button:
			_swing_button.text = "Play swing"
		if _swing_scrub:
			_swing_scrub.set_value_no_signal(_keyframe_index * 0.5)
	_refresh_swing_path()


func _select_keyframe(stage: int) -> void:
	_keyframe_index = clampi(stage, 0, 2)
	if _tab_container.current_tab not in [0, 1]:
		_select_section(1)
	else:
		_on_tab_changed(_tab_container.current_tab)

func _bind_keyframe_inspectors() -> void:
	for i in range(_keyframe_buttons.size()):
		_keyframe_buttons[i].set_pressed_no_signal(i == _keyframe_index)
	_edit_def = SwingPath.endpoint(_current_def, _keyframe_index) if _current_def is PostureDefinition and _keyframe_index != 1 else _current_def
	if _body_tab: _body_tab.set_definition(_edit_def)
	if _paddle_tab: _paddle_tab.set_definition(_edit_def)

func _store_keyframe_paddle(pose: PostureDefinition) -> void:
	var offset := Vector3.ZERO
	var rotation := Vector3.ZERO
	for i in range(3):
		offset[i] = pose.get(PADDLE_POSITION_FIELDS[i]) - _current_def.get(PADDLE_POSITION_FIELDS[i])
		rotation[i] = pose.get(PADDLE_ROTATION_FIELDS[i]) - _current_def.get(PADDLE_ROTATION_FIELDS[i])
	_current_def.set("charge_paddle_offset" if _keyframe_index == 0 else "ft_paddle_offset", offset)
	_current_def.set("charge_paddle_rotation_deg" if _keyframe_index == 0 else "ft_paddle_rotation_deg", rotation)

func _on_keyframe_field_changed(field: String, value: Variant) -> void:
	if not _current_def is PostureDefinition or _keyframe_index == 1:
		_on_field_changed(field, value)
		_bind_keyframe_inspectors()
		return
	if field in PADDLE_POSITION_FIELDS or field in PADDLE_ROTATION_FIELDS:
		_store_keyframe_paddle(_edit_def)
	elif field in BodyKeyframe.FIELDS:
		var property: String = "windup_body" if _keyframe_index == 0 else "follow_through_body"
		var body: Resource = _current_def.get(property)
		if body == null:
			body = BodyKeyframe.new()
			body.capture(_edit_def)
			_current_def.set(property, body)
		body.values[field] = value
	else:
		# Grip handedness, reach and gameplay metadata belong to the entire stroke.
		_current_def.set(field, value)
	_mark_dirty()
	_status_label.text = "Modified: %s · %s" % [_current_def.display_name, KEYFRAME_NAMES[_keyframe_index]]
	_charge_tab.set_definition(_current_def)
	_ft_tab.set_definition(_current_def)
	_bind_keyframe_inspectors()
	_apply_section_preview()
	_refresh_gizmos()


func _on_field_changed(_field: String, _value: Variant) -> void:
	if _current_def is PostureDefinition:
		var mapping: Dictionary = {
			"charge_body_rotation_deg": ["windup_body", "body_yaw_deg", _current_def.body_yaw_deg + _current_def.charge_body_rotation_deg],
			"charge_hip_coil_deg": ["windup_body", "hip_yaw_deg", _current_def.hip_yaw_deg + _current_def.charge_hip_coil_deg],
			"charge_back_foot_load": ["windup_body", "weight_shift", -_current_def.charge_back_foot_load],
			"ft_hip_uncoil_deg": ["follow_through_body", "hip_yaw_deg", _current_def.hip_yaw_deg + _current_def.ft_hip_uncoil_deg],
			"ft_front_foot_load": ["follow_through_body", "weight_shift", _current_def.ft_front_foot_load],
		}
		if mapping.has(_field):
			var entry: Array = mapping[_field]
			var body: Resource = _current_def.get(entry[0])
			if body: body.values[entry[1]] = entry[2]

	if _current_def:
		if _current_def is PostureDefinition and _player:
			_player.posture.transition_pose_blend = _current_def
			_clamp_current_paddle()
			if _field.begins_with("zone_") or _field == "has_zone" or _field == "paddle_floor_clearance":
				_normalize_zone_bounds(_field)
				if _player.posture.has_method("refresh_posture_zones"):
					_player.posture.refresh_posture_zones()
				if _current_def.has_zone and not _player.posture._posture_zone_bounds.has(_current_def.posture_id) and _player.posture.has_method("_create_posture_zone_bounds"):
					_player.posture._create_posture_zone_bounds()
				if _current_def.has_zone:
					_update_zone_mesh_from_def(_current_def)
				elif _player.posture._posture_zone_bounds.has(_current_def.posture_id):
					_player.posture._posture_zone_bounds[_current_def.posture_id].visible = false
			_sync_ghost_to_definition(_current_def)
			_player.posture.force_posture_update(_current_def)
		_status_label.text = "Modified: %s" % _current_def.display_name
		_mark_dirty()
	_bind_keyframe_inspectors()
	_apply_section_preview()
	_refresh_gizmos()

func _normalize_zone_bounds(changed_field: String) -> void:
	var def: PostureDefinition = _current_def
	if changed_field == "zone_x_min":
		def.zone_x_min = minf(def.zone_x_min, def.zone_x_max - 0.02)
	elif changed_field == "zone_x_max":
		def.zone_x_max = maxf(def.zone_x_max, def.zone_x_min + 0.02)
	elif changed_field == "zone_y_min":
		def.zone_y_min = minf(def.zone_y_min, def.zone_y_max - 0.02)
	elif changed_field == "zone_y_max":
		def.zone_y_max = maxf(def.zone_y_max, def.zone_y_min + 0.02)
	def.zone_y_min = maxf(def.zone_y_min, def.paddle_floor_clearance)
	def.zone_y_max = maxf(def.zone_y_max, def.zone_y_min + 0.02)
	_paddle_tab.set_definition(def)
	if _contact_tab:
		_contact_tab.set_definition(def)

func _clamp_current_paddle() -> void:
	if _player == null or not _current_def is PostureDefinition:
		return
	var def: PostureDefinition = _current_def
	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	var requested: Vector3 = _player.global_position + def.resolve_paddle_offset(fh, fwd)
	var shoulder: Vector3 = BodyPose.shoulder_world(_player, def)
	var limited: Vector3 = PaddleReach.clamp_head_with_floor(
		requested, shoulder, _player.COURT_FLOOR_Y + def.paddle_floor_clearance)
	var offset: Vector3 = limited - _player.global_position
	def.paddle_forehand_mul = offset.dot(fh)
	def.paddle_forward_mul = offset.dot(fwd)
	def.paddle_y_offset = offset.y
	_reach_label.text = "Paddle reach: %.2f / %.2f m%s" % [
		requested.distance_to(shoulder), PaddleReach.MAX_HEAD_DISTANCE,
		" (limited)" if requested.distance_to(limited) > 0.001 else "",
	]
	if requested.distance_to(limited) > 0.001:
		_paddle_tab.set_definition(def)

func _refresh_gizmos() -> void:
	if _gizmo_controller == null or _current_def == null or _player == null:
		if _gizmo_controller:
			_gizmo_controller.clear_all_gizmos()
		return
	_gizmo_controller.clear_all_gizmos()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return
	
	# Body rotation gizmos (shared)
	if _player.skeleton and (_tab_container == null or _tab_container.current_tab == 0):
		var hip_idx: int = _player.skeleton.find_bone("hips")
		if hip_idx >= 0:
			var hip_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(hip_idx).origin)
			var hip_gizmo := _gizmo_controller.add_rotation_gizmo("hip_rotation", hip_pos)
			hip_gizmo.scale = Vector3(0.6, 0.6, 0.6)
		var chest_idx: int = _player.skeleton.find_bone("chest")
		if chest_idx >= 0:
			var chest_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(chest_idx).origin)
			var chest_gizmo := _gizmo_controller.add_rotation_gizmo("torso_rotation", chest_pos)
			chest_gizmo.scale = Vector3(0.5, 0.5, 0.5)
		var head_idx: int = _player.skeleton.find_bone("head")
		if head_idx >= 0:
			var head_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(head_idx).origin)
			var head_gizmo := _gizmo_controller.add_rotation_gizmo("head_rotation", head_pos)
			head_gizmo.scale = Vector3(0.4, 0.4, 0.4)
	
	if _is_base_pose_mode:
		return
	if _tab_container and _tab_container.current_tab in [2, 3]:
		return
	
	# Paddle position gizmo (stroke only)
	var def = _current_def as PostureDefinition
	if def == null:
		return
	var stage_pose: PostureDefinition = SwingPath.endpoint(def, _keyframe_index)
	# Always compute from definition — ghost may be stale from gameplay or a previous edit.
	var stage_transform: Transform3D = SwingPath.world_transform(_player, stage_pose)
	var paddle_pos: Vector3 = stage_transform.origin + stage_transform.basis.y * 0.4
	if _tab_container == null or _tab_container.current_tab == 1:
		_gizmo_controller.add_position_gizmo("paddle_position", paddle_pos, Color(0.3, 0.9, 0.3), 0.08, true)
	# Sync ghost to definition so _process doesn't fight with stale ghost data
	_sync_ghost_to_definition(def)

	# Zone bounds gizmos — either 6 face handles or 1 big center handle
	if def.has_zone and (_tab_container == null or _tab_container.current_tab == 4):
		var bounds := _get_zone_world_bounds(def)
		if _zone_move_mode:
			# One big center gizmo for moving the whole zone
			_gizmo_controller.add_position_gizmo("zone_center", bounds.center, Color(0.9, 0.9, 0.2), 0.12, true)
		else:
			# 6 face handles for precise resizing
			var face_names := ["zone_left","zone_right","zone_bottom","zone_top","zone_front","zone_back"]
			var face_colors := [
				Color(1.0,0.3,0.3), Color(1.0,0.3,0.3),
				Color(0.3,0.3,1.0), Color(0.3,0.3,1.0),
				Color(0.9,0.5,0.2), Color(0.7,0.4,0.15),
			]
			var face_sizes := [0.05,0.05,0.05,0.05,0.06,0.06]
			var face_keys := ["left","right","bottom","top","front","back"]
			for i in range(6):
				_gizmo_controller.add_zone_handle(face_names[i], bounds[face_keys[i]], face_colors[i], face_sizes[i], true)

func _get_basis_from_rotation(rot_deg: Vector3) -> Basis:
	var b := Basis()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
	b = b * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
	b = b * Basis(Vector3.FORWARD, deg_to_rad(rot_deg.z))
	return b


## Compute zone face positions directly from definition — ONE SOURCE OF TRUTH.
## Mirrors the math in _update_zone_mesh_from_def so gizmos always match the definition.
func _get_zone_world_bounds(def: PostureDefinition) -> Dictionary:
	var fh_axis: Vector3 = _player._get_forehand_axis()
	var fwd_axis: Vector3 = _player._get_forward_axis()
	var zone_cx: float = (def.zone_x_min + def.zone_x_max) * 0.5
	var zone_cy_world: float = _player.COURT_FLOOR_Y + (def.zone_y_min + def.zone_y_max) * 0.5
	var zone_cz: float = def.zone_forward_offset
	var center: Vector3 = _player.global_position + fh_axis * zone_cx + fwd_axis * zone_cz
	center.y = zone_cy_world
	var half_x: float = (def.zone_x_max - def.zone_x_min) * 0.5
	var half_y: float = (def.zone_y_max - def.zone_y_min) * 0.5
	var half_z: float = 0.075
	return {
		"center": center,
		"left":   center + fh_axis * (-half_x),
		"right":  center + fh_axis * half_x,
		"bottom": Vector3(center.x, zone_cy_world - half_y, center.z),
		"top":    Vector3(center.x, zone_cy_world + half_y, center.z),
		"front":  center + fwd_axis * (-half_z),
		"back":   center + fwd_axis * half_z,
	}

func _on_ghost_selected(posture_id: int) -> void:
	if _posture_list == null or _is_base_pose_mode:
		return
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	for i in range(defs.size()):
		if defs[i].posture_id == posture_id:
			_posture_list.select(i)
			_on_posture_selected(i)
			return

func _on_zone_selected(posture_id: int) -> void:
	# Clicking a zone mesh selects its posture and enters zone move mode
	if _posture_list == null or _is_base_pose_mode:
		return
	var defs: Array = _library.all_definitions()
	for i in range(defs.size()):
		if defs[i].posture_id == posture_id:
			_posture_list.select(i)
			_on_posture_selected(i)
			break
	# Auto-enable zone move mode so the big center gizmo appears
	if not _zone_move_mode:
		_zone_move_mode = true
		_zone_move_button.text = "Move contact area"
		_refresh_gizmos()
		_status_label.text = "Zone move mode: ON (click zone mesh to edit)"

func _on_ghost_moved(posture_id: int, new_position: Vector3) -> void:
	if _player == null or not _current_def is PostureDefinition:
		return
	if _current_def.posture_id != posture_id:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return
	# new_position is the ghost HANDLE base; add head offset to get HEAD position
	# before decomposing into definition fields (which store HEAD offset).
	var ghost = _player.posture.posture_ghosts.get(posture_id)
	var head_offset: Vector3 = Vector3.ZERO
	if ghost:
		var ghost_scale_y: float = _player.posture.POSTURE_GHOST_SCALE.y
		head_offset = ghost.global_transform.basis.y.normalized() * 0.4 * ghost_scale_y
	var head_pos: Vector3 = PaddleReach.clamp_head_with_floor(
		new_position + head_offset, PaddleReach.shoulder_world(_player),
		_player.COURT_FLOOR_Y + _current_def.paddle_floor_clearance)
	if ghost:
		ghost.global_position = head_pos - head_offset
	var offset: Vector3 = head_pos - _player.global_position
	var def = _current_def as PostureDefinition
	if def == null:
		return

	# Charge postures update charge_offset; normal postures update paddle offset
	if posture_id in [_player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND]:
		def.charge_paddle_offset = Vector3(
			offset.dot(forehand_axis),
			offset.y,
			offset.dot(forward_axis)
		)
	else:
		def.paddle_forehand_mul = offset.dot(forehand_axis)
		def.paddle_forward_mul = offset.dot(forward_axis)
		def.paddle_y_offset = offset.y

	_status_label.text = "Updated: %s ghost position" % def.display_name
	_mark_dirty()
	_paddle_tab.set_definition(def)
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.refresh_from_definition(def)
	_apply_section_preview()

## Immediately updates the purple zone mesh for the given posture definition.
## Called from _on_gizmo_moved so the box resizes in real time without waiting
## for the next _physics_process().
func _update_zone_mesh_from_def(def: PostureDefinition) -> void:
	if _player == null:
		return
	var zone_mi = _player.posture._posture_zone_bounds.get(def.posture_id)
	if zone_mi == null:
		return
	var mesh: BoxMesh = zone_mi.mesh as BoxMesh
	if mesh == null:
		return
	var fh_axis: Vector3 = _player._get_forehand_axis()
	var fwd_axis: Vector3 = _player._get_forward_axis()
	var zone_y_min_rel: float = _player.COURT_FLOOR_Y + def.zone_y_min - _player.global_position.y
	var zone_y_max_rel: float = _player.COURT_FLOOR_Y + def.zone_y_max - _player.global_position.y
	var zone_cx: float = (def.zone_x_min + def.zone_x_max) * 0.5
	var zone_cy: float = (zone_y_min_rel + zone_y_max_rel) * 0.5
	var zone_cz: float = def.zone_forward_offset
	zone_mi.position = fh_axis * zone_cx + Vector3.UP * zone_cy + fwd_axis * zone_cz
	mesh.size = Vector3(def.zone_x_max - def.zone_x_min, zone_y_max_rel - zone_y_min_rel, 0.15)
	zone_mi.look_at(zone_mi.global_position + fwd_axis, Vector3.UP, true)
	if _player.posture.has_method("_update_zone_face_planes"):
		_player.posture._update_zone_face_planes(zone_mi)

## Sync the posture ghost to match the definition fields.
## This ensures _process and _refresh_gizmos don't read stale gameplay positions.
## CRITICAL: rotation MUST be synced BEFORE position, because position uses basis.y.
func _sync_ghost_to_definition(def: PostureDefinition) -> void:
	if _player == null or _player.posture == null:
		return
	var ghost = _player.posture.posture_ghosts.get(def.posture_id)
	if ghost == null:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()

	# Sync ROTATION first — position math depends on ghost.basis.y
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = forward_axis.z
	var rot_deg: Vector3 = def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)
	ghost.rotation_degrees = rot_deg

	# Sync POSITION from definition fields
	var offset: Vector3 = forehand_axis * def.paddle_forehand_mul \
		+ forward_axis * def.paddle_forward_mul \
		+ Vector3(0.0, def.paddle_y_offset, 0.0)
	var ghost_scale_y: float = _player.posture.POSTURE_GHOST_SCALE.y
	var limited_head: Vector3 = PaddleReach.clamp_head_with_floor(
		_player.global_position + offset, PaddleReach.shoulder_world(_player),
		_player.COURT_FLOOR_Y + def.paddle_floor_clearance)
	var expected: Vector3 = limited_head - _player.global_position - ghost.basis.y.normalized() * 0.4 * ghost_scale_y
	if ghost.position.distance_to(expected) > 0.001:
		ghost.position = expected

func _on_gizmo_moved(field_name: String, new_position: Vector3) -> void:
	if _player == null or _current_def == null:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return
	if field_name == "paddle_position" and _current_def is PostureDefinition:
		new_position = PaddleReach.clamp_head_with_floor(
			new_position, PaddleReach.shoulder_world(_player),
			_player.COURT_FLOOR_Y + _current_def.paddle_floor_clearance)
	if field_name == "paddle_position" and _current_def is PostureDefinition and _keyframe_index != 1:
		var stage_offset: Vector3 = new_position - _player.global_position
		var target: PostureDefinition = SwingPath.endpoint(_current_def, _keyframe_index)
		for i in range(3):
			target.set(PADDLE_POSITION_FIELDS[i], [stage_offset.dot(forehand_axis), stage_offset.y, stage_offset.dot(forward_axis)][i])
		_store_keyframe_paddle(target)
		_mark_dirty()
		_bind_keyframe_inspectors()
		_apply_section_preview()
		return
	var offset: Vector3 = new_position - _player.global_position
	var def = _current_def as PostureDefinition
	if def != null:
		match field_name:
			"paddle_position":
				# Store the raw head offset directly — paddle_* fields represent HEAD position,
				# not handle position. Gameplay subtracts b.y * 0.4 later to get the handle.
				def.paddle_forehand_mul = offset.dot(forehand_axis)
				def.paddle_forward_mul = offset.dot(forward_axis)
				def.paddle_y_offset = offset.y
				# Directly move ghost to match gizmo (ghost is source of truth)
				var ghost = _player.posture.posture_ghosts.get(def.posture_id)
				if ghost:
					# Use POSTURE_GHOST_SCALE so editor placement matches gameplay exactly.
					# NOTE: ghost.basis.y already includes node scale; normalize first
					# to avoid double-scaling (0.4 * scale * scale).
					var ghost_scale_y: float = _player.posture.POSTURE_GHOST_SCALE.y
					ghost.position = offset - ghost.basis.y.normalized() * 0.4 * ghost_scale_y
				_status_label.text = "Updated: %s position" % def.display_name
			"zone_left":
				def.zone_x_min = offset.dot(forehand_axis)
				_status_label.text = "Updated: %s zone x_min" % def.display_name
			"zone_right":
				def.zone_x_max = offset.dot(forehand_axis)
				_status_label.text = "Updated: %s zone x_max" % def.display_name
			"zone_bottom":
				# zone_y_min is height above COURT_FLOOR_Y, not relative to player Y
				def.zone_y_min = new_position.y - _player.COURT_FLOOR_Y
				_status_label.text = "Updated: %s zone y_min" % def.display_name
			"zone_top":
				def.zone_y_max = new_position.y - _player.COURT_FLOOR_Y
				_status_label.text = "Updated: %s zone y_max" % def.display_name
			"zone_front", "zone_back":
				var half_z := 0.075
				if field_name == "zone_front":
					def.zone_forward_offset = offset.dot(forward_axis) - half_z
				else:
					def.zone_forward_offset = offset.dot(forward_axis) + half_z
				_status_label.text = "Updated: %s zone_forward_offset" % def.display_name
			"zone_center":
				# Move entire zone while preserving width/height
				var new_center_x: float = offset.dot(forehand_axis)
				var new_center_y: float = new_position.y - _player.COURT_FLOOR_Y
				var width: float = def.zone_x_max - def.zone_x_min
				var height: float = def.zone_y_max - def.zone_y_min
				def.zone_x_min = new_center_x - width / 2.0
				def.zone_x_max = new_center_x + width / 2.0
				def.zone_y_min = new_center_y - height / 2.0
				def.zone_y_max = new_center_y + height / 2.0
				def.zone_forward_offset = offset.dot(forward_axis)
				_status_label.text = "Updated: %s zone center" % def.display_name
		# Immediately update zone mesh so handles don't snap back before next physics frame
		if field_name.begins_with("zone_"):
			var zone_field: String = {
				"zone_bottom": "zone_y_min", "zone_top": "zone_y_max",
				"zone_left": "zone_x_min", "zone_right": "zone_x_max",
			}.get(field_name, "")
			_normalize_zone_bounds(zone_field)
			if _player.posture.has_method("refresh_posture_zones"):
				_player.posture.refresh_posture_zones()
			_update_zone_mesh_from_def(def)
		_mark_dirty()
		_paddle_tab.set_definition(def)
		_contact_tab.set_definition(def)
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.refresh_from_definition(def)
		_apply_section_preview()

func _on_gizmo_rotated(field_name: String, euler_delta: Vector3) -> void:
	if _current_def == null:
		return
	var body_def = _edit_def if _edit_def else _current_def
	var fields: Dictionary = {}
	match field_name:
		"hip_rotation": fields = {"hip_yaw_deg": body_def.hip_yaw_deg + euler_delta.y}
		"torso_rotation": fields = {"torso_pitch_deg": body_def.torso_pitch_deg + euler_delta.x, "torso_yaw_deg": body_def.torso_yaw_deg + euler_delta.y, "torso_roll_deg": body_def.torso_roll_deg + euler_delta.z}
		"head_rotation": fields = {"head_pitch_deg": body_def.head_pitch_deg + euler_delta.x, "head_yaw_deg": body_def.head_yaw_deg + euler_delta.y}
	for field in fields:
		body_def.set(field, fields[field])
		_on_keyframe_field_changed(field, fields[field])
	_bind_keyframe_inspectors()

func _on_drag_ended() -> void:
	if _current_def == null:
		return
	print(_format_verified_drag(_current_def))
	_mark_dirty()

func _format_verified_drag(def) -> String:
	var s := "[VERIFIED DRAG] %s" % def.display_name
	if def is PostureDefinition:
		s += " | fh=%.4f fwd=%.4f y=%.4f" % [def.paddle_forehand_mul, def.paddle_forward_mul, def.paddle_y_offset]
		if def.has_zone:
			s += " | zone=[%.3f..%.3f] y=[%.3f..%.3f] z=%.3f" % [def.zone_x_min, def.zone_x_max, def.zone_y_min, def.zone_y_max, def.zone_forward_offset]
		s += " | pitch=%.1f yaw=%.1f roll=%.1f" % [def.paddle_pitch_base_deg, def.paddle_yaw_base_deg, def.paddle_roll_base_deg]
	elif def is BasePoseDefinition:
		s += " | pitch=%.1f yaw=%.1f roll=%.1f" % [def.pitch_deg, def.yaw_deg, def.roll_deg]
	return s

func _on_revert_pose() -> void:
	if _current_def == null:
		return
	var key = _dirty_key(_current_def)
	var saved = _saved_snapshots.get(key)
	if saved == null:
		return
	for property in saved.get_property_list():
		if property["usage"] & PROPERTY_USAGE_STORAGE and property["name"] != "script":
			var value = saved.get(property["name"])
			_current_def.set(property["name"], value.duplicate(true) if value is Resource else value)
	_dirty_defs.erase(key)
	for inspector in [_body_tab, _paddle_tab, _charge_tab, _ft_tab, _contact_tab]:
		inspector.set_definition(_current_def)
	_bind_keyframe_inspectors()
	if _current_def is PostureDefinition:
		_sync_ghost_to_definition(_current_def)
		_update_zone_mesh_from_def(_current_def)
	_apply_section_preview()
	_refresh_gizmos()
	_update_save_all_button()
	_status_label.text = "Reverted unsaved edits: " + _current_def.display_name
