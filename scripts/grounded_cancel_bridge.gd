extends RefCounted
## Contact-free bridge from the current supported reach into ordinary movement.
## Root/step clocks belong to normal Player movement immediately; this module
## blends actual rig channels and re-solves both arms and current foot anchors.
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
const Feet = preload("res://scripts/pose_foot_contacts.gd")
const Floor = preload("res://scripts/paddle_floor_geometry.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")
const DURATION := 0.20
var actor
var helper
var active := false
var elapsed := 0.0
var weight := 0.0
var status := "idle"
var target_pose: PostureDefinition
var source: Dictionary = {}
var target_channels: Array = []
var last_report: Dictionary = {}
var last_failure := ""
var rejected_steps := 0
var _hands = Hands.new()

func begin(player, reach, pose: PostureDefinition, channels: Array) -> void:
	actor = player; helper = reach; target_pose = pose.duplicate(true)
	_hands.initialize(actor)
	target_channels = channels.duplicate(true)
	source = _capture()
	active = true; elapsed = 0.0; weight = 0.0; status = "moving; recovering paddle"

func step(delta: float) -> bool:
	if not active: return true
	elapsed += maxf(delta, 0.0)
	# This is the ordinary moving stance solver, using the actual handed-off
	# court contacts. It chooses real steps rather than translating shoes.
	actor.posture.force_posture_update(target_pose, false)
	actor.leg_ik.update_leg_ik(actor._consume_support_delta(), target_pose)
	actor.arm_ik.update_arm_ik(delta, target_pose)
	var target := _capture()
	# The actual entry channels were admitted before this action began. A
	# changed rally can disable normal live READY fitting during recovery;
	# return through the captured safe channels instead of inheriting that
	# newly generated invalid orientation. Root and foot stepping stay live.
	for side in [0, 1]:
		if not target.arms[side].channels.within_animation_budget:
			target.arms[side].channels = target_channels[side]
	var next := minf(smoothstep(0.0, DURATION, elapsed), weight + maxf(delta, 0.0) * 7.5)
	if not _apply(source, target, next):
		# Never make an invalid blend visible. The caller rolls back this normal
		# movement tick to its previous actual pose/contact state if necessary.
		rejected_steps += 1
		status = "movement limited while physical pose recovers"
		return false
	weight = next
	if weight >= 0.999999:
		active = false; status = "normal movement and pose recovered"
	return true

func _capture() -> Dictionary:
	var body: Node3D = actor.body_pivot
	var skin = body.get_meta("articulated_torso")
	var result := {"body": body.transform, "torso": body.get_node("TorsoMesh").transform,
		"hips": body.get_node("HipsMesh").transform, "pelvis": skin._last_pelvis,
		"abdomen": skin._last_abdomen, "chest": skin._last_chest, "arms": [], "feet": []}
	for side in [0, 1]:
		var arm = actor.right_arm_node if side == 0 else actor.left_arm_node
		var model = arm.articulated_hand
		var bones: Array[Quaternion] = []
		for bone in range(model.WRIST_BRIDGE_BONE): bones.append(model.skeleton.get_bone_pose_rotation(bone))
		var fields: Dictionary = {}
		for key in ["_mode", "_closure", "_index_closure", "_support_style_weight", "_recovery_pose_key"]: fields[key] = model.get(key)
		result.arms.append({"base": arm.transform, "wrist": arm.anatomical_wrist_world - actor.global_position,
			"elbow": arm.forearm_pivot.global_position - actor.global_position,
			"channels": Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, arm.anatomical_wrist_world, side == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign),
			"bones": bones, "fields": fields})
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		result.feet.append({"transform": leg.foot_pivot.global_transform, "knee": leg.shin_pivot.global_position})
	result["grip_basis"] = actor.paddle_node.global_basis.inverse() * actor.right_arm_node.hand_mesh.global_basis
	result["grip_anchor"] = actor.paddle_node.to_local(actor.right_arm_node.hand_mesh.global_position)
	return result

func _apply(from: Dictionary, to: Dictionary, amount: float) -> bool:
	var body: Node3D = actor.body_pivot
	body.transform = Transform3D(from.body).interpolate_with(to.body, amount)
	body.get_node("TorsoMesh").transform = Transform3D(from.torso).interpolate_with(to.torso, amount)
	body.get_node("HipsMesh").transform = Transform3D(from.hips).interpolate_with(to.hips, amount)
	body.get_meta("articulated_torso").update_frames(Transform3D(from.pelvis).interpolate_with(to.pelvis, amount), Transform3D(from.abdomen).interpolate_with(to.abdomen, amount), Transform3D(from.chest).interpolate_with(to.chest, amount))
	for side in [0, 1]:
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var anchor: Transform3D = to.feet[side].transform
		if not Feet.reach_report(leg.thigh_pivot.global_position, anchor.origin, leg.thigh_length, leg.shin_length).feasible: return _fail("leg reach side " + str(side))
		leg.solve_ik(anchor.origin, to.feet[side].knee, 0.0)
		leg.foot_pivot.global_basis = anchor.basis
		leg._keep_sole_above_floor()
		if leg.foot_pivot.global_position.distance_to(anchor.origin) > 0.00002: return _fail("sole anchor side " + str(side))
		var arm = actor.right_arm_node if side == 0 else actor.left_arm_node
		var start: Dictionary = from.arms[side]; var finish: Dictionary = to.arms[side]
		arm.transform = Transform3D(start.base).interpolate_with(finish.base, amount)
		var wrist: Vector3 = actor.global_position + Vector3(start.wrist).lerp(finish.wrist, amount)
		var pole: Vector3 = actor.global_position + Vector3(start.elbow).lerp(finish.elbow, amount)
		var distance: float = wrist.distance_to(arm.upper_pivot.global_position)
		if distance > arm.upper_arm_length + arm.forearm_length - 0.001 or distance < 0.002: return _fail("arm reach side " + str(side))
		arm.upper_pivot.basis = Basis.IDENTITY; arm.forearm_pivot.basis = Basis.IDENTITY
		arm.solve_ik(wrist, pole, Transform3D.IDENTITY, wrist)
		var model = arm.articulated_hand
		var reference: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, side == 1)
		var axial := deg_to_rad(lerpf(start.channels.forearm_axial_deg, finish.channels.forearm_axial_deg, amount) / model.radial_sign)
		var flex := deg_to_rad(lerpf(start.channels.flexion_deg, finish.channels.flexion_deg, amount))
		var deviation := deg_to_rad(lerpf(start.channels.radial_deviation_deg, finish.channels.radial_deviation_deg, amount) / model.radial_sign)
		var anatomical := reference * Basis(Vector3.RIGHT, axial) * Basis(Vector3.UP, flex) * Basis(Vector3.BACK, deviation)
		var mount := Transform3D(anatomical * model.anatomical_basis.inverse(), Vector3.ZERO)
		mount.origin = wrist - mount.basis * model.wrist_socket
		_hands.apply_mount(arm, mount)
		if side == 0:
			var grip: Basis = Basis(from.grip_basis).slerp(to.grip_basis, amount).orthonormalized()
			var anchor_in_paddle: Vector3 = Vector3(from.grip_anchor).lerp(to.grip_anchor, amount)
			var basis: Basis = mount.basis * grip.inverse()
			actor.paddle_node.global_transform = Transform3D(basis, mount.origin - basis * anchor_in_paddle)
			helper._last_grip_basis = grip; helper._last_grip_anchor = anchor_in_paddle
		for bone in range(1, model.WRIST_BRIDGE_BONE):
			model.skeleton.set_bone_pose_rotation(bone, Quaternion(start.bones[bone]).slerp(finish.bones[bone], amount)); model.bone_pose_write_count += 1
		model.pose_update_count += 1
		if amount >= 0.999999:
			for key in finish.fields: model.set(key, finish.fields[key])
		else:
			model._mode = "RECOVERY"; model._recovery_pose_key = Vector4(-1, -1, -1, -1)
	var paddle: Transform3D = actor.paddle_node.global_transform
	if (paddle * Paddle.HEAD_OFFSET).y - Floor.head_clearance(paddle.basis) < PickleballConstants.FLOOR_Y - 0.00002: return _fail("paddle floor")
	helper._feet_planted[0] = actor.leg_ik.right_foot_locked; helper._feet_planted[1] = actor.leg_ik.left_foot_locked
	last_report = displayed_report()
	if not last_report.valid: return _fail("displayed rig: " + JSON.stringify(last_report))
	return true

func displayed_report() -> Dictionary:
	var result: Dictionary = helper.displayed_report()
	# Strike admission requires planted support. Cancellation has already
	# closed both contact windows and handed the root to ordinary locomotion;
	# the existing running gait includes short, explicit flight phases.
	var actual_sole_support := false
	for foot in result.feet:
		actual_sole_support = actual_sole_support or absf(float(foot.sole_y) - PickleballConstants.FLOOR_Y) <= 0.002
	var gait_flight: bool = actor.leg_ik._run_active
	result["locomotion_sole_support"] = actual_sole_support
	result["locomotion_flight"] = gait_flight and not result.grounded
	result["contact_admissible"] = false
	result.valid = result.main_hand_seated and (result.grounded or actual_sole_support or gait_flight)
	for arm in result.arms: result.valid = result.valid and arm.valid
	for foot in result.feet: result.valid = result.valid and foot.valid
	return result

func _fail(reason: String) -> bool:
	last_failure = reason
	return false
