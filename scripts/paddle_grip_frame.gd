extends RefCounted


const BEVEL_DEG: = 135.0
static func basis(paddle_basis: Basis, is_left: bool, rotation_deg: float = 0.0) -> Basis:
	return paddle_basis * Basis(Vector3.UP, deg_to_rad(BEVEL_DEG + (180.0 if is_left else 0.0) + rotation_deg))
