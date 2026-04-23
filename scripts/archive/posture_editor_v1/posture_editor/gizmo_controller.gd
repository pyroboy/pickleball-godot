extends Node3D

## Handles 3D gizmo interaction via raycasting
## - Mouse hover detection
## - Click-to-select
## - Drag-to-move (with axis constraints)
## - Visual feedback (highlight selected, show axes)

signal gizmo_selected(gizmo: GizmoHandle)
signal gizmo_deselected()
signal gizmo_drag_started(gizmo: GizmoHandle)
signal gizmo_drag_ended(gizmo: GizmoHandle)
signal gizmo_moved(gizmo: GizmoHandle, new_position: Vector3)
signal gizmo_rotated(gizmo: GizmoHandle, euler_delta: Vector3)

var _camera: Camera3D
var _camera_rig: CameraRig  # Reference to camera rig to cancel orbit drag when dragging gizmos
var _selected_gizmo = null
var _hovered_gizmo = null
var _dragging: bool = false
var _drag_plane: Plane
var _drag_start_pos: Vector3
var _drag_start_mouse: Vector2

# Axis constraints
enum Constraint { NONE, X, Y, Z, XY, XZ, YZ }
var _current_constraint: Constraint = Constraint.NONE

# Visual feedback
var _selection_highlight: MeshInstance3D
var _axis_lines: Node3D
var _tab_label: Label3D

## Reference to PostureEditorUI — used to block gizmo input when mouse is over UI.
var _posture_editor_ui: Control = null

func set_posture_editor_ui(ui: Control) -> void:
	_posture_editor_ui = ui

## Returns true if the mouse is currently over the posture editor UI panel.
func _is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	if _posture_editor_ui == null or not _posture_editor_ui.visible:
		return false
	var rect: Rect2 = _posture_editor_ui.get_global_rect()
	return rect.has_point(mouse_pos)

# Body-part colliders for hover detection (invisible spheres at body part positions)
# Maps body_part_name → StaticBody3D
var _body_part_colliders: Dictionary = {}

# Body-part meshes that glow on hover (actual player body meshes)
# Maps body_part_name → MeshInstance3D
var _body_part_meshes: Dictionary = {}

# Original materials for body meshes (restored after glow ends)
# Maps MeshInstance3D → original material_override (or null)
var _original_materials: Dictionary = {}

# Currently hovered body part name ("" if none)
var _hovered_body_part: String = ""
var _last_hovered_body_part: String = ""

# Collider radius for body part hover detection
const _BODY_COLLIDER_RADIUS := 0.18

# Glow mesh settings (used as material override on actual body meshes)
const _GLOW_COLOR := Color(0.3, 1.0, 0.5, 0.6)  # Semi-transparent green

func _ready() -> void:
	# Find camera
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		push_warning("GizmoController: No camera found")
	
	# Create selection highlight
	_selection_highlight = MeshInstance3D.new()
	_selection_highlight.name = "SelectionHighlight"
	var highlight_mesh := SphereMesh.new()
	highlight_mesh.radius = 0.15
	highlight_mesh.height = 0.3
	_selection_highlight.mesh = highlight_mesh
	var highlight_mat := StandardMaterial3D.new()
	highlight_mat.albedo_color = Color(1, 1, 0, 0.3)
	highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_highlight.material_override = highlight_mat
	_selection_highlight.visible = false
	add_child(_selection_highlight)
	
	# Create axis lines container
	_axis_lines = Node3D.new()
	_axis_lines.name = "AxisLines"
	add_child(_axis_lines)
	
	# Create tab-name billboard label
	_tab_label = Label3D.new()
	_tab_label.name = "TabLabel"
	_tab_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tab_label.text = ""
	_tab_label.font_size = 48
	_tab_label.modulate = Color(1, 0.95, 0.6, 0.9)
	_tab_label.outline_modulate = Color(0.1, 0.1, 0.1, 0.8)
	_tab_label.pixel_size = 0.005
	_tab_label.no_depth_test = true
	_tab_label.visible = false
	add_child(_tab_label)

## Set the body-part names and positions for hover detection.
## Creates (or updates) invisible sphere colliders at each body part's world position.
## Call this each frame from _process() to keep colliders in sync with player movement.
func set_body_part_positions(positions: Dictionary) -> void:
	for body_part_name in positions:
		var world_pos: Vector3 = positions[body_part_name]
		_set_body_part_collider(body_part_name, world_pos)

func _set_body_part_collider(body_part_name: String, world_pos: Vector3) -> void:
	# Create/update invisible sphere collider for this body part
	var collider: StaticBody3D
	if _body_part_colliders.has(body_part_name):
		collider = _body_part_colliders[body_part_name]
	else:
		collider = StaticBody3D.new()
		collider.name = "Collider_%s" % body_part_name
		collider.collision_layer = 0  # Not physical — pure detection
		collider.collision_mask = 0
		var shape := SphereShape3D.new()
		shape.radius = _BODY_COLLIDER_RADIUS
		var col_shape := CollisionShape3D.new()
		col_shape.shape = shape
		collider.add_child(col_shape)
		add_child(collider)
		_body_part_colliders[body_part_name] = collider
	
	collider.global_position = world_pos

## Register body-part meshes for glow-on-hover.
## Call this once when editor opens, or when body parts may have changed.
## maps body_part_name → MeshInstance3D from the player's actual body mesh.
func set_body_part_meshes(meshes: Dictionary) -> void:
	for body_part_name in meshes:
		var mesh: MeshInstance3D = meshes[body_part_name]
		_body_part_meshes[body_part_name] = mesh
		# Store original material (may be null)
		if not _original_materials.has(mesh):
			_original_materials[mesh] = mesh.material_override

func _clear_body_part_colliders() -> void:
	for collider in _body_part_colliders.values():
		collider.queue_free()
	_body_part_colliders.clear()
	# Restore original materials on all body meshes
	for mesh in _original_materials:
		mesh.material_override = _original_materials[mesh]
	_original_materials.clear()
	_body_part_meshes.clear()

## Returns the body_part_name closest to the given ray, or "" if none.
func _raycast_body_parts(ray_origin: Vector3, ray_dir: Vector3) -> String:
	var closest_body_part: String = ""
	var closest_dist: float = INF
	
	for body_part_name in _body_part_colliders:
		var collider: StaticBody3D = _body_part_colliders[body_part_name]
		# Distance from ray to sphere center
		var to_collider: Vector3 = collider.global_position - ray_origin
		var proj_len: float = to_collider.dot(ray_dir)
		if proj_len < 0:
			continue  # Ray points away
		var closest_point: Vector3 = ray_origin + ray_dir * proj_len
		var dist: float = closest_point.distance_to(collider.global_position)
		if dist < _BODY_COLLIDER_RADIUS and proj_len < closest_dist:
			closest_dist = proj_len
			closest_body_part = body_part_name
	
	return closest_body_part

func _input(event: InputEvent) -> void:
	if not _camera:
		return
	
	# Block gizmo input when mouse is over the posture editor UI panel.
	# Do NOT consume here — Controls' gui_input runs AFTER _input, so marking
	# the event handled would block button/slider clicks in the panel.
	var mouse_over_ui := _is_mouse_over_ui(event.position) if event is InputEventMouse else false
	if event is InputEventMouse and mouse_over_ui:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_select_gizmo(event.position)
				# Immediately update drag so gizmo snaps to body part on the FIRST frame.
				# Without this, the gizmo only moves on the next mouse-move event, causing
				# a visual jump from its stale creation position to wherever the ray lands.
				if _dragging:
					_update_drag(event.position)
					get_viewport().set_input_as_handled()
			else:
				var was_dragging := _dragging
				_stop_drag()
				# Only consume the release if we were actually dragging a gizmo.
				# Otherwise let it propagate so the camera rig can stop orbiting.
				if was_dragging:
					get_viewport().set_input_as_handled()
				
	elif event is InputEventMouseMotion:
		if _dragging and _selected_gizmo:
			_update_drag(event.position)
			get_viewport().set_input_as_handled()
		else:
			_update_hover(event.position)

func _try_select_gizmo(screen_pos: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)
	
	# ── 1. Try to click an already-visible gizmo (paddle gizmos, revealed body gizmos)
	var closest_gizmo: GizmoHandle = null
	var closest_dist := INF
	
	for child in get_children():
		if child is GizmoHandle and child.visible:
			var hit_dist: float = child.raycast_test(ray_origin, ray_dir)
			if hit_dist >= 0 and hit_dist < closest_dist:
				closest_dist = hit_dist
				closest_gizmo = child
	
	if closest_gizmo:
		_select_gizmo(closest_gizmo)
		_start_drag(closest_gizmo, screen_pos)
		return
	
	# ── 2. No gizmo clicked — check if hovering a body part (click to reveal)
	# If raycast hits a body part collider, the mesh glow is active (applied in _update_hover)
	var body_part_hit: String = _raycast_body_parts(ray_origin, ray_dir)
	if body_part_hit != "":
		var gizmo_for_body: GizmoHandle = _find_gizmo_for_body_part(body_part_hit)
		if gizmo_for_body:
			gizmo_for_body.visible = true
			_select_gizmo(gizmo_for_body)
			_start_drag(gizmo_for_body, screen_pos)
			return
	
	# ── 3. Nothing hit — deselect
	_deselect_gizmo()

func _select_gizmo(gizmo: GizmoHandle) -> void:
	if _selected_gizmo:
		# Hide previous body gizmo and restore its mesh material when switching
		if _selected_gizmo != gizmo and _selected_gizmo.body_part_name != "":
			_selected_gizmo.visible = false
			# Restore original material on the previous body mesh
			if _body_part_meshes.has(_selected_gizmo.body_part_name):
				var prev_mesh: MeshInstance3D = _body_part_meshes[_selected_gizmo.body_part_name]
				if _original_materials.has(prev_mesh):
					prev_mesh.material_override = _original_materials[prev_mesh]
		_selected_gizmo.set_selected(false)
	
	_selected_gizmo = gizmo
	gizmo.set_selected(true)
	
	# Update highlight
	_selection_highlight.visible = true
	_selection_highlight.global_position = gizmo.global_position
	
	# Show axis lines
	_show_axis_lines(gizmo.global_position)
	
	# Show tab label on selected gizmo
	_tab_label.global_position = gizmo.global_position + Vector3(0, 0.3, 0)
	_tab_label.text = "[%s]" % gizmo.tab_name
	_tab_label.visible = true
	
	# Ensure body gizmo is visible when selected (it may have been revealed by hover)
	# Restore the body mesh material since the gizmo itself is now visible
	if gizmo.body_part_name != "":
		gizmo.visible = true
		if _body_part_meshes.has(gizmo.body_part_name):
			var mesh: MeshInstance3D = _body_part_meshes[gizmo.body_part_name]
			if _original_materials.has(mesh):
				mesh.material_override = _original_materials[mesh]
	
	gizmo_selected.emit(gizmo)

func _deselect_gizmo() -> void:
	if _selected_gizmo:
		# Hide body gizmos and restore body mesh material when deselecting
		if _selected_gizmo.body_part_name != "":
			_selected_gizmo.visible = false
			# Restore original material on the body mesh
			if _body_part_meshes.has(_selected_gizmo.body_part_name):
				var mesh: MeshInstance3D = _body_part_meshes[_selected_gizmo.body_part_name]
				if _original_materials.has(mesh):
					mesh.material_override = _original_materials[mesh]
		_selected_gizmo.set_selected(false)
		_selected_gizmo = null
	
	_selection_highlight.visible = false
	_axis_lines.visible = false
	_tab_label.visible = false
	
	gizmo_deselected.emit()

func _update_hover(screen_pos: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)
	
	# ── 0. Body-part hover detection (always runs, even during body gizmo drag)
	# This must happen BEFORE the early return so we can detect hover-deselect.
	_hovered_body_part = _raycast_body_parts(ray_origin, ray_dir)
	
	# If hovering a different body part than selected, deselect and stop drag.
	# This allows orbiting camera while hovering body parts without being stuck in drag.
	if _dragging and _selected_gizmo and _selected_gizmo.body_part_name != "":
		if _hovered_body_part != "" and _hovered_body_part != _selected_gizmo.body_part_name:
			_deselect_gizmo()
			if _dragging:
				_stop_drag()
			# Don't return — continue to normal hover detection
	
	# Skip rest of body-part hover check while dragging a body gizmo (prevents flicker)
	if _dragging and _selected_gizmo and _selected_gizmo.body_part_name != "":
		return
	
	# ── 1. Body-part detection — show glow mesh on hover ─────────────────────
	# Reveal gizmo on hover (body part glow already applied below).
	# This lets users see the gizmo before deciding to click and drag.
	var gizmo_for_body: GizmoHandle
	if _hovered_body_part != "":
		gizmo_for_body = _find_gizmo_for_body_part(_hovered_body_part)
		if gizmo_for_body and not gizmo_for_body.visible:
			gizmo_for_body.visible = true
		
		# Glow the actual body mesh for currently hovered body part
		if _body_part_meshes.has(_hovered_body_part):
			var mesh: MeshInstance3D = _body_part_meshes[_hovered_body_part]
			var glow_mat := StandardMaterial3D.new()
			glow_mat.albedo_color = _GLOW_COLOR
			glow_mat.emission_enabled = true
			glow_mat.emission = _GLOW_COLOR
			glow_mat.emission_energy_multiplier = 1.5
			glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = glow_mat
		
		# Show tab label at body-part position
		var gizmo_for_label: GizmoHandle = _selected_gizmo if _selected_gizmo else gizmo_for_body
		if gizmo_for_label:
			var label_pos: Vector3
			if _body_part_colliders.has(_hovered_body_part):
				label_pos = _body_part_colliders[_hovered_body_part].global_position
			else:
				label_pos = gizmo_for_body.global_position if gizmo_for_body else Vector3.ZERO
			_tab_label.global_position = label_pos + Vector3(0, 0.3, 0)
			_tab_label.text = "[%s]" % gizmo_for_label.tab_name
			_tab_label.visible = true
	
	# Clear glow for previously-hovered body part (restore original material)
	if _hovered_body_part != _last_hovered_body_part:
		if _last_hovered_body_part != "":
			# Restore original material on the body mesh
			if _body_part_meshes.has(_last_hovered_body_part):
				var prev_mesh: MeshInstance3D = _body_part_meshes[_last_hovered_body_part]
				if _original_materials.has(prev_mesh):
					prev_mesh.material_override = _original_materials[prev_mesh]
			# Hide gizmo if it was revealed but not selected
			var prev_gizmo: GizmoHandle = _find_gizmo_for_body_part(_last_hovered_body_part)
			if prev_gizmo and prev_gizmo != _selected_gizmo:
				prev_gizmo.visible = false
		_last_hovered_body_part = _hovered_body_part
		
		# Auto-deselect previously selected body gizmo when hovering a different body part.
		# This keeps only one body gizmo visible at a time (click-to-reveal per body part).
		# Note: For active drag, the hover-deselect above handles stopping the drag first.
		if _selected_gizmo and _selected_gizmo.body_part_name != "" and _hovered_body_part != _selected_gizmo.body_part_name:
			_deselect_gizmo()
	
	# ── 2. Gizmo hover detection ─────────────────────────────────────────────
	# Only check paddle gizmos (body gizmos are click-to-reveal only)
	var hovered: GizmoHandle = null
	var closest_dist := INF
	
	for child in get_children():
		if child is GizmoHandle and child.visible:
			# Skip body-part gizmos (they're revealed by clicking body glow)
			if child.body_part_name != "":
				continue
			var hit_dist: float = child.raycast_test(ray_origin, ray_dir)
			if hit_dist >= 0 and hit_dist < closest_dist:
				closest_dist = hit_dist
				hovered = child
	
	if hovered != _hovered_gizmo:
		if _hovered_gizmo:
			_hovered_gizmo.set_hovered(false)
		_hovered_gizmo = hovered
		if _hovered_gizmo:
			_hovered_gizmo.set_hovered(true)
	
	# ── 3. Tab label (show on hovered gizmo OR body glow) ───────────────────
	if _hovered_gizmo:
		_tab_label.global_position = _hovered_gizmo.global_position + Vector3(0, 0.3, 0)
		_tab_label.text = "[%s]" % _hovered_gizmo.tab_name
		_tab_label.visible = true
	elif _hovered_body_part == "" and not _selected_gizmo:
		_tab_label.visible = false

## Find the gizmo with the given body_part_name (regardless of visibility).
func _find_gizmo_for_body_part(body_part_name: String) -> GizmoHandle:
	for child in get_children():
		if child is GizmoHandle and child.body_part_name == body_part_name:
			return child
	return null

func _start_drag(gizmo: GizmoHandle, screen_pos: Vector2) -> void:
	_dragging = true
	# Cancel any in-progress orbit drag so camera doesn't fight with gizmo dragging.
	if _camera_rig:
		_camera_rig.cancel_orbit_drag()
	_drag_start_pos = gizmo.global_position
	_drag_start_mouse = screen_pos
	
	# Create drag plane facing camera — used for ALL gizmo types (including body gizmos).
	# For body gizmos the drag updates the posture definition offset, which the IK system
	# uses to recompute the body-part position on subsequent frames.
	var to_gizmo := (_drag_start_pos - _camera.global_position).normalized()
	_drag_plane = Plane(to_gizmo, _drag_start_pos)
	
	gizmo_drag_started.emit(gizmo)

func _update_drag(screen_pos: Vector2) -> void:
	if not _selected_gizmo:
		return
	
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)
	
	# Intersect with drag plane
	var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return
	
	var new_pos: Vector3 = intersection
	
	# Rotation gizmos: compute and emit rotation delta (independent of position override).
	# This updates on every frame while dragging so rotation feels smooth.
	if _selected_gizmo.gizmo_type == GizmoHandle.GizmoType.ROTATION:
		var rotation_gizmo := _selected_gizmo as RotationGizmo
		if rotation_gizmo:
			var euler_delta := rotation_gizmo.calculate_rotation_from_drag(_drag_start_pos, new_pos, _camera.global_position)
			gizmo_rotated.emit(_selected_gizmo, euler_delta)
			# Update drag start for relative movement next frame
			_drag_plane = Plane((new_pos - _camera.global_position).normalized(), new_pos)
			_drag_start_pos = new_pos
	# Position gizmos (including body-part gizmos): update position and emit moved signal.
	# For body gizmos this drives the posture-definition offset update via _on_gizmo_moved.
	else:
		_selected_gizmo.global_position = new_pos
		_selection_highlight.global_position = new_pos
		_update_axis_lines_position(new_pos)
		gizmo_moved.emit(_selected_gizmo, new_pos)
	
	# Keep tab label on top of gizmo while dragging
	_tab_label.global_position = _selected_gizmo.global_position + Vector3(0, 0.3, 0)

func _stop_drag() -> void:
	if _dragging and _selected_gizmo:
		gizmo_drag_ended.emit(_selected_gizmo)
		_deselect_gizmo()
	_dragging = false
	_current_constraint = Constraint.NONE

func _show_axis_lines(pos: Vector3) -> void:
	_axis_lines.visible = true
	_update_axis_lines_position(pos)

func _update_axis_lines_position(pos: Vector3) -> void:
	_axis_lines.global_position = pos
	_axis_lines.global_rotation = Vector3.ZERO

func set_constraint(constraint: Constraint) -> void:
	_current_constraint = constraint

func set_camera(camera: Camera3D) -> void:
	_camera = camera

func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig

func add_gizmo_handle(gizmo: GizmoHandle) -> void:
	add_child(gizmo)

func remove_gizmo(gizmo: GizmoHandle) -> void:
	if gizmo == _selected_gizmo:
		_deselect_gizmo()
	if gizmo == _hovered_gizmo:
		_hovered_gizmo = null
	gizmo.queue_free()

func clear_all_gizmos() -> void:
	for child in get_children():
		if child is GizmoHandle:
			child.queue_free()
	_selected_gizmo = null
	_hovered_gizmo = null
	_selection_highlight.visible = false
	_axis_lines.visible = false

func get_selected_gizmo() -> GizmoHandle:
	return _selected_gizmo

func _process(_delta: float) -> void:
	pass  # Body part positions are pushed from posture_editor_ui._process

## Push body-part world positions from the editor so colliders stay in sync
## with the player's animated skeleton. Call this every frame.
func update_body_part_positions(positions: Dictionary) -> void:
	for body_part_name in positions:
		_set_body_part_collider(body_part_name, positions[body_part_name])
