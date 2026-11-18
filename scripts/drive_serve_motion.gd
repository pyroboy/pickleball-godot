extends RefCounted
const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
const ShotMotionContext = preload("res://scripts/shot_motion_context.gd")
const TacticalMotion = preload("res://scripts/tactical_stroke_motion.gd")




const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ElbowPreset = preload("res://scripts/elbow_preset_runtime.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
const Support = preload("res://scripts/groundstroke_support_motion.gd")
const Preparation = preload("res://scripts/stroke_preparation_orientation.gd")
const ServePresentation = preload("res://scripts/serve_pose_presentation.gd")
const ServeJoint = preload("res://scripts/serve_joint_motion.gd")
const Delivery = preload("res://scripts/serve_delivery_profile.gd")
const ReadyGuard = preload("res://scripts/ready_guard_profile.gd")
const ServeEdits = preload("res://scripts/mobile_serve_pose_store.gd")
const BACKHAND_EXTRA_BODY_COIL_DEG: = 12.0
const BACKHAND_EXTRA_HIP_COIL_DEG: = 8.0
const SERVE_CONTACT: = Delivery.CONTACT
const SERVE_STRIKE_TIME: = 0.12
const SERVE_HOLD_HEIGHT: = Delivery.VOLLEY_HOLD_Y - Delivery.CONTACT.y
const SERVE_PALM_DROP: = 0.085
const SERVE_SWEEP_TIME: = 0.3
const SERVE_HOLD_TIME: = 0.08
const SERVE_RECOVERY_TIME: = 0.24

static func drive_strength(base: PostureDefinition, charge: float, is_volley: bool = false, near_kitchen: bool = false) -> float:
	if near_kitchen or is_volley or base.family not in [0, 1] or base.height_tier != 2:
		return 0.0
	return smoothstep(0.58, 0.95, clampf(charge, 0.0, 1.0))

static func drive_definition(base: PostureDefinition, charge: float, is_volley: bool = false, spin_mode: int = 0, near_kitchen: bool = false, shot_intent: String = "AUTO", motion_context: Dictionary = {}) -> PostureDefinition:
	if TacticalMotion.eligible(motion_context): return TacticalMotion.definition(base, motion_context)
	if not motion_context.is_empty():
		charge = float(motion_context.get("charge", charge))
		is_volley = bool(motion_context.get("is_volley", is_volley))
		spin_mode = int(motion_context.get("spin_mode", spin_mode))
		near_kitchen = bool(motion_context.get("near_kitchen", near_kitchen))
		shot_intent = str(motion_context.get("shot_intent", shot_intent))
	# An explicitly committed overhead keeps its overhead mechanics at the kitchen.
	if str(motion_context.get("profile", "")) == "SMASH": near_kitchen = false
	if base.family == 1 and base.left_hand_mode == 1:
		return _two_hand_backhand_definition(base, charge, is_volley, near_kitchen, shot_intent)
	var def: PostureDefinition = base.lerp_with(base, 0.0)
	var strength: float = 0.0 if shot_intent == "DROP" else drive_strength(base, charge, is_volley, near_kitchen)
	if is_zero_approx(strength): return _compact_or_overhead_definition(base, charge, is_volley, near_kitchen, shot_intent)
	var side: float = 1.0 if base.family == 0 else -1.0


	def.paddle_roll_base_deg = PaddleRotation.angle_lerp(base.paddle_roll_base_deg, 120.0 * side, strength)
	def.paddle_roll_signed_deg = PaddleRotation.angle_lerp(base.paddle_roll_signed_deg, 0.0, strength)



	var compact: PostureDefinition = _compact_or_overhead_definition(base, minf(charge, 0.58), is_volley, near_kitchen, shot_intent)
	var windup: PostureDefinition = Path.endpoint(compact, 0)
	windup.paddle_forehand_mul = lerpf(windup.paddle_forehand_mul, side * 0.44, strength)
	windup.paddle_forehand_mul += side * 0.12 * sin(PI * strength) * clampf((0.62 - absf(base.paddle_forehand_mul)) / 0.12, 0.0, 1.0)
	windup.paddle_forward_mul = lerpf(windup.paddle_forward_mul, -0.28, strength)
	windup.paddle_y_offset = lerpf(windup.paddle_y_offset, maxf(base.paddle_y_offset + 0.12, 0.1), strength)
	windup.body_yaw_deg = lerpf(windup.body_yaw_deg, 18.0 * side, strength)
	windup.hip_yaw_deg = lerpf(windup.hip_yaw_deg, 12.0 * side, strength)
	windup.torso_yaw_deg = lerpf(windup.torso_yaw_deg, 19.0 * side, strength)
	if base.family == 1:



		windup.body_yaw_deg -= BACKHAND_EXTRA_BODY_COIL_DEG * strength
		windup.hip_yaw_deg -= BACKHAND_EXTRA_HIP_COIL_DEG * strength
	windup.head_yaw_deg = - (windup.body_yaw_deg + windup.hip_yaw_deg + windup.torso_yaw_deg) * 0.72
	windup.crouch_amount = maxf(windup.crouch_amount, lerpf(base.crouch_amount, 0.13, strength))
	windup.weight_shift = lerpf(windup.weight_shift, -0.68, strength)
	windup.stance_width = maxf(windup.stance_width, 0.5)
	windup.paddle_roll_base_deg = PaddleRotation.angle_lerp(windup.paddle_roll_base_deg, 20.0 * side, strength)
	windup.paddle_roll_signed_deg = PaddleRotation.angle_lerp(windup.paddle_roll_signed_deg, 0.0, strength)


	var right: bool = base.paddle_hand == 0
	var pole: Vector3 = windup.right_elbow_pole if right else windup.left_elbow_pole
	if pole.length_squared() <= 1e-10: pole = Vector3(0.5 if right else -0.5, -1.0, -0.5)
	pole += Vector3(0, 0.08, 0.05) * strength
	if right: windup.right_elbow_pole = pole
	else: windup.left_elbow_pole = pole
	var finish: PostureDefinition = Path.endpoint(compact, 2)
	finish.paddle_forehand_mul = lerpf(finish.paddle_forehand_mul, -0.24 if base.family == 0 else 0.47, strength)
	finish.paddle_forward_mul = lerpf(finish.paddle_forward_mul, 0.34, strength)
	finish.paddle_y_offset = lerpf(finish.paddle_y_offset, maxf(base.paddle_y_offset + 0.34, 0.48), strength)
	finish.body_yaw_deg = lerpf(finish.body_yaw_deg, -12.0 * side, strength)
	finish.hip_yaw_deg = lerpf(finish.hip_yaw_deg, -14.0 * side, strength)
	finish.torso_yaw_deg = lerpf(finish.torso_yaw_deg, -10.0 * side, strength)


	finish.torso_pitch_deg -= 12.0 * strength
	finish.head_yaw_deg = - (finish.body_yaw_deg + finish.hip_yaw_deg + finish.torso_yaw_deg) * 0.65
	finish.weight_shift = lerpf(finish.weight_shift, 0.72, strength)
	finish.crouch_amount = lerpf(finish.crouch_amount, maxf(0.045, base.crouch_amount * 0.65), strength)
	finish.paddle_roll_base_deg = PaddleRotation.angle_lerp(finish.paddle_roll_base_deg, -32.0 * side, strength)
	finish.paddle_roll_signed_deg = PaddleRotation.angle_lerp(finish.paddle_roll_signed_deg, 0.0, strength)
	if spin_mode == 1:
		def.paddle_pitch_base_deg -= 4.0 * strength
		finish.paddle_y_offset += 0.025 * strength
	elif spin_mode == 2:
		def.paddle_pitch_base_deg += 12.0 * strength
		finish.paddle_y_offset = lerpf(finish.paddle_y_offset, base.paddle_y_offset + 0.08, strength)
		finish.paddle_forward_mul = lerpf(finish.paddle_forward_mul, 0.43, strength)
	_write_endpoint(def, windup, true)
	_write_endpoint(def, finish, false)
	return def




static func _two_hand_backhand_definition(base: PostureDefinition, charge: float, is_volley: bool, near_kitchen: bool, shot_intent: String) -> PostureDefinition:
	if base.posture_id == 9: return base.lerp_with(base, 0.0)
	var strength: float = 0.0 if shot_intent == "DROP" else drive_strength(base, charge, is_volley, near_kitchen)
	var compact: PostureDefinition = _compact_or_overhead_definition(base, minf(charge, 0.58), is_volley, near_kitchen, shot_intent)
	if is_zero_approx(strength): return compact
	var def: PostureDefinition = base.lerp_with(base, 0.0)
	_write_endpoint(def, Path.blend_pose(Path.endpoint(compact, 0), Path.endpoint(base, 0), strength), true)
	_write_endpoint(def, Path.blend_pose(Path.endpoint(compact, 2), Path.endpoint(base, 2), strength), false)
	for right in [true, false]:
		var authored: PackedVector3Array = base.right_elbow_path if right else base.left_elbow_path
		var blended: = PackedVector3Array()
		for i in range(authored.size()):
			var pose: PostureDefinition = Path.sample(compact, float(i) / maxf(authored.size() - 1, 1))
			var pole: Vector3 = pose.right_elbow_pole if right else pose.left_elbow_pole
			blended.append(pole.lerp(authored[i], strength))
		if right: def.right_elbow_path = blended
		else: def.left_elbow_path = blended
	return def

static func held_drive_pose(base: PostureDefinition, charge: float, is_volley: bool = false, spin_mode: int = 0, near_kitchen: bool = false, shot_intent: String = "AUTO", motion_context: Dictionary = {}) -> PostureDefinition:
	if TacticalMotion.eligible(motion_context): return TacticalMotion.sample(base, 0.0, motion_context)
	if not motion_context.is_empty():
		charge = float(motion_context.get("charge", charge))
		is_volley = bool(motion_context.get("is_volley", is_volley))
		spin_mode = int(motion_context.get("spin_mode", spin_mode))
		near_kitchen = bool(motion_context.get("near_kitchen", near_kitchen))
		shot_intent = str(motion_context.get("shot_intent", shot_intent))
	# An explicitly committed overhead keeps its overhead mechanics at the kitchen.
	if str(motion_context.get("profile", "")) == "SMASH": near_kitchen = false
	var def: PostureDefinition = drive_definition(base, charge, is_volley, spin_mode, near_kitchen, shot_intent)
	if base.family == 1 and base.left_hand_mode == 1:
		var linked: PostureDefinition = Path.sample(def, 0.5 * (1.0 - clampf(charge, 0.0, 1.0)))
		linked.set_meta("visual_wrist_lag_deg", 0.0)
		return linked
	var pose: PostureDefinition = Path.blend_pose(def, Path.endpoint(def, 0), clampf(charge, 0.0, 1.0))
	if base.family == 1 and base.height_tier == 2 and not is_volley and not near_kitchen and shot_intent != "DROP":
		pose.left_elbow_pole = PostureDefinition.blend_elbow_pole(pose.left_elbow_pole, Vector3(0, -0.25, 0.35), smoothstep(0.35, 0.65, charge), false)
	Support.swing(pose, base, 0.0, charge, is_volley or near_kitchen or shot_intent == "DROP")
	Preparation.turn_shaft(pose, Preparation.drive_turn(base, 0.0, charge, drive_strength(base, charge, is_volley, near_kitchen), is_volley or near_kitchen or shot_intent == "DROP"))
	pose.set_meta("visual_wrist_lag_deg", 0.0)
	return pose

static func sample_drive(base: PostureDefinition, progress: float, charge: float, is_volley: bool = false, spin_mode: int = 0, near_kitchen: bool = false, shot_intent: String = "AUTO", motion_context: Dictionary = {}) -> PostureDefinition:
	if TacticalMotion.eligible(motion_context): return TacticalMotion.sample(base, progress, motion_context)
	if not motion_context.is_empty():
		charge = float(motion_context.get("charge", charge))
		is_volley = bool(motion_context.get("is_volley", is_volley))
		spin_mode = int(motion_context.get("spin_mode", spin_mode))
		near_kitchen = bool(motion_context.get("near_kitchen", near_kitchen))
		shot_intent = str(motion_context.get("shot_intent", shot_intent))
	# An explicitly committed overhead keeps its overhead mechanics at the kitchen.
	if str(motion_context.get("profile", "")) == "SMASH": near_kitchen = false
	var def: PostureDefinition = drive_definition(base, charge, is_volley, spin_mode, near_kitchen, shot_intent)
	var t: float = clampf(progress, 0.0, 1.0)
	if base.family == 1 and base.left_hand_mode == 1:


		var linked: PostureDefinition = Path.sample(def, lerpf(0.5, t, clampf(charge, 0.0, 1.0)))
		linked.set_meta("visual_wrist_lag_deg", 0.0)
		ElbowPreset.tag(linked,base,t,"stroke_runtime")
		return linked
	var pose: PostureDefinition = Path.sample(def, t)
	if t < 0.5 and shot_intent != "DROP":


		var u: float = t * 2.0
		var slot: float = pow(sin(PI * u), 2.0) * drive_strength(base, charge, is_volley, near_kitchen)
		pose.paddle_y_offset -= (0.08 if spin_mode == 2 else 0.26) * slot
		pose.paddle_forward_mul -= 0.06 * slot


		pose.paddle_forehand_mul += (0.18 if base.family == 0 else -0.18) * slot * clampf((0.62 - absf(base.paddle_forehand_mul)) / 0.12, 0.0, 1.0)
		if base.family == 1:
			pose.left_elbow_pole = PostureDefinition.blend_elbow_pole(pose.left_elbow_pole, Vector3(-0.3, 0.0, 0.65), slot, false)
			pose.left_hand_offset += Vector3(-0.1, -0.15, 0.0) * slot
	var result: PostureDefinition = Path.blend_pose(def, pose, clampf(charge, 0.0, 1.0))
	Support.swing(result, base, t, charge, is_volley or near_kitchen or shot_intent == "DROP")
	Preparation.turn_shaft(result, Preparation.drive_turn(base, t, charge, drive_strength(base, charge, is_volley, near_kitchen), is_volley or near_kitchen or shot_intent == "DROP"))


	result.set_meta("visual_wrist_lag_deg", Preparation.wrist_lag(base, t, charge, drive_strength(base, charge, is_volley, near_kitchen), is_volley or near_kitchen or shot_intent == "DROP"))
	ElbowPreset.tag(result,base,t,"stroke_runtime")
	return result




static func motion_kind(base: PostureDefinition, charge: float, is_volley: bool = false, near_kitchen: bool = false) -> String:
	if base.family == 3 and not near_kitchen: return "SMASH"
	if is_volley or (near_kitchen and base.family == 3): return "VOLLEY"
	if near_kitchen or charge <= 0.58 or base.height_tier <= 1: return "DINK"
	return "DRIVE"

static func kitchen_ready(base: PostureDefinition) -> PostureDefinition:
	var pose: PostureDefinition = base.lerp_with(base, 0.0)
	pose.display_name = "Kitchen Ready"
	pose.paddle_forehand_mul = base.paddle_forehand_mul + 0.065
	pose.paddle_forward_mul = base.paddle_forward_mul
	pose.paddle_y_offset = base.paddle_y_offset + 0.02
	pose.crouch_amount = 0.1
	pose.stance_width = 0.5
	pose.front_foot_forward = 0.04
	pose.back_foot_back = -0.04
	pose.weight_shift = 0.0
	pose.torso_pitch_deg = -8.0

	ReadyGuard.compact(pose, base)
	return pose

static func _compact_or_overhead_definition(base: PostureDefinition, charge: float, is_volley: bool, near_kitchen: bool = false, shot_intent: String = "AUTO") -> PostureDefinition:
	var def: PostureDefinition = base.lerp_with(base, 0.0)


	if base.family == 1 and base.left_hand_mode == 1:
		def.right_elbow_path = PackedVector3Array();def.left_elbow_path = PackedVector3Array()
	var kind: String = "DROP" if shot_intent == "DROP" else motion_kind(base, charge, is_volley, near_kitchen)
	if kind == "DRIVE": return def
	var windup: PostureDefinition = base.lerp_with(base, 0.0)
	var finish: PostureDefinition = base.lerp_with(base, 0.0)
	if kind == "SMASH":

		def.left_hand_mode = 4
		def.left_hand_offset = Vector3(-0.05, 0.6, -0.4)

		windup.paddle_forehand_mul = 0.75
		windup.paddle_forward_mul = -0.25
		windup.paddle_y_offset = 0.96
		windup.paddle_pitch_base_deg = -20.0
		windup.paddle_pitch_signed_deg = 0.0
		windup.paddle_roll_base_deg = 15.0
		windup.paddle_roll_signed_deg = 0.0
		windup.body_yaw_deg = 15.0
		windup.hip_yaw_deg = 8.0
		windup.torso_yaw_deg = 14.0
		windup.torso_pitch_deg -= 12.0
		windup.weight_shift = -0.5
		windup.crouch_amount = maxf(base.crouch_amount, 0.09)
		windup.left_hand_mode = 4
		windup.left_hand_offset = Vector3(-0.1, 0.6, -0.4)
		finish.paddle_forehand_mul = -0.05
		finish.paddle_forward_mul = 0.49
		finish.paddle_y_offset = 0.17
		finish.paddle_pitch_base_deg = -18.0
		finish.paddle_pitch_signed_deg = 0.0
		finish.paddle_roll_base_deg = -45.0
		finish.paddle_roll_signed_deg = 0.0
		finish.body_yaw_deg = -9.0
		finish.hip_yaw_deg = -10.0
		finish.torso_yaw_deg = -8.0
		finish.weight_shift = 0.55
		finish.crouch_amount = maxf(base.crouch_amount, 0.06)
		finish.left_hand_mode = 4
		finish.left_hand_offset = Vector3(-0.06, -0.02, -0.3)
	else:
		var compact: float = 0.075 if kind == "VOLLEY" else (0.1 if kind == "DROP" else 0.13)
		var motion_scale: float = base.compact_motion_scale
		windup.paddle_forward_mul -= compact * motion_scale
		windup.paddle_y_offset -= (0.035 if kind == "VOLLEY" else 0.065) * motion_scale
		windup.weight_shift = -0.1
		windup.crouch_amount = base.crouch_amount + (0.04 if near_kitchen else 0.025)
		if near_kitchen:
			windup.stance_width = maxf(base.stance_width, 0.54)
			finish.stance_width = windup.stance_width


		finish.paddle_forward_mul += (0.015 if kind == "VOLLEY" else (compact if base.height_tier == 2 else compact * 0.4)) * motion_scale
		if kind == "VOLLEY" and absf(base.paddle_forehand_mul) > 0.6:
			finish.paddle_forehand_mul *= 0.96
		if base.height_tier <= 1: finish.paddle_forehand_mul *= base.compact_finish_lateral_scale
		finish.paddle_y_offset += (0.025 if kind == "VOLLEY" else 0.13) * motion_scale
		if base.paddle_hand == 0: finish.right_elbow_pole += base.compact_finish_elbow_offset
		else: finish.left_elbow_pole += base.compact_finish_elbow_offset
		finish.weight_shift = 0.18

	_write_endpoint(def, windup, true)
	_write_endpoint(def, finish, false)
	return def

static func _write_endpoint(def: PostureDefinition, pose: PostureDefinition, windup: bool) -> void :
	var offset: = Vector3(pose.paddle_forehand_mul - def.paddle_forehand_mul, 
		pose.paddle_y_offset - def.paddle_y_offset, pose.paddle_forward_mul - def.paddle_forward_mul)
	var angles: = Vector3(pose.paddle_pitch_base_deg - def.paddle_pitch_base_deg, 
		pose.paddle_yaw_base_deg - def.paddle_yaw_base_deg, pose.paddle_roll_base_deg - def.paddle_roll_base_deg)
	var body: Resource = BodyKey.new()
	body.capture(pose)
	if windup:
		def.charge_paddle_offset = offset
		def.charge_paddle_rotation_deg = PaddleRotation.vector(angles)
		def.windup_body = body
	else:
		def.ft_paddle_offset = offset
		def.ft_paddle_rotation_deg = PaddleRotation.vector(angles)
		def.follow_through_body = body

static func serve_launch_offset(is_red_side: bool) -> Vector3:
	var sign: float = -1.0 if is_red_side else 1.0
	return Vector3(SERVE_CONTACT.x * sign, SERVE_CONTACT.y, - SERVE_CONTACT.z * sign)

static func serve_contact(spin_mode: int = 0) -> PostureDefinition:
	var pose: = PostureDefinition.new()
	pose.posture_id = 0
	pose.display_name = "Underhand Serve"
	pose.family = 0

	pose.paddle_pitch_sign_source = 1
	pose.paddle_yaw_sign_source = 1
	pose.paddle_roll_sign_source = 1
	pose.paddle_hand = 0
	pose.left_hand_mode = 4
	pose.paddle_forehand_mul = SERVE_CONTACT.x
	pose.paddle_y_offset = SERVE_CONTACT.y
	pose.paddle_forward_mul = SERVE_CONTACT.z
	pose.paddle_pitch_base_deg = 0.0 if spin_mode == 1 else (14.0 if spin_mode == 2 else 8.0)
	pose.paddle_roll_base_deg = 145.0
	pose.paddle_floor_clearance = 0.06
	pose.lead_foot = 1
	pose.stance_width = 0.44

	pose.front_foot_forward = -0.12
	pose.back_foot_back = -0.34
	pose.right_foot_yaw_deg = 22.0
	pose.left_foot_yaw_deg = 5.0
	pose.crouch_amount = 0.08
	pose.weight_shift = 0.12
	pose.body_yaw_deg = 7.0
	pose.hip_yaw_deg = -5.0
	pose.torso_yaw_deg = 2.0
	pose.torso_pitch_deg = -12.0
	pose.head_yaw_deg = -4.0
	pose.head_pitch_deg = 12.0


	pose.left_hand_offset = Vector3(-0.07, -0.13, -0.2)
	pose.right_elbow_pole = Vector3(0.46, -0.25, 0.02)
	pose.left_elbow_pole = Vector3(-0.4, -0.15, 0.1)
	return ServeJoint.contact(pose, SERVE_CONTACT)

static func serve_preparation(charge: float, spin_mode: int = 0) -> PostureDefinition:
	var pose: PostureDefinition = serve_contact(spin_mode)
	var load: float = clampf(charge, 0.0, 1.0)
	pose.display_name = "Serve Preparation"
	pose.paddle_forehand_mul = lerpf(0.48, 0.34, load)
	pose.paddle_y_offset = lerpf(-0.28, -0.4, load)
	pose.paddle_forward_mul = lerpf(0.15, 0.19, load)
	pose.paddle_roll_base_deg = lerpf(172.0, 148.0, load)
	pose.body_yaw_deg = lerpf(8.0, 18.0, load)
	pose.hip_yaw_deg = lerpf(4.0, 10.0, load)
	pose.torso_yaw_deg = lerpf(6.0, 12.0, load)
	pose.crouch_amount = lerpf(0.075, 0.12, load)
	pose.weight_shift = lerpf(-0.35, -0.64, load)
	pose.torso_pitch_deg = lerpf(-16.0, -12.0, load)
	pose.stance_width = lerpf(0.48, 0.44, load)
	pose.back_foot_back = lerpf(-0.27, -0.34, load)
	pose.head_yaw_deg = - (pose.body_yaw_deg + pose.hip_yaw_deg + pose.torso_yaw_deg) * 0.6

	pose.left_hand_offset = Vector3(SERVE_CONTACT.x + 0.15, SERVE_CONTACT.y + SERVE_HOLD_HEIGHT - 0.15 - serve_palm_depth(load), SERVE_CONTACT.z - 0.55)

	return pose

static func serve_strike(start: PostureDefinition, progress: float, spin_mode: int = 0) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	var contact: PostureDefinition = serve_contact(spin_mode)
	var pose: PostureDefinition = start.lerp_with(contact, t * t)



	pose.left_hand_offset = start.left_hand_offset.lerp(contact.left_hand_offset, smoothstep(0.0, 0.45, t))
	return pose

static func serve_follow_through(charge: float, progress: float, spin_mode: int = 0) -> PostureDefinition:
	var contact: PostureDefinition = serve_contact(spin_mode)
	var finish: PostureDefinition = serve_contact(spin_mode)
	var amount: float = lerpf(0.72, 1.0, clampf(charge, 0.0, 1.0))
	finish.display_name = "Serve Finish"
	finish.paddle_forehand_mul = lerpf(SERVE_CONTACT.x, -0.24, amount)
	finish.paddle_y_offset = lerpf(SERVE_CONTACT.y, 0.25 if spin_mode == 2 else 0.47, amount)
	finish.paddle_forward_mul = 0.34
	finish.paddle_roll_base_deg = -30.0
	finish.paddle_pitch_base_deg = -8.0
	finish.body_yaw_deg = -11.0
	finish.hip_yaw_deg = -12.0
	finish.torso_yaw_deg = -7.0
	finish.head_yaw_deg = 18.0
	finish.crouch_amount = 0.045
	finish.weight_shift = 0.6
	finish.left_hand_offset = Vector3(-0.1, -0.05, -0.32)
	var t: float = clampf(progress, 0.0, 1.0)
	var pose: PostureDefinition = contact.lerp_with(finish, t)


	# Complete orientation already takes the shortest quaternion path above.

	pose.paddle_forward_mul += sin(PI * t) * (0.11 if spin_mode == 2 else 0.16)
	return pose



static func _style_spin(style: int) -> int:
	return 2 if style == 2 else (1 if style in [1, 4, 5, 6] else 0)

static func serve_style_preparation(style: int, charge: float, held_offset: Vector3, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	var pose: PostureDefinition = ServePresentation.prepare(_legacy_serve_style_preparation(style, charge, held_offset), style, charge, held_offset)
	return ServeEdits.apply_motion(pose, style, Vector3(clampf(charge, 0.0, 1.0), 0, 0), custom, use_saved)

static func _legacy_serve_style_preparation(style: int, charge: float, held_offset: Vector3) -> PostureDefinition:
	var q: float = clampf(charge, 0.0, 1.0)
	var pose: PostureDefinition = serve_preparation(q, _style_spin(style))


	pose.left_elbow_pole = ServePresentation.SUPPORT_RELEASE_POLE
	match style:
		1:
			pose.paddle_y_offset -= 0.055 * q
			pose.paddle_forehand_mul += 0.035 * q
		2:
			pose.paddle_y_offset = lerpf(pose.paddle_y_offset, -0.16, q)
			pose.paddle_forward_mul = lerpf(pose.paddle_forward_mul, 0.12, q)
			pose.paddle_pitch_base_deg = 18.0


			pose.torso_pitch_deg -= 16.0 * q
		3:
			pose.body_yaw_deg *= lerpf(1.0, 0.65, q)
			pose.hip_yaw_deg *= lerpf(1.0, 0.65, q)
			pose.torso_yaw_deg *= lerpf(1.0, 0.65, q)
			pose.weight_shift *= lerpf(1.0, 0.7, q)
			pose.paddle_y_offset -= 0.025 * q
		4:
			pose.paddle_forehand_mul += 0.07 * q
			pose.paddle_forward_mul -= 0.15 * q
			pose.body_yaw_deg += 3.0 * q
		5, 6:
			pose.paddle_forehand_mul += 0.08 * q
			pose.paddle_forward_mul -= 0.06 * q
	var palm_depth: float = serve_presentation_palm_depth(q, held_offset.y)

	if style == 3:
		palm_depth -= 0.003 * q * q * smoothstep(0.08, 0.265, held_offset.y)
	pose.left_hand_offset = held_offset - Vector3(-0.15, 0.15, 0.55) - Vector3.UP * palm_depth
	if q < 0.45:


		pose.set_meta("reference_serve_load", Vector4(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul, pose.paddle_roll_base_deg))


		pose.set_meta("reference_serve_rotation", pose.resolve_paddle_rotation_deg(-1.0, -1.0))
		if is_zero_approx(q):
			pose.paddle_forehand_mul = 0.55
			pose.paddle_y_offset = 0.02
			pose.paddle_forward_mul = 0.15
			pose.paddle_roll_base_deg = 58.0
		else:


			var t: = smoothstep(0.0, 0.45, q)
			var angles: Vector3 = pose.resolve_paddle_rotation_deg(-1.0, -1.0) * (PI / 180.0)
			var frame: = Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y)
			var old_basis: = frame * Basis(Vector3.FORWARD, angles.z)
			var hold_basis: = frame * Basis(Vector3.FORWARD, deg_to_rad(58.0))
			var roll: = lerpf(58.0, pose.paddle_roll_base_deg, t)
			var basis: = frame * Basis(Vector3.FORWARD, deg_to_rad(roll))
			var grip_offset: = (PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + pose.right_hand_offset
			var hand_a: = Vector3(0.55, 0.02, - 0.15) + hold_basis * grip_offset
			var hand_b: = Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul) + old_basis * grip_offset
			var head: = hand_a.lerp(hand_b, t) - basis * grip_offset
			pose.paddle_forehand_mul = head.x
			pose.paddle_y_offset = head.y
			pose.paddle_forward_mul = - head.z
			pose.paddle_roll_base_deg = roll
		Preparation.turn_shaft(pose, Preparation.serve_turn(q))
	return pose

static func serve_presentation_palm_depth(charge: float, held_height: float) -> float:




	var rows: Array = [
		[0.0896, 0.083, 0.0807, 0.0797, 0.0796], 
		[0.07945, 0.0793, 0.07953, 0.08006, 0.08085], 
		[0.08068, 0.08167, 0.08292, 0.08444, 0.08622], 
		[0.08567, 0.08763, 0.0899, 0.09251, 0.09546], 
		[0.09339, 0.09625, 0.09877, 0.10095, 0.1028]]
	var h: float = clampf((held_height - (SERVE_CONTACT.y + SERVE_HOLD_HEIGHT)) / 0.37, 0.0, 1.0) * 4.0
	var q: float = clampf(charge, 0.0, 1.0) * 4.0
	var hi: int = mini(3, int(h))
	var qi: int = mini(3, int(q))
	var lower: float = lerpf(rows[hi][qi], rows[hi][qi + 1], q - qi)
	var upper: float = lerpf(rows[hi + 1][qi], rows[hi + 1][qi + 1], q - qi)
	var depth: float = lerpf(lower, upper, h - hi)

	if h < 1.0:
		depth -= 0.0026 * sin(PI * h) * pow(1.0 - clampf(charge, 0.0, 1.0), 2.0)
	return depth

static func serve_palm_depth(charge: float) -> float:


	var values: Array[float] = [0.0896, 0.083, 0.0807, 0.0797, 0.0796]
	var t: float = clampf(charge, 0.0, 1.0) * 4.0
	var index: int = mini(3, int(t))
	return lerpf(values[index], values[index + 1], t - index)

static func serve_style_contact(style: int, ball_offset: Vector3 = SERVE_CONTACT, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	return ServeEdits.apply_motion(_raw_serve_style_contact(style, ball_offset), style, Vector3(0, 1, 0), custom, use_saved)

static func _raw_serve_style_contact(style: int, ball_offset: Vector3 = SERVE_CONTACT) -> PostureDefinition:
	return ServeJoint.contact(serve_contact(_style_spin(style)), ball_offset)

static func _set_serve_surface(pose: PostureDefinition, ball_offset: Vector3) -> void :

	ServeJoint.contact(pose, ball_offset)

static func original_serve_load(start: PostureDefinition) -> PostureDefinition:
	if start.has_meta("serve_phase_profile"):
		start = _legacy_serve_style_preparation(int(start.get_meta("serve_phase_style")), float(start.get_meta("serve_phase_charge")), start.get_meta("serve_phase_held_offset"))
	if not start.has_meta("reference_serve_load"): return start
	var original: PostureDefinition = start.lerp_with(start, 0.0)
	var values: Vector4 = start.get_meta("reference_serve_load")
	original.paddle_forehand_mul = values.x
	original.paddle_y_offset = values.y
	original.paddle_forward_mul = values.z
	original.paddle_roll_base_deg = values.w
	if start.has_meta("reference_serve_rotation"):
		var rotation: Vector3 = start.get_meta("reference_serve_rotation")
		original.paddle_pitch_base_deg = rotation.x
		original.paddle_yaw_base_deg = rotation.y
		original.paddle_roll_base_deg = rotation.z
		original.paddle_pitch_signed_deg = 0.0
		original.paddle_yaw_signed_deg = 0.0
		original.paddle_roll_signed_deg = 0.0
	return original

static func serve_style_wait(start: PostureDefinition, release_progress: float, style: int, ball_offset: Vector3 = SERVE_CONTACT, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	var baseline: PostureDefinition = ServeEdits.raw_pose(start)
	var pose: PostureDefinition = _raw_serve_style_wait(baseline, release_progress, style, ball_offset)
	var q: float = clampf(float(baseline.get_meta("serve_phase_charge", 1.0)), 0.0, 1.0)
	return ServeEdits.apply_motion(pose, style, Vector3(q, 0, 0), custom, use_saved)

static func _raw_serve_style_wait(start: PostureDefinition, release_progress: float, style: int, ball_offset: Vector3 = SERVE_CONTACT) -> PostureDefinition:
	if start.has_meta("serve_phase_profile"):
		var held: PostureDefinition = start.lerp_with(start, 0.0)
		ServePresentation.copy_context(start, held)
		var end: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
		held.left_hand_offset = start.left_hand_offset.lerp(end.left_hand_offset, smoothstep(0.0, 1.0, release_progress))
		held.left_elbow_pole = start.left_elbow_pole.lerp(ServePresentation.SUPPORT_RELEASE_POLE, smoothstep(0.0, 1.0, release_progress * (0.12 / 0.18)))
		return held
	var pose: PostureDefinition = start.lerp_with(start, 0.0)
	if start.has_meta("reference_serve_load"):
		var load: PostureDefinition = original_serve_load(start)
		var settle: = smoothstep(0.0, 1.0, release_progress)
		pose = Path.blend_pose(start, load, settle)
		if settle < 1.0:
			pose.set_meta("reference_serve_load", start.get_meta("reference_serve_load"))
			if start.has_meta("reference_serve_rotation"): pose.set_meta("reference_serve_rotation", start.get_meta("reference_serve_rotation"))
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	pose.left_hand_offset = start.left_hand_offset.lerp(contact.left_hand_offset, smoothstep(0.0, 1.0, release_progress))
	return pose

static func serve_style_strike(start: PostureDefinition, progress: float, style: int, ball_offset: Vector3 = SERVE_CONTACT, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	start = ServeEdits.raw_pose(start)
	var t: float = clampf(progress, 0.0, 1.0)
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	var q: float = clampf(float(start.get_meta("serve_phase_charge", 1.0)), 0.0, 1.0)
	var u: float = t * t


	var dip: float = -10.0 * (1.0 - q) * sin(PI * u)
	var outside: float = 8.0 * pow(sin(PI * u), 2.0)  # was 20: rolled the forearm and snapped the elbow mid-strike
	var pose: PostureDefinition = ServeJoint.blend(start, contact, u, dip, outside, smoothstep(0.0, 1.0, t))
	_smooth_through_contact(pose, start, contact, _serve_finish_key(style, q, ball_offset), u, true)
	ServePresentation.copy_context(start, pose)
	return ServeEdits.apply_motion(pose, style, Vector3(q * (1.0 - u), u, 0), custom, use_saved)

static func _legacy_serve_style_strike(start: PostureDefinition, progress: float, style: int, ball_offset: Vector3 = SERVE_CONTACT) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	var loaded: PostureDefinition = original_serve_load(start)
	var pose: PostureDefinition = Path.blend_pose(loaded, contact, t * t)
	pose.left_hand_offset = start.left_hand_offset.lerp(contact.left_hand_offset, smoothstep(0.0, 0.45, t))


	if style in [0, 1, 3, 4, 5, 6]:
		pose.paddle_y_offset -= sin(PI * t) * (0.08 if style in [0, 1, 3, 4] else 0.04)

	if style == 5: pose.paddle_forehand_mul -= sin(PI * t) * 0.18
	if style == 6: pose.paddle_forehand_mul += sin(PI * t) * 0.06



	if start.has_meta("reference_serve_load") and not start.has_meta("serve_phase_profile") and t < 0.65:
		var support: = pose.left_hand_offset
		pose = Path.blend_pose(start, pose, smoothstep(0.0, 0.65, t))
		pose.left_hand_offset = support
	return pose

static func serve_style_follow_through(style: int, charge: float, progress: float, ball_offset: Vector3 = SERVE_CONTACT, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	var finish: PostureDefinition = _serve_finish_key(style, charge, ball_offset)
	var pose: PostureDefinition = ServeJoint.blend(contact, finish, t)
	var windup: PostureDefinition = ServeEdits.raw_pose(serve_style_wait(serve_style_preparation(style, charge, Styles_hold(style), null, false), 1.0, style, ball_offset, null, false))
	_smooth_through_contact(pose, windup, contact, finish, t, false)
	return ServeEdits.apply_motion(pose, style, Vector3(0, 1.0 - t, t * lerpf(0.72, 1.0, clampf(charge, 0.0, 1.0))), custom, use_saved)

static func _serve_finish_key(style: int, charge: float, ball_offset: Vector3) -> PostureDefinition:
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	var finish: PostureDefinition = ServePresentation.finish(_legacy_serve_style_follow_through(style, charge, 1.0, ball_offset), style)
	return ServeJoint.blend(contact, finish, lerpf(0.72, 1.0, clampf(charge, 0.0, 1.0)))

static func Styles_hold(style: int) -> Vector3:
	return load("res://scripts/serve_style.gd").hold_offset(style)

## The strike (wind-up -> contact) and follow-through (contact -> finish) are separate joint
## blends, so the paddle turned a sharp corner at contact and the elbow snapped. Bend the end
## of the strike and the start of the follow-through toward one shared direction (wind-up ->
## finish), Hermite-style, so the head and elbow pass through contact as one smooth curve.
## Contact itself is unchanged (both terms are zero at u = 1 / u = 0).
static func _smooth_through_contact(pose: PostureDefinition, windup: PostureDefinition, contact: PostureDefinition, finish: PostureDefinition, u: float, into: bool) -> void:
	var h: float = (u * u * u - u * u) if into else (u * u * u - 2.0 * u * u + u)
	if is_zero_approx(h): return
	var head := func(d: PostureDefinition) -> Vector3: return Vector3(d.paddle_forehand_mul, d.paddle_y_offset, d.paddle_forward_mul)
	for channel in ["head"]:
		var a: Vector3 = head.call(windup) if channel == "head" else windup.right_elbow_pole
		var c: Vector3 = head.call(contact) if channel == "head" else contact.right_elbow_pole
		var f: Vector3 = head.call(finish) if channel == "head" else finish.right_elbow_pole
		var through: Vector3 = f - a
		if through.length() < 0.001: continue
		var chord: Vector3 = (c - a) if into else (f - c)
		var correction: Vector3 = (through.normalized() * chord.length() - chord) * h
		if channel == "head":
			pose.paddle_forehand_mul += correction.x; pose.paddle_y_offset += correction.y; pose.paddle_forward_mul += correction.z
		else:
			pose.right_elbow_pole += correction

static func _legacy_serve_style_follow_through(style: int, charge: float, progress: float, ball_offset: Vector3 = SERVE_CONTACT) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	var contact: PostureDefinition = _raw_serve_style_contact(style, ball_offset)
	var finish: PostureDefinition = serve_follow_through(charge, 1.0, _style_spin(style))
	if style == 2:
		finish.paddle_forehand_mul = 0.08
		finish.paddle_forward_mul = 0.46
		finish.paddle_y_offset = -0.05
		finish.paddle_roll_base_deg = 160.0
		finish.paddle_pitch_base_deg = 18.0
	elif style == 3:
		finish.paddle_y_offset = lerpf(0.34, 0.55, clampf(charge, 0, 1))
		finish.paddle_forward_mul = 0.42
	var pose: PostureDefinition = Path.blend_pose(contact, finish, t)
	if style != 2:
		# Complete orientation already takes the shortest quaternion path above.
		pose.paddle_forward_mul += sin(PI * t) * 0.14
	else:
		pose.paddle_y_offset -= sin(PI * t) * 0.095
	if style == 5: pose.paddle_forehand_mul += 0.6 * t * pow(1.0 - t, 3.0)
	if style == 6: pose.paddle_forehand_mul -= sin(PI * t) * 0.1
	return pose
