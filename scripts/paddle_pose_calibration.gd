extends RefCounted




const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const LEGACY_HEAD_TO_MAIN_GRIP: = 0.4 - 0.07
const CURRENT_HEAD_TO_MAIN_GRIP: = PaddleSize.HEAD_CENTER_Y - PaddleSize.MAIN_GRIP_Y

static func non_contact_head_from_legacy(head: Vector3, canonical_basis: Basis) -> Vector3:
	var shift: Vector3 = canonical_basis.y * (CURRENT_HEAD_TO_MAIN_GRIP - LEGACY_HEAD_TO_MAIN_GRIP)

	return head + Vector3(shift.x, shift.y, - shift.z)
