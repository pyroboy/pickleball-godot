class_name RotationGizmoV2 extends Node3D

## Simple rotation gizmo with 3 axis rings (X=red, Y=green, Z=blue).
## Emits euler delta (degrees) while dragging.

signal rotated(euler_delta: Vector3)

var field_name: String = ""

const RING_RADIUS: float = 0.22
const RING_THICKNESS: float = 0.04

var _rings: Dictionary = {}  # axis_name -> MeshInstance3D
var _selected_axis: String = ""
var _drag_start_pos: Vector3
var _drag_start_rot: Vector3

func _ready() -> void:
	_add_ring("x", Color(1, 0.3, 0.3))
	_add_ring("y", Color(0.3, 1, 0.3))
	_add_ring("z", Color(0.3, 0.3, 1))

func _add_ring(axis: String, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Ring_%s" % axis.to_upper()
	# Torus in XY plane by default; rotate to correct orientation
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.01
	torus.outer_radius = RING_RADIUS + 0.01
	mesh_inst.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	# Orient torus so its plane normal aligns with rotation axis
	match axis:
		"x": mesh_inst.rotation_degrees = Vector3(0, 90, 0)  # YZ plane
		"y": mesh_inst.rotation_degrees = Vector3(90, 0, 0)  # XZ plane
		"z": mesh_inst.rotation_degrees = Vector3(0, 0, 0)   # XY plane
	add_child(mesh_inst)
	_rings[axis] = mesh_inst

## Raycast against all rings. Returns "x", "y", "z", or "".
func raycast_test(ray_origin: Vector3, ray_dir: Vector3) -> String:
	var best_axis: String = ""
	var best_dist: float = INF
	for axis in _rings:
		var normal := _axis_vector(axis)
		var plane := Plane(normal, global_position)
		var intersection: Variant = plane.intersects_ray(ray_origin, ray_dir)
		if intersection == null:
			continue
		var hit_pos: Vector3 = intersection
		var dist_from_center: float = hit_pos.distance_to(global_position)
		var dist_from_ring: float = absf(dist_from_center - RING_RADIUS)
		if dist_from_ring < RING_THICKNESS and ray_origin.distance_to(hit_pos) < best_dist:
			best_dist = ray_origin.distance_to(hit_pos)
			best_axis = axis
	return best_axis

func highlight_axis(axis: String) -> void:
	for a in _rings:
		var mesh: MeshInstance3D = _rings[a]
		var mat: StandardMaterial3D = mesh.material_override.duplicate()
		if a == axis:
			mat.albedo_color = Color(1, 1, 0.5)
		else:
			mat.albedo_color = _base_color(a)
		mesh.material_override = mat

func clear_highlight() -> void:
	highlight_axis("")

func _base_color(axis: String) -> Color:
	match axis:
		"x": return Color(1, 0.3, 0.3)
		"y": return Color(0.3, 1, 0.3)
		"z": return Color(0.3, 0.3, 1)
		_: return Color.WHITE

func _axis_vector(axis: String) -> Vector3:
	match axis:
		"x": return Vector3.RIGHT
		"y": return Vector3.UP
		"z": return Vector3.FORWARD
		_: return Vector3.UP

## Start a drag on the given axis.
func start_drag(axis: String, ray_origin: Vector3, ray_dir: Vector3) -> void:
	_selected_axis = axis
	_drag_start_rot = Vector3.ZERO
	var plane := Plane(_axis_vector(axis), global_position)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_dir)
	if intersection != null:
		_drag_start_pos = intersection

## Update drag and return euler delta in degrees.
func update_drag(ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	if _selected_axis == "":
		return Vector3.ZERO
	var axis_vec := _axis_vector(_selected_axis)
	var plane := Plane(axis_vec, global_position)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return Vector3.ZERO
	var current_pos: Vector3 = intersection
	var start_vec := (_drag_start_pos - global_position).normalized()
	var current_vec := (current_pos - global_position).normalized()
	# Project onto plane perpendicular to axis
	start_vec = (start_vec - start_vec.dot(axis_vec) * axis_vec).normalized()
	current_vec = (current_vec - current_vec.dot(axis_vec) * axis_vec).normalized()
	if start_vec.length() < 0.001 or current_vec.length() < 0.001:
		return Vector3.ZERO
	var angle: float = atan2(current_vec.cross(start_vec).dot(axis_vec), start_vec.dot(current_vec))
	var delta := Vector3.ZERO
	match _selected_axis:
		"x": delta.x = rad_to_deg(angle)
		"y": delta.y = rad_to_deg(angle)
		"z": delta.z = rad_to_deg(angle)
	_drag_start_pos = current_pos
	rotated.emit(delta)
	return delta

func end_drag() -> void:
	_selected_axis = ""
	clear_highlight()
