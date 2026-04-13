class_name BasePoseDefinition extends Resource

const _PostureDefinition = preload("res://scripts/posture_definition.gd")

## Body-only authored pose data that layers underneath a stroke/contact posture.
##
## These resources do not own paddle contact geometry, charge, or follow-through.
## They only define the player's base stance, body orientation, support-arm posture,
## foot placement bias, and timing metadata used by PoseController.

# ── Identity ────────────────────────────────────────────────────────────────
@export var base_pose_id: int = -1
@export var display_name: String = ""
@export var canonical_intent: int = 0
@export_range(0.0, 1.0) var stroke_overlay_mix: float = 0.82

# ── Runtime metadata ────────────────────────────────────────────────────────
@export_group("Runtime")
@export var recovery_time: float = 0.12
@export var landing_lockout_time: float = 0.12
@export var jump_window: float = 0.36
@export var split_step_hop_height: float = 0.0
@export var lunge_distance: float = 0.0

# ── Right arm IK / support posture ──────────────────────────────────────────
@export_group("Right Arm IK")
@export var right_hand_offset: Vector3 = Vector3.ZERO
@export var right_elbow_pole: Vector3 = Vector3.ZERO
@export var right_shoulder_rotation_deg: Vector3 = Vector3.ZERO

# ── Left arm IK / support posture ───────────────────────────────────────────
@export_group("Left Arm IK")
@export_enum("Free", "PaddleNeck", "AcrossChest", "OverheadLift") var left_hand_mode: int = 0
@export var left_hand_offset: Vector3 = Vector3.ZERO
@export var left_elbow_pole: Vector3 = Vector3.ZERO
@export var left_shoulder_rotation_deg: Vector3 = Vector3.ZERO

# ── Legs / stance ───────────────────────────────────────────────────────────
@export_group("Legs")
@export var stance_width: float = 0.35
@export var front_foot_forward: float = 0.12
@export var back_foot_back: float = -0.08
@export var right_foot_yaw_deg: float = 0.0
@export var left_foot_yaw_deg: float = 0.0
@export var right_knee_pole: Vector3 = Vector3.ZERO
@export var left_knee_pole: Vector3 = Vector3.ZERO
@export var right_foot_offset: Vector3 = Vector3.ZERO
@export var left_foot_offset: Vector3 = Vector3.ZERO
@export_enum("Right", "Left") var lead_foot: int = 0
@export var crouch_amount: float = 0.0
@export_range(-1.0, 1.0) var weight_shift: float = 0.0

# ── Torso / body pivot ──────────────────────────────────────────────────────
@export_group("Torso")
@export var hip_yaw_deg: float = 0.0
@export var torso_yaw_deg: float = 0.0
@export var torso_pitch_deg: float = 0.0
@export var torso_roll_deg: float = 0.0
@export var spine_curve_deg: float = 0.0

@export_group("Body Pivot")
@export var body_yaw_deg: float = 0.0
@export var body_pitch_deg: float = 0.0
@export var body_roll_deg: float = 0.0

# ── Head ────────────────────────────────────────────────────────────────────
@export_group("Head")
@export var head_yaw_deg: float = 0.0
@export var head_pitch_deg: float = 0.0
@export_range(0.0, 1.0) var head_track_ball_weight: float = 1.0

# ── Metadata ────────────────────────────────────────────────────────────────
@export_group("Metadata")
@export var schema_version: int = 1
@export_multiline var notes: String = ""
@export var last_tuned_by: String = ""
@export var last_tuned_at: String = ""


func duplicate_pose():
	var pose = load("res://scripts/base_pose_definition.gd").new()
	_copy_fields_to(pose)
	return pose


func blend_onto_stroke(stroke_def, weight: float = -1.0):
	if stroke_def == null:
		return null

	var mix: float = stroke_overlay_mix if weight < 0.0 else weight
	mix = clampf(mix, 0.0, 1.0)

	var blended = stroke_def.lerp_with(stroke_def, 0.0)
	_apply_body_fields(blended, stroke_def, mix)
	return blended


func to_preview_posture(stroke_def):
	return blend_onto_stroke(stroke_def, 1.0)


func _copy_fields_to(other) -> void:
	other.base_pose_id = base_pose_id
	other.display_name = display_name
	other.canonical_intent = canonical_intent
	other.stroke_overlay_mix = stroke_overlay_mix
	other.recovery_time = recovery_time
	other.landing_lockout_time = landing_lockout_time
	other.jump_window = jump_window
	other.split_step_hop_height = split_step_hop_height
	other.lunge_distance = lunge_distance
	other.right_hand_offset = right_hand_offset
	other.right_elbow_pole = right_elbow_pole
	other.right_shoulder_rotation_deg = right_shoulder_rotation_deg
	other.left_hand_mode = left_hand_mode
	other.left_hand_offset = left_hand_offset
	other.left_elbow_pole = left_elbow_pole
	other.left_shoulder_rotation_deg = left_shoulder_rotation_deg
	other.stance_width = stance_width
	other.front_foot_forward = front_foot_forward
	other.back_foot_back = back_foot_back
	other.right_foot_yaw_deg = right_foot_yaw_deg
	other.left_foot_yaw_deg = left_foot_yaw_deg
	other.right_knee_pole = right_knee_pole
	other.left_knee_pole = left_knee_pole
	other.right_foot_offset = right_foot_offset
	other.left_foot_offset = left_foot_offset
	other.lead_foot = lead_foot
	other.crouch_amount = crouch_amount
	other.weight_shift = weight_shift
	other.hip_yaw_deg = hip_yaw_deg
	other.torso_yaw_deg = torso_yaw_deg
	other.torso_pitch_deg = torso_pitch_deg
	other.torso_roll_deg = torso_roll_deg
	other.spine_curve_deg = spine_curve_deg
	other.body_yaw_deg = body_yaw_deg
	other.body_pitch_deg = body_pitch_deg
	other.body_roll_deg = body_roll_deg
	other.head_yaw_deg = head_yaw_deg
	other.head_pitch_deg = head_pitch_deg
	other.head_track_ball_weight = head_track_ball_weight
	other.schema_version = schema_version
	other.notes = notes
	other.last_tuned_by = last_tuned_by
	other.last_tuned_at = last_tuned_at


func _apply_body_fields(target, source, mix: float) -> void:
	target.right_hand_offset = source.right_hand_offset.lerp(right_hand_offset, mix)
	target.right_elbow_pole = source.right_elbow_pole.lerp(right_elbow_pole, mix)
	target.right_shoulder_rotation_deg = source.right_shoulder_rotation_deg.lerp(right_shoulder_rotation_deg, mix)
	target.left_hand_mode = source.left_hand_mode if mix < 0.5 else left_hand_mode
	target.left_hand_offset = source.left_hand_offset.lerp(left_hand_offset, mix)
	target.left_elbow_pole = source.left_elbow_pole.lerp(left_elbow_pole, mix)
	target.left_shoulder_rotation_deg = source.left_shoulder_rotation_deg.lerp(left_shoulder_rotation_deg, mix)
	target.stance_width = lerpf(source.stance_width, stance_width, mix)
	target.front_foot_forward = lerpf(source.front_foot_forward, front_foot_forward, mix)
	target.back_foot_back = lerpf(source.back_foot_back, back_foot_back, mix)
	target.right_foot_yaw_deg = lerpf(source.right_foot_yaw_deg, right_foot_yaw_deg, mix)
	target.left_foot_yaw_deg = lerpf(source.left_foot_yaw_deg, left_foot_yaw_deg, mix)
	target.right_knee_pole = source.right_knee_pole.lerp(right_knee_pole, mix)
	target.left_knee_pole = source.left_knee_pole.lerp(left_knee_pole, mix)
	target.right_foot_offset = source.right_foot_offset.lerp(right_foot_offset, mix)
	target.left_foot_offset = source.left_foot_offset.lerp(left_foot_offset, mix)
	target.lead_foot = source.lead_foot if mix < 0.5 else lead_foot
	target.crouch_amount = lerpf(source.crouch_amount, crouch_amount, mix)
	target.weight_shift = lerpf(source.weight_shift, weight_shift, mix)
	target.hip_yaw_deg = lerpf(source.hip_yaw_deg, hip_yaw_deg, mix)
	target.torso_yaw_deg = lerpf(source.torso_yaw_deg, torso_yaw_deg, mix)
	target.torso_pitch_deg = lerpf(source.torso_pitch_deg, torso_pitch_deg, mix)
	target.torso_roll_deg = lerpf(source.torso_roll_deg, torso_roll_deg, mix)
	target.spine_curve_deg = lerpf(source.spine_curve_deg, spine_curve_deg, mix)
	target.body_yaw_deg = lerpf(source.body_yaw_deg, body_yaw_deg, mix)
	target.body_pitch_deg = lerpf(source.body_pitch_deg, body_pitch_deg, mix)
	target.body_roll_deg = lerpf(source.body_roll_deg, body_roll_deg, mix)
	target.head_yaw_deg = lerpf(source.head_yaw_deg, head_yaw_deg, mix)
	target.head_pitch_deg = lerpf(source.head_pitch_deg, head_pitch_deg, mix)
	target.head_track_ball_weight = lerpf(source.head_track_ball_weight, head_track_ball_weight, mix)
