# Pickleball Godot - Architecture Documentation

## Overview

A 3D pickleball simulation built with Godot 4.6. The game features realistic ball physics with aerodynamics (drag, Magnus effect, spin damping), a full-body procedural animation system via inverse kinematics (IK), an AI opponent with configurable difficulty, and a posture editor for designing swing poses.

---

## Project Structure

```
pickleball-godot/
├── scenes/              # Godot scene files (.tscn)
│   ├── ball.tscn
│   ├── court.tscn
│   ├── game.tscn         # Main scene
│   ├── player.tscn
│   └── paddle.tscn
├── scripts/              # All GDScript code
│   ├── archive/           # Archived/refactored code
│   ├── camera/           # Camera rig + shake
│   ├── fx/               # Visual effects (trails, decals, bursts)
│   ├── posture_editor/   # In-editor posture editing tool
│   ├── tests/             # Unit + E2E tests
│   ├── time/             # Time scale management
│   ├── ui/               # HUD, menus, settings
│   ├── ball.gd           # Ball physics + audio synth
│   ├── constants.gd      # Global constants (autoload)
│   ├── game.gd           # Root orchestrator (~500 lines)
│   ├── physics.gd        # Physics utilities
│   ├── player.gd         # Player controller (full body)
│   ├── player_ai_brain.gd # AI decision-making
│   ├── posture_controller.gd # Posture state machine
│   ├── shot_physics.gd   # Ball hitting physics
│   └── ...
├── resources/            # Art, meshes, textures
├── docs/                 # Design documents & plans
└── project.godot         # Godot project config
```

---

## Core Architecture

### 1. Game Orchestrator (`game.gd`)

**Role**: Thin root orchestrator. Owns all game state and scoring. Delegates subsystem work to child nodes.

**Key State**:
```gdscript
enum GameState { WAITING, SERVING, PLAYING, POINT_SCORED }
var score_left, score_right: int
var serving_team: int
var game_state: GameState
var serve_charge_time: float
```

**Child Subsystems** (all created as children, not injected):
| Subsystem | Purpose |
|-----------|---------|
| `GameServe` | Serve charge, aim/arc, serve execution |
| `GameTrajectory` | Trajectory visualization |
| `GameShots` | Shot classification, out indicator |
| `GameDropTest` | Kinematic bounce calibration |
| `GameDebugUI` | Debug labels, posture display |
| `GameSoundTune` | Sound signature tuning panel |

**Wiring Pattern**:
- `game.gd` instantiates subsystems via `preload()` + `.new()`
- Each subsystem receives refs to `game.gd`, `ball`, `player_left`, `player_right`
- Callbacks use `signal_name.connect(_handler)` pattern

---

### 2. Ball Physics (`ball.gd`)

**Physics Model** (custom, not Godot physics):
- Quadratic air drag: `F_drag = -0.5 * ρ * Cd * A * |v| * v`
- Magnus curl force: `F_magnus = k * (ω × v)`
- Spin damping (exponential decay with half-life)
- Velocity-dependent COR (coefficient of restitution): `0.78 → 0.56` from 3→18 m/s
- Spin-tangential bounce coupling on floor contact

**Key Constants** (tuned via `AERO_EFFECT_SCALE`):
```gdscript
const DRAG_COEFFICIENT := 0.47
const MAGNUS_COEFFICIENT := 0.0003
const SPIN_DAMPING_HALFLIFE := 150.0
const AERO_EFFECT_SCALE := 0.79
```

**Predictors** (static methods mirror `_physics_process` for AI/debug):
- `predict_aero_step()` — single step with drag + Magnus + spin decay
- `predict_bounce_spin()` — bounce with spin coupling

**Signals**: `hit_by_paddle`, `bounced`, `hit_player_body`

---

### 3. Shot Physics (`shot_physics.gd`)

Computes target ball velocity for a shot given:
- Ball position
- Charge ratio (0→1)
- Player number (0=blue/human, 1=red/AI)
- Shot type: SMASH, FAST, VOLLEY, DINK, DROP, LOB, RETURN

**Algorithm**:
1. Select target speed from `MIN_SWING_SPEED_MS → MAX_SWING_SPEED_MS` curve
2. Select target landing zone based on shot type
3. Iteratively solve ballistic trajectory (6 iterations) to clear the net
4. Compute spin axis from shot type (topspin/backspin/sidespin)
5. Apply sweet-spot speed penalty for off-center paddle contact

**Key Gap References**: GAP-15 (sweet-spot), GAP-X (paddle velocity transfer)

---

### 4. Player Controller (`player.gd`)

Full body character with procedural animation via IK.

**Submodules** (child nodes):
| Module | Purpose |
|--------|---------|
| `posture` (PlayerPaddlePosture) | Paddle position/rotation from posture definitions |
| `hitting` (PlayerHitting) | Swing animation, charge/release, paddle velocity |
| `pose_controller` | Base pose state machine (athletic_ready, split_step, etc.) |
| `body_animation` | Torso/hip animation blendspace |
| `arm_ik` (PlayerArmIK) | Two-bone IK for arm chains |
| `leg_ik` (PlayerLegIK) | Leg positioning |
| `ai_brain` | AI movement + hitting decisions |
| `awareness_grid` | Spatial grid for ball prediction |

**Paddle Postures** (22 states):
```gdscript
enum PaddlePosture {
    FOREHAND, FORWARD, BACKHAND,
    MEDIUM_OVERHEAD, HIGH_OVERHEAD,
    LOW_FOREHAND, LOW_FORWARD, LOW_BACKHAND,
    CHARGE_FOREHAND, CHARGE_BACKHAND,
    WIDE_FOREHAND, WIDE_BACKHAND,
    VOLLEY_READY,
    MID_LOW_FOREHAND, MID_LOW_BACKHAND, MID_LOW_FORWARD,
    MID_LOW_WIDE_FOREHAND, MID_LOW_WIDE_BACKHAND,
    LOW_WIDE_FOREHAND, LOW_WIDE_BACKHAND,
    READY,
}
```

**Base Pose States** (for body positioning):
```gdscript
enum BasePoseState {
    ATHLETIC_READY, SPLIT_STEP, RECOVERY_READY,
    KITCHEN_NEUTRAL, DINK_BASE, DROP_RESET_BASE,
    PUNCH_VOLLEY_READY, DINK_VOLLEY_READY, DEEP_VOLLEY_READY,
    GROUNDSTROKE_BASE, LOB_DEFENSE_BASE,
    FOREHAND_LUNGE, BACKHAND_LUNGE, LOW_SCOOP_LUNGE,
    OVERHEAD_PREP, JUMP_TAKEOFF, AIR_SMASH, LANDING_RECOVERY,
    LATERAL_SHUFFLE, CROSSOVER_RUN, BACKPEDAL, DECEL_PLANT,
}
```

---

### 5. Posture System

**Files**:
- `posture_definition.gd` — Resource with 40+ @export fields per posture
- `posture_library.gd` — Runtime library of all 22 posture definitions
- `posture_skeleton_applier.gd` — Applies posture to Skeleton3D bones
- `posture_offset_resolver.gd` — Computes paddle world position from posture
- `posture_commit_selector.gd` — Commit zone validation
- `posture_colors.gd` — Debug visualization colors
- `posture_constants.gd` — Posture-related constants

**PostureDefinition Fields** (grouped by subsystem):
- Identity: `posture_id`, `display_name`, `family`, `height_tier`
- Paddle Position: `paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset`
- Paddle Rotation: `paddle_pitch/yaw/roll_base_deg` + `*_signed_deg` + `sign_source`
- Commit Zone: `zone_x_min/max`, `zone_y_min/max`
- Right/Left Arm IK: `*_hand_offset`, `*_elbow_pole`, `*_shoulder_rotation_deg`
- Legs: `stance_width`, `front_foot_forward`, `back_foot_back`, knee poles
- Torso: `hip_yaw_deg`, `torso_yaw/pitch/roll_deg`, `spine_curve_deg`
- Head: `head_yaw/pitch_deg`, `head_track_ball_weight`
- Charge: `charge_paddle_offset/rotation`, `charge_body_rotation_deg`, `charge_hip_coil_deg`
- Follow-through: `ft_paddle_offset/rotation`, `ft_hip_uncoil_deg`, timing

**Mirroring**: Postures use signed-angle pattern with `swing_sign` (+1 blue, -1 red) and `fwd_sign` for blue/red differentiation.

---

### 6. AI Brain (`player_ai_brain.gd`)

**State Machine**:
```gdscript
enum AIState { INTERCEPT_POSITION, CHARGING, HIT_BALL }
```

**Key Features**:
- **GAP-47 Visuomotor Latency**: Ring buffer simulating 133-300ms reaction delay based on difficulty
- **Trajectory Prediction**: Iteratively steps ball physics to find intercept point
- **Posture Selection**: Score function weighing reposition cost + posture preference + paddle error
- **Difficulty Levels**: Easy/Medium/Hard with different speed scales, reaction latency, swing thresholds
- **Intercept Pool**: Pre/post-bounce contact point candidates for two-bounce rule compliance

**Prediction Functions**:
- `_predict_first_bounce_position()` — Where ball lands
- `_predict_ai_contact_candidates()` — 3 hittable points (pre-bounce, first bounce, second bounce)
- `_predict_ai_intercept_marker_point()` — Optimal intercept with height filtering

---

### 7. Camera System (`camera/`)

- `camera_rig.gd` — Orbit/tilt camera with editor mode focus
- `camera_shake.gd` — Screen shake on impacts

Camera modes: Editor focus (when posture editor open), normal gameplay

---

### 8. Visual Effects (`fx/`)

| File | Purpose |
|------|---------|
| `fx_pool.gd` | Object pool for impact effects |
| `ball_trail.gd` | Trail mesh following ball |
| `bounce_decal.gd` | Court decal on bounce |
| `impact_burst.gd` | Particle burst on paddle hit |
| `hit_feedback.gd` | Camera shake + effects on hit |

---

### 9. UI System (`ui/`)

| File | Purpose |
|------|---------|
| `hud.gd` | Main HUD canvas |
| `scoreboard_ui.gd` | Score display, state text |
| `pause_menu.gd` | Pause screen |
| `settings_panel.gd` | Settings controls |
| `settings.gd` | Settings singleton (autoload) |
| `pause_controller.gd` | Pause state management (autoload) |

---

### 10. Posture Editor (`posture_editor/`)

In-engine tool for designing posture poses. **Only runs in editor** (not in shipped game).

**Key Files**:
| File | Purpose |
|------|---------|
| `posture_editor_state.gd` | Editor state machine |
| `posture_editor_gizmos.gd` | Gizmo management |
| `posture_editor_preview.gd` | Live preview rendering |
| `posture_editor_transport.gd` | Timeline transport (play/pause) |
| `gizmo_controller.gd` | Base gizmo logic |
| `gizmo_handle.gd` | Drag handle |
| `rotation_gizmo.gd` | Rotation gizmo |
| `position_gizmo.gd` | Position gizmo |
| `pose_trigger.gd` | Trigger zones |
| Tabs: `arms_tab.gd`, `legs_tab.gd`, `torso_tab.gd`, `head_tab.gd`, `paddle_tab.gd`, `charge_tab.gd`, `follow_through_tab.gd` | Property editors |

**UI**: `posture_editor_ui.gd` — Main editor panel

---

### 11. Game Modes

| File | Purpose |
|------|---------|
| `game_serve.gd` | Serve charge + release flow |
| `game_shots.gd` | Shot classification + out detection |
| `game_trajectory.gd` | Trajectory arc visualization |
| `game_drop_test.gd` | Physics calibration tool |
| `game_debug_ui.gd` | Debug overlay |
| `game_sound_tune.gd` | Audio tuning panel |
| `practice_launcher.gd` | Practice mode ball launcher |

---

### 12. Constants (`constants.gd`)

All gameplay constants in one place (autoload as `PickleballConstants`):
- Court dimensions, net height
- Ball properties (mass, radius, COR)
- Player speed, paddle force
- AI parameters
- Posture thresholds

---

## Data Flow

```
Input (keyboard/controller)
    ↓
input_handler.gd          # Raw input → intent
    ↓
game.gd                   # Game state machine
    ↓
┌───────────────────────────────────────────────┐
│  player_left / player_right                    │
│  ├── posture (PlayerPaddlePosture)             │
│  │   └── Reads PostureDefinition from library  │
│  ├── pose_controller (BasePoseState machine)   │
│  ├── hitting (swing animation)                │
│  ├── arm_ik / leg_ik (IK chains)              │
│  └── ai_brain (AI only)                       │
└───────────────────────────────────────────────┘
    ↓
ball.gd                   # Physics simulation
    ↓
shot_physics.gd           # Hitting calculations
    ↓
FX + Audio               # Visual/audio feedback
```

---

## Key Design Patterns

### 1. Child Subsystem Pattern
```gdscript
# game.gd creates subsystems as children (not injected)
game_serve = _GameServe.new()
add_child(game_serve)
game_serve.setup(self, ball, player_left, player_right, ...)
```

### 2. Static Predictor Methods
Ball physics predictors are `static` so AI and debug visuals can call them without a ball instance:
```gdscript
static func predict_aero_step(...) -> Array
static func predict_bounce_spin(...) -> Array
```

### 3. Gap Documentation
Code references "GAP-N" comments (Gameplay Analysis Points) tracking physics decisions:
- GAP-15: Sweet-spot speed reduction
- GAP-21: COR vs impact speed
- GAP-41: Serve angular velocity
- GAP-47: AI reaction latency
- GAP-55: Drag equation
- GAP-59: Magnus force
- GAP-60: Spin-tangential bounce
- GAP-61: Spin damping

### 4. Posture Resource Pattern
Postures are `PostureDefinition` Resources (`.gd` with `@export` fields), not hardcoded. The posture editor can modify them at runtime.

### 5. Signal-Based Decoupling
```gdscript
ball.bounced.connect(_on_ball_bounced)
ball.hit_by_paddle.connect(_on_any_paddle_hit)
rally_scorer.rally_ended.connect(_on_rally_ended)
```

---

## Autoloads (Singletons)

| Name | Type | Purpose |
|------|------|---------|
| `PickleballConstants` | `constants.gd` | All gameplay constants |
| `Settings` | `ui/settings.gd` | User preferences |
| `TimeScale` | `time/time_scale_manager.gd` | Slow-mo control |
| `FXPool` | `fx/fx_pool.gd` | Effect object pooling |
| `PauseController` | `ui/pause_controller.gd` | Pause state |

---

## Testing

**Unit Tests** (`scripts/tests/`):
- `test_physics_utils.gd` — Physics math
- `test_player_hitting.gd` — Hitting logic
- `test_base_pose_system.gd` — Posture system
- `test_rally_scorer.gd` — Scoring
- `test_shot_physics.gd` — Shot calculations

**E2E Tests**:
- `e2e_test_runner.gd` — Godot-level integration tests
- `test_e2e_playwright.py` — Browser-based UI testing
- `test_e2e_mcp.py` — Claude agent integration
- `test_e2e_ultrafast.py` — Fast smoke tests

**Fakes** (`tests/fakes/`):
- `fake_ball.gd`, `fake_ball_node.gd`, `fake_player.gd` — Test doubles

---

## Debug Features

- **V key**: Cycle debug visuals (zone overlays, trajectory lines, AI markers)
- **X key**: Cycle difficulty (Easy/Medium/Hard)
- **T key**: Drop test mode (calibrate ball bounce)
- **B key**: Toggle intent indicators
- **Posture editor** (Tab): In-engine posture editing (editor only)
- **Ball spin visualizers**: Axis arrow + equator markers showing spin direction
- **Bounce spots**: Yellow circles on ball bounce (when debug on)

---

## Known Architecture Notes

1. **Orphaned helpers**: `game.gd` creates `_court_helper` and `_net_helper` via `script.new()` but doesn't add them to the tree — freed in `_exit_tree()` to avoid ObjectDB leaks.

2. **Preload order**: `game.gd` preloads all class_name scripts at the top to ensure correct load order and avoid parse errors.

3. **Camera rig preload**: `CameraRigScript` is a `preload` const (not in _preload dict) because it's used in `_setup_camera_rig()`.

4. **SwingE2EProbe**: Created after `ball_physics_probe` due to initialization order requirements.

5. **Two-bounce rule**: AI uses `ball.both_bounces_complete` to determine when volleys are legal.

6. **AI reaction latency**: Hardcoded frame counts per difficulty — Easy 18 frames, Medium 12, Hard 8 (at 60Hz).
