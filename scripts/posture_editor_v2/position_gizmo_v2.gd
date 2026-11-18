class_name PositionGizmoV2 extends MeshInstance3D

## Position gizmo for v2.  Default is a simple sphere.
## When show_axis_handles is true, adds RGB arrow handles (cylinder + cone)
## for axis-constrained movement following the 3D transform standard.

var field_name: String = ""
var gizmo_color: Color = Color(0.3, 0.9, 0.3)
var gizmo_size: float = 0.08

## When true, displays X/Y/Z arrow handles (Red/Green/Blue).
@export var show_axis_handles: bool = false:
	set(value):
		if show_axis_handles == value:
			return
		show_axis_handles = value
		if show_axis_handles and is_inside_tree():
			_create_axis_handles()

var axis_handle_length: float = 0.25
var axis_handle_radius: float = 0.02

var _axis_handles: Dictionary = {}      # axis_name -> MeshInstance3D (cylinder)
var _axis_cones: Dictionary = {}        # axis_name -> MeshInstance3D (cone)
var _axis_materials: Dictionary = {}    # axis_name -> StandardMaterial3D
var _selected_axis: String = ""

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = gizmo_size
	sphere.height = gizmo_size * 2.0
	mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = gizmo_color
	mat.emission_enabled = true
	mat.emission = gizmo_color
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat

	if show_axis_handles:
		_create_axis_handles()

func _create_axis_handles() -> void:
	if not _axis_handles.is_empty():
		return

	var axis_colors := {
		"x": Color(1, 0, 0),   # Red
		"y": Color(0, 1, 0),   # Green
		"z": Color(0, 0, 1)    # Blue
	}

	for axis_name in ["x", "y", "z"]:
		var color: Color = axis_colors[axis_name]

		# Cylinder shaft
		var cyl := MeshInstance3D.new()
		cyl.name = "AxisHandle_" + axis_name.to_upper()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = axis_handle_radius
		cylinder.bottom_radius = axis_handle_radius
		cylinder.height = axis_handle_length
		cyl.mesh = cylinder

		# Position and rotate based on axis
		match axis_name:
			"x":
				cyl.rotation.z = -PI / 2
				cyl.position.x = axis_handle_length * 0.5
			"y":
				cyl.position.y = axis_handle_length * 0.5
			"z":
				cyl.rotation.x = PI / 2
				cyl.position.z = axis_handle_length * 0.5

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.6
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		cyl.material_override = mat

		_axis_handles[axis_name] = cyl
		_axis_materials[axis_name] = mat
		add_child(cyl)

		# Cone arrowhead
		var cone := MeshInstance3D.new()
		cone.name = "AxisCone_" + axis_name.to_upper()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.0
		cone_mesh.bottom_radius = axis_handle_radius * 2.5
		cone_mesh.height = axis_handle_radius * 6.0
		cone.mesh = cone_mesh
		cone.material_override = mat

		match axis_name:
			"x":
				cone.rotation.z = -PI / 2
				cone.position.x = axis_handle_length + axis_handle_radius * 3.0
			"y":
				cone.position.y = axis_handle_length + axis_handle_radius * 3.0
			"z":
				cone.rotation.x = PI / 2
				cone.position.z = axis_handle_length + axis_handle_radius * 3.0

		add_child(cone)
		_axis_cones[axis_name] = cone

## Returns hit distance along ray, or -1 if no hit.
## When show_axis_handles is true, axis handles take priority over the sphere.
func raycast_test(ray_origin: Vector3, ray_dir: Vector3) -> float:
	_selected_axis = ""

	if show_axis_handles:
		var best_hit := -1.0
		for axis_name in ["x", "y", "z"]:
			var handle: MeshInstance3D = _axis_handles.get(axis_name, null)
			if handle == null:
				continue
			var hit := _intersect_cylinder(
				ray_origin, ray_dir,
				handle.global_position,
				handle.global_transform.basis.y.normalized(),
				axis_handle_radius,
				axis_handle_length
			)
			if hit >= 0 and (best_hit < 0 or hit < best_hit):
				best_hit = hit
				_selected_axis = axis_name

			# Also check the cone arrowhead — generous cylindrical bounds
			var cone: MeshInstance3D = _axis_cones.get(axis_name, null)
			if cone:
				var cone_hit := _intersect_cylinder(
					ray_origin, ray_dir,
					cone.global_position,
					cone.global_transform.basis.y.normalized(),
					axis_handle_radius * 2.5,
					axis_handle_radius * 6.0
				)
				if cone_hit >= 0 and (best_hit < 0 or cone_hit < best_hit):
					best_hit = cone_hit
					_selected_axis = axis_name

		if best_hit >= 0:
			return best_hit

	# Fall back to sphere
	var world_pos := _get_effective_position()
	var to_center: Vector3 = world_pos - ray_origin
	var proj: float = to_center.dot(ray_dir)
	if proj < 0:
		return -1.0
	var closest: Vector3 = ray_origin + ray_dir * proj
	var dist: float = closest.distance_to(world_pos)
	if dist > gizmo_size * 1.5:
		return -1.0
	return proj

func get_selected_axis() -> String:
	return _selected_axis

func highlight_axis(axis: String) -> void:
	for mat in _axis_materials.values():
		mat.albedo_color.a = 0.3
		mat.emission_energy_multiplier = 0.5
	if _axis_materials.has(axis):
		_axis_materials[axis].albedo_color.a = 1.0
		_axis_materials[axis].emission_energy_multiplier = 3.0

func clear_highlight() -> void:
	for mat in _axis_materials.values():
		mat.albedo_color.a = 0.6
		mat.emission_energy_multiplier = 1.5

func _get_effective_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position

func _intersect_cylinder(ray_origin: Vector3, ray_dir: Vector3,
						  cylinder_pos: Vector3, cylinder_axis: Vector3,
						  radius: float, height: float) -> float:
	var to_cyl := cylinder_pos - ray_origin
	var half_h := height * 0.5

	var perp_dir := ray_dir - ray_dir.dot(cylinder_axis) * cylinder_axis
	var perp_to := to_cyl - to_cyl.dot(cylinder_axis) * cylinder_axis

	var a := perp_dir.length_squared()
	if a < 0.0001:
		# Ray is parallel to cylinder axis
		var perp_dist_sq := perp_to.length_squared()
		if perp_dist_sq > radius * radius:
			return -1.0
		# Ray passes inside the infinite cylinder; intersect with caps
		var denom := ray_dir.dot(cylinder_axis)
		if absf(denom) < 0.0001:
			return -1.0
		var t1 := (to_cyl.dot(cylinder_axis) - half_h) / denom
		var t2 := (to_cyl.dot(cylinder_axis) + half_h) / denom
		if t1 >= 0 and t2 >= 0:
			return minf(t1, t2)
		if t1 >= 0:
			return t1
		if t2 >= 0:
			return t2
		return -1.0

	var b := -2.0 * perp_dir.dot(perp_to)
	var c := perp_to.length_squared() - radius * radius

	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0:
		return -1.0

	var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		t = (-b + sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		return -1.0

	var hit_point := ray_origin + ray_dir * t
	var along_axis := (hit_point - cylinder_pos).dot(cylinder_axis)
	if absf(along_axis) > half_h:
		return -1.0

	return t
