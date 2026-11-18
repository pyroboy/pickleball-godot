extends RefCounted
## Exact vertical support of the capsule blade and cylindrical handle.
## No mesh sampling or change to collision/racket dimensions.
const D = preload("res://scripts/paddle_dimensions.gd")
const MARGIN := 0.003
static func head_clearance(basis: Basis) -> float:
	var blade := absf(basis.y.y) * D.HEAD_SPINE_HALF + D.HEAD_RADIUS * Vector2(basis.x.y, basis.y.y).length() + absf(basis.z.y) * D.HEAD_HALF_THICKNESS
	var handle := -(D.HANDLE_CENTER_Y - D.HEAD_CENTER_Y) * basis.y.y + absf(basis.y.y) * D.HANDLE_LENGTH * 0.5 + D.HANDLE_RADIUS * Vector2(basis.x.y, basis.z.y).length()
	return maxf(blade, handle) + MARGIN
static func clearance(pose: PostureDefinition, basis: Basis) -> float:
	if pose.has_zone and pose.height_tier == 0 and pose.paddle_floor_clearance < 0.3:
		return maxf(pose.paddle_floor_clearance, head_clearance(basis))
	return pose.paddle_floor_clearance
