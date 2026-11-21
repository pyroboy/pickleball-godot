class_name PostureDefinition extends Resource
const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
























@export var posture_id: int = -1
@export var display_name: String = ""
@export var family: int = 2
@export var height_tier: int = 2


@export_group("Paddle Position")

@export var paddle_forehand_mul: float = 0.0

@export var paddle_forward_mul: float = 0.0

@export var paddle_y_offset: float = 0.0




@export_group("Paddle Rotation")
@export var paddle_pitch_base_deg: float = 0.0
@export var paddle_pitch_signed_deg: float = 0.0
@export_enum("None", "SwingSign", "FwdSign") var paddle_pitch_sign_source: int = 0

@export var paddle_yaw_base_deg: float = 0.0
@export var paddle_yaw_signed_deg: float = 0.0
@export_enum("None", "SwingSign", "FwdSign") var paddle_yaw_sign_source: int = 0

@export var paddle_roll_base_deg: float = 0.0
@export var paddle_roll_signed_deg: float = 0.0
@export_enum("None", "SwingSign", "FwdSign") var paddle_roll_sign_source: int = 0


@export var paddle_floor_clearance: float = 0.06


@export_group("Commit Zone")
@export var has_zone: bool = false
@export var zone_x_min: float = 0.0
@export var zone_x_max: float = 0.0
@export var zone_y_min: float = 0.0
@export var zone_y_max: float = 0.0
@export var zone_forward_offset: float = 0.5


@export_group("Right Arm IK")
@export_enum("Right", "Left") var paddle_hand: int = 0
@export var right_hand_offset: Vector3 = Vector3.ZERO

@export var main_grip_rotation_deg: float = 0.0
## Paddle-local shaft spin, counter-rotated at the hand mount to keep its seat.
@export var paddle_in_hand_rotation_deg: float = 0.0
@export var support_grip_rotation_deg: float = 0.0
@export var support_grip_slide_m: float = 0.0
@export_range(0.0, 1.0) var support_index_closure: float = 1.0

@export_range(0.0, 1.0) var support_grip_style: float = 0.0


@export var right_elbow_path: PackedVector3Array = PackedVector3Array()
@export var left_elbow_path: PackedVector3Array = PackedVector3Array()
## Optional, data-only sampled smoothing overlay. Authoring replaces this whole
## dictionary; runtime samplers only read it. Empty preserves the original pose.
@export var elbow_preset_bake: Dictionary = {}
@export var right_elbow_pole: Vector3 = Vector3.ZERO
@export var right_shoulder_rotation_deg: Vector3 = Vector3.ZERO
## Elbow swivel (scripts/elbow_swivel.gd): the paddle elbow's turn around the arm in degrees,
## used with weight elbow_swivel_weight (0 = the older pole + wrist correction, 1 = this angle).
@export var right_elbow_swivel_deg: float = 0.0
@export var left_elbow_swivel_deg: float = 0.0
@export_range(0.0, 1.0) var elbow_swivel_weight: float = 0.0


@export_group("Left Arm IK")
@export_enum("Auto", "PaddleNeck", "AcrossChest", "OverheadLift", "Free") var left_hand_mode: int = 0
@export var left_hand_offset: Vector3 = Vector3.ZERO
@export var left_elbow_pole: Vector3 = Vector3.ZERO
@export var left_shoulder_rotation_deg: Vector3 = Vector3.ZERO


@export_group("Legs")
@export var stance_width: float = 0.35
@export var front_foot_forward: float = 0.12
@export var back_foot_back: float = -0.08
@export var right_foot_yaw_deg: float = 0.0
@export var left_foot_yaw_deg: float = 0.0
## Authored ankle request: positive toes down, negative toes up. Runtime sole
## contact/floor clearance limits the applied angle without changing this value.
@export var right_foot_pitch_deg: float = 0.0
@export var left_foot_pitch_deg: float = 0.0
@export var right_knee_pole: Vector3 = Vector3.ZERO
@export var left_knee_pole: Vector3 = Vector3.ZERO
@export var right_foot_offset: Vector3 = Vector3.ZERO
@export var left_foot_offset: Vector3 = Vector3.ZERO
@export_enum("Right", "Left") var lead_foot: int = 0
@export var crouch_amount: float = 0.0
@export_range(-1.0, 1.0) var weight_shift: float = 0.0


@export_group("Torso")
@export var hip_yaw_deg: float = 0.0
@export var torso_yaw_deg: float = 0.0
@export var torso_pitch_deg: float = 0.0
@export var torso_roll_deg: float = 0.0
@export var spine_curve_deg: float = 0.0

@export_range(0.0, 0.05, 0.001) var shoulder_protraction_m: float = 0.0


@export_group("Body Pivot")
## Stance-space body translation, independent of the authored paddle target.
## X is forehand/sideways, Y is height, Z is forward, in metres.
@export var body_position_offset: Vector3 = Vector3.ZERO
@export var body_yaw_deg: float = 0.0
@export var body_pitch_deg: float = 0.0
@export var body_roll_deg: float = 0.0


@export_group("Head")
@export var head_yaw_deg: float = 0.0
@export var head_pitch_deg: float = 0.0
@export_range(0.0, 1.0) var head_track_ball_weight: float = 1.0


@export_group("Charge")
@export var charge_paddle_offset: Vector3 = Vector3.ZERO
@export var charge_paddle_rotation_deg: Vector3 = Vector3.ZERO
@export var charge_body_rotation_deg: float = 0.0
@export var charge_hip_coil_deg: float = 0.0
@export_range(0.0, 1.0) var charge_back_foot_load: float = 0.7


@export_group("Follow-Through")
@export var ft_paddle_offset: Vector3 = Vector3.ZERO
@export var ft_paddle_rotation_deg: Vector3 = Vector3.ZERO
@export var ft_hip_uncoil_deg: float = 0.0
@export_range(0.0, 1.0) var ft_front_foot_load: float = 0.85
@export var ft_duration_strike: float = 0.09
@export var ft_duration_sweep: float = 0.18
@export var ft_duration_settle: float = 0.15
@export var ft_duration_hold: float = 0.12


@export_range(0.0, 1.0) var compact_finish_lateral_scale: float = 0.82
@export_range(0.0, 1.0) var compact_motion_scale: float = 1.0
@export var compact_finish_elbow_offset: Vector3 = Vector3.ZERO
@export_enum("ExpoOut", "QuadOut", "SineInOut") var ft_ease_curve: int = 0
@export_range(0.0, 1.0) var swing_path_blend: float = 1.0
## Paddle path keys (Pose Studio swing arc): points the paddle passes through between the keys.
## Key i is at stroke progress paddle_path_times[i] (0 = Wind-up, 0.5 = Contact, 1 = Finish;
## never on those three) and pushes the paddle by paddle_path_offsets[i] (forehand, up,
## forward metres) off the normal curve; Wind-up, Contact and Finish themselves never move.
@export var paddle_path_times: PackedFloat32Array = PackedFloat32Array()
@export var paddle_path_offsets: PackedVector3Array = PackedVector3Array()
## Shape only the bend around Contact. The middle value preserves existing motion.
@export_range(0.0, 1.0) var contact_curve: float = 0.5
## Ready -> Wind-up paddle path shape (ready_windup_curve.gd). Auto 0 and bow 0 = the old straight move.
@export_range(0.0, 1.0) var ready_curve_auto: float = 1.0
@export_range(0.0, 1.0) var ready_curve_bow: float = 0.0
@export_range(0.0, 1.0) var ready_curve_round: float = 0.5
@export_range(-180.0, 180.0) var ready_curve_dir_deg: float = 0.0
@export_range(0.05, 0.95) var ready_curve_peak: float = 0.5
## Ready -> Wind-up path keys (Pose Studio AutoPose arc, grey lead-in): key i at lead-in progress
## ready_path_times[i] (0 = Ready, 1 = Wind-up, never on those two) pushes the paddle by
## ready_path_offsets[i] (forehand, up, forward metres) off the Ready -> Wind-up path.
@export var ready_path_times: PackedFloat32Array = PackedFloat32Array()
@export var ready_path_offsets: PackedVector3Array = PackedVector3Array()
@export var windup_body: Resource
@export var follow_through_body: Resource
@export var charge_duration: float = 0.3


@export_group("Variants")
## Backhand-face version of this pose (docs/POSE_STUDIO_SPEC.md stage 7): field name -> value
## overrides (roll, grip, arm, charge / finish rotations; "windup_body" / "follow_through_body"
## take a StrokeBodyKeyframe). Empty = no variant. Data only: nothing in the game reads it until
## the stage 7 hookup, behind a setting, after the look is approved.
@export var backhand_face_variant: Dictionary = {}

var _variant_cache: Resource = null

@export_group("Metadata")
@export var schema_version: int = 1
@export_multiline var notes: String = ""
@export var last_tuned_by: String = ""
@export var last_tuned_at: String = ""




func resolve_paddle_rotation_deg(swing_sign: float, fwd_sign: float) -> Vector3:
	return Vector3(
		paddle_pitch_base_deg + paddle_pitch_signed_deg * _sign_for(paddle_pitch_sign_source, swing_sign, fwd_sign), 
		paddle_yaw_base_deg + paddle_yaw_signed_deg * _sign_for(paddle_yaw_sign_source, swing_sign, fwd_sign), 
		paddle_roll_base_deg + paddle_roll_signed_deg * _sign_for(paddle_roll_sign_source, swing_sign, fwd_sign), 
	)




func resolve_paddle_offset(forehand_axis: Vector3, forward_axis: Vector3) -> Vector3:
	return forehand_axis * paddle_forehand_mul\
	+ forward_axis * paddle_forward_mul\
	+ Vector3(0.0, paddle_y_offset, 0.0)




static func blend_elbow_pole(a: Vector3, b: Vector3, weight: float, right_arm: bool) -> Vector3:
	var t: float = clampf(weight, 0.0, 1.0)
	if t <= 0.0: return a
	if t >= 1.0: return b
	if a.length_squared() <= 1e-10 and b.length_squared() <= 1e-10: return Vector3.ZERO
	var fallback: = Vector3(0.5 if right_arm else -0.5, -1.0, -0.5)
	var start: Vector3 = fallback if a.length_squared() <= 1e-10 else a
	var finish: Vector3 = fallback if b.length_squared() <= 1e-10 else b
	return start.lerp(finish, t)


func lerp_with(other, w: float):
	var t: float = clampf(w, 0.0, 1.0)
	var o = load("res://scripts/posture_definition.gd").new()
	o.posture_id = posture_id
	o.display_name = display_name
	o.family = family
	o.height_tier = height_tier if t < 0.5 else other.height_tier
	o.paddle_forehand_mul = lerpf(paddle_forehand_mul, other.paddle_forehand_mul, t)
	o.paddle_forward_mul = lerpf(paddle_forward_mul, other.paddle_forward_mul, t)
	o.paddle_y_offset = lerpf(paddle_y_offset, other.paddle_y_offset, t)
	o.paddle_pitch_base_deg = lerpf(paddle_pitch_base_deg, other.paddle_pitch_base_deg, t)
	o.paddle_pitch_signed_deg = lerpf(paddle_pitch_signed_deg, other.paddle_pitch_signed_deg, t)
	o.paddle_pitch_sign_source = paddle_pitch_sign_source if t < 0.5 else other.paddle_pitch_sign_source
	o.paddle_yaw_base_deg = lerpf(paddle_yaw_base_deg, other.paddle_yaw_base_deg, t)
	o.paddle_yaw_signed_deg = lerpf(paddle_yaw_signed_deg, other.paddle_yaw_signed_deg, t)
	o.paddle_yaw_sign_source = paddle_yaw_sign_source if t < 0.5 else other.paddle_yaw_sign_source
	o.paddle_roll_base_deg = lerpf(paddle_roll_base_deg, other.paddle_roll_base_deg, t)
	o.paddle_roll_signed_deg = lerpf(paddle_roll_signed_deg, other.paddle_roll_signed_deg, t)
	o.paddle_roll_sign_source = paddle_roll_sign_source if t < 0.5 else other.paddle_roll_sign_source
	o.paddle_floor_clearance = lerpf(paddle_floor_clearance, other.paddle_floor_clearance, t)
	o.has_zone = has_zone if t < 0.5 else other.has_zone
	o.zone_x_min = lerpf(zone_x_min, other.zone_x_min, t)
	o.zone_x_max = lerpf(zone_x_max, other.zone_x_max, t)
	o.zone_y_min = lerpf(zone_y_min, other.zone_y_min, t)
	o.zone_y_max = lerpf(zone_y_max, other.zone_y_max, t)
	o.zone_forward_offset = lerpf(zone_forward_offset, other.zone_forward_offset, t)
	o.right_hand_offset = right_hand_offset.lerp(other.right_hand_offset, t)
	o.main_grip_rotation_deg = PaddleRotation.angle_lerp(main_grip_rotation_deg, other.main_grip_rotation_deg, t)
	o.paddle_in_hand_rotation_deg = PaddleRotation.angle_lerp(paddle_in_hand_rotation_deg, other.paddle_in_hand_rotation_deg, t)
	o.support_grip_rotation_deg = PaddleRotation.angle_lerp(support_grip_rotation_deg, other.support_grip_rotation_deg, t)
	o.support_grip_slide_m = lerpf(support_grip_slide_m, other.support_grip_slide_m, t)
	o.support_index_closure = lerpf(support_index_closure, other.support_index_closure, t)
	o.support_grip_style = lerpf(support_grip_style, other.support_grip_style, t)
	o.right_elbow_path = right_elbow_path if t < 0.5 else other.right_elbow_path
	o.left_elbow_path = left_elbow_path if t < 0.5 else other.left_elbow_path
	# Like authored path arrays, immutable bake data is shared by transient samples.
	# Persistence and editor copies deep-copy it at their transaction boundaries.
	o.elbow_preset_bake = elbow_preset_bake if t < 0.5 else other.elbow_preset_bake
	o.paddle_hand = paddle_hand if t < 0.5 else other.paddle_hand
	o.right_elbow_pole = blend_elbow_pole(right_elbow_pole, other.right_elbow_pole, t, true)
	o.right_shoulder_rotation_deg = right_shoulder_rotation_deg.lerp(other.right_shoulder_rotation_deg, t)
	var swivel: Array = load("res://scripts/elbow_swivel.gd").blend(self, other, t)
	o.right_elbow_swivel_deg = swivel[0]; o.left_elbow_swivel_deg = swivel[1]; o.elbow_swivel_weight = swivel[2]
	o.left_hand_mode = left_hand_mode if t < 0.5 else other.left_hand_mode
	o.left_hand_offset = left_hand_offset.lerp(other.left_hand_offset, t)
	o.left_elbow_pole = blend_elbow_pole(left_elbow_pole, other.left_elbow_pole, t, false)
	o.left_shoulder_rotation_deg = left_shoulder_rotation_deg.lerp(other.left_shoulder_rotation_deg, t)
	o.stance_width = lerpf(stance_width, other.stance_width, t)
	o.front_foot_forward = lerpf(front_foot_forward, other.front_foot_forward, t)
	o.back_foot_back = lerpf(back_foot_back, other.back_foot_back, t)
	o.right_foot_yaw_deg = lerpf(right_foot_yaw_deg, other.right_foot_yaw_deg, t)
	o.left_foot_yaw_deg = lerpf(left_foot_yaw_deg, other.left_foot_yaw_deg, t)
	o.right_foot_pitch_deg = lerpf(right_foot_pitch_deg, other.right_foot_pitch_deg, t)
	o.left_foot_pitch_deg = lerpf(left_foot_pitch_deg, other.left_foot_pitch_deg, t)
	o.right_knee_pole = right_knee_pole.lerp(other.right_knee_pole, t)
	o.left_knee_pole = left_knee_pole.lerp(other.left_knee_pole, t)
	o.right_foot_offset = right_foot_offset.lerp(other.right_foot_offset, t)
	o.left_foot_offset = left_foot_offset.lerp(other.left_foot_offset, t)
	o.lead_foot = lead_foot if t < 0.5 else other.lead_foot
	if lead_foot != other.lead_foot:
		# Lead is a discrete label, but each named foot needs a continuous path.
		# Compensate only this sampled pose; authored anchors remain untouched.
		var right_forward: float = lerpf(front_foot_forward if lead_foot == 0 else back_foot_back, other.front_foot_forward if other.lead_foot == 0 else other.back_foot_back, t)
		var left_forward: float = lerpf(back_foot_back if lead_foot == 0 else front_foot_forward, other.back_foot_back if other.lead_foot == 0 else other.front_foot_forward, t)
		o.right_foot_offset.z += right_forward - (o.front_foot_forward if o.lead_foot == 0 else o.back_foot_back)
		o.left_foot_offset.z += left_forward - (o.back_foot_back if o.lead_foot == 0 else o.front_foot_forward)
	o.crouch_amount = lerpf(crouch_amount, other.crouch_amount, t)
	o.weight_shift = lerpf(weight_shift, other.weight_shift, t)
	o.hip_yaw_deg = lerpf(hip_yaw_deg, other.hip_yaw_deg, t)
	o.torso_yaw_deg = lerpf(torso_yaw_deg, other.torso_yaw_deg, t)
	o.torso_pitch_deg = lerpf(torso_pitch_deg, other.torso_pitch_deg, t)
	o.torso_roll_deg = lerpf(torso_roll_deg, other.torso_roll_deg, t)
	o.spine_curve_deg = lerpf(spine_curve_deg, other.spine_curve_deg, t)
	o.shoulder_protraction_m = lerpf(shoulder_protraction_m, other.shoulder_protraction_m, t)
	o.body_position_offset = body_position_offset.lerp(other.body_position_offset, t)
	o.body_yaw_deg = lerpf(body_yaw_deg, other.body_yaw_deg, t)
	o.body_pitch_deg = lerpf(body_pitch_deg, other.body_pitch_deg, t)
	o.body_roll_deg = lerpf(body_roll_deg, other.body_roll_deg, t)
	o.head_yaw_deg = lerpf(head_yaw_deg, other.head_yaw_deg, t)
	o.head_pitch_deg = lerpf(head_pitch_deg, other.head_pitch_deg, t)
	o.head_track_ball_weight = lerpf(head_track_ball_weight, other.head_track_ball_weight, t)
	o.charge_paddle_offset = charge_paddle_offset.lerp(other.charge_paddle_offset, t)
	o.charge_paddle_rotation_deg = PaddleRotation.vector_lerp(charge_paddle_rotation_deg, other.charge_paddle_rotation_deg, t)
	o.charge_body_rotation_deg = lerpf(charge_body_rotation_deg, other.charge_body_rotation_deg, t)
	o.charge_hip_coil_deg = lerpf(charge_hip_coil_deg, other.charge_hip_coil_deg, t)
	o.charge_back_foot_load = lerpf(charge_back_foot_load, other.charge_back_foot_load, t)
	o.ft_paddle_offset = ft_paddle_offset.lerp(other.ft_paddle_offset, t)
	o.ft_paddle_rotation_deg = PaddleRotation.vector_lerp(ft_paddle_rotation_deg, other.ft_paddle_rotation_deg, t)
	o.ft_hip_uncoil_deg = lerpf(ft_hip_uncoil_deg, other.ft_hip_uncoil_deg, t)
	o.ft_front_foot_load = lerpf(ft_front_foot_load, other.ft_front_foot_load, t)
	o.ft_duration_strike = lerpf(ft_duration_strike, other.ft_duration_strike, t)
	o.ft_duration_sweep = lerpf(ft_duration_sweep, other.ft_duration_sweep, t)
	o.ft_duration_settle = lerpf(ft_duration_settle, other.ft_duration_settle, t)
	o.ft_duration_hold = lerpf(ft_duration_hold, other.ft_duration_hold, t)
	o.compact_finish_lateral_scale = lerpf(compact_finish_lateral_scale, other.compact_finish_lateral_scale, t)
	o.compact_motion_scale = lerpf(compact_motion_scale, other.compact_motion_scale, t)
	o.compact_finish_elbow_offset = compact_finish_elbow_offset.lerp(other.compact_finish_elbow_offset, t)
	o.ft_ease_curve = ft_ease_curve if t < 0.5 else other.ft_ease_curve
	o.swing_path_blend = lerpf(swing_path_blend, other.swing_path_blend, t)
	o.paddle_path_times = (paddle_path_times if t < 0.5 else other.paddle_path_times).duplicate()
	o.paddle_path_offsets = (paddle_path_offsets if t < 0.5 else other.paddle_path_offsets).duplicate()
	o.contact_curve = lerpf(contact_curve, other.contact_curve, t)
	o.ready_curve_auto = lerpf(ready_curve_auto, other.ready_curve_auto, t)
	o.ready_curve_bow = lerpf(ready_curve_bow, other.ready_curve_bow, t)
	o.ready_curve_round = lerpf(ready_curve_round, other.ready_curve_round, t)
	o.ready_curve_dir_deg = rad_to_deg(lerp_angle(deg_to_rad(ready_curve_dir_deg), deg_to_rad(other.ready_curve_dir_deg), t))
	o.ready_curve_peak = lerpf(ready_curve_peak, other.ready_curve_peak, t)
	o.ready_path_times = (ready_path_times if t < 0.5 else other.ready_path_times).duplicate()
	o.ready_path_offsets = (ready_path_offsets if t < 0.5 else other.ready_path_offsets).duplicate()
	o.windup_body = windup_body
	o.follow_through_body = follow_through_body
	o.charge_duration = lerpf(charge_duration, other.charge_duration, t)
	o.schema_version = schema_version
	o.notes = notes
	o.last_tuned_by = last_tuned_by
	o.last_tuned_at = last_tuned_at
	PaddleRotation.blend_into(o, self, other, t)
	return o


func _sign_for(source: int, swing_sign: float, fwd_sign: float) -> float:
	match source:
		1: return swing_sign
		2: return fwd_sign
		_: return 1.0
