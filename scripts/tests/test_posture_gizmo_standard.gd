extends RefCounted














func run_all(totals: Dictionary) -> void :
	_test_v1_position_gizmo_rgb_axes(totals)
	_test_v1_position_gizmo_arrow_structure(totals)
	_test_v1_rotation_gizmo_rgb_rings(totals)
	_test_v1_rotation_gizmo_ring_orientation(totals)
	_test_v2_rotation_gizmo_rgb_rings(totals)
	_test_v2_rotation_gizmo_ring_orientation(totals)
	_test_v2_position_gizmo_is_sphere(totals)
	_test_gizmo_hover_highlight(totals)
	_test_gizmo_selected_highlight(totals)




func _test_v1_position_gizmo_rgb_axes(totals: Dictionary) -> void :
	var gizmo: = _PositionGizmo.new()
	gizmo.show_axis_handles = true
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var expected: = {"x": Color(1, 0, 0), "y": Color(0, 1, 0), "z": Color(0, 0, 1)}
	var ok: = true
	for axis in expected:
		var handle: MeshInstance3D = gizmo._axis_handles.get(axis, null)
		if handle == null or handle.material_override == null:
			ok = false
			break
		var actual: Color = handle.material_override.albedo_color
		if not _color_approx(actual, expected[axis]):
			ok = false
			print("    V1 pos %s axis color: expected %s, got %s" % [axis, expected[axis], actual])

	_assert(ok, "V1 PositionGizmo axis handles are RGB (X=Red, Y=Green, Z=Blue)", totals)
	parent.queue_free()


func _test_v1_position_gizmo_arrow_structure(totals: Dictionary) -> void :
	var gizmo: = _PositionGizmo.new()
	gizmo.show_axis_handles = true
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var has_cylinders: = 0
	var has_cones: = 0
	for child in gizmo.get_children():
		if child is MeshInstance3D:
			if child.mesh is CylinderMesh:
				var cyl: CylinderMesh = child.mesh
				if cyl.top_radius > 0.0 and cyl.bottom_radius > 0.0:
					has_cylinders += 1
				elif cyl.top_radius == 0.0:
					has_cones += 1

	var ok: = has_cylinders >= 3 and has_cones >= 3
	_assert(ok, 
		"V1 PositionGizmo has cylinder shafts (%d) and cone arrowheads (%d)" % [has_cylinders, has_cones], 
		totals)
	parent.queue_free()




func _test_v1_rotation_gizmo_rgb_rings(totals: Dictionary) -> void :
	var gizmo: = _RotationGizmo.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var expected: = {"x": Color(1, 0, 0), "y": Color(0, 1, 0), "z": Color(0, 0, 1)}
	var ok: = true
	for axis in expected:
		var ring: MeshInstance3D = gizmo._rings.get(axis, null)
		if ring == null or ring.material_override == null:
			ok = false
			break
		var actual: Color = ring.material_override.albedo_color
		if not _color_approx(actual, expected[axis]):
			ok = false

	_assert(ok, "V1 RotationGizmo rings are RGB (X=Red/pitch, Y=Green/yaw, Z=Blue/roll)", totals)
	parent.queue_free()


func _test_v1_rotation_gizmo_ring_orientation(totals: Dictionary) -> void :
	var gizmo: = _RotationGizmo.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var ring_x: MeshInstance3D = gizmo._rings.get("x", null)
	var ring_y: MeshInstance3D = gizmo._rings.get("y", null)
	var ring_z: MeshInstance3D = gizmo._rings.get("z", null)

	var ok: = ring_x != null and ring_y != null and ring_z != null
	if ok:



		ok = _vec_approx(ring_x.rotation, Vector3(0, 0, - PI / 2)) and \
		_vec_approx(ring_y.rotation, Vector3(0, 0, 0)) and \
		_vec_approx(ring_z.rotation, Vector3(PI / 2, 0, 0))

	_assert(ok, "V1 RotationGizmo rings oriented in correct planes (YZ/XZ/XY)", totals)
	parent.queue_free()




func _test_v2_rotation_gizmo_rgb_rings(totals: Dictionary) -> void :
	var gizmo: = _RotationGizmoV2.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var expected: = {"x": Color(1, 0.3, 0.3), "y": Color(0.3, 1, 0.3), "z": Color(0.3, 0.3, 1)}
	var ok: = true
	for axis in expected:
		var ring: MeshInstance3D = gizmo._rings.get(axis, null)
		if ring == null or ring.material_override == null:
			ok = false
			break
		var actual: Color = ring.material_override.albedo_color
		if not _color_approx(actual, expected[axis]):
			ok = false

	_assert(ok, "V2 RotationGizmoV2 rings are RGB-tinted (X=red, Y=green, Z=blue)", totals)
	parent.queue_free()


func _test_v2_rotation_gizmo_ring_orientation(totals: Dictionary) -> void :
	var gizmo: = _RotationGizmoV2.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var ring_x: MeshInstance3D = gizmo._rings.get("x", null)
	var ring_y: MeshInstance3D = gizmo._rings.get("y", null)
	var ring_z: MeshInstance3D = gizmo._rings.get("z", null)

	var ok: = ring_x != null and ring_y != null and ring_z != null
	if ok:



		ok = _vec_approx(ring_x.rotation_degrees, Vector3(0, 90, 0)) and \
		_vec_approx(ring_y.rotation_degrees, Vector3(90, 0, 0)) and \
		_vec_approx(ring_z.rotation_degrees, Vector3(0, 0, 0))

	_assert(ok, "V2 RotationGizmoV2 rings oriented in correct planes (YZ/XZ/XY)", totals)
	parent.queue_free()




func _test_v2_position_gizmo_is_sphere(totals: Dictionary) -> void :
	var gizmo: = _PositionGizmoV2.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var is_sphere: = gizmo.mesh is SphereMesh
	_assert(is_sphere, 
		"V2 PositionGizmoV2 is a simple sphere (not standard arrow handles)", totals)
	parent.queue_free()




func _test_gizmo_hover_highlight(totals: Dictionary) -> void :
	var gizmo: = _RotationGizmoV2.new()
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	var ring_x: MeshInstance3D = gizmo._rings.get("x", null)
	var ring_y: MeshInstance3D = gizmo._rings.get("y", null)
	var ok: = ring_x != null and ring_y != null
	if ok:
		var x_col: Color = ring_x.material_override.albedo_color
		var y_col: Color = ring_y.material_override.albedo_color

		var is_yellow: = func(c: Color) -> bool: return c.r > 0.9 and c.g > 0.9 and c.b < 0.6
		ok = is_yellow.call(x_col) and not is_yellow.call(y_col)

	_assert(ok, "V2 RotationGizmoV2 highlight_axis dims non-selected rings", totals)
	parent.queue_free()


func _test_gizmo_selected_highlight(totals: Dictionary) -> void :
	var gizmo: = _GizmoHandle.new()
	gizmo.gizmo_color = Color.BLUE
	gizmo.hover_color = Color.YELLOW
	gizmo.selected_color = Color.GREEN
	var parent: = Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()


	var rest_col: Color = gizmo._base_material.albedo_color


	gizmo.set_hovered(true)
	var hover_col: Color = gizmo._base_material.albedo_color


	gizmo.set_selected(true)
	var sel_col: Color = gizmo._base_material.albedo_color

	var ok: = _color_approx(rest_col, Color.BLUE) and \
	_color_approx(hover_col, Color.YELLOW) and \
	_color_approx(sel_col, Color.GREEN)

	_assert(ok, "GizmoHandle visual states: rest→hover→selected colors correct", totals)
	parent.queue_free()




func _color_approx(a: Color, b: Color, tol: float = 0.05) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

func _vec_approx(a: Vector3, b: Vector3, tol: float = 0.05) -> bool:
	return a.distance_to(b) <= tol

func _assert(condition: bool, label: String, totals: Dictionary) -> void :
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)

const _PositionGizmo: = preload("res://scripts/posture_editor/position_gizmo.gd")
const _RotationGizmo: = preload("res://scripts/posture_editor/rotation_gizmo.gd")
const _PositionGizmoV2: = preload("res://scripts/posture_editor_v2/position_gizmo_v2.gd")
const _RotationGizmoV2: = preload("res://scripts/posture_editor_v2/rotation_gizmo_v2.gd")
const _GizmoHandle: = preload("res://scripts/posture_editor/gizmo_handle.gd")
