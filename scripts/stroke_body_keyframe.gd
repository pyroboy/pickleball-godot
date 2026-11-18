extends Resource
## Absolute body values at wind-up or follow-through; contact uses the stroke itself.
const FIELDS: Array[String] = [
	"stance_width", "front_foot_forward", "back_foot_back", "right_foot_yaw_deg", "left_foot_yaw_deg",
	"right_knee_pole", "left_knee_pole", "right_foot_offset", "left_foot_offset", "lead_foot", "crouch_amount", "weight_shift",
	"hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg",
	"body_yaw_deg", "body_pitch_deg", "body_roll_deg", "head_yaw_deg", "head_pitch_deg", "head_track_ball_weight",
	"right_hand_offset", "left_hand_offset", "right_shoulder_rotation_deg", "left_shoulder_rotation_deg",
	"right_elbow_pole", "left_elbow_pole", "left_hand_mode",
	"paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg",
	"paddle_pitch_sign_source", "paddle_yaw_sign_source", "paddle_roll_sign_source",
]
@export var values: Dictionary = {}

func capture(pose) -> void:
	for field in FIELDS:
		values[field] = pose.get(field)

func apply_to(pose) -> void:
	for field in values:
		if field in FIELDS:
			pose.set(field, values[field])
