# Plan: posture_editor_ui.gd Refactor

## Goal
Split `scripts/posture_editor_ui.gd` (1866 lines) into focused modules with clear responsibilities. No new functionality — pure refactor.

## Constraints
- Tab sub-scripts stay at `scripts/posture_editor/tabs/*.gd` (already exist)
- Gizmo scripts stay at `scripts/posture_editor/*.gd` (already exist)
- `pose_trigger.gd` and `transition_player.gd` stay at `scripts/posture_editor/` (already exist)
- Keep all existing signal connections, enums, constants, and public API
- New files get `class_name` matching filename

## File Structure

```
scripts/posture_editor/
├── posture_editor_ui.gd          # Shell: UI build, orchestration, input, signals  (~460 lines)
├── posture_editor_state.gd       # Editor state: _current_*, dirty, workspace        (~180 lines)
├── posture_editor_gizmos.gd      # Gizmo creation, update, hover, procedural meshes  (~440 lines)
├── posture_editor_transport.gd   # Transport bar UI + playback callbacks              (~220 lines)
├── posture_editor_preview.gd     # Transition player, pose trigger, preview defs      (~230 lines)
├── tabs/                         # (already exists, untouched)
│   ├── paddle_tab.gd
│   ├── legs_tab.gd
│   ├── arms_tab.gd
│   ├── head_tab.gd
│   ├── torso_tab.gd
│   ├── charge_tab.gd
│   └── follow_through_tab.gd
```

## Module Responsibility

### `posture_editor_state.gd`
- All `_current_def`, `_current_base_def`, `_current_id`, `_is_dirty`, `_workspace_mode`, `_layout_preset`, `_editor_restore_posture_id`
- `_is_base_pose_mode()`, `_current_body_resource()`, `_current_display_name()`
- `_set_dirty()`, `_update_save_button_state()`
- `_filename_for()`, `_filename_for_base_pose()`

### `posture_editor_preview.gd`
- `_pose_trigger`, `_transition_player`
- `_setup_transition_player()`
- `_build_charge_preview_def()`, `_build_follow_through_preview_defs()`, `_copy_definition()`
- `_build_preview_posture_for_editor()`, `_contextualize_posture_for_preview()`
- `_preview_context_base_pose_id()`, `_preview_context_stroke_posture_id()`, `_preview_context_base_pose_def()`
- `_capture_live_restore_posture()`, `_restore_live_posture_from_editor()`
- `_on_play_transition()`

### `posture_editor_transport.gd`
- `_transport_bar`, `_transport_play_btn`, `_transport_save_btn`, `_transport_phase_label`, `_transport_time_label`, `_transport_progress`
- `build_transport_bar()`, `_build_transport_bar_ui()`, `_resize_transport_bar()`, `_on_transport_bar_tree_entered()`
- `_connect_transport_signals()`
- `_on_transport_play()`, `_on_transport_playback_started()`, `_on_transport_playback_stopped()`, `_on_transport_playback_finished()`, `_on_transport_phase_changed()`
- `_update_transport_ui()`

### `posture_editor_gizmos.gd`
- `_gizmo_controller`, `_knee_mesh_nodes`, `_elbow_mesh_nodes`
- `_create_gizmo_controller()`, `_create_position_gizmos()` (stub)
- `_create_paddle_gizmos()`, `_create_torso_gizmos()`, `_create_head_gizmos()`, `_create_arm_gizmos()`, `_create_leg_gizmos()`
- `_update_active_gizmos()`, `_update_gizmo_positions()`, `_update_gizmo_visibility()`
- `_calculate_paddle_world_position()`, `_color_for_family()`
- `_on_gizmo_selected()`, `_on_gizmo_moved()`, `_on_gizmo_rotated()`
- `_refresh_live_preview()` (gizmo-related part)
- `_process()` hover/glow body-part logic, procedural knee/elbow mesh creation
- `_teardown_preview_state()` (mesh cleanup part)
- `get_current_paddle_position()`

### `posture_editor_ui.gd` (shell — remains)
- Constants: `DATA_DIR`, `BASE_POSE_DATA_DIR`, `READY_POSTURE_ID`, `CHARGE_FOREHAND_POSTURE_ID`, `CHARGE_BACKHAND_POSTURE_ID`
- Enums: `Workspace`, `LayoutPreset`
- Signals: `editor_opened`, `editor_closed`
- All UI element variables
- `_ready()` full UI tree construction
- `_make_panel_style()`, `_style_action_button()`
- `_populate_posture_list()`, `_add_scroll_tab()`
- `_apply_layout_preset()`
- `_on_toggle_*()` handlers
- `_on_posture_selected()`, `_populate_properties()`, `_on_field_changed()`
- `_on_trigger_pose()`, `_on_save()`
- `_on_toggle_workspace()`, `_on_preview_context_changed()`
- `_update_solo_mode_ui()`, `_on_tab_changed()`
- `set_player()`
- `_notification()`, `_input()`
- `_update_workspace_ui()`, `_update_mode_ui()`
- `_teardown_preview_state()` (orchestration part only — calls gizmo module for mesh cleanup)
- `_on_transition_preview_started()`, `_on_transition_preview_ended()`

## Extraction Order

### Step 1: Extract `posture_editor_state.gd`
**Lines to move:** ~180 lines (state variables + helper methods)
```
Variables (lines ~33-41):
  _current_def, _current_base_def, _current_id, _is_dirty,
  _editor_restore_posture_id, _workspace_mode, _layout_preset

Methods:
  _is_base_pose_mode() → 619-621
  _current_body_resource() → 622-623
  _current_display_name() → 625-627
  _set_dirty() → 584-586
  _update_save_button_state() → 588-596
  _filename_for_base_pose() → 943-945
  _filename_for() → 947-949
```
**New file**: `scripts/posture_editor/posture_editor_state.gd`
**class_name**: `PostureEditorState`
**Wiring**: Replace inline state with `PostureEditorState.new()` instance stored in `_state`. Forward calls: `_is_base_pose_mode()` → `_state.is_base_pose_mode()`, etc.

### Step 2: Extract `posture_editor_transport.gd`
**Lines to move:** ~220 lines
```
Variables (lines ~79-84):
  _transport_bar, _transport_play_btn, _transport_save_btn,
  _transport_phase_label, _transport_time_label, _transport_progress

Methods:
  build_transport_bar() → 351-364
  _on_transport_bar_tree_entered() → 366-370
  _build_transport_bar_ui() → 372-483
  _resize_transport_bar() → 487-500
  _connect_transport_signals() → 502-508
  _on_transport_play() → 870-872
  _on_transport_playback_started() → 874-877
  _on_transport_playback_stopped() → 879-882
  _on_transport_playback_finished() → 884-892
  _on_transport_phase_changed() → 894-895
  _update_transport_ui() → 897-918
```
**New file**: `scripts/posture_editor/posture_editor_transport.gd`
**class_name**: `PostureEditorTransport`
**Wiring**: `PostureEditorTransport.new()` in `_transport`. Connect signals from external `_transition_player` via `_transport.connect_transition_signals(transition_player)`.

### Step 3: Extract `posture_editor_preview.gd`
**Lines to move:** ~230 lines
```
Variables (lines ~73-76):
  _pose_trigger, _transition_player

Methods:
  _setup_transition_player() → 823-842
  _build_charge_preview_def() → 1752-1776
  _build_follow_through_preview_defs() → 1778-1796
  _copy_definition() → 1798-1801
  _build_preview_posture_for_editor() → 675-684
  _contextualize_posture_for_preview() → 686-692
  _preview_context_base_pose_id() → 629-646
  _preview_context_stroke_posture_id() → 648-665
  _preview_context_base_pose_def() → 667-673
  _capture_live_restore_posture() → 1849-1853
  _restore_live_posture_from_editor() → 1855-1858
  _on_play_transition() → 844-866
```
**New file**: `scripts/posture_editor/posture_editor_preview.gd`
**class_name**: `PostureEditorPreview`
**Wiring**: `PostureEditorPreview.new()` in `_preview`. Forward `set_player()`, `trigger_pose()`, `is_frozen()`, etc. Playback signals connected in shell.

### Step 4: Extract `posture_editor_gizmos.gd`
**Lines to move:** ~440 lines
```
Variables (lines ~67-71):
  _gizmo_controller, _knee_mesh_nodes, _elbow_mesh_nodes, _player

Methods:
  set_player() → 1000-1002
  _create_gizmo_controller() → 1005-1038
  _create_position_gizmos() → 1041-1042 (stub)
  get_current_paddle_position() → 1044-1047
  _calculate_paddle_world_position() → 1049-1062
  _color_for_family() → 1064-1070
  _on_gizmo_selected() → 1072-1102
  _on_gizmo_moved() → 1104-1229
  _on_gizmo_rotated() → 1231-1263
  _create_paddle_gizmos() → 1284-1300
  _create_torso_gizmos() → 1302-1333
  _create_head_gizmos() → 1335-1350
  _create_arm_gizmos() → 1352-1406
  _create_leg_gizmos() → 1408-1462
  _update_active_gizmos() → 1268-1282
  _update_gizmo_positions() → 1475-1524
  _update_gizmo_visibility() → 1526-1548
  _refresh_live_preview() → 1464-1473
  _teardown_preview_state() (mesh cleanup) → 1830-1847
  _process() hover/glow section → 1577-1735
```
**New file**: `scripts/posture_editor/posture_editor_gizmos.gd`
**class_name**: `PostureEditorGizmos`
**Wiring**: `PostureEditorGizmos.new()` in `_gizmos`. `set_player()`, `set_tab_container()`, `set_transition_player()`, `set_library()`, `set_base_pose_library()`. Gizmo signals forwarded to shell.

### Step 5: Clean up `posture_editor_ui.gd`
After all modules extracted, shell should:
- Instantiate state/preview/transport/gizmos modules
- Forward UI events to appropriate module
- Keep orchestration, signal emission, and UI layout

## New File Boilerplate

Each extracted module needs:

```gdscript
class_name PostureEditor<Module> extends RefCounted

## Singletons (injected by parent shell — set via init or direct reference)
var _state: PostureEditorState
var _preview: PostureEditorPreview
var _transport: PostureEditorTransport
var _gizmos: PostureEditorGizmos
var _player: Node3D
var _library
var _base_pose_library
var _tab_container: TabContainer
var _transition_player  # TransitionPlayer reference

func init(state, preview, transport, gizmos, player, library, base_pose_library, tab_container) -> void:
    _state = state
    _preview = preview
    _transport = transport
    _gizmos = gizmos
    _player = player
    _library = library
    _base_pose_library = base_pose_library
    _tab_container = tab_container
```

## Verification Steps

1. **Syntax check**: `godot --headless --path . --check-only` (parse all new files)
2. **Load check**: Launch game, open posture editor (press E), verify all tabs load, gizmos appear, transport bar shows
3. **Interaction check**: Select posture, drag paddle gizmo, check property panel updates, save works
4. **Transition check**: Press Space (swing preview), verify transport bar updates, phase labels change
5. **Close/reopen**: Press E to close, E to reopen — editor state preserved correctly
6. **No new errors**: `godot --headless --quit-after 30 2>&1 | grep -i error` returns empty

## Risk Mitigation
- **Biggest risk**: Breaking signal connections. Mitigation: do one module at a time, test after each extraction.
- **State coupling**: `_current_def` is referenced in 40+ places. State module centralizes it.
- **Circular deps**: Gizmo module needs player; player not known at construction. Use `set_player()` deferred init.
