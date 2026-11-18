extends RefCounted

const Path = preload("res://scripts/stroke_swing_path.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
const ElbowPreset = preload("res://scripts/elbow_preset_runtime.gd")
const Context = preload("res://scripts/shot_motion_context.gd")

static func eligible(context: Dictionary) -> bool:
	return str(context.get("profile", "LEGACY")) in Context.PROFILES and str(context.get("profile", "LEGACY")) not in ["LEGACY", "SMASH"]

static func definition(base: PostureDefinition, context: Dictionary) -> PostureDefinition:
	var def: PostureDefinition = base.lerp_with(base, 0.0)
	if not eligible(context): return def
	var name: String = str(context.profile)
	var charge: float = clampf(float(context.get("charge", 0.5)), 0.0, 1.0)
	var pace: float = clampf(float(context.get("incoming_speed", 0.0)) / 16.0, 0.0, 1.0)
	var side: float = -1.0 if base.family == 1 else 1.0
	var windup: PostureDefinition = base.lerp_with(base, 0.0)
	var finish: PostureDefinition = base.lerp_with(base, 0.0)
	# Near reach boundaries keep the shape, scaled to the same authored envelope.
	var scale: float = clampf(base.compact_motion_scale, 0.25, 1.0)
	if absf(base.paddle_forehand_mul) > 0.62: scale *= 0.5
	if base.height_tier == 0: scale *= 0.6
	var prep: = Vector3.ZERO
	var end: = Vector3.ZERO
	var coil: float = 0.0
	var uncoil: float = 0.0
	var settle: float = 0.0
	match name:
		"BLOCK":
			prep = Vector3(0.0, 0.008, 0.025)
			end = Vector3(-side * 0.012, -0.022, -lerpf(0.035, 0.085, pace))
			windup.weight_shift = 0.02
			finish.weight_shift = -0.12
			settle = 0.02
		"RESET":
			prep = Vector3(side * 0.01, 0.012, 0.018)
			end = Vector3(-side * 0.022, -0.045, -lerpf(0.045, 0.10, pace))
			windup.weight_shift = 0.0
			finish.weight_shift = -0.18
			settle = 0.035
		"PUNCH":
			prep = Vector3(-side * 0.015, -0.015, -0.055)
			end = Vector3(side * 0.018, 0.025, lerpf(0.07, 0.13, charge))
			coil = 2.5
			uncoil = -3.0
			windup.weight_shift = -0.12
			finish.weight_shift = 0.25
		"COUNTER":
			prep = Vector3(side * 0.025, -0.012, -0.035)
			end = Vector3(-side * 0.07, 0.055, 0.10)
			coil = 4.0
			uncoil = -6.0
			windup.weight_shift = -0.08
			finish.weight_shift = 0.29
		"ROLL":
			prep = Vector3(side * 0.025, -0.11, -0.06)
			end = Vector3(-side * 0.035, 0.20, 0.085)
			coil = 3.0
			uncoil = -5.0
			windup.weight_shift = -0.12
			finish.weight_shift = 0.21
			settle = -0.015
		"FLICK":
			prep = Vector3(side * 0.012, -0.05, -0.02)
			end = Vector3(-side * 0.055, 0.115, 0.05)
			coil = 1.5
			uncoil = -2.5
			windup.weight_shift = -0.03
			finish.weight_shift = 0.14
		"HALF_VOLLEY":
			prep = Vector3(0.0, 0.014, -0.027)
			end = Vector3(-side * 0.012, 0.065, 0.037)
			windup.weight_shift = -0.08
			finish.weight_shift = 0.10
			settle = -0.012
		"JAMMED":
			prep = Vector3(-side * 0.022, 0.012, -0.018)
			end = Vector3(side * 0.058, 0.045, 0.035)
			coil = -5.0
			uncoil = 3.0
			windup.weight_shift = -0.10
			finish.weight_shift = 0.05
			# Clearance is a capped torso request; never a root or ball translation.
			windup.body_position_offset += Vector3(-side * 0.025, 0.0, -0.022)
			finish.body_position_offset += Vector3(-side * 0.012, 0.0, -0.008)
			settle = 0.015
		"OFFENSIVE_LOB":
			prep = Vector3(side * 0.012, -0.07, -0.07)
			end = Vector3(-side * 0.025, 0.26, 0.095)
			coil = 2.0
			uncoil = -3.0
			windup.weight_shift = -0.18
			finish.weight_shift = 0.24
			settle = -0.025
	_set_offset(windup, prep * scale)
	_set_offset(finish, end * scale)
	windup.body_yaw_deg += coil * side * scale
	finish.body_yaw_deg += uncoil * side * scale
	windup.torso_yaw_deg += coil * side * 0.35 * scale
	finish.torso_yaw_deg += uncoil * side * 0.35 * scale
	windup.head_yaw_deg -= coil * side * 0.6 * scale
	finish.head_yaw_deg -= uncoil * side * 0.6 * scale
	windup.crouch_amount = clampf(base.crouch_amount + 0.025 * scale, 0.0, 0.65)
	finish.crouch_amount = clampf(base.crouch_amount + settle * scale, 0.0, 0.65)
	# Keep the authored hand mode, grip rotations and support-hand offsets. The
	# existing IK and grip transition own reach, hand seating, and recovery.
	# New endpoint poles use the contact poles, not unrelated authored drive keys.
	def.right_elbow_path = PackedVector3Array()
	def.left_elbow_path = PackedVector3Array()
	_write_endpoint(def, windup, true)
	_write_endpoint(def, finish, false)
	def.set_meta("tactical_profile", name)
	return def

static func sample(base: PostureDefinition, progress: float, context: Dictionary) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	# Preserve the entire accepted contact, including paddle basis and both hands.
	if is_equal_approx(t, 0.5):
		var contact: PostureDefinition = base.lerp_with(base, 0.0)
		contact.set_meta("tactical_profile", str(context.get("profile", "LEGACY")))
		contact.set_meta("visual_wrist_lag_deg", 0.0)
		ElbowPreset.tag(contact, base, t, "stroke_runtime")
		return contact
	var def: PostureDefinition = definition(base, context)
	var pose: PostureDefinition = Path.sample(def, t)
	pose.set_meta("tactical_profile", str(context.get("profile", "LEGACY")))
	pose.set_meta("visual_wrist_lag_deg", 0.0)
	ElbowPreset.tag(pose, base, t, "stroke_runtime")
	return pose

static func _set_offset(pose: PostureDefinition, offset: Vector3) -> void:
	pose.paddle_forehand_mul += offset.x
	pose.paddle_y_offset += offset.y
	pose.paddle_forward_mul += offset.z

static func _write_endpoint(def: PostureDefinition, pose: PostureDefinition, windup: bool) -> void:
	var offset: = Vector3(pose.paddle_forehand_mul - def.paddle_forehand_mul, pose.paddle_y_offset - def.paddle_y_offset, pose.paddle_forward_mul - def.paddle_forward_mul)
	var body: Resource = BodyKey.new()
	body.capture(pose)
	if windup:
		def.charge_paddle_offset = offset
		def.charge_paddle_rotation_deg = Vector3.ZERO
		def.windup_body = body
	else:
		def.ft_paddle_offset = offset
		def.ft_paddle_rotation_deg = Vector3.ZERO
		def.follow_through_body = body
