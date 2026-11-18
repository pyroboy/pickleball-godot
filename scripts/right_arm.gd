extends Node3D
class_name RightArm

var upper_arm_length: float = 0.35
var forearm_length: float = 0.35


var articulated_hand
var anatomical_wrist_world: = Vector3.ZERO
var visual_stretch: = 1.0
var visual_wrist_lag_deg: = 0.0

@onready var upper_pivot: Node3D = $UpperArmPivot
@onready var forearm_pivot: Node3D = $UpperArmPivot / ForearmPivot
@onready var hand_pivot: Node3D = $UpperArmPivot / ForearmPivot / HandPivot
@onready var upper_mesh: MeshInstance3D = $UpperArmPivot / UpperMesh
@onready var fore_mesh: MeshInstance3D = $UpperArmPivot / ForearmPivot / ForeMesh
@onready var hand_mesh: MeshInstance3D = $UpperArmPivot / ForearmPivot / HandPivot / HandMesh

func _ready() -> void :

	set_lengths(0.35, 0.35)

func set_materials(mat: StandardMaterial3D) -> void :
	if upper_mesh:
		upper_mesh.material_override = mat
	if fore_mesh:
		fore_mesh.material_override = mat
	if hand_mesh:
		hand_mesh.material_override = mat

func set_lengths(upper: float, fore: float) -> void :
	upper_arm_length = upper
	forearm_length = fore

	if not is_inside_tree():
		return

	forearm_pivot.position = Vector3(0, 0, - upper_arm_length)
	hand_pivot.position = Vector3(0, 0, - forearm_length)

	upper_mesh.position = Vector3(0, 0, - upper_arm_length * 0.5)
	if upper_mesh.mesh is CapsuleMesh:
		upper_mesh.mesh = upper_mesh.mesh.duplicate()
		upper_mesh.mesh.height = upper_arm_length
		upper_mesh.mesh.radius = 0.055

	fore_mesh.position = Vector3(0, 0, - forearm_length * 0.5)
	if fore_mesh.mesh is CapsuleMesh:
		fore_mesh.mesh = fore_mesh.mesh.duplicate()
		fore_mesh.mesh.height = forearm_length
		fore_mesh.mesh.radius = 0.045

func solve_ik(target_position: Vector3, pole_position: Vector3, target_transform = null, wrist_target: Vector3 = Vector3.INF) -> void :
	if not upper_pivot or not forearm_pivot:
		return

	var shoulder_pos = upper_pivot.global_position
	var endpoint: Vector3 = wrist_target if wrist_target.is_finite() else target_position
	anatomical_wrist_world = endpoint
	var to_target = endpoint - shoulder_pos
	var distance = to_target.length()
	var direction: Vector3 = to_target.normalized() if to_target.length_squared() > 1e-08 else Vector3.DOWN

	var L1 = upper_arm_length
	var L2 = forearm_length
	var stretch = max(distance / (L1 + L2), 1.0)
	visual_stretch = stretch

	L1 *= stretch
	L2 *= stretch





	forearm_pivot.position = Vector3(0, 0, - L1)
	hand_pivot.position = Vector3(0, 0, - L2)
	if upper_mesh:
		upper_mesh.position = Vector3(0, 0, - L1 * 0.5)
		upper_mesh.scale = Vector3(1, stretch, 1)
	if fore_mesh:
		fore_mesh.position = Vector3(0, 0, - L2 * 0.5)
		fore_mesh.scale = Vector3(1, stretch, 1)

	var angle_shoulder = 0.0
	var angle_elbow = 0.0

	if distance >= L1 + L2:

		angle_shoulder = 0.0
		angle_elbow = 0.0
	elif distance <= abs(L1 - L2):

		angle_shoulder = 0.0
		angle_elbow = PI
	else:
		var denom_s = 2.0 * L1 * distance
		var cos_s = (L1 * L1 + distance * distance - L2 * L2) / denom_s
		angle_shoulder = acos(clamp(cos_s, -1.0, 1.0))

		var denom_e = 2.0 * L1 * L2
		var cos_e = (L1 * L1 + L2 * L2 - distance * distance) / denom_e
		angle_elbow = PI - acos(clamp(cos_e, -1.0, 1.0))


	var to_pole: Vector3 = (pole_position - shoulder_pos).normalized()

	if (to_pole - direction * direction.dot(to_pole)).length_squared() < 1e-10:
		to_pole = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT



	upper_pivot.look_at(shoulder_pos + direction, to_pole, false)


	upper_pivot.rotate_object_local(Vector3.RIGHT, angle_shoulder)


	forearm_pivot.rotation = Vector3.ZERO
	forearm_pivot.rotate_object_local(Vector3.RIGHT, - angle_elbow)



	hand_pivot.global_position = target_position
	if target_transform != null:
		hand_pivot.global_basis = target_transform.basis
	else:
		hand_pivot.rotation = Vector3.ZERO
	preload("res://scripts/player_arm_visual.gd").update_arm(self)
