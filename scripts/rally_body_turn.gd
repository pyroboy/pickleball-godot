extends RefCounted
## Isolated first-profile shoulder-turn candidate. Authored resources remain unchanged.
static func sample(pose: PostureDefinition) -> PostureDefinition:
	if pose == null or pose.posture_id != 0: return pose
	var result: PostureDefinition = pose.duplicate(false)
	result.set_meta("body_turn_original_yaw_deg",pose.body_yaw_deg)
	result.body_yaw_deg = minf(pose.body_yaw_deg,-30.0)
	return result
