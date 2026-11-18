extends RefCounted
## Fixed, user-approved whole static Ready pose, not a general JSON import endpoint.
## Source: docs/pose-imports/ready-2026-10-02.json (same UTF-8 contents).
## selected_stage_name is historical editor context; ID20 uses its top-level pose.
const ID := "ready_2026_10_02"
const BASELINE_SHA256 := "58674192bf423dab162f8df4f27e81456fdbcc27b3e52830153d18dd23d56175"
const SOURCE_SHA256 := "4c4eff0caf366551a9ade8f8c1a5710ccae0866dcd2af037ac188a07db2cd5ae"
const JSON_TEXT := """{
  "baseline_sha256": "58674192bf423dab162f8df4f27e81456fdbcc27b3e52830153d18dd23d56175",
  "family": 2,
  "fields": {
    "back_foot_back": -0.07,
    "body_pitch_deg": 18,
    "body_roll_deg": 0,
    "body_yaw_deg": 0,
    "charge_back_foot_load": 0.25,
    "charge_body_rotation_deg": 0,
    "charge_duration": 0.32,
    "charge_hip_coil_deg": 0,
    "charge_paddle_offset": [
      0,
      0,
      0
    ],
    "charge_paddle_rotation_deg": [
      0,
      0,
      0
    ],
    "compact_finish_elbow_offset": [
      0,
      0,
      0
    ],
    "compact_finish_lateral_scale": 0.82,
    "compact_motion_scale": 1,
    "crouch_amount": 0.14,
    "follow_through_body": {
      "back_foot_back": -0.07,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": 0,
      "crouch_amount": 0.14,
      "front_foot_forward": 0.07,
      "head_pitch_deg": 0,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": 0,
      "hip_yaw_deg": 0,
      "lead_foot": 1,
      "left_elbow_pole": [
        -0.5096216797828674,
        -0.5666975975036621,
        -0.28676795959472656
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 5,
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
      "main_grip_rotation_deg": -30,
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 0,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": 0,
      "right_elbow_pole": [
        0.9268393516540527,
        0.5907312631607056,
        0.7309346199035645
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": 5,
      "right_hand_offset": [
        0,
        -0.05000000074505806,
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
      "shoulder_protraction_m": 0.05,
      "spine_curve_deg": 0,
      "stance_width": 0.59,
      "support_grip_rotation_deg": -120,
      "support_grip_slide_m": 0.00825,
      "support_index_closure": 0.400000005960464,
      "torso_pitch_deg": -6,
      "torso_roll_deg": 0,
      "torso_yaw_deg": 0,
      "weight_shift": 0
    },
    "front_foot_forward": 0.07,
    "ft_duration_hold": 0.06,
    "ft_duration_settle": 0.18,
    "ft_duration_strike": 0.1,
    "ft_duration_sweep": 0.2,
    "ft_ease_curve": 2,
    "ft_front_foot_load": 0.8,
    "ft_hip_uncoil_deg": 0,
    "ft_paddle_offset": [
      0,
      0,
      0
    ],
    "ft_paddle_rotation_deg": [
      0,
      0,
      0
    ],
    "has_zone": false,
    "head_pitch_deg": -21,
    "head_track_ball_weight": 0.8,
    "head_yaw_deg": 0,
    "hip_yaw_deg": 0,
    "lead_foot": 1,
    "left_elbow_path": [],
    "left_elbow_pole": [
      -0.5096216797828674,
      -0.5666975975036621,
      -0.28676795959472656
    ],
    "left_foot_offset": [
      0,
      0,
      0
    ],
    "left_foot_yaw_deg": 5,
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
    "main_grip_rotation_deg": -131,
    "paddle_floor_clearance": 0.06,
    "paddle_forehand_mul": -0.06000000000000005,
    "paddle_forward_mul": 0.5800000000000001,
    "paddle_hand": 0,
    "paddle_pitch_base_deg": -10,
    "paddle_pitch_sign_source": 1,
    "paddle_pitch_signed_deg": 0,
    "paddle_roll_base_deg": 11,
    "paddle_roll_sign_source": 1,
    "paddle_roll_signed_deg": 0,
    "paddle_y_offset": 0.22,
    "paddle_yaw_base_deg": 88,
    "paddle_yaw_sign_source": 1,
    "paddle_yaw_signed_deg": 0,
    "right_elbow_path": [],
    "right_elbow_pole": [
      0.9268393516540527,
      0.5907312631607056,
      0.7309346199035645
    ],
    "right_foot_offset": [
      0,
      0,
      0
    ],
    "right_foot_yaw_deg": 5,
    "right_hand_offset": [
      0,
      -0.02800000086426735,
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
    "shoulder_protraction_m": 0.05,
    "spine_curve_deg": 0,
    "stance_width": 0.59,
    "support_grip_rotation_deg": -115,
    "support_grip_slide_m": 0.00825,
    "support_grip_style": 0,
    "support_index_closure": 0.400000005960464,
    "swing_path_blend": 1,
    "torso_pitch_deg": -6,
    "torso_roll_deg": 0,
    "torso_yaw_deg": 0,
    "weight_shift": 0,
    "windup_body": {
      "back_foot_back": -0.07,
      "body_pitch_deg": 0,
      "body_roll_deg": 0,
      "body_yaw_deg": 0,
      "crouch_amount": 0.14,
      "front_foot_forward": 0.07,
      "head_pitch_deg": 0,
      "head_track_ball_weight": 0.8,
      "head_yaw_deg": 0,
      "hip_yaw_deg": 0,
      "lead_foot": 1,
      "left_elbow_pole": [
        -0.5096216797828674,
        -0.5666975975036621,
        -0.28676795959472656
      ],
      "left_foot_offset": [
        0,
        0,
        0
      ],
      "left_foot_yaw_deg": 5,
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
      "main_grip_rotation_deg": -30,
      "paddle_pitch_sign_source": 1,
      "paddle_pitch_signed_deg": 0,
      "paddle_roll_sign_source": 1,
      "paddle_roll_signed_deg": 0,
      "paddle_yaw_sign_source": 1,
      "paddle_yaw_signed_deg": 0,
      "right_elbow_pole": [
        0.9268393516540527,
        0.5907312631607056,
        0.7309346199035645
      ],
      "right_foot_offset": [
        0,
        0,
        0
      ],
      "right_foot_yaw_deg": 5,
      "right_hand_offset": [
        0,
        -0.05000000074505806,
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
      "shoulder_protraction_m": 0.05,
      "spine_curve_deg": 0,
      "stance_width": 0.59,
      "support_grip_rotation_deg": -120,
      "support_grip_slide_m": 0.00825,
      "support_index_closure": 0.400000005960464,
      "torso_pitch_deg": -6,
      "torso_roll_deg": 0,
      "torso_yaw_deg": 0,
      "weight_shift": 0
    },
    "zone_forward_offset": 0.5,
    "zone_x_max": 0,
    "zone_x_min": 0,
    "zone_y_max": 0,
    "zone_y_min": 0
  },
  "id": 20,
  "kind": "stroke",
  "name": "Ready",
  "schema": "pickleball.pose",
  "scope": "whole_pose",
  "selected_stage": 1,
  "selected_stage_context": "Editor view only; fields contain the whole pose and all keyframes",
  "selected_stage_name": "Contact",
  "version": 1
}
"""
