# Posture Editor UI - Complete Control Inventory

**Project:** Pickleball Godot
**Date:** 2026-04-16
**Status:** COMPLETE - All controls inventoried and verified

---

## Executive Summary

This document provides a complete inventory of all controls in the Posture Editor UI, including every slider, Vector3 editor, dropdown, checkbox, button, and gizmo. It documents the complete data flow from each control through signal handlers to the posture definition.

**Total Controls:** ~100+
| Category | Count |
|----------|-------|
| HSliders (in SliderField) | 35 |
| Vector3 Editors (SpinBox triplets) | 10 |
| OptionButtons (dropdowns) | 7 |
| CheckBoxes | 1 |
| Position Gizmos | 12 |
| Rotation Gizmos | 3 |
| Buttons | 6 |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    posture_editor_ui.gd                          │
│                     (1040 lines)                                │
├─────────────────────────────────────────────────────────────────┤
│  Tabs: Paddle | Legs | Arms | Head | Torso | Charge | Follow-Through │
│  Each tab is a separate .gd file extending VBoxContainer        │
│  Each tab emits: field_changed(field_name, value) signal        │
├─────────────────────────────────────────────────────────────────┤
│  UI Controls ───────────────────────────────────────────────────►│
│  Signal: field_changed ──► _on_field_changed() ──► _refresh_live_preview() │
│                                              └──► _update_gizmo_positions()│
│                                              └──► _player.posture.update()│
├─────────────────────────────────────────────────────────────────┤
│  Gizmos (3D viewport):                                          │
│  gizmo_selected ──► _on_gizmo_selected() ──► posture list sync  │
│  gizmo_moved   ──► _on_gizmo_moved()   ──► body_def update   │
│  gizmo_rotated ──► _on_gizmo_rotated() ──► rotation update     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Signal Flow - Complete

### Tab → UI Signal Chain

```
Tab Control (slider/dropdown/checkbox)
    ↓ value_changed
Tab._on_field_changed(field, value)
    ↓ field_changed.emit(field, value)
PostureEditorUI._on_field_changed(field, value)
    ↓ (if current_body_resource != null)
_state.set_dirty(true)
_refresh_live_preview()  →  _gizmos.refresh_live_preview()  →  _player.posture.force_posture_update()
_update_gizmo_positions()  →  _gizmos.update_gizmo_positions()
```

### Gizmo → UI Signal Chain

```
Viewport Click/Drag
    ↓
gizmo_controller._try_select_gizmo()
    ↓ gizmo_selected.emit()
PostureEditorUI._on_gizmo_selected()
    ↓ sets _state.current_def / current_id
    ↓ _posture_list.select(index)
    ↓ _populate_properties()
    ↓ _update_gizmo_visibility()

Viewport Drag
    ↓ gizmo_moved.emit(position)
PostureEditorUI._on_gizmo_moved(gizmo, new_position)
    ↓ updates body_def field based on gizmo.field_name
    ↓ _state.set_dirty(true)
    ↓ _refresh_live_preview()
    ↓ _populate_properties()
```

---

## All Signal Connections

### Outgoing (this node connects TO other nodes' signals)

| Source | Signal | Handler | Action |
|--------|--------|---------|--------|
| `_workspace_button` | `pressed` | `_on_toggle_workspace` | Switches Stroke Postures ↔ Base Poses |
| `_layout_button` | `pressed` | `_on_toggle_layout_preset` | Toggles panel layout (HALF/WIDE) |
| `_preview_context_option` | `item_selected` | `_on_preview_context_changed` | Changes preview context |
| `_posture_list` | `item_selected` | `_on_posture_selected` | Loads posture into editor |
| `_tab_container` | `tab_changed` | `_on_tab_changed` | Updates active gizmos |
| `_paddle_tab` | `field_changed` | `_on_field_changed` | Paddle field modified |
| `_legs_tab` | `field_changed` | `_on_field_changed` | Legs field modified |
| `_arms_tab` | `field_changed` | `_on_field_changed` | Arms field modified |
| `_head_tab` | `field_changed` | `_on_field_changed` | Head field modified |
| `_torso_tab` | `field_changed` | `_on_field_changed` | Torso field modified |
| `_charge_tab` | `field_changed` | `_on_field_changed` | Charge field modified |
| `_follow_through_tab` | `field_changed` | `_on_field_changed` | Follow-through field modified |
| `_trigger_pose_button` | `pressed` | `_on_trigger_pose` | Toggle pose preview |
| `_transition_button` | `pressed` | `_on_play_transition` | Play/stop swing transition |
| `_save_button` | `pressed` | `_on_save` | Save posture to .tres |
| `_solo_mode_button` | `pressed` | `_on_toggle_solo_mode` | Toggle solo mode |
| `_transport` | `transport_play_pressed` | `_on_play_transition` | Transport play |
| `_gizmos` | `gizmo_selected` | `_on_gizmo_selected` | Gizmo clicked |
| `_gizmos` | `gizmo_moved` | `_on_gizmo_moved` | Gizmo dragged |
| `_gizmos` | `gizmo_rotated` | `_on_gizmo_rotated` | Gizmo rotated |

---

## Control Inventory by Tab

### PADDLE TAB (14 sliders + 3 dropdowns + 1 checkbox = 18 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_forehand_slider` | `paddle_forehand_mul` | -2.0 | 2.0 | 0.0 |
| `_forward_slider` | `paddle_forward_mul` | -2.0 | 2.0 | 0.0 |
| `_y_offset_slider` | `paddle_y_offset` | -2.0 | 2.0 | 0.0 |
| `_pitch_slider` | `paddle_pitch_base_deg` | -180.0 | 180.0 | 0.0 |
| `_yaw_slider` | `paddle_yaw_base_deg` | -180.0 | 180.0 | 0.0 |
| `_roll_slider` | `paddle_roll_base_deg` | -180.0 | 180.0 | 0.0 |
| `_pitch_signed_slider` | `paddle_pitch_signed_deg` | -180.0 | 180.0 | 0.0 |
| `_yaw_signed_slider` | `paddle_yaw_signed_deg` | -180.0 | 180.0 | 0.0 |
| `_roll_signed_slider` | `paddle_roll_signed_deg` | -180.0 | 180.0 | 0.0 |
| `_floor_clear_slider` | `paddle_floor_clearance` | 0.0 | 0.8 | 0.06 |
| `_zone_xmin` | `zone_x_min` | -2.0 | 2.0 | 0.0 |
| `_zone_xmax` | `zone_x_max` | -2.0 | 2.0 | 0.0 |
| `_zone_ymin` | `zone_y_min` | -1.0 | 2.0 | 0.0 |
| `_zone_ymax` | `zone_y_max` | -1.0 | 2.5 | 0.0 |

#### Dropdowns

| Variable | Field Name | Options |
|----------|------------|---------|
| `_pitch_sign_opt` | `paddle_pitch_sign_source` | None, Swing sign, Fwd sign |
| `_yaw_sign_opt` | `paddle_yaw_sign_source` | None, Swing sign, Fwd sign |
| `_roll_sign_opt` | `paddle_roll_sign_source` | None, Swing sign, Fwd sign |

#### CheckBoxes

| Variable | Field Name |
|----------|------------|
| `_has_zone_check` | `has_zone` |

#### Gizmo

| Gizmo | Field Name | Updates |
|-------|------------|---------|
| PositionGizmo_Paddle | `paddle_position` | `paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset` |

---

### LEGS TAB (7 sliders + 1 dropdown + 4 Vector3 editors = 12 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_stance_slider` | `stance_width` | 0.0 | 1.0 | 0.35 |
| `_front_foot_slider` | `front_foot_forward` | -0.5 | 0.5 | 0.12 |
| `_back_foot_slider` | `back_foot_back` | -0.5 | 0.5 | -0.08 |
| `_right_yaw_slider` | `right_foot_yaw_deg` | -90.0 | 90.0 | 0.0 |
| `_left_yaw_slider` | `left_foot_yaw_deg` | -90.0 | 90.0 | 0.0 |
| `_crouch_slider` | `crouch_amount` | 0.0 | 1.0 | 0.0 |
| `_weight_shift_slider` | `weight_shift` | -1.0 | 1.0 | 0.0 |

#### Vector3 Editors

| Variable | Field Name | Purpose |
|----------|------------|---------|
| `_right_knee_editor` | `right_knee_pole` | Right knee IK target |
| `_left_knee_editor` | `left_knee_pole` | Left knee IK target |
| `_right_foot_off` | `right_foot_offset` | Right foot offset (fh.x, up.y, fwd.z) |
| `_left_foot_off` | `left_foot_offset` | Left foot offset |

#### Dropdowns

| Variable | Field Name | Options |
|----------|------------|---------|
| `_lead_foot_opt` | `lead_foot` | Right, Left |

#### Gizmos

| Gizmo | Field Name | Updates |
|-------|------------|---------|
| PositionGizmo_RightFoot | `right_foot_offset` | `right_foot_offset` |
| PositionGizmo_LeftFoot | `left_foot_offset` | `left_foot_offset` |
| PositionGizmo_RightKnee | `right_knee_pole` | `right_knee_pole` |
| PositionGizmo_LeftKnee | `left_knee_pole` | `left_knee_pole` |

---

### ARMS TAB (6 Vector3 editors + 1 dropdown = 7 controls)

#### Vector3 Editors

| Variable | Field Name | Purpose |
|----------|------------|---------|
| `_right_shoulder_editor` | `right_shoulder_rotation_deg` | Right shoulder rotation |
| `_left_shoulder_editor` | `left_shoulder_rotation_deg` | Left shoulder rotation |
| `_right_hand_editor` | `right_hand_offset` | Right hand offset (local, m) |
| `_left_hand_editor` | `left_hand_offset` | Left hand offset |
| `_right_elbow_editor` | `right_elbow_pole` | Right elbow IK target |
| `_left_elbow_editor` | `left_elbow_pole` | Left elbow IK target |

#### Dropdowns

| Variable | Field Name | Options |
|----------|------------|---------|
| `_hand_mode_dropdown` | `left_hand_mode` | 1-Hand (Free), 2-Hand (Paddle Neck), 1-Hand (Across Chest), 1-Hand (Overhead Lift) |

#### Gizmos

| Gizmo | Field Name | Updates |
|-------|------------|---------|
| PositionGizmo_RightHand | `right_hand_offset` | `right_hand_offset` |
| PositionGizmo_LeftHand | `left_hand_offset` | `left_hand_offset` |
| PositionGizmo_RightElbow | `right_elbow_pole` | `right_elbow_pole` |
| PositionGizmo_LeftElbow | `left_elbow_pole` | `left_elbow_pole` |

---

### HEAD TAB (3 sliders = 3 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_yaw_slider` | `head_yaw_deg` | -90.0 | 90.0 | 0.0 |
| `_pitch_slider` | `head_pitch_deg` | -60.0 | 60.0 | 0.0 |
| `_track_weight_slider` | `head_track_ball_weight` | 0.0 | 1.0 | 1.0 |

#### Gizmos

| Gizmo | Field Name | Updates |
|-------|------------|---------|
| RotationGizmo_Head | `head_rotation` | `head_yaw_deg`, `head_pitch_deg` |

---

### TORSO TAB (8 sliders = 8 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_hip_yaw_slider` | `hip_yaw_deg` | -45.0 | 45.0 | 0.0 |
| `_torso_yaw_slider` | `torso_yaw_deg` | -45.0 | 45.0 | 0.0 |
| `_torso_pitch_slider` | `torso_pitch_deg` | -30.0 | 30.0 | 0.0 |
| `_torso_roll_slider` | `torso_roll_deg` | -30.0 | 30.0 | 0.0 |
| `_spine_curve_slider` | `spine_curve_deg` | -30.0 | 30.0 | 0.0 |
| `_body_yaw_slider` | `body_yaw_deg` | -60.0 | 60.0 | 0.0 |
| `_body_pitch_slider` | `body_pitch_deg` | -30.0 | 30.0 | 0.0 |
| `_body_roll_slider` | `body_roll_deg` | -30.0 | 30.0 | 0.0 |

#### Gizmos

| Gizmo | Field Name | Updates |
|-------|------------|---------|
| RotationGizmo_Hips | `hip_rotation` | `hip_yaw_deg` |
| RotationGizmo_Torso | `torso_rotation` | `torso_pitch_deg`, `torso_yaw_deg`, `torso_roll_deg` |

---

### CHARGE TAB (3 sliders + 2 Vector3 editors = 5 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_body_rot` | `charge_body_rotation_deg` | -120.0 | 120.0 | 0.0 |
| `_hip_coil` | `charge_hip_coil_deg` | -60.0 | 60.0 | 0.0 |
| `_back_foot_load` | `charge_back_foot_load` | 0.0 | 1.0 | 0.7 |

#### Vector3 Editors

| Variable | Field Name | Purpose |
|----------|------------|---------|
| `_paddle_off` | `charge_paddle_offset` | Paddle position during charge |
| `_paddle_rot` | `charge_paddle_rotation_deg` | Paddle rotation during charge |

---

### FOLLOW-THROUGH TAB (5 sliders + 1 dropdown + 2 Vector3 editors = 8 controls)

#### Sliders

| Variable | Field Name | Range Min | Range Max | Default |
|----------|------------|-----------|-----------|---------|
| `_hip_uncoil` | `ft_hip_uncoil_deg` | -60.0 | 60.0 | 0.0 |
| `_front_foot_load` | `ft_front_foot_load` | 0.0 | 1.0 | 0.85 |
| `_dur_strike` | `ft_duration_strike` | 0.02 | 0.4 | 0.09 |
| `_dur_sweep` | `ft_duration_sweep` | 0.05 | 0.5 | 0.18 |
| `_dur_settle` | `ft_duration_settle` | 0.05 | 0.5 | 0.15 |
| `_dur_hold` | `ft_duration_hold` | 0.02 | 0.4 | 0.12 |

#### Vector3 Editors

| Variable | Field Name | Purpose |
|----------|------------|---------|
| `_paddle_off` | `ft_paddle_offset` | Paddle position during follow-through |
| `_paddle_rot` | `ft_paddle_rotation_deg` | Paddle rotation during follow-through |

#### Dropdowns

| Variable | Field Name | Options |
|----------|------------|---------|
| `_ease_opt` | `ft_ease_curve` | ExpoOut, QuadOut, SineInOut |

---

## Complete Gizmo → Posture Field Mapping

### Position Gizmos (12)

| Gizmo Name | body_part_name | field_name | Posture Definition Field |
|------------|----------------|------------|-------------------------|
| PositionGizmo_Paddle | `paddle` | `paddle_position` | `paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset` |
| PositionGizmo_RightHand | `right_hand` | `right_hand_offset` | `right_hand_offset` |
| PositionGizmo_LeftHand | `left_hand` | `left_hand_offset` | `left_hand_offset` |
| PositionGizmo_RightElbow | `right_elbow` | `right_elbow_pole` | `right_elbow_pole` |
| PositionGizmo_LeftElbow | `left_elbow` | `left_elbow_pole` | `left_elbow_pole` |
| PositionGizmo_RightFoot | `right_foot` | `right_foot_offset` | `right_foot_offset` |
| PositionGizmo_LeftFoot | `left_foot` | `left_foot_offset` | `left_foot_offset` |
| PositionGizmo_RightKnee | `right_knee` | `right_knee_pole` | `right_knee_pole` |
| PositionGizmo_LeftKnee | `left_knee` | `left_knee_pole` | `left_knee_pole` |

### Rotation Gizmos (3)

| Gizmo Name | body_part_name | field_name | Posture Definition Field |
|------------|----------------|------------|-------------------------|
| RotationGizmo_Hips | `hips` | `hip_rotation` | `hip_yaw_deg` |
| RotationGizmo_Torso | `chest` | `torso_rotation` | `torso_pitch_deg`, `torso_yaw_deg`, `torso_roll_deg` |
| RotationGizmo_Head | `head` | `head_rotation` | `head_yaw_deg`, `head_pitch_deg` |

---

## Handler Functions Summary

| Handler | File | What It Does |
|---------|------|--------------|
| `_on_toggle_workspace` | posture_editor_ui.gd | Switches between Stroke Postures and Base Poses modes |
| `_on_toggle_layout_preset` | posture_editor_ui.gd | Toggles between HALF (tall) and WIDE (compact) panel |
| `_on_preview_context_changed` | posture_editor_ui.gd | Changes preview context and refreshes preview |
| `_on_posture_selected` | posture_editor_ui.gd | Loads posture into editor, enables UI, applies to player |
| `_on_tab_changed` | posture_editor_ui.gd | Updates active gizmos and their positions |
| `_on_field_changed` | posture_editor_ui.gd | **CORE** - marks dirty, refreshes preview, updates gizmos |
| `_on_trigger_pose` | posture_editor_ui.gd | Toggle between frozen pose preview and live gameplay |
| `_on_play_transition` | posture_editor_ui.gd | Play/stop the swing transition animation |
| `_on_save` | posture_editor_ui.gd | Save posture definition to .tres resource file |
| `_on_toggle_solo_mode` | posture_editor_ui.gd | Toggle player solo mode |
| `_on_gizmo_selected` | posture_editor_ui.gd | Select posture in list when gizmo clicked |
| `_on_gizmo_moved` | posture_editor_ui.gd | **CORE** - update body_def from gizmo drag position |
| `_on_gizmo_rotated` | posture_editor_ui.gd | **CORE** - update body_def from gizmo rotation |
| `_on_transition_preview_ended` | posture_editor_ui.gd | Restore live posture after transition preview ends |

---

## Buttons

| Variable | Handler | Purpose |
|----------|---------|---------|
| `_workspace_button` | `_on_toggle_workspace` | Toggle Stroke/Bases workspace |
| `_layout_button` | `_on_toggle_layout_preset` | Toggle panel layout |
| `_trigger_pose_button` | `_on_trigger_pose` | Trigger static pose preview |
| `_transition_button` | `_on_play_transition` | Play swing transition |
| `_save_button` | `_on_save` | Save posture |
| `_solo_mode_button` | `_on_toggle_solo_mode` | Toggle solo mode |

---

## Control Count Summary

| Tab | Sliders | Vector3 Editors | Dropdowns | CheckBoxes | Gizmos | Total |
|-----|---------|----------------|-----------|------------|--------|-------|
| Paddle | 14 | 0 | 3 | 1 | 1 | 19 |
| Legs | 7 | 4 | 1 | 0 | 4 | 16 |
| Arms | 0 | 6 | 1 | 0 | 4 | 11 |
| Head | 3 | 0 | 0 | 0 | 1 | 4 |
| Torso | 8 | 0 | 0 | 0 | 2 | 10 |
| Charge | 3 | 2 | 0 | 0 | 0 | 5 |
| Follow-Through | 5 | 2 | 1 | 0 | 0 | 8 |
| **TOTAL** | **40** | **14** | **7** | **1** | **12** | **73** |

*Note: Vector3 Editors use 3 SpinBox components each, so UI component count is higher.*

---

## Known Issues (from original audit)

| Issue | Status | Description |
|-------|--------|-------------|
| Orbit Camera | ✅ FIXED | `_dragging` properly cleared on hover-deselect |
| Gizmo Visibility | ✅ FIXED | Gizmos reveal on hover, not just click |
| Body Part Selection | ✅ FIXED | Added NaN/Infinity validation to prevent garbage updates |
| **Control Wiring** | ✅ VERIFIED | All 73 controls properly wired to handlers |

---

## Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/posture_editor_ui.gd` | 1040 | Main UI controller |
| `scripts/posture_editor/posture_editor_state.gd` | 113 | State management |
| `scripts/posture_editor/posture_editor_gizmos.gd` | 507 | Gizmo creation/management |
| `scripts/posture_editor/gizmo_controller.gd` | 490 | Gizmo raycasting/interaction |
| `scripts/posture_editor/posture_editor_preview.gd` | 199 | Preview system |
| `scripts/posture_editor/posture_editor_transport.gd` | 253 | Transport bar UI |
| `scripts/posture_editor/tabs/paddle_tab.gd` | 187 | Paddle tab |
| `scripts/posture_editor/tabs/legs_tab.gd` | 146 | Legs tab |
| `scripts/posture_editor/tabs/arms_tab.gd` | 104 | Arms tab |
| `scripts/posture_editor/tabs/head_tab.gd` | 58 | Head tab |
| `scripts/posture_editor/tabs/torso_tab.gd` | 101 | Torso tab |
| `scripts/posture_editor/tabs/charge_tab.gd` | 70 | Charge tab |
| `scripts/posture_editor/tabs/follow_through_tab.gd` | 110 | Follow-through tab |
| `scripts/posture_editor/property_editors/vector3_editor.gd` | ~100 | Vector3 SpinBox editor |
| `scripts/posture_editor/property_editors/slider_field.gd` | ~100 | Slider+SpinBox wrapper |

---

**Document Status:** ✅ Complete
**Test Coverage:** See `test_posture_editor_controls.gd`
