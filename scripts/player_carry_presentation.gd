extends RefCounted



const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Calibration = preload("res://scripts/paddle_pose_calibration.gd")
const KEYS: = [
    [Vector3(0.3295943737, -0.07198661566, 0.75604534149), Vector3(35.96657943726, -72.29800415039, -122.25761413574), Vector3(0.35382509232, 0.06113660336, 0.07909345627)], 
    [Vector3(0.2924079895, -0.11512708664, 0.74649810791), Vector3(47.4122543335, -62.79523086548, -126.49958801269), Vector3(0.38318705559, -0.06924551725, 0.06589794159)], 
    [Vector3(0.24956703186, -0.18558859825, 0.72852563858), Vector3(55.10863494873, -50.3941078186, -129.0608215332), Vector3(0.42077255249, -0.18738758564, 0.06381797791)], 
    [Vector3(0.21202397346, -0.29764217138, 0.70668029785), Vector3(59.948802948, -34.13129043579, -132.33662414551), Vector3(0.4629945755, -0.28096401691, 0.06965303421)], 
    [Vector3(0.21173405647, -0.45361965895, 0.69063520432), Vector3(61.81888961792, -14.69887638092, -139.04656982422), Vector3(0.4887162447, -0.34126311541, 0.07559204102)], 
 ]
static func apply(pose: PostureDefinition, bend: float) -> void :
    var progress: float = clampf(bend, 0.0, 1.0) * 4.0
    var index: int = mini(3, int(progress))
    var weight: float = progress - index
    var head: Vector3 = KEYS[index][0].lerp(KEYS[index + 1][0], weight)
    var basis: Basis = _basis(KEYS[index][1]).slerp(_basis(KEYS[index + 1][1]), weight)
    head = Calibration.non_contact_head_from_legacy(head, basis)
    pose.paddle_forehand_mul = head.x;pose.paddle_y_offset = head.y;pose.paddle_forward_mul = head.z
    Orientation.set_canonical_basis(pose, basis)
    pose.right_elbow_pole = KEYS[index][2].lerp(KEYS[index + 1][2], weight)

static func _basis(degrees: Vector3) -> Basis:
    var angles: Vector3 = degrees * (PI / 180.0)
    return Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) * Basis(Vector3.FORWARD, angles.z)
