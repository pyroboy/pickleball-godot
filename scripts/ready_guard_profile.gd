extends RefCounted


const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const POSES: = [[Vector3(-0.30752635, 0.11906743, 0.441895008), Vector3(25.392910004, -0.021830566, -79.719810486), Vector3(0.367276192, 0.118280649, 0.31504631)], [Vector3(-0.306064725, 0.1229949, 0.417887688), Vector3(31.207759857, 2.411502838, -77.409431458), Vector3(0.373723984, 0.097853422, 0.333044052)], [Vector3(0.307614326, 0.116858363, 0.441230297), Vector3(-63.824539185, -10.028442383, 90.169792175), Vector3(-0.365687609, 0.117630839, 0.313652992)], [Vector3(0.306185126, 0.120188713, 0.417450905), Vector3(-58.583446503, -12.289830208, 92.673835754), Vector3(-0.372115254, 0.097776055, 0.331720352)]]

static func authored_guard(dominant: int = 0) -> PostureDefinition:
	if dominant != 1: return PostureLibrary.instance().get_def(20)
	var authored: PostureDefinition = load("res://data/presentation/ready_left.tres")
	if not GripStore.has_global(): return authored
	# This fallback is outside the main editable library. Never mutate the
	# packaged resource while applying the mirrored global main grip.
	var pose: PostureDefinition = authored.duplicate(true)
	GripStore.apply_to_definition(pose, true)
	return pose

static func compact(pose: PostureDefinition, base: PostureDefinition) -> void :
	if base.paddle_hand == 0 and base.left_hand_mode == 1:



		pose.paddle_forehand_mul = base.paddle_forehand_mul
		pose.paddle_forward_mul = base.paddle_forward_mul
		pose.paddle_y_offset = base.paddle_y_offset + 0.02
		Orientation.set_canonical_basis(pose, Orientation.canonical_basis(base))
		pose.right_elbow_pole = base.right_elbow_pole
		pose.left_elbow_pole = base.left_elbow_pole
		return
	var start: Array = POSES[base.paddle_hand * 2]
	var finish: Array = POSES[base.paddle_hand * 2 + 1]
	var delta: Vector3 = finish[0] - start[0]
	pose.paddle_forehand_mul = base.paddle_forehand_mul + delta.x
	pose.paddle_y_offset = base.paddle_y_offset + delta.y
	pose.paddle_forward_mul = base.paddle_forward_mul + delta.z
	var turn: Basis = _basis(start[1]).inverse() * _basis(finish[1])
	Orientation.set_canonical_basis(pose, Orientation.canonical_basis(base) * turn)
	if base.paddle_hand == 1: pose.left_elbow_pole = base.left_elbow_pole + (finish[2] - start[2])
	else: pose.right_elbow_pole = base.right_elbow_pole + (finish[2] - start[2])

static func _basis(degrees: Vector3) -> Basis:
	var a: Vector3 = degrees * (PI / 180.0)
	return Basis(Vector3.RIGHT, a.x) * Basis(Vector3.UP, a.y) * Basis(Vector3.FORWARD, a.z)
