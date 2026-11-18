class_name GizmoControllerV2 extends Node3D





signal gizmo_moved(field_name: String, new_position: Vector3)
signal gizmo_rotated(field_name: String, euler_delta: Vector3)
signal ghost_selected(posture_id: int)
signal ghost_moved(posture_id: int, new_position: Vector3)
signal zone_selected(posture_id: int)
signal drag_ended()

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var _camera: Camera3D
var _ui: Control
var _player = null
var _selected_gizmo = null
var _dragging: bool = false
var _drag_plane: Plane
var _is_rotation_drag: bool = false


var _dragging_ghost: Node3D = null
var _dragging_ghost_id: int = -1


var _dragging_paddle: bool = false


var _drag_axis: String = ""


var _hovered_gizmo = null
var _hovered_axis: String = ""

func set_camera(camera: Camera3D) -> void :
	_camera = camera

func set_ui(ui: Control) -> void :
	_ui = ui

func set_player(player) -> void :
	_player = player

func _is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	if _ui == null or not _ui.visible:
		return false
	return _ui.get_global_rect().has_point(mouse_pos)

func _input(event: InputEvent) -> void :
	if not _camera or _ui == null or not _ui.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var was_dragging: = _dragging
		_stop_drag()
		if was_dragging:
			get_viewport().set_input_as_handled()
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
	elif event is InputEventMouseMotion:
		if _dragging and (_selected_gizmo != null or _dragging_ghost != null or _dragging_paddle):
			_update_drag(event.position)
			get_viewport().set_input_as_handled()
		elif not _dragging:
			_update_hover(event.position)



func _find_gizmo_under_ray(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var closest_gizmo = null
	var closest_dist: = INF
	var closest_axis: = ""

	for child in get_children():
		if child is PositionGizmoV2:
			var hit_dist: float = child.raycast_test(ray_origin, ray_dir)
			if hit_dist >= 0 and hit_dist < closest_dist:
				closest_dist = hit_dist
				closest_gizmo = child
				closest_axis = child.get_selected_axis()

	for child in get_children():
		if child is RotationGizmoV2:
			var axis: String = child.raycast_test(ray_origin, ray_dir)
			if axis != "":
				var to_center: Vector3 = child.global_position - ray_origin
				var proj: float = to_center.dot(ray_dir)
				if proj >= 0 and proj < closest_dist:
					closest_dist = proj
					closest_gizmo = child
					closest_axis = axis

	return {"gizmo": closest_gizmo, "axis": closest_axis}

func _update_hover(screen_pos: Vector2) -> void :
	var ray_origin: = _camera.project_ray_origin(screen_pos)
	var ray_dir: = _camera.project_ray_normal(screen_pos)
	var result: = _find_gizmo_under_ray(ray_origin, ray_dir)
	var gizmo = result.gizmo
	var axis: String = result.axis

	if gizmo == null or gizmo == _selected_gizmo:
		if _hovered_gizmo != null and _hovered_gizmo != _selected_gizmo:
			_hovered_gizmo.clear_highlight()
		_hovered_gizmo = null
		_hovered_axis = ""
		return

	if gizmo != _hovered_gizmo or axis != _hovered_axis:
		if _hovered_gizmo != null and _hovered_gizmo != _selected_gizmo:
			_hovered_gizmo.clear_highlight()
		_hovered_gizmo = gizmo
		_hovered_axis = axis
		if gizmo is PositionGizmoV2:
			gizmo.highlight_axis(axis)
		elif gizmo is RotationGizmoV2:
			gizmo.highlight_axis(axis)

func _try_select_gizmo(screen_pos: Vector2) -> void :
	var ray_origin: = _camera.project_ray_origin(screen_pos)
	var ray_dir: = _camera.project_ray_normal(screen_pos)


	var result: = _find_gizmo_under_ray(ray_origin, ray_dir)
	var closest_gizmo = result.gizmo
	if closest_gizmo:

		if closest_gizmo is RotationGizmoV2:
			closest_gizmo._selected_axis = result.axis
		_select_gizmo(closest_gizmo)
		_start_drag(closest_gizmo, screen_pos, ray_origin, ray_dir)
		return


	if _player and _player.posture:
		var zone_result: = _raycast_zone_meshes(ray_origin, ray_dir)
		if zone_result.posture_id >= 0:
			zone_selected.emit(zone_result.posture_id)
			return


	if _player and _player.posture:
		var ghost_result: = _raycast_ghosts(ray_origin, ray_dir)
		if ghost_result.posture_id >= 0 and ghost_result.ghost != null:
			ghost_selected.emit(ghost_result.posture_id)
			_dragging_ghost = ghost_result.ghost
			_dragging_ghost_id = ghost_result.posture_id
			_dragging = true
			var to_ghost: Vector3 = (_dragging_ghost.global_position - _camera.global_position).normalized()
			_drag_plane = Plane(to_ghost, _dragging_ghost.global_position)
			return


	if _player and _player.paddle_node and _player.posture and _player.posture.editor_preview_mode:
		var space_state: = get_world_3d().direct_space_state
		var query: = PhysicsRayQueryParameters3D.new()
		query.from = ray_origin
		query.to = ray_origin + ray_dir * 100.0
		query.collision_mask = 4
		query.collide_with_bodies = true
		var ray_result: = space_state.intersect_ray(query)
		if ray_result.has("position"):
			_dragging_paddle = true
			_dragging = true
			var to_paddle: Vector3 = (_player.paddle_node.global_position - _camera.global_position).normalized()
			_drag_plane = Plane(to_paddle, _player.paddle_node.global_position)
			return

	_deselect_gizmo()



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

		var handle_hit: = _ray_point_hit(ray_origin, ray_dir, ghost.global_position, THRESHOLD)


		var head_pos: Vector3 = ghost.global_position + ghost.global_transform.basis.y.normalized() * PaddleSize.HEAD_CENTER_Y * _player.posture.POSTURE_GHOST_SCALE.y
		var head_hit: = _ray_point_hit(ray_origin, ray_dir, head_pos, THRESHOLD)
		if handle_hit.is_valid and handle_hit.proj < best_proj:
			best_proj = handle_hit.proj
			best_id = posture_id
			best_ghost = ghost
		if head_hit.is_valid and head_hit.proj < best_proj:
			best_proj = head_hit.proj
			best_id = posture_id
			best_ghost = ghost
	return {"posture_id": best_id, "ghost": best_ghost}


func _raycast_zone_meshes(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var best_id: int = -1
	var best_dist: float = INF

	if _player == null or _player.posture == null:
		return {"posture_id": -1, "dist": INF}

	for posture_id in _player.posture._posture_zone_bounds.keys():
		var zone_mi: MeshInstance3D = _player.posture._posture_zone_bounds[posture_id]
		if zone_mi == null or not zone_mi.visible:
			continue
		var mesh: BoxMesh = zone_mi.mesh as BoxMesh
		if mesh == null:
			continue


		var inv_transform: = zone_mi.global_transform.affine_inverse()
		var local_origin: Vector3 = inv_transform * ray_origin
		var local_dir: Vector3 = inv_transform.basis * ray_dir
		var half_size: Vector3 = mesh.size / 2.0


		var tmin: float = - INF
		var tmax: float = INF
		var hit: bool = true
		for i in range(3):
			if abs(local_dir[i]) < 0.0001:
				if local_origin[i] < - half_size[i] or local_origin[i] > half_size[i]:
					hit = false
					break
			else:
				var t1: float = ( - half_size[i] - local_origin[i]) / local_dir[i]
				var t2: float = (half_size[i] - local_origin[i]) / local_dir[i]
				if t1 > t2:
					var tmp: float = t1
					t1 = t2
					t2 = tmp
				if t1 > tmin:
					tmin = t1
				if t2 < tmax:
					tmax = t2
				if tmin > tmax:
					hit = false
					break
		if hit and tmin >= 0 and tmin < best_dist:
			best_dist = tmin
			best_id = posture_id

	return {"posture_id": best_id, "dist": best_dist}




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

func _select_gizmo(gizmo) -> void :
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

func _deselect_gizmo() -> void :
	if _selected_gizmo:
		if _selected_gizmo is PositionGizmoV2:
			var mat: StandardMaterial3D = _selected_gizmo.material_override.duplicate()
			mat.albedo_color = _selected_gizmo.gizmo_color
			_selected_gizmo.material_override = mat
		elif _selected_gizmo is RotationGizmoV2:
			_selected_gizmo.clear_highlight()
		_selected_gizmo = null
	if _hovered_gizmo != null:
		_hovered_gizmo.clear_highlight()
		_hovered_gizmo = null
		_hovered_axis = ""

func _start_drag(gizmo, _screen_pos: Vector2, ray_origin: Vector3, ray_dir: Vector3) -> void :
	_dragging = true
	_drag_axis = ""
	if gizmo is PositionGizmoV2:
		_is_rotation_drag = false
		var to_gizmo: Vector3 = (gizmo.global_position - _camera.global_position).normalized()
		_drag_plane = Plane(to_gizmo, gizmo.global_position)
		if gizmo.show_axis_handles:
			_drag_axis = gizmo.get_selected_axis()
	elif gizmo is RotationGizmoV2:
		_is_rotation_drag = true
		gizmo.start_drag(gizmo._selected_axis, ray_origin, ray_dir)

func _update_drag(screen_pos: Vector2) -> void :
	var ray_origin: = _camera.project_ray_origin(screen_pos)
	var ray_dir: = _camera.project_ray_normal(screen_pos)


	if _dragging_paddle and _player and _player.paddle_node:
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			var paddle_head: Vector3 = intersection + _player.paddle_node.global_transform.basis.y * PaddleSize.HEAD_CENTER_Y
			var ghost = _player.posture.posture_ghosts.get(_player.paddle_posture)
			if ghost:
				var ghost_base: Vector3 = paddle_head - ghost.global_transform.basis.y * PaddleSize.HEAD_CENTER_Y
				ghost.global_position = ghost_base
				ghost_moved.emit(_player.paddle_posture, ghost_base)
		return


	if _dragging_ghost != null:
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			_dragging_ghost.global_position = intersection
			ghost_moved.emit(_dragging_ghost_id, intersection)
		return

	if not _selected_gizmo:
		return
	if _selected_gizmo is PositionGizmoV2:
		var intersection: Variant = _drag_plane.intersects_ray(ray_origin, ray_dir)
		if intersection == null:
			return
		var new_pos: Vector3 = intersection

		if _drag_axis != "" and _selected_gizmo.show_axis_handles:
			var axis_vec: = Vector3.ZERO
			match _drag_axis:
				"x": axis_vec = Vector3.RIGHT
				"y": axis_vec = Vector3.UP
				"z": axis_vec = Vector3.FORWARD
			var drag_delta: Vector3 = intersection - _selected_gizmo.global_position
			var constrained: Vector3 = axis_vec * drag_delta.dot(axis_vec)
			new_pos = _selected_gizmo.global_position + constrained
		_selected_gizmo.global_position = new_pos
		gizmo_moved.emit(_selected_gizmo.field_name, new_pos)
	elif _selected_gizmo is RotationGizmoV2:
		var delta: Vector3 = _selected_gizmo.update_drag(ray_origin, ray_dir)
		if delta.length() > 0.001:
			gizmo_rotated.emit(_selected_gizmo.field_name, delta)

func _stop_drag() -> void :
	var was_dragging: = _dragging
	_dragging = false
	_dragging_ghost = null
	_dragging_ghost_id = -1
	_dragging_paddle = false
	_drag_axis = ""
	if _selected_gizmo is RotationGizmoV2:
		_selected_gizmo.end_drag()
	_deselect_gizmo()
	if was_dragging:
		drag_ended.emit()

func clear_all_gizmos() -> void :
	if _hovered_gizmo != null:
		_hovered_gizmo.clear_highlight()
	_hovered_gizmo = null
	_hovered_axis = ""
	for child in get_children():
		child.queue_free()
	_selected_gizmo = null
	_dragging = false
	_dragging_ghost = null
	_dragging_ghost_id = -1
	_dragging_paddle = false

func is_dragging() -> bool:
	return _dragging

func is_dragging_zone_handle() -> bool:
	return _dragging and _selected_gizmo is PositionGizmoV2 and _selected_gizmo.name.begins_with("zone_")

func add_position_gizmo(field_name: String, pos: Vector3, color: Color, size: float = 0.08, with_axis_handles: bool = false) -> PositionGizmoV2:
	var gizmo: = PositionGizmoV2.new()
	gizmo.name = field_name
	gizmo.field_name = field_name
	gizmo.gizmo_color = color
	gizmo.gizmo_size = size
	gizmo.show_axis_handles = with_axis_handles
	add_child(gizmo)
	gizmo.global_position = pos
	return gizmo

func add_zone_handle(field_name: String, pos: Vector3, color: Color, size: float = 0.05, with_axis_handles: bool = false) -> PositionGizmoV2:
	return add_position_gizmo(field_name, pos, color, size, with_axis_handles)

func add_rotation_gizmo(field_name: String, pos: Vector3) -> RotationGizmoV2:
	var gizmo: = RotationGizmoV2.new()
	gizmo.name = "RotationGizmo_%s" % field_name
	add_child(gizmo)
	gizmo.global_position = pos
	return gizmo
