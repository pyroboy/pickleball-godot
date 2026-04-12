extends Node3D
class_name Leg

var thigh_length: float = 0.38
var shin_length: float = 0.36

@onready var thigh_pivot: Node3D = $ThighPivot
@onready var shin_pivot: Node3D = $ThighPivot/ShinPivot
@onready var foot_pivot: Node3D = $ThighPivot/ShinPivot/FootPivot
@onready var thigh_mesh: MeshInstance3D = $ThighPivot/ThighMesh
@onready var shin_mesh: MeshInstance3D = $ThighPivot/ShinPivot/ShinMesh
@onready var foot_mesh: MeshInstance3D = $ThighPivot/ShinPivot/FootPivot/FootMesh

func _ready() -> void:
	set_lengths(0.38, 0.36)

func set_materials(body_mat: StandardMaterial3D, shoe_mat: StandardMaterial3D) -> void:
	if thigh_mesh:
		thigh_mesh.material_override = body_mat
	if shin_mesh:
		shin_mesh.material_override = body_mat
	if foot_mesh:
		foot_mesh.material_override = shoe_mat

func set_lengths(thigh: float, shin: float) -> void:
	thigh_length = thigh
	shin_length = shin

	if not is_inside_tree():
		return

	shin_pivot.position = Vector3(0, 0, -thigh_length)
	foot_pivot.position = Vector3(0, 0, -shin_length)

	thigh_mesh.position = Vector3(0, 0, -thigh_length * 0.5)
	if thigh_mesh.mesh is CapsuleMesh:
		thigh_mesh.mesh = thigh_mesh.mesh.duplicate()
		thigh_mesh.mesh.height = thigh_length
		thigh_mesh.mesh.radius = 0.06

	shin_mesh.position = Vector3(0, 0, -shin_length * 0.5)
	if shin_mesh.mesh is CapsuleMesh:
		shin_mesh.mesh = shin_mesh.mesh.duplicate()
		shin_mesh.mesh.height = shin_length
		shin_mesh.mesh.radius = 0.05

func solve_ik(target_position: Vector3, pole_position: Vector3, foot_tilt: float = 0.0) -> void:
	if not thigh_pivot or not shin_pivot:
		return

	var hip_pos = thigh_pivot.global_position
	var to_target = target_position - hip_pos
	var distance = to_target.length()
	var direction = to_target.normalized()

	var L1 = thigh_length
	var L2 = shin_length
	var stretch = max(distance / (L1 + L2), 1.0)

	L1 *= stretch
	L2 *= stretch

	distance = min(distance, L1 + L2 - 0.001)

	shin_pivot.position = Vector3(0, 0, -L1)
	foot_pivot.position = Vector3(0, 0, -L2)
	if thigh_mesh:
		thigh_mesh.position = Vector3(0, 0, -L1 * 0.5)
		thigh_mesh.scale = Vector3(1, 1, stretch)
	if shin_mesh:
		shin_mesh.position = Vector3(0, 0, -L2 * 0.5)
		shin_mesh.scale = Vector3(1, 1, stretch)

	var angle_hip = 0.0
	var angle_knee = 0.0

	if distance >= L1 + L2:
		angle_hip = 0.0
		angle_knee = 0.0
	elif distance <= abs(L1 - L2):
		angle_hip = 0.0
		angle_knee = PI
	else:
		var denom_h = 2.0 * L1 * distance
		var cos_h = (L1 * L1 + distance * distance - L2 * L2) / denom_h
		angle_hip = acos(clamp(cos_h, -1.0, 1.0))

		var denom_k = 2.0 * L1 * L2
		var cos_k = (L1 * L1 + L2 * L2 - distance * distance) / denom_k
		angle_knee = PI - acos(clamp(cos_k, -1.0, 1.0))

	var to_pole = (pole_position - hip_pos).normalized()
	thigh_pivot.look_at(hip_pos + direction, to_pole, false)
	thigh_pivot.rotate_object_local(Vector3.RIGHT, angle_hip)

	shin_pivot.rotation = Vector3.ZERO
	shin_pivot.rotate_object_local(Vector3.RIGHT, -angle_knee)

	# Keep foot flat on the ground (reset to world-up orientation)
	foot_pivot.global_rotation = Vector3(foot_tilt * 0.3, 0, 0)  # max ~17 degrees tilt
