class_name PositionGizmo extends GizmoHandle

## Position gizmo with axis handles for constrained movement

@export var show_axis_handles: bool = true
@export var axis_handle_length: float = 0.25
@export var axis_handle_radius: float = 0.02

var _axis_handles: Dictionary = {}  # axis_name -> MeshInstance3D
var _axis_materials: Dictionary = {}

enum Axis { X, Y, Z }
var _drag_axis: Axis = Axis.X

func _ready() -> void:
	gizmo_type = GizmoType.POSITION
	_create_main_handle()
	if show_axis_handles:
		_create_axis_handles()
	super._ready()

func _create_main_handle() -> void:
	# Main sphere handle
	var sphere := SphereMesh.new()
	sphere.radius = gizmo_size * 0.5
	sphere.height = gizmo_size
	mesh = sphere

func _create_axis_handles() -> void:
	var axis_colors := {
		"x": Color(1, 0, 0),  # Red
		"y": Color(0, 1, 0),  # Green
		"z": Color(0, 0, 1)   # Blue
	}
	
	for axis_name in ["x", "y", "z"]:
		var handle := MeshInstance3D.new()
		handle.name = "AxisHandle_" + axis_name.to_upper()
		
		# Cylinder for axis line
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = axis_handle_radius
		cylinder.bottom_radius = axis_handle_radius
		cylinder.height = axis_handle_length
		handle.mesh = cylinder
		
		# Position and rotate based on axis
		match axis_name:
			"x":
				handle.rotation.z = -PI / 2
				handle.position.x = axis_handle_length * 0.5
			"y":
				handle.position.y = axis_handle_length * 0.5
			"z":
				handle.rotation.x = PI / 2
				handle.position.z = axis_handle_length * 0.5
		
		# Material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = axis_colors[axis_name]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.6
		handle.material_override = mat
		
		_axis_handles[axis_name] = handle
		_axis_materials[axis_name] = mat
		add_child(handle)
		
		# Cone at end for better visibility
		var cone := MeshInstance3D.new()
		cone.name = "AxisCone_" + axis_name.to_upper()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.0
		cone_mesh.bottom_radius = axis_handle_radius * 2.5
		cone_mesh.height = axis_handle_radius * 6
		cone.mesh = cone_mesh
		cone.material_override = mat
		
		match axis_name:
			"x":
				cone.rotation.z = -PI / 2
				cone.position.x = axis_handle_length + axis_handle_radius * 3
			"y":
				cone.position.y = axis_handle_length + axis_handle_radius * 3
			"z":
				cone.rotation.x = PI / 2
				cone.position.z = axis_handle_length + axis_handle_radius * 3
		
		add_child(cone)
		_axis_handles[axis_name + "_cone"] = cone

func highlight_axis(axis: Axis) -> void:
	# Dim all axes
	for mat in _axis_materials.values():
		mat.albedo_color.a = 0.3
	
	# Highlight selected
	var axis_name := ""
	match axis:
		Axis.X: axis_name = "x"
		Axis.Y: axis_name = "y"
		Axis.Z: axis_name = "z"
	
	if _axis_materials.has(axis_name):
		_axis_materials[axis_name].albedo_color.a = 1.0

func clear_axis_highlight() -> void:
	for mat in _axis_materials.values():
		mat.albedo_color.a = 0.6

## Override intersect_ray to handle axis handles
func intersect_ray(ray_origin: Vector3, ray_dir: Vector3) -> float:
	# First check main sphere
	var main_hit := super.intersect_ray(ray_origin, ray_dir)
	
	# Then check axis handles (closer hit wins)
	for axis_name in ["x", "y", "z"]:
		if not _axis_handles.has(axis_name):
			continue
			
		var handle: MeshInstance3D = _axis_handles[axis_name]
		var handle_hit := _intersect_cylinder(
			ray_origin, ray_dir,
			handle.global_position,
			handle.global_transform.basis.y,  # Cylinder axis
			axis_handle_radius,
			axis_handle_length
		)
		
		if handle_hit >= 0 and (main_hit < 0 or handle_hit < main_hit):
			match axis_name:
				"x": _drag_axis = Axis.X
				"y": _drag_axis = Axis.Y
				"z": _drag_axis = Axis.Z
			return handle_hit
	
	return main_hit

func _intersect_cylinder(ray_origin: Vector3, ray_dir: Vector3, 
						 cylinder_pos: Vector3, cylinder_axis: Vector3,
						 radius: float, height: float) -> float:
	# Simplified cylinder-ray intersection
	# Returns distance along ray or -1 if no hit
	
	var to_cyl := cylinder_pos - ray_origin
	var half_h := height * 0.5
	
	# Project ray onto plane perpendicular to cylinder axis
	var perp_dir := ray_dir - ray_dir.dot(cylinder_axis) * cylinder_axis
	var perp_to := to_cyl - to_cyl.dot(cylinder_axis) * cylinder_axis
	
	var a := perp_dir.length_squared()
	if a < 0.0001:
		return -1.0  # Ray parallel to cylinder axis
	
	var b := -2.0 * perp_dir.dot(perp_to)
	var c := perp_to.length_squared() - radius * radius
	
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0:
		return -1.0  # No intersection
	
	var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		t = (-b + sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		return -1.0
	
	# Check height bounds
	var hit_point := ray_origin + ray_dir * t
	var along_axis := (hit_point - cylinder_pos).dot(cylinder_axis)
	if abs(along_axis) > half_h:
		return -1.0
	
	return t

func get_drag_axis() -> Axis:
	return _drag_axis
