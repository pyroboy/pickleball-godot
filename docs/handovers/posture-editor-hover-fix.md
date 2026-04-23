# Handoff Prompt: Fix Body Part Hover Detection in Posture Editor

## Problem Statement

The body part hover detection in the posture editor (E key to open) is inaccurate. When the user hovers the mouse over body parts (hands, feet, torso, head, etc.), the wrong part highlights or no highlight appears.

**Symptoms observed:**
- Body part hover is "way off" — doesn't match where the mouse actually points
- Body part naming may be incorrect — tab labels don't match the body part being hovered
- Data handling in posture animation and panel controls needs improvement

## Files to Examine (PRIMARY)

### 1. `scripts/posture_editor/gizmo_controller.gd`
**Critical file — contains hover detection logic**

Key areas to investigate:
- Line 51: `_BODY_COLLIDER_RADIUS := 0.18` — fixed radius for ALL body parts
- Lines 154-172: `_raycast_body_parts()` — sphere-ray intersection math
- Lines 108-131: `set_body_part_positions()` and `_set_body_part_collider()`
- Lines 294-390: `_update_hover()` — hover state machine

**Specific questions:**
1. Is `0.18` radius appropriate for all body parts? (hands ~0.08, torso ~0.25)
2. Is the ray-sphere intersection math correct for all cases?
3. Are colliders properly synced with mesh positions?

### 2. `scripts/posture_editor/posture_editor_gizmos.gd`
**Critical file — position computation and mesh registration**

Key areas to investigate:
- Lines 350-539: `process_frame()` — builds `positions` dict and `meshes` dict
- Lines 361-371: Mesh registration for torso/head (potential null checks)
- Lines 384-416: Knee mesh creation and caching
- Lines 419-450: Elbow mesh creation and caching
- Lines 454-539: Position computation branch (animating vs static)

**Specific questions:**
1. `positions` dict comes from pivot nodes OR computed formulas. Could this cause misalignment with `meshes` dict?
2. Are there null-check gaps that cause mesh registration to fail silently?
3. Does `is_animating` vs `is_frozen` branching cause position jumps?

### 3. `scripts/posture_editor_ui.gd`
**Important — UI callbacks and data flow**

Key areas to investigate:
- Lines 783-912: `_on_gizmo_moved()` — offset calculation and body_def updates
- Lines 1060-1079: `_process()` — calls `_gizmos.process_frame()`
- Lines 946-961: Gizmo management functions

**Specific questions:**
1. Offset calculation assumes player_pos is constant — valid during drag?
2. Are all field_name cases handled correctly?

## Files to Examine (SECONDARY)

### 4. `scripts/posture_editor/gizmo_handle.gd`
- Line 24: `body_part_name: String = ""` — the naming property
- Line 29: body-mesh hover detection logic

### 5. `scripts/posture_definition.gd`
- Lines 143-158: `resolve_paddle_offset()` and `resolve_paddle_rotation_deg()`
- Line 242: `_sign_for()` — swing/fwd sign resolution

### 6. `scripts/posture_editor/posture_editor_state.gd`
- Lines 32-33: `current_body_resource()` — returns `_current_def` or `_current_base_def`

## Body Part Naming Map

**Gizmo body_part_name assignments** (in `posture_editor_gizmos.gd`):
```
Torso:     "hips", "chest"
Head:      "head"
Arms:      "right_hand", "left_hand", "right_elbow", "left_elbow"
Legs:      "right_foot", "left_foot", "right_knee", "left_knee"
Paddle:    "" (empty string — no body part)
```

**Meshes registered** (in `process_frame()`):
```
From body_pivot:     "chest", "hips", "head"
From arm nodes:       "right_hand", "left_hand"
From leg nodes:       "right_foot", "left_foot"
Dynamically created:  "right_knee", "left_knee", "right_elbow", "left_elbow"
```

## Architecture Overview

```
User presses E
    ↓
input_handler.gd:_handle_debug_toggles() → KEY_E
    ↓
game.gd:_toggle_posture_editor()
    ↓
posture_editor_ui.visible = true
    ↓
editor_opened.emit() → _update_active_gizmos()
    ↓
PostureEditorGizmos.create_gizmo_controller()
    ↓
GizmoController handles all hover/drag via _input()
    ↓
_update_hover() every frame:
    ├── _raycast_body_parts() → tests ray against StaticBody3D colliders
    ├── If hit: glow mesh + show tab label + reveal gizmo
    └── _on_gizmo_moved() when dragging → updates body_def
```

## Research Required

1. **Godot 4.x raycasting best practices** for custom collision shapes
2. **Sphere collider sizing** for proximity detection (not physics)
3. **Godot StaticBody3D** vs Area3D for hover detection tradeoffs
4. **Adaptive collision sizes** based on body part type
5. Any known Godot issues with ray-sphere intersection in _input()

## Constraints

- **DO NOT break** existing gizmo drag functionality
- **DO NOT break** tab-based visibility filtering
- **Maintain** the glow material effect on hover
- **Maintain** camera orbit when NOT hovering gizmo/body parts
- **Preserve** the distinction between paddle gizmos (no body_part_name) and body part gizmos

## Verification Criteria

After fix, test each body part:
1. Hover over "right_hand" → should show "[right_hand]" label + glow
2. Hover over "left_elbow" → should show "[left_elbow]" label + glow
3. No flickering when moving between adjacent parts (e.g., knee → foot)
4. Correct behavior during animation playback vs static editing
5. Panel controls still update correctly when dragging gizmos

## User's Original Intent

- Fix body part hover being "way off"
- Fix body part naming being wrong
- Improve data handling in posture animation and panel controls
