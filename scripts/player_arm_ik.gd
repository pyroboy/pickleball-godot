class_name PlayerArmIK extends Node
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const _PostureSkeletonApplier = preload("res://scripts/posture_skeleton_applier.gd")

const ArmAnatomy = preload("res://scripts/arm_anatomy.gd")
const HandPresentation = preload("res://scripts/player_hand_presentation.gd")
const ElbowPreset = preload("res://scripts/elbow_preset_runtime.gd")
const LiveArmBudget = preload("res://scripts/live_arm_budget.gd")
const ElbowSwivel = preload("res://scripts/elbow_swivel.gd")
## Support hand in "Paddle grip" mode: within NEAR metres of the paddle neck it is gripping (its
## elbow is aimed from the wrist); FAR or more off it, the pose's own elbow guide decides.
const SUPPORT_GRIP_ELBOW_NEAR := 0.04
const SUPPORT_GRIP_ELBOW_FAR := 0.16
var _hands
## Experiment switch (Pose Studio, stage 6c step 2): false = the paddle arm's elbow follows the
## authored pole without the wrist correction below. Default true: unchanged game.
static var paddle_elbow_wrist_correction := true
## PICKLEBALL_ELBOW_SWIVEL=0 ignores authored elbow swivels (the game as before them; bench A/B).
static var elbow_swivel_enabled: bool = OS.get_environment("PICKLEBALL_ELBOW_SWIVEL") != "0"
var _player

func _ready() -> void :
	_player = get_parent() as CharacterBody3D

func update_arm_ik(delta: float, def_override = null) -> void:
	if _player != null and _player.posture != null: _player.posture.arm_pending_def = null
	var _pt := Time.get_ticks_usec()
	_perf_update_arm_ik(delta, def_override)
	PerfMonitor.record("arm.ik", Time.get_ticks_usec() - _pt)

func _perf_update_arm_ik(delta: float, def_override = null) -> void:
	if _hands == null:
		_hands = HandPresentation.new()
		_hands.initialize(_player)
	var b = _player._get_ball_ref()
	var def = def_override if def_override != null else _player.get_runtime_posture_def()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var between = _player._between_point_owner() if _player.has_method("_between_point_owner") else null
	var pole_reference_axis: Vector3 = forehand_axis
	if between != null and def != null:
		pole_reference_axis = forehand_axis.rotated(Vector3.UP, -deg_to_rad(def.body_yaw_deg))

	var swivel_record: Array = []   # [arm, wrist, swivel pole]: the drawn elbow, recorded after every arm step
	var support_swivel_record: Array = []   # [arm, wrist, turn deg, is the left arm]
	if _player.paddle_node:
		var left_dominant: bool = def != null and def.paddle_hand == 1
		var dominant_arm = _player.left_arm_node if left_dominant else _player.right_arm_node
		var support_arm = _player.right_arm_node if left_dominant else _player.left_arm_node
		var main_offset: Vector3 = (def.left_hand_offset if left_dominant else def.right_hand_offset) if def else Vector3.ZERO
		var support_offset: Vector3 = (def.right_hand_offset if left_dominant else def.left_hand_offset) if def else Vector3.ZERO
		var main_pole: Vector3 = (def.left_elbow_pole if left_dominant else def.right_elbow_pole) if def else Vector3.ZERO
		var support_pole: Vector3 = (def.right_elbow_pole if left_dominant else def.left_elbow_pole) if def else Vector3.ZERO
		var side: float = -1.0 if left_dominant else 1.0
		var main_target: Vector3 = _player.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET + main_offset)
		var main_pole_world: Vector3 = _player.global_position + forehand_axis * 0.5 * side + Vector3.DOWN + forward_axis * -0.5
		if main_pole.length_squared() > 1e-10:
			main_pole_world = _player.global_position + _PostureSkeletonApplier.stance_offset(main_pole, forehand_axis, forward_axis)
		if dominant_arm and def:
			var shoulder_rotation: Vector3 = def.left_shoulder_rotation_deg if left_dominant else def.right_shoulder_rotation_deg
			main_pole_world = _rotate_shoulder_pole(dominant_arm, main_pole_world, shoulder_rotation)
		if dominant_arm and dominant_arm.has_method("solve_ik"):
			var mount: Transform3D = _hands.main_mount(dominant_arm, main_target, _player.paddle_node.global_basis, def)
			var wrist: Vector3 = HandPresentation.wrist_for(dominant_arm, mount)
			var distal: Vector3 = mount.basis * dominant_arm.articulated_hand.anatomical_basis.x
			main_pole_world = ArmAnatomy.stabilized_pole(dominant_arm.upper_pivot.global_position, wrist, main_pole_world, -pole_reference_axis * side)
			if paddle_elbow_wrist_correction:
				main_pole_world = ArmAnatomy.conditioned_pole(dominant_arm.upper_pivot.global_position, wrist, main_pole_world, distal, dominant_arm.upper_arm_length, dominant_arm.forearm_length)
			# Authored elbow swivel (stage 6c): the pose's angle replaces the guide point by its weight.
			var swivel_weight: float = clampf(float(def.elbow_swivel_weight), 0.0, 1.0) if def != null and "elbow_swivel_weight" in def else 0.0
			var swivel_pole: Vector3 = Vector3.INF   # INF = draw the solved elbow
			if swivel_weight > 0.0 and elbow_swivel_enabled:
				var chest: Array = ElbowSwivel.frame(def, forehand_axis, forward_axis, left_dominant)
				var sh: Vector3 = dominant_arm.upper_pivot.global_position
				var deg: float = def.left_elbow_swivel_deg if left_dominant else def.right_elbow_swivel_deg
				swivel_pole = ElbowSwivel.mix(sh, wrist, main_pole_world, chest[0], chest[1], deg, left_dominant, swivel_weight)


			var lag: float = clampf(float(def.get_meta("visual_wrist_lag_deg", 0.0)) if def else 0.0, 0.0, 6.0)
			dominant_arm.visual_wrist_lag_deg = lag
			if lag > 1e-05:
				var shoulder: Vector3 = dominant_arm.upper_pivot.global_position
				var axis: Vector3 = (wrist - shoulder).normalized()
				var trail_sign: float = side * (-1.0 if def.family == 1 else 1.0)
				main_pole_world = shoulder + (main_pole_world - shoulder).rotated(axis, deg_to_rad(lag * trail_sign))
				if swivel_pole.is_finite(): swivel_pole = shoulder + (swivel_pole - shoulder).rotated(axis, deg_to_rad(lag * trail_sign))
			dominant_arm.solve_ik(main_target, main_pole_world, _player.paddle_node.global_transform, wrist)
			# The authored swivel is visual only (gameplay reads the solved arm). The turn from the
			# solved elbow to the swivel one is recorded after the last arm step below.
			if elbow_swivel_enabled: swivel_record = [dominant_arm, wrist, swivel_pole]
			_hands.apply_mount(dominant_arm, mount)

		var support_target: Vector3 = get_support_hand_target(def)
		var external_target: = Vector3.INF
		if between != null and def != null and def.left_hand_mode == 4:
			external_target = between.support_hand_target_for(_player.get_actor_id())
		if external_target.is_finite(): support_target = external_target
		else: support_target += _PostureSkeletonApplier.stance_offset(support_offset, forehand_axis, forward_axis)
		var support_pole_world: Vector3 = _player.global_position - forehand_axis * 0.5 * side + Vector3.DOWN + forward_axis * -0.5
		if support_pole.length_squared() > 1e-10:
			support_pole_world = _player.global_position + _PostureSkeletonApplier.stance_offset(support_pole, forehand_axis, forward_axis)
		if support_arm and def:
			var shoulder_rotation: Vector3 = def.right_shoulder_rotation_deg if left_dominant else def.left_shoulder_rotation_deg
			support_pole_world = _rotate_shoulder_pole(support_arm, support_pole_world, shoulder_rotation)
		if support_arm and support_arm.has_method("solve_ik"):
			var is_gripping: bool = _support_mode(def) == 1 and not external_target.is_finite()
			var mount: Transform3D = _hands.support_mount(support_arm, support_target, def, is_gripping, support_pole_world)
			var game = _player.get_parent()
			var callouts = game.get("court_callouts")
			var gesture: float = callouts.gesture_weight(_player) if callouts != null else 0.0
			if gesture > 0.0001:
				support_target = callouts.gesture_target(_player, support_arm, support_target, gesture)
				support_pole_world = support_arm.upper_pivot.global_position - forehand_axis * side * 0.5 + forward_axis * 0.3
				mount = _hands.callout_mount(support_arm, support_target, support_pole_world, gesture)
			var wrist: Vector3 = HandPresentation.wrist_for(support_arm, mount)
			support_pole_world = ArmAnatomy.stabilized_pole(support_arm.upper_pivot.global_position, wrist, support_pole_world, pole_reference_axis * side)
			var orientation_grip_weight: float = _hands.support_orientation_grip_weight()
			# The elbow is aimed from the gripping wrist only while the hand really is on the paddle.
			# A pose that moves the hand off it (hand target offset) keeps the "Paddle grip" mode, and
			# this rule then held the elbow up at shoulder height whatever the pose's elbow guide said.
			if not external_target.is_finite():
				orientation_grip_weight *= 1.0 - smoothstep(SUPPORT_GRIP_ELBOW_NEAR, SUPPORT_GRIP_ELBOW_FAR, support_offset.length())
			if orientation_grip_weight > 1e-05:
				var distal: Vector3 = mount.basis * support_arm.articulated_hand.anatomical_basis.x
				var shoulder: Vector3 = support_arm.upper_pivot.global_position
				var conditioned: Vector3 = ArmAnatomy.conditioned_pole(shoulder, wrist, support_pole_world, distal, support_arm.upper_arm_length, support_arm.forearm_length)
				if orientation_grip_weight >= 0.99999: support_pole_world = conditioned
				else:


					var raw_direction: Vector3 = (support_pole_world - shoulder).normalized()
					var grip_direction: Vector3 = (conditioned - shoulder).normalized()
					support_pole_world = shoulder + raw_direction.slerp(grip_direction, orientation_grip_weight)
			support_arm.visual_wrist_lag_deg = 0.0
			support_arm.solve_ik(support_target, support_pole_world, null, wrist)
			if elbow_swivel_enabled and def != null and "elbow_swivel_weight" in def:
				var support_deg: float = def.right_elbow_swivel_deg if left_dominant else def.left_elbow_swivel_deg
				support_swivel_record = [support_arm, wrist, support_deg * clampf(float(def.elbow_swivel_weight), 0.0, 1.0), not left_dominant]
			_hands.apply_mount(support_arm, mount, true)


	if def != null and def.has_meta(ElbowPreset.SAMPLE_META):
		_player.set_meta("elbow_preset_report", ElbowPreset.apply(_player, def))
	elif _player.has_meta("elbow_preset_report"):
		_player.remove_meta("elbow_preset_report")
	LiveArmBudget.apply(_player, def, _hands)
	# Drawn elbow (pixel cards, studio, checker): from the elbow the arm ended with (LiveArmBudget may
	# have re-solved it), turned to the authored swivel and kept outside the torso.
	if not swivel_record.is_empty():
		var arm = swivel_record[0]
		ElbowSwivel.record_visual_turn(arm, swivel_record[1], arm.forearm_pivot.global_position, swivel_record[2], ElbowSwivel.body_shapes(_player))
	# The support arm's swivel field is a turn of its drawn elbow away from the solved one (+ out),
	# not an absolute angle: 0 shows the solved elbow, so poses that never set it look the same.
	# A hand gripping the paddle has its solved elbow aimed from the wrist whatever the pose's
	# guide says; this is how a pose (and AutoPose) still places that elbow. Visual only.
	if not support_swivel_record.is_empty():
		var s_arm = support_swivel_record[0]
		var s_wrist: Vector3 = support_swivel_record[1]
		var s_pole := Vector3.INF
		if absf(float(support_swivel_record[2])) > 1e-4:
			var s_left: bool = support_swivel_record[3]
			var s_chest: Array = ElbowSwivel.frame(def, forehand_axis, forward_axis, s_left)
			var s_shoulder: Vector3 = s_arm.upper_pivot.global_position
			var s_now: float = ElbowSwivel.angle(s_shoulder, s_wrist, s_arm.forearm_pivot.global_position, s_chest[0], s_chest[1], s_left)
			if not is_nan(s_now): s_pole = ElbowSwivel.pole(s_shoulder, s_wrist, s_chest[0], s_chest[1], s_now + float(support_swivel_record[2]), s_left)
		ElbowSwivel.record_visual_turn(s_arm, s_wrist, s_arm.forearm_pivot.global_position, s_pole)

	if not _player.is_ai and b != null and _player.debug_visual and _player.posture.human_contact == null:
		if _player.debug_visual.human_committed_contact_position != Vector3.ZERO:
			var dist_to_ball = b.global_position.distance_to(_player.debug_visual.human_committed_contact_position)
			var inbound = (_player.debug_visual.human_committed_contact_position.z - _player.global_position.z) < 0.2

			if _player.debug_visual.human_intercept_indicator:
				_player.debug_visual.human_intercept_indicator.global_position = _player.debug_visual.human_intercept_indicator.global_position.lerp(
					_player._clamp_to_court(_player.debug_visual.human_committed_contact_position), 15.0 * delta)
				if inbound:
					var ms = Time.get_ticks_msec()
					_player.debug_visual.human_intercept_indicator.visible = (ms % 400 > 150)
				else:
					_player.debug_visual.human_intercept_indicator.visible = true
				var mat = _player.debug_visual.human_intercept_indicator.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color.a = clamp(1.0 - dist_to_ball * 0.08, 0.15, 0.6)

			if _player.debug_visual.human_target_indicator:
				if _player.debug_visual.human_target_indicator.global_position == Vector3.ZERO:
					_player.debug_visual.human_target_indicator.global_position = _player._clamp_to_court(_player.debug_visual.human_committed_target_position)
				else:
					_player.debug_visual.human_target_indicator.global_position = _player.debug_visual.human_target_indicator.global_position.lerp(
						_player._clamp_to_court(_player.debug_visual.human_committed_target_position), 10.0 * delta)
				var reactive_size = clamp(dist_to_ball * 0.4, 0.45, 2.5)
				_player.debug_visual.human_target_indicator.scale = _player.debug_visual.human_target_indicator.scale.lerp(Vector3(reactive_size, 1.0, reactive_size), 22.0 * delta)
				_player.debug_visual.human_target_indicator.visible = true
				var tmat = _player.debug_visual.human_target_indicator.material_override as StandardMaterial3D
				if tmat:
					tmat.albedo_color.a = clamp(1.0 - dist_to_ball * 0.07, 0.08, 0.4)
					tmat.emission_energy_multiplier = clamp(1.2 - dist_to_ball * 0.1, 0.2, 1.2)



func _rotate_shoulder_pole(arm: Node3D, pole: Vector3, angles: Vector3) -> Vector3:
	if angles.length_squared() < 0.0001: return pole
	var stance: = Basis(_player._get_forehand_axis(), Vector3.UP, - _player._get_forward_axis())
	var rotation: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
	var shoulder: Vector3 = arm.get_node("UpperArmPivot").global_position
	return shoulder + rotation * (pole - shoulder)


func get_support_hand_target(def) -> Vector3:
	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	var mode: int = _support_mode(def)
	var left_dominant: bool = def != null and def.paddle_hand == 1
	var side: float = 1.0 if left_dominant else -1.0
	match mode:
		1: return _player.paddle_node.to_global(PaddleSize.SUPPORT_GRIP_OFFSET + Vector3.UP * def.support_grip_slide_m)
		2: return _player.global_position + fh * 0.2 * side + fwd * 0.2 + Vector3(0, 0.45, 0)
		3: return _player.global_position + Vector3(0, 1.05, 0) + fwd * 0.15
		_: return _player.global_position + fwd * 0.55 + fh * 0.15 * side + Vector3(0, 0.15, 0)

func _support_mode(def) -> int:
	var value: int = def.left_hand_mode if def else 0
	if value != 0: return value
	var both: bool = _player.paddle_posture in _player.BACKHAND_POSTURES or _player.paddle_posture in [
		_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD, 
		_player.PaddlePosture.VOLLEY_READY, _player.PaddlePosture.READY]
	return 1 if both else 4
