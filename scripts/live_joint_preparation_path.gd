extends RefCounted
## Live preparation (player_hitting, AI brain, human contact): limits how fast the paddle hand
## turns (720 deg/s) by bisecting the blend toward the desired pose. Poses are used as authored.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
## Binary search steps for the admissible blend.
## 10 steps cost up to ~45 ms per call on iPhone 15 Pro; 6 resolve the blend to
## 1/64, a few degrees of paddle turn at most.
const SEARCH_STEPS := 6

static func sample(player, desired: PostureDefinition, previous: PostureDefinition, delta: float) -> PostureDefinition:
	if desired == null: return desired
	if _reach_script == null: _reach_script = load("res://scripts/live_transition_arm_reach.gd")
	if not _reach_script.enabled(player, desired): return desired
	if previous != null and previous.has_meta("live_joint_presented_basis"):
		var rebased: Transform3D = Path.world_transform(player, previous)
		var head: Vector3 = rebased * D.HEAD_OFFSET
		rebased.basis = previous.get_meta("live_joint_presented_basis")
		rebased.origin = head - rebased.basis * D.HEAD_OFFSET
		previous = _encode(player, previous, rebased)
	# Poses are used as authored: the wrist-limit correction is off (user's call; projecting a
	# pose past the wrist limit flipped the AI blade every tick). match_contact_authority tolerates the arm.
	var result: PostureDefinition = desired
	if previous == null or delta < 0.0: return _presented(player, result)
	var arm = player.left_arm_node if desired.paddle_hand == 1 else player.right_arm_node
	var before_paddle: Transform3D = Path.world_transform(player, previous)
	var old: Quaternion = Grip.basis(before_paddle.basis, previous.paddle_hand == 1, previous.main_grip_rotation_deg - previous.paddle_in_hand_rotation_deg).orthonormalized().get_rotation_quaternion()
	var allowance: float = deg_to_rad(719.9) * maxf(delta, 0.0) + .00001
	# Perf: `previous`'s paddle frame is the same for every candidate; it was rebuilt twice per
	# candidate (up to 14 world transforms a call).
	_before_basis = before_paddle.basis
	_before_quat = before_paddle.basis.orthonormalized().get_rotation_quaternion()
	var full_angle: float = _hand_angle(player, result, old, previous)
	if full_angle <= allowance: return _presented(player, result, _candidate_basis)
	if PerfToggles.hand_turn_closed_form:
		# The hand turn grows close to evenly with the blend, so the share that fits the allowance
		# is about allowance / full turn. Each try is measured and the share rescaled by how far
		# over or under it came out, so two or three blends land within a few percent of the
		# largest share that fits (the search below takes six blends for it to 1/64).
		var share: float = clampf(allowance / full_angle, 0.0, 1.0)
		var best: PostureDefinition = null
		var best_basis: Basis = _before_basis
		var best_share := 0.0
		for unused in range(3):
			if share <= best_share + 0.01: break
			var candidate: PostureDefinition = Path.blend_pose(desired, previous, 1.0 - share)
			var turn: float = _hand_angle(player, candidate, old, previous)
			if turn <= allowance:
				best = candidate; best_basis = _candidate_basis; best_share = share
				if turn >= allowance * 0.93 or share >= 1.0: break
				share = minf(1.0, share * allowance / maxf(turn, 0.000001) * 0.985)   # room left: step up once
			else:
				share = maxf(best_share, share * clampf(allowance / turn, 0.25, 1.0) * 0.985)
		return _presented(player, best if best != null else previous, best_basis)
	var low := 0.0; var high := 1.0
	var admitted: PostureDefinition = previous
	var admitted_basis: Basis = _before_basis
	for unused in range(SEARCH_STEPS):
		var middle := (low + high) * .5
		var candidate: PostureDefinition = Path.blend_pose(desired, previous, 1.0 - middle)
		if _hand_angle(player, candidate, old, previous) <= allowance:
			low = middle; admitted = candidate; admitted_basis = _candidate_basis
		else: high = middle
	return _presented(player, admitted, admitted_basis)

static var _reach_script: Script
static var _before_basis: Basis        # paddle basis of `previous` in the current sample() call
static var _before_quat: Quaternion
static var _candidate_basis: Basis     # paddle basis of the pose _hand_angle measured last

static func _hand_angle(player, pose: PostureDefinition, old: Quaternion, previous: PostureDefinition) -> float:
	var paddle: Transform3D = Path.world_transform(player, pose)
	_candidate_basis = paddle.basis
	var basis: Basis = Grip.basis(paddle.basis, pose.paddle_hand == 1, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
	var angle: float = old.angle_to(basis.orthonormalized().get_rotation_quaternion())
	angle = maxf(angle, _before_quat.angle_to(paddle.basis.orthonormalized().get_rotation_quaternion()))
	if Path._support_mode(pose) == 1:
		var support = player.right_arm_node if pose.paddle_hand == 1 else player.left_arm_node
		var support_basis: Basis = Grip.basis(paddle.basis, pose.paddle_hand == 0, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
		var prior_support: Basis = Grip.basis(_before_basis, previous.paddle_hand == 0, previous.support_grip_rotation_deg - previous.paddle_in_hand_rotation_deg) if Path._support_mode(previous) == 1 else support.hand_mesh.global_basis.orthonormalized()
		var support_clock: Dictionary = support.get_meta("live_support_frame", {})
		if not support_clock.is_empty():
			prior_support = support_clock.start if is_equal_approx(float(support_clock.time), player._support_sim_time) else support_clock.last
		angle = maxf(angle, prior_support.orthonormalized().get_rotation_quaternion().angle_to(support_basis.orthonormalized().get_rotation_quaternion()))
	return angle

static func _encode(player, pose: PostureDefinition, desired: Transform3D) -> PostureDefinition:
	return preload("res://scripts/paddle_pose_encoding.gd").encode(player, pose, desired)

## `paddle_basis`: the pose's world paddle basis when the caller has just computed it.
static func _presented(player, pose: PostureDefinition, paddle_basis = null) -> PostureDefinition:
	var result: PostureDefinition = pose.duplicate(false)
	result.set_meta("live_joint_presented_basis", (paddle_basis as Basis if paddle_basis != null else Path.world_transform(player, pose).basis).orthonormalized())
	return result
