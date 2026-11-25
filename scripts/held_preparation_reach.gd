extends RefCounted
## An incoming contact fit is not a reach guarantee for its displaced Wind-up.
## Only live HELD preparation is projected here. The source/contact definition,
## paddle orientation, input clock and eventual Contact are never changed.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Reach = preload("res://scripts/paddle_wrist_reach.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Floor = preload("res://scripts/paddle_floor_geometry.gd")
const WristBudget = preload("res://scripts/live_arm_budget.gd")
const ReadyRate = preload("res://scripts/incoming_ready_motion.gd")
const Rotation = preload("res://scripts/paddle_rotation.gd")
const ARM_RESERVE_M := 0.001
const ITERATIONS := 64

static func fit(player, pose: PostureDefinition) -> Dictionary:
	var result := {"pose": pose, "limited": false, "feasible": true, "distance_m": 0.0}
	if player == null or player.posture.editor_preview_mode or player.hitting.serving_visual_active: return result
	var ball = player._get_ball_ref()
	if ball == null or not ball.is_in_play: return result
	var paddle: Transform3D = Path.world_transform(player, pose)
	var main_shoulder: Vector3 = Body.shoulder_world(player, pose)
	var support_shoulder: Vector3 = player.global_transform * Body.pivot_transform(player, pose) * Body.torso_transform(player, pose) * Body.shoulder_local(player, pose, 1.0 if pose.paddle_hand == 1 else -1.0)
	if player.leg_ik != null and player.leg_ik.feet_initialized:
		var feet: Array = [player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]
		var fit_body: Dictionary = Body._position_candidate(player, pose, Body.pivot_transform(player, pose), Vector3.ZERO, feet)
		main_shoulder = fit_body.shoulder
		support_shoulder = fit_body.support_shoulder
	var centers: Array[Vector3] = [main_shoulder - Reach.wrist_world(paddle, pose)]
	var radii: Array[float] = [Reach.link_budget(player, pose) - ARM_RESERVE_M]
	if Path._support_mode(pose) == 1:
		var left: bool = pose.paddle_hand == 0
		var arm = player.left_arm_node if left else player.right_arm_node
		var hand_offset: Vector3 = pose.left_hand_offset if left else pose.right_hand_offset
		var wrist: Vector3 = paddle * (D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m)
		wrist += player._get_forehand_axis() * hand_offset.x + Vector3.UP * hand_offset.y + player._get_forward_axis() * hand_offset.z
		wrist += Grip.basis(paddle.basis, left, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg) * Reach.socket(left)
		centers.append(support_shoulder - wrist)
		radii.append(arm.upper_arm_length + arm.forearm_length - ARM_RESERVE_M)
	var head: Vector3 = paddle * D.HEAD_OFFSET
	centers.append(Body.shoulder_world(player, pose, null, false) - head)
	radii.append(PaddleReach.MAX_HEAD_DISTANCE)
	var minimum_y: float = player.COURT_FLOOR_Y + Floor.clearance(pose, paddle.basis) - head.y
	var delta: Vector3 = _project(centers, radii, minimum_y)
	result.feasible = _fits(delta, centers, radii, minimum_y)
	if not result.feasible or delta.length_squared() < 1e-12: return result
	var fitted: PostureDefinition = pose.duplicate(false)
	var desired := paddle
	desired.origin += delta
	# Undo the optional captured travel frame before writing stance-space head
	# channels, otherwise the presentation overlay would apply the fit twice.
	if bool(pose.get_meta("travel_paddle_follow", false)) and Body.locomotion_weight(player, pose) > 0.00001:
		var pivot: Transform3D = Body.untranslated_pivot_transform(player, pose)
		var travel: Transform3D = (pivot * Body.torso_transform(player, pose, true)) * (pivot * Body.torso_transform(player, pose, false)).affine_inverse()
		desired.origin = player.global_position + travel.affine_inverse() * (desired.origin - player.global_position)
		desired.basis = travel.basis.inverse() * desired.basis
	desired = Path.remove_in_hand_transform(desired, pose)
	var stance: Basis = Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
	var local_head: Vector3 = stance.inverse() * (desired * D.HEAD_OFFSET - player.global_position)
	fitted.paddle_forehand_mul = local_head.x
	fitted.paddle_y_offset = local_head.y
	fitted.paddle_forward_mul = -local_head.z
	result.pose = fitted
	result.limited = true
	result.distance_m = delta.length()
	return result

static func fit_grip(player, pose: PostureDefinition, previous_pose: PostureDefinition = null, delta: float = -1.0, body_allowance: float = 0.04) -> PostureDefinition:
	if player == null or pose == null or player.posture.editor_preview_mode or player.hitting.serving_visual_active: return pose
	var ball = player._get_ball_ref()
	if ball == null or not ball.is_in_play: return pose
	# Simple hands (PerfToggles.simple_hands; user, 2026-11-25: the pixel cards draw the hands, the
	# game needs no 3D fingers or wrist limits): the grip stays as posed. No search for a grip
	# roll inside the wrist budget (it ran a wrist solve about 680 times a second while HIT was
	# held, 2-3 ms a call on the Mac). The paddle's own turn-rate limit below still applies.
	if PerfToggles.simple_hands: return _continuous(player, previous_pose, pose, delta)
	var paddle: Transform3D = Path.world_transform(player, pose)
	var left: bool = pose.paddle_hand == 1
	var arm = player.left_arm_node if left else player.right_arm_node
	var shoulder: Vector3 = Body.shoulder_world(player, pose)
	if player.leg_ik != null and player.leg_ik.feet_initialized:
		shoulder = Body._position_candidate(player, pose, Body.pivot_transform(player, pose), Vector3.ZERO,
			[player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]).shoulder
	var anchor: Vector3 = paddle * Reach.grip_local(pose)
	var angle: float = pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg
	if _grip_fits(arm, shoulder, paddle.basis, anchor, angle, left, body_allowance): return _continuous(player, previous_pose, pose, delta)
	# The smallest grip turn that fits: the first 5 degree step that fits in either direction,
	# refined by bisection. Perf: both directions are stepped together, smallest turn first (the
	# negative one first on a tie, as before). The old order tried every negative step before any
	# positive one, so a hand that needed a small positive turn cost 18 failed fits each call.
	# Same answer: a direction's first fitting step is the same either way.
	var best := INF
	for index in range(1, 19):
		for direction in [-1.0, 1.0]:
			if not _grip_fits(arm, shoulder, paddle.basis, anchor, angle + float(index) * 5.0 * direction, left, body_allowance): continue
			var low := float(index - 1) * 5.0; var high := float(index) * 5.0
			for unused in range(10):
				var middle := (low + high) * .5
				if _grip_fits(arm, shoulder, paddle.basis, anchor, angle + middle * direction, left, body_allowance): high = middle
				else: low = middle
			best = high * direction
			break
		if is_finite(best): break
	if not is_finite(best): return _continuous(player, previous_pose, pose, delta)
	var result: PostureDefinition = pose.duplicate(false)
	result.main_grip_rotation_deg += best
	result.set_meta("held_grip_fit_deg", best)
	return _continuous(player, previous_pose, result, delta)

static func fit_planned_contact_grip(player, pose: PostureDefinition, previous_pose: PostureDefinition = null, compact_reception: bool = false) -> PostureDefinition:
	# Planning-only API. The caller must choose this before committing a swing
	# and interpolate its held/released hand into the returned Contact. Never
	# invoke this to modify an already accepted hit or its physical paddle face.
	var started: int = Time.get_ticks_usec()
	if PerfToggles.simple_hands:
		# Grip as posed: nothing to fit, and no cramped-reception shaft roll.
		var as_posed: PostureDefinition = pose.duplicate(false)
		as_posed.set_meta("planned_live_grip", true)
		as_posed.set_meta("planned_live_grip_delta_deg", 0.0)
		as_posed.set_meta("planned_live_grip_feasible", true)
		as_posed.set_meta("planned_live_grip_status", "as_posed")
		as_posed.set_meta("planned_live_grip_cost_usec", 0)
		return as_posed
	var planned: PostureDefinition = pose
	if compact_reception and previous_pose != null and previous_pose.posture_id == pose.posture_id:
		planned = _plane_roll(pose, float(previous_pose.get_meta("planned_live_grip_plane_deg", 0.0)))
	if previous_pose != null and (compact_reception or previous_pose.posture_id == pose.posture_id) and previous_pose.paddle_hand == pose.paddle_hand:
		planned = planned.duplicate(false)
		planned.main_grip_rotation_deg = previous_pose.main_grip_rotation_deg
	var result: PostureDefinition = fit_grip(player, planned, null, -1.0, 0.0)
	if compact_reception and not _planned_fits(player, result):
		# A cramped reception may need a different shaft direction, selected
		# before preparation. Keep the face normal and exact head point fixed.
		# This bounded fallback is never an impact-time repair.
		for angle in [30.0, -30.0]:
			var candidate: PostureDefinition = fit_grip(player, _plane_roll(pose, angle), null, -1.0, 0.0)
			var original_frame: Transform3D = Path.world_transform(player, pose)
			var candidate_frame: Transform3D = Path.world_transform(player, candidate)
			var preserves_contact: bool = (original_frame * D.HEAD_OFFSET).distance_to(candidate_frame * D.HEAD_OFFSET) <= .000001 and original_frame.basis.z.normalized().dot(candidate_frame.basis.z.normalized()) >= .999999
			if preserves_contact and _planned_fits(player, candidate):
				result = candidate
				break
	if result == pose: result = pose.duplicate(false)
	result.set_meta("planned_live_grip", true)
	result.set_meta("planned_live_grip_delta_deg", result.main_grip_rotation_deg - pose.main_grip_rotation_deg)
	var feasible: bool = _planned_fits(player, result)
	result.set_meta("planned_live_grip_feasible", feasible)
	result.set_meta("planned_live_grip_status", "fitted" if feasible else "no_fixed_grip_solution")
	result.set_meta("planned_live_grip_cost_usec", Time.get_ticks_usec() - started)
	return result

static func _planned_fits(player, result: PostureDefinition) -> bool:
	var paddle: Transform3D = Path.world_transform(player, result)
	var left: bool = result.paddle_hand == 1
	var arm = player.left_arm_node if left else player.right_arm_node
	var shoulder: Vector3 = Body.shoulder_world(player, result)
	if player.leg_ik != null and player.leg_ik.feet_initialized:
		shoulder = Body._position_candidate(player, result, Body.pivot_transform(player, result), Vector3.ZERO,
			[player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]).shoulder
	return _grip_fits(arm, shoulder, paddle.basis, paddle * Reach.grip_local(result), result.main_grip_rotation_deg - result.paddle_in_hand_rotation_deg, left)

static func _plane_roll(pose: PostureDefinition, angle: float) -> PostureDefinition:
	var result: PostureDefinition = pose.duplicate(false)
	var tx: Transform3D = Path.canonical_transform(pose)
	var head: Vector3 = tx * D.HEAD_OFFSET
	tx.basis = Basis(tx.basis.z, deg_to_rad(angle)) * tx.basis
	tx.origin = head - tx.basis * D.HEAD_OFFSET
	tx = Path.remove_in_hand_transform(tx, pose)
	Rotation.set_basis(result, tx.basis)
	head = tx * D.HEAD_OFFSET
	result.paddle_forehand_mul = head.x
	result.paddle_y_offset = head.y
	result.paddle_forward_mul = -head.z
	result.set_meta("planned_live_grip_plane_deg", angle)
	return result

static func _continuous(player, previous: PostureDefinition, pose: PostureDefinition, delta: float) -> PostureDefinition:
	if pose.has_meta("held_preparation_rate_limited"): pose.remove_meta("held_preparation_rate_limited")
	if previous == null or delta < 0.0: return pose
	var before: Basis = Path.world_transform(player, previous).basis
	var after: Basis = Path.world_transform(player, pose).basis
	var left: bool = pose.paddle_hand == 1
	var old_hand: Basis = Grip.basis(before, left, previous.main_grip_rotation_deg - previous.paddle_in_hand_rotation_deg)
	var new_hand: Basis = Grip.basis(after, left, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
	var angle: float = old_hand.get_rotation_quaternion().angle_to(new_hand.get_rotation_quaternion())
	if angle <= deg_to_rad(ReadyRate.MAX_PREPARATION_ANGULAR_SPEED_DEG) * maxf(delta, 0.0) + 0.00001: return pose
	# Keep the last feasible held visual on an inadmissible interval. The next
	# sample retries the latest incoming target; no control time or shot is lost.
	var held: PostureDefinition = previous.duplicate(false)
	held.set_meta("held_preparation_rate_limited", true)
	return held

static func _grip_fits(arm, shoulder: Vector3, paddle: Basis, anchor: Vector3, angle: float, left: bool, body_allowance: float = 0.0) -> bool:
	var hand: Basis = Grip.basis(paddle, left, angle)
	var wrist: Vector3 = anchor + hand * Reach.socket(left)
	# Perf: WristBudget.fits_within answers "feasible and cost <= .97" exactly as the full solve
	# did, without building the elbow nobody reads here.
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var hand_frame: Basis = hand * arm.articulated_hand.anatomical_basis
	if WristBudget.fits_within(shoulder, wrist, elbow, hand_frame, arm.upper_arm_length, arm.forearm_length, left, .97): return true
	if body_allowance <= 0.0: return false
	# The live Ready elbow already fits with a small knee flexion. Allow that
	# existing body fit before demanding a new grip roll, so a small frame does
	# not get stuck behind an unnecessary first-frame hand rotation.
	var lower: Vector3 = Vector3.DOWN * body_allowance
	return WristBudget.fits_within(shoulder + lower, wrist, elbow + lower, hand_frame, arm.upper_arm_length, arm.forearm_length, left, .97)

static func _project(centers: Array[Vector3], radii: Array[float], minimum_y: float) -> Vector3:
	var offset := Vector3.ZERO
	var residuals: Array[Vector3] = []
	for unused in range(centers.size() + 1): residuals.append(Vector3.ZERO)
	for unused in range(ITERATIONS):
		var previous := offset
		for index in range(centers.size()):
			var trial: Vector3 = offset + residuals[index]
			var span: Vector3 = trial - centers[index]
			var projected: Vector3 = trial if span.length() <= radii[index] else centers[index] + span.normalized() * radii[index]
			residuals[index] = trial - projected
			offset = projected
		var trial: Vector3 = offset + residuals[-1]
		offset = Vector3(trial.x, maxf(trial.y, minimum_y), trial.z)
		residuals[-1] = trial - offset
		if offset.distance_to(previous) < 0.0000001 and _fits(offset, centers, radii, minimum_y): break
	return offset

static func _fits(offset: Vector3, centers: Array[Vector3], radii: Array[float], minimum_y: float) -> bool:
	if not offset.is_finite() or offset.y < minimum_y - 0.000001: return false
	for index in range(centers.size()):
		if offset.distance_to(centers[index]) > radii[index] + 0.000001: return false
	return true
