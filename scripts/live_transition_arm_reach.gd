extends RefCounted
## Live incoming/held/released/recovery blends can leave their endpoints' reach
## envelope after the moving feet lower the body. Keep the accepted paddle and
## both real foot contacts fixed; find the smallest feasible body translation.
## This does not rewrite an authored pose, move a contact, or stretch a limb.
const Reach = preload("res://scripts/paddle_wrist_reach.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ReachProjection = preload("res://scripts/wide_backhand_reach_profile.gd")
const WristBudget = preload("res://scripts/live_arm_budget.gd")
const ARM_RESERVE_M := 0.0001
const MAX_BODY_SHIFT_M := 0.12
# Perf: body-shift search resolution. Was 5 mm x 24 steps + 10 bisections (~0.005 mm,
# far below anything visible) and dominated rally CPU. 1 cm x 12 + 5 bisections = ~0.3 mm.
const SEARCH_STEP_M := 0.01
const SEARCH_STEPS := 12
const SEARCH_BISECTIONS := 5
# Perf: hard cap on candidate wrist-budget checks per solve. In the between-point
# carried-cup case each check costs ~1 ms, and uncapped searches hit ~100 checks
# (100+ ms frames). If nothing fits within the cap the body keeps the base offset.
const MAX_BUDGET_CHECKS := 8
# Between points (cut-scene) each check also tests the carried cup (~0.5 ms); cap lower.
const MAX_BUDGET_CHECKS_BETWEEN := 2
# ...and no bisection refinement there: each between-point check also runs the
# carried-cup lattice (up to ~2.6k elbow tests when it fails). iPhone 15 Pro log:
# 20 checks = 55 ms while the server steps into position.

static func enabled(player, pose) -> bool:
	if pose == null: return false
	if player == null or not player.has_method("_get_ball_ref") or not "posture" in player or not "hitting" in player: return false
	if player.posture == null or player.posture.editor_preview_mode: return false
	if player.has_method("_between_point_owner") and player._between_point_owner() != null:
		return player._between_point_owner().phase == "SET_SERVE"
	var game = player.get_parent()
	if game != null and "game_state" in game and game.game_state in [game.GameState.WAITING, game.GameState.SERVING] and int(pose.posture_id) == 20 and game.get_server_actor() != player:
		return true
	var ball = player._get_ball_ref()
	if ball != null and ball.is_in_play or _serve_cup(player): return true
	# A miss or point-ending bounce does not end a committed visual recovery.
	# Keep its fixed-link/wrist conditioning until that presentation owner exits.
	if player.hitting != null and player.hitting.is_in_follow_through: return true
	var human = player.posture.human_contact
	return human != null and (human.phase >= 0 or human._charge_cancel_recovering)

static func _serve_cup(player) -> bool:
	if player.hitting == null or not player.hitting.serving_visual_active: return false
	if not "arm_ik" in player or player.arm_ik == null or player.arm_ik._hands == null: return false
	var game = player.get_parent()
	if game == null or not "game_serve" in game or game.game_serve == null: return false
	return game.game_state == game.GameState.WAITING and not game.game_serve.is_release_pending() and not game.ball.is_in_play and game.get_server_actor() == player

static func solve(player, pose, feet: Array) -> Dictionary:
	var report := {"active": false, "feasible": true, "world_offset": Vector3.ZERO, "iterations": 0}
	if not enabled(player, pose) or feet.size() != 2 or player.paddle_node == null: return report
	var main = player.left_arm_node if pose.paddle_hand == 1 else player.right_arm_node
	var support = player.right_arm_node if pose.paddle_hand == 1 else player.left_arm_node
	if main == null or support == null: return report
	var paddle: Transform3D = player.paddle_node.global_transform
	var support_left: bool = pose.paddle_hand == 0
	var support_offset: Vector3 = pose.left_hand_offset if support_left else pose.right_hand_offset
	var support_wrist: Vector3 = player.arm_ik.get_support_hand_target(pose)
	support_wrist += player._get_forehand_axis() * support_offset.x + Vector3.UP * support_offset.y + player._get_forward_axis() * support_offset.z
	if Path._support_mode(pose) == 1:
		support_wrist += Grip.basis(paddle.basis, support_left, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg) * Reach.socket(support_left)
	var between = player._between_point_owner() if player.has_method("_between_point_owner") else null
	if between != null and between.has_method("support_wrist_for_body_fit"):
		var carried_wrist: Vector3 = between.support_wrist_for_body_fit(player.get_actor_id())
		if carried_wrist.is_finite(): support_wrist = carried_wrist
	var serve_cup: bool = _serve_cup(player)
	if serve_cup:
		var serve = player.get_parent().game_serve
		var center: Vector3 = serve.get_held_ball_position()
		var charge: float = float(pose.get_meta("serve_phase_charge", serve.get_charge_ratio()))
		var mount: Transform3D = player.arm_ik._hands._serve_grasp_mount(support, center, charge, center.y - player.global_position.y)
		if player.has_meta("carried_cup_continuity"):
			var basis: Basis = _next_carried_cup_basis(player, pose)
			mount = Transform3D(basis, center - basis * support.articulated_hand.cup_ball_center)
		support_wrist = mount * support.articulated_hand.wrist_socket
	var release: Dictionary = _serve_release(player, pose)
	if not release.is_empty(): support_wrist = release.wrist
	var centers: Array[Vector3] = [Reach.wrist_world(paddle, pose) - main.upper_pivot.global_position,
		support_wrist - support.upper_pivot.global_position]
	var radii: Array[float] = [main.upper_arm_length + main.forearm_length - ARM_RESERVE_M,
		support.upper_arm_length + support.forearm_length - ARM_RESERVE_M]
	report["pre_fit_main_reach_m"] = centers[0].length()
	report["pre_fit_support_reach_m"] = centers[1].length()
	for side in range(2):
		var leg = player.right_leg_node if side == 0 else player.left_leg_node
		if leg == null:
			report.feasible = false
			return report
		centers.append(feet[side] - leg.thigh_pivot.global_position)
		radii.append((leg.thigh_length + leg.shin_length) * ReachProjection.LEG_REACH_SHARE)
	var solved: Dictionary = ReachProjection.minimum_translation(centers, radii)
	report.iterations = solved.iterations
	if not release.is_empty():
		# The free hand frame depends on the translated shoulder. Re-evaluate
		# that exact dependency, with a fixed four-projection bound.
		for unused in range(4):
			var next: Dictionary = _serve_release(player, pose, solved.offset)
			centers[1] = next.wrist - support.upper_pivot.global_position
			if ReachProjection._fits(solved.offset, centers, radii): break
			solved = ReachProjection.minimum_translation(centers, radii)
			report.iterations += solved.iterations
		report["release_dependency"] = true
		report["candidate_checks"] = 1
	report.feasible = solved.feasible and solved.offset.length() <= MAX_BODY_SHIFT_M
	if report.feasible:
		var offset: Vector3 = solved.offset
		if (not serve_cup or player.has_meta("carried_cup_continuity")) and not _wrist_budgets_fit(player, pose, paddle, offset):
			# Slight knee flexion changes the shoulder-to-fixed-grip geometry
			# enough to admit a legal elbow plane, including the live Ready
			# entry. Lowering preserves grounded contacts and never lengthens
			# a leg. Search is bounded by the existing body-translation cap.
			var found := false
			var checks := 0
			var max_checks: int = MAX_BUDGET_CHECKS_BETWEEN if between != null else MAX_BUDGET_CHECKS
			var best := Vector3.INF
			var directions: Array[Vector3] = [Vector3.DOWN, (Vector3.DOWN - player._get_forward_axis()).normalized(), (Vector3.DOWN + player._get_forward_axis()).normalized(),
				(Vector3.DOWN + player._get_forehand_axis()).normalized(), (Vector3.DOWN - player._get_forehand_axis()).normalized()]
			for direction in directions:
				if checks >= max_checks: break
				for index in range(1, SEARCH_STEPS + 1):
					var trial: Vector3 = offset + direction * float(index) * SEARCH_STEP_M
					if trial.length() > MAX_BODY_SHIFT_M or (found and trial.length() >= best.length()): break
					if not release.is_empty(): report.candidate_checks += 1
					if checks >= max_checks: break
					checks += 1
					if not _targets_fit(player, pose, trial, centers, radii, not release.is_empty()) or not _wrist_budgets_fit(player, pose, paddle, trial): continue
					var low := float(index - 1) * SEARCH_STEP_M; var high := float(index) * SEARCH_STEP_M
					for unused in range(0 if between != null else SEARCH_BISECTIONS):
						var middle := (low + high) * .5
						var candidate: Vector3 = offset + direction * middle
						if not release.is_empty(): report.candidate_checks += 1
						if _targets_fit(player, pose, candidate, centers, radii, not release.is_empty()) and _wrist_budgets_fit(player, pose, paddle, candidate): high = middle
						else: low = middle
					best = offset + direction * high
					found = true
					break
			if found: offset = best
			report["wrist_budget_feasible"] = found
		else: report["wrist_budget_feasible"] = true
		if not release.is_empty() and (not bool(report.get("wrist_budget_feasible", false)) or not _targets_fit(player, pose, offset, centers, radii, true)):
			report.feasible = false
			return report
		report.world_offset = offset
		report.active = offset.length_squared() > 1e-12
	return report

static func _wrist_budgets_fit(player, pose, paddle: Transform3D, offset: Vector3) -> bool:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_wrist_budgets_fit(player, pose, paddle, offset)
	PerfMonitor.record("reach.wrist_budgets_fit", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_wrist_budgets_fit(player, pose, paddle: Transform3D, offset: Vector3) -> bool:
	for side in range(2):
		var main: bool = side == pose.paddle_hand
		if not main and Path._support_mode(pose) != 1: continue
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var left: bool = side == 1
		var hand_offset: Vector3 = pose.left_hand_offset if left else pose.right_hand_offset
		var rotation: float = pose.main_grip_rotation_deg if main else pose.support_grip_rotation_deg
		var basis: Basis = Grip.basis(paddle.basis, left, rotation - pose.paddle_in_hand_rotation_deg)
		var grip: Vector3 = paddle * (D.MAIN_GRIP_OFFSET + hand_offset) if main else paddle * (D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m)
		if not main: grip += player._get_forehand_axis() * hand_offset.x + Vector3.UP * hand_offset.y + player._get_forward_axis() * hand_offset.z
		var wrist: Vector3 = grip + basis * Reach.socket(left)
		if not preload("res://scripts/arm_budget_acceptance.gd").accepts(arm.upper_pivot.global_position + offset, wrist, arm.forearm_pivot.global_position + offset,
			basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left, .98): return false
	var release: Dictionary = _serve_release(player, pose, offset)
	if not release.is_empty():
		var arm = player.right_arm_node if int(release.side) == 0 else player.left_arm_node
		if not preload("res://scripts/arm_budget_acceptance.gd").accepts(arm.upper_pivot.global_position + offset, release.wrist, arm.forearm_pivot.global_position + offset,
			release.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, int(release.side) == 1, .98): return false
	var carried: Dictionary = _carried_cup_frame(player, pose)
	if not carried.is_empty():
		var arm = player.left_arm_node
		var fit: Dictionary = WristBudget.solve(arm.upper_pivot.global_position + offset, carried.wrist, carried.elbow, carried.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, true)
		if not fit.feasible:
			var between = player._between_point_owner() if player.has_method("_between_point_owner") else null
			if between == null or not between.has_method("cup_can_fit_body_offset") or not between.cup_can_fit_body_offset(player.get_actor_id(), offset): return false
	return true

static func _carried_cup_frame(player, pose = null) -> Dictionary:
	var between = player._between_point_owner() if player.has_method("_between_point_owner") else null
	if between != null and between.has_method("support_cup_frame_for_body_fit"):
		return between.support_cup_frame_for_body_fit(player.get_actor_id())
	if not _serve_cup(player) or not player.has_meta("carried_cup_continuity"): return {}
	var state: Dictionary = player.get_meta("carried_cup_continuity")
	var model = player.left_arm_node.articulated_hand
	var center: Vector3 = player.get_parent().game_serve.get_held_ball_position()
	var basis: Basis = _next_carried_cup_basis(player, pose)
	return {"wrist": center + basis * (model.wrist_socket - model.cup_ball_center), "basis": basis, "elbow": state.elbow}

static func _next_carried_cup_basis(player, pose) -> Basis:
	var state: Dictionary = player.get_meta("carried_cup_continuity")
	var same_tick: bool = int(state.tick) == Engine.get_physics_frames() and state.has("frame_basis")
	var previous: Basis = state.frame_basis if same_tick else state.basis
	var serve = player.get_parent().game_serve
	var center: Vector3 = serve.get_held_ball_position()
	var charge: float = float(pose.get_meta("serve_phase_charge", serve.get_charge_ratio())) if pose != null else serve.get_charge_ratio()
	var target: Transform3D = player.arm_ik._hands._serve_grasp_mount(player.left_arm_node, center, charge, center.y - player.global_position.y)
	var angle: float = previous.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion())
	var step: float = deg_to_rad(600.0) * player.get_physics_process_delta_time()
	return previous.slerp(target.basis, minf(1.0, step / maxf(angle, .000001)))

static func apply(player, pose, feet: Array) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_apply(player, pose, feet)
	PerfMonitor.record("leg.live_arm_reach", Time.get_ticks_usec() - _pt)

static func _perf_apply(player, pose, feet: Array) -> void:
	if player.body_pivot == null: return
	var report: Dictionary = solve(player, pose, feet)
	player.body_pivot.set_meta("live_transition_arm_reach", report)
	if not report.active or not report.feasible: return
	var paddle: Transform3D = player.paddle_node.global_transform
	player.body_pivot.global_position += report.world_offset
	player.paddle_node.global_transform = paddle

static func _targets_fit(player, pose, offset: Vector3, centers: Array[Vector3], radii: Array[float], release: bool) -> bool:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_targets_fit(player, pose, offset, centers, radii, release)
	PerfMonitor.record("reach.targets_fit", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_targets_fit(player, pose, offset: Vector3, centers: Array[Vector3], radii: Array[float], release: bool) -> bool:
	if not release: return ReachProjection._fits(offset, centers, radii)
	var frame: Dictionary = _serve_release(player, pose, offset)
	if frame.is_empty(): return false
	var support = player.right_arm_node if int(frame.side) == 0 else player.left_arm_node
	var actual: Array[Vector3] = centers.duplicate()
	actual[1] = frame.wrist - support.upper_pivot.global_position
	return ReachProjection._fits(offset, actual, radii)

# Startup frames can run before arm IK has built its hands; treat that as "no release".
static func _serve_release(player, pose, offset := Vector3.ZERO) -> Dictionary:
	if not "arm_ik" in player or player.arm_ik == null or player.arm_ik._hands == null: return {}
	return player.arm_ik._hands.preview_serve_release(pose, offset)
