extends RefCounted
## Fixed, user-approved whole-pose payload, not a general JSON import endpoint.
## Source: docs/pose-imports/forehand-2026-10-02.json (same UTF-8 contents).
const ID := "forehand_2026_10_02"
const BASELINE_SHA256 := "7d00b5f7c732b64f8f6bef660b37e16f13807b95fe59fd5dd6ce5ceebe44d3ed"
const SOURCE_SHA256 := "0f43987aa1a0f494e3ebde166d069a364e7e1332d4a77ef51e05aa5e538f2ea5"
const JSON_TEXT := """{
  "baseline_sha256": "7d00b5f7c732b64f8f6bef660b37e16f13807b95fe59fd5dd6ce5ceebe44d3ed",
  "family": 0,
  "fields": {
    "back_foot_back": -0.15,
    "body_pitch_deg": 0,
    "body_position_offset": [
      0,
      0,
      0
    ],
    "body_roll_deg": 0,
    "body_yaw_deg": 0,
    "charge_back_foot_load": 0.65,
    "charge_body_rotation_deg": 18,
    "charge_duration": 0.382,
    "charge_hip_coil_deg": 12,
    "charge_paddle_offset": [
      0.205376997590065,
      -0.3119840919971466,
      -1.1377273797988892
    ],
    "charge_paddle_rotation_deg": [
      166.7729949951172,
      91.25482940673828,
      -12.011588096618652
    ],
    "compact_finish_elbow_offset": [
      0,
      0,
      0
    ],
    "compact_finish_lateral_scale": 0.82,
    "compact_motion_scale": 1,
    "contact_curve": 0.5,
    "crouch_amount": 0.07,
    "follow_through_body": {
      "back_foot_back": -0.15,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": -12,
      "crouch_amount": 0.143,
      "front_foot_forward": 0.18,
      "head_pitch_deg": -25,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": 23.4,
      "hip_yaw_deg": -14,
      "lead_foot": 1,
      "left_elbow_pole": [
        0,
        0,
        0
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 5,
      "left_hand_mode": 4,
      "left_hand_offset": [
        -0.28999999165534973,
        -0.1899999976158142,
        -0.3400000035762787
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
      "paddle_pitch_signed_deg": 12,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": -25,
      "right_elbow_pole": [
        -0.5,
        0.5,
        0
      ],
      "right_foot_offset": [
        0,
        0,
        0.05000000074505806
      ],
      "right_foot_yaw_deg": -26.30000000000001,
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
      "stance_width": 0.48,
      "torso_pitch_deg": -3,
      "torso_roll_deg": 0,
      "torso_yaw_deg": -10,
      "weight_shift": 0.72
    },
    "front_foot_forward": 0.18,
    "ft_duration_hold": 0.08,
    "ft_duration_settle": 0.18,
    "ft_duration_strike": 0.12,
    "ft_duration_sweep": 0.28,
    "ft_ease_curve": 2,
    "ft_front_foot_load": 0.8,
    "ft_hip_uncoil_deg": -10,
    "ft_paddle_offset": [
      -0.6819999814033508,
      0.531000018119812,
      0.15000000596046448
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
      0,
      0,
      0
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
      0,
      0
    ],
    "main_grip_rotation_deg": 0,
    "paddle_floor_clearance": 0.053,
    "paddle_forehand_mul": 0.42,
    "paddle_forward_mul": 0.46,
    "paddle_hand": 0,
    "paddle_in_hand_rotation_deg": 0,
    "paddle_pitch_base_deg": 0,
    "paddle_pitch_sign_source": 1,
    "paddle_pitch_signed_deg": 5,
    "paddle_roll_base_deg": 120,
    "paddle_roll_sign_source": 1,
    "paddle_roll_signed_deg": 0,
    "paddle_y_offset": 0.08,
    "paddle_yaw_base_deg": 0,
    "paddle_yaw_sign_source": 1,
    "paddle_yaw_signed_deg": 0,
    "right_elbow_path": [],
    "right_elbow_pole": [
      -0.5,
      -0.5,
      0
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
      0,
      0
    ],
    "shoulder_protraction_m": 0,
    "spine_curve_deg": 0,
    "stance_width": 0.48,
    "support_grip_rotation_deg": 0,
    "support_grip_slide_m": 0,
    "support_grip_style": 0,
    "support_index_closure": 1,
    "swing_path_blend": 1,
    "torso_pitch_deg": 0,
    "torso_roll_deg": 0,
    "torso_yaw_deg": 0,
    "weight_shift": 0.15,
    "windup_body": {
      "back_foot_back": -0.14,
      "body_pitch_deg": 0,
      "body_position_offset": [
        0,
        0,
        0
      ],
      "body_roll_deg": 0,
      "body_yaw_deg": 18,
      "crouch_amount": 0.216,
      "front_foot_forward": 0.18,
      "head_pitch_deg": -28,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": -35.28,
      "hip_yaw_deg": 12,
      "lead_foot": 1,
      "left_elbow_pole": [
        0,
        0,
        0
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 84.30000000000001,
      "left_hand_mode": 4,
      "left_hand_offset": [
        -0.07999999821186066,
        0.019999999552965164,
        -0.14000000059604645
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
      "main_grip_rotation_deg": -23.5,
      "paddle_in_hand_rotation_deg": 21.5,
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": -10.800000000000011,
      "paddle_roll_sign_source": 2,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": 35,
      "right_elbow_pole": [
        0.06393641233444214,
        0.0897594690322876,
        0.1332421600818634
      ],
      "right_foot_offset": [
        -0.014000000432133675,
        0,
        -0.3019999861717224
      ],
      "right_foot_yaw_deg": 0,
      "right_hand_offset": [
        0,
        -0.01209999993443489,
        0
      ],
      "right_knee_pole": [
        0,
        0,
        0
      ],
      "right_shoulder_rotation_deg": [
        -120,
        -120,
        -95.5999984741211
      ],
      "spine_curve_deg": 0,
      "stance_width": 0.5,
      "torso_pitch_deg": 3,
      "torso_roll_deg": 0,
      "torso_yaw_deg": 19,
      "weight_shift": -0.68
    },
    "zone_forward_offset": 0.46,
    "zone_x_max": 0.62,
    "zone_x_min": 0.22,
    "zone_y_max": 1.255,
    "zone_y_min": 0.855
  },
  "id": 0,
  "kind": "stroke",
  "name": "Forehand",
  "schema": "pickleball.pose",
  "scope": "whole_pose",
  "selected_stage": 2,
  "selected_stage_context": "Editor view only; fields contain the whole pose and all keyframes",
  "selected_stage_name": "Finish",
  "version": 1
}
"""
