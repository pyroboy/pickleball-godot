extends RefCounted

const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const STANDING_BODY_LIFT: = 0.3
const PELVIS_CENTER: = Vector3(0, Dimensions.PELVIS_CENTER_Y, 0)
const PELVIS_TO_WAIST: = Vector3(0, Dimensions.PELVIS_HALF_HEIGHT + Dimensions.ABDOMEN_LENGTH, 0)
const WAIST_TO_CHEST: = Vector3(0, Dimensions.WAIST_TO_CHEST, 0)

static func _stance_rotation(player, angles: Vector3) -> Basis:
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, - player._get_forward_axis())
	return stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()



static func locomotion_enabled(player, def) -> bool:
	return locomotion_weight(player, def) > 1e-05

static func locomotion_weight(player, def) -> float:
	if def == null or not ("leg_ik" in player) or player.leg_ik == null: return 0.0


	if player.has_method("_between_point_owner") and player._between_point_owner() != null: return 0.0
	if "posture" in player and player.posture != null:
		if player.posture.editor_preview_mode: return 0.0
	# An intentional pre-swing setup may align the pelvis with its latched
	# support frame. Authored held/committed swings and serves keep ownership.
	if "drive_preparation" in player.leg_ik and player.leg_ik.drive_preparation.body_alignment_active:
		return player.leg_ik.locomotion_body_weight
	# Neutral motion and actual captured travel both fade on their own clocks;
	# heading exactly zero never transfers ownership abruptly.
	var motion:float=player.leg_ik.locomotion_body_weight
	var captured:float=clampf(float(def.get_meta("travel_locomotion_weight",0.0)),0.0,1.0)
	if def.has_meta("visual_locomotion_weight"):
		return maxf(captured,clampf(float(def.get_meta("visual_locomotion_weight")),0.0,1.0)*motion)
	if def.posture_id not in [12,20]: return 0.0
	if "posture" in player and player.posture != null:
		if "_committed_incoming_posture" in player.posture and player.posture._committed_incoming_posture >= 0: return 0.0
	if "hitting" in player and player.hitting != null:
		if player.hitting.charge_visual_active or player.hitting.serving_visual_active or player.hitting.is_in_follow_through: return 0.0
	return motion

static func locomotion_turn(player, def) -> float:
	var weight: float = locomotion_weight(player, def)
	if weight <= 0.0: return 0.0
	var turn:float=rad_to_deg(angle_difference(deg_to_rad(def.body_yaw_deg+def.hip_yaw_deg),deg_to_rad(player.leg_ik.locomotion_hip_yaw_deg)))
	var reference:float=player.leg_ik._body_turn_reference_deg
	turn=reference+wrapf(turn-reference,-180.0,180.0)
	return turn*weight

static func requested_position_offset(player, def) -> Vector3:
	if def == null or not "body_position_offset" in def: return Vector3.ZERO
	var offset: Vector3 = def.body_position_offset
	return player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + player._get_forward_axis() * offset.z

static func position_offset(player, def) -> Vector3:
	# The ordinary zero-offset path needs no diagnostic report allocation.
	if def == null or not "body_position_offset" in def or def.body_position_offset == Vector3.ZERO: return Vector3.ZERO
	return position_report(player, def).world_offset

## Shared deterministic cap: the paddle keeps its pre-translation solved target.
## Requested/applied are stance-space metres; world_offset excludes floor fitting.
## Optional feet describe existing live plants, rather than the settled targets.
static func position_report(player, def, feet: Array = []) -> Dictionary:
	var requested: Vector3 = requested_position_offset(player, def)
	var result := {"requested": def.body_position_offset if def != null and "body_position_offset" in def else Vector3.ZERO,
		"applied": Vector3.ZERO, "world_offset": Vector3.ZERO, "limited": false, "reason": ""}
	if requested == Vector3.ZERO: return result
	# Canonical serve-joint math has axes only, not a live rig or floor. Preserve
	# its authored translation; the real player applies the physical cap later.
	if not "global_position" in player or not "COURT_FLOOR_Y" in player:
		result.applied = result.requested; result.world_offset = requested
		return result
	# Dynamic loading avoids the Path -> BodyPose preload dependency cycle.
	# world_transform explicitly uses the untranslated shoulder and cannot recurse.
	var path: Script = load("res://scripts/stroke_swing_path.gd")
	var paddle: Transform3D = path.world_transform(player, def)
	var pivot: Transform3D = untranslated_pivot_transform(player, def)
	var context: Dictionary = _position_context(player, def, feet)
	var baseline: Dictionary = _position_candidate(player, def, pivot, Vector3.ZERO, feet, context)
	var wrist: Vector3 = WristReach.wrist_world(paddle, def)
	var head: Vector3 = paddle * PaddleSize.HEAD_OFFSET
	var support_wrist := Vector3.INF
	var support_budget := 0.7
	if path._support_mode(def) == 1:
		var is_left: bool = def.paddle_hand == 0
		var support_offset: Vector3 = def.left_hand_offset if is_left else def.right_hand_offset
		support_wrist = paddle * (PaddleSize.SUPPORT_GRIP_OFFSET + Vector3.UP * def.support_grip_slide_m)
		support_wrist += player._get_forehand_axis() * support_offset.x + Vector3.UP * support_offset.y + player._get_forward_axis() * support_offset.z
		support_wrist += GripFrame.basis(paddle.basis, is_left, def.support_grip_rotation_deg - def.paddle_in_hand_rotation_deg) * WristReach.socket(is_left)
		var arm_key: String = "left_arm_node" if is_left else "right_arm_node"
		if arm_key in player:
			var arm = player.get(arm_key)
			if arm != null: support_budget = arm.upper_arm_length + arm.forearm_length
	var limits := {"wrist": maxf(WristReach.link_budget(player, def), baseline.shoulder.distance_to(wrist)) + 0.00001,
		"head": maxf(PaddleReach.MAX_HEAD_DISTANCE, baseline.shoulder.distance_to(head)) + 0.00001,
		"raw_head": maxf(PaddleReach.MAX_HEAD_DISTANCE, baseline.raw_shoulder.distance_to(head)) + 0.00001,
		"legs": baseline.leg_spans, "leg_heights": baseline.leg_heights,
		"support_wrist": support_wrist, "support_budget": maxf(support_budget, baseline.support_shoulder.distance_to(support_wrist)) + .00001 if support_wrist.is_finite() else INF}
	# Existing live plants can further restrict an already capped settled pose,
	# but must not expand it and thereby move its new authored foot targets.
	var desired: Vector3 = position_report(player, def).world_offset if feet.size() == 2 else requested
	var candidate: Dictionary = _position_candidate(player, def, pivot, desired, feet, context)
	var scale := 1.0
	if not _position_fits(candidate, wrist, head, limits):
		var low := 0.0; var high := 1.0
		for iteration in range(16):
			var middle: float = (low + high) * .5
			if _position_fits(_position_candidate(player, def, pivot, desired * middle, feet, context), wrist, head, limits): low = middle
			else: high = middle
		scale = low
		candidate = _position_candidate(player, def, pivot, desired * scale, feet, context)
	var effective: Vector3 = candidate.origin - baseline.origin
	result.world_offset = desired * scale
	result.applied = Vector3(effective.dot(player._get_forehand_axis()), effective.y, effective.dot(player._get_forward_axis()))
	result.limited = result.applied.distance_to(result.requested) > .0001
	if result.limited: result.reason = "Reach / planted-foot limit" if scale < .9999 else "Grounded leg-height limit"
	return result

static func _position_fits(candidate: Dictionary, wrist: Vector3, head: Vector3, limits: Dictionary) -> bool:
	if candidate.shoulder.distance_to(wrist) > limits.wrist: return false
	if candidate.shoulder.distance_to(head) > limits.head or candidate.raw_shoulder.distance_to(head) > limits.raw_head: return false
	if limits.support_wrist.is_finite() and candidate.support_shoulder.distance_to(limits.support_wrist) > limits.support_budget: return false
	var length: float = (Dimensions.THIGH_LENGTH + Dimensions.SHIN_LENGTH) * .985
	for side in range(2):
		if candidate.leg_spans[side] > maxf(length, limits.legs[side]) + .00001: return false
		if candidate.leg_heights[side] < minf(.15, limits.leg_heights[side]) - .00001: return false
	return true

# These frames and contact anchors are invariant during one synchronous cap
# search. Keep them invocation-local so edits, handedness and live plants
# are observed immediately by the next call.
static func _position_context(player, def, feet: Array) -> Dictionary:
	var fh: Vector3 = player._get_forehand_axis()
	var fwd: Vector3 = player._get_forward_axis()
	var foot_targets: Array[Vector3] = []
	var hip_locals: Array[Vector3] = []
	for index in range(2):
		var side: float = 1.0 if index == 0 else -1.0
		hip_locals.append(Vector3.UP * (Dimensions.HIP_HEIGHT - Dimensions.PELVIS_CENTER_Y) + fh * side * Dimensions.HIP_HALF_WIDTH)
		var foot: Vector3
		if feet.size() == 2: foot = feet[index]
		else:
			var lead: bool = (index == 0 and def.lead_foot == 0) or (index == 1 and def.lead_foot == 1)
			var authored: Vector3 = def.right_foot_offset if index == 0 else def.left_foot_offset
			var lateral: float = maxf(.09, def.stance_width * .5 + authored.x * side) * side
			foot = player.global_position + fh * lateral + fwd * ((def.front_foot_forward if lead else def.back_foot_back) + authored.z)
			foot.y = PickleballConstants.FLOOR_Y + .04 + maxf(authored.y, 0.0)
		foot_targets.append(foot)
	return {"pelvis": pelvis_transform(player, def), "torso": torso_transform(player, def),
		"main_shoulder": shoulder_local(player, def, -1.0 if def.paddle_hand == 1 else 1.0),
		"support_shoulder": shoulder_local(player, def, 1.0 if def.paddle_hand == 1 else -1.0),
		"feet": foot_targets, "hips": hip_locals}

static func _position_candidate(player, def, pivot: Transform3D, offset: Vector3, feet: Array, context: Dictionary = {}) -> Dictionary:
	if context.is_empty(): context = _position_context(player, def, feet)
	var translated := pivot; translated.origin += offset
	var world: Transform3D = player.global_transform * translated
	var pelvis: Transform3D = context.pelvis
	var lower := 0.0
	var spans: Array[float] = []
	var heights: Array[float] = []
	for index in range(2):
		var hip: Vector3 = world * pelvis * context.hips[index]
		var foot: Vector3 = context.feet[index]
		var horizontal: float = Vector2(hip.x - foot.x, hip.z - foot.z).length()
		spans.append(horizontal)
		heights.append(hip.y - foot.y)
		var length: float = (Dimensions.THIGH_LENGTH + Dimensions.SHIN_LENGTH) * .985
		lower = maxf(lower, hip.y - foot.y - sqrt(maxf(0.0, length * length - horizontal * horizontal)))
	var raw_shoulder: Vector3 = world * context.torso * context.main_shoulder
	var support_shoulder: Vector3 = world * context.torso * context.support_shoulder
	for index in range(heights.size()): heights[index] -= lower
	return {"origin": translated.origin - Vector3.UP * lower, "raw_shoulder": raw_shoulder,
		"shoulder": raw_shoulder - Vector3.UP * lower, "support_shoulder": support_shoulder - Vector3.UP * lower, "leg_spans": spans, "leg_heights": heights}

static func foot_position_offset(_player, _def) -> Vector3:
	# Body/hip/torso edits never author new court contacts. Explicit stance and
	# foot channels remain the sole authored placement controls.
	return Vector3.ZERO

static func has_position_edit(def) -> bool:
	if def == null or not "body_position_offset" in def: return false
	if def.body_position_offset != Vector3.ZERO: return true
	# Keep the same constrained solver across the entire edited path, including
	# a zero-valued endpoint or an intermediate crossing through zero.
	for key in [def.windup_body, def.follow_through_body]:
		if key != null and key.get("values") is Dictionary and key.values.get("body_position_offset", Vector3.ZERO) != Vector3.ZERO: return true
	return false

static func pivot_transform(player, def) -> Transform3D:
	var result: Transform3D = untranslated_pivot_transform(player, def)
	result.origin += position_offset(player, def)
	return result

static func untranslated_pivot_transform(player, def) -> Transform3D:
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, - player._get_forward_axis())
	var canonical: = Basis.from_euler(Vector3( - def.body_pitch_deg, - def.body_yaw_deg, def.body_roll_deg) * (PI / 180.0))
	var basis: Basis = stance * canonical * stance.inverse()
	var origin: Vector3 = player._get_forward_axis() * def.weight_shift * 0.1 + Vector3.UP * (STANDING_BODY_LIFT - def.crouch_amount)
	origin += player._get_forehand_axis() * clampf(float(def.get_meta("charged_load_lateral", 0.0)), -0.055, 0.055)
	return Transform3D(basis, origin)




static func pelvis_transform(player, def, use_locomotion: bool = true) -> Transform3D:
	return Transform3D(_stance_rotation(player, Vector3(0, -(def.hip_yaw_deg+(locomotion_turn(player,def) if use_locomotion else 0.0)), 0)), PELVIS_CENTER)

static func abdomen_transform(player, def, use_locomotion: bool = true) -> Transform3D:
	var bend: = _stance_rotation(player, Vector3( - def.spine_curve_deg * Dimensions.ABDOMEN_BEND_SHARE, 0, 0))
	return pelvis_transform(player, def, use_locomotion) * Transform3D(bend, Vector3(0, Dimensions.PELVIS_HALF_HEIGHT, 0))

static func waist_transform(player, def, use_locomotion: bool = true) -> Transform3D:
	var bend: = _stance_rotation(player, Vector3( - def.spine_curve_deg * (1.0 - Dimensions.ABDOMEN_BEND_SHARE), 0, 0))
	return abdomen_transform(player, def, use_locomotion) * Transform3D(bend, Vector3(0, Dimensions.ABDOMEN_LENGTH, 0))

static func torso_transform(player, def, use_locomotion: bool = true) -> Transform3D:
	var weight:float=locomotion_weight(player,def) if use_locomotion else 0.0
	var counterturn: float = sin(deg_to_rad(player.leg_ik.locomotion_hip_yaw_deg))*30.0*weight if weight > 0.0 else 0.0
	var bend: = _stance_rotation(player, Vector3( - (28.0 + def.torso_pitch_deg), - def.torso_yaw_deg + counterturn, def.torso_roll_deg))
	return waist_transform(player, def, use_locomotion) * Transform3D(bend, Vector3.ZERO) * Transform3D(Basis.IDENTITY, WAIST_TO_CHEST)

static func shoulder_local(player, def, side: float) -> Vector3:
	return player._get_forehand_axis() * side * Dimensions.SHOULDER_HALF_WIDTH + Vector3.UP * Dimensions.SHOULDER_ABOVE_CHEST + player._get_forward_axis() * clampf(def.shoulder_protraction_m, 0.0, 0.05)

static func shoulder_world(player, def, actual_body_transform = null, include_position: bool = true) -> Vector3:
	var side: float = -1.0 if def.paddle_hand == 1 else 1.0
	var local: Vector3 = shoulder_local(player, def, side)
	var root: Transform3D = player.global_transform * (pivot_transform(player, def) if include_position else untranslated_pivot_transform(player, def)) if actual_body_transform == null else actual_body_transform
	return root * torso_transform(player, def) * local

static func apply(player, def) -> void :
	if player.body_pivot == null: return
	player.body_pivot.transform = pivot_transform(player, def)
	player.body_pivot.set_meta("pose_body_position_applied", player.body_pivot.position - untranslated_pivot_transform(player, def).origin)
	var chest_transform: Transform3D = torso_transform(player, def)
	var pelvis: Transform3D = pelvis_transform(player, def)
	var torso: Node3D = player.body_pivot.get_node_or_null("TorsoMesh")
	if torso:
		torso.transform = chest_transform
		var head: Node3D = torso.get_node_or_null("HeadMesh")
		if head:
			head.rotation_degrees = Vector3(def.head_pitch_deg * player._get_swing_sign(), - def.head_yaw_deg, 0)
	var hips: Node3D = player.body_pivot.get_node_or_null("HipsMesh")
	if hips: hips.transform = pelvis
	var skin = player.body_pivot.get_meta("articulated_torso") if player.body_pivot.has_meta("articulated_torso") else null
	if skin: skin.update_frames(pelvis, abdomen_transform(player, def), chest_transform)
	for side in [1, -1]:
		var arm = player.right_arm_node if side == 1 else player.left_arm_node
		if arm:
			arm.position = chest_transform * shoulder_local(player, def, float(side))
			arm.rotation_degrees = def.right_shoulder_rotation_deg if side == 1 else def.left_shoulder_rotation_deg
		var leg = player.right_leg_node if side == 1 else player.left_leg_node
		if leg:
			leg.position = pelvis * (Vector3.UP * (Dimensions.HIP_HEIGHT - Dimensions.PELVIS_CENTER_Y) + player._get_forehand_axis() * side * Dimensions.HIP_HALF_WIDTH)
