extends RefCounted
## Match adapter for the immutable, grounded long/high reach. This owns only a
## physically admitted presentation. The caller owns movement collisions, ball
## flight, finite contact, scoring and outgoing-shot authority.
const Identity = preload("res://scripts/special_action_identity.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Motion = preload("res://scripts/prototype/long_reach_pose.gd")
const Candidate = preload("res://scripts/prototype/dive_save_controller.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const ArmBudget = preload("res://scripts/live_arm_budget.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")
const Contact = preload("res://scripts/finite_paddle_contact.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")
const Floor = preload("res://scripts/paddle_floor_geometry.gd")
const FootContact = preload("res://scripts/pose_foot_contacts.gd")
const Shot = preload("res://scripts/shot_physics.gd")
const BallScript = preload("res://scripts/ball.gd")
const STEP := 1.0 / 120.0
const CONTACT_OPEN := 0.38
const CONTACT_CLOSE := 0.57
const ROOT_TOLERANCE := 0.035
const MAX_CANDIDATE_PROBES := 6
const MAX_HAND_RATE_DEG := 720.0
var actor
var hands = Hands.new()
var shot = Shot.new()
var active := false
var elapsed := 0.0
var contacted := false
var flight_id := -1
var plan: Dictionary = {}
var status := "idle"
var diagnostics: Dictionary = {}
var latest_motion: Dictionary = {}
var handoff: Dictionary = {}
var _origin := Vector3.ZERO
var _base: Dictionary = {}
var _base_body_rotation := Vector3.ZERO
var _base_body_scale := Vector3.ONE
var _torso_node: Node3D
var _hips_node: Node3D
var _skin
var _entry: Dictionary = {}
var _ankles: Array[Vector3] = []
var _yaws: Array[float] = []
var _foot_bases: Array[Basis] = []
var _feet_planted: Array[bool] = [true, true]
var _main_wrist := Vector3.ZERO
var _main_channels: Dictionary = {}
var _grip_anchor := Vector3.ZERO
var _grip_rotation := 0.0
var _certified_payload := PackedByteArray()
var _certified_entry := PackedByteArray()
var _last_grip_basis := Basis.IDENTITY
var _last_grip_anchor := Vector3.ZERO
var timing: Dictionary = {}
var profile_certification := false
var _motion_cache_parameters: Array = []
var _motion_cache: Dictionary = {}
var _entry_grip_basis := Basis.IDENTITY
var _support_finger_rotations: Array[Quaternion] = []
var _support_finger_fields: Dictionary = {}

func _init(owner) -> void:
	actor = owner
	hands.initialize(actor)
	_torso_node = actor.body_pivot.get_node("TorsoMesh")
	_hips_node = actor.body_pivot.get_node("HipsMesh")
	_skin = actor.body_pivot.get_meta("articulated_torso")
	var game = actor.get_parent()
	shot.setup(game.ball, game.player_left, game.player_right)

func _eligible(state: Dictionary) -> bool:
	# Planning can precede the real first bounce, but contact cannot. A legal
	# forecasted groundstroke is not permission to volley or bypass foot history.
	if not bool(state.get("playing", false)) or bool(state.get("paused", false)) or not bool(state.get("in_play", false)): return false
	if actor.posture.editor_preview_mode or actor.is_jumping or not Identity.matches(actor, state): return false
	var ball = actor._get_ball_ref()
	return Identity.incoming(actor, ball) and ball.bounces_since_last_hit < 2 and Identity.flight_matches(ball, state)

func _supported_entry() -> bool:
	var ik = actor.leg_ik
	return ik != null and ik.feet_initialized and ik.right_foot_locked and ik.left_foot_locked and ik._active_side < 0 and not ik._run_active and not ik._airborne and Vector2(actor.current_velocity.x, actor.current_velocity.z).length() <= 0.18

func _necessary_entry_fit() -> bool:
	for side in [0, 1]:
		var arm = actor.right_arm_node if side == 0 else actor.left_arm_node
		if arm.upper_pivot.global_position.distance_to(arm.anatomical_wrist_world) > arm.upper_arm_length + arm.forearm_length - 0.001: return false
		if not _channels(arm, side == 1).within_animation_budget: return false
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		if not FootContact.reach_report(leg.thigh_pivot.global_position, leg.foot_pivot.global_position, leg.thigh_length, leg.shin_length).feasible: return false
	return true

func coarse_candidate_possible(prediction: Dictionary, state: Dictionary) -> bool:
	# Necessary forecast filter only. No rig writes, certificates, timing or
	# status updates; the exact chooser remains the admission authority.
	if active or not _eligible(state) or not _supported_entry() or not _necessary_entry_fit(): return false
	return not _coarse_forecasts(prediction, state).is_empty()

func _coarse_forecasts(prediction: Dictionary, state: Dictionary) -> Array:
	var result: Array = []
	var origin: Vector3 = actor.global_position
	var bounds := Rect2(actor.min_x, actor.min_z, actor.max_x - actor.min_x, actor.max_z - actor.min_z)
	var base_bounces: int = int(state.get("forecast_bounces", actor._get_ball_ref().bounces_since_last_hit))
	var fault_time: float = Planner.predicted_fault_time(actor, Identity.forecast_ball(actor._get_ball_ref(), base_bounces), prediction)
	for sample: Dictionary in prediction.get("samples", []):
		if float(sample.get("time", 0.0)) < 0.405: continue
		if float(sample.get("time", 0.0)) > CONTACT_CLOSE: break
		if float(sample.get("time", 0.0)) >= fault_time: continue
		if base_bounces + int(sample.get("bounces", 0)) != 1: continue
		var forecast_state := state.duplicate(); forecast_state.bounces = 1
		var forecast_sample := sample.duplicate(); forecast_sample.bounces = 0
		var proposed: Dictionary = Candidate.choose_plan(origin, forecast_state, [forecast_sample], bounds)
		if not proposed.is_empty(): result.append({"sample": sample, "proposed": proposed})
	return result

func choose_plan(prediction: Dictionary, state: Dictionary, intent: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	timing = {"choose_usec": 0, "candidate_probes": 0, "full_preflights": 0}
	_certified_payload = PackedByteArray(); _certified_entry = PackedByteArray()
	status = "rejected: incoming groundstroke or supported entry unavailable"
	if active or not _eligible(state) or not _supported_entry(): timing.choose_usec = Time.get_ticks_usec() - started; return {}
	if not _necessary_entry_fit():
		status = "rejected: current supported rig exceeds unchanged arm/wrist/leg budgets"
		timing.choose_usec = Time.get_ticks_usec() - started
		return {}
	if not intent.get("target", Vector3.INF).is_finite(): status = "rejected: an actual return target is required"; return {}
	status = "rejected: no legal reachable forecast inside reaction window"
	var forecasts := _coarse_forecasts(prediction, state)
	if forecasts.is_empty(): timing.choose_usec = Time.get_ticks_usec() - started; return {}
	var capture_started := Time.get_ticks_usec()
	var captured := _snapshot()
	_capture_entry()
	timing["capture_usec"] = Time.get_ticks_usec() - capture_started
	var result: Dictionary = {}
	var probed := 0
	for item: Dictionary in forecasts:
		var sample: Dictionary = item.sample
		var proposed: Dictionary = item.proposed
		proposed.travel = minf(float(proposed.travel), Motion.maximum_travel(float(proposed.point.y)))
		proposed.target = _origin + proposed.direction * proposed.travel
		proposed["incoming_velocity"] = sample.get("vel", Vector3.ZERO)
		proposed["backhand"] = proposed.direction.dot(actor._get_forehand_axis()) < 0.0
		proposed["intent"] = intent.duplicate(true)
		proposed = Identity.annotate(actor, proposed)
		proposed["groundstroke_bounces"] = 1
		# Approach below the incoming ball, then lift into the supported strike.
		# Low contacts retain floor clearance; taller contacts need more space
		# under the finite paddle head during its preparation turn.
		var rear: float = (Vector3(proposed.point) - _origin).dot(actor._get_forward_axis())
		proposed["rear_retrieval"] = rear < -0.15
		proposed["preparation_dip"] = 0.12 if rear < -0.15 else 0.12 * smoothstep(0.48, 0.85, float(proposed.point.y)) + 0.15 * smoothstep(1.50, 1.85, float(proposed.point.y))
		proposed["forecast_bounces"] = int(sample.get("bounces", 0))
		probed += 1
		if probed > MAX_CANDIDATE_PROBES: break
		var fit_started := Time.get_ticks_usec()
		var fitted := _fit_contact(proposed)
		timing["fit_usec"] = int(timing.get("fit_usec", 0)) + Time.get_ticks_usec() - fit_started
		if not fitted: continue
		timing.full_preflights += 1
		# Adjacent forecast samples share this same entry and continuous path.
		# Do not block input with repeated 217-frame certifications on one edge.
		var preflight_started := Time.get_ticks_usec()
		var certified := _preflight(proposed, prediction)
		timing["preflight_usec"] = Time.get_ticks_usec() - preflight_started
		if not certified: break
		result = proposed
		result["entry_root"] = _origin
		result["ball_snapshot"] = _flight_snapshot()
		result["provenance"] = "actual supported rig; finite paddle fit; full 120 Hz arm/wrist/foot preflight"
		status = "admitted grounded reach candidate"
		break
	_restore(captured)
	if not result.is_empty():
		_certified_payload = var_to_bytes(result)
		_certified_entry = _entry_signature()
	timing["choose_usec"] = Time.get_ticks_usec() - started
	timing["candidate_probes"] = mini(probed, MAX_CANDIDATE_PROBES)
	return result

func begin(candidate: Dictionary, state: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	if active or not _valid_candidate(candidate) or not _eligible(state) or not _supported_entry(): status = "rejected: entry no longer supported"; return false
	if int(candidate.get("flight_id", -2)) != int(state.get("flight_id", -1)) or not Identity.matches(actor, candidate):
		status = "rejected: stale flight or different actor"; return false
	if not candidate.get("entry_root", Vector3.INF).is_finite() or actor.global_position.distance_to(candidate.entry_root) > ROOT_TOLERANCE:
		status = "rejected: entry root changed"; return false
	if candidate.get("ball_snapshot", {}) != _flight_snapshot(): status = "rejected: stale incoming prediction"; return false
	var checked := candidate.duplicate(true)
	var cached := not _certified_payload.is_empty() and var_to_bytes(candidate) == _certified_payload and _entry_signature() == _certified_entry
	if not cached:
		var captured := _snapshot()
		_capture_entry()
		var accepted := _fit_contact(checked) and _preflight(checked)
		_restore(captured)
		if not accepted: return false
	timing["begin_usec"] = Time.get_ticks_usec() - started
	timing["begin_reused_certificate"] = cached
	plan = checked; flight_id = int(state.flight_id); active = true; elapsed = 0.0; contacted = false
	latest_motion = _motion(0.0); handoff.clear(); status = "grounded reach active"
	return true

func advance(delta: float, state: Dictionary) -> Dictionary:
	if not active: return {"active": false, "root_delta": Vector3.ZERO, "contact_window": false}
	if not is_finite(delta) or delta < 0.0: return {"active": true, "root_delta": Vector3.ZERO, "contact_window": false}
	if bool(state.get("paused", false)): return {"active": true, "root_delta": Vector3.ZERO, "contact_window": false}
	if not Identity.matches(actor, plan) or not Identity.matches(actor, state) or not bool(state.get("playing", false)) or (not contacted and (not _eligible(state) or int(state.get("flight_id", -1)) != flight_id)):
		cancel("incoming ownership or legality changed")
		return {"active": false, "root_delta": Vector3.ZERO, "contact_window": false}
	elapsed = minf(Motion.DURATION, elapsed + delta)
	latest_motion = _motion(elapsed)
	var target: Vector3 = _origin + latest_motion.root_offset
	return {"active": true, "root_target": target, "root_delta": target - actor.global_position,
		"elapsed": elapsed, "phase": latest_motion.phase, "contact_window": contact_window(), "finished": elapsed >= Motion.DURATION}

func contact_window() -> bool:
	var ball = actor._get_ball_ref()
	return active and not contacted and elapsed >= CONTACT_OPEN and elapsed <= CONTACT_CLOSE and Identity.matches(actor, plan) and Identity.incoming(actor, ball) and ball.flight_id == flight_id and ball.bounces_since_last_hit == 1

func mark_contact() -> void:
	# Called only AFTER the owner's actual finite contact and authority checks.
	if active: contacted = true

func apply() -> bool:
	if not active: return false
	var target: Vector3 = _origin + _motion(elapsed).root_offset
	if actor.global_position.distance_to(target) > ROOT_TOLERANCE:
		cancel("root movement blocked; presentation did not bypass collision")
		return false
	var before := _snapshot()
	if not _present(elapsed, plan, false):
		diagnostics["runtime_failed_time"] = elapsed; diagnostics["runtime_failure"] = status
		_restore(before)
		cancel("actual rig no longer fits the admitted path: " + status)
		return false
	_sync_foot_state()
	if elapsed >= Motion.DURATION:
		status = "grounded reach complete"
		_finish_handoff()
	return true

func cancel(reason: String = "cancelled") -> void:
	status = reason
	if active: _finish_handoff()
	else: active = false

func _finish_handoff() -> void:
	# Preserve the exact current root, paddle and court contacts. Normal IK can
	# finish a raised shoe or turn using its ordinary step/recovery machinery.
	_sync_foot_state()
	var ik = actor.leg_ik
	ik._run_active = false; ik._run_stopping = false; ik._moving = false
	ik._live_stance_initialized = false; ik._active_side = -1
	for side in [0, 1]:
		if not _feet_planted[side]:
			ik._active_side = side
			ik._live_step_origin = ik.right_foot_smooth if side == 0 else ik.left_foot_smooth
			ik._step_elapsed = 0.0; ik._step_duration = ik.STANCE_STEP_DURATION
			break
	ik._last_body_position = Vector3(actor.global_position.x, ik.ANKLE_HEIGHT, actor.global_position.z)
	handoff = {"body": actor.body_pivot.transform, "paddle": actor.paddle_node.global_transform,
		"root": actor.global_position, "feet": [ik.right_foot_smooth, ik.left_foot_smooth],
		"finished": elapsed >= Motion.DURATION, "reason": status}
	active = false

func _capture_entry() -> void:
	_origin = actor.global_position
	_base = Motion.capture_base(actor)
	_base_body_rotation = actor.body_pivot.rotation
	_base_body_scale = actor.body_pivot.scale
	var torso: Node3D = actor.body_pivot.get_node("TorsoMesh")
	var arm = actor.right_arm_node
	_main_wrist = torso.to_local(arm.anatomical_wrist_world)
	_main_channels = _channels(arm, false)
	_grip_anchor = actor.paddle_node.to_local(arm.hand_mesh.global_position)
	_entry_grip_basis = actor.paddle_node.global_basis.inverse() * arm.hand_mesh.global_basis
	var pose = actor.get_runtime_posture_def()
	_grip_rotation = float(pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
	_ankles.clear(); _yaws.clear(); _foot_bases.clear()
	for leg in [actor.right_leg_node, actor.left_leg_node]:
		_ankles.append(leg.foot_pivot.global_position); _yaws.append(leg.foot_pivot.global_rotation.y); _foot_bases.append(leg.foot_pivot.global_basis)
	_feet_planted = [true, true]
	var support_model = actor.left_arm_node.articulated_hand
	_support_finger_rotations.clear()
	for bone in range(support_model.WRIST_BRIDGE_BONE): _support_finger_rotations.append(support_model.skeleton.get_bone_pose_rotation(bone))
	_support_finger_fields.clear()
	for key in ["_mode", "_closure", "_index_closure", "_support_style_weight", "_recovery_pose_key"]: _support_finger_fields[key] = support_model.get(key)

func _motion(time: float, selected: Dictionary = plan) -> Dictionary:
	var when: float = float(selected.get("time", Motion.CONTACT_TIME))
	var parameters: Array = [when, selected.get("direction", Vector3.RIGHT), float(selected.get("travel", 0.0)), bool(selected.get("backhand", false)), float(selected.get("point", Vector3.ZERO).y)]
	if parameters != _motion_cache_parameters:
		_motion_cache_parameters = parameters; _motion_cache.clear()
	if _motion_cache.has(time): return _motion_cache[time].duplicate()
	var t: float = time * Motion.CONTACT_TIME / when if time <= when else Motion.CONTACT_TIME + (time - when) * (Motion.DURATION - Motion.CONTACT_TIME) / (Motion.DURATION - when)
	var result := Motion.sample(t, parameters[1], parameters[2], parameters[3], parameters[4])
	# Only immutable local motion math is cached. Entry rig, ball prediction,
	# legality, contact fit and every certification sample are still observed.
	if _motion_cache.size() < 512: _motion_cache[time] = result.duplicate()
	return result

func _valid_candidate(candidate: Dictionary) -> bool:
	if candidate.is_empty(): return false
	var time: float = float(candidate.get("time", NAN))
	var travel: float = float(candidate.get("travel", NAN))
	var point: Vector3 = candidate.get("point", Vector3.INF)
	var direction: Vector3 = candidate.get("direction", Vector3.ZERO)
	return int(candidate.get("groundstroke_bounces", -1)) == 1 and is_finite(time) and time >= CONTACT_OPEN and time <= CONTACT_CLOSE and is_finite(travel) and travel >= 0.0 and travel <= Motion.maximum_travel(point.y) + 0.00001 and point.is_finite() and direction.is_finite() and absf(direction.length() - 1.0) < 0.0001

func _fit_contact(candidate: Dictionary) -> bool:
	if not _valid_candidate(candidate): status = "rejected: invalid candidate geometry or timing"; return false
	if not candidate.get("point", Vector3.INF).is_finite() or not candidate.get("incoming_velocity", Vector3.INF).is_finite(): return false
	var motion: Dictionary = _motion(float(candidate.time), candidate)
	actor.global_position = _origin + motion.root_offset
	_apply_body(motion)
	var intent: Dictionary = candidate.get("intent", {})
	var target: Vector3 = intent.get("target", Vector3.INF)
	if not target.is_finite(): status = "rejected: invalid target"; return false
	var arm = actor.right_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var head_extent := Vector3(Paddle.HEAD_RADIUS, Paddle.LENGTH - Paddle.MAIN_GRIP_Y, Paddle.HEAD_HALF_THICKNESS).length()
	var reach: float = arm.upper_arm_length + arm.forearm_length + arm.articulated_hand.wrist_socket.length() + head_extent + BallScript.BALL_RADIUS + Surface.contact_surface_tolerance()
	if shoulder.distance_to(candidate.point) > reach: status = "rejected: finite head beyond actual arm reach"; return false
	var response: Dictionary = shot.solve_aimed_launch(candidate.point, target, clampf(float(intent.get("charge", 0.25)), 0.0, 1.0), actor.get_court_side(), int(intent.get("spin_mode", 0)), str(intent.get("aim_mode", "AUTO")), str(intent.get("shot_intent", "GROUNDSTROKE")))
	if not response.get("feasible", false): status = "rejected: requested return cannot be solved"; return false
	var impulse: Vector3 = response.velocity - candidate.incoming_velocity
	if impulse.length_squared() < 0.00001: return false
	var normal := impulse.normalized()
	var down: Vector3 = Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if down.length_squared() < 0.00001: down = actor._get_forward_axis() - normal * actor._get_forward_axis().dot(normal)
	down = down.normalized()
	var backhand: bool = candidate.backhand
	var low: bool = candidate.point.y < 0.50
	var preferred := Vector2(90.0, 45.0) if low and backhand else (Vector2(-30.0, -90.0) if low else (Vector2(135.0, 0.0) if backhand else Vector2(-135.0, 0.0)))
	if candidate.point.y > 1.05:
		var high := smoothstep(1.05, 1.45, float(candidate.point.y)); var upper := smoothstep(1.45, 1.85, float(candidate.point.y))
		preferred = Vector2(135.0 + 15.0 * high + 15.0 * upper, 45.0 * high * (1.0 - upper)) if backhand else Vector2(-135.0 - 45.0 * upper, 0.0)
	# Preserve the original roll first, with small bounded grip/roll alternatives
	# when the live entry/target differs from the isolated practice fixture.
	for roll_offset in [0.0, -15.0, 15.0, -30.0, 30.0]:
		for grip_offset in [0.0, -15.0, 15.0]:
			if _fit_orientation(candidate, response, normal, down, preferred + Vector2(roll_offset, grip_offset), motion):
				candidate["follow_through"] = _follow_through_budget(candidate)
				return true
	status = "rejected: no finite contact face within unchanged wrist budget"
	return false

func _fit_orientation(candidate: Dictionary, response: Dictionary, normal: Vector3, down: Vector3, preferred: Vector2, motion: Dictionary) -> bool:
	var arm = actor.right_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var backhand: bool = candidate.backhand
	var target: Vector3 = candidate.intent.target
	var y: Vector3 = down.rotated(normal, deg_to_rad(preferred.x))
	var basis := Basis(y.cross(normal).normalized(), y, normal).orthonormalized()
	if backhand: basis = Basis(-basis.x, basis.y, -basis.z)
	var head: Vector3 = candidate.point - normal * (BallScript.BALL_RADIUS + Paddle.HEAD_HALF_THICKNESS)
	var floor_y: float = BallScript.FLOOR_Y + Floor.head_clearance(basis)
	if head.y < floor_y:
		var in_face: Vector3 = Vector3.UP - normal * normal.y
		if in_face.y <= 0.00001: return false
		head += in_face * ((floor_y - head.y) / in_face.y)
	var tx := Transform3D(basis, head - basis * Paddle.HEAD_OFFSET)
	var mount: Transform3D = hands.main_mount(arm, tx * Paddle.MAIN_GRIP_OFFSET, tx.basis, {"main_grip_rotation_deg": preferred.y, "paddle_in_hand_rotation_deg": 0.0})
	var wrist: Vector3 = Hands.wrist_for(arm, mount)
	if not Contact.touches(tx, candidate.point, BallScript.BALL_RADIUS) or wrist.distance_to(shoulder) > arm.upper_arm_length + arm.forearm_length - 0.005:
		status = "rejected: finite paddle/actual wrist cannot reach contact"; return false
	var guide: Vector3 = actor.right_arm_node.upper_pivot.global_position + actor.body_pivot.get_node("TorsoMesh").global_basis.x * _team_sign()
	var pole: Vector3 = Anatomy.conditioned_pole(shoulder, wrist, guide, mount.basis * arm.articulated_hand.anatomical_basis.x, arm.upper_arm_length, arm.forearm_length)
	arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
	arm.solve_ik(wrist, pole, tx, wrist)
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, false), mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
	if not channels.within_animation_budget:
		var conditioned := ArmBudget.solve(shoulder, wrist, arm.forearm_pivot.global_position, mount.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, false)
		if not conditioned.feasible: return false
		pole = conditioned.elbow
		arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
		arm.solve_ik(wrist, pole, tx, wrist)
		channels = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, false), mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
		if not channels.within_animation_budget: return false
	var chest: Transform3D = actor.body_pivot.get_node("TorsoMesh").global_transform
	candidate.merge({"paddle": tx, "return_target": target, "contact_normal": normal,
		"shaft_roll": preferred.x, "grip_rotation": preferred.y, "wrist_channels": channels,
		"pole_in_chest": chest.affine_inverse() * pole, "wrist_in_chest": chest.affine_inverse() * wrist,
		"planned_response": response}, true)
	return true

func _follow_through_budget(selected: Dictionary) -> float:
	# A stricter 3 mm reserve plus local minimum refinement certifies the
	# follow-through scalar between the regular 120 Hz path samples too.
	var limit: float = actor.right_arm_node.upper_arm_length + actor.right_arm_node.forearm_length - 0.003
	var budget := 0.12
	var minimum_time := float(selected.time)
	for frame in range(ceili(Motion.DURATION / STEP) + 1):
		var time := float(frame) * STEP
		var value := _follow_limit_at(time, selected, limit)
		if value < budget: budget = value; minimum_time = time
	if budget < 0.12:
		var low := maxf(0.0, minimum_time - STEP)
		var high := minf(Motion.DURATION, minimum_time + STEP)
		for iteration in range(24):
			var left := low + (high - low) * 0.38196601125
			var right := low + (high - low) * 0.61803398875
			var lv := _follow_limit_at(left, selected, limit)
			var rv := _follow_limit_at(right, selected, limit)
			budget = minf(budget, minf(lv, rv))
			if lv < rv: high = right
			else: low = left
	return maxf(0.0, budget - 0.0001)

func _follow_limit_at(time: float, selected: Dictionary, limit: float) -> float:
	var when: float = selected.time
	var weight := _arm_path_weight(time, selected)
	var amount := smoothstep(when, when + 0.12, time) * weight
	# A zero follow-through coefficient has no length constraint on that
	# scalar. Keep every sampled time, but avoid writing an irrelevant rig.
	if amount <= 0.00001: return INF
	var motion := _motion(time, selected)
	actor.global_position = _origin + motion.root_offset; _apply_body(motion)
	var chest: Transform3D = actor.body_pivot.get_node("TorsoMesh").global_transform
	var base: Vector3 = _main_path_wrist(chest, selected, weight) - actor.right_arm_node.upper_pivot.global_position
	var normal: Vector3 = selected.contact_normal
	var projection := base.dot(normal)
	var discriminant := projection * projection + limit * limit - base.length_squared()
	if discriminant <= 0.0: return 0.0
	return maxf(0.0, -projection + sqrt(discriminant)) / amount

func _path_pole(wrist: Vector3, chest: Transform3D, weight: float, selected: Dictionary) -> Vector3:
	var shoulder: Vector3 = actor.right_arm_node.upper_pivot.global_position
	# Interpolate whole elbow-circle frames, then parallel-transport the
	# radial guide onto the actual wrist span. Projecting a point guide
	# through the shoulder/wrist axis can reverse its sign in one frame.
	var start_axis: Vector3 = (chest * _main_wrist - shoulder).normalized()
	var finish_axis: Vector3 = (chest * selected.wrist_in_chest - shoulder).normalized()
	var start_radial: Vector3 = chest * _base.main_elbow - shoulder
	var finish_radial: Vector3 = chest * selected.pole_in_chest - shoulder
	start_radial = (start_radial - start_axis * start_radial.dot(start_axis)).normalized()
	finish_radial = (finish_radial - finish_axis * finish_radial.dot(finish_axis)).normalized()
	var start_frame := Basis(start_axis, start_radial, start_axis.cross(start_radial)).orthonormalized()
	var finish_frame := Basis(finish_axis, finish_radial, finish_axis.cross(finish_radial)).orthonormalized()
	var blended := start_frame.slerp(finish_frame, weight)
	var transported: Vector3 = Quaternion(blended.x, (wrist - shoulder).normalized()) * blended.y
	return shoulder + transported

func _main_path_wrist(chest: Transform3D, selected: Dictionary, weight: float) -> Vector3:
	if bool(selected.get("rear_retrieval", false)): return chest * _main_wrist.lerp(selected.wrist_in_chest, weight)
	var shoulder: Vector3 = actor.right_arm_node.upper_pivot.global_position
	var start_span: Vector3 = chest * _main_wrist - shoulder
	var finish_span: Vector3 = chest * selected.wrist_in_chest - shoulder
	var radius_weight := 1.0 - pow(1.0 - weight, 2.0)
	return shoulder + start_span.normalized().slerp(finish_span.normalized(), weight) * lerpf(start_span.length(), finish_span.length(), radius_weight)

func _arm_path_weight(time: float, selected: Dictionary) -> float:
	var when: float = selected.time
	var rear: bool = bool(selected.get("rear_retrieval", false))
	var prepare := _steady_prepare_weight(time / maxf(0.32, when - 0.015), 0.15 if rear else 0.05)
	var recovery := _steady_prepare_weight((time - when - 0.12) / 0.43)
	return prepare * (1.0 - recovery)

func _steady_prepare_weight(progress: float, ramp: float = 0.05) -> float:
	# A cosine-eased velocity ramp spreads rotation across the available
	# load interval, without delaying the physical contact deadline.
	var u := clampf(progress, 0.0, 1.0)
	if u < ramp: return (u - ramp / PI * sin(PI * u / ramp)) * 0.5 / (1.0 - ramp)
	if u > 1.0 - ramp: return 1.0 - _steady_prepare_weight(1.0 - u, ramp)
	return (u - 0.5 * ramp) / (1.0 - ramp)

func _present(time: float, selected: Dictionary, probing: bool) -> bool:
	var stage_clock := Time.get_ticks_usec() if profile_certification and probing else 0
	var motion: Dictionary = _motion(time, selected)
	stage_clock = _profile_stage("sample_motion_usec", stage_clock)
	if probing: actor.global_position = _origin + motion.root_offset
	_apply_body(motion)
	stage_clock = _profile_stage("motion_body_usec", stage_clock)
	if not _apply_feet(motion, selected.direction, probing): status = "rejected: planted leg path"; return false
	stage_clock = _profile_stage("feet_usec", stage_clock)
	var chest: Transform3D = actor.body_pivot.get_node("TorsoMesh").global_transform
	var when: float = selected.time
	var weight: float = _arm_path_weight(time, selected)
	var arm = actor.right_arm_node
	var wrist: Vector3 = _main_path_wrist(chest, selected, weight)
	wrist += selected.contact_normal * float(selected.get("follow_through", 0.12)) * smoothstep(when, when + 0.12, time) * weight
	var desired_dip := float(selected.get("preparation_dip", 0.0)) * smoothstep(0.0, 0.31, time) * (1.0 - smoothstep(when - 0.10, when, time))
	if desired_dip > 0.0:
		# Entry grips differ. Keep the low approach within the original arm
		# sphere; the path certificate separately rejects insufficient ball
		# clearance or wrist-channel feasibility, rather than stretching it.
		var relative: Vector3 = wrist - arm.upper_pivot.global_position
		var radius: float = arm.upper_arm_length + arm.forearm_length - 0.002
		var discriminant := radius * radius - relative.x * relative.x - relative.z * relative.z
		var available_dip := maxf(0.0, relative.y + sqrt(maxf(0.0, discriminant))) if discriminant >= 0.0 else 0.0
		wrist += Vector3.DOWN * minf(desired_dip, available_dip)
	if wrist.distance_to(arm.upper_pivot.global_position) > arm.upper_arm_length + arm.forearm_length - 0.001:
		status = "rejected: intermediate reach exceeds actual arm length"; return false
	# look_at preserves its incoming scale; remove accumulated numerical scale
	# before solving fixed nominal links rather than widening geometry budgets.
	arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
	arm.solve_ik(wrist, _path_pole(wrist, chest, weight, selected), Transform3D.IDENTITY, wrist)
	var reference: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, false)
	var finish: Dictionary = selected.wrist_channels
	var channel_weight := weight if bool(selected.get("rear_retrieval", false)) else pow(weight, 0.75)
	var flex := lerpf(float(_main_channels.flexion_deg), float(finish.flexion_deg), channel_weight)
	var dev := lerpf(float(_main_channels.radial_deviation_deg), float(finish.radial_deviation_deg), channel_weight)
	var axial := lerpf(float(_main_channels.forearm_axial_deg), float(finish.forearm_axial_deg), channel_weight)
	var anatomical: Basis = reference * Basis(Vector3.RIGHT, deg_to_rad(axial)) * Basis(Vector3.UP, deg_to_rad(flex)) * Basis(Vector3.BACK, deg_to_rad(dev))
	var mount := Transform3D(anatomical * arm.articulated_hand.anatomical_basis.inverse(), Vector3.ZERO)
	mount.origin = wrist - mount.basis * arm.articulated_hand.wrist_socket
	var grip: Basis = _entry_grip_basis.slerp(Hands.GripFrame.basis(Basis.IDENTITY, false, float(selected.grip_rotation)), weight).orthonormalized()
	var paddle_basis: Basis = mount.basis * grip.inverse()
	var anchor: Vector3 = _grip_anchor.lerp(Paddle.MAIN_GRIP_OFFSET, weight)
	actor.paddle_node.global_transform = Transform3D(paddle_basis, mount.origin - paddle_basis * anchor)
	if not probing: _last_grip_basis = grip; _last_grip_anchor = anchor
	hands.apply_mount(arm, mount)
	stage_clock = _profile_stage("main_arm_usec", stage_clock)
	_apply_support(motion, selected, time)
	stage_clock = _profile_stage("support_arm_usec", stage_clock)
	for item in [[actor.right_arm_node, false], [actor.left_arm_node, true]]:
		var current = item[0]
		if current.upper_pivot.global_position.distance_to(current.anatomical_wrist_world) > current.upper_arm_length + current.forearm_length + 0.00001:
			status = "rejected: support arm path exceeds actual links"; return false
		var channels := _channels(current, item[1])
		if not channels.within_animation_budget:
			status = "rejected: intermediate wrist budget"
			diagnostics["failed_wrist"] = channels; diagnostics["failed_time"] = time; diagnostics["support"] = item[1]
			return false
	var paddle: Transform3D = actor.paddle_node.global_transform
	if (paddle * Paddle.HEAD_OFFSET).y - Floor.head_clearance(paddle.basis) < BallScript.FLOOR_Y - 0.001:
		status = "rejected: paddle path below floor"; return false
	_profile_stage("channel_floor_checks_usec", stage_clock)
	if not probing:
		latest_motion = motion
		latest_motion["support_phase"] = "release" if time < 0.38 else ("one_hand_reach" if time < 0.80 else "regrip")
	return true

func _profile_stage(key: String, started: int) -> int:
	if started == 0: return 0
	var now := Time.get_ticks_usec()
	timing[key] = int(timing.get(key, 0)) + now - started
	return now

func _team_sign() -> float:
	return 1.0 if int(plan.get("court_side", actor.get_court_side()) if active else actor.get_court_side()) == 0 else -1.0

func _apply_body(motion: Dictionary) -> void:
	# Exact immutable Motion.apply_body transforms, composed before publishing
	# them. Reassigning the base body then position then rotation recursively
	# dirtied every rig descendant three times per certification sample.
	var chest: Transform3D = _base.chest
	var waist: Vector3 = chest.origin - chest.basis * Vector3.UP * Motion.Dimensions.WAIST_TO_CHEST
	var chest_basis := Basis(Vector3.UP, float(motion.torso_yaw))
	if float(motion.get("height_weight", 0.0)) > 0.0:
		chest_basis *= Basis(Vector3.RIGHT, float(motion.get("torso_extension", 0.0)) * _team_sign())
	var turn := Transform3D(chest_basis, waist - chest_basis * waist)
	_torso_node.transform = turn * _base.torso
	if _hips_node.transform != _base.hips: _hips_node.transform = _base.hips
	_skin.update_frames(_base.pelvis, _base.abdomen, turn * chest)
	actor.right_arm_node.transform = turn * _base.right_arm
	actor.left_arm_node.transform = turn * _base.left_arm
	var rotation: Vector3 = _base_body_rotation + Vector3(motion.body_rotation) + Vector3.UP * float(motion.body_yaw)
	var basis := Basis.from_euler(rotation, actor.body_pivot.rotation_order) * Basis.from_scale(_base_body_scale)
	actor.body_pivot.transform = Transform3D(basis, Transform3D(_base.body).origin + Vector3(motion.body_offset))

func _apply_support(motion: Dictionary, selected: Dictionary = {}, time: float = -1.0) -> void:
	var arm = actor.left_arm_node
	var torso: Node3D = actor.body_pivot.get_node("TorsoMesh")
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var rest: Vector3 = torso.to_global(_base.support_wrist)
	var high: float = float(motion.get("height_weight", 0.0))
	var offset := Vector3(-0.38, -0.24, 0.06).lerp(Vector3(-0.48, -0.38, 0.06), high)
	offset.x *= _team_sign(); offset.z *= _team_sign()
	var opened: Vector3 = shoulder + torso.global_basis * offset
	var weight: float = motion.counterbalance_weight
	var release_end := 0.65 if bool(selected.get("rear_retrieval", false)) else 0.75
	if time <= release_end: weight = smoothstep(0.0, release_end, time)
	var wrist: Vector3 = rest.lerp(opened, weight)
	# Counterbalance follows an arc around the shoulder. A straight chord
	# can fold the wrist almost into its shoulder and spin the forearm.
	var start_span := rest - shoulder
	var end_span := opened - shoulder
	wrist = shoulder + start_span.normalized().slerp(end_span.normalized(), weight) * lerpf(start_span.length(), end_span.length(), weight)
	var pole_offset := Vector3.LEFT.lerp(Vector3(-1.0, -0.30, -0.30), high)
	pole_offset.x *= _team_sign(); pole_offset.z *= _team_sign()
	var pole: Vector3 = torso.to_global(_base.support_elbow).lerp(shoulder + torso.global_basis * pole_offset, weight)
	var start_axis: Vector3 = (rest - shoulder).normalized()
	var finish_axis: Vector3 = (opened - shoulder).normalized()
	var start_radial: Vector3 = torso.to_global(_base.support_elbow) - shoulder
	var finish_radial: Vector3 = torso.global_basis * pole_offset
	start_radial = (start_radial - start_axis * start_radial.dot(start_axis)).normalized()
	finish_radial = (finish_radial - finish_axis * finish_radial.dot(finish_axis)).normalized()
	var start_frame := Basis(start_axis, start_radial, start_axis.cross(start_radial)).orthonormalized()
	var finish_frame := Basis(finish_axis, finish_radial, finish_axis.cross(finish_radial)).orthonormalized()
	var blended := start_frame.slerp(finish_frame, weight)
	pole = shoulder + Quaternion(blended.x, (wrist - shoulder).normalized()) * blended.y
	arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
	var mount: Transform3D = hands._free_mount_for_pole(arm, wrist, pole)
	var rest_mount: Transform3D = torso.global_transform * _base.support_mount
	mount.basis = rest_mount.basis.slerp(mount.basis, float(motion.pole_weight)).orthonormalized()
	mount.origin = wrist - mount.basis * arm.articulated_hand.wrist_socket
	arm.solve_ik(mount.origin, pole, mount, wrist)
	# Use a convex wrist-channel path at every height; blending world-space
	# wrist bases only for intermediate heights can exceed the unchanged limits.
	var model = arm.articulated_hand
	var ready: Dictionary = _base.support_channels
	var settle := 1.0 - weight
	var reference: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, true)
	var axial := deg_to_rad(float(ready.forearm_axial_deg) * settle / model.radial_sign)
	var flex := deg_to_rad(float(ready.flexion_deg) * settle)
	var deviation := deg_to_rad(float(ready.radial_deviation_deg) * settle / model.radial_sign)
	var anatomical: Basis = reference * Basis(Vector3.RIGHT, axial) * Basis(Vector3.UP, flex) * Basis(Vector3.BACK, deviation)
	var safe: Basis = anatomical * model.anatomical_basis.inverse()
	mount.basis = safe.orthonormalized()
	mount.origin = wrist - mount.basis * model.wrist_socket
	hands.apply_mount(arm, mount)
	_apply_support_fingers(weight)

func _apply_support_fingers(weight: float) -> void:
	var model = actor.left_arm_node.articulated_hand
	# Interpolate actual captured digit rotations, so a two-hand grip cannot
	# jump to a relaxed preset before the support palm has released the handle.
	for bone in range(1, model.WRIST_BRIDGE_BONE):
		var target: Quaternion = model._data.poses.OPEN[bone]
		model.skeleton.set_bone_pose_rotation(bone, _support_finger_rotations[bone].slerp(target, weight))
		model.bone_pose_write_count += 1
	model.pose_update_count += 1
	if weight <= 0.000001:
		for key in _support_finger_fields: model.set(key, _support_finger_fields[key])
	else:
		model._mode = "RECOVERY"
		model._recovery_pose_key = Vector4(-1, -1, -1, -1)
		model._closure = float(_support_finger_fields._closure) * (1.0 - weight)
		model._index_closure = float(_support_finger_fields._index_closure) * (1.0 - weight)
		model._support_style_weight = float(_support_finger_fields._support_style_weight) * (1.0 - weight)

func _apply_feet(motion: Dictionary, direction: Vector3, probing: bool) -> bool:
	var lead_right: bool = direction.dot(actor._get_forehand_axis()) >= 0.0
	for side in [0, 1]:
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var lead: bool = (side == 0) == lead_right
		var lift: float = motion.lead_lift if lead else motion.trail_lift
		var ankle: Vector3 = _ankles[side] + direction * float(motion.lead_travel if lead else motion.trail_travel) + Vector3.UP * lift
		if not FootContact.reach_report(leg.thigh_pivot.global_position, ankle, leg.thigh_length, leg.shin_length).feasible: return false
		var yaw: float = _yaws[side] + (-0.44 if lead_right else 0.44) * float(motion.lead_yaw_weight if lead else motion.trail_yaw_weight)
		var forward: Vector3 = Basis(Vector3.UP, yaw) * Vector3.FORWARD
		leg.solve_ik(ankle, ankle + forward * 0.65 + Vector3.UP * 0.35, 0.0)
		leg.foot_pivot.global_basis = Basis(Vector3.UP, yaw - _yaws[side]) * _foot_bases[side]
		leg._keep_sole_above_floor()
		if not probing: _feet_planted[side] = lift <= 0.000001
	return true

func _sync_foot_state() -> void:
	var ik = actor.leg_ik
	for side in [0, 1]:
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var foot: Vector3 = leg.foot_pivot.global_position
		var was_locked: bool = ik.right_foot_locked if side == 0 else ik.left_foot_locked
		var old_anchor: Vector3 = ik.right_foot_lock_pos if side == 0 else ik.left_foot_lock_pos
		# A hitch can contain the entire takeoff/landing interval. The immutable
		# path advanced this foot in flight; record its new court contact even
		# when neither rendered endpoint happens to show the airborne phase.
		var new_contact := _feet_planted[side] and (not was_locked or old_anchor.distance_to(foot) > 0.00001)
		if side == 0:
			ik.right_foot_smooth = foot; ik.right_foot_locked = _feet_planted[side]
			ik.right_step_t = 1.0 if _feet_planted[side] else 0.5; ik._right_yaw = leg.foot_pivot.global_rotation.y
			if _feet_planted[side]: ik.right_foot_lock_pos = foot
			if new_contact: ik.right_contact_serial += 1
		else:
			ik.left_foot_smooth = foot; ik.left_foot_locked = _feet_planted[side]
			ik.left_step_t = 1.0 if _feet_planted[side] else 0.5; ik._left_yaw = leg.foot_pivot.global_rotation.y
			if _feet_planted[side]: ik.left_foot_lock_pos = foot
			if new_contact: ik.left_contact_serial += 1
		ik._knee_yaw[side] = leg.foot_pivot.global_rotation.y

func _preflight(candidate: Dictionary, prediction: Dictionary = {}) -> bool:
	if prediction.is_empty():
		var ball = actor._get_ball_ref()
		prediction = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, CONTACT_CLOSE + STEP)
	var previous_time := 0.0
	var previous_paddle := Transform3D.IDENTITY
	var previous_hands: Array = []
	var maximum_hand_speed := 0.0
	diagnostics = {"samples": 0, "arm_limits_unchanged": true, "provenance": "actual rig path at 120 Hz including exact contact"}
	for frame in range(ceili(Motion.DURATION / STEP) + 1):
		var time := minf(float(frame) * STEP, Motion.DURATION)
		if not _present(time, candidate, true):
			diagnostics["rejected_time"] = time
			return false
		var rotations: Array = [actor.right_arm_node.hand_mesh.global_basis.orthonormalized().get_rotation_quaternion(), actor.left_arm_node.hand_mesh.global_basis.orthonormalized().get_rotation_quaternion()]
		if not previous_hands.is_empty():
			for side in [0, 1]:
				var speed := rad_to_deg(previous_hands[side].angle_to(rotations[side])) / (time - previous_time)
				maximum_hand_speed = maxf(maximum_hand_speed, speed)
				if speed > MAX_HAND_RATE_DEG:
					status = "rejected: hand-frame angular path exceeds 720 degrees per second"
					diagnostics["angular_speed"] = speed; diagnostics["rejected_time"] = time; diagnostics["support"] = side == 1
					return false
		previous_hands = rotations
		diagnostics["max_hand_degrees_per_second"] = maximum_hand_speed
		if frame > 0 and previous_time < CONTACT_OPEN:
			var fraction := clampf((CONTACT_OPEN - previous_time) / maxf(time - previous_time, .000001), 0.0, 1.0)
			var early := Contact.first_sweep_fraction(_prediction_point(prediction, previous_time), _prediction_point(prediction, time), previous_paddle, actor.paddle_node.global_transform, BallScript.BALL_RADIUS, fraction)
			if early >= 0.0:
				status = "rejected: incoming ball intersects paddle during preparation"
				diagnostics["preparation_touch_time"] = lerpf(previous_time, time, early)
				return false
		previous_time = time; previous_paddle = actor.paddle_node.global_transform
		diagnostics.samples += 1
	if not _present(float(candidate.time), candidate, true): return false
	if not Contact.touches(actor.paddle_node.global_transform, candidate.point, BallScript.BALL_RADIUS):
		status = "rejected: joint-space path misses finite head at predicted contact"; return false
	return true

func _prediction_point(prediction: Dictionary, time: float) -> Vector3:
	var samples: Array = prediction.get("samples", [])
	if samples.is_empty(): return Vector3.INF
	var previous: Dictionary = samples[0]
	for sample: Dictionary in samples:
		if float(sample.time) >= time:
			var fraction := clampf((time - float(previous.time)) / maxf(float(sample.time) - float(previous.time), .000001), 0.0, 1.0)
			return Vector3(previous.pos).lerp(sample.pos, fraction)
		previous = sample
	return Vector3.INF

func _channels(arm, left: bool) -> Dictionary:
	return Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, arm.anatomical_wrist_world, left), arm.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, arm.articulated_hand.radial_sign)

func displayed_report(ball_point: Vector3 = Vector3.INF, radius: float = BallScript.BALL_RADIUS) -> Dictionary:
	var result := {"valid": true, "main_hand_seated": false, "finite_touch": false, "arms": [], "feet": [], "grounded": false}
	var paddle: Transform3D = actor.paddle_node.global_transform
	var main = actor.right_arm_node
	var mount: Transform3D = main.hand_mesh.global_transform
	var position_error: float = mount.origin.distance_to(paddle * _last_grip_anchor)
	var expected: Basis = paddle.basis * _last_grip_basis
	var rotation_error: float = maxf((mount.basis.x - expected.x).length(), maxf((mount.basis.y - expected.y).length(), (mount.basis.z - expected.z).length()))
	result.main_hand_seated = position_error <= 0.00002 and rotation_error <= 0.00002
	result["grip_position_error"] = position_error; result["grip_basis_error"] = rotation_error
	result.valid = result.main_hand_seated
	for side in [0, 1]:
		var arm = actor.right_arm_node if side == 0 else actor.left_arm_node
		var wrist: Vector3 = Hands.wrist_for(arm, arm.hand_mesh.global_transform)
		var upper_error: float = absf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position) - arm.upper_arm_length)
		var fore_error: float = absf(arm.forearm_pivot.global_position.distance_to(wrist) - arm.forearm_length)
		var socket_error: float = wrist.distance_to(arm.anatomical_wrist_world)
		var channels := _channels(arm, side == 1)
		var valid: bool = upper_error <= 0.00002 and fore_error <= 0.00002 and socket_error <= 0.00002 and channels.within_animation_budget
		result.arms.append({"valid": valid, "channels": channels, "upper_link_error": upper_error, "fore_link_error": fore_error, "wrist_socket_error": socket_error, "link_budget": arm.upper_arm_length + arm.forearm_length})
		result.valid = result.valid and valid
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var foot: Vector3 = leg.foot_pivot.global_position
		var leg_upper: float = absf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position) - leg.thigh_length)
		var leg_lower: float = absf(leg.shin_pivot.global_position.distance_to(foot) - leg.shin_length)
		var bounds: AABB = leg.foot_mesh.mesh.get_aabb()
		var sole := INF
		for corner in range(8): sole = minf(sole, (leg.foot_mesh.global_transform * bounds.get_endpoint(corner)).y)
		var supported: bool = bool(leg.reach_report.get("feasible", false)) and leg_upper <= 0.00002 and leg_lower <= 0.00002 and sole >= BallScript.FLOOR_Y - 0.00002
		result.feet.append({"valid": supported, "planted": _feet_planted[side], "sole_y": sole, "ankle": foot, "upper_link_error": leg_upper, "lower_link_error": leg_lower})
		result.valid = result.valid and supported
		result.grounded = result.grounded or _feet_planted[side] and absf(sole - BallScript.FLOOR_Y) <= 0.002
	result.valid = result.valid and result.grounded
	if ball_point.is_finite(): result.finite_touch = Contact.touches(paddle, ball_point, radius)
	result["paddle"] = paddle; result["phase"] = latest_motion.get("phase", "entry")
	return result

func _flight_snapshot() -> Dictionary:
	var ball = actor._get_ball_ref()
	return {"flight_id": ball.flight_id, "position": ball.global_position, "velocity": ball.linear_velocity, "omega": ball.angular_velocity, "bounces": ball.bounces_since_last_hit, "last_hit_by": ball.last_hit_by, "last_hit_identity": Identity.ball_identity(ball), "in_play": ball.is_in_play}

func _entry_signature() -> PackedByteArray:
	var values: Array = [Identity.describe(actor), actor.get_instance_id(), actor.global_transform, actor.current_velocity, actor.body_pivot.transform,
		actor.body_pivot.get_node("TorsoMesh").transform, actor.paddle_node.global_transform]
	var skin = actor.body_pivot.get_meta("articulated_torso")
	values.append_array([skin._last_pelvis, skin._last_abdomen, skin._last_chest])
	for arm in [actor.right_arm_node, actor.left_arm_node]:
		var model = arm.articulated_hand
		values.append_array([arm.transform, arm.upper_pivot.global_transform, arm.forearm_pivot.global_transform,
			arm.hand_mesh.global_transform, arm.anatomical_wrist_world, arm.upper_arm_length, arm.forearm_length,
			model._mode, model._closure, model._index_closure, model._support_style_weight, model._recovery_pose_key,
			arm.has_meta("live_support_frame"), arm.get_meta("live_support_frame", {})])
		for bone in range(1, model.WRIST_BRIDGE_BONE): values.append(model.skeleton.get_bone_pose_rotation(bone))
	for leg in [actor.right_leg_node, actor.left_leg_node]: values.append_array([leg.transform, leg.foot_pivot.global_transform, leg.foot_mesh.transform, leg.thigh_length, leg.shin_length])
	var ik = actor.leg_ik
	values.append_array([ik.right_foot_locked, ik.left_foot_locked, ik._active_side, ik._run_active, ik._airborne])
	return var_to_bytes(values)

func _snapshot() -> Dictionary:
	var nodes: Array = [{"node": actor, "transform": actor.transform}]
	var bones: Array = []
	for node in actor.find_children("*", "Node3D", true, false):
		nodes.append({"node": node, "transform": node.transform})
		if node is Skeleton3D:
			var channels: Array = []
			var poses: Array[Transform3D] = []
			for index in node.get_bone_count(): poses.append(node.get_bone_pose(index))
			for index in node.get_bone_count(): channels.append([node.get_bone_pose_position(index), node.get_bone_pose_rotation(index), node.get_bone_pose_scale(index)])
			bones.append({"node": node, "poses": poses, "channels": channels})
	var arms: Array = []
	for arm in [actor.right_arm_node, actor.left_arm_node]:
		var model = arm.articulated_hand
		var fields: Dictionary = {}
		for key in ["_mode", "_closure", "_index_closure", "_support_style_weight", "_recovery_pose_key", "_last_wrist_axis", "pose_update_count", "bone_pose_write_count", "wrist_bridge_update_count"]: fields[key] = model.get(key)
		arms.append({"arm": arm, "wrist": arm.anatomical_wrist_world, "stretch": arm.visual_stretch, "lag": arm.visual_wrist_lag_deg, "fields": fields,
			"had_support_frame": arm.has_meta("live_support_frame"), "support_frame": arm.get_meta("live_support_frame", {}).duplicate(true)})
	var bridges: Array = []
	for pair in [[actor.right_arm_node, "arm_elbow_bridge"], [actor.left_arm_node, "arm_elbow_bridge"], [actor.right_leg_node, "leg_knee_bridge"], [actor.left_leg_node, "leg_knee_bridge"]]:
		if not pair[0].has_meta(pair[1]): continue
		var bridge = pair[0].get_meta(pair[1])
		var fields: Dictionary = {}
		for key in ["last_relative", "initialized", "bone_pose_write_count", "pose_version", "sampled_version", "sampled_vertices", "_triangles", "_points", "palette"]:
			var value: Variant = bridge.get(key)
			fields[key] = value.duplicate() if value is Array else value
		bridges.append({"bridge": bridge, "fields": fields})
	var skin = actor.body_pivot.get_meta("articulated_torso")
	return {"bridges": bridges, "nodes": nodes, "bones": bones, "arms": arms, "skin": skin, "pelvis": skin._last_pelvis,
		"abdomen": skin._last_abdomen, "chest": skin._last_chest, "skin_writes": skin.bone_pose_write_count,
		"right_report": actor.right_leg_node.reach_report.duplicate(true), "left_report": actor.left_leg_node.reach_report.duplicate(true)}

func _restore(saved: Dictionary) -> void:
	for item in saved.nodes: item.node.transform = item.transform
	for item in saved.bones:
		if not item.has("channels"):
			for index in item.poses.size(): item.node.set_bone_pose(index, item.poses[index])
			continue
		for index in item.channels.size():
			item.node.set_bone_pose_position(index, item.channels[index][0])
			item.node.set_bone_pose_rotation(index, item.channels[index][1])
			item.node.set_bone_pose_scale(index, item.channels[index][2])
	for item in saved.bridges:
		for key in item.fields:
			var value: Variant = item.fields[key]
			item.bridge.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	for item in saved.arms:
		item.arm.anatomical_wrist_world = item.wrist; item.arm.visual_stretch = item.stretch; item.arm.visual_wrist_lag_deg = item.lag
		for key in item.fields: item.arm.articulated_hand.set(key, item.fields[key])
		if item.had_support_frame: item.arm.set_meta("live_support_frame", item.support_frame.duplicate(true))
		elif item.arm.has_meta("live_support_frame"): item.arm.remove_meta("live_support_frame")
	saved.skin._last_pelvis = saved.pelvis; saved.skin._last_abdomen = saved.abdomen; saved.skin._last_chest = saved.chest; saved.skin.bone_pose_write_count = saved.skin_writes
	actor.right_leg_node.reach_report = saved.right_report.duplicate(true); actor.left_leg_node.reach_report = saved.left_report.duplicate(true)
