extends RefCounted
## Isolated prototype adapter. Production source is read-only.
## Frames freeze the displayed body, paddle and final hand mesh mounts. A route
## substitutes ONLY the elbow-circle branch after production pose sampling.
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const BodyClearance = preload("res://scripts/body_clearance.gd")
const PaddleClearance = preload("res://scripts/paddle_clearance.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const UPPER_RADIUS := 0.058
const FORE_RADIUS := 0.037
const SHOULDER_SEAM := 0.08

static func prepare(player) -> void:
	player.hitting.serving_visual_active = false
	player.hitting.charge_visual_active = false
	player.hitting.is_in_follow_through = false
	player.current_velocity = Vector3.ZERO
	player.posture.editor_preview_mode = true

static func capture(player, pose: PostureDefinition, time: float, include_geometry: bool = true) -> Array[Dictionary]:
	prepare(player)
	player.leg_ik.feet_initialized = false
	player.posture.transition_pose_blend = pose
	player.posture.force_posture_update(pose)
	return capture_current(player, pose, time, include_geometry)

static func capture_current(player, pose: PostureDefinition, time: float, include_geometry: bool = true) -> Array[Dictionary]:
	var geometry: Dictionary = {}
	var skin: Array = []
	if player.body_pivot.has_meta("articulated_torso"):
		var torso = player.body_pivot.get_meta("articulated_torso")
		skin = [torso._last_pelvis, torso._last_abdomen, torso._last_chest]
	if include_geometry:
		geometry = BodyClearance.volumes(player, pose, player.body_pivot.global_transform, skin if skin.size() == 3 else null)
	var paddle: Transform3D = player.paddle_node.global_transform
	var fixed_paddle_margin: float = INF
	if include_geometry:
		var margins: Dictionary = BodyClearance.sample_paddle(paddle, PaddleClearance.sample_head_surface(), geometry)
		for value in margins.values(): fixed_paddle_margin = minf(fixed_paddle_margin, float(value))
	var result: Array[Dictionary] = []
	var hands = player.arm_ik._hands
	for side in range(2):
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var model = arm.articulated_hand
		var mount: Transform3D = arm.hand_mesh.global_transform
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var wrist: Vector3 = mount * model.wrist_socket
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var hand_basis: Basis = mount.basis * model.anatomical_basis
		var frame: Dictionary = {"time": time, "side": side, "is_left": side == 1,
			"dominant": side == pose.paddle_hand, "paddle_hand": pose.paddle_hand,
			"court": player.player_num, "posture_id": pose.posture_id,
			"phase": str(pose.get_meta("preview_serve_phase", pose.get_meta("auto_elbow_phase", "STROKE"))),
			"shoulder": shoulder, "wrist": wrist, "baseline_elbow": elbow,
			"upper_length": arm.upper_arm_length, "fore_length": arm.forearm_length,
			"hand_basis": hand_basis, "hand_mount": mount,
			"wrist_socket": model.wrist_socket, "anatomical_basis": model.anatomical_basis,
			"radial_sign": model.radial_sign, "thumb_up": -arm.forearm_pivot.global_basis.y,
			"target_position": arm.hand_pivot.global_position,
			"production_ik_wrist": arm.anatomical_wrist_world,
			"production_visual_stretch": arm.visual_stretch,
			"production_visual_wrist_lag_deg": arm.visual_wrist_lag_deg,
			"production_hand_mode": str(hands.mode),
			"production_support_grip_weight": float(hands._support_grip_weight),
			"body_transform": player.body_pivot.global_transform,
			"body_skin_frames": skin, "body_geometry": geometry,
			"paddle_transform": paddle, "paddle_inverse": paddle.affine_inverse(),
			"fixed_paddle_torso_sample_margin_m": fixed_paddle_margin,
			"upper_radius": UPPER_RADIUS, "fore_radius": FORE_RADIUS,
			"shoulder_exclude_m": SHOULDER_SEAM,
			"obstacles": [], "grip_attachment_exclude_m": 0.045,
			"collision_model": "conservative displayed skin cells; arm maximum profile-radius capsules; own proximal upper-arm seam only"}
		frame["baseline_channels"] = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, frame.thumb_up, side == 1), hand_basis, model.radial_sign)
		frame["fixed_mount_ik_wrist_gap_m"] = wrist.distance_to(arm.anatomical_wrist_world)
		result.append(frame)
	if include_geometry:
		for side in range(2):
			var other: Dictionary = result[1 - side]
			result[side].obstacles = [{"a": other.shoulder, "b": other.baseline_elbow, "radius": UPPER_RADIUS, "label": "other_upper"},
				{"a": other.baseline_elbow, "b": other.wrist, "radius": FORE_RADIUS, "label": "other_fore"}]
			var head: Node3D = player.body_pivot.get_node_or_null("TorsoMesh/HeadMesh")
			if head != null: result[side].obstacles.append({"a": head.global_position, "b": head.global_position, "radius": 0.10, "label": "head"})
	return result

## Pure counterpart of right_arm/left_arm.solve_ik geometry. Never stretches.
## The fixed mesh mount is a deliberate final stage, matching the requested
## invariant; production RELAXED/REGRIP would remount and is measured separately.
static func forward(frame: Dictionary, elbow: Vector3) -> Dictionary:
	var shoulder: Vector3 = frame.shoulder
	var wrist: Vector3 = frame.wrist
	var upper: float = frame.upper_length
	var fore: float = frame.fore_length
	var span: Vector3 = wrist - shoulder
	var distance: float = span.length()
	var reach_ok: bool = distance <= upper + fore + 0.000001 and distance >= absf(upper - fore) - 0.000001 and distance > 0.000001
	if not reach_ok:
		return {"valid": false, "reason": "fixed_wrist_outside_nominal_reach", "elbow": elbow,
			"required_stretch": maxf(1.0, distance / (upper + fore)), "reach_gap_m": maxf(distance - upper - fore, absf(upper - fore) - distance)}
	var axis: Vector3 = span / distance
	var radial: Vector3 = elbow - shoulder
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 1e-12:
		radial = Vector3.UP - axis * axis.y
		if radial.length_squared() < 1e-12: radial = Vector3.RIGHT - axis * axis.x
	var along: float = (upper * upper + distance * distance - fore * fore) / (2.0 * distance)
	var radius: float = sqrt(maxf(0.0, upper * upper - along * along))
	var solved: Vector3 = shoulder + axis * along + radial.normalized() * radius
	var shoulder_angle: float = acos(clampf(along / upper, -1.0, 1.0))
	var elbow_angle: float = PI - acos(clampf((upper * upper + fore * fore - distance * distance) / (2.0 * upper * fore), -1.0, 1.0))
	var fore_basis: Basis = Basis.looking_at(axis, radial.normalized()) * Basis(Vector3.RIGHT, shoulder_angle - elbow_angle)
	return {"valid": true, "elbow": solved, "wrist": wrist,
		"fore_basis": fore_basis,
		"elbow_projection_gap_m": solved.distance_to(elbow),
		"upper_error_m": absf(shoulder.distance_to(solved) - upper),
		"fore_error_m": absf(solved.distance_to(wrist) - fore),
		"hand_mount": frame.hand_mount,
		"channels": Anatomy.decompose(Anatomy.forearm_reference(shoulder, solved, wrist, -fore_basis.y, frame.is_left), frame.hand_basis, frame.radial_sign)}

static func apply_solution(player, frame: Dictionary, solution: Dictionary, armindex: int = -1) -> Dictionary:
	if not solution.has("elbow") or not bool(solution.get("valid", solution.get("feasible", true))):
		return {"applied": false, "reason": "route_not_feasible"}
	var desired: Vector3 = solution.elbow
	var solved: Dictionary = forward(frame, desired)
	if not bool(solved.valid): return {"applied": false, "reason": solved.reason}
	if float(solved.elbow_projection_gap_m) > 0.0001:
		return {"applied": false, "reason": "elbow_not_on_nominal_circle", "gap_m": solved.elbow_projection_gap_m}
	var side: int = int(frame.side) if armindex < 0 else armindex
	var arm = player.right_arm_node if side == 0 else player.left_arm_node
	var paddle_before: Transform3D = player.paddle_node.global_transform
	var body_before: Transform3D = player.body_pivot.global_transform
	var fixed: Transform3D = frame.hand_mount
	arm.solve_ik(frame.target_position, desired, paddle_before if bool(frame.dominant) else null, frame.wrist)
	var hands = player.arm_ik._hands
	var saved_mode: String = hands.mode
	var saved_weight: float = hands._support_grip_weight
	hands.mode = frame.production_hand_mode
	hands._support_grip_weight = frame.production_support_grip_weight
	hands.apply_mount(arm, fixed, not bool(frame.dominant))
	var production_mount: Transform3D = arm.hand_mesh.global_transform
	hands.mode = saved_mode
	hands._support_grip_weight = saved_weight
	arm.articulated_hand.set_mesh_world_transform(fixed)
	arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
	var actual_channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, frame.wrist, frame.is_left), arm.hand_mesh.global_basis * frame.anatomical_basis, frame.radial_sign)
	return {"applied": true, "actual_wrist_budget_ok": actual_channels.within_animation_budget,
		"actual_wrist_coupled_ratio": actual_channels.coupled_budget_ratio,
		"actual_wrist_axial_deg": actual_channels.forearm_axial_deg,
		"forward_wrist_flexion_error_deg": absf(float(actual_channels.flexion_deg) - float(solved.channels.flexion_deg)),
		"forward_wrist_deviation_error_deg": absf(float(actual_channels.radial_deviation_deg) - float(solved.channels.radial_deviation_deg)),
		"forward_wrist_axial_error_deg": absf(float(actual_channels.forearm_axial_deg) - float(solved.channels.forearm_axial_deg)),
		"elbow_parity_gap_m": arm.forearm_pivot.global_position.distance_to(desired),
		"wrist_error_m": (arm.hand_mesh.global_transform * frame.wrist_socket).distance_to(frame.wrist),
		"hand_position_error_m": arm.hand_mesh.global_position.distance_to(fixed.origin),
		"hand_rotation_error_deg": basis_angle_deg(arm.hand_mesh.global_basis, fixed.basis),
		"production_apply_mount_position_gap_m": production_mount.origin.distance_to(fixed.origin),
		"production_apply_mount_rotation_gap_deg": basis_angle_deg(production_mount.basis, fixed.basis),
		"paddle_position_error_m": player.paddle_node.global_position.distance_to(paddle_before.origin),
		"paddle_rotation_error_deg": basis_angle_deg(player.paddle_node.global_basis, paddle_before.basis),
		"body_position_error_m": player.body_pivot.global_position.distance_to(body_before.origin),
		"body_rotation_error_deg": basis_angle_deg(player.body_pivot.global_basis, body_before.basis),
		"upper_length_error_m": absf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position) - float(frame.upper_length)),
		"fore_length_error_m": absf(arm.forearm_pivot.global_position.distance_to(frame.wrist) - float(frame.fore_length)),
		"stretch": arm.visual_stretch}

static func basis_angle_deg(a: Basis, b: Basis) -> float:
	# atan2 is stable near identity, unlike acos(quaternion dot), whose float
	# roundoff alone can manufacture a ~0.04-degree error for identical mounts.
	var relative: Basis = a.orthonormalized() * b.orthonormalized().inverse()
	var sine: float = Vector3(relative.y.z - relative.z.y, relative.z.x - relative.x.z, relative.x.y - relative.y.x).length() * 0.5
	var cosine: float = clampf((relative.x.x + relative.y.y + relative.z.z - 1.0) * 0.5, -1.0, 1.0)
	return rad_to_deg(atan2(sine, cosine))

static func sample_pose(kind: String, id: int, progress: float, hand: int = 0, charge: float = 1.0) -> PostureDefinition:
	var pose: PostureDefinition
	if kind == "serve":
		var duration: float = serve_duration(id)
		pose = Preview.sample_serve_elapsed(id, progress * duration, charge)
	else:
		var base: PostureDefinition = PostureLibrary.instance().get_def(id).duplicate(true)
		base.paddle_hand = hand
		pose = Path.sample(base, progress) if kind == "authored" else Motion.sample_drive(base, progress, charge)
	pose.paddle_hand = hand
	return pose

static func serve_duration(style: int) -> float:
	return float(Preview.serve_plan(style).contact_time) + Styles.sweep_duration(style) + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME

static func sample_times(kind: String, id: int, steps: int) -> Array[float]:
	var times: Array[float] = []
	for step in range(steps + 1): times.append(float(step) / maxi(steps, 1))
	if kind == "serve":
		var plan: Dictionary = Preview.serve_plan(id)
		var duration: float = serve_duration(id)
		var contact: float = plan.contact_time
		for elapsed in [0.0, 0.18 * 0.45, 0.18, float(plan.bounce_time), contact - Styles.stroke_duration(id), contact,
			contact + Styles.sweep_duration(id), contact + Styles.sweep_duration(id) + Motion.SERVE_HOLD_TIME, duration]:
			if elapsed >= 0.0 and elapsed <= duration:
				var t: float = elapsed / duration
				if not times.has(t): times.append(t)
	else:
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			if not times.has(t): times.append(t)
	times.sort()
	return times

static func baseline_metrics(frame: Dictionary) -> Dictionary:
	var shoulder: Vector3 = frame.shoulder
	var wrist: Vector3 = frame.wrist
	var elbow: Vector3 = frame.baseline_elbow
	var span: float = shoulder.distance_to(wrist)
	var forward_result: Dictionary = forward(frame, elbow)
	var channels: Dictionary = frame.baseline_channels
	return {"reach_ok": bool(forward_result.valid), "reach_gap_m": maxf(0.0, span - float(frame.upper_length) - float(frame.fore_length)),
		"production_stretch": frame.production_visual_stretch,
		"wrist_budget_ok": channels.within_animation_budget,
		"wrist_budget_ratio": channels.coupled_budget_ratio,
		"wrist_axial_deg": channels.forearm_axial_deg,
		"fixed_mount_ik_wrist_gap_m": frame.fixed_mount_ik_wrist_gap_m,
		"baseline_circle_gap_m": forward_result.get("elbow_projection_gap_m", -1.0)}

static func validate_pair(frames: Array, solutions: Array) -> Dictionary:
	if frames.size() != 2 or solutions.size() != 2:
		return {"valid": false, "reason": "two_arm_pair_required", "clearance_m": -INF}
	var segments: Array = []
	for side in range(2):
		if not solutions[side].has("elbow") or not bool(solutions[side].get("valid", solutions[side].get("feasible", true))):
			return {"valid": false, "reason": "one_arm_infeasible", "clearance_m": -INF}
		segments.append([{"a": frames[side].shoulder, "b": solutions[side].elbow, "r": float(frames[side].upper_radius)},
			{"a": solutions[side].elbow, "b": frames[side].wrist, "r": float(frames[side].fore_radius)}])
	var minimum: float = INF
	var pair: String = ""
	for first in range(2):
		for second in range(2):
			var a: Dictionary = segments[0][first]
			var b: Dictionary = segments[1][second]
			var clearance: float = segment_distance(a.a, a.b, b.a, b.b) - a.r - b.r
			if clearance < minimum:
				minimum = clearance
				pair = "%s/%s" % ["upper" if first == 0 else "fore", "upper" if second == 0 else "fore"]
	return {"valid": minimum >= -0.000001, "reason": "" if minimum >= -0.000001 else "optimized_arm_pair_collision", "clearance_m": minimum, "limb_pair": pair,
		"model": "analytic distance between max-profile capsules of the final two routes"}

static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1: Vector3 = q1 - p1
	var d2: Vector3 = q2 - p2
	var r: Vector3 = p1 - p2
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	if a <= 1e-12 and e <= 1e-12: return p1.distance_to(p2)
	if a <= 1e-12: t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= 1e-12: s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denominator: float = a * e - b * b
			if denominator > 1e-12: s = clampf((b * f - c * e) / denominator, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)

## A conservative continuous-in-space capsule/SDF check against the exact
## rounded paddle head and cylindrical shaft. Segment subdivision uses the
## 1-Lipschitz SDF bound; unresolved intervals fail closed. Only the final 45mm
## of forearm at its own wrist/handle attachment excludes shaft contact.
static func paddle_constraint(frame: Dictionary, elbow: Vector3) -> Dictionary:
	var pure: Dictionary = forward(frame, elbow)
	if not bool(pure.valid): return {"valid": false, "reasons": [pure.reason], "clearance_m": -INF}
	if not bool(pure.channels.within_animation_budget): return {"valid": false, "reasons": ["production_forward_wrist_budget"], "clearance_m": -INF}
	var inverse: Transform3D = frame.paddle_inverse
	var shoulder: Vector3 = inverse * frame.shoulder
	var local_elbow: Vector3 = inverse * elbow
	var wrist: Vector3 = inverse * frame.wrist
	var upper_radius: float = frame.upper_radius
	var fore_radius: float = frame.fore_radius
	var minimum: float = INF
	minimum = minf(minimum, _paddle_segment_bound(shoulder, local_elbow, upper_radius, true, 6))
	minimum = minf(minimum, _paddle_segment_bound(local_elbow, wrist, fore_radius, true, 6))
	minimum = minf(minimum, _paddle_segment_bound(shoulder, local_elbow, upper_radius, false, 6))
	var fore_length: float = local_elbow.distance_to(wrist)
	var shaft_end: Vector3 = local_elbow.lerp(wrist, clampf(1.0 - float(frame.get("grip_attachment_exclude_m", 0.045)) / maxf(fore_length, 0.00001), 0.0, 1.0))
	minimum = minf(minimum, _paddle_segment_bound(local_elbow, shaft_end, fore_radius, false, 6))
	var reasons: Array = []
	if minimum < 0.001: reasons.append("arm_paddle_clearance")
	if float(frame.get("fixed_paddle_torso_sample_margin_m", INF)) < -0.000001:
		reasons.append("immutable_paddle_torso_penetration")
	return {"valid": reasons.is_empty(), "reasons": reasons, "clearance_m": minimum,
		"model": "adaptive Lipschitz capsule-to-exact-paddle-SDF lower bound"}

static func _paddle_sdf(point: Vector3, head: bool) -> float:
	if head: return PaddleClearance.distance_to_head_shape(point)
	var cylinder := Vector2(Vector2(point.x, point.z).length() - PaddleSize.HANDLE_RADIUS,
		absf(point.y - PaddleSize.HANDLE_CENTER_Y) - PaddleSize.HANDLE_LENGTH * 0.5)
	return cylinder.max(Vector2.ZERO).length() + minf(maxf(cylinder.x, cylinder.y), 0.0)

static func _paddle_segment_bound(a: Vector3, b: Vector3, radius: float, head: bool, depth: int) -> float:
	var middle: Vector3 = (a + b) * 0.5
	var half_length: float = a.distance_to(b) * 0.5
	var center_distance: float = _paddle_sdf(middle, head) - radius
	var bound: float = center_distance - half_length
	if bound >= 0.001 or depth <= 0 or center_distance < 0.0: return bound
	return minf(_paddle_segment_bound(a, middle, radius, head, depth - 1), _paddle_segment_bound(middle, b, radius, head, depth - 1))

## Optional exact-second fixture from the isolated gameplay-parity sequence.
## A TO_READY sequence includes strike, sweep, hold and recovery. It is a separate
## coverage mode from sample_pose's normalized source keyframe path.
static func make_sequence(kind: String, id: int, hand: int = 0, player = null):
	var Sequence: Script = load("res://scripts/ui/mobile_pose_sequence.gd")
	var source: PostureDefinition
	if kind == "serve": source = preload("res://scripts/mobile_serve_pose_store.gd").get_def(id).duplicate(true)
	else: source = PostureLibrary.instance().get_def(id).duplicate(true)
	source.paddle_hand = hand
	var sequence = Sequence.new()
	sequence.configure(source, Sequence.Mode.TO_READY, Sequence.Stance.AUTHORED, 0, kind != "authored", player)
	return sequence

static func sequence_times(sequence, steps: int) -> Array[float]:
	var times: Array[float] = []
	for index in range(steps + 1): times.append(float(sequence.duration) * index / maxi(steps, 1))
	var hold: float = Motion.SERVE_HOLD_TIME if int(sequence.style) >= 0 else maxf(0.0, float(sequence.source.ft_duration_hold))
	for time in [float(sequence.release_seconds), float(sequence.stroke_seconds), float(sequence.stroke_seconds) + hold, float(sequence.full_seconds)]:
		if time >= 0.0 and time <= float(sequence.duration): times.append(time)
	if int(sequence.style) >= 0:
		var plan: Dictionary = Preview.serve_plan(sequence.style)
		for time in [0.081, 0.18, float(plan.bounce_time), float(plan.contact_time) - Styles.stroke_duration(sequence.style)]:
			if time >= 0.0 and time <= float(sequence.duration): times.append(time)
	times.sort()
	var unique: Array[float] = []
	for time in times:
		if unique.is_empty() or time - unique[-1] > 0.0000001: unique.append(time)
	return unique
