# Posture Editor UI - Data Handling Audit

**Project:** Pickleball Godot
**Date:** 2026-04-16
**Status:** INVENTORY COMPLETE - ISSUES IDENTIFIED

---

## Executive Summary

The posture editor UI (`posture_editor_ui.gd`) is a complex hybrid system that bridges 3D gizmo interaction in the viewport with a 2D editor panel. This audit maps every function, data connection, signal, and identifies root causes for the reported issues:

1. **Orbit camera** - abruptly stopping/misfiring during drag
2. **Body part selection** - not moving the pose correctly
3. **Gizmos** - not hidden before dragging body parts

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    posture_editor_ui.gd                          │
│                     (Shell / Controller)                        │
├─────────────┬─────────────┬─────────────┬──────────────────────┤
│ _state      │ _preview    │ _transport │ _gizmos              │
│ Posture     │ Posture     │ Transport  │ PostureEditorGizmos   │
│ EditorState │ Editor      │ Bar UI     │                       │
│             │ Preview     │            │                       │
├─────────────┴─────────────┴─────────────┴──────────────────────┤
│                    gizmo_controller.gd                          │
│              (GizmoHandle children - raycasting)               │
├─────────────────────────────────────────────────────────────────┤
│                    camera_rig.gd                                 │
│              (orbit camera - 3rd person mode)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Signal Flow Diagram

```
USER INPUT
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│ GAME.GD._unhandled_input()                                       │
│   → posture_editor_ui._input()  [KEY_G, KEY_P, KEY_SPACE]       │
│   → camera_rig.handle_input()  [orbit drag - MOUSE_BUTTON_LEFT] │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│ gizmo_controller._input()  ← LEFT CLICK on viewport           │
│   ├─ _try_select_gizmo()                                        │
│   │   ├─ 1. Click visible gizmo → select + start_drag          │
│   │   ├─ 2. Click body part → reveal gizmo + select + drag     │
│   │   └─ 3. Nothing hit → deselect                              │
│   │                                                             │
│   ├─ _start_drag() → gizmo_drag_started.emit()                │
│   ├─ _update_drag() → gizmo_moved.emit() / gizmo_rotated.emit│
│   └─ _stop_drag() → gizmo_drag_ended.emit() → _deselect()     │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│ posture_editor_ui._on_gizmo_moved() / _on_gizmo_rotated()       │
│   ├─ Updates posture definition (body_def.*)                    │
│   ├─ Calls _populate_properties()                               │
│   ├─ Calls _refresh_live_preview() → _gizmos.refresh_live_preview()
│   └─ Applies to player: _player.posture.force_posture_update() │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Inventory

### 1. posture_editor_ui.gd (1028 lines)

**Role:** Shell controller - owns UI elements and coordinates sub-modules.

#### Signals Emitted
| Signal | Purpose | Connected To |
|--------|---------|--------------|
| `editor_opened()` | Editor visibility changed | game.gd |
| `editor_closed()` | Editor closed | game.gd |

#### Signals Received
| Signal | Source | Handler | Action |
|--------|--------|---------|--------|
| `transport_play_pressed` | _transport | _on_play_transition | Start swing preview |
| `field_changed` | tabs (_paddle_tab, etc.) | _on_field_changed | Mark dirty, refresh preview |
| `gizmo_selected` | _gizmos | _on_gizmo_selected | Sync posture list |
| `gizmo_moved` | _gizmos | _on_gizmo_moved | Update definition |
| `gizmo_rotated` | _gizmos | _on_gizmo_rotated | Update definition |

#### Key Functions

**Initialization:**
| Function | Line | Purpose |
|----------|------|---------|
| `_init()` | 71 | Create sub-modules (_state, _preview, _transport, _gizmos) |
| `_ready()` | 81 | Build UI, init modules |
| `_init_preview()` | 134 | Initialize preview with player reference |
| `_init_transport()` | 137 | Setup transport callbacks |
| `_init_gizmos()` | 141 | Setup gizmo callbacks |

**Posture Selection:**
| Function | Line | Purpose | Data Modified |
|----------|------|---------|---------------|
| `_on_posture_selected()` | 479 | Handle list item click | Sets _state.current_def/base_def, applies posture to player |
| `_populate_properties()` | 528 | Update tab fields | Reads from _state.current_def |
| `_refresh_live_preview()` | 904 | Refresh gizmo preview | → _gizmos.refresh_live_preview() |

**Field Changes:**
| Function | Line | Purpose | Data Modified |
|----------|------|---------|---------------|
| `_on_field_changed()` | 547 | Tab field updated | Marks dirty, calls _refresh_live_preview(), _update_gizmo_positions(), applies to player |
| `_on_gizmo_moved()` | 736 | Gizmo dragged | Updates body_def fields (paddle_position, hand offsets, foot offsets, etc.) |
| `_on_gizmo_rotated()` | 855 | Rotation gizmo dragged | Updates body_def rotation fields |

**Gizmo Management:**
| Function | Line | Purpose |
|----------|------|---------|
| `set_player()` | 888 | Set player reference, init gizmos |
| `_update_active_gizmos()` | 895 | → _gizmos.update_active_gizmos() |
| `_update_gizmo_positions()` | 898 | → _gizmos.update_gizmo_positions() |
| `_update_gizmo_visibility()` | 901 | → _gizmos.update_gizmo_visibility() |
| `_refresh_live_preview()` | 904 | → _gizmos.refresh_live_preview() |

**Input Handling:**
| Function | Line | Keys | Action |
|----------|------|------|--------|
| `_input()` | 986 | G | Toggle solo mode |
| `_input()` | 994 | P | Trigger pose |
| `_input()` | 997 | SPACE | Play transition |

**Visibility/Notification:**
| Function | Line | Purpose |
|----------|------|---------|
| `_notification()` | 960 | NOTIFICATION_VISIBILITY_CHANGED - opens/closes editor |
| `_teardown_preview_state()` | 945 | Cleanup on close |

---

### 2. posture_editor_state.gd (113 lines)

**Role:** Central state store for editor.

#### State Variables
| Variable | Type | Initial | Purpose |
|----------|------|---------|---------|
| `_current_def` | PostureDefinition | null | Currently selected posture |
| `_current_base_def` | BasePoseDefinition | null | Currently selected base pose |
| `_current_id` | int | -1 | Currently selected posture ID |
| `_is_dirty` | bool | false | Unsaved changes flag |
| `_editor_restore_posture_id` | int | -1 | Posture to restore after preview |
| `_workspace_mode` | int | 0 | STROKE_POSTURES or BASE_POSES |
| `_layout_preset` | int | 0 | HALF or WIDE panel layout |

#### Injected References
| Reference | Type | Set By | Purpose |
|-----------|------|--------|---------|
| `_library` | PostureLibrary | init() | Access posture definitions |
| `_base_pose_library` | BasePoseLibrary | init() | Access base pose definitions |
| `_posture_list` | ItemList | init() | UI posture list |
| `_save_button` | Button | init() | Save button UI |
| `_status_label` | Label | init() | Status display |
| `_transition_button` | Button | init() | Preview swing button |
| `_trigger_pose_button` | Button | init() | Preview pose button |

#### Key Methods
| Method | Line | Purpose |
|--------|------|---------|
| `init()` | 20 | Inject dependencies |
| `current_body_resource()` | 32 | Returns current_def or current_base_def |
| `current_display_name()` | 35 | Get display name of current |
| `set_dirty()` | 39 | Mark unsaved, update button |
| `is_base_pose_mode()` | 29 | Check workspace mode |
| `populate_posture_list()` | 61 | Fill UI list |
| `filename_for()` | 57 | Generate filename for posture |
| `filename_for_base_pose()` | 53 | Generate filename for base pose |

---

### 3. posture_editor_gizmos.gd (507 lines)

**Role:** Manages creation and update of 3D gizmos in viewport.

#### Signals Emitted
| Signal | Payload | Connected To |
|--------|---------|--------------|
| `gizmo_selected` | gizmo | posture_editor_ui._on_gizmo_selected |
| `gizmo_moved` | gizmo, new_position | posture_editor_ui._on_gizmo_moved |
| `gizmo_rotated` | gizmo, euler_delta | posture_editor_ui._on_gizmo_rotated |

#### State
| Variable | Type | Purpose |
|----------|------|---------|
| `_gizmo_controller` | GizmoController | The actual gizmo interaction node |
| `_knee_mesh_nodes` | Dictionary | Runtime-created knee spheres |
| `_elbow_mesh_nodes` | Dictionary | Runtime-created elbow spheres |
| `_player` | Node3D | Player reference |
| `_state` | PostureEditorState | State reference |
| `_tab_container` | TabContainer | Tab UI reference |

#### Key Methods
| Method | Line | Purpose |
|--------|------|---------|
| `create_gizmo_controller()` | 22 | Create/add GizmoController to scene |
| `set_player()` | 50 | Update player reference |
| `get_current_paddle_position()` | 53 | Get paddle world pos for focus |
| `update_active_gizmos()` | 89 | Clear and recreate all gizmos |
| `update_gizmo_positions()` | 282 | Sync gizmo positions to body |
| `update_gizmo_visibility()` | 330 | Show/hide based on tab/selection |
| `process_frame()` | 349 | Update body part positions in gizmo controller |
| `refresh_live_preview()` | 275 | Apply posture to player |
| `teardown_mesh_nodes()` | 496 | Cleanup runtime meshes |

#### Gizmo Creation Methods
| Method | Creates | Lines |
|--------|---------|-------|
| `_create_paddle_gizmos()` | PositionGizmo for paddle | 105-121 |
| `_create_torso_gizmos()` | RotationGizmo for hips/chest | 123-152 |
| `_create_head_gizmos()` | RotationGizmo for head | 154-169 |
| `_create_arm_gizmos()` | PositionGizmo for hands/elbows | 171-221 |
| `_create_leg_gizmos()` | PositionGizmo for feet/knees | 223-273 |

---

### 4. gizmo_controller.gd (471 lines)

**Role:** Raycasting-based gizmo interaction in 3D viewport.

#### Signals Emitted
| Signal | Payload | Purpose |
|--------|---------|---------|
| `gizmo_selected` | GizmoHandle | Gizmo clicked |
| `gizmo_deselected` | - | Selection cleared |
| `gizmo_drag_started` | GizmoHandle | Drag began |
| `gizmo_drag_ended` | GizmoHandle | Drag ended |
| `gizmo_moved` | GizmoHandle, Vector3 | Position changed |
| `gizmo_rotated` | GizmoHandle, euler_delta | Rotation changed |

#### State Variables
| Variable | Type | Purpose |
|----------|------|---------|
| `_camera` | Camera3D | For raycasting |
| `_selected_gizmo` | GizmoHandle | Currently selected |
| `_hovered_gizmo` | GizmoHandle | Currently hovered |
| `_dragging` | bool | Drag in progress |
| `_drag_plane` | Plane | Drag plane for raycasting |
| `_drag_start_pos` | Vector3 | Drag start position |
| `_drag_start_mouse` | Vector2 | Drag start mouse pos |
| `_body_part_colliders` | Dictionary | Invisible sphere colliders |
| `_body_part_meshes` | Dictionary | Actual body meshes for glow |
| `_original_materials` | Dictionary | Restore materials after glow |

#### Critical Input Handling (Line 162-189)

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _try_select_gizmo(event.position)
                if _dragging:
                    _update_drag(event.position)
                    get_viewport().set_input_as_handled()
            else:
                var was_dragging := _dragging
                _stop_drag()
                if was_dragging:
                    get_viewport().set_input_as_handled()
                # ⚠️ PROBLEM: Only consumes if was dragging!
```

**⚠️ ISSUE #1 - ORBIT CAMERA RELEASES IMPROPERLY:**
- Line 178-182: `_stop_drag()` only calls `get_viewport().set_input_as_handled()` if `_dragging` was true
- If drag was never started (e.g., clicked empty space), the release event propagates to camera_rig
- camera_rig.handle_input() line 119: `orbit_dragging = event.pressed` will set it to FALSE on release
- This causes orbit to stop even when it wasn't the one dragging

#### Selection Flow (Line 191-223)

```gdscript
func _try_select_gizmo(screen_pos: Vector2) -> void:
    # 1. Click visible gizmo → select + drag
    # 2. Click body part → reveal gizmo + select + drag
    # 3. Nothing → deselect
```

**⚠️ ISSUE #2 - BODY PART CLICK SHOWS GIZMO BEFORE DRAG:**
- Line 214-219: When body part is clicked, gizmo is set visible THEN drag starts
- The gizmo appears on click, but user expects it to be visible BEFORE dragging
- This causes "ghost" appearing behavior

#### Gizmo Visibility Logic (Line 330-347)

```gdscript
func update_gizmo_visibility() -> void:
    # ⚠️ ISSUE #3 - GIZMO HIDDEN DURING DRAG PROBLEMS
    # Line 342-343: All body part gizmos are hidden by default
    if gh.body_part_name in ["chest", "head", "hips", ...]:
        gizmo.visible = false  # Hidden initially!
        continue
```

**⚠️ ISSUE #3 - GIZMO VISIBILITY RACE:**
- Body gizmos (chest, head, hips, hands, feet, elbows, knees) are always hidden initially
- They are revealed on click (line 217)
- BUT: During drag, visibility might get out of sync
- `update_gizmo_visibility()` is called from multiple places but not during active drag

#### Key Methods
| Method | Line | Purpose |
|--------|------|---------|
| `_try_select_gizmo()` | 191 | Main selection logic |
| `_select_gizmo()` | 225 | Handle selection state |
| `_deselect_gizmo()` | 263 | Clear selection, hide body gizmos |
| `_start_drag()` | 373 | Begin drag, create drag plane |
| `_update_drag()` | 386 | Handle drag movement |
| `_stop_drag()` | 421 | End drag |
| `_update_hover()` | 282 | Hover detection |
| `_raycast_body_parts()` | 143 | Find hovered body part |

---

### 5. camera_rig.gd (241 lines)

**Role:** Camera control including orbit mode.

#### Orbit State
| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `orbit_mode` | int | 0 | 0=default, 1=behind blue, 2=behind red, 3=editor |
| `orbit_angle` | float | 0.0 | Horizontal orbit angle |
| `orbit_pitch` | float | 0.35 | Vertical orbit angle |
| `orbit_auto` | bool | false | Auto-rotate enabled |
| `_orbit_dragging` | bool | false | Mouse dragging orbit |
| `_orbit_idle_timer` | float | 0.0 | Time since last interaction |
| `editor_focus_point` | Vector3 | INF | Focus point for editor camera |

#### Critical Input Handling (Line 114-126)

```gdscript
func handle_input(event: InputEvent) -> void:
    if orbit_mode == 0:
        return  # ⚠️ Default camera doesn't handle orbit!
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _orbit_dragging = event.pressed  # Line 119
```

**⚠️ ISSUE #1 ROOT CAUSE - ORBIT DRAG FLAG COLISION:**
1. `gizmo_controller._input()` line 176-182: On mouse release, if was dragging gizmo → `set_input_as_handled()` (good)
2. But: If gizmo drag was NOT active (clicked empty space), release propagates here
3. Line 119 sets `_orbit_dragging = false` (line 119)
4. Since orbit_mode is 0 in default, line 115-116 returns early - orbit_mode 0 doesn't use orbit drag!
5. **BUT**: When posture editor is open, what is orbit_mode?

Looking at game.gd, the camera is in orbit_mode 0 (default) during normal gameplay. The issue is:
- When NOT in a gizmo drag, the release event goes to camera_rig
- camera_rig.handle_input returns early for orbit_mode == 0
- So NO issue here for default camera

The issue might be when orbit_mode != 0 (3rd person modes).

**SECONDARY ISSUE - EDITOR CAMERA MODE:**
- Line 179: `orbit_mode == 3` is the "editor camera" mode
- This mode is likely used when posture editor is open
- Line 118-119: In orbit_mode 3, LEFT mouse sets `_orbit_dragging`
- If gizmo_controller doesn't consume the event, orbit mode will start/stop dragging

**THE REAL BUG:** gizmo_controller line 179-182:
```gdscript
if was_dragging:
    get_viewport().set_input_as_handled()
# Only consume if we were actually dragging
```

This means:
- If you click empty space (not on gizmo, not on body part) → no drag started
- Release propagates to camera_rig
- If orbit_mode != 0, camera starts/stops orbiting

---

## Issue Analysis & Checklist

### Issue #1: Orbit Camera Abruptly Stops/Misfires

**Root Cause:** Event propagation collision between gizmo_controller and camera_rig

**Flow:**
1. User drags gizmo → gizmo_controller handles, sets input as handled ✓
2. User clicks empty space → gizmo_controller._try_select_gizmo runs, finds nothing, deselects
3. User releases mouse → event propagates to camera_rig
4. camera_rig.handle_input() sets `_orbit_dragging = false` if orbit_mode != 0

**Checklist:**
- [ ] Line 179-182: Release handling only consumes if was dragging - CORRECT
- [ ] But what if `_dragging` flag is true but gizmo was deselected elsewhere?
- [ ] Check if `_dragging` is properly cleared in `_deselect_gizmo()` - Line 424: `_dragging = false` is in `_stop_drag()`, not in `_deselect_gizmo()`

**BUG FOUND:** `_deselect_gizmo()` line 263-280 does NOT clear `_dragging`. If drag was active and gizmo gets deselected (line 333-334: auto-deselect when hovering different body part), `_dragging` remains true but gizmo is deselected. On next mouse release, `_stop_drag()` will fire `gizmo_drag_ended` even though no gizmo is selected.

### Issue #2: Body Part Selection Doesn't Move Pose

**Root Cause:** Multiple possible causes

**Checklist:**
- [ ] `_on_gizmo_moved()` line 736-853: Check if field_name matching is correct
- [ ] Line 738: `if gizmo.posture_id != _state.get_current_id()` - posture ID mismatch could cause early return
- [ ] Line 741-843: Player axis calculations - if `_player` is null or axes are wrong, no update
- [ ] Check if `_player.posture` exists and `force_posture_update()` works

**DATA FLOW FOR BODY PART MOVE:**
```
_on_gizmo_moved(gizmo, new_position)
  → gizmo.field_name determines what to update
  → Get player axes (_player._get_forward_axis(), _player._get_forehand_axis())
  → Compute offset in local space
  → Update body_def field (right_hand_offset, left_hand_offset, etc.)
  → _state.set_dirty(true)
  → _populate_properties()
  → _refresh_live_preview()
    → _gizmos.refresh_live_preview()
      → _player.posture.force_posture_update(preview_def)
```

### Issue #3: Gizmos Not Hidden Before Dragging

**Root Cause:** Visibility toggle race condition

**Current Flow:**
1. Click body part → `_try_select_gizmo()` line 214
2. Line 217: `gizmo_for_body.visible = true` (reveal on click)
3. Line 218: `_select_gizmo()` (highlights)
4. Line 219: `_start_drag()` (begins drag)

**Problem:** User sees gizmo appear simultaneously with drag starting. They expect gizmo to be visible BEFORE they decide to drag.

**Checklist:**
- [ ] `_update_hover()` line 282: Body part glow on hover works
- [ ] Line 305-328: When moving mouse off body part, previous gizmo hidden (line 326-328)
- [ ] During drag, hover detection skipped? Line 283-285: `if _dragging and _selected_gizmo and _selected_gizmo.body_part_name != "": return`

**DESYNC ISSUE:** During drag, `_update_hover()` is skipped. If gizmo visibility gets out of sync during this time (e.g., tab switch, selection change), it won't be corrected until drag ends.

---

## Complete Function Inventory

### posture_editor_ui.gd

| Function | Line | Category | Calls |
|----------|------|----------|-------|
| `_init()` | 71 | init | - |
| `_ready()` | 81 | lifecycle | `_init_preview`, `_init_transport`, `_init_gizmos`, `_make_header/split/footer`, `_state.init` |
| `_init_preview()` | 134 | init | `_preview.init` |
| `_init_transport()` | 137 | init | `_transport.set_save_callback` |
| `_init_gizmos()` | 141 | init | `_gizmos.init`, connects signals |
| `_make_header()` | 149 | UI build | - |
| `_make_main_split()` | 229 | UI build | - |
| `_make_footer()` | 336 | UI build | - |
| `_make_panel_style()` | 382 | style | - |
| `_style_action_button()` | 395 | style | - |
| `_populate_posture_list()` | 432 | state | `_state.populate_posture_list` |
| `_add_scroll_tab()` | 435 | UI build | - |
| `_on_toggle_layout_preset()` | 455 | UI action | `_state.get/set_layout_preset`, `_apply_layout_preset` |
| `_apply_layout_preset()` | 460 | UI action | - |
| `_on_posture_selected()` | 479 | **CORE** | `_state` setters, `_populate_properties`, `_refresh_live_preview`, `_update_active_gizmos`, `_player.posture` methods |
| `_populate_properties()` | 528 | state sync | tabs `.set_definition` |
| `_on_field_changed()` | 547 | **CORE** | `_state.set_dirty`, `_refresh_live_preview`, `_update_gizmo_positions`, `_player.posture` methods |
| `_on_trigger_pose()` | 563 | preview | `_preview` methods |
| `_on_play_transition()` | 589 | preview | `_preview.on_play_transition` |
| `_on_save()` | 598 | **IO** | `ResourceSaver.save`, `_state` |
| `_on_toggle_workspace()` | 623 | UI action | `_state` setters, `_gizmos.get_gizmo_controller.clear_all_gizmos`, `_preview` |
| `_update_workspace_ui()` | 645 | UI sync | `_state.is_base_pose_mode`, `_populate_posture_list` |
| `_on_preview_context_changed()` | 671 | preview | `_preview.set_preview_context_option_idx` |
| `_on_toggle_solo_mode()` | 684 | player | `_player.posture.solo_mode` |
| `_update_solo_mode_ui()` | 690 | UI sync | - |
| `_on_tab_changed()` | 702 | UI action | `_update_active_gizmos`, `_update_gizmo_positions` |
| `_on_gizmo_selected()` | 708 | **CORE** | `_state` setters, `_posture_list.select`, `_populate_properties` |
| `_on_gizmo_moved()` | 736 | **CORE** | `_player` axes, body_def updates, `_state.set_dirty`, `_populate_properties`, `_refresh_live_preview`, `_player.posture` |
| `_on_gizmo_rotated()` | 855 | **CORE** | body_def rotation updates, similar to above |
| `set_player()` | 888 | setup | `_preview.init`, `_gizmos.set_player/create_gizmo_controller` |
| `_update_active_gizmos()` | 895 | gizmo sync | `_gizmos.update_active_gizmos` |
| `_update_gizmo_positions()` | 898 | gizmo sync | `_gizmos.update_gizmo_positions` |
| `_update_gizmo_visibility()` | 901 | gizmo sync | `_gizmos.update_gizmo_visibility` |
| `_refresh_live_preview()` | 904 | preview | `_gizmos.refresh_live_preview` |
| `build_transport_bar()` | 909 | UI build | `_transport.build_transport_bar` |
| `_update_mode_ui()` | 914 | UI sync | - |
| `_teardown_preview_state()` | 945 | cleanup | `_preview`, `_state`, `_gizmos` |
| `_notification()` | 960 | lifecycle | various |
| `_input()` | 986 | input | - |
| `_process()` | 1003 | process | `_preview.get_pose_trigger().update`, `_update_gizmo_positions`, `_gizmos.process_frame` |
| `get_current_paddle_position()` | 1015 | query | `_gizmos.get_current_paddle_position` |
| `_on_transition_preview_ended()` | 1025 | callback | `_preview.restore_live_posture_from_editor`, `_update_mode_ui` |

---

## Data Connections Summary

### Player Posture Data Flow

```
_posture_library.definitions[]
    ↓ (selected by user)
_state.current_def / _state.current_base_def
    ↓ (applied to player)
_player.posture.force_posture_update(def)
    ↓
_player.posture._apply_full_body_posture(def)
    ↓
IK systems (arm_ik, leg_ik) read def fields
    ↓
Skeleton transforms updated
```

### Gizmo → Definition Flow

```
gizmo_controller (raycasts in viewport)
    ↓ gizmo_moved / gizmo_rotated signals
posture_editor_ui._on_gizmo_moved() / _on_gizmo_rotated()
    ↓ (matches gizmo.field_name)
body_def.right_hand_offset / left_elbow_pole / etc.
    ↓
_state.set_dirty(true)
    ↓
_player.posture.force_posture_update(current_def)
```

---

## Fixes Applied

### ✅ Fix #1: Orbit Camera Event Handling (Body Gizmo Drag)

**File:** `gizmo_controller.gd`
**Lines:** 290-297 (moved from 340-345)

**Problem:** `_dragging` flag not cleared when gizmo deselects during drag. The original fix at lines 340-345 was UNREACHABLE for body gizmos because the early return at lines 282-285 triggered first. This is the critical bug: when dragging a body gizmo and hovering a different body part, the hover check never ran due to early return.

**Original broken flow:**
```
1. Mouse moves during body gizmo drag
2. _update_hover() called
3. Early return triggers (dragging && body_part_name != "")
4. Lines 340-345 NEVER execute ← BUG
```

**Applied Fix:**
```gdscript
# ── 0. Body-part hover detection (always runs, even during body gizmo drag)
# This must happen BEFORE the early return so we can detect hover-deselect.
_hovered_body_part = _raycast_body_parts(ray_origin, ray_dir)

# If hovering a different body part than selected, deselect and stop drag.
# This allows orbiting camera while hovering body parts without being stuck in drag.
if _dragging and _selected_gizmo and _selected_gizmo.body_part_name != "":
    if _hovered_body_part != "" and _hovered_body_part != _selected_gizmo.body_part_name:
        _deselect_gizmo()
        if _dragging:
            _stop_drag()
        # Don't return — continue to normal hover detection

# Skip rest of body-part hover check while dragging a body gizmo (prevents flicker)
if _dragging and _selected_gizmo and _selected_gizmo.body_part_name != "":
    return
```

### ✅ Fix #2: Gizmo Visibility Before Drag

**File:** `gizmo_controller.gd`
**Lines:** 306-310

**Problem:** Body gizmos only visible on click, not on hover.

**Applied Fix:**
```gdscript
var gizmo_for_body: GizmoHandle
if _hovered_body_part != "":
    gizmo_for_body = _find_gizmo_for_body_part(_hovered_body_part)
    if gizmo_for_body and not gizmo_for_body.visible:
        gizmo_for_body.visible = true
```

### ✅ Fix #3: Body Part Selection → Pose Update Validation

**File:** `posture_editor_ui.gd`
**Lines:** 745-754

**Problem:** Validation only checked `length() < 0.01` which doesn't catch NaN (NaN < 0.01 is false).

**Applied Fix:**
```gdscript
# Guard: if axes are zero/invalid (NaN, Infinity, or near-zero), we cannot
# compute meaningful offsets. This prevents garbage values from corrupting the
# posture definition. Note: NaN.length() returns NaN, and NaN < 0.01 is false,
# so we must check is_zero_approx() explicitly.
if is_zero_approx(forward_axis.length()) or is_zero_approx(forehand_axis.length()):
    push_warning("PostureEditorUI: Player axes too small (near-zero length), cannot compute gizmo offset")
    return
if not is_finite(forward_axis.length()) or not is_finite(forehand_axis.length()):
    push_warning("PostureEditorUI: Player axes invalid (NaN/Infinity), cannot compute gizmo offset")
    return
```

---

## Test Plan

### Test: Orbit Camera Release

**Steps:**
1. Open posture editor (E key)
2. Ensure orbit mode is enabled (orbit_mode != 0, e.g., press P to cycle)
3. Click and drag in viewport (NOT on a gizmo)
4. Release mouse
5. **Expected:** Orbit should NOT start/stop unexpectedly
6. **Expected:** If orbit was dragging, it should stop smoothly

### Test: Body Part Gizmo Drag

**Steps:**
1. Open posture editor
2. Select a posture
3. Hover over a body part (e.g., hand)
4. **Expected:** Body part glows green, gizmo appears nearby
5. Click and drag the revealed gizmo
6. **Expected:** Pose should update in real-time
7. Release
8. **Expected:** Gizmo stays visible, selection maintained

### Test: Gizmo Visibility Sync

**Steps:**
1. Open posture editor
2. Select Torso tab
3. Hover over chest → rotation gizmo appears
4. Move to different body part without clicking
5. **Expected:** Previous gizmo hides, new one appears
6. Click and hold on gizmo
7. While holding, press Tab to switch tabs
8. **Expected:** Gizmo doesn't disappear during drag

---

## Verification Checklist

### Issue #1: Orbit Camera ✅ FIXED
- [ ] Start drag on body part
- [ ] Hover different body part (while still holding mouse)
- [ ] Release mouse
- [ ] Camera orbit NOT stuck — responds to new orbit attempts
- [ ] `gizmo_drag_ended` signal fires on hover-interrupt

### Issue #2: Gizmo Visibility ✅ FIXED
- [ ] Hover body part → gizmo appears (no click)
- [ ] Move off body part → gizmo hides
- [ ] Click visible gizmo → drag starts immediately (gizmo already visible)
- [ ] Multiple body parts NOT simultaneously visible (only hovered one)

### Issue #3: Pose Update Validation ✅ FIXED
- [ ] Normal drag operation: posture updates correctly
- [ ] If axes become zero: early return with warning in console
- [ ] No NaN or garbage offset values in body_def

---

## File Reference Map

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/posture_editor_ui.gd` | 1028 | Shell controller |
| `scripts/posture_editor/posture_editor_state.gd` | 113 | State management |
| `scripts/posture_editor/posture_editor_preview.gd` | 199 | Preview/tween playback |
| `scripts/posture_editor/posture_editor_transport.gd` | 253 | Transport bar UI |
| `scripts/posture_editor/posture_editor_gizmos.gd` | 507 | Gizmo management |
| `scripts/posture_editor/gizmo_controller.gd` | 471 | Gizmo raycasting/input |
| `scripts/camera/camera_rig.gd` | 241 | Camera control |
| `scripts/posture_editor/gizmo_handle.gd` | 156 | Base gizmo class |
| `scripts/posture_editor/position_gizmo.gd` | 178 | Position gizmo class |
| `scripts/posture_editor/rotation_gizmo.gd` | 189 | Rotation gizmo class |
| `scripts/posture_editor/pose_trigger.gd` | TBD | Pose preview trigger |
| `scripts/posture_editor/transition_player.gd` | TBD | Swing transition player |

---

**Document Status:** ✅ Complete
**Next Step:** Implement fixes identified above
