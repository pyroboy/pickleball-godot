extends RefCounted
## Fixed, user-approved whole-pose payload, not a general JSON import endpoint.
## Source: docs/pose-imports/wide-forehand-2026-10-02.json (same UTF-8 contents).
const ID := "wide_forehand_2026_10_02"
const BASELINE_SHA256 := "72c0fec1538ce80113be5fe65b308e3068d1442941d16856c78190f5fea8e8b9"
const SOURCE_SHA256 := "418dc0372c11c8b12732a6a78c3514468cfff59e88a761c6f9c73baf991b0c03"
const JSON_TEXT := """{
  "baseline_sha256": "72c0fec1538ce80113be5fe65b308e3068d1442941d16856c78190f5fea8e8b9",
  "family": 0,
  "fields": {
    "back_foot_back": -0.12,
    "body_pitch_deg": 0,
    "body_roll_deg": 0,
    "body_yaw_deg": 41.30000000000001,
    "charge_back_foot_load": 0.65,
    "charge_body_rotation_deg": 16,
    "charge_duration": 0.32,
    "charge_hip_coil_deg": 12,
    "charge_paddle_offset": [
      -0.3299727439880371,
      -0.3707068860530853,
      -0.9633494019508362
    ],
    "charge_paddle_rotation_deg": [
      82.5,
      -113,
      -50.900001525878906
    ],
    "compact_finish_elbow_offset": [
      0,
      0,
      0
    ],
    "compact_finish_lateral_scale": 0.82,
    "compact_motion_scale": 1,
    "crouch_amount": 0.06,
    "follow_through_body": {
      "back_foot_back": -0.12,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": -12,
      "crouch_amount": 0.045,
      "front_foot_forward": 0.16,
      "head_pitch_deg": -28,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": 23.4,
      "hip_yaw_deg": -14,
      "lead_foot": 1,
      "left_elbow_pole": [
        -0.47999998927116394,
        -0.3499999940395355,
        -0.2199999988079071
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 5,
      "left_hand_mode": 4,
      "left_hand_offset": [
        -0.15000000596046448,
        0,
        -0.2199999988079071
      ],
      "left_knee_pole": [
        0,
        0,
        0
      ],
      "left_shoulder_rotation_deg": [
        0,
        8,
        0
      ],
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 5,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": -18,
      "right_elbow_pole": [
        0.47999998927116394,
        -0.3499999940395355,
        -0.2199999988079071
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": -10,
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
        -8,
        0
      ],
      "spine_curve_deg": 0,
      "stance_width": 0.56,
      "torso_pitch_deg": -12,
      "torso_roll_deg": 0,
      "torso_yaw_deg": -10,
      "weight_shift": 0.72
    },
    "front_foot_forward": 0.16,
    "ft_duration_hold": 0.06,
    "ft_duration_settle": 0.18,
    "ft_duration_strike": 0.12,
    "ft_duration_sweep": 0.28,
    "ft_ease_curve": 2,
    "ft_front_foot_load": 0.8,
    "ft_hip_uncoil_deg": -8,
    "ft_paddle_offset": [
      -1.3139727115631104,
      0.3400000035762787,
      0.2856506109237671
    ],
    "ft_paddle_rotation_deg": [
      0,
      0,
      -152
    ],
    "has_zone": true,
    "head_pitch_deg": -28,
    "head_track_ball_weight": 0.8,
    "head_yaw_deg": 2,
    "hip_yaw_deg": -2,
    "lead_foot": 1,
    "left_elbow_path": [],
    "left_elbow_pole": [
      -0.47999998927116394,
      -0.3499999940395355,
      -0.2199999988079071
    ],
    "left_foot_offset": [
      0,
      0,
      0
    ],
    "left_foot_yaw_deg": 5,
    "left_hand_mode": 4,
    "left_hand_offset": [
      -0.15000000596046448,
      0,
      -0.2199999988079071
    ],
    "left_knee_pole": [
      0,
      0,
      0
    ],
    "left_shoulder_rotation_deg": [
      0,
      8,
      0
    ],
    "main_grip_rotation_deg": 0,
    "paddle_floor_clearance": 0.06,
    "paddle_forehand_mul": 0.86797273,
    "paddle_forward_mul": 0.3573494,
    "paddle_hand": 0,
    "paddle_pitch_base_deg": -9.5,
    "paddle_pitch_sign_source": 1,
    "paddle_pitch_signed_deg": 5,
    "paddle_roll_base_deg": 69.9,
    "paddle_roll_sign_source": 1,
    "paddle_roll_signed_deg": 0,
    "paddle_y_offset": 0.16070688,
    "paddle_yaw_base_deg": 0,
    "paddle_yaw_sign_source": 1,
    "paddle_yaw_signed_deg": 0,
    "right_elbow_path": [],
    "right_elbow_pole": [
      0.47999998927116394,
      -0.3499999940395355,
      -0.2199999988079071
    ],
    "right_foot_offset": [
      0,
      0,
      0
    ],
    "right_foot_yaw_deg": 5,
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
      -8,
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
    "torso_yaw_deg": 0,
    "weight_shift": 0.2,
    "windup_body": {
      "back_foot_back": -0.12,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": 18,
      "crouch_amount": 0.13,
      "front_foot_forward": 0.16,
      "head_pitch_deg": -28,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": -35.28,
      "hip_yaw_deg": 12,
      "lead_foot": 1,
      "left_elbow_pole": [
        -0.47999998927116394,
        -0.3499999940395355,
        -0.2199999988079071
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 5,
      "left_hand_mode": 4,
      "left_hand_offset": [
        -0.15000000596046448,
        0,
        -0.2199999988079071
      ],
      "left_knee_pole": [
        0,
        0,
        0
      ],
      "left_shoulder_rotation_deg": [
        0,
        8,
        0
      ],
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 5,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": 22,
      "right_elbow_pole": [
        0.47999998927116394,
        -0.3499999940395355,
        -0.2199999988079071
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": 20,
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
        -8,
        0
      ],
      "spine_curve_deg": -10.899999999999999,
      "stance_width": 0.56,
      "torso_pitch_deg": 0,
      "torso_roll_deg": 0,
      "torso_yaw_deg": 19,
      "weight_shift": -0.68
    },
    "zone_forward_offset": 0.3573,
    "zone_x_max": 1.068,
    "zone_x_min": 0.668,
    "zone_y_max": 1.2857,
    "zone_y_min": 0.8857
  },
  "id": 10,
  "kind": "stroke",
  "name": "Wide Forehand",
  "schema": "pickleball.pose",
  "scope": "whole_pose",
  "selected_stage": 0,
  "selected_stage_context": "Editor view only; fields contain the whole pose and all keyframes",
  "selected_stage_name": "Wind-up",
  "version": 1
}
"""
