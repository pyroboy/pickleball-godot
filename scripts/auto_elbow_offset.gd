extends RefCounted
## Transactional whole-guide offsets. Scene-free solve() may run on a worker.
## Body-pivot local frame at EACH source time: +X right, +Y up, +Z backward.
## Meters internally. This is a preference, never a literal elbow translation.
const Route = preload("res://scripts/auto_elbow_route.gd")
const Fixture = preload("res://scripts/auto_elbow_fixture.gd")
const Quality = preload("res://scripts/auto_elbow_quality.gd")
const VERSION = "body-local-guide-offset-v1"
const MAX_OFFSET_M = 0.20
var generation := 0
var accepted: Dictionary = {}
var zero_routes: Array = []
var offsets: Array = [Vector3.ZERO, Vector3.ZERO]

func initialize(base: Dictionary) -> bool:
	generation += 1
	accepted = {}; zero_routes = []; offsets = [Vector3.ZERO, Vector3.ZERO]
	if not bool(base.get("quality", {}).get("apply", false)): return false
	zero_routes = base.bakes.duplicate(true)
	accepted = {"valid": true, "bakes": zero_routes, "offsets": offsets.duplicate(), "status": "zero_offset"}
	return true

func request(side: int, value: Vector3) -> Dictionary:
	generation += 1
	var wanted := offsets.duplicate()
	if side < 0 or side > 1: return {"ticket": generation, "valid": false, "status": "invalid_arm"}
	wanted[side] = value
	return {"ticket": generation, "valid": true, "offsets": wanted}

func cancel() -> void:
	generation += 1 # Last accepted route deliberately remains visible.

func commit(ticket: int, result: Dictionary) -> bool:
	if ticket != generation or not bool(result.get("valid", false)): return false
	accepted = result; offsets = result.offsets.duplicate()
	return true

static func guide_frame(t: float, source: Dictionary, side: int, zero: Dictionary, offset: Vector3) -> Dictionary:
	var pair: Array = source.get("%.9f" % t, [])
	if pair.is_empty(): return {}
	var frame: Dictionary = pair[side].duplicate(true)
	var reference := Route.sample(zero, t, frame)
	if not bool(reference.get("valid", false)): return {}
	# Rotation only: body scaling must never scale centimeter controls.
	frame.guide_elbow = reference.elbow + (frame.body_transform as Transform3D).basis.orthonormalized() * offset
	return frame

static func solve(knots: Array, source: Dictionary, fine: Array, duration: float, zero: Array, wanted: Array) -> Dictionary:
	var failed := {"valid": false, "status": "invalid_offset", "offsets": wanted}
	if zero.size() != 2 or wanted.size() != 2: return failed
	for value in wanted:
		if not (value is Vector3) or not value.is_finite(): return failed
		if maxf(absf(value.x), maxf(absf(value.y), absf(value.z))) > MAX_OFFSET_M: return failed
	var hash_context := HashingContext.new(); hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes({"version":VERSION,"source":source,"offsets":wanted,"zero_nodes":[zero[0].nodes,zero[1].nodes]}))
	var input_hash := hash_context.finish().hex_encode()
	# Exact route identity, including original candidate order/interpolant.
	if wanted[0] == Vector3.ZERO and wanted[1] == Vector3.ZERO:
		return {"valid": true, "status": "zero_offset", "bakes": zero.duplicate(), "offsets": wanted, "input_sha256":input_hash, "quality":{"apply":true,"status":"exact_zero_route_restored"}}
	var planned: Array = []
	for side in range(2):
		if wanted[side] == Vector3.ZERO:
			planned.append(zero[side]); continue
		var frames: Array = []
		for frame in knots[side]: frames.append(guide_frame(frame.time, source, side, zero[side], wanted[side]))
		planned.append(Route.bake(frames, {"frame_at": guide_frame.bind(source, side, zero[side], wanted[side]), "require_obstacles": true, "extra_evaluator": Fixture.paddle_constraint, "velocity_weight": 10.0, "angular_velocity_weight": 5.0, "baseline_weight": 0.1, "guide_weight": 100.0, "max_validation_step_s": duration / 120.0 * 1.001}))
		if not bool(planned[-1].complete): return {"valid": false, "status": "no_complete_model_safe_route", "offsets": wanted}
	var old_paths: Array = [[], []]; var new_paths: Array = [[], []]
	var max_guide_error := 0.0; var max_movement := 0.0
	for pair in fine:
		var solutions: Array = []
		for side in range(2):
			var frame: Dictionary = pair[side]
			var solution := Route.sample(planned[side], frame.time, frame)
			if not bool(solution.get("feasible", false)): return {"valid": false, "status": "dense_sample_failed", "offsets": wanted}
			solutions.append(solution)
			var original := Route.sample(zero[side], frame.time, frame)
			var guide: Vector3 = original.elbow + frame.body_transform.basis.orthonormalized() * wanted[side]
			max_guide_error = maxf(max_guide_error, solution.elbow.distance_to(guide))
			max_movement = maxf(max_movement, solution.elbow.distance_to(original.elbow))
			old_paths[side].append(frame.baseline_elbow); new_paths[side].append(solution.elbow)
		if not bool(Fixture.validate_pair(pair, solutions).valid): return {"valid": false, "status": "final_pair_failed", "offsets": wanted}
	var quality := Quality.decide(Quality.metrics(old_paths), Quality.metrics(new_paths), false, true)
	if not bool(quality.apply): return {"valid": false, "status": quality.status, "offsets": wanted}
	return {"valid": true, "status": "constrained_no_change" if max_movement < 0.000001 else "projected_model_safe_route", "bakes": planned, "offsets": wanted, "input_sha256":input_hash, "max_guide_error_m": max_guide_error, "max_elbow_movement_m": max_movement, "quality": quality, "continuous_time_certified": false}

static func apply_solution(player, frame: Dictionary, solution: Dictionary, side: int) -> Dictionary:
	# Prototype-only numerical repair. Production look_at/rotate preserves scale,
	# so repeated reconstruction accumulates unintended float32 pivot scaling.
	# The route contract is NOMINAL rigid links, not that accidental scale.
	# Both joint rotations are rebuilt by solve_ik immediately afterward.
	if not bool(solution.get("feasible", false)): return {"applied":false,"reason":"route_not_feasible"}
	var arm = player.right_arm_node if side == 0 else player.left_arm_node
	var scale_error: float = (arm.upper_pivot.global_basis.get_scale()-Vector3.ONE).length()
	if scale_error > 0.001: return {"applied":false,"reason":"unexpected_nonunit_arm_scale"}
	arm.upper_pivot.global_basis = arm.upper_pivot.global_basis.orthonormalized()
	arm.forearm_pivot.basis = Basis.IDENTITY
	var applied := Fixture.apply_solution(player,frame,solution,side)
	applied["preapply_numerical_scale_error"] = scale_error
	return applied
