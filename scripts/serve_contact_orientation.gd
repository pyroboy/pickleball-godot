extends RefCounted
## Contact rotation is additive, but its ball surface point is invariant.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const BALL_RADIUS := 0.0375
const CONTACT_DISTANCE := Size.HEAD_HALF_THICKNESS + BALL_RADIUS
class CanonicalAxes extends RefCounted:
	var global_transform := Transform3D.IDENTITY
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD
static var _axes := CanonicalAxes.new()

static func apply_pivot(pose: PostureDefinition, baseline: PostureDefinition, weight: float) -> void:
	# Include shaft spin and its grip pivot, not only the unspun Euler frame.
	# Strip each authored head translation so this only compensates orientation.
	var face_point := Size.HEAD_OFFSET + Vector3.BACK * CONTACT_DISTANCE
	var old_head := Vector3(baseline.paddle_forehand_mul, baseline.paddle_y_offset, -baseline.paddle_forward_mul)
	var new_head := Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, -pose.paddle_forward_mul)
	var old_offset: Vector3 = Path.canonical_transform(baseline) * face_point - old_head
	var new_offset: Vector3 = Path.canonical_transform(pose) * face_point - new_head
	var correction: Vector3 = (old_offset - new_offset) * clampf(weight, 0.0, 1.0)
	pose.paddle_forehand_mul += correction.x
	pose.paddle_y_offset += correction.y
	pose.paddle_forward_mul -= correction.z

static func diagnostics(pose: PostureDefinition, player = null) -> Dictionary:
	var frame: Transform3D = Path.canonical_transform(pose)
	var shoulder: Vector3 = Body.shoulder_world(_axes, pose)
	var floor_y := -1.0
	var budget := Wrist.DEFAULT_LINK_BUDGET
	if player != null:
		frame = Path.world_transform(player, pose)
		shoulder = Body.shoulder_world(player, pose)
		floor_y = player.COURT_FLOOR_Y
		budget = Wrist.link_budget(player, pose)
	var distance: float = shoulder.distance_to(Wrist.wrist_world(frame, pose))
	var lowest := INF
	for point in Size.head_hull_points(): lowest = minf(lowest, (frame * point).y)
	var unreachable: bool = distance > budget + Wrist.NUMERICAL_EPSILON
	var below_floor: bool = lowest < floor_y - .0001
	var warning := ""
	if unreachable: warning = "Contact orientation exceeds arm reach; the hand may not seat. Reduce rotation or adjust body/grip."
	if below_floor: warning += (" " if not warning.is_empty() else "") + "The Contact paddle extends below the court."
	return {"limited": unreachable or below_floor, "warning": warning, "wrist_distance": distance,
		"arm_budget": budget, "lowest_paddle_y": lowest, "floor_y": floor_y}
