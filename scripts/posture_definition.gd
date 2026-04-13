class_name PostureDefinition extends Resource

## Full-body definition of a single paddle posture.
##
## One Resource per posture. Loaded by PostureLibrary and consumed by
## PlayerPaddlePosture, PlayerHitting, PlayerBodyAnimation, PlayerArmIK
## (wiring happens in Phase 2+).
##
## Fields grouped by subsystem:
##   - Identity
##   - Paddle position/rotation + commit zone
##   - Right arm IK (paddle hand)
##   - Left arm IK (two-handed grip / guard hand)
##   - Legs / stance
##   - Hips / torso
##   - Head
##   - Charge (pre-swing wind-up)
##   - Follow-through (post-contact)
##
## Sign-source fields encode whether an angle is multiplied by
## _get_swing_sign() or _get_forward_axis().z at runtime. This is how
## the current hardcoded functions handle blue-vs-red mirroring — we
## preserve the pattern so gameplay stays byte-identical.

# ── Identity ────────────────────────────────────────────────────────
@export var posture_id: int = -1          ## PaddlePosture enum value
@export var display_name: String = ""     ## e.g. "Low Wide Forehand"
@export var family: int = 2               ## 0=FH, 1=BH, 2=center, 3=overhead
@export var height_tier: int = 2          ## 0=LOW, 1=MID_LOW, 2=NORMAL, 3=OVERHEAD

# ── Paddle position ─────────────────────────────────────────────────
@export_group("Paddle Position")
## forehand-axis multiplier (sideways). + = forehand side, - = backhand side.
@export var paddle_forehand_mul: float = 0.0
## forward-axis multiplier. + = out toward net, - = behind player (charge).
@export var paddle_forward_mul: float = 0.0
## vertical offset relative to player origin (world Y).
@export var paddle_y_offset: float = 0.0

# ── Paddle rotation ─────────────────────────────────────────────────
## Each rotation axis = (base_deg) + (signed_deg * sign_source)
## sign_source: 0 = no sign (pure base), 1 = swing_sign, 2 = fwd_sign
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

## Floor clearance for paddle head. 0.06 normal, 0.45 for inverted (LOW) postures.
@export var paddle_floor_clearance: float = 0.06

# ── Commit zone (replaces POSTURE_ZONES dict) ───────────────────────
@export_group("Commit Zone")
@export var has_zone: bool = false        ## some postures (charge, ready) have no zone
@export var zone_x_min: float = 0.0
@export var zone_x_max: float = 0.0
@export var zone_y_min: float = 0.0
@export var zone_y_max: float = 0.0

# ── Right arm IK (paddle hand) — Phase 3 wiring ─────────────────────
@export_group("Right Arm IK")
@export var right_hand_offset: Vector3 = Vector3.ZERO
@export var right_elbow_pole: Vector3 = Vector3.ZERO
@export var right_shoulder_rotation_deg: Vector3 = Vector3.ZERO

# ── Left arm IK (two-handed grip / guard hand) — Phase 3 wiring ─────
@export_group("Left Arm IK")
@export_enum("Free", "PaddleNeck", "AcrossChest", "OverheadLift") var left_hand_mode: int = 0
@export var left_hand_offset: Vector3 = Vector3.ZERO
@export var left_elbow_pole: Vector3 = Vector3.ZERO
@export var left_shoulder_rotation_deg: Vector3 = Vector3.ZERO

# ── Legs / stance — Phase 3 wiring ──────────────────────────────────
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

# ── Hips / torso — Phase 3 wiring ───────────────────────────────────
@export_group("Torso")
@export var hip_yaw_deg: float = 0.0
@export var torso_yaw_deg: float = 0.0
@export var torso_pitch_deg: float = 0.0
@export var torso_roll_deg: float = 0.0
@export var spine_curve_deg: float = 0.0

# ── Body Pivot (whole-body rotation) — Phase 3 wiring ────────────────
@export_group("Body Pivot")
@export var body_yaw_deg: float = 0.0     # Rotation around Y axis (stance direction)
@export var body_pitch_deg: float = 0.0  # Forward/back lean
@export var body_roll_deg: float = 0.0    # Side-to-side lean

# ── Head — Phase 3 wiring ───────────────────────────────────────────
@export_group("Head")
@export var head_yaw_deg: float = 0.0
@export var head_pitch_deg: float = 0.0
@export_range(0.0, 1.0) var head_track_ball_weight: float = 1.0

# ── Charge (pre-swing wind-up) ──────────────────────────────────────
@export_group("Charge")
@export var charge_paddle_offset: Vector3 = Vector3.ZERO
@export var charge_paddle_rotation_deg: Vector3 = Vector3.ZERO
@export var charge_body_rotation_deg: float = 0.0
@export var charge_hip_coil_deg: float = 0.0
@export_range(0.0, 1.0) var charge_back_foot_load: float = 0.7

# ── Follow-through (post-contact) ───────────────────────────────────
@export_group("Follow-Through")
@export var ft_paddle_offset: Vector3 = Vector3.ZERO
@export var ft_paddle_rotation_deg: Vector3 = Vector3.ZERO
@export var ft_hip_uncoil_deg: float = 0.0
@export_range(0.0, 1.0) var ft_front_foot_load: float = 0.85
@export var ft_duration_strike: float = 0.09
@export var ft_duration_sweep: float = 0.18
@export var ft_duration_settle: float = 0.15
@export var ft_duration_hold: float = 0.12
@export_enum("ExpoOut", "QuadOut", "SineInOut") var ft_ease_curve: int = 0

# ── Metadata ────────────────────────────────────────────────────────
@export_group("Metadata")
@export var schema_version: int = 1
@export_multiline var notes: String = ""
@export var last_tuned_by: String = ""
@export var last_tuned_at: String = ""


## Resolve the signed-angle pattern used by _get_posture_rotation_offset_for().
## Caller passes swing_sign and fwd_sign; we apply whichever source each axis wants.
func resolve_paddle_rotation_deg(swing_sign: float, fwd_sign: float) -> Vector3:
	return Vector3(
		paddle_pitch_base_deg + paddle_pitch_signed_deg * _sign_for(paddle_pitch_sign_source, swing_sign, fwd_sign),
		paddle_yaw_base_deg + paddle_yaw_signed_deg * _sign_for(paddle_yaw_sign_source, swing_sign, fwd_sign),
		paddle_roll_base_deg + paddle_roll_signed_deg * _sign_for(paddle_roll_sign_source, swing_sign, fwd_sign),
	)


## Resolve the paddle position offset given the player's local axes.
## Mirrors get_posture_offset_for() structure: forehand_mul * fh + forward_mul * fwd + (0, y, 0).
func resolve_paddle_offset(forehand_axis: Vector3, forward_axis: Vector3) -> Vector3:
	return forehand_axis * paddle_forehand_mul \
		+ forward_axis * paddle_forward_mul \
		+ Vector3(0.0, paddle_y_offset, 0.0)


## Blend numeric fields toward `other` for smooth transition playback (t = 0 → self, 1 → other).
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
	o.right_hand_offset = right_hand_offset.lerp(other.right_hand_offset, t)
	o.right_elbow_pole = right_elbow_pole.lerp(other.right_elbow_pole, t)
	o.right_shoulder_rotation_deg = right_shoulder_rotation_deg.lerp(other.right_shoulder_rotation_deg, t)
	o.left_hand_mode = left_hand_mode if t < 0.5 else other.left_hand_mode
	o.left_hand_offset = left_hand_offset.lerp(other.left_hand_offset, t)
	o.left_elbow_pole = left_elbow_pole.lerp(other.left_elbow_pole, t)
	o.left_shoulder_rotation_deg = left_shoulder_rotation_deg.lerp(other.left_shoulder_rotation_deg, t)
	o.stance_width = lerpf(stance_width, other.stance_width, t)
	o.front_foot_forward = lerpf(front_foot_forward, other.front_foot_forward, t)
	o.back_foot_back = lerpf(back_foot_back, other.back_foot_back, t)
	o.right_foot_yaw_deg = lerpf(right_foot_yaw_deg, other.right_foot_yaw_deg, t)
	o.left_foot_yaw_deg = lerpf(left_foot_yaw_deg, other.left_foot_yaw_deg, t)
	o.right_knee_pole = right_knee_pole.lerp(other.right_knee_pole, t)
	o.left_knee_pole = left_knee_pole.lerp(other.left_knee_pole, t)
	o.right_foot_offset = right_foot_offset.lerp(other.right_foot_offset, t)
	o.left_foot_offset = left_foot_offset.lerp(other.left_foot_offset, t)
	o.lead_foot = lead_foot if t < 0.5 else other.lead_foot
	o.crouch_amount = lerpf(crouch_amount, other.crouch_amount, t)
	o.weight_shift = lerpf(weight_shift, other.weight_shift, t)
	o.hip_yaw_deg = lerpf(hip_yaw_deg, other.hip_yaw_deg, t)
	o.torso_yaw_deg = lerpf(torso_yaw_deg, other.torso_yaw_deg, t)
	o.torso_pitch_deg = lerpf(torso_pitch_deg, other.torso_pitch_deg, t)
	o.torso_roll_deg = lerpf(torso_roll_deg, other.torso_roll_deg, t)
	o.spine_curve_deg = lerpf(spine_curve_deg, other.spine_curve_deg, t)
	o.body_yaw_deg = lerpf(body_yaw_deg, other.body_yaw_deg, t)
	o.body_pitch_deg = lerpf(body_pitch_deg, other.body_pitch_deg, t)
	o.body_roll_deg = lerpf(body_roll_deg, other.body_roll_deg, t)
	o.head_yaw_deg = lerpf(head_yaw_deg, other.head_yaw_deg, t)
	o.head_pitch_deg = lerpf(head_pitch_deg, other.head_pitch_deg, t)
	o.head_track_ball_weight = lerpf(head_track_ball_weight, other.head_track_ball_weight, t)
	o.charge_paddle_offset = charge_paddle_offset.lerp(other.charge_paddle_offset, t)
	o.charge_paddle_rotation_deg = charge_paddle_rotation_deg.lerp(other.charge_paddle_rotation_deg, t)
	o.charge_body_rotation_deg = lerpf(charge_body_rotation_deg, other.charge_body_rotation_deg, t)
	o.charge_hip_coil_deg = lerpf(charge_hip_coil_deg, other.charge_hip_coil_deg, t)
	o.charge_back_foot_load = lerpf(charge_back_foot_load, other.charge_back_foot_load, t)
	o.ft_paddle_offset = ft_paddle_offset.lerp(other.ft_paddle_offset, t)
	o.ft_paddle_rotation_deg = ft_paddle_rotation_deg.lerp(other.ft_paddle_rotation_deg, t)
	o.ft_hip_uncoil_deg = lerpf(ft_hip_uncoil_deg, other.ft_hip_uncoil_deg, t)
	o.ft_front_foot_load = lerpf(ft_front_foot_load, other.ft_front_foot_load, t)
	o.ft_duration_strike = lerpf(ft_duration_strike, other.ft_duration_strike, t)
	o.ft_duration_sweep = lerpf(ft_duration_sweep, other.ft_duration_sweep, t)
	o.ft_duration_settle = lerpf(ft_duration_settle, other.ft_duration_settle, t)
	o.ft_duration_hold = lerpf(ft_duration_hold, other.ft_duration_hold, t)
	o.ft_ease_curve = ft_ease_curve if t < 0.5 else other.ft_ease_curve
	o.schema_version = schema_version
	o.notes = notes
	o.last_tuned_by = last_tuned_by
	o.last_tuned_at = last_tuned_at
	return o


func _sign_for(source: int, swing_sign: float, fwd_sign: float) -> float:
	match source:
		1: return swing_sign
		2: return fwd_sign
		_: return 1.0
