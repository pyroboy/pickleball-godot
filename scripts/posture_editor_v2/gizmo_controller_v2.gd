class_name GizmoControllerV2 extends Node3D

## Simplified gizmo controller for v2.
## Handles mouse raycasting, selection, and drag for position and rotation gizmos.
## CP-ghost: also handles direct ghost click-and-drag and zone handle dragging.

signal gizmo_moved(field_name: String, new_position: Vector3)
signal gizmo_rotated(field_name: String, euler_delta: Vector3)
signal ghost_selected(posture_id: int)
signal ghost_moved(posture_id: int, new_position: Vector3)

var _camera: Camera3D
var _ui: Control
var _player = null
var _selected_gizmo = null
var _dragging: bool = false
var _drag_plane: Plane
var _is_rotation_drag: bool = false

# Ghost drag state
var _dragging_ghost: Node3D = null
var _dragging_ghost_id: int = -1

# Paddle drag state
var _dragging_paddle: bool = false

func set_camera(camera: Camera3D) -> void:
	_camera = camera

func set_ui(ui: Control) -> void:
	_ui = ui

func set_player(player) -> void:
	_player = player

func _is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	if _ui == null or not _ui.visible:
		return false
	return _ui.get_global_rect().has_point(mouse_pos)

func _input(event: InputEvent) -> void:
	if not _camera:
		return
	if event is InputEventMouse:
		if _is_mouse_over_ui(event.position):
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_select_gizmo(event.position)
				if _dragging:
					get_viewport().set_input_as_handled()
			else:
				var was_dragging := _dragging
				_stop_drag()
				if was_dragging:
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging and (_selected_gizmo != null or _dragging_ghost != null or _dragging_paddle):
			_update_drag(event.position)
			get_viewport().set_input_as_handled()

func _try_select_gizmo(screen_pos: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	# ── Ghost click takes priority over gizmos ──
	if _player and _player.posture:
		var ghost_result := _raycast_ghosts(ray_origin, ray_dir)
		if ghost_result.posture_id >= 0 and ghost_result.ghost != null:
			ghost_selected.emit(ghost_result.posture_id)
			_dragging_ghost = ghost_result.ghost
			_dragging_ghost_id = ghost_result.posture_id
			_dragging = true
			var to_ghost: Vector3 = (_dragging_ghost.global_position - _camera.global_position).normalized()
			_drag_plane = Plane(to_ghost, _dragging_ghost.global_position)
			return

	var closest_gizmo = null
	var closest_dist := INF
	# Check position gizmos
	for child in get_children():
		if child is PositionGizmoV2:
			var hit_dist: float = child.raycast_test(ray_origin, ray_dir)
			if hit_dist >= 0 and hit_dist < closest_dist:
				closest_dist = hit_dist
				closest_gizmo = child
	# Check rotation gizmos
	for child in get_children():
		if child is RotationGizmoV2:
			var axis: String = child.raycast_test(ray_origin, ray_dir)
			if axis != "":
				# Estimate hit distance from camera to gizmo center
				var to_center: Vector3 = child.global_position - ray_origin
				var proj: float = to_center.dot(ray_dir)
				if proj >= 0 and proj < closest_dist:
					closest_dist = proj
					closest_gizmo = child
					child._selected_axis = axis
	if closest_gizmo:
		_select_gizmo(closest_gizmo)
		_start_drag(closest_gizmo, screen_pos, ray_origin, ray_dir)
	else:
		# ── Paddle click fallback (only in editor preview mode) ──
		if _player and _player.paddle_node and _player.posture and _player.posture.editor_preview_mode:
			var space_state := get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.new()
			query.from = ray_origin
			query.to = ray_origin + ray_dir * 100.0
			query.collision_mask = 4  # Paddle is on collision_layer 4
			query.collide_with_bodies = true
			var result := space_state.intersect_ray(query)
			if result.has("position"):
				_dragging_paddle = true
				_dragging = true
				var to_paddle: Vector3 = (_player.paddle_node.global_position - _camera.global_position).normalized()
				_drag_plane = Plane(to_paddle, _player.paddle_node.global_position)
				return
		_deselect_gizmo()

## Raycast against posture ghosts. Returns {posture_id, ghost}.
## Checks both handle base and head center positions.
func _raycast_ghosts(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var best_id: int = -1
	var best_ghost: Node3D = null
	var best_proj: float = INF
	var THRESHOLD: float = 0.12

	if _player == null or _player.posture == null:
		return {"posture_id": -1, "ghost": null}

	for posture_id in _player.posture.posture_ghosts.keys():
		var ghost: Node3D = _player.posture.posture_ghosts[posture_id]
		if ghost == null:
			continue
		# Check handle base
		var handle_hit := _ray_point_hit(ray_origin, ray_dir, ghost.global_position, THRESHOLD)
		# Check head center
		var head_pos: Vector3 = ghost.global_position + ghost.global_transform.basis.y * 0.4 * _player.posture.POSTURE_GHOST_SCALE.y
		var head_hit := _ray_point_hit(ray_origin, ray_dir, head_pos, THRESHOLD)
		if handle_hit.is_valid and handle_hit.proj < best_proj:
			best_proj = handle_hit.proj
			best_id = posture_id
			best_ghost = ghost
		if head_hit.is_valid and head_hit.proj < best_proj:
			best_proj = head_hit.proj
			best_id = posture_id
			best_ghost = ghost
	return {"posture_id": best_id, "ghost": best_ghost}

## Returns {is_valid, proj} for a ray-point intersection test.
## is_valid = true when point is within threshold distance of the ray and in front of camera.
## proj = distance along the ray (used for depth sorting).
func _ray_point_hit(ray_origin: Vector3, ray_dir: Vector3, point: Vector3, threshold: float) -> Dictionary:
	var to_point: Vector3 = point - ray_origin
	var proj: float = to_point.dot(ray_dir)
	if proj < 0.0:
		return {"is_valid": false, "proj": INF}
	var closest: Vector3 = ray_origin + ray_dir * proj
	var perp_dist: float = closest.distance_to(point)
	if perp_dist > threshold:
		return {"is_valid": false, "proj": INF}
	return {"is_valid": true, "proj": proj}

func _select_gizmo(gizmo) -> void:
	if _selected_gizmo and _selected_gizmo != gizmo:
		if _selected_gizmo is PositionGizmoV2:
			_selected_gizmo.material_override.albedo_color = _selected_gizmo.gizmo_color
		elif _selected_gizmo is RotationGizmoV2:
			_selected_gizmo.clear_highlight()
	_selected_gizmo = gizmo
	if gizmo is PositionGizmoV2:
		var mat: StandardMaterial3D = gizmo.material_override.duplicate()
		mat.albedo_color = Color(1, 1, 0.5)
		gizmo.material_override = mat
	elif gizmo is RotationGizmoV2:
		gizmo.highlight_axis(gizmo._selected_axis)

func _deselect_gizmo() -> void:
	if _selected_gizmo:
		if _selected_gizmo is PositionGizmoV2:
			var mat: StandardMaterial3D = _selected_gizmo.material_override.duplicate()
			mat.albedo_color = _selected_gizmo.gizmo_color
			_selected_gizmo.material_override = mat
		elif _selected_gizmo is RotationGizmoV2:
			_selected_gizmo.clear_highlight()
		_selected_gizmo = null

func _start_drag(gizmo, _screen_pos: Vector2, ray_origin: Vector3, ray_dir: Vector3) -> void:
	_dragging = true
	if gizmo is PositionGizmoV2:
		_is_rotation_drag = false
		var to_gizmo: Vector3 = (gizmo.global_position - _camera.global_position).normalized()
		_drag_plane = Plane(to_gizmo, gizmo.global_position)
	elif gizmo is RotationGizmoV2:
		_is_rotation_drag = true
		gizmo.start_drag(gizmo._selected_axis, ray_origin, ray_dir)

func _update_drag(screen_pos: Vector2) -> void:
	# Paddle drag
	if _dragging_paddle and _player and _player.paddle_node:
		var ray_origin := _camera.project_ray_origin(screen_pos)
		var ray_dir := _camera.project_ray_normal(screen_pos)
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			var paddle_head: Vector3 = intersection + _player.paddle_node.global_transform.basis.y * 0.4
			var ghost = _player.posture.posture_ghosts.get(_player.paddle_posture)
			if ghost:
				var ghost_base: Vector3 = paddle_head - ghost.global_transform.basis.y * 0.4
				ghost.global_position = ghost_base
				ghost_moved.emit(_player.paddle_posture, ghost_base)
		return

	# Ghost drag takes priority
	if _dragging_ghost != null:
		var ray_origin := _camera.project_ray_origin(screen_pos)
		var ray_dir := _camera.project_ray_normal(screen_pos)
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			_dragging_ghost.global_position = intersection
			ghost_moved.emit(_dragging_ghost_id, intersection)
		return

	if not _selected_gizmo:
		return
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)
	if _selected_gizmo is PositionGizmoV2:
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection == null:
			return
		_selected_gizmo.global_position = intersection
		gizmo_moved.emit(_selected_gizmo.field_name, intersection)
	elif _selected_gizmo is RotationGizmoV2:
		var delta: Vector3 = _selected_gizmo.update_drag(ray_origin, ray_dir)
		if delta.length() > 0.001:
			gizmo_rotated.emit(_selected_gizmo.field_name, delta)

func _stop_drag() -> void:
	_dragging = false
	_dragging_ghost = null
	_dragging_ghost_id = -1
	_dragging_paddle = false
	if _selected_gizmo is RotationGizmoV2:
		_selected_gizmo.end_drag()
	_deselect_gizmo()

func clear_all_gizmos() -> void:
	for child in get_children():
		child.queue_free()
	_selected_gizmo = null
	_dragging = false
	_dragging_ghost = null
	_dragging_ghost_id = -1
	_dragging_paddle = false

func add_position_gizmo(field_name: String, pos: Vector3, color: Color, size: float = 0.08) -> PositionGizmoV2:
	var gizmo := PositionGizmoV2.new()
	gizmo.field_name = field_name
	gizmo.gizmo_color = color
	gizmo.gizmo_size = size
	add_child(gizmo)
	gizmo.global_position = pos
	return gizmo

func add_zone_handle(field_name: String, pos: Vector3, color: Color, size: float = 0.05) -> PositionGizmoV2:
	return add_position_gizmo(field_name, pos, color, size)

func add_rotation_gizmo(field_name: String, pos: Vector3) -> RotationGizmoV2:
	var gizmo := RotationGizmoV2.new()
	gizmo.name = "RotationGizmo_%s" % field_name
	add_child(gizmo)
	gizmo.global_position = pos
	return gizmo
