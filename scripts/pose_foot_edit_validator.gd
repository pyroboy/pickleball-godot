extends RefCounted
## Read-only edit transaction validation. The caller simulates a candidate on its
## isolated rig, validates it, then restores its baseline before committing data.
## 20 micrometres covers floating-point IK noise, not visible foot movement.
const POSITION_TOLERANCE_M := .00002
const ANGLE_TOLERANCE_RAD := .00002

static func snapshot(player) -> Dictionary:
	var feet: Array[Dictionary] = []
	for right in [true, false]:
		var leg = player.right_leg_node if right else player.left_leg_node
		var anchor: Vector3 = player.leg_ik.right_foot_smooth if right else player.leg_ik.left_foot_smooth
		var locked: bool = player.leg_ik.right_foot_locked if right else player.leg_ik.left_foot_locked
		var report: Dictionary = leg.reach_report.duplicate(true) if "reach_report" in leg else {}
		var requested: float = float(report.get("requested_distance", leg.thigh_pivot.global_position.distance_to(anchor)))
		var applied: float = float(report.get("applied_distance", requested))
		feet.append({"side": "Right" if right else "Left", "anchor": anchor, "ankle": leg.foot_pivot.global_position,
			"yaw": leg.foot_pivot.global_rotation.y, "planted": locked,
			"reach_excess": absf(requested-applied), "anchor_error": leg.foot_pivot.global_position.distance_to(anchor),
			"reach": report})
	return {"root": player.global_transform, "feet": feet, "body_position": player.body_pivot.position}

static func validate(player, candidate_pose, baseline: Dictionary) -> Dictionary:
	return compare(snapshot(player), candidate_pose, baseline)

static func compare(candidate: Dictionary, candidate_pose, baseline: Dictionary) -> Dictionary:
	var requested: Vector3 = candidate_pose.body_position_offset if candidate_pose != null else Vector3.ZERO
	var result := {"accepted": true, "limited": false, "reason": "", "requested_body_offset": requested,
		"candidate_body_position": candidate.body_position, "baseline_body_position": baseline.body_position,
		"position_tolerance_m": POSITION_TOLERANCE_M, "violations": []}
	var failures: Array[String] = []
	var old_root: Transform3D = baseline.root
	var new_root: Transform3D = candidate.root
	if old_root.origin.distance_to(new_root.origin) > POSITION_TOLERANCE_M or not old_root.basis.is_equal_approx(new_root.basis):
		failures.append("Body edit would move the gameplay root")
	for index in range(2):
		var old: Dictionary = baseline.feet[index]
		var now: Dictionary = candidate.feet[index]
		if not old.planted: continue # Explicit airborne contact belongs to its motion owner.
		var side: String = old.side
		if not now.planted:
			failures.append(side + " planted foot would release")
		if old.anchor.distance_to(now.anchor) > POSITION_TOLERANCE_M:
			failures.append(side + " court anchor would move by %.3f mm" % (old.anchor.distance_to(now.anchor)*1000.0))
		if absf(angle_difference(float(old.yaw), float(now.yaw))) > ANGLE_TOLERANCE_RAD:
			failures.append(side + " planted foot would rotate")
		# Existing impossible authored poses are not made uneditable: accept an
		# unchanged or better error, but never let a body edit worsen it.
		var permitted_reach: float = maxf(POSITION_TOLERANCE_M, float(old.reach_excess) + POSITION_TOLERANCE_M)
		var permitted_error: float = maxf(POSITION_TOLERANCE_M, float(old.anchor_error) + POSITION_TOLERANCE_M)
		if float(now.reach_excess) > permitted_reach:
			failures.append(side + " leg reach would worsen from %.3f to %.3f mm beyond limits" % [float(old.reach_excess)*1000.0, float(now.reach_excess)*1000.0])
		if float(now.anchor_error) > permitted_error:
			failures.append(side + " ankle would miss its planted anchor by %.3f mm (was %.3f mm)" % [float(now.anchor_error)*1000.0, float(old.anchor_error)*1000.0])
		# A previously valid plant must preserve the actual ankle too, not just
		# the hidden target. Inherited invalid ankles may move toward the anchor.
		if float(old.anchor_error) <= POSITION_TOLERANCE_M and old.ankle.distance_to(now.ankle) > POSITION_TOLERANCE_M:
			failures.append(side + " planted ankle would move by %.3f mm" % (old.ankle.distance_to(now.ankle)*1000.0))
	result.accepted = failures.is_empty()
	result.limited = not result.accepted
	result.violations = failures
	if not result.accepted:
		result.reason = "; ".join(failures) + ". Change not applied; reduce the body/hip move or explicitly edit the foot."
	return result
