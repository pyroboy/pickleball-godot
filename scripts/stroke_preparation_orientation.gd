extends RefCounted
const Rotation = preload("res://scripts/paddle_rotation.gd")



const LOAD_FACE_TURN_DEG: = -95.0
const EXACT_APPROACH_PROGRESS: = 0.4
const SERVE_LOAD_CHARGE: = 0.45
const WRIST_LAG_BUDGET_DEG: = 6.0

static func canonical_basis(pose: PostureDefinition) -> Basis:
	return Rotation.unspun_basis(pose)

static func set_canonical_basis(pose: PostureDefinition, basis: Basis) -> void:
	Rotation.set_basis(pose, basis)

static func turn_shaft(pose: PostureDefinition, degrees: float) -> void :
	if is_zero_approx(degrees): return
	set_canonical_basis(pose, canonical_basis(pose) * Basis(Vector3.UP, deg_to_rad(degrees)))

static func drive_turn(base: PostureDefinition, progress: float, charge: float, strength: float, compact: bool) -> float:
	if compact or base.family not in [0, 3]: return 0.0
	var amount: float = clampf(charge, 0.0, 1.0) if base.family == 3 else strength
	var envelope: float = 1.0 - smoothstep(0.0, EXACT_APPROACH_PROGRESS, clampf(progress, 0.0, 1.0))
	return LOAD_FACE_TURN_DEG * amount * envelope

static func serve_turn(charge: float) -> float:
	return LOAD_FACE_TURN_DEG * (1.0 - smoothstep(0.0, SERVE_LOAD_CHARGE, clampf(charge, 0.0, 1.0)))

static func wrist_lag(base: PostureDefinition, progress: float, charge: float, strength: float, compact: bool) -> float:
	if compact or base.family not in [0, 1, 3] or progress <= 0.0 or progress >= EXACT_APPROACH_PROGRESS: return 0.0
	var amount: float = clampf(charge, 0.0, 1.0) if base.family == 3 else strength
	return WRIST_LAG_BUDGET_DEG * amount * pow(sin(PI * progress / EXACT_APPROACH_PROGRESS), 2.0)
