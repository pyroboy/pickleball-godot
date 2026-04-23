# Posture Editor V2 — Gradual Porting Plan

## Archive
All v1 code is snapshotted in `scripts/archive/posture_editor_v1/`.
- `posture_editor_ui.gd` (1112 lines)
- `posture_editor/*.gd` (10 submodule files)

## Goal
Rebuild the posture editor piece-by-piece from the `PostureEditorV2` shell, fixing input/camera/UI issues at each checkpoint rather than debugging the monolith.

## Checkpoints

### ✅ CP0 — Archive & Plan
- [x] Copy v1 code to archive
- [x] Write this plan document

### ✅ CP1 — Window Resize on Open/Close
**What:** When the editor opens, maximize the window. When it closes, restore previous geometry.  
**Why:** This was the simplest self-contained behavior from v1's `_on_editor_opened` / `_on_editor_closed`. Proves the shell can talk to the windowing system.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — added `_expand_window()` / `_restore_window()` inside `open()` / `close()`
- `scripts/game.gd` — connected v2 signals to `_on_editor_v2_opened` / `_on_editor_v2_closed` stubs
- `scripts/input_handler.gd` — `KEY_E` now calls `_toggle_posture_editor_v2()` instead of v1

### ✅ CP2 — Editor Camera Mode
**What:** Switch camera to orbit_mode=3 (editor orbit) on open, restore previous mode on close.  
**Why:** Isolates camera switching from input handling.  
**Files touched:**
- `scripts/game.gd` — `_on_editor_v2_opened` saves camera state + switches to orbit_mode=3; `_on_editor_v2_closed` restores it
- `scripts/game.gd` — `_physics_process` now sets `editor_focus_point` from v2 (player position) when v2 is visible

### ✅ CP3 — Basic UI Panel with Mouse Blocking
**What:** A panel that actually blocks mouse events from leaking to the 3D viewport.  
**Why:** Fixes the core input bug where UI clicks were stolen by camera orbit / gizmos.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — root `mouse_filter` changed to `STOP`; added `contains_screen_point()`
- `scripts/camera/camera_rig.gd` — already had `is_mouse_over_editor_ui_cb` check in `handle_input()`
- `scripts/game.gd` — wired callback to v2 (after v2 is created); stopped v1 gizmo init so old gizmos don't steal input

### ✅ CP4 — Posture List + Selection
**What:** ItemList that loads posture/base-pose definitions. Click to select.  
**Why:** First data-binding checkpoint. No gizmos yet.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — added ItemList, workspace toggle, status label; wires to `PostureLibrary.instance()` and `BasePoseLibrary.instance()`
- `scripts/posture_library.gd` / `base_pose_library.gd` — reused existing singletons

### ✅ CP5 — Inspector Tabs (sliders only)
**What:** TabContainer with Body/Paddle/Charge/Follow-Through tabs, each with sliders/editors bound to definition fields.  
**Why:** Pure UI-data binding; still no 3D interaction.  
**Files touched:**
- New: `scripts/posture_editor_v2/simple_inspector.gd` — generic field builder (float, vector3, option, bool)
- `scripts/posture_editor_v2.gd` — added HSplit layout with list + TabContainer; 4 tabs wired up; stroke-only tabs hidden in base-pose mode

### ✅ CP6 — Live Preview (Pose Freeze)
**What:** "Preview Pose" button freezes player into selected posture.  
**Why:** Brings back the pose trigger system one piece at a time.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — added Preview Pose button, `set_player()`, `_process()` for pose trigger update, auto-release on close/selection change
- `scripts/game.gd` — wired `player_left` into v2 via `set_player()`

### ✅ CP7 — 3D Gizmos (Position)
**What:** Click-and-drag paddle position gizmo in the 3D viewport.  
**Why:** The hardest part; tackled in isolation with working UI/camera underneath.  
**Files touched:**
- New: `scripts/posture_editor_v2/position_gizmo_v2.gd` — simple spherical gizmo
- New: `scripts/posture_editor_v2/gizmo_controller_v2.gd` — raycast + camera-plane drag, respects UI boundary
- `scripts/posture_editor_v2.gd` — creates paddle gizmo on selection, updates definition on drag, syncs inspectors

### ✅ CP8 — 3D Gizmos (Rotation)
**What:** Rotation ring gizmos for hips, chest, and head.  
**Files touched:**
- New: `scripts/posture_editor_v2/rotation_gizmo_v2.gd` — 3-axis ring gizmo with camera-plane angle calculation
- `scripts/posture_editor_v2/gizmo_controller_v2.gd` — handles both position and rotation gizmos
- `scripts/posture_editor_v2.gd` — creates rotation gizmos at skeleton bone positions, updates body rotation fields on drag

### ✅ CP9 — Save / Load
**What:** Save button writes `.tres` for the selected posture or base pose.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — added Save button + `_on_save()` that writes to `data/postures/` or `data/base_poses/`

### ✅ CP10 — Transport / Transition Preview
**What:** "Preview Swing" button plays charge→contact→follow-through using existing TransitionPlayer.  
**Files touched:**
- `scripts/posture_editor_v2.gd` — added Preview Swing button + `_on_preview_swing()` that sets up TransitionPlayer with ready/charge/contact/FT defs and toggles play/pause

## Rules
1. **One checkpoint at a time.** Merge & test before moving on.
2. **If a checkpoint is buggy, do NOT add more code.** Fix it or revert.
3. **Reuse v1 archive code** by copying files out of `scripts/archive/posture_editor_v1/` rather than rewriting from scratch.
4. **Delete v1 references from `game.gd`** as v2 subsystems replace them.
