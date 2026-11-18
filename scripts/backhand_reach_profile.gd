extends RefCounted
## Approved follow-up to the 2026-10-02 ID 2 import: keep the complete paddle
## trajectory and both seated grips fixed; move only the body over its feet.
## This is a solved presentation delta, never a rewrite of the source JSON,
## stroke keys, arm lengths, or foot targets. See docs/BACKHAND_REACH_0_3_14.md.
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const ARM_RESERVE_M := 0.0001
const LEG_REACH_SHARE := 0.985
const MAX_BODY_SHIFT_M := 0.12
const SOLVE_TOLERANCE_M := 0.000001
const MAX_ITERATIONS := 96

static func enabled(def) -> bool:
	return def != null and def.posture_id == 2 and def.family == 1 and def.left_hand_mode == 1

## Called after ordinary body/floor fitting and before the ordinary leg IK pass.
## All spheres live in translation-space: each is the set of body translations
## that puts a particular shoulder/hip within its unchanged limb-link budget.
## Dykstra's projection finds the least squared-distance translation in their
## convex intersection. Plain sequential clamping would depend on arm order.
static func solve(player, def, feet: Array) -> Dictionary:
	var report := {"active": false, "feasible": true, "world_offset": Vector3.ZERO, "iterations": 0}
	if not enabled(def) or feet.size() != 2 or player.paddle_node == null: return report
	var paddle: Transform3D = player.paddle_node.global_transform
	var main = player.left_arm_node if def.paddle_hand == 1 else player.right_arm_node
	var support = player.right_arm_node if def.paddle_hand == 1 else player.left_arm_node
	if main == null or support == null: return report
	var support_left: bool = def.paddle_hand == 0
	var support_offset: Vector3 = def.left_hand_offset if support_left else def.right_hand_offset
	var support_anchor: Vector3 = paddle * (PaddleSize.SUPPORT_GRIP_OFFSET + Vector3.UP * def.support_grip_slide_m)
	support_anchor += player._get_forehand_axis() * support_offset.x + Vector3.UP * support_offset.y + player._get_forward_axis() * support_offset.z
	var support_wrist: Vector3 = support_anchor + GripFrame.basis(paddle.basis, support_left, def.support_grip_rotation_deg - def.paddle_in_hand_rotation_deg) * WristReach.socket(support_left)
	var centers: Array[Vector3] = [WristReach.wrist_world(paddle, def) - main.upper_pivot.global_position,
		support_wrist - support.upper_pivot.global_position]
	var radii: Array[float] = [main.upper_arm_length + main.forearm_length - ARM_RESERVE_M,
		support.upper_arm_length + support.forearm_length - ARM_RESERVE_M]
	# Zero is exact whenever the authored arms already fit. In particular this
	# leaves every already reachable authored sample intact.
	if centers[0].length() <= radii[0] and centers[1].length() <= radii[1]: return report
	report.active = true
	for side in range(2):
		var leg = player.right_leg_node if side == 0 else player.left_leg_node
		if leg == null:
			report.feasible = false
			return report
		centers.append(feet[side] - leg.thigh_pivot.global_position)
		radii.append((leg.thigh_length + leg.shin_length) * LEG_REACH_SHARE)
	var projected: Dictionary = minimum_translation(centers, radii)
	report.iterations = projected.iterations
	report.feasible = projected.feasible and projected.offset.length() <= MAX_BODY_SHIFT_M
	if report.feasible: report.world_offset = projected.offset
	return report

static func minimum_translation(centers: Array[Vector3], radii: Array[float]) -> Dictionary:
	var offset := Vector3.ZERO
	var residuals: Array[Vector3] = []
	for unused in centers: residuals.append(Vector3.ZERO)
	var iterations := 0
	for iteration in range(MAX_ITERATIONS):
		var previous := offset
		for index in range(centers.size()):
			var trial: Vector3 = offset + residuals[index]
			var span: Vector3 = trial - centers[index]
			var projected: Vector3 = trial if span.length() <= radii[index] else centers[index] + span.normalized() * radii[index]
			residuals[index] = trial - projected
			offset = projected
		iterations = iteration + 1
		if offset.distance_to(previous) <= SOLVE_TOLERANCE_M * .1 and _fits(offset, centers, radii): break
	return {"offset": offset, "feasible": _fits(offset, centers, radii), "iterations": iterations}

static func _fits(offset: Vector3, centers: Array[Vector3], radii: Array[float]) -> bool:
	if not offset.is_finite(): return false
	for index in range(centers.size()):
		if offset.distance_to(centers[index]) > radii[index] + SOLVE_TOLERANCE_M: return false
	return true

static func apply(player, def, feet: Array) -> void:
	if player.body_pivot == null: return
	if enabled(def):
		# Node3D.look_at preserves scale, including accumulated single-precision
		# roundoff from past solves. These are rotation-only rig pivots: restore
		# their unit-basis invariant, never change either nominal link length.
		for arm in [player.right_arm_node, player.left_arm_node]:
			if arm != null:
				arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
				arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
	var report: Dictionary = solve(player, def, feet)
	player.body_pivot.set_meta("backhand_reach_report", report)
	if not report.active or not report.feasible: return
	var paddle: Transform3D = player.paddle_node.global_transform
	player.body_pivot.global_position += report.world_offset
	# The paddle is parented beneath the body. Restore its exact world transform
	# before the existing leg and hand solvers run against their original targets.
	player.paddle_node.global_transform = paddle
