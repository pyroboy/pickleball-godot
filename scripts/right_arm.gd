extends Node3D
class_name RightArm

var upper_arm_length: float = 0.35
var forearm_length: float = 0.35

@onready var upper_pivot: Node3D = $UpperArmPivot
@onready var forearm_pivot: Node3D = $UpperArmPivot/ForearmPivot
@onready var hand_pivot: Node3D = $UpperArmPivot/ForearmPivot/HandPivot
@onready var upper_mesh: MeshInstance3D = $UpperArmPivot/UpperMesh
@onready var fore_mesh: MeshInstance3D = $UpperArmPivot/ForearmPivot/ForeMesh
@onready var hand_mesh: MeshInstance3D = $UpperArmPivot/ForearmPivot/HandPivot/HandMesh

func _ready() -> void:
	# Set default lengths
	set_lengths(0.35, 0.35)

func set_materials(mat: StandardMaterial3D) -> void:
	if upper_mesh:
		upper_mesh.material_override = mat
	if fore_mesh:
		fore_mesh.material_override = mat
	if hand_mesh:
		hand_mesh.material_override = mat

func set_lengths(upper: float, fore: float) -> void:
	upper_arm_length = upper
	forearm_length = fore
	
	if not is_inside_tree():
		return
		
	forearm_pivot.position = Vector3(0, 0, -upper_arm_length)
	hand_pivot.position = Vector3(0, 0, -forearm_length)
	
	upper_mesh.position = Vector3(0, 0, -upper_arm_length * 0.5)
	if upper_mesh.mesh is CapsuleMesh:
		upper_mesh.mesh = upper_mesh.mesh.duplicate()
		upper_mesh.mesh.height = upper_arm_length
		upper_mesh.mesh.radius = 0.055
		
	fore_mesh.position = Vector3(0, 0, -forearm_length * 0.5)
	if fore_mesh.mesh is CapsuleMesh:
		fore_mesh.mesh = fore_mesh.mesh.duplicate()
		fore_mesh.mesh.height = forearm_length
		fore_mesh.mesh.radius = 0.045

func solve_ik(target_position: Vector3, pole_position: Vector3, target_transform: Transform3D = Transform3D()) -> void:
	if not upper_pivot or not forearm_pivot:
		return
		
	var shoulder_pos = upper_pivot.global_position
	var to_target = target_position - shoulder_pos
	var distance = to_target.length()
	var direction = to_target.normalized()
	
	var L1 = upper_arm_length
	var L2 = forearm_length
	var stretch = max(distance / (L1 + L2), 1.0)
	
	L1 *= stretch
	L2 *= stretch
	
	distance = min(distance, L1 + L2 - 0.001)
	
	forearm_pivot.position = Vector3(0, 0, -L1)
	hand_pivot.position = Vector3(0, 0, -L2)
	if upper_mesh:
		upper_mesh.position = Vector3(0, 0, -L1 * 0.5)
		upper_mesh.scale = Vector3(1, 1, stretch)
	if fore_mesh:
		fore_mesh.position = Vector3(0, 0, -L2 * 0.5)
		fore_mesh.scale = Vector3(1, 1, stretch)
	
	var angle_shoulder = 0.0
	var angle_elbow = 0.0
	
	if distance >= L1 + L2:
		# Target too far, simple stretch
		angle_shoulder = 0.0
		angle_elbow = 0.0
	elif distance <= abs(L1 - L2):
		# Fold
		angle_shoulder = 0.0
		angle_elbow = PI
	else:
		var denom_s = 2.0 * L1 * distance
		var cos_s = (L1 * L1 + distance * distance - L2 * L2) / denom_s
		angle_shoulder = acos(clamp(cos_s, -1.0, 1.0))
		
		var denom_e = 2.0 * L1 * L2
		var cos_e = (L1 * L1 + L2 * L2 - distance * distance) / denom_e
		angle_elbow = PI - acos(clamp(cos_e, -1.0, 1.0))
	
	# Plane defined by shoulder, target, and pole
	var to_pole = (pole_position - shoulder_pos).normalized()
	
	# The 'up' vector of look_at aligns the local +Y axis towards the pole.
	# We want the elbow to point towards the pole, so we will pitch the arm towards +Y.
	upper_pivot.look_at(shoulder_pos + direction, to_pole, false)
	
	# Pitching by +angle_shoulder around local X bends the -Z axis towards the +Y axis.
	upper_pivot.rotate_object_local(Vector3.RIGHT, angle_shoulder)
	
	# Reset and bend elbow back towards the target line
	forearm_pivot.rotation = Vector3.ZERO
	forearm_pivot.rotate_object_local(Vector3.RIGHT, -angle_elbow)
	
	# Align hand perfectly to target orientation if provided
	if target_transform != Transform3D():
		hand_pivot.global_transform.basis = target_transform.basis
