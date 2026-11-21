extends RefCounted
## Match adapter for the immutable, emergency airborne save. This owns only a
## physically admitted presentation. The caller owns movement collisions, ball
## flight, finite contact, scoring and outgoing-shot authority.
const Motion = preload("res://scripts/emergency_dive_motion.gd")
const ProfileCatalog = preload("res://scripts/emergency_dive_profile_catalog.gd")
const ReadyClearance = preload("res://scripts/live_ready_clearance.gd")
const Grounded = preload("res://scripts/match_grounded_reach.gd")
const RigSurfaces = preload("res://scripts/player_surface_contacts.gd")
const BodyProfile = preload("res://scripts/body_surface_profile.gd")
const BodyDimensions = preload("res://scripts/player_body_dimensions.gd")
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
const CONTACT_OPEN := 0.49
const CONTACT_CLOSE := 0.59
const ROOT_TOLERANCE := 0.035
const MAX_CANDIDATE_PROBES := 4
const COOLDOWN := 3.20
var actor
var hands = Hands.new()
var shot = Shot.new()
var active := false
var cooldown := 0.0
var cancelled := false
var _blocked_root := Vector3.INF
var _entry_pelvis := Vector3.ZERO
var _current_pelvis := Vector3.ZERO
var _floor_support := false
var _foot_air: Array[Vector3] = []
var _arm_geometry: Dictionary = {}
var _exact_geometry: Dictionary = {}
var _exact_geometry_key := PackedByteArray()
var _local_geometry_key := PackedByteArray()
var _core_vertices := PackedVector3Array()
var _head_vertices := PackedVector3Array()
var _body_inverse := Transform3D.IDENTITY
var _mesh_floor_cache: Dictionary = {}
var _skin_bound_cache: Dictionary = {}
var bound_acceleration := true
var _rig_meshes: Array[MeshInstance3D] = []
var _support_ok := true
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
var _entry: Dictionary = {}
var _ankles: Array[Vector3] = []
var _yaws: Array[float] = []
var _foot_bases: Array[Basis] = []
var _feet_planted: Array[bool] = [true, true]
var _main_wrist := Vector3.ZERO
var _entry_paddle := Transform3D.IDENTITY
var _entry_main_mount := Transform3D.IDENTITY
var _main_channels: Dictionary = {}
var _main_chart_angle := 0.0
var _grip_anchor := Vector3.ZERO
var _grip_rotation := 0.0
var _certified_payload := PackedByteArray()
var _certified_entry := PackedByteArray()
var _last_grip_basis := Basis.IDENTITY
var _last_grip_anchor := Vector3.ZERO
var timing: Dictionary = {}
var _entry_grip_basis := Basis.IDENTITY
var use_catalog := true
var verify_catalog_path := false
var clearance_margin := 0.0
var polish_profile_angles := false
var _presentation_time := 0.0
var _path_curve: Array = []
var _path_curve_step := STEP
var _pose_angles: Array[float] = [0.0, 0.0]
var profile_enabled := false
var profile_usec: Dictionary = {}

func _profile_mark(stage: String, started: int) -> void:
	if profile_enabled: profile_usec[stage] = int(profile_usec.get(stage, 0)) + Time.get_ticks_usec() - started

func _init(owner) -> void:
	actor = owner
	hands.initialize(actor)
	var game = actor.get_parent()
	shot.setup(game.ball, game.player_left, game.player_right)

func _eligible(state: Dictionary) -> bool:
	# Planning can precede the real first bounce, but contact cannot. A legal
	# forecasted groundstroke is not permission to volley or bypass foot history.
	if not bool(state.get("playing", false)) or bool(state.get("paused", false)) or not bool(state.get("in_play", false)): return false
	if actor.posture.editor_preview_mode or (actor.is_jumping and not active) or int(state.get("player_num", -1)) != actor.player_num: return false
	var ball = actor._get_ball_ref()
	return ball != null and ball.is_in_play and ball.last_hit_by >= 0 and ball.last_hit_by != actor.player_num and ball.bounces_since_last_hit < 2 and ball.flight_id == int(state.get("flight_id", -1))

func _supported_entry() -> bool:
	var ik = actor.leg_ik
	return ik != null and ik.feet_initialized and ik.right_foot_locked and ik.left_foot_locked and ik._active_side < 0 and not ik._run_active and not ik._airborne and Vector2(actor.current_velocity.x, actor.current_velocity.z).length() <= 0.18

func choose_plan(prediction: Dictionary, state: Dictionary, intent: Dictionary) -> Dictionary:
	if use_catalog: return _choose_catalog(prediction, state, intent)
	return choose_plan_exact(prediction, state, intent)

func entry_match_report() -> Dictionary:
	var data := ProfileCatalog.load_profiles()
	if data.is_empty(): return {"matches": false, "reason": "missing_or_stale_catalog"}
	var actual := ProfileCatalog.entry_state(actor)
	var reports: Array = []
	for profile: Dictionary in data.profiles:
		if int(profile.entry.player_num) != actor.player_num: continue
		var report := ProfileCatalog.entry_match_report(actor, profile.entry, actual)
		reports.append({"profile": profile.id, "entry": report})
		if report.matches: return {"matches": true, "profile": profile.id}
	return {"matches": false, "reason": "actual_preparation_differs", "reports": reports}

func _profile_paddle(samples: Array, time: float) -> Transform3D:
	var low := 0; var high := samples.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if float(samples[middle].time) <= time: low = middle
		else: high = middle
	var before: Dictionary = samples[low]; var after: Dictionary = samples[high]
	var fraction := clampf((time - float(before.time)) / maxf(0.000001, float(after.time) - float(before.time)), 0.0, 1.0)
	var first: Transform3D = before.paddle; var last: Transform3D = after.paddle
	return Transform3D(first.basis.slerp(last.basis, fraction).orthonormalized(), first.origin.lerp(last.origin, fraction) + actor.global_position)

func _choose_catalog(prediction: Dictionary, state: Dictionary, intent: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	_certified_payload = PackedByteArray(); _certified_entry = PackedByteArray()
	status = "rejected: explicit dive and supported entry required"
	if active or cooldown > 0.0 or not _eligible(state) or not _supported_entry(): return {}
	if not bool(intent.get("emergency_dive", false)) or not intent.get("target", Vector3.INF).is_finite(): return {}
	var data := ProfileCatalog.load_profiles()
	if data.is_empty(): status = "rejected: missing or stale certified dive catalog"; return {}
	var actual := ProfileCatalog.entry_state(actor)
	var possible: Array = []
	var fault_time := Planner.predicted_fault_time(actor, actor._get_ball_ref(), prediction)
	for profile: Dictionary in data.profiles:
		if int(profile.entry.player_num) != actor.player_num: continue
		if not ProfileCatalog.entry_match_report(actor, profile.entry, actual).matches: continue
		var certificate: Dictionary = profile.certificate
		if int(certificate.get("samples", 0)) < 5377 or float(certificate.get("sleeve_gap_m", 0.0)) < 0.00025: continue
		var endpoint: Vector3 = actor.global_position + Vector3(profile.plan.direction) * Motion.MAX_TRAVEL
		if endpoint.x < actor.min_x or endpoint.x > actor.max_x or endpoint.z < actor.min_z or endpoint.z > actor.max_z: continue
		if minf(absf(actor.global_position.z), absf(endpoint.z)) < 2.0: continue
		for sample: Dictionary in prediction.get("samples", []):
			var time := float(sample.get("time", 0.0))
			if time < CONTACT_OPEN or time > CONTACT_CLOSE or time >= fault_time: continue
			if actor._get_ball_ref().bounces_since_last_hit + int(sample.get("bounces", 0)) != 1: continue
			var point: Vector3 = sample.get("pos", Vector3.INF)
			if not point.is_finite() or not Contact.touches(_profile_paddle(profile.paddles, time), point, BallScript.BALL_RADIUS): continue
			possible.append({"profile": profile, "sample": sample})
			break
	if possible.is_empty(): status = "rejected: no genuine matching certified opportunity"; return {}
	var grounded := Grounded.new(actor)
	var grounded_started := Time.get_ticks_usec()
	var preference_entry := _snapshot(true)
	var grounded_plan := grounded.choose_plan(prediction, state, intent)
	_restore(preference_entry)
	if not grounded_plan.is_empty(): status = "rejected: grounded reach is sufficient"; return {}
	timing["grounded_preference_usec"] = Time.get_ticks_usec() - grounded_started
	var saved := _snapshot(true); _capture_entry()
	var result := {}
	for opportunity: Dictionary in possible:
		var profile: Dictionary = opportunity.profile; var sample: Dictionary = opportunity.sample
		var candidate: Dictionary = profile.plan.duplicate(true)
		candidate.point += _origin; candidate.paddle.origin += _origin
		candidate.merge({"kind": "DIVE", "intent": intent.duplicate(true), "entry_root": _origin, "flight_id": int(state.flight_id), "player_num": actor.player_num,
			"ball_snapshot": _flight_snapshot(), "catalog_id": profile.id, "catalog_code": data.code, "forecast_point": sample.pos,
			"forecast_time": sample.time, "provenance": "unchanged finite certified profile; genuine matching entry; real forecast; no awarded contact"}, true)
		if not _present(float(sample.time), candidate, true): continue
		if not Contact.touches(actor.paddle_node.global_transform, sample.pos, BallScript.BALL_RADIUS): continue
		var response: Dictionary = shot.solve_aimed_launch(sample.pos, intent.target, clampf(float(intent.get("charge", 0.25)), 0.0, 1.0), actor.player_num,
			int(intent.get("spin_mode", 0)), str(intent.get("aim_mode", "AUTO")), str(intent.get("shot_intent", "GROUNDSTROKE")))
		if not response.get("feasible", false): continue
		var impulse: Vector3 = response.velocity - Vector3(sample.get("vel", Vector3.ZERO))
		if impulse.length_squared() < 0.00001 or impulse.normalized().dot(candidate.contact_normal) < cos(deg_to_rad(3.0)): continue
		result = candidate; break
	_restore(saved)
	if not result.is_empty():
		_certified_payload = var_to_bytes(result); _certified_entry = _entry_signature()
		status = "admitted unchanged certified dive opportunity"
	else: status = "rejected: actual contact or requested return differs from certified face"
	timing["admission_usec"] = Time.get_ticks_usec() - started
	return result

func choose_plan_exact(prediction: Dictionary, state: Dictionary, intent: Dictionary) -> Dictionary:
	_certified_payload = PackedByteArray(); _certified_entry = PackedByteArray()
	status = "rejected: explicit emergency dive and supported entry required"
	if active or cooldown > 0.0 or not _eligible(state) or not _supported_entry(): return {}
	if not bool(intent.get("emergency_dive", false)) or not intent.get("target", Vector3.INF).is_finite(): return {}
	# An explicit dive does not replace a feasible supported save.
	var grounded = Grounded.new(actor)
	if not grounded.choose_plan(prediction, state, intent).is_empty():
		status = "rejected: grounded reach is sufficient"; return {}
	var captured := _snapshot()
	_capture_entry()
	var result: Dictionary = {}
	var probed := 0
	var fault_time: float = Planner.predicted_fault_time(actor, actor._get_ball_ref(), prediction)
	var samples: Array = prediction.get("samples", []).duplicate()
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a.time) - Motion.CONTACT_TIME) < absf(float(b.time) - Motion.CONTACT_TIME))
	for sample: Dictionary in samples:
		var when: float = float(sample.get("time", 0.0))
		if when < CONTACT_OPEN: continue
		if when > CONTACT_CLOSE: continue
		if when >= fault_time or actor._get_ball_ref().bounces_since_last_hit + int(sample.get("bounces", 0)) != 1: continue
		var point: Vector3 = sample.get("pos", Vector3.INF)
		if not point.is_finite() or point.y < 0.28 or point.y > 0.85: continue
		var toward := Vector3(point.x - _origin.x, 0.0, point.z - _origin.z)
		if toward.length() < 1.50 or toward.length() > 2.20: continue
		if toward.normalized().dot(actor._get_forward_axis()) < -0.15: continue
		var direction := toward.normalized()
		var endpoint := _origin + direction * Motion.MAX_TRAVEL
		if endpoint.x < actor.min_x or endpoint.x > actor.max_x or endpoint.z < actor.min_z or endpoint.z > actor.max_z: continue
		if minf(absf(_origin.z), absf(endpoint.z)) < 1.35: continue
		var proposed := {"kind": "DIVE", "flight_id": int(state.flight_id), "time": when, "point": point,
			"direction": direction, "travel": Motion.MAX_TRAVEL, "incoming_velocity": sample.get("vel", Vector3.ZERO),
			"backhand": direction.dot(actor._get_forehand_axis()) < 0.0, "intent": intent.duplicate(true),
			"player_num": actor.player_num, "groundstroke_bounces": 1, "forecast_bounces": int(sample.get("bounces", 0))}
		probed += 1
		if probed > MAX_CANDIDATE_PROBES: break
		if not _fit_contact(proposed) or not _preflight(proposed): continue
		result = proposed
		result["entry_root"] = _origin; result["ball_snapshot"] = _flight_snapshot()
		result["provenance"] = "actual ballistic airborne rig; supported load; finite paddle; unchanged joint limits; complete landing and get-up preflight"
		status = "admitted emergency dive opportunity"; break
	_restore(captured)
	if not result.is_empty():
		_certified_payload = var_to_bytes(result); _certified_entry = _entry_signature()
	timing["candidate_probes"] = mini(probed, MAX_CANDIDATE_PROBES)
	return result

func begin(candidate: Dictionary, state: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	if active or cooldown > 0.0 or not _valid_candidate(candidate) or not _eligible(state) or not _supported_entry(): status = "rejected: entry no longer supported"; return false
	if int(candidate.get("flight_id", -2)) != int(state.get("flight_id", -1)) or int(candidate.get("player_num", -1)) != actor.player_num:
		status = "rejected: stale flight or different actor"; return false
	if not candidate.get("entry_root", Vector3.INF).is_finite() or actor.global_position.distance_to(candidate.entry_root) > ROOT_TOLERANCE:
		status = "rejected: entry root changed"; return false
	if candidate.get("ball_snapshot", {}) != _flight_snapshot(): status = "rejected: stale incoming prediction"; return false
	var checked := candidate.duplicate(true)
	var cached := not _certified_payload.is_empty() and var_to_bytes(candidate) == _certified_payload and _entry_signature() == _certified_entry
	if not cached and candidate.has("catalog_id"):
		status = "rejected: certified profile or actual entry changed"; return false
	if not cached:
		var captured := _snapshot()
		_capture_entry()
		var accepted := _fit_contact(checked) and _preflight(checked)
		_restore(captured)
		if not accepted: return false
	timing["begin_usec"] = Time.get_ticks_usec() - started
	timing["begin_reused_certificate"] = cached
	plan = checked; flight_id = int(state.flight_id); active = true; elapsed = 0.0; contacted = false
	cancelled = false; cooldown = COOLDOWN; _blocked_root = Vector3.INF
	latest_motion = _motion(0.0); handoff.clear(); status = "emergency dive active"
	return true

func advance(delta: float, state: Dictionary) -> Dictionary:
	if not is_finite(delta) or delta < 0.0: return {"active": active, "root_delta": Vector3.ZERO, "contact_window": false}
	if bool(state.get("paused", false)): return {"active": active, "root_delta": Vector3.ZERO, "contact_window": false}
	cooldown = maxf(0.0, cooldown - delta)
	if not active: return {"active": false, "root_delta": Vector3.ZERO, "contact_window": false}
	if not bool(state.get("playing", false)) or (not contacted and (not _eligible(state) or int(state.get("flight_id", -1)) != flight_id)):
		cancel("incoming ownership changed; finish physical recovery")
		if not active: return {"active": false, "root_delta": Vector3.ZERO, "contact_window": false}
	elapsed = minf(Motion.DURATION, elapsed + delta)
	latest_motion = _motion(elapsed)
	var target: Vector3 = _origin + latest_motion.root_offset if not _blocked_root.is_finite() else _blocked_root
	return {"active": true, "root_target": target, "root_delta": target - actor.global_position,
		"elapsed": elapsed, "phase": latest_motion.phase, "contact_window": contact_window(), "finished": elapsed >= Motion.DURATION,
		"airborne": latest_motion.airborne, "root_velocity": latest_motion.root_velocity if not _blocked_root.is_finite() else Vector3.ZERO,
		"root_acceleration": latest_motion.root_acceleration, "ground_projected_root": true}

func contact_window() -> bool:
	var ball = actor._get_ball_ref()
	return active and not cancelled and not contacted and elapsed >= CONTACT_OPEN and elapsed <= CONTACT_CLOSE and ball != null and ball.is_in_play and ball.flight_id == flight_id and ball.last_hit_by != actor.player_num and ball.bounces_since_last_hit == 1

func mark_contact() -> void:
	# Called only AFTER the owner's actual finite contact and authority checks.
	if active: contacted = true

func apply() -> bool:
	if not active: return false
	var target: Vector3 = _origin + _motion(elapsed).root_offset
	if _blocked_root.is_finite(): target = _blocked_root
	if actor.global_position.distance_to(target) > ROOT_TOLERANCE:
		cancelled = true; status = "movement blocked; finish landing at actual root"
		_blocked_root = actor.global_position
	var before := _snapshot(true)
	if not _present(elapsed, plan, false):
		_restore(before)
		status = "actual rig path invalid; presentation rolled back"
		cancelled = true
		return false
	_sync_foot_state()
	if elapsed >= Motion.DURATION:
		status = "emergency dive recovered" if contacted else "missed emergency dive recovered"
		_finish_handoff()
	return true

func cancel(reason: String = "cancelled") -> void:
	status = reason; cancelled = true
	# Once push-off has begun, a miss, rally fault or released input cannot
	# erase momentum. The owner must keep advancing through physical get-up.
	if active and elapsed <= 0.000001: _finish_handoff()

func reset() -> void:
	# Only explicit match/reset lifecycle may remove an in-progress dive.
	if active:
		_present(Motion.DURATION, plan, false); _sync_foot_state(); _finish_handoff()
	active = false; elapsed = 0.0; cooldown = 0.0; cancelled = false; contacted = false
	plan.clear(); latest_motion.clear(); _blocked_root = Vector3.INF; status = "idle"

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
	_head_vertices.clear()
	_rig_meshes = RigSurfaces.meshes(actor)
	var head_mesh: Mesh = actor.body_pivot.get_node("TorsoMesh/HeadMesh").mesh
	for surface in range(head_mesh.get_surface_count()): _head_vertices.append_array(head_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	var torso: Node3D = actor.body_pivot.get_node("TorsoMesh")
	var arm = actor.right_arm_node
	_entry_paddle = actor.paddle_node.global_transform
	_entry_main_mount = arm.hand_mesh.global_transform
	_main_wrist = torso.to_local(arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length)))
	_base.support_wrist = torso.to_local(actor.left_arm_node.forearm_pivot.to_global(Vector3(0, 0, -actor.left_arm_node.forearm_length)))
	_base.support_channels = _channels(actor.left_arm_node, true)
	_main_channels = _channels(arm, false)
	_main_chart_angle = _chart_angle(arm.upper_pivot.global_position, arm.forearm_pivot.global_position, torso.to_global(_main_wrist), torso.global_transform)
	_grip_anchor = actor.paddle_node.to_local(arm.hand_mesh.global_position)
	_entry_grip_basis = actor.paddle_node.global_basis.inverse() * arm.hand_mesh.global_basis
	var pose = actor.get_runtime_posture_def()
	_grip_rotation = float(pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
	_ankles.clear(); _yaws.clear(); _foot_bases.clear()
	for leg in [actor.right_leg_node, actor.left_leg_node]:
		_ankles.append(leg.foot_pivot.global_position); _yaws.append(leg.foot_pivot.global_rotation.y); _foot_bases.append(leg.foot_pivot.global_basis)
	_feet_planted = [true, true]
	_entry_pelvis = actor.body_pivot.to_global(_base.pelvis.origin)
	_foot_air.clear()
	for side in [0, 1]: _foot_air.append(_ankles[side] - _entry_pelvis)

func _motion(time: float, selected: Dictionary = plan) -> Dictionary:
	var result := Motion.sample(time, selected.get("direction", Vector3.RIGHT), float(selected.get("travel", Motion.MAX_TRAVEL)), bool(selected.get("backhand", false)), float(selected.get("point", Vector3.ZERO).y))
	# Catalog times describe actual rendered support, not the ground-projected
	# root. Presentation below still checks the realized floor geometry.
	if selected.has("air_start") and selected.has("landed_at"):
		result.airborne = time >= float(selected.air_start) and time < float(selected.landed_at)
		if time >= Motion.TAKEOFF and time < float(selected.air_start): result.phase = &"push_off"
		elif time >= float(selected.landed_at) and time < Motion.SLIDE_END: result.phase = &"floor_landing_slide"
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
	var response: Dictionary = shot.solve_aimed_launch(candidate.point, target, clampf(float(intent.get("charge", 0.25)), 0.0, 1.0), actor.player_num, int(intent.get("spin_mode", 0)), str(intent.get("aim_mode", "AUTO")), str(intent.get("shot_intent", "GROUNDSTROKE")))
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
	_solve_arm_ik(arm, wrist, pole, tx, wrist)
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, false), mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
	if not channels.within_animation_budget:
		var conditioned := ArmBudget.solve(shoulder, wrist, arm.forearm_pivot.global_position, mount.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, false)
		if not conditioned.feasible: return false
		pole = conditioned.elbow
		_solve_arm_ik(arm, wrist, pole, tx, wrist)
		channels = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, false), mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
		if not channels.within_animation_budget: return false
	var safe_pole: Vector3 = _safe_elbow(arm, wrist, pole, mount)
	if not safe_pole.is_finite(): return false
	pole = safe_pole
	_solve_arm_ik(arm, wrist, pole, tx, wrist)
	channels = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, false), mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
	var chest: Transform3D = actor.body_pivot.get_node("TorsoMesh").global_transform
	candidate.merge({"paddle": tx, "return_target": target, "contact_normal": normal,
		"shaft_roll": preferred.x, "grip_rotation": preferred.y, "wrist_channels": channels,
		"pole_in_chest": chest.affine_inverse() * pole, "pole_chart_angle": _chart_angle(shoulder, pole, wrist, chest), "wrist_in_chest": chest.affine_inverse() * wrist,
		"planned_response": response}, true)
	return true

func _follow_through_budget(_selected: Dictionary) -> float:
	# The emergency save absorbs the ball with a compact fixed wrist finish.
	return 0.0

func _chart_angle(shoulder: Vector3, elbow: Vector3, wrist: Vector3, chest: Transform3D) -> float:
	var axis := (wrist - shoulder).normalized()
	var reference := chest.basis.y; reference -= axis * reference.dot(axis)
	var radial := elbow - shoulder; radial -= axis * radial.dot(axis)
	return reference.normalized().signed_angle_to(radial.normalized(), axis)

func _path_pole(wrist: Vector3, chest: Transform3D, weight: float, selected: Dictionary) -> Vector3:
	# Interpolate an elbow-circle chart, not two almost axial 3D guides. A
	# projected guide can cross its singular axis and silently swivel 180deg.
	var shoulder: Vector3 = actor.right_arm_node.upper_pivot.global_position
	var axis := (wrist - shoulder).normalized()
	var reference := chest.basis.y; reference -= axis * reference.dot(axis)
	if reference.length() < 0.20: return Vector3.INF
	var angle := lerp_angle(_main_chart_angle, float(selected.pole_chart_angle), weight)
	return shoulder + reference.normalized().rotated(axis, angle)

func _present(time: float, selected: Dictionary, probing: bool) -> bool:
	_presentation_time = time
	_path_curve = selected.get("catalog_curve", [])
	_path_curve_step = float(selected.get("catalog_curve_step", STEP))
	var motion: Dictionary = _motion(time, selected)
	if probing: actor.global_position = _origin + motion.root_offset
	var profile_started := Time.get_ticks_usec() if profile_enabled else 0
	_apply_body(motion)
	_profile_mark("body_and_geometry", profile_started)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	if not _apply_feet(motion, selected.direction, probing): status = "rejected: dive leg path"; return false
	_profile_mark("legs", profile_started)
	var chest: Transform3D = actor.body_pivot.get_node("TorsoMesh").global_transform
	var when: float = selected.time
	var weight: float = smoothstep(0.12, maxf(0.32, when - 0.015), time) * (1.0 - smoothstep(1.70, 2.65, time))
	var arm = actor.right_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var first: Vector3 = chest * _main_wrist - shoulder
	var last: Vector3 = chest * Vector3(selected.wrist_in_chest) - shoulder
	var forward: Vector3 = (chest.basis.x * _team_sign() * float(selected.get("prepare_lateral", 0.25)) - chest.basis.z * _team_sign()).normalized()
	# A shoulder-centred spherical arc cannot collapse the wrist through the
	# shoulder the way a straight Cartesian blend can. The radius is a convex
	# blend of two attainable endpoints and a0.54m preparation radius.
	var a := first.normalized().slerp(forward, weight)
	var b := forward.slerp(last.normalized(), weight)
	var radius := first.length() * (1.0 - weight) * (1.0 - weight) + 2.0 * float(selected.get("prepare_radius", .54)) * weight * (1.0 - weight) + last.length() * weight * weight
	var wrist: Vector3 = shoulder + a.slerp(b, weight).normalized() * radius
	wrist += selected.contact_normal * float(selected.get("follow_through", 0.12)) * smoothstep(when, when + 0.12, time) * weight
	if wrist.distance_to(arm.upper_pivot.global_position) > arm.upper_arm_length + arm.forearm_length - 0.001:
		status = "rejected: intermediate reach exceeds actual arm length"; return false
	var safe_pole: Vector3 = _safe_elbow(arm, wrist, _path_pole(wrist, chest, weight, selected))
	if not safe_pole.is_finite():
		diagnostics["failed_time"] = time; status = "rejected: no clear main-arm path"; return false
	_solve_arm_ik(arm, wrist, safe_pole, Transform3D.IDENTITY, wrist)
	var reference: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, false)
	var finish: Dictionary = selected.wrist_channels
	var flex := lerpf(float(_main_channels.flexion_deg), float(finish.flexion_deg), weight)
	var dev := lerpf(float(_main_channels.radial_deviation_deg), float(finish.radial_deviation_deg), weight)
	var axial := lerpf(float(_main_channels.forearm_axial_deg), float(finish.forearm_axial_deg), weight)
	var anatomical: Basis = reference * Basis(Vector3.RIGHT, deg_to_rad(axial)) * Basis(Vector3.UP, deg_to_rad(flex)) * Basis(Vector3.BACK, deg_to_rad(dev))
	var mount := Transform3D(anatomical * arm.articulated_hand.anatomical_basis.inverse(), Vector3.ZERO)
	mount.origin = wrist - mount.basis * arm.articulated_hand.wrist_socket
	var grip: Basis = _entry_grip_basis.slerp(Hands.GripFrame.basis(Basis.IDENTITY, false, float(selected.grip_rotation)), weight).orthonormalized()
	var paddle_basis: Basis = mount.basis * grip.inverse()
	var anchor: Vector3 = _grip_anchor.lerp(Paddle.MAIN_GRIP_OFFSET, weight)
	actor.paddle_node.global_transform = Transform3D(paddle_basis, mount.origin - paddle_basis * anchor)
	if not probing: _last_grip_basis = grip; _last_grip_anchor = anchor
	hands.apply_mount(arm, mount)
	_apply_support(motion)
	if not _support_ok: status = "rejected: no clear support-arm path"; diagnostics["failed_time"] = time; return false
	if time > Motion.TAKEOFF and time < 1.58:
		var floor_report := _rig_floor()
		actor.body_pivot.global_position.y += maxf(0.0, PickleballConstants.FLOOR_Y - float(floor_report.minimum))
		_floor_support = float(floor_report.minimum) <= PickleballConstants.FLOOR_Y + 0.000001
		motion.airborne = not _floor_support
		if _floor_support and time < 0.30: motion.phase = &"push_off"
		elif _floor_support and time < Motion.SLIDE_END: motion.phase = &"floor_landing_slide"
		motion["body_floor_minimum"] = maxf(PickleballConstants.FLOOR_Y, float(floor_report.minimum))
		motion["support_part"] = floor_report.part if _floor_support else "none"
		_current_pelvis = actor.body_pivot.to_global(_base.pelvis.origin)
		_update_arm_geometry()
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
	if not probing:
		latest_motion = motion
		latest_motion["support_phase"] = "release" if time < 0.28 else ("one_hand_dive" if time < 1.86 else "regrip")
	return true

func _team_sign() -> float:
	return 1.0 if actor.player_num == 0 else -1.0

func _apply_body(motion: Dictionary) -> void:
	var body_motion := motion.duplicate()
	body_motion.torso_yaw *= _team_sign()
	Motion.Base.apply_body(actor, _base, body_motion)
	var t: float = motion.time
	var direction: Vector3 = motion.direction
	var tilt := Basis(Vector3.UP.cross(direction).normalized(), float(motion.tilt))
	var body: Transform3D = actor.global_transform * _base.body
	var base_pelvis: Vector3 = body * _base.pelvis.origin
	var pelvis := base_pelvis + Vector3.UP * (float(motion.load_drop) + float(motion.ballistic_offset))
	# Get up from the actual floor support. Until feet have gathered, the
	# body remains supported on its side; afterwards feet bear the rise.
	if t >= 1.58:
		var rise := smoothstep(1.58, 2.40, t)
		pelvis.y = lerpf(pelvis.y, base_pelvis.y, rise)
	body.basis = tilt * body.basis
	body.origin = pelvis - body.basis * _base.pelvis.origin
	actor.body_pivot.global_transform = body
	var minimum := _core_floor()
	_floor_support = t > Motion.TAKEOFF and t < 1.58 and minimum <= PickleballConstants.FLOOR_Y + 0.000001
	if minimum < PickleballConstants.FLOOR_Y:
		actor.body_pivot.global_position.y += PickleballConstants.FLOOR_Y - minimum
	_current_pelvis = actor.body_pivot.to_global(_base.pelvis.origin)
	_update_arm_geometry()

func _core_floor() -> float:
	_update_arm_geometry()
	var result := INF
	var body: Transform3D = actor.body_pivot.global_transform
	for point in _core_vertices: result = minf(result, (body * point).y)
	var head: MeshInstance3D = actor.body_pivot.get_node("TorsoMesh/HeadMesh")
	for point in _head_vertices: result = minf(result, (head.global_transform * point).y)
	return result

func _apply_support(motion: Dictionary) -> void:
	_support_ok = true
	var arm = actor.left_arm_node
	var torso: Node3D = actor.body_pivot.get_node("TorsoMesh")
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var rest: Vector3 = torso.to_global(_base.support_wrist)
	var high: float = float(motion.get("height_weight", 0.0))
	var offset := Vector3(-0.38, -0.24, 0.06).lerp(Vector3(-0.48, -0.38, 0.06), high)
	offset.x *= _team_sign(); offset.z *= _team_sign()
	var opened: Vector3 = shoulder + torso.global_basis * Vector3(0.0, 0.40, -0.16 * _team_sign())
	opened.y = maxf(opened.y, PickleballConstants.FLOOR_Y + 0.18)
	var weight: float = motion.counterbalance_weight
	var outboard: Vector3 = -torso.global_basis.x * _team_sign()
	var away: Vector3 = -(torso.global_basis * _base.support_mount.basis * arm.articulated_hand.palm_normal).normalized()
	var first_control: Vector3 = rest + outboard * 0.14 + away * 0.08
	var second_control: Vector3 = opened + outboard * 0.10 + away * 0.04
	var wrist: Vector3 = rest * pow(1.0 - weight, 3) + first_control * (3.0 * weight * pow(1.0 - weight, 2)) + second_control * (3.0 * weight * weight * (1.0 - weight)) + opened * pow(weight, 3)
	var pole_offset := Vector3.LEFT.lerp(Vector3(-1.0, -0.30, -0.30), high)
	pole_offset.x *= _team_sign(); pole_offset.z *= _team_sign()
	var pole: Vector3 = torso.to_global(_base.support_elbow).lerp(shoulder + torso.global_basis * pole_offset, weight)
	arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
	var mount: Transform3D = hands.callout_mount(arm, wrist, pole, weight)
	var rest_mount: Transform3D = torso.global_transform * _base.support_mount
	mount.basis = rest_mount.basis.slerp(mount.basis, float(motion.pole_weight)).orthonormalized()
	mount.origin = wrist - mount.basis * arm.articulated_hand.wrist_socket
	var safe_pole: Vector3 = _safe_elbow(arm, wrist, pole)
	if not safe_pole.is_finite(): _support_ok = false; return
	pole = safe_pole
	_solve_arm_ik(arm, mount.origin, pole, mount, wrist)
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
	var hand: Dictionary = _base.support_hand_pose
	var closure: float = (1.0 - smoothstep(0.0, 0.20, float(motion.time))) if float(motion.time) < 0.25 else smoothstep(2.60, Motion.DURATION, float(motion.time))
	arm.articulated_hand.set_recovery_pose(1.0 - closure, 0.0, hand.index, hand.style)


func _update_arm_geometry() -> void:
	_body_inverse = actor.body_pivot.global_transform.affine_inverse()
	var skin = actor.body_pivot.get_meta("articulated_torso")
	var key := var_to_bytes([skin._last_pelvis, skin._last_abdomen, skin._last_chest])
	if key == _local_geometry_key: return
	_local_geometry_key = key
	var d = BodyDimensions
	var frames: Array[Transform3D] = [skin._last_pelvis * Transform3D(Basis.IDENTITY, Vector3(0, d.PELVIS_CENTER_Y, 0)).affine_inverse(),
		skin._last_abdomen * Transform3D(Basis.IDENTITY, Vector3(0, d.PELVIS_CENTER_Y + d.PELVIS_HALF_HEIGHT, 0)).affine_inverse(),
		skin._last_chest * Transform3D(Basis.IDENTITY, Vector3(0, d.CHEST_CENTER_Y, 0)).affine_inverse()]
	var rings: Array = []
	var weights := BodyProfile.weights()
	var source := BodyProfile.surface_rings(actor._get_forward_axis().z > 0.0)
	_core_vertices.clear()
	for row in range(source.size()):
		var ring := PackedVector3Array()
		for point in source[row]: ring.append((frames[0] * point) * weights[row].x + (frames[1] * point) * weights[row].y + (frames[2] * point) * weights[row].z)
		rings.append(ring); _core_vertices.append_array(ring)
	var cells: Array[AABB] = []
	for row in range(rings.size() - 1):
		var bounds := AABB(rings[row][0], Vector3.ZERO)
		for point in rings[row]: bounds = bounds.expand(point)
		for point in rings[row + 1]: bounds = bounds.expand(point)
		cells.append(bounds)
	# Each local slice box encloses every actual displayed torso triangle in
	# that slice. Capsule tests against expanded boxes are continuous and more
	# conservative than the former sampled convex-hull margin checks.
	_arm_geometry = {"boxes": cells, "frame_source": "displayed_skin_local_slice_bounds"}

func _solve_arm_ik(arm, target: Vector3, pole: Vector3, mount, wrist: Vector3) -> void:
	# Godot look_at preserves basis scale. Thousands of transactional IK
	# probes must not accumulate floating-point scale in a physical link.
	# Rebuild the rotational pivots at unit scale before the ordinary solver.
	arm.upper_pivot.basis = Basis.IDENTITY
	arm.forearm_pivot.basis = Basis.IDENTITY
	arm.solve_ik(target, pole, mount, wrist)

func _safe_elbow(arm, wrist: Vector3, preferred: Vector3, fixed_mount: Variant = null) -> Vector3:
	if not preferred.is_finite(): return Vector3.INF
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var span: Vector3 = wrist - shoulder
	var distance := span.length()
	if distance <= 0.001 or distance >= arm.upper_arm_length + arm.forearm_length - 0.00001: return Vector3.INF
	var axis := span / distance
	var along: float = (arm.upper_arm_length * arm.upper_arm_length - arm.forearm_length * arm.forearm_length + distance * distance) / (2.0 * distance)
	var center: Vector3 = shoulder + axis * along
	var radius: float = sqrt(maxf(0.0, arm.upper_arm_length * arm.upper_arm_length - along * along))
	var radial := preferred - center; radial -= axis * radial.dot(axis)
	if radial.length_squared() < 0.000001: radial = Vector3.UP - axis * axis.y
	if radial.length_squared() < 0.000001: radial = Vector3.RIGHT - axis * axis.x
	radial = radial.normalized()
	if not _path_curve.is_empty():
		var side := 0 if arm == actor.right_arm_node else 1
		var scaled := clampf(_presentation_time / _path_curve_step, 0.0, float(_path_curve.size() - 1))
		var before := floori(scaled); var after := mini(before + 1, _path_curve.size() - 1)
		var angle := lerp_angle(float(_path_curve[before][side]), float(_path_curve[after][side]), scaled - before)
		var elbow := center + radial.rotated(axis, angle) * radius
		_solve_arm_ik(arm, wrist, elbow, Transform3D.IDENTITY, wrist)
		if verify_catalog_path and not _arm_mesh_clear(arm): return Vector3.INF
		return elbow
	for index in range(73):
		var step := ceili(float(index) * 0.5) * (1.0 if index % 2 == 1 else -1.0)
		var elbow := center + radial.rotated(axis, deg_to_rad(step * 5.0)) * radius
		if minf(elbow.y - 0.045, wrist.y - 0.025) < PickleballConstants.FLOOR_Y - 0.0001: continue
		if fixed_mount != null:
			var reference: Basis = Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false)
			var channels: Dictionary = Anatomy.decompose(reference, fixed_mount.basis * arm.articulated_hand.anatomical_basis, 1.0)
			if not channels.within_animation_budget: continue
		var profile_started := Time.get_ticks_usec() if profile_enabled else 0
		_solve_arm_ik(arm, wrist, elbow, Transform3D.IDENTITY, wrist)
		_profile_mark("candidate_arm_node_writes", profile_started)
		profile_started = Time.get_ticks_usec() if profile_enabled else 0
		var mesh_clear := _arm_mesh_clear(arm)
		_profile_mark("sleeve_clearance", profile_started)
		if not mesh_clear: continue
		var chosen_angle := deg_to_rad(step * 5.0)
		if polish_profile_angles and index > 0:
			var low := 0.0; var high := absf(chosen_angle); var sign_angle := signf(chosen_angle)
			for refine in 10:
				var angle := (low + high) * 0.5
				var probe := center + radial.rotated(axis, angle * sign_angle) * radius
				var allowed := minf(probe.y - 0.045, wrist.y - 0.025) >= PickleballConstants.FLOOR_Y - 0.0001
				if allowed and fixed_mount != null:
					var reference: Basis = Anatomy.forearm_reference(shoulder, probe, wrist, Vector3.UP, false)
					allowed = Anatomy.decompose(reference, fixed_mount.basis * arm.articulated_hand.anatomical_basis, 1.0).within_animation_budget
				if allowed:
					_solve_arm_ik(arm, wrist, probe, Transform3D.IDENTITY, wrist)
					allowed = _arm_mesh_clear(arm)
				if allowed: high = angle
				else: low = angle
			chosen_angle = high * sign_angle
			elbow = center + radial.rotated(axis, chosen_angle) * radius
			_solve_arm_ik(arm, wrist, elbow, Transform3D.IDENTITY, wrist)
		_pose_angles[0 if arm == actor.right_arm_node else 1] = chosen_angle
		return elbow
	diagnostics["unsafe_shoulder"] = shoulder; diagnostics["unsafe_wrist"] = wrist
	return Vector3.INF

func _triangle_box(a: Vector3, b: Vector3, c: Vector3, box: AABB) -> bool:
	var center := box.get_center(); var half := box.size * 0.5
	a -= center; b -= center; c -= center
	var edges: Array[Vector3] = [b - a, c - b, a - c]
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK, edges[0].cross(edges[1])]
	for edge in edges:
		axes.append(edge.cross(Vector3.RIGHT)); axes.append(edge.cross(Vector3.UP)); axes.append(edge.cross(Vector3.BACK))
	for axis in axes:
		if axis.length_squared() < 0.0000000001: continue
		var lo := minf(axis.dot(a), minf(axis.dot(b), axis.dot(c)))
		var hi := maxf(axis.dot(a), maxf(axis.dot(b), axis.dot(c)))
		var radius := half.dot(axis.abs())
		if lo > radius or hi < -radius: return false
	return true

func _arm_mesh_clear(arm) -> bool:
	var started := Time.get_ticks_usec() if profile_enabled else 0
	var box_clear := _arm_box_clear(arm)
	_profile_mark("sleeve_box", started)
	if box_clear and clearance_margin <= 0.0: return true
	if _exact_geometry_key != _local_geometry_key:
		started = Time.get_ticks_usec() if profile_enabled else 0
		_exact_geometry = ReadyClearance.body_geometry(actor)
		_profile_mark("torso_bvh_build", started)
		_exact_geometry_key = _local_geometry_key.duplicate()
	_exact_geometry.inverse = _body_inverse
	started = Time.get_ticks_usec() if profile_enabled else 0
	var clear := ReadyClearance.arm_clear(arm, _exact_geometry, clearance_margin)
	_profile_mark("sleeve_exact", started)
	return clear

func _skin_bound(mesh: MeshInstance3D) -> AABB:
	var resource: Mesh = mesh.mesh
	if not _skin_bound_cache.has(resource):
		var groups: Dictionary = {}
		for surface in resource.get_surface_count():
			var arrays: Array = resource.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]; var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = bones.size() / vertices.size() if bones != null and weights != null and bones.size() >= vertices.size() * 4 else 0
			for index in vertices.size():
				if stride == 0:
					groups[-1] = groups[-1].expand(vertices[index]) if groups.has(-1) else AABB(vertices[index], Vector3.ZERO)
				else:
					for slot in stride:
						var offset: int = index * stride + slot
						if weights[offset] <= 0.0: continue
						var bone: int = bones[offset]
						groups[bone] = groups[bone].expand(vertices[index]) if groups.has(bone) else AABB(vertices[index], Vector3.ZERO)
		_skin_bound_cache[resource] = groups
	var palette: Array[Transform3D] = RigSurfaces._skin_palette(mesh)
	var minimum := Vector3.INF; var maximum := -Vector3.INF
	for bone: int in _skin_bound_cache[resource]:
		var frame: Transform3D = _body_inverse * (mesh.global_transform if bone < 0 or bone >= palette.size() else palette[bone])
		var box: AABB = _skin_bound_cache[resource][bone]
		for corner in 8:
			var point: Vector3 = frame * box.get_endpoint(corner)
			minimum = minimum.min(point); maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum).grow(0.000002)

func _mesh_separated(arm, mesh: MeshInstance3D) -> bool:
	# Each skinned vertex is a convex weighted blend of these per-bone bind
	# bounds. Their posed union AABB therefore encloses the entire mesh.
	var bound := _skin_bound(mesh)
	if mesh == arm.upper_mesh:
		var shoulder: Vector3 = _body_inverse * arm.upper_pivot.global_position
		var axis: Vector3 = (_body_inverse.basis * (arm.forearm_pivot.global_position - arm.upper_pivot.global_position)).normalized()
		var points: Array[Vector3] = []; var distances: Array[float] = []
		var minimum := Vector3.INF; var maximum := -Vector3.INF
		for corner in 8:
			var point := bound.get_endpoint(corner); var distance := (point - shoulder).dot(axis) - 0.12
			points.append(point); distances.append(distance)
			if distance >= 0.0: minimum = minimum.min(point); maximum = maximum.max(point)
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			var a: int = edge[0]; var b: int = edge[1]
			if (distances[a] >= 0.0) == (distances[b] >= 0.0): continue
			var point: Vector3 = points[a].lerp(points[b], distances[a] / (distances[a] - distances[b]))
			minimum = minimum.min(point); maximum = maximum.max(point)
		if not minimum.is_finite(): return true
		bound = AABB(minimum, maximum - minimum).grow(0.000002)
	for cell: AABB in _arm_geometry.boxes:
		if bound.intersects(cell): return false
	return true

func _arm_box_clear(arm) -> bool:
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var along := (elbow - shoulder).normalized()
	for mesh in [arm.upper_mesh, arm.fore_mesh]:
		if bound_acceleration and _mesh_separated(arm, mesh): continue
		var points := RigSurfaces.world_triangles(mesh)
		for index in range(0, points.size() - 2, 3):
			var triangle := PackedVector3Array([points[index], points[index + 1], points[index + 2]])
			if mesh == arm.upper_mesh:
				# The proximal sleeve is the intended shoulder attachment. Clip
				# that joint seam; do not waive the distal upper arm or forearm.
				var clipped := PackedVector3Array()
				var previous := triangle[-1]; var before := (previous - shoulder).dot(along) >= 0.12
				for point in triangle:
					var after := (point - shoulder).dot(along) >= 0.12
					if before != after:
						var fraction := (0.12 - (previous - shoulder).dot(along)) / (point - previous).dot(along)
						clipped.append(previous.lerp(point, fraction))
					if after: clipped.append(point)
					previous = point; before = after
				triangle = clipped
			if triangle.size() < 3: continue
			for i in range(triangle.size()): triangle[i] = _body_inverse * triangle[i]
			for fan in range(1, triangle.size() - 1):
				var a: Vector3 = triangle[0]; var b: Vector3 = triangle[fan]; var c: Vector3 = triangle[fan + 1]
				var broad := AABB(a, Vector3.ZERO).expand(b).expand(c)
				for box: AABB in _arm_geometry.boxes:
					if broad.intersects(box) and _triangle_box(a, b, c, box): return false
	return true

func _mesh_floor(mesh: MeshInstance3D, palette: Array[Transform3D] = []) -> float:
	var id := mesh.mesh.get_instance_id()
	if not _mesh_floor_cache.has(id):
		var parts: Array = []
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			parts.append({"vertices": arrays[Mesh.ARRAY_VERTEX], "bones": arrays[Mesh.ARRAY_BONES], "weights": arrays[Mesh.ARRAY_WEIGHTS]})
		_mesh_floor_cache[id] = parts
	var result := INF
	var matrix: Transform3D = mesh.global_transform
	for part in _mesh_floor_cache[id]:
		var vertices: PackedVector3Array = part.vertices
		var skinned: bool = not palette.is_empty() and part.bones != null and part.weights != null and part.bones.size() >= vertices.size() * 4
		if not skinned:
			for vertex in vertices: result = minf(result, (matrix * vertex).y)
		else:
			var stride: int = part.bones.size() / vertices.size()
			for index in range(vertices.size()):
				var y := 0.0
				for slot in range(stride):
					var offset: int = index * stride + slot
					var bone: int = part.bones[offset]
					if part.weights[offset] > 0.0 and bone < palette.size(): y += (palette[bone] * vertices[index]).y * part.weights[offset]
				result = minf(result, y)
	return result

func _rig_floor() -> Dictionary:
	var result := {"minimum": INF, "part": ""}
	for mesh in _rig_meshes:
		var palette := RigSurfaces._skin_palette(mesh)
		if RigSurfaces.posed_bounds(mesh.mesh, mesh.global_transform, palette).position.y >= float(result.minimum): continue
		var minimum := _mesh_floor(mesh, palette)
		if minimum < float(result.minimum): result = {"minimum": minimum, "part": String(mesh.name)}
	return result

func _apply_feet(motion: Dictionary, direction: Vector3, probing: bool) -> bool:
	var t: float = motion.time
	var yaw_axis := Vector3.UP.cross(direction).normalized()
	var tilt := Basis(yaw_axis, float(motion.tilt))
	var root_shift: Vector3 = actor.global_position - _origin
	var tuck := smoothstep(Motion.TAKEOFF, 0.39, t)
	var lead_right: bool = direction.dot(actor._get_forehand_axis()) > 0.0
	for side in [0, 1]:
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var plant_time := 1.58 if (side == 0) == lead_right else Motion.FEET_PLANT
		var gather := smoothstep(Motion.GETUP_START, plant_time, t)
		var ankle: Vector3 = _ankles[side]
		if t > Motion.TAKEOFF:
			var flown: Vector3 = _current_pelvis + tilt * _foot_air[side]
			flown.y = maxf(_ankles[side].y + 0.04, flown.y + 0.08)
			ankle = _ankles[side].lerp(flown, tuck)
		if t >= Motion.GETUP_START:
			var final: Vector3 = _ankles[side] + root_shift
			ankle = ankle.lerp(final, gather)
			ankle.y += sin(PI * gather) * 0.045
			ankle += actor._get_forward_axis() * sin(PI * gather) * 0.48
		if not FootContact.reach_report(leg.thigh_pivot.global_position, ankle, leg.thigh_length, leg.shin_length).feasible:
			diagnostics["failed_foot"] = side; diagnostics["failed_time"] = t; diagnostics["foot_reach"] = FootContact.reach_report(leg.thigh_pivot.global_position, ankle, leg.thigh_length, leg.shin_length)
			return false
		var pole: Vector3 = leg.thigh_pivot.global_position + actor._get_forward_axis() * 0.7 + Vector3.UP * (0.7 * tuck)
		leg.solve_ik(ankle, pole, 0.0)
		leg.foot_pivot.global_basis = _foot_bases[side]
		leg._keep_sole_above_floor()
		if not probing: _feet_planted[side] = t <= Motion.TAKEOFF or t >= plant_time
	return true

func _sync_foot_state() -> void:
	var ik = actor.leg_ik
	ik._airborne = bool(latest_motion.get("airborne", false))
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

func _entry_continuity() -> bool:
	var actual: Transform3D = actor.paddle_node.global_transform
	var mount: Transform3D = actor.right_arm_node.hand_mesh.global_transform
	var error := actual.origin.distance_to(_entry_paddle.origin)
	error = maxf(error, mount.origin.distance_to(_entry_main_mount.origin))
	for axis in [0, 1, 2]:
		error = maxf(error, (actual.basis[axis] - _entry_paddle.basis[axis]).length())
		error = maxf(error, (mount.basis[axis] - _entry_main_mount.basis[axis]).length())
	return error <= 0.00002

func _preflight(candidate: Dictionary) -> bool:
	diagnostics = {"samples": 0, "arm_limits_unchanged": true, "provenance": "actual rig path at 120 Hz including exact contact"}
	for frame in range(ceili(Motion.DURATION / STEP) + 1):
		if not _present(minf(float(frame) * STEP, Motion.DURATION), candidate, true): return false
		if frame == 0:
			if not _entry_continuity(): status = "rejected: discontinuous entry presentation"; return false
		var profile_started := Time.get_ticks_usec() if profile_enabled else 0
		if float(_rig_floor().minimum) < PickleballConstants.FLOOR_Y - 0.0001:
			status = "rejected: exact rig path penetrates floor"; return false
		_profile_mark("full_rig_floor", profile_started)
		diagnostics.samples += 1
	if not _present(float(candidate.time), candidate, true): return false
	if not Contact.touches(actor.paddle_node.global_transform, candidate.point, BallScript.BALL_RADIUS):
		status = "rejected: joint-space path misses finite head at predicted contact"; return false
	return true

func _channels(arm, left: bool) -> Dictionary:
	return Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length)), left), arm.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, arm.articulated_hand.radial_sign)

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
		var socket_error: float = wrist.distance_to(arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length)))
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
	result["airborne"] = bool(latest_motion.get("airborne", false))
	result["body_floor_support"] = _floor_support
	result.valid = result.valid and (result.grounded or result.airborne or _floor_support)
	if ball_point.is_finite(): result.finite_touch = Contact.touches(paddle, ball_point, radius)
	result["paddle"] = paddle; result["phase"] = latest_motion.get("phase", "entry")
	return result

func _flight_snapshot() -> Dictionary:
	var ball = actor._get_ball_ref()
	return {"flight_id": ball.flight_id, "position": ball.global_position, "velocity": ball.linear_velocity, "omega": ball.angular_velocity, "bounces": ball.bounces_since_last_hit, "last_hit_by": ball.last_hit_by, "in_play": ball.is_in_play}

func _entry_signature() -> PackedByteArray:
	var values: Array = [actor.get_instance_id(), actor.global_transform, actor.current_velocity, actor.body_pivot.transform,
		actor.body_pivot.get_node("TorsoMesh").transform, actor.paddle_node.global_transform, ProfileCatalog.entry_state(actor)]
	var skin = actor.body_pivot.get_meta("articulated_torso")
	values.append_array([skin._last_pelvis, skin._last_abdomen, skin._last_chest])
	for arm in [actor.right_arm_node, actor.left_arm_node]:
		var model = arm.articulated_hand
		values.append_array([arm.transform, arm.upper_pivot.global_transform, arm.forearm_pivot.global_transform,
			arm.hand_mesh.global_transform, arm.anatomical_wrist_world, arm.upper_arm_length, arm.forearm_length,
			model._mode, model._closure, model._index_closure, model._support_style_weight])
	for leg in [actor.right_leg_node, actor.left_leg_node]: values.append_array([leg.transform, leg.foot_pivot.global_transform, leg.foot_mesh.transform, leg.thigh_length, leg.shin_length])
	var ik = actor.leg_ik
	values.append_array([ik.right_foot_locked, ik.left_foot_locked, ik._active_side, ik._run_active, ik._airborne])
	return var_to_bytes(values)

func _snapshot(narrow: bool = false) -> Dictionary:
	var nodes: Array = [{"node": actor, "transform": actor.transform}]
	var bones: Array = []
	var changed: Array = actor.find_children("*", "Node3D", true, false) if not narrow else [actor.body_pivot, actor.paddle_node, actor.body_pivot.get_node("TorsoMesh"), actor.body_pivot.get_node("HipsMesh"), actor.body_pivot.get_meta("articulated_torso").skeleton]
	if narrow:
		for arm in [actor.right_arm_node, actor.left_arm_node]:
			changed.append_array([arm, arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot, arm.upper_mesh, arm.fore_mesh, arm.hand_mesh, arm.articulated_hand.skeleton])
			if arm.has_meta("arm_elbow_bridge"): changed.append(arm.get_meta("arm_elbow_bridge").skeleton)
		for leg in [actor.right_leg_node, actor.left_leg_node]:
			changed.append_array([leg, leg.thigh_pivot, leg.shin_pivot, leg.foot_pivot, leg.thigh_mesh, leg.shin_mesh, leg.foot_mesh])
			if leg.has_meta("leg_knee_bridge"): changed.append(leg.get_meta("leg_knee_bridge").skeleton)
	for node in changed:
		nodes.append({"node": node, "transform": node.transform})
		if node is Skeleton3D:
			var poses: Array[Transform3D] = []; var channels: Array = []
			for index in node.get_bone_count():
				poses.append(node.get_bone_pose(index))
				channels.append([node.get_bone_pose_position(index), node.get_bone_pose_rotation(index), node.get_bone_pose_scale(index)])
			bones.append({"node": node, "poses": poses, "channels": channels})
	var arms: Array = []
	for arm in [actor.right_arm_node, actor.left_arm_node]:
		var model = arm.articulated_hand
		var fields: Dictionary = {}
		for key in ["_mode", "_closure", "_index_closure", "_support_style_weight", "_recovery_pose_key", "_last_wrist_axis", "pose_update_count", "bone_pose_write_count", "wrist_bridge_update_count"]: fields[key] = model.get(key)
		arms.append({"arm": arm, "wrist": arm.anatomical_wrist_world, "stretch": arm.visual_stretch, "lag": arm.visual_wrist_lag_deg, "fields": fields, "support_frame_present": arm.has_meta("live_support_frame"), "support_frame": arm.get_meta("live_support_frame", {}).duplicate(true)})
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
		for index in item.poses.size():
			if item.has("channels"):
				item.node.set_bone_pose_position(index, item.channels[index][0])
				item.node.set_bone_pose_rotation(index, item.channels[index][1])
				item.node.set_bone_pose_scale(index, item.channels[index][2])
			else: item.node.set_bone_pose(index, item.poses[index])
	for item in saved.bridges:
		for key in item.fields: item.bridge.set(key, item.fields[key].duplicate() if item.fields[key] is Array else item.fields[key])
	for item in saved.arms:
		item.arm.anatomical_wrist_world = item.wrist; item.arm.visual_stretch = item.stretch; item.arm.visual_wrist_lag_deg = item.lag
		for key in item.fields: item.arm.articulated_hand.set(key, item.fields[key])
		if item.support_frame_present: item.arm.set_meta("live_support_frame", item.support_frame.duplicate(true))
		elif item.arm.has_meta("live_support_frame"): item.arm.remove_meta("live_support_frame")
	saved.skin._last_pelvis = saved.pelvis; saved.skin._last_abdomen = saved.abdomen; saved.skin._last_chest = saved.chest; saved.skin.bone_pose_write_count = saved.skin_writes
	actor.right_leg_node.reach_report = saved.right_report; actor.left_leg_node.reach_report = saved.left_report
