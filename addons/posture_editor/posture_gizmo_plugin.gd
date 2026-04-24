@tool
extends EditorNode3DGizmoPlugin

const COURT_FLOOR_Y: float = 0.075
const GHOST_FORWARD_PLANE: float = 0.5
const ZONE_DEPTH: float = 0.15

var dock: PostureEditorDock:
	set(value):
		if dock != null:
			if dock.posture_selected.is_connected(_on_posture_changed):
				dock.posture_selected.disconnect(_on_posture_changed)
			if dock.posture_changed.is_connected(_on_posture_changed):
				dock.posture_changed.disconnect(_on_posture_changed)
		dock = value
		if dock != null:
			dock.posture_selected.connect(_on_posture_changed)
			dock.posture_changed.connect(_on_posture_changed)

var _active_gizmo: EditorNode3DGizmo = null
var _drag_data: Dictionary = {}

func _init() -> void:
	create_material("zone", Color(0.6, 0.1, 1.0, 0.6))
	create_material("paddle", Color(1.0, 0.85, 0.2, 0.5))
	create_handle_material("handles")

func _get_gizmo_name() -> String:
	return "PostureEditor"

func _has_gizmo(node: Node3D) -> bool:
	if not node is CharacterBody3D:
		return false
	if node.get_node_or_null("Paddle") != null:
		return true
	if node.get_node_or_null("BodyPivot/Paddle") != null:
		return true
	return false

func _create_gizmo(node: Node3D) -> EditorNode3DGizmo:
	var gizmo := EditorNode3DGizmo.new()
	_active_gizmo = gizmo
	return gizmo

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if node == null or dock == null:
		return

	var def = dock.get_selected_definition()
	if def == null:
		return

	var forehand_axis: Vector3 = node.basis.x
	var forward_axis: Vector3 = -node.basis.z
	var player_pos: Vector3 = node.global_position

	if def.has_zone:
		_draw_zone(gizmo, def, player_pos, forehand_axis, forward_axis)
	_draw_paddle(gizmo, def, player_pos, forehand_axis, forward_axis)

func _draw_zone(gizmo: EditorNode3DGizmo, def, player_pos: Vector3, forehand_axis: Vector3, forward_axis: Vector3) -> void:
	var x_min: float = def.zone_x_min
	var x_max: float = def.zone_x_max
	var y_min_world: float = COURT_FLOOR_Y + def.zone_y_min
	var y_max_world: float = COURT_FLOOR_Y + def.zone_y_max
	var z: float = GHOST_FORWARD_PLANE

	var c0 := player_pos + forehand_axis * x_min + Vector3.UP * y_min_world + forward_axis * z
	var c1 := player_pos + forehand_axis * x_max + Vector3.UP * y_min_world + forward_axis * z
	var c2 := player_pos + forehand_axis * x_max + Vector3.UP * y_max_world + forward_axis * z
	var c3 := player_pos + forehand_axis * x_min + Vector3.UP * y_max_world + forward_axis * z

	var c4 := c0 + forward_axis * ZONE_DEPTH
	var c5 := c1 + forward_axis * ZONE_DEPTH
	var c6 := c2 + forward_axis * ZONE_DEPTH
	var c7 := c3 + forward_axis * ZONE_DEPTH

	var lines := PackedVector3Array()
	# Front face
	lines.append(c0); lines.append(c1)
	lines.append(c1); lines.append(c2)
	lines.append(c2); lines.append(c3)
	lines.append(c3); lines.append(c0)
	# Back face
	lines.append(c4); lines.append(c5)
	lines.append(c5); lines.append(c6)
	lines.append(c6); lines.append(c7)
	lines.append(c7); lines.append(c4)
	# Connecting edges
	lines.append(c0); lines.append(c4)
	lines.append(c1); lines.append(c5)
	lines.append(c2); lines.append(c6)
	lines.append(c3); lines.append(c7)

	gizmo.add_lines(lines, get_material("zone", gizmo), false, Color(0.6, 0.1, 1.0, 0.6))

	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	handles.append(c0); ids.append(0)
	handles.append(c1); ids.append(1)
	handles.append(c2); ids.append(2)
	handles.append(c3); ids.append(3)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids, false, false)

func _draw_paddle(gizmo: EditorNode3DGizmo, def, player_pos: Vector3, forehand_axis: Vector3, forward_axis: Vector3) -> void:
	var offset: Vector3 = forehand_axis * def.paddle_forehand_mul \
						+ forward_axis * def.paddle_forward_mul \
						+ Vector3.UP * def.paddle_y_offset
	var paddle_pos: Vector3 = player_pos + offset

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.25, 0.55, 0.03)
	var head_transform := Transform3D(Basis.IDENTITY, paddle_pos + Vector3.UP * 0.2)
	gizmo.add_mesh(head_mesh, get_material("paddle", gizmo), head_transform)

	var handle_mesh := CylinderMesh.new()
	handle_mesh.height = 0.4
	handle_mesh.radius = 0.02
	var handle_transform := Transform3D(Basis.IDENTITY, paddle_pos - Vector3.UP * 0.2)
	gizmo.add_mesh(handle_mesh, get_material("paddle", gizmo), handle_transform)

	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	handles.append(paddle_pos)
	ids.append(4)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids, false, false)

func _get_handle_value(gizmo: EditorNode3DGizmo, index: int, secondary: bool) -> Variant:
	var def = dock.get_selected_definition()
	if def == null:
		return null
	if index < 4:
		return [def.zone_x_min, def.zone_x_max, def.zone_y_min, def.zone_y_max]
	elif index == 4:
		return [def.paddle_forehand_mul, def.paddle_forward_mul, def.paddle_y_offset]
	return null

func _set_handle(gizmo: EditorNode3DGizmo, index: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	if node == null or dock == null:
		return

	var def = dock.get_selected_definition()
	if def == null:
		return

	if not _drag_data.has(gizmo):
		var handle_pos := _get_handle_world_pos(gizmo, index, node, def)
		var to_camera := (camera.global_position - handle_pos).normalized()
		_drag_data[gizmo] = {
			"index": index,
			"plane": Plane(to_camera, handle_pos),
			"original": _get_handle_value(gizmo, index, secondary)
		}

	var data: Dictionary = _drag_data[gizmo]
	if data.index != index:
		return

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var intersection: Variant = data.plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return

	var forehand_axis: Vector3 = node.basis.x
	var forward_axis: Vector3 = -node.basis.z
	var player_pos: Vector3 = node.global_position

	if index < 4:
		var local: Vector3 = intersection - player_pos
		var x: float = local.dot(forehand_axis)
		var y: float = intersection.y - COURT_FLOOR_Y
		match index:
			0: # front-bottom-left
				def.zone_x_min = minf(x, def.zone_x_max - 0.01)
				def.zone_y_min = minf(y, def.zone_y_max - 0.01)
			1: # front-bottom-right
				def.zone_x_max = maxf(x, def.zone_x_min + 0.01)
				def.zone_y_min = minf(y, def.zone_y_max - 0.01)
			2: # front-top-left
				def.zone_x_min = minf(x, def.zone_x_max - 0.01)
				def.zone_y_max = maxf(y, def.zone_y_min + 0.01)
			3: # front-top-right
				def.zone_x_max = maxf(x, def.zone_x_min + 0.01)
				def.zone_y_max = maxf(y, def.zone_y_min + 0.01)
	elif index == 4:
		var local: Vector3 = intersection - player_pos
		def.paddle_forehand_mul = local.dot(forehand_axis)
		def.paddle_forward_mul = local.dot(forward_axis)
		def.paddle_y_offset = local.y

	dock.mark_dirty()
	dock.sync_from_definition()
	gizmo.clear()
	_redraw(gizmo)

func _commit_handle(gizmo: EditorNode3DGizmo, index: int, secondary: bool, restore: bool, cancel: bool) -> void:
	if cancel and _drag_data.has(gizmo):
		var data: Dictionary = _drag_data[gizmo]
		var def = dock.get_selected_definition()
		if def != null and data.original != null:
			if index < 4:
				def.zone_x_min = data.original[0]
				def.zone_x_max = data.original[1]
				def.zone_y_min = data.original[2]
				def.zone_y_max = data.original[3]
			elif index == 4:
				def.paddle_forehand_mul = data.original[0]
				def.paddle_forward_mul = data.original[1]
				def.paddle_y_offset = data.original[2]
		gizmo.clear()
		_redraw(gizmo)
		dock.sync_from_definition()
	_drag_data.erase(gizmo)

func _get_handle_world_pos(gizmo: EditorNode3DGizmo, index: int, node: Node3D, def) -> Vector3:
	var forehand_axis: Vector3 = node.basis.x
	var forward_axis: Vector3 = -node.basis.z
	var player_pos: Vector3 = node.global_position

	if index < 4:
		var x: float = def.zone_x_min if index in [0, 3] else def.zone_x_max
		var y: float = def.zone_y_min if index in [0, 1] else def.zone_y_max
		return player_pos + forehand_axis * x + Vector3.UP * (COURT_FLOOR_Y + y) + forward_axis * GHOST_FORWARD_PLANE
	elif index == 4:
		return player_pos + forehand_axis * def.paddle_forehand_mul \
						 + forward_axis * def.paddle_forward_mul \
						 + Vector3.UP * def.paddle_y_offset
	return Vector3.ZERO

func _on_posture_changed(_def) -> void:
	if _active_gizmo != null:
		_active_gizmo.clear()
		_redraw(_active_gizmo)
