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

# Data
var _library: PostureLibrary
var _base_pose_library: BasePoseLibrary
var _current_def = null
var _is_base_pose_mode: bool = false

# Player / Preview / Gizmos / Transport
var _player = null
var _pose_trigger = null
var _preview_button: Button
var _swing_button: Button
var _save_button: Button
var _gizmo_controller: GizmoControllerV2 = null
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

func _ready() -> void:
	# Right-side sheet, same footprint as the legacy editor so the 3D court
	# stays visible on the left.
	anchor_left = 0.62
	anchor_right = 0.995
	anchor_top = 0.02
	anchor_bottom = 0.98
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.18, 0.96)
	sb.border_color = Color(0.42, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Posture Editor v2"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "Close (Q)"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	# Workspace toggle
	var workspace_row := HBoxContainer.new()
	workspace_row.add_theme_constant_override("separation", 8)
	vbox.add_child(workspace_row)

	_workspace_button = Button.new()
	_workspace_button.text = "Workspace: Stroke Postures"
	_workspace_button.pressed.connect(_on_toggle_workspace)
	workspace_row.add_child(_workspace_button)

	# Main split: list on left, inspector on right
	var main_split := HSplitContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 160
	vbox.add_child(main_split)

	# Left: posture list
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(left_vbox)

	var list_title := Label.new()
	list_title.text = "Postures"
	list_title.add_theme_font_size_override("font_size", 16)
	list_title.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	left_vbox.add_child(list_title)

	_posture_list = ItemList.new()
	_posture_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posture_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_posture_list.custom_minimum_size = Vector2(140, 200)
	_posture_list.item_selected.connect(_on_posture_selected)
	left_vbox.add_child(_posture_list)

	# Preview toggle button
	_preview_button = Button.new()
	_preview_button.text = "Toggle Preview"
	_preview_button.disabled = true
	_preview_button.pressed.connect(_on_preview_pose)
	left_vbox.add_child(_preview_button)

	# Swing preview button
	_swing_button = Button.new()
	_swing_button.text = "Preview Swing"
	_swing_button.disabled = true
	_swing_button.pressed.connect(_on_preview_swing)
	left_vbox.add_child(_swing_button)

	# Save button
	_save_button = Button.new()
	_save_button.text = "Save to .tres"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save)
	left_vbox.add_child(_save_button)

	# Status label (under list)
	_status_label = Label.new()
	_status_label.text = "Select a posture to edit"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.9))
	left_vbox.add_child(_status_label)

	# Right: inspector tabs
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var right_sb := StyleBoxFlat.new()
	right_sb.bg_color = Color(0.07, 0.10, 0.14, 0.85)
	right_sb.set_corner_radius_all(8)
	right_panel.add_theme_stylebox_override("panel", right_sb)
	main_split.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 8)
	right_margin.add_theme_constant_override("margin_right", 8)
	right_margin.add_theme_constant_override("margin_top", 8)
	right_margin.add_theme_constant_override("margin_bottom", 8)
	right_panel.add_child(right_margin)

	var tab_container := TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.tab_changed.connect(_on_tab_changed)
	right_margin.add_child(tab_container)

	# Build tabs
	_build_tabs(tab_container)

	# Load libraries
	_library = PostureLibrary.instance()
	_base_pose_library = BasePoseLibrary.instance()
	_populate_list()

func open() -> void:
	if visible:
		return
	_expand_window()
	visible = true
	if _player and _player.posture:
		_player.posture.editor_preview_mode = true
	editor_opened.emit()

func close() -> void:
	if not visible:
		return
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
	_restore_window()
	visible = false
	editor_closed.emit()

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
	return get_global_rect().has_point(pos)

func set_player(player) -> void:
	_player = player
	if _player and _player.get_parent():
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

func _process(_delta: float) -> void:
	if _pose_trigger:
		_pose_trigger.update()
	# Keep paddle gizmo synced with GHOST head center (ghost is source of truth in editor)
	if _gizmo_controller and _current_def and _player and _player.posture:
		var paddle_gizmo = _gizmo_controller.get_node_or_null("paddle_position")
		if paddle_gizmo:
			var ghost = _player.posture.posture_ghosts.get(_current_def.posture_id)
			if ghost:
				var ghost_head_pos: Vector3 = ghost.global_position + ghost.global_transform.basis.y * 0.4
				paddle_gizmo.global_position = ghost_head_pos
		# Keep zone corner handles glued to the purple box (updates during drag)
		# Skip while dragging a zone handle so the handle doesn't snap back before
		# _physics_process() has a chance to update the mesh.
		if not _gizmo_controller.is_dragging_zone_handle():
			var zone_mi = _player.posture._posture_zone_bounds.get(_current_def.posture_id)
			if zone_mi:
				var zone_mesh: BoxMesh = zone_mi.mesh as BoxMesh
				var half_size: Vector3 = zone_mesh.size / 2.0
				var basis: Basis = zone_mi.global_transform.basis
				var center: Vector3 = zone_mi.global_position
				var corner_offsets := [
					Vector3(-half_size.x, -half_size.y, -half_size.z),
					Vector3( half_size.x, -half_size.y, -half_size.z),
					Vector3(-half_size.x,  half_size.y, -half_size.z),
					Vector3( half_size.x,  half_size.y, -half_size.z),
				]
				var corner_names := ["zone_BLF","zone_BRF","zone_TLF","zone_TRF"]
				for i in range(4):
					var gizmo = _gizmo_controller.get_node_or_null(corner_names[i])
					if gizmo:
						gizmo.global_position = center + basis * corner_offsets[i]
				var face_offsets := [
					Vector3(0.0, 0.0, -half_size.z),
					Vector3(0.0, 0.0,  half_size.z),
				]
				var face_names := ["zone_front","zone_back"]
				for i in range(2):
					var gizmo = _gizmo_controller.get_node_or_null(face_names[i])
					if gizmo:
						gizmo.global_position = center + basis * face_offsets[i]
	# After transition finishes, snap paddle to match ghost so all three align
	if _pose_transition_tween == null and _current_def and _player and _player.posture and _player.paddle_node:
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
	_workspace_button.text = "Workspace: Base Poses" if _is_base_pose_mode else "Workspace: Stroke Postures"
	_populate_list()
	_current_def = null
	_status_label.text = "Select a %s to edit" % ("base pose" if _is_base_pose_mode else "stroke posture")
	# Hide stroke-only tabs in base-pose mode
	_set_tab_hidden("Paddle", _is_base_pose_mode)
	_set_tab_hidden("Charge", _is_base_pose_mode)
	_set_tab_hidden("Follow-Through", _is_base_pose_mode)
	# Clear inspectors and gizmos
	_body_tab.set_definition(null)
	_paddle_tab.set_definition(null)
	_charge_tab.set_definition(null)
	_ft_tab.set_definition(null)
	if _gizmo_controller:
		_gizmo_controller.clear_all_gizmos()

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
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	for def in defs:
		_posture_list.add_item(def.display_name)

func _on_posture_selected(index: int) -> void:
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	if index < 0 or index >= defs.size():
		return
	_current_def = defs[index]
	_status_label.text = "Selected: %s" % _current_def.display_name
	posture_selected.emit(_current_def)
	print("[EDITOR V2] Selected ", _current_def.display_name)
	# Populate inspectors
	_body_tab.set_definition(_current_def)
	_paddle_tab.set_definition(_current_def)
	_charge_tab.set_definition(_current_def)
	_ft_tab.set_definition(_current_def)
	# Enable preview for stroke postures only
	if _preview_button:
		_preview_button.disabled = _is_base_pose_mode
	if _swing_button:
		_swing_button.disabled = _is_base_pose_mode
		_swing_button.text = "Preview Swing"
	if _save_button:
		_save_button.disabled = false
	# Auto-preview pose for stroke postures
	_trigger_pose_preview()
	# Update gizmos
	_refresh_gizmos()
	# Show relevant ghosts for the selected posture
	if _player and _player.posture:
		_player.posture.set_editor_solo_posture_id(_current_def.posture_id)

func _trigger_pose_preview() -> void:
	if _player == null or _current_def == null:
		return
	if _is_base_pose_mode:
		return
	# Stop swing preview if running
	if _transition_player and _transition_player.is_playing():
		_transition_player.stop()
		if _swing_button:
			_swing_button.text = "Preview Swing"
	
	var target_def = _current_def as PostureDefinition
	if target_def == null:
		return
	
	var current_posture_id: int = _player.paddle_posture
	var ready_posture_id: int = _player.PaddlePosture.READY
	
	# Already at target — nothing to do
	if current_posture_id == target_def.posture_id:
		return
	
	var current_def: PostureDefinition = _library.get_def(current_posture_id)
	var ready_def: PostureDefinition = _library.get_def(ready_posture_id)
	
	# Kill any existing transition
	if _pose_transition_tween and _pose_transition_tween.is_valid():
		_pose_transition_tween.kill()
		_pose_transition_tween = null
	
	# Simple single-stage lerp if we don't have current/ready defs, or target is READY
	if current_def == null or ready_def == null or target_def.posture_id == ready_posture_id:
		_player.paddle_posture = target_def.posture_id
		if _player.posture:
			_player.posture.force_posture_update(target_def)
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
	if _player == null or _current_def == null:
		return
	if _is_base_pose_mode:
		return
	_trigger_pose_preview()

func _on_preview_swing() -> void:
	if _player == null or _current_def == null or _is_base_pose_mode:
		return
	if _transition_player == null:
		_transition_player = TransitionPlayer.new()
		add_child(_transition_player)
	# Build transition defs
	var def := _current_def as PostureDefinition
	if def == null:
		return
	var ready_def: PostureDefinition = _library.get_def(20) # READY
	var charge_def: PostureDefinition = null
	if def.family == 0:
		charge_def = _library.get_def(8) # CHARGE_FOREHAND
	elif def.family == 1:
		charge_def = _library.get_def(9) # CHARGE_BACKHAND
	if charge_def == null:
		charge_def = def
	# Build follow-through preview
	var ft_def: PostureDefinition = def.lerp_with(def, 0.0)
	ft_def.paddle_forehand_mul += def.ft_paddle_offset.x
	ft_def.paddle_y_offset += def.ft_paddle_offset.y
	ft_def.paddle_forward_mul += def.ft_paddle_offset.z
	ft_def.paddle_pitch_base_deg += def.ft_paddle_rotation_deg.x
	ft_def.paddle_yaw_base_deg += def.ft_paddle_rotation_deg.y
	ft_def.paddle_roll_base_deg += def.ft_paddle_rotation_deg.z
	ft_def.hip_yaw_deg += def.ft_hip_uncoil_deg
	_transition_player.setup(_player, ready_def, charge_def, def, [ft_def])
	if _transition_player.is_playing():
		_transition_player.pause()
		_swing_button.text = "Preview Swing"
		_status_label.text = "Paused swing preview"
	else:
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.release_pose()
		_transition_player.play()
		_swing_button.text = "Pause Swing"
		_status_label.text = "Playing swing preview"

func _on_save() -> void:
	if _current_def == null:
		return
	var path: String = ""
	var filename: String = ""
	if _is_base_pose_mode:
		var base: String = _current_def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		filename = "%02d_%s.tres" % [_current_def.base_pose_id, base]
		path = "res://data/base_poses/" + filename
	else:
		var base: String = _current_def.display_name.to_lower().replace(" ", "_").replace("-", "_")
		filename = "%02d_%s.tres" % [_current_def.posture_id, base]
		path = "res://data/postures/" + filename
	# Ensure directory exists ( defensive — Godot won't create it automatically )
	var dir_path := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir_path):
		var err_mkdir := DirAccess.make_dir_recursive_absolute(dir_path)
		if err_mkdir != OK:
			_status_label.text = "Failed to create directory: %s (err %d)" % [dir_path, err_mkdir]
			push_warning("PostureEditorV2: failed to create directory %s (error %d)" % [dir_path, err_mkdir])
			return
	var err := ResourceSaver.save(_current_def, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err == OK:
		_current_def.resource_path = path
		_status_label.text = "Saved: %s" % filename
		print("[EDITOR V2] Saved ", path)
	else:
		_status_label.text = "Save failed: error %d — %s" % [err, error_string(err)]
		push_warning("PostureEditorV2: failed to save %s (error %d)" % [path, err])

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
			"stance_width", "front_foot_forward", "back_foot_back",
			"right_foot_yaw_deg", "left_foot_yaw_deg",
			"right_knee_pole", "left_knee_pole",
			"right_foot_offset", "left_foot_offset",
			"lead_foot", "crouch_amount", "weight_shift",
			"hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg",
			"body_yaw_deg", "body_pitch_deg", "body_roll_deg",
			"head_yaw_deg", "head_pitch_deg", "head_track_ball_weight",
			"right_hand_offset", "left_hand_offset",
			"right_elbow_pole", "left_elbow_pole",
			"left_hand_mode",
		],
		{
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
			"left_hand_mode": {"label": "Left Hand Mode", "type": "option", "items": ["Free", "PaddleNeck", "AcrossChest", "OverheadLift"]},
		}
	)
	_body_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Body", _body_tab)

	# ── Paddle tab (stroke only) ──
	_paddle_tab = SimpleInspector.new()
	_paddle_tab.name = "Paddle"
	_paddle_tab.build(
		[
			"paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset",
			"paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg",
			"paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg",
			"paddle_pitch_sign_source", "paddle_yaw_sign_source", "paddle_roll_sign_source",
			"paddle_floor_clearance",
			"has_zone", "zone_x_min", "zone_x_max", "zone_y_min", "zone_y_max", "zone_forward_offset",
		],
		{
			"paddle_forehand_mul": {"label": "Forehand Mul", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_forward_mul": {"label": "Forward Mul", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_y_offset": {"label": "Y Offset", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"paddle_pitch_base_deg": {"label": "Pitch Base", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_yaw_base_deg": {"label": "Yaw Base", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_roll_base_deg": {"label": "Roll Base", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_pitch_signed_deg": {"label": "Pitch Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_yaw_signed_deg": {"label": "Yaw Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_roll_signed_deg": {"label": "Roll Signed", "type": "float", "min": - 180.0, "max": 180.0, "step": 1.0},
			"paddle_pitch_sign_source": {"label": "Pitch Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_yaw_sign_source": {"label": "Yaw Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_roll_sign_source": {"label": "Roll Sign", "type": "option", "items": ["None", "SwingSign", "FwdSign"]},
			"paddle_floor_clearance": {"label": "Floor Clearance", "type": "float", "min": 0.0, "max": 0.8, "step": 0.01},
			"has_zone": {"label": "Has Commit Zone", "type": "bool"},
			"zone_x_min": {"label": "Zone X Min", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"zone_x_max": {"label": "Zone X Max", "type": "float", "min": - 2.0, "max": 2.0, "step": 0.01},
			"zone_y_min": {"label": "Zone Y Min", "type": "float", "min": - 1.0, "max": 2.0, "step": 0.01},
			"zone_y_max": {"label": "Zone Y Max", "type": "float", "min": - 1.0, "max": 2.5, "step": 0.01},
			"zone_forward_offset": {"label": "Zone Forward", "type": "float", "min": - 1.0, "max": 3.0, "step": 0.01},
		}
	)
	_paddle_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Paddle", _paddle_tab)

	# ── Charge tab (stroke only) ──
	_charge_tab = SimpleInspector.new()
	_charge_tab.name = "Charge"
	_charge_tab.build(
		[
			"charge_paddle_offset", "charge_paddle_rotation_deg",
			"charge_body_rotation_deg", "charge_hip_coil_deg", "charge_back_foot_load",
		],
		{
			"charge_paddle_offset": {"label": "Paddle Offset", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"charge_paddle_rotation_deg": {"label": "Paddle Rotation", "type": "vector3", "min": - 180.0, "max": 180.0, "step": 1.0},
			"charge_body_rotation_deg": {"label": "Body Rotation", "type": "float", "min": - 60.0, "max": 120.0, "step": 1.0},
			"charge_hip_coil_deg": {"label": "Hip Coil", "type": "float", "min": - 60.0, "max": 60.0, "step": 1.0},
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
			"ft_duration_strike", "ft_duration_sweep", "ft_duration_settle", "ft_duration_hold",
		],
		{
			"ft_paddle_offset": {"label": "Paddle Offset", "type": "vector3", "min": - 2.0, "max": 2.0, "step": 0.01},
			"ft_paddle_rotation_deg": {"label": "Paddle Rotation", "type": "vector3", "min": - 180.0, "max": 180.0, "step": 1.0},
			"ft_hip_uncoil_deg": {"label": "Hip Uncoil", "type": "float", "min": - 60.0, "max": 60.0, "step": 1.0},
			"ft_front_foot_load": {"label": "Front Foot Load", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
			"ft_duration_strike": {"label": "Strike Dur", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_sweep": {"label": "Sweep Dur", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_settle": {"label": "Settle Dur", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
			"ft_duration_hold": {"label": "Hold Dur", "type": "float", "min": 0.0, "max": 0.5, "step": 0.01},
		}
	)
	_ft_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Follow-Through", _ft_tab)

func _add_scroll_tab(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
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

func _on_tab_changed(_tab_index: int) -> void:
	pass

func _on_field_changed(_field: String, _value: Variant) -> void:
	if _current_def:
		_status_label.text = "Modified: %s" % _current_def.display_name
	_refresh_gizmos()

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
	if _player.skeleton:
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
	
	# Paddle position gizmo (stroke only)
	var def = _current_def as PostureDefinition
	if def == null:
		return
	var paddle_pos: Vector3
	var ghost = _player.posture.posture_ghosts.get(def.posture_id)
	if ghost:
		paddle_pos = ghost.global_position + ghost.global_transform.basis.y * 0.4
	else:
		var offset: Vector3 = forehand_axis * def.paddle_forehand_mul + forward_axis * def.paddle_forward_mul + Vector3(0.0, def.paddle_y_offset, 0.0)
		paddle_pos = _player.global_position + offset
	_gizmo_controller.add_position_gizmo("paddle_position", paddle_pos, Color(0.3, 0.9, 0.3), 0.08)

	# Zone bounds corner handles — 4 front corners + 2 face centers
	if def.has_zone:
		var zone_mi = _player.posture._posture_zone_bounds.get(def.posture_id)
		if zone_mi:
			var zone_mesh: BoxMesh = zone_mi.mesh as BoxMesh
			var half_size: Vector3 = zone_mesh.size / 2.0
			var basis: Basis = zone_mi.global_transform.basis
			var center: Vector3 = zone_mi.global_position
			var corners := [
				center + basis * Vector3(-half_size.x, -half_size.y, -half_size.z),  # BLF
				center + basis * Vector3( half_size.x, -half_size.y, -half_size.z),  # BRF
				center + basis * Vector3(-half_size.x,  half_size.y, -half_size.z),  # TLF
				center + basis * Vector3( half_size.x,  half_size.y, -half_size.z),  # TRF
			]
			var faces := [
				center + basis * Vector3(0.0, 0.0, -half_size.z),  # front face center
				center + basis * Vector3(0.0, 0.0,  half_size.z),  # back face center
			]
			var corner_names := ["zone_BLF","zone_BRF","zone_TLF","zone_TRF"]
			var corner_colors := [Color(1.0,0.3,0.3),Color(1.0,0.3,0.3),Color(0.3,0.3,1.0),Color(0.3,0.3,1.0)]
			var corner_sizes := [0.05,0.05,0.05,0.05]
			for i in range(4):
				_gizmo_controller.add_zone_handle(corner_names[i], corners[i], corner_colors[i], corner_sizes[i])
			var face_names := ["zone_front","zone_back"]
			var face_colors := [Color(0.9,0.5,0.2),Color(0.7,0.4,0.15)]
			var face_sizes := [0.06,0.06]
			for i in range(2):
				_gizmo_controller.add_zone_handle(face_names[i], faces[i], face_colors[i], face_sizes[i])

func _get_basis_from_rotation(rot_deg: Vector3) -> Basis:
	var b := Basis()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
	b = b * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
	b = b * Basis(Vector3.FORWARD, deg_to_rad(rot_deg.z))
	return b

func _on_ghost_selected(posture_id: int) -> void:
	if _posture_list == null:
		return
	var defs: Array = _base_pose_library.all_definitions() if _is_base_pose_mode else _library.all_definitions()
	for i in range(defs.size()):
		if defs[i].posture_id == posture_id:
			_posture_list.select(i)
			_on_posture_selected(i)
			return

func _on_ghost_moved(posture_id: int, new_position: Vector3) -> void:
	if _player == null or _current_def == null:
		return
	if _current_def.posture_id != posture_id:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return
	var offset: Vector3 = new_position - _player.global_position
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
	_paddle_tab.set_definition(def)
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.refresh_from_definition(def)

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

func _on_gizmo_moved(field_name: String, new_position: Vector3) -> void:
	if _player == null or _current_def == null:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return
	var offset: Vector3 = new_position - _player.global_position
	var def = _current_def as PostureDefinition
	if def != null:
		match field_name:
			"paddle_position":
				if _player.paddle_node == null:
					def.paddle_forehand_mul = offset.dot(forehand_axis)
					def.paddle_forward_mul = offset.dot(forward_axis)
					def.paddle_y_offset = offset.y
				else:
					var actual_basis_y: Vector3 = _player.paddle_node.global_transform.basis.y
					var posture_rot: Vector3 = def.resolve_paddle_rotation_deg(_player._get_swing_sign(), forward_axis.z)
					var posture_basis: Basis = _get_basis_from_rotation(posture_rot)
					var desired_head_offset: Vector3 = offset
					var corrected_offset: Vector3 = desired_head_offset - actual_basis_y * 0.4 + posture_basis.y * 0.4
					def.paddle_forehand_mul = corrected_offset.dot(forehand_axis)
					def.paddle_forward_mul = corrected_offset.dot(forward_axis)
					def.paddle_y_offset = corrected_offset.y
					# Directly move ghost to match gizmo (ghost is source of truth)
					var ghost = _player.posture.posture_ghosts.get(def.posture_id)
					if ghost:
						ghost.position = desired_head_offset - ghost.basis.y * 0.4
					# Directly move paddle to match gizmo
					_player.paddle_node.global_position = new_position - _player.paddle_node.global_transform.basis.y * 0.4
				_status_label.text = "Updated: %s position" % def.display_name
			"zone_BLF":
				def.zone_x_min = offset.dot(forehand_axis)
				def.zone_y_min = offset.y
				_status_label.text = "Updated: %s zone (x_min, y_min)" % def.display_name
			"zone_BRF":
				def.zone_x_max = offset.dot(forehand_axis)
				def.zone_y_min = offset.y
				_status_label.text = "Updated: %s zone (x_max, y_min)" % def.display_name
			"zone_TLF":
				def.zone_x_min = offset.dot(forehand_axis)
				def.zone_y_max = offset.y
				_status_label.text = "Updated: %s zone (x_min, y_max)" % def.display_name
			"zone_TRF":
				def.zone_x_max = offset.dot(forehand_axis)
				def.zone_y_max = offset.y
				_status_label.text = "Updated: %s zone (x_max, y_max)" % def.display_name
			"zone_front", "zone_back":
				var zone_mi = _player.posture._posture_zone_bounds.get(def.posture_id)
				var half_z = 0.075
				if zone_mi and zone_mi.mesh:
					var zm = zone_mi.mesh as BoxMesh
					if zm:
						half_z = zm.size.z / 2.0
				if field_name == "zone_front":
					# Front face is at center + fwd * half_z
					def.zone_forward_offset = offset.dot(forward_axis) - half_z
				else:
					# Back face is at center - fwd * half_z
					def.zone_forward_offset = offset.dot(forward_axis) + half_z
				_status_label.text = "Updated: %s zone_forward_offset" % def.display_name
		# Immediately update zone mesh so handles don't snap back before next physics frame
		if field_name.begins_with("zone_"):
			_update_zone_mesh_from_def(def)
		_paddle_tab.set_definition(def)
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.refresh_from_definition(def)

func _on_gizmo_rotated(field_name: String, euler_delta: Vector3) -> void:
	if _current_def == null:
		return
	var body_def = _current_def
	match field_name:
		"hip_rotation":
			body_def.hip_yaw_deg += euler_delta.y
		"torso_rotation":
			body_def.torso_pitch_deg += euler_delta.x
			body_def.torso_yaw_deg += euler_delta.y
			body_def.torso_roll_deg += euler_delta.z
		"head_rotation":
			body_def.head_pitch_deg += euler_delta.x
			body_def.head_yaw_deg += euler_delta.y
	_status_label.text = "Updated: %s rotation" % body_def.display_name
	_body_tab.set_definition(body_def)
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.refresh_from_definition(_current_def)
