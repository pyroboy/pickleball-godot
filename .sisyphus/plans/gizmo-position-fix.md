# Gizmo Position Fix — Use Animated Node Positions

## TL;DR
> Fix gizmos to appear AT their respective body parts by reading actual animated world positions from arm/leg IK nodes, not computing mathematically.

---

## Context

### Problem
Body-part gizmos (hands, elbows, feet, knees) appear centralized or at wrong positions because computed positions don't match actual animated positions from the IK system.

### Root Cause
Gizmo positions are computed mathematically from posture definition values using `stance_offset()` formulas, but the actual animated positions depend on:
1. IK solving (which the definition values feed into)
2. Animation state
3. Physics interactions

**The fix**: Position gizmos at the **actual animated world positions** from the arm/leg IK nodes, not computed from raw definition values.

---

## Work Objectives

### Core Fix
Update `_create_arm_gizmos()` and `_create_leg_gizmos()` in `posture_editor_ui.gd` to read gizmo positions from **actual animated node world positions** instead of computing from definition values.

### What to Change

**`_create_arm_gizmos()`** — 4 gizmos:
- **Right hand**: `right_arm_node → UpperArmPivot/ForearmPivot/HandPivot.global_position`
- **Left hand**: `left_arm_node → UpperArmPivot/ForearmPivot/HandPivot.global_position`
- **Right elbow**: `right_arm_node → UpperArmPivot/ForearmPivot.global_position`
- **Left elbow**: `left_arm_node → UpperArmPivot/ForearmPivot.global_position`

**`_create_leg_gizmos()`** — 4 gizmos:
- **Right foot**: `right_leg_node → ThighPivot/ShinPivot/FootPivot.global_position`
- **Left foot**: `left_leg_node → ThighPivot/ShinPivot/FootPivot.global_position`
- **Right knee**: `right_leg_node → ThighPivot/ShinPivot.global_position`
- **Left knee**: `left_leg_node → ThighPivot/ShinPivot.global_position`

**`_update_gizmo_positions()`** — Update positions per-frame from same animated node paths.

**`_on_gizmo_moved()`** — This already works correctly — it reads the dragged gizmo's NEW position and writes back to the posture definition. No change needed here.

---

## Files to Modify

| File | Change |
|------|--------|
| `scripts/posture_editor_ui.gd` | `_create_arm_gizmos()`, `_create_leg_gizmos()`, `_update_gizmo_positions()` |

---

## Acceptance Criteria

1. Arm gizmos (hands, elbows) appear at the animated hand/elbow positions on the player's body
2. Leg gizmos (feet, knees) appear at the animated foot/knee positions on the player's body
3. When player moves/animates, gizmos follow the actual animated positions
4. Dragging a gizmo still correctly updates the posture definition
5. Glow-on-hover still works (already implemented)

---

## Verification

Run Godot, open posture editor, select Arms/Legs tab, hover body parts to see glow, click to reveal gizmo. Gizmo should appear AT the body part, not somewhere else.
