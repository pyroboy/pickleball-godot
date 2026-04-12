# Posture Editor Enhancement Plan
## Bringing Implementation to Full Proposal Fidelity

**Status**: Planning Phase  
**Estimated Effort**: 4-6 days  
**Priority**: Medium (nice-to-have polish after core gameplay)

---

## Executive Summary

The current posture editor provides **infrastructure** (data layer, library, skeleton) and **basic UX** (sliders for paddle fields, view-only 3D boxes). This plan details the work needed to reach **full proposal fidelity**:

1. **Draggable 3D Gizmos** — interactive handles for paddle, knees, feet, head
2. **Trigger Pose System** — snap player to static pose for inspection
3. **Transition Scrubber** — play charge→contact→follow-through animation
4. **Full-Body UI** — tabs/fields for legs, arms, head, torso

---

## Phase Breakdown

### Wave 1: Foundation (Day 1)
| Task | Description | Complexity |
|------|-------------|------------|
| 1.1 | Gizmo interaction framework (raycasting, selection, dragging) | High |
| 1.2 | Refactor posture_editor_ui.gd into modular components | Medium |

### Wave 2: 3D Gizmos (Days 2-3)
| Task | Description | Complexity |
|------|-------------|------------|
| 2.1 | Paddle position gizmo (draggable sphere with axis handles) | High |
| 2.2 | Paddle rotation gizmo (ring handles for pitch/yaw/roll) | High |
| 2.3 | Knee pole gizmos (diamond markers, draggable) | Medium |
| 2.4 | Foot position gizmos (flat discs, draggable) | Medium |
| 2.5 | Head aim gizmo (forward arrow, draggable) | Medium |

### Wave 3: Pose & Preview (Day 4)
| Task | Description | Complexity |
|------|-------------|-------|
| 3.1 | Trigger Pose button — freeze game, snap player to posture | Medium |
| 3.2 | Full-body field UI — tabs for legs/arms/head/torso | Medium |
| 3.3 | Two-way binding — gizmo drag updates slider, slider updates gizmo | Medium |

### Wave 4: Transitions (Days 5-6)
| Task | Description | Complexity |
|------|-------------|------------|
| 4.1 | Charge→Contact→Follow-Through tween system | High |
| 4.2 | Scrubber UI — timeline with play/pause/seek | Medium |
| 4.3 | Loop mode for continuous preview | Low |

---

## Detailed Technical Plan

### 1. Gizmo Interaction Framework

**Problem**: Current gizmos are view-only MeshInstance3D boxes. Need interactive handles.

**Approach**:
```gdscript
# New: scripts/posture_editor/gizmo_controller.gd
class_name GizmoController extends Node3D

## Handles 3D gizmo interaction via raycasting
## - Mouse hover detection
## - Click-to-select
## - Drag-to-move (with axis constraints)
## - Visual feedback (highlight selected, show axes)

var _camera: Camera3D
var _selected_gizmo: GizmoHandle = null
var _dragging: bool = false
var _drag_plane: Plane
var _drag_offset: Vector3

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _try_select_gizmo(event.position)
            else:
                _stop_drag()
    elif event is InputEventMouseMotion and _dragging:
        _update_drag(event.position)

func _try_select_gizmo(screen_pos: Vector2) -> void:
    # Raycast from camera through mouse position
    var ray_origin := _camera.project_ray_origin(screen_pos)
    var ray_dir := _camera.project_ray_normal(screen_pos)
    
    # Find closest gizmo intersecting ray
    # ... ray-sphere or ray-box intersection ...
    
    if hit_gizmo:
        _start_drag(hit_gizmo, hit_point)
```

**Key Components**:
- `GizmoHandle` base class (position handle, rotation handle, etc.)
- Axis constraint system (drag along X/Y/Z or plane)
- Visual feedback (highlight, axis lines)
- Two-way data binding with PostureDefinition

**Files to Create**:
- `scripts/posture_editor/gizmo_controller.gd`
- `scripts/posture_editor/gizmo_handle.gd` (base)
- `scripts/posture_editor/position_gizmo.gd`
- `scripts/posture_editor/rotation_gizmo.gd`

---

### 2. Paddle Position Gizmo

**Design**:
- Sphere at paddle position (as proposal suggests)
- Three axis handles (red=X, green=Y, blue=Z) extending from sphere
- Drag sphere = free movement
- Drag axis handle = constrained to that axis
- Click sphere without drag = select (highlight)

**Integration**:
- Updates `PostureDefinition.paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset`
- Must respect player's facing direction (forehand/forward axes)
- Live preview in 3D viewport

**Algorithm for Axis-Constrained Drag**:
```gdscript
func _drag_constrained_to_axis(screen_pos: Vector2, axis: Vector3) -> void:
    # Project mouse ray onto drag plane
    var ray = _camera.project_ray(screen_pos)
    var intersection = _drag_plane.intersects_ray(ray.origin, ray.dir)
    
    # Project intersection onto axis line
    var to_point = intersection - _drag_start_pos
    var projected = to_point.dot(axis) * axis
    
    # Update gizmo position
    _gizmo.position = _drag_start_pos + projected
    
    # Convert back to posture definition values
    _update_posture_from_world_position(_gizmo.global_position)
```

---

### 3. Paddle Rotation Gizmo

**Design** (as proposal):
- Ring gizmo around paddle
- Three rings (red=pitch, green=yaw, blue=roll)
- Drag ring = rotate around that axis
- Visual feedback: ring highlights on hover

**Implementation**:
- Use TorusMesh for rings
- Ray-torus intersection for selection
- Arcball rotation or direct angle mapping
- Update `PostureDefinition` rotation fields (with sign-source awareness)

---

### 4. Knee Pole Gizmos

**Design**:
- Diamond shape (OctahedronMesh)
- Positioned at knee pole target
- Color-coded: right=red, left=blue
- Drag to adjust pole target

**Integration**:
- Updates `PostureDefinition.right_knee_pole`, `left_knee_pole`
- Affects leg IK solving in real-time
- Must be relative to hip/thigh position

---

### 5. Foot Position Gizmos

**Design**:
- Flat disc (CylinderMesh with height=0.01)
- Positioned on ground at foot target
- Color-coded: right=red, left=blue
- Drag to move foot target

**Integration**:
- Updates `PostureDefinition.right_foot_offset`, `left_foot_offset`
- Affects leg IK target position
- Y position should clamp to ground level

---

### 6. Head Aim Gizmo

**Design**:
- Arrow pointing in head look direction
- Base at head position
- Drag arrow tip to adjust yaw/pitch
- Cone at arrow tip for grab target

**Integration**:
- Updates `PostureDefinition.head_yaw_deg`, `head_pitch_deg`
- Affects head bone rotation via skeleton

---

### 7. Trigger Pose System

**Purpose**: Allow inspecting a posture without hitting a ball

**Implementation**:
```gdscript
# In posture_editor_ui.gd
func _on_trigger_pose() -> void:
    if not _current_def or not _player:
        return
    
    # Freeze game time
    Engine.time_scale = 0.0
    
    # Snap player to posture
    _player.paddle_posture = _current_def.posture_id
    
    # Force immediate posture application (no tween)
    if _player.posture:
        _player.posture.force_posture(_current_def)
    
    # Apply full-body skeleton pose
    if _skeleton_applier:
        _skeleton_applier.apply(_current_def)
    
    # Show "Frozen for inspection" indicator
    _show_frozen_indicator()

func _on_resume_game() -> void:
    Engine.time_scale = 1.0
    _hide_frozen_indicator()
```

**UI Changes**:
- Add "Trigger Pose" button to editor UI
- Show "Game Frozen" banner when active
- Auto-resume on editor close or press Escape

---

### 8. Full-Body UI Fields

**Current State**: Only paddle fields shown
**Target**: Organized tabs/groups for all body parts

**Layout**:
```
┌─────────────────────────────────────────────┐
│  [Paddle] [Legs] [Arms] [Head] [Torso]      │  ← TabContainer
├─────────────────────────────────────────────┤
│                                             │
│  Selected Tab Content:                      │
│  ├─ Slider: Stance Width    [====●===] 0.35 │
│  ├─ Slider: Front Foot Fwd  [===●====] 0.12 │
│  ├─ Slider: Back Foot Back  [====●===] -0.08│
│  ├─ Vec3:   Right Knee Pole [x][y][z]       │
│  └─ Vec3:   Left Knee Pole  [x][y][z]       │
│                                             │
└─────────────────────────────────────────────┘
```

**Implementation**:
- Use Godot's `TabContainer` node
- Create reusable `Vector3Editor` control (3 spin boxes)
- Create reusable `SliderWithLabel` control
- Group fields by body part from PostureDefinition

**Files**:
- `scripts/posture_editor/property_editors/vector3_editor.gd`
- `scripts/posture_editor/property_editors/slider_field.gd`
- `scripts/posture_editor/tabs/paddle_tab.gd`
- `scripts/posture_editor/tabs/legs_tab.gd`
- `scripts/posture_editor/tabs/arms_tab.gd`
- `scripts/posture_editor/tabs/head_tab.gd`
- `scripts/posture_editor/tabs/torso_tab.gd`

---

### 9. Transition Scrubber System

**Purpose**: Preview charge→contact→follow-through animation

**Design**:
- Timeline with three markers: Charge, Contact, Follow-Through
- Play button: animate through full sequence
- Pause/Stop buttons
- Scrubber handle: drag to any point in timeline
- Loop toggle: repeat animation
- Duration settings per phase

**Implementation**:
```gdscript
# New: scripts/posture_editor/transition_player.gd
class_name TransitionPlayer extends Node

enum Phase { CHARGE, CONTACT, FOLLOW_THROUGH, SETTLE }

var _phase_durations := {
    Phase.CHARGE: 0.5,
    Phase.CONTACT: 0.1,  # Instant hit
    Phase.FOLLOW_THROUGH: 0.3,
    Phase.SETTLE: 0.2
}

var _current_time: float = 0.0
var _total_duration: float = 1.1  # Sum of phases
var _playing: bool = false

func play() -> void:
    _playing = true
    _current_time = 0.0

func stop() -> void:
    _playing = false
    _current_time = 0.0

func seek(t: float) -> void:
    _current_time = clamp(t, 0.0, _total_duration)
    _apply_pose_at_time(_current_time)

func _process(delta: float) -> void:
    if not _playing:
        return
    
    _current_time += delta
    if _current_time >= _total_duration:
        if _loop:
            _current_time = 0.0
        else:
            _playing = false
            return
    
    _apply_pose_at_time(_current_time)

func _apply_pose_at_time(t: float) -> void:
    # Determine phase and lerp factor
    var phase_info = _get_phase_at_time(t)
    
    match phase_info.phase:
        Phase.CHARGE:
            # Lerp from ready to charge posture
            _lerp_postures(_ready_def, _charge_def, phase_info.factor)
        Phase.CONTACT:
            # Instant switch to contact
            _apply_posture(_contact_def)
        Phase.FOLLOW_THROUGH:
            # Lerp through follow-through sequence
            var ft_defs = _get_follow_through_definitions()
            var idx = int(phase_info.factor * (ft_defs.size() - 1))
            var local_t = fmod(phase_info.factor * (ft_defs.size() - 1), 1.0)
            _lerp_postures(ft_defs[idx], ft_defs[idx + 1], local_t)
```

**UI**:
- Horizontal slider (0-100%)
- Phase markers (vertical lines at phase boundaries)
- Play/Pause/Stop buttons
- Loop checkbox
- Duration inputs per phase

---

## File Structure

```
scripts/posture_editor/
├── posture_editor_ui.gd              (refactored, thinner)
├── gizmo_controller.gd               (new)
├── gizmo_handle.gd                   (new, base)
├── position_gizmo.gd                 (new)
├── rotation_gizmo.gd                 (new)
├── transition_player.gd              (new)
├── property_editors/
│   ├── vector3_editor.gd             (new)
│   └── slider_field.gd               (new)
└── tabs/
    ├── paddle_tab.gd                 (new)
    ├── legs_tab.gd                   (new)
    ├── arms_tab.gd                   (new)
    ├── head_tab.gd                   (new)
    └── torso_tab.gd                  (new)
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Raycasting performance with 21 postures × 5 gizmos | Medium | Medium | Use spatial hash, only raycast when mouse moves |
| Gizmo dragging feels laggy | Medium | High | Use immediate mode updates, defer posture save |
| Two-way binding creates infinite loops | Medium | High | Use change flags, block re-entrant updates |
| Transition player conflicts with game state | High | High | Freeze time, isolate player from AI/ball physics |
| Camera angle makes gizmos hard to select | Medium | Medium | Add gizmo size scaling by distance, alternate camera angles |

---

## Success Criteria

- [ ] Can drag paddle position gizmo and see posture update live
- [ ] Can drag knee/foot/head gizmos and see skeleton react
- [ ] Click "Trigger Pose" freezes game and snaps player to posture
- [ ] "Play Transition" scrubs through charge→contact→FT smoothly
- [ ] UI shows tabs for all body parts with working sliders
- [ ] Two-way binding: gizmo drag updates slider, slider updates gizmo
- [ ] All changes save to .tres and persist

---

## Next Steps

1. **Review this plan** — confirm scope and priorities
2. **Wave 1 implementation** — gizmo framework + refactoring
3. **Wave 2 implementation** — all 3D gizmos
4. **Wave 3 implementation** — Trigger Pose + full-body UI
5. **Wave 4 implementation** — Transition scrubber
6. **Integration testing** — verify all features work together

**Ready to proceed?** Say "start Wave 1" or ask questions about specific features.
