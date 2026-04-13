# Plan: Fix Tab Sliders → Player Gizmo Wiring

## TL;DR

Fix 3 bugs in `posture_editor_ui.gd`:
1. `_update_gizmo_visibility()` incorrectly hides paddle gizmos (they have `body_part_name = "paddle_position"` which passes the `!= ""` check)
2. Slider changes don't update gizmo positions until the next `_process()` frame
3. `_refresh_live_preview()` may not be propagating all paddle/charge/follow-through fields to the live player

**Deliverables**: Slider adjustments immediately reflect on the 3D gizmo AND update the player body in real-time.
**Estimated Effort**: Short
**Parallel Execution**: NO — sequential code reading + fixes
**Critical Path**: Bug 1 → Bug 2 → Bug 3 investigation → Bug 3 fix

---

## Context

### The Bug Reports
- "the sliders in the tabs are not working please make them work on the player"

### What the Code Currently Does

**Tab → `_on_field_changed`** (paddle_tab.gd:165, charge_tab.gd:62, follow_through_tab.gd:98):
```gdscript
func _on_field_changed(field: String, value: Variant) -> void:
    if _def:
        match field:
            "paddle_forehand_mul": _def.paddle_forehand_mul = value
            ...
    field_changed.emit(field, value)  # → posture_editor_ui._on_field_changed
```

**`_on_field_changed` in posture_editor_ui.gd:780**:
```gdscript
func _on_field_changed(_field_name: String, _value: Variant) -> void:
    if _current_body_resource() == null: return
    _status_label.text = "Modified: %s" % _current_display_name()
    _set_dirty(true)
    _refresh_live_preview()   # ← only does pose_trigger or force_posture_update
    _update_mode_ui()
    # NOTE: _update_gizmo_positions() is NOT called here!
```

**`_refresh_live_preview()` in posture_editor_ui.gd:1435**:
```gdscript
func _refresh_live_preview() -> void:
    var preview_def = _build_preview_posture_for_editor()
    if preview_def == null or _player == null or not _player.posture:
        return
    if _pose_trigger and _pose_trigger.is_frozen():
        _pose_trigger.refresh_from_definition(preview_def)
    else:
        # Only applies if time_scale is "fake paused" (editor preview mode)
        if Engine.time_scale < 0.001:
            _player.posture.force_posture_update(preview_def)
```

**`force_posture_update()` in player_paddle_posture.gd:379**:
- Sets `paddle_posture = def.posture_id`
- Computes `_posture_lerp_pos` and `_posture_lerp_rot` from `def.resolve_paddle_offset()` + `resolve_paddle_rotation_deg()`
- Calls `_apply_full_body_posture(def)` which applies via `_skeleton_applier.apply(def)`

### Bug 1: `_update_gizmo_visibility()` hides ALL gizmos with `body_part_name != ""`

In `posture_editor_ui.gd:1513`:
```gdscript
if gh.body_part_name != "":
    gizmo.visible = false
    continue
```

Paddle gizmos have `body_part_name = "paddle_position"` (non-empty string), so they get hidden here. But paddle gizmos are NOT body-part hover gizmos — they should be visible when the Paddle tab is active.

**Fix**: Change the condition to check for actual body-part names specifically, or only skip gizmos whose `body_part_name` matches a known body-part list. Paddle gizmos with `body_part_name = "paddle_position"` should pass through to the normal visibility logic.

### Bug 2: Gizmo doesn't update until next `_process()` frame

When `_on_field_changed` fires after a slider move, `_refresh_live_preview()` is called but `_update_gizmo_positions()` is NOT. So the paddle gizmo only moves on the next engine frame in `_process()`.

**Fix**: Add `_update_gizmo_positions()` call in `_on_field_changed` after `_refresh_live_preview()`.

### Bug 3: `_refresh_live_preview()` only applies pose when `Engine.time_scale < 0.001`

During normal gameplay, `Engine.time_scale` is 1.0. So `_player.posture.force_posture_update(preview_def)` is NEVER called for live slider edits. Only when the pose is "frozen" via the preview system.

**Fix**: When a slider changes, we need to apply the edited definition to the live player. The `_def` object IS being updated (the match statement in tabs modifies it), so the question is whether `_refresh_live_preview()` can/should call `force_posture_update()` directly, or whether a new path is needed.

The key insight: `_build_preview_posture_for_editor()` returns a `preview_def` (via `_contextualize_posture_for_preview` which calls `base_def.to_preview_posture(def)`), not the edited `_current_def` itself. So even if we called `force_posture_update`, it would use the contextualized preview def, not the raw slider values.

We need to ensure that when sliders change, the LIVE player body reflects the new values. The path could be:
1. Call `force_posture_update(_current_def)` directly (for stroke postures) — this applies `_current_def` which IS the edited def
2. Or call `_player.posture.force_posture_update(_current_def)` directly in `_on_field_changed`

But `force_posture_update` expects a full posture def with `posture_id`. For base poses, `_current_base_def` is the def but it doesn't have a `posture_id`. So the path needs to be:
- Stroke posture mode: `_player.posture.force_posture_update(_current_def)`
- Base pose mode: different path (need to investigate)

### Additional Issue Found: `_build_preview_posture_for_editor()` returns a COMPOSED def, not the edited def

When sliders in paddle/charge/follow-through tabs change, they modify `_current_def` directly. But `_refresh_live_preview()` calls `_build_preview_posture_for_editor()` which returns a `preview_def` from `_contextualize_posture_for_preview()`. This applies the BASE-POSE overlay, not the raw edited values.

The fix: For Paddle/Charge/FollowThrough tab changes, we should call `force_posture_update(_current_def)` directly, bypassing the contextualize step.

---

## Work Objectives

### Bug 1 Fix — `_update_gizmo_visibility()` hiding paddle gizmos
**File**: `scripts/posture_editor_ui.gd`
**Change**: Line ~1513 — change `if gh.body_part_name != "":` to a whitelist of actual body-part names (chest, head, hips, right_hand, left_hand, right_foot, left_foot, right_elbow, left_elbow, right_knee, left_knee). Paddle gizmos have `body_part_name = "paddle_position"` which is NOT a real body part and should pass through to normal visibility logic.

### Bug 2 Fix — Gizmo position update latency
**File**: `scripts/posture_editor_ui.gd`
**Change**: In `_on_field_changed()`, after `_refresh_live_preview()`, add a call to `_update_gizmo_positions()` so the gizmo snaps to the new position immediately.

### Bug 3 Fix — Slider changes not applying to live player
**File**: `scripts/posture_editor_ui.gd`
**Change**: In `_on_field_changed()`, after `_refresh_live_preview()`, also call `_player.posture.force_posture_update(_current_def)` directly when in stroke posture mode (not base pose mode). This bypasses the `Engine.time_scale` guard and the preview-context machinery.

**Scope considerations**:
- This should only apply when `_is_base_pose_mode() == false` (stroke postures)
- For base pose mode, a different path may be needed (investigate `_apply_full_body_posture` for base poses)
- The `_refresh_live_preview()` existing guard `if Engine.time_scale < 0.001` is for the preview/pose-trigger path — we want to override it for live slider edits

---

## Verification Strategy

### QA Scenarios

**Scenario 1: Paddle tab slider → gizmo follows immediately**
  Tool: Godot headless + MCP
  Preconditions: Editor open, Paddle tab active, a stroke posture selected (e.g., FOREHAND)
  Steps:
    1. Read paddle gizmo world position (godot_run_script)
    2. Move Paddle "Forehand Mul" slider from 0.0 to 0.5
    3. Read paddle gizmo world position again
  Expected Result: Gizmo moves to new position reflecting +0.5 forehand offset (same frame as slider release)
  Evidence: .sisyphus/evidence/slider-gizmo-immediate.md

**Scenario 2: Paddle tab slider → player paddle follows**
  Tool: Godot headless + MCP
  Preconditions: Editor open, a stroke posture selected, live gameplay active (not frozen preview)
  Steps:
    1. Record paddle world position via `player.paddle_node.global_position`
    2. Change "Forward Mul" slider from 0.0 to 0.3
    3. Read paddle world position again
  Expected Result: Player paddle moves to reflect the new forward offset
  Evidence: .sisyphus/evidence/slider-player-paddle.md

**Scenario 3: Charge tab slider → gizmo and player update**
  Tool: Godot headless + MCP
  Preconditions: Editor open, Charge tab active, a stroke posture selected
  Steps:
    1. Read charge paddle position
    2. Move "Body rotation" slider
    3. Read charge paddle position
  Expected Result: Both gizmo and player reflect the change
  Evidence: .sisyphus/evidence/charge-slider.md

**Scenario 4: Base pose mode — leg slider → player stance updates**
  Tool: Godot headless + MCP
  Preconditions: Editor in Base Pose workspace mode, Legs tab active, base pose selected
  Steps:
    1. Read player foot world positions
    2. Move "Stance width" slider
    3. Read foot positions
  Expected Result: Foot positions change to reflect new stance width
  Evidence: .sisyphus/evidence/base-pose-leg-slider.md

---

## Execution Strategy

**Wave 1 (Sequential — must read before writing)**:
1. Read `scripts/posture_editor_ui.gd` around line 1513 to confirm exact current code
2. Read `scripts/posture_editor_ui.gd` around line 780 to confirm exact `_on_field_changed` code
3. Implement Bug 1 fix
4. Implement Bug 2 fix
5. Implement Bug 3 fix (tentative — may need additional investigation if `force_posture_update` signature doesn't accept base pose defs)
6. Validate with `godot_validate` on the modified file
7. Run Godot headless smoke test
8. User manual verification

---

## Success Criteria

- [ ] Paddle tab slider → paddle gizmo moves in same frame (no lag)
- [ ] Paddle tab slider → player paddle position updates in live gameplay
- [ ] Charge tab slider → charge phase pose updates on player
- [ ] Follow-through tab slider → follow-through pose updates on player
- [ ] Base pose Legs/Arms/Head/Torso sliders → player stance/arm/head/torso updates
- [ ] No new parse errors in modified file
- [ ] Editor opens without crash
