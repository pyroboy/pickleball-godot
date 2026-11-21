extends RefCounted
## Relative bevel choices, independent of world paddle orientation.
## Positive canonical angles describe the right hand; left-hand values mirror.
const PRESET_NAMES := ["Continental", "Eastern forehand", "Semi-Western forehand", "Eastern backhand", "Custom"]
const PRESET_ANGLES := [0.0, 45.0, 90.0, -45.0]

static func relative_rotation(pose) -> float:
	return wrapf((pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg) * (-1.0 if pose.paddle_hand == 1 else 1.0), -180.0, 180.0)

static func spin_for_relative(pose, degrees: float) -> float:
	return wrapf(pose.main_grip_rotation_deg - degrees * (-1.0 if pose.paddle_hand == 1 else 1.0), -180.0, 180.0)

static func set_relative_rotation(pose, degrees: float) -> void:
	pose.paddle_in_hand_rotation_deg = spin_for_relative(pose, degrees)

static func preset_index(pose) -> int:
	var rotation := relative_rotation(pose)
	for index in range(PRESET_ANGLES.size()):
		if absf(wrapf(rotation - PRESET_ANGLES[index], -180.0, 180.0)) < 0.01: return index
	return PRESET_ANGLES.size()
