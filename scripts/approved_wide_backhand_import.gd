extends RefCounted
## Fixed, user-approved whole-pose payload, not a general JSON import endpoint.
## Source: docs/pose-imports/wide-backhand-2026-10-02.json (same UTF-8 contents).
const ID := "wide_backhand_2026_10_02"
const BASELINE_SHA256 := "384597e79f8a6cadac4d06617699013137363b81051eabcb9f2cece1d6bf02b8"
const SOURCE_SHA256 := "2a626f3eba2e37f5c18db705ce4b11c6c6f028645a6acad829d059b084330a8d"
const JSON_TEXT := """{
  "baseline_sha256": "384597e79f8a6cadac4d06617699013137363b81051eabcb9f2cece1d6bf02b8",
  "family": 1,
  "fields": {
    "back_foot_back": -0.22999999999999998,
    "body_pitch_deg": 0,
    "body_position_offset": [
      0,
      0,
      0
    ],
    "body_roll_deg": 0,
    "body_yaw_deg": -30,
    "charge_back_foot_load": 0.65,
    "charge_body_rotation_deg": -16,
    "charge_duration": 0.32,
    "charge_hip_coil_deg": -12,
    "charge_paddle_offset": [
      0.08091974258422852,
      -0.5992295145988464,
      -0.9726316332817078
    ],
    "charge_paddle_rotation_deg": [
      -18.19997215270996,
      -2.027057647705078,
      26.899999618530273
    ],
    "compact_finish_elbow_offset": [
      0,
      0,
      0
    ],
    "compact_finish_lateral_scale": 0.82,
    "compact_motion_scale": 1,
    "contact_curve": 0.5,
    "crouch_amount": 0.06,
    "follow_through_body": {
      "back_foot_back": 0.43999999999999995,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": 12,
      "crouch_amount": 0.045,
      "front_foot_forward": 0.16,
      "head_pitch_deg": 1,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": -58,
      "hip_yaw_deg": 14,
      "lead_foot": 0,
      "left_elbow_pole": [
        -0.4000000059604645,
        -0.3499999940395355,
        0.10000000149011612
      ],
      "left_foot_offset": [
        -0.07000000029802322,
        0,
        -0.15000000596046448
      ],
      "left_foot_yaw_deg": -5,
      "left_hand_mode": 1,
      "left_hand_offset": [
        0,
        0,
        0
      ],
      "left_knee_pole": [
        0,
        0,
        0
      ],
      "left_shoulder_rotation_deg": [
        0,
        0,
        0
      ],
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 5,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": 18,
      "right_elbow_pole": [
        0.15000000596046448,
        -0.23999999463558197,
        0.23999999463558197
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": 10,
      "right_hand_offset": [
        0,
        0,
        0
      ],
      "right_knee_pole": [
        0,
        0,
        0
      ],
      "right_shoulder_rotation_deg": [
        0,
        0,
        0
      ],
      "spine_curve_deg": 0,
      "stance_width": 0.56,
      "torso_pitch_deg": 0,
      "torso_roll_deg": 0,
      "torso_yaw_deg": 10,
      "weight_shift": 0.72
    },
    "front_foot_forward": 0.16,
    "ft_duration_hold": 0.06,
    "ft_duration_settle": 0.18,
    "ft_duration_strike": 0.12,
    "ft_duration_sweep": 0.28,
    "ft_ease_curve": 2,
    "ft_front_foot_load": 0.8,
    "ft_hip_uncoil_deg": 8,
    "ft_paddle_offset": [
      1.1160376071929932,
      0.33741888403892517,
      0.12471818923950195
    ],
    "ft_paddle_rotation_deg": [
      -18.19997215270996,
      -2.027057647705078,
      152
    ],
    "has_zone": true,
    "head_pitch_deg": -28,
    "head_track_ball_weight": 0.8,
    "head_yaw_deg": -2,
    "hip_yaw_deg": -8,
    "lead_foot": 0,
    "left_elbow_path": [],
    "left_elbow_pole": [
      -0.4000000059604645,
      -0.3499999940395355,
      0.10000000149011612
    ],
    "left_foot_offset": [
      0,
      0,
      0
    ],
    "left_foot_yaw_deg": -95,
    "left_hand_mode": 1,
    "left_hand_offset": [
      0,
      0,
      0
    ],
    "left_knee_pole": [
      0,
      0,
      0
    ],
    "left_shoulder_rotation_deg": [
      0,
      0,
      0
    ],
    "main_grip_rotation_deg": 0,
    "paddle_floor_clearance": 0.03,
    "paddle_forehand_mul": -0.6460376977920532,
    "paddle_forward_mul": 0.6152818202972412,
    "paddle_hand": 0,
    "paddle_in_hand_rotation_deg": 0,
    "paddle_pitch_base_deg": 18.199981609604418,
    "paddle_pitch_sign_source": 1,
    "paddle_pitch_signed_deg": 5,
    "paddle_roll_base_deg": -120,
    "paddle_roll_sign_source": 1,
    "paddle_roll_signed_deg": -40,
    "paddle_y_offset": 0.1492295265197754,
    "paddle_yaw_base_deg": 2.0270567116872233,
    "paddle_yaw_sign_source": 1,
    "paddle_yaw_signed_deg": 29,
    "right_elbow_path": [],
    "right_elbow_pole": [
      0.05999999865889549,
      -0.30000001192092896,
      0.20000000298023224
    ],
    "right_foot_offset": [
      0,
      0,
      0
    ],
    "right_foot_yaw_deg": 6,
    "right_hand_offset": [
      0,
      0,
      0
    ],
    "right_knee_pole": [
      0,
      0,
      0
    ],
    "right_shoulder_rotation_deg": [
      0,
      0,
      0
    ],
    "shoulder_protraction_m": 0,
    "spine_curve_deg": 0,
    "stance_width": 0.56,
    "support_grip_rotation_deg": 0,
    "support_grip_slide_m": 0,
    "support_grip_style": 0,
    "support_index_closure": 1,
    "swing_path_blend": 1,
    "torso_pitch_deg": 0,
    "torso_roll_deg": 0,
    "torso_yaw_deg": -12,
    "weight_shift": 0.2,
    "windup_body": {
      "back_foot_back": -0.43999999999999995,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": -18,
      "crouch_amount": 0.26,
      "front_foot_forward": 0.16,
      "head_pitch_deg": -28,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": 35.28,
      "hip_yaw_deg": -66.3,
      "lead_foot": 0,
      "left_elbow_pole": [
        -0.4000000059604645,
        -0.3499999940395355,
        0.10000000149011612
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": -78,
      "left_hand_mode": 1,
      "left_hand_offset": [
        0,
        0,
        0
      ],
      "left_knee_pole": [
        0,
        0,
        0
      ],
      "left_shoulder_rotation_deg": [
        0,
        0,
        0
      ],
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 77,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 77,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": -22,
      "right_elbow_pole": [
        0.019999999552965164,
        -0.23999999463558197,
        0.019999999552965164
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": -20,
      "right_hand_offset": [
        0,
        0,
        0
      ],
      "right_knee_pole": [
        0,
        0,
        0
      ],
      "right_shoulder_rotation_deg": [
        0,
        0,
        0
      ],
      "spine_curve_deg": 0,
      "stance_width": 0.56,
      "support_grip_style": 0.34,
      "torso_pitch_deg": 0,
      "torso_roll_deg": 0,
      "torso_yaw_deg": -19,
      "weight_shift": -0.68
    },
    "zone_forward_offset": 0.5654,
    "zone_x_max": -0.4461,
    "zone_x_min": -0.8461,
    "zone_y_max": 1.2716,
    "zone_y_min": 0.8716
  },
  "id": 11,
  "kind": "stroke",
  "name": "Wide Backhand",
  "schema": "pickleball.pose",
  "scope": "whole_pose",
  "selected_stage": 2,
  "selected_stage_context": "Editor view only; fields contain the whole pose and all keyframes",
  "selected_stage_name": "Finish",
  "version": 1
}
"""
