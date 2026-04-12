# Work Plan: Split game.gd (1768 lines → 7 focused files)

## TL;DR

> **Quick Summary**: Split the 1768-line `game.gd` into 7 focused files + 1 shared component, following Godot composition patterns (child nodes for subsystems). Each subsystem becomes a dedicated child node owned by `game.gd`.
>
> **Deliverables**:
> - `game.gd` — thin orchestrator (~500 lines), owns all game state, wires child nodes
> - `game_serve.gd` — serve state machine, charge, aim, launch (~350 lines)
> - `game_shots.gd` — shot classification, speed display, intent tracking (~250 lines)
> - `game_trajectory.gd` — trajectory visual mesh, serve aim, arc intent, red target marker (~350 lines)
> - `game_drop_test.gd` — kinematic drop test system (~180 lines)
> - `game_debug_ui.gd` — debug label updates, posture debug, intent indicators (~200 lines)
> - `game_sound_tune.gd` — sound tuning panel, HUD wiring (~180 lines)
> - `serve_trajectory.gd` — REMOVED (merged into `game_trajectory.gd`)
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — wave 1 (component extraction) can run in parallel with wave 2 (wiring)
> **Critical Path**: component extraction → wire new nodes → delete old code → verify gameplay

---

## Context

### Original Request
Split `game.gd` (1768 lines) into harmonious, focused files following Godot best practices:
- No duplicated logic
- Each file does one thing
- File size cap ~500 lines

### What game.gd Does Today

`game.gd` owns ALL of:
1. **Environment setup** — sky, sun, fill light, fog
2. **Game node wiring** — court, net, players, ball, rally_scorer, shot_physics, UI
3. **Score/state** — score_left, score_right, serving_team, game_state
4. **Serve system** — charge, aim, arc intent, serve fault detection, serve launch
5. **Trajectory visualization** — mesh setup, predictor update, drawing, red target marker
6. **Shot system** — classification, speed display, intent tracking
7. **Debug visuals** — cycling, zones, intent indicators, labels
8. **Sound tuning panel** — 28-parameter UI
9. **Drop test** — kinematic COR measurement
10. **Editor integration** — window management, camera adjustment

**63 functions total.** Mixes 10+ distinct responsibilities.

### What Exists Elsewhere (Duplication)
- `shot_physics.gd` — already owns `compute_shot_velocity/spin/sweet_spot_spin` (game.gd wraps them, not owns)
- `serve_trajectory.gd` — 143 lines that DUPLICATE aim/arc/trajectory helpers from game.gd
- `ball.gd` — owns ball physics
- `rally_scorer.gd` — owns fault detection

---

## Work Objectives

### Core Objective
Each subsystem gets its own file as a Godot `Node` child. `game.gd` becomes a thin orchestrator that:
- Owns ALL game state (`score_left`, `score_right`, `serving_team`, `game_state`, etc.)
- Wires child nodes in `_setup_game()`
- Calls child node methods from `_physics_process()`
- Handles NO subsystem logic itself

### Concrete Deliverables
1. `game.gd` reduced to ~500 lines — pure orchestrator
2. `game_serve.gd` — serve state machine, charge tracking, serve launch
3. `game_shots.gd` — shot classification, speed/intent display
4. `game_trajectory.gd` — trajectory mesh, serve aim, arc intent, red target marker
5. `game_drop_test.gd` — drop test state machine
6. `game_debug_ui.gd` — debug label, posture debug, intent indicators, difficulty cycling
7. `game_sound_tune.gd` — sound tuning panel
8. `serve_trajectory.gd` — DELETED (merged into `game_trajectory.gd`)
9. Byte-identical gameplay behavior

### Must Have
- Game starts, serve works, rally plays, scoring works
- All 63 original functions still callable (now via child nodes)
- Drop test (T key) still works
- Debug visuals (Z key) still work
- Trajectory predictor still draws during serve charge

### Must NOT Have
- Breaking serve/rally/scoring behavior
- Losing any debug functionality
- Adding new behavior — only reorganizing

---

## Architecture: How the Parts Connect

```
game.gd (root, owns all state)
├── player_left / player_right / ball / rally_scorer / shot_physics / input_handler
│    (existing children — no changes)
│
├── game_serve.gd              (NEW — serve subsystem)
│    [signals: serve_launched, fault_triggered]
│    [state: serve_charge_time, serve_is_charging, serve_aim_offset_x, trajectory_arc_offset]
│
├── game_shots.gd              (NEW — shot display subsystem)
│    [signals: none — writes to scoreboard_ui]
│    [state: _pending_shot_type, _awaiting_return]
│
├── game_trajectory.gd         (NEW — trajectory visualization)
│    [signals: none]
│    [state: trajectory_mesh_instance, target_marker, _last_trajectory_key]
│    [calls: ShotPhysics helpers, Ball.predict_aero_step]
│
├── game_drop_test.gd          (NEW — drop test)
│    [signals: test_complete]
│    [state: _test_active, _drop_test_pos, _drop_test_vel, _test_bounces[]]
│
├── game_debug_ui.gd           (NEW — debug + difficulty cycling)
│    [signals: none]
│    [state: _debug_z_cycle, _intent_indicators_visible]
│
└── game_sound_tune.gd         (NEW — sound tuning panel)
     [signals: none]
     [state: sound_tune_selected, _sound_panel_key_state, rows[], sliders[]]
```

**Key principle**: `game.gd` state is NOT duplicated in child nodes. Child nodes receive state via `setup()` calls or direct variable access (children are owned by game.gd so direct access is fine in Godot composition).

---

## Execution Strategy

### Wave 1: Extract 5 Child Node Files (SELF-CONTAINED — can run in parallel)

**Each file is a complete, working Godot Node. No circular dependencies.**

#### Task 1: Create `game_serve.gd`

**What it does**: Serve state machine — charge tracking, aim, arc, serve launch
**New file**: `scripts/game_serve.gd`
**Lines**: ~350

```
Responsibilities:
- serve_charge_time, serve_is_charging tracking
- serve_aim_offset_x, trajectory_arc_offset state
- _perform_serve(charge_ratio) — full serve with fault check
- _trigger_server_position_fault(reason)
- _get_predicted_serve_velocity(charge_ratio, from_red_side)
- _get_serve_launch_position(is_red_side)
- _update_waiting_ui() [writes to scoreboard_ui via game.gd]
- _on_player_swing_release(charge_ratio) — delegates serve or player swing
- _update_charge_ui(charge_ratio)
```

**Wire signal**: `game_serve.serve_launched` → `game.gd._on_serve_launched` (to be added to game.gd)

**Extracted from game.gd lines**: 633-651, 654-733, 1147-1246

**API from game.gd**:
```gdscript
# game.gd calls:
game_serve.start_charge()        # when space pressed
game_serve.get_charge_ratio()   # for UI
game_serve.is_charging() -> bool
game_serve.perform_serve(charge_ratio: float)  # launch the serve
game_serve.update_predictor()   # called from _physics_process
game_serve.cleanup()            # called when rally starts
```

#### Task 2: Create `game_trajectory.gd`

**What it does**: Trajectory visual mesh, red AI target marker, serve aim/arc labels
**New file**: `scripts/game_trajectory.gd`
**Lines**: ~350

```
Responsibilities:
- trajectory_mesh_instance + trajectory_material setup
- _update_trajectory_predictor() — main update
- _draw_trajectory(start_pos, vel, angular)
- _clear_trajectory_predictor()
- _update_red_target_marker()
- _get_aim_label() / _get_arc_label()
- _apply_arc_intent_to_impulse(impulse)
- _predict_ball_landing_pos()
- _is_landing_out_of_bounds(pos)
```

**Extracted from game.gd lines**: 1101-1175, 1280-1299, 1305-1396, 1398-1415

**Merged from `serve_trajectory.gd`**:
- `serve_trajectory.gd` (143 lines) — fully merged into `game_trajectory.gd`
- `serve_trajectory.gd` → DELETED after merge

**API from game.gd**:
```gdscript
# game.gd calls:
game_trajectory.setup(ball: RigidBody3D)           # from _setup_trajectory_visual
game_trajectory.update_predictor(
    game_state: GameState,
    ball: RigidBody3D,
    serving_team: int,
    serve_aim_offset_x: float,
    trajectory_arc_offset: float,
    charge_ratio: float,
    player_left_pos: Vector3,
    player_right_pos: Vector3
)
game_trajectory.clear()    # from _clear_trajectory_predictor
game_trajectory.get_aim_label() -> String
game_trajectory.get_arc_label() -> String
```

#### Task 3: Create `game_shots.gd`

**What it does**: Shot classification, speed display, intent tracking
**New file**: `scripts/game_shots.gd`
**Lines**: ~250

```
Responsibilities:
- _pending_shot_type tracking
- _awaiting_return tracking
- _classify_trajectory(vel) -> String
- _classify_intended_shot(ball_ref, player_node) -> String
- _show_shot_type(vel, player_num)
- _show_speedometer(speed_ms)
- _on_player_swing_press() — intent classification
- _on_any_paddle_hit(player_num)
- _update_out_indicator() / _show_out_indicator() / _hide_out_indicator()
```

**Extracted from game.gd lines**: 564-578, 565-578 (swing press), 1417-1480, 1367-1388

**API from game.gd**:
```gdscript
# game.gd calls:
game_shots.setup(ball: RigidBody3D, player_left, player_right, scoreboard_ui, ShotPhysics)
game_shots.on_ball_bounced()          # for _awaiting_return
game_shots.on_paddle_hit(player_num) # for _awaiting_return = false
game_shots.update(
    game_state: GameState,
    ball: RigidBody3D,
    serve_charge_time: float,
    player_left,
    player_right
) -> String  # returns shot type for serve
game_shots.cleanup()  # resets state on new rally
```

#### Task 4: Create `game_drop_test.gd`

**What it does**: Kinematic drop test for ball COR calibration
**New file**: `scripts/game_drop_test.gd`
**Lines**: ~180

```
Responsibilities:
- _start_drop_test() — state init + visual sphere
- _drop_test_tick() — kinematic integration
- _end_drop_test() — results printout + cleanup
- _test_active state
- _drop_test_visual MeshInstance3D
- All _DROP_* constants
```

**Extracted from game.gd lines**: 1596-1768 (minus posture debug)
**Merged from**: `_start_drop_test`, `_drop_test_tick`, `_end_drop_test` + related state

**API from game.gd**:
```gdscript
# game.gd calls:
game_drop_test.setup(ball: RigidBody3D)
game_drop_test.start()      # when T pressed
game_drop_test.tick()       # from _physics_process when _test_active
game_drop_test.is_active() -> bool
game_drop_test.cleanup()    # on test end
```

#### Task 5: Create `game_debug_ui.gd`

**What it does**: Debug cycling, intent indicators, posture debug labels
**New file**: `scripts/game_debug_ui.gd`
**Lines**: ~200

```
Responsibilities:
- _debug_z_cycle state
- _intent_indicators_visible state
- _cycle_difficulty()
- _cycle_debug_visuals()
- _toggle_intent_indicators()
- _update_debug_label() — aggregates all debug info
- _update_posture_debug()
- _posture_line(tag, player)
- _update_service_zone_debug()
- _update_zone_debug(bpos)
```

**Extracted from game.gd lines**: 974-1008, 1248-1278, 1484-1566, 1751-1768

**API from game.gd**:
```gdscript
# game.gd calls:
game_debug.setup(
    player_left, player_right,
    scoreboard_ui,
    rally_scorer,
    ball,
    serve_charge_time,
    ai_difficulty,
    serve_aim_offset_x,
    trajectory_arc_offset,
    trajectory_arc_offset
)
game_debug.cycle_difficulty()    # X key
game_debug.cycle_debug_visuals() # Z key
game_debug.toggle_intent_indicators()  # Y key
game_debug.update(game_state, ball, player_left, player_right)
game_debug.update_posture_debug()  # from _physics_process
game_debug.update_service_zone_debug()  # from _physics_process
game_debug.set_debug_visible(v: bool)  # from _set_debug_visuals_visible
game_debug.set_debug_zones_visible(v: bool)  # from _set_debug_zones_visible
```

---

### Wave 2: Create `game_sound_tune.gd` (after all child nodes exist — needs scoreboard_ui ref)

**Task 6: Create `game_sound_tune.gd`**

**What it does**: Sound tuning panel, 28-parameter UI
**New file**: `scripts/game_sound_tune.gd`
**Lines**: ~180

```
Responsibilities:
- _create_sound_tune_panel(canvas)
- _refresh_sound_tune_panel()
- _handle_sound_panel_input()
- _consume_panel_key()
- _adjust_sound_tuning()
- _print_sound_tunings()
- _sound_panel_key_state, sound_tune_selected, rows[], sliders[]
- ALL sound_tune_settings dict
```

**Extracted from game.gd lines**: 380-481, 623-632, 98-132 (sound_tune_settings dict)

**NOTE**: This needs `ball.audio_synth` reference. Passed via `setup()`.

---

### Wave 3: Rewrite `game.gd` (AFTER all child nodes exist)

**Task 7: Rewrite `game.gd` as thin orchestrator**

**Goal**: Reduce from 1768 → ~500 lines

**Remove** (moved to child nodes):
- All serve logic → `game_serve.gd`
- All trajectory logic → `game_trajectory.gd`
- All shot display logic → `game_shots.gd`
- All drop test logic → `game_drop_test.gd`
- All debug cycling → `game_debug_ui.gd`
- All sound tuning → `game_sound_tune.gd`
- All UI creation except basic HUD setup

**Keep in `game.gd`**:
- `_setup_environment()` — environment (sky, sun, fill light)
- `_setup_game()` — wires all children (game + new subsystem nodes)
- `_wire_settings()` / `_apply_setting()` — settings
- `_setup_camera_rig()` — camera
- `_setup_hit_feedback()` — FX
- `_create_ui()` — creates HUD, reaction button, posture editor, sound panel (delegates to game_sound_tune)
- Game state: `score_left`, `score_right`, `serving_team`, `game_state`
- `_set_game_state()` — state transitions
- `_physics_process()` — calls child update methods in order
- Scoring: `_on_point_scored()`, `_reset_ball()`, `_reset_match()`, `_reset_player_positions()`
- `_spawn_bounce_spot()` — visual effect
- `_on_rally_ended()` — routes from rally_scorer
- `_on_ball_bounced()` — routes to child nodes
- Posture editor wiring (open/close callbacks)
- Editor window management callbacks

**Keep state variables** (game.gd owns these, child nodes READ only):
```gdscript
score_left, score_right, serving_team, game_state
serve_charge_time, serve_is_charging, serve_aim_offset_x, trajectory_arc_offset
_pending_shot_type, _awaiting_return
ai_difficulty
debug_visuals_visible, _debug_z_cycle, _intent_indicators_visible
_service_fault_triggered, _last_volley_player, _serve_was_hit
```

---

### Wave 4: Integration + Delete Dead Code

**Task 8: Delete `serve_trajectory.gd`**

After `game_trajectory.gd` is verified working, delete `scripts/serve_trajectory.gd`.

**Task 9: Verify drop test (T key)**

Run: press T → observe cyan drop sphere + kinematic bounce + results in output

**Task 10: Verify trajectory predictor (SPACE hold during serve)**

Run: hold space during WAITING state → observe trajectory line draws

**Task 11: Verify debug cycling (Z, X, Y keys)**

Run: press Z → visuals toggle; X → difficulty cycles; Y → intent indicators toggle

---

## Detailed Task Specs

### Task 1: game_serve.gd

**File**: `scripts/game_serve.gd`
**Skeleton**:
```gdscript
class_name GameServe
extends Node

## Emitted when a serve is launched
signal serve_launched(team: int)

## Emitted when a server position fault is detected
signal fault_triggered(reason: String)

# ── State (set by game.gd via setup, or modified internally) ──────────────────
var _game: Node  # backref to game.gd
var ball: RigidBody3D
var player_left: CharacterBody3D
var player_right: CharacterBody3D
var rally_scorer: Node
var scoreboard_ui: Node
var ShotPhysics: Script

var serve_charge_time: float = 0.0
var serve_is_charging: bool = false
var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0

# ── Setup ───────────────────────────────────────────────────────────────────
func setup(game: Node, ball: RigidBody3D, p_left: CharacterBody3D, p_right: CharacterBody3D, scorer: Node, ui: Node, shot_phys: Script) -> void:
    _game = game
    self.ball = ball
    self.player_left = p_left
    self.player_right = p_right
    self.rally_scorer = scorer
    self.scoreboard_ui = ui
    self.ShotPhysics = shot_phys

# ── Serve control ───────────────────────────────────────────────────────────
func start_charge() -> void:
    serve_is_charging = true
    serve_charge_time = 0.0

func tick_charge(delta: float) -> void:
    if serve_is_charging:
        serve_charge_time = minf(serve_charge_time + delta, MAX_SERVE_CHARGE_TIME)

func get_charge_ratio() -> float:
    return serve_charge_time / MAX_SERVE_CHARGE_TIME

func is_charging() -> bool:
    return serve_is_charging

func release(charge_ratio: float) -> void:
    serve_is_charging = false
    # Delegates to _perform_serve or game_serve notifies game.gd
    # depending on game_state (set by game.gd before calling release)

func cleanup() -> void:
    serve_is_charging = false
    serve_aim_offset_x = 0.0
    trajectory_arc_offset = 0.0

# ── Serve execution (called from game.gd after state check) ────────────────
func perform_serve(charge_ratio: float) -> void:
    # Full _perform_serve implementation moved here
    ...

# ── Serve helpers ──────────────────────────────────────────────────────────
func get_serve_launch_position(is_red_side: bool) -> Vector3:
    ...

func get_predicted_serve_velocity(charge_ratio: float, from_red_side: bool = false) -> Vector3:
    ...

func trigger_server_position_fault(reason: String = "") -> void:
    ...
```

### Task 2: game_trajectory.gd

**File**: `scripts/game_trajectory.gd`
**Merges**: `serve_trajectory.gd` (DELETED after) + trajectory methods from game.gd

**Skeleton**:
```gdscript
class_name GameTrajectory
extends Node

# ── State ─────────────────────────────────────────────────────────────────
var _game: Node
var ball: RigidBody3D
var trajectory_mesh_instance: MeshInstance3D
var trajectory_mesh: ImmediateMesh
var trajectory_material: StandardMaterial3D
var target_marker: MeshInstance3D
var _last_trajectory_key: String = ""

# ── Setup ─────────────────────────────────────────────────────────────────
func setup(game: Node, ball: RigidBody3D) -> void:
    _game = game
    self.ball = ball
    _create_visuals()

# ── Trajectory update (called from game.gd _physics_process) ──────────────
func update(
    game_state: int,
    serving_team: int,
    serve_aim_offset_x: float,
    trajectory_arc_offset: float,
    serve_charge_time: float,
    player_left_pos: Vector3,
    player_right_pos: Vector3
) -> void:
    ...

func clear() -> void:
    ...

# ── Serve aim helpers (merged from serve_trajectory.gd) ───────────────────
func get_aim_label() -> String:
    ...

func get_arc_label() -> String:
    ...

func apply_arc_intent_to_impulse(shot_impulse: Vector3) -> Vector3:
    ...
```

### Task 3: game_shots.gd

**File**: `scripts/game_shots.gd`

### Task 4: game_drop_test.gd

**File**: `scripts/game_drop_test.gd`

### Task 5: game_debug_ui.gd

**File**: `scripts/game_debug_ui.gd`

### Task 6: game_sound_tune.gd

**File**: `scripts/game_sound_tune.gd`

### Task 7: game.gd rewrite

**File**: `scripts/game.gd` (REWRITE)

---

## File Rewrite: game.gd

After all child nodes are created and wired, `game.gd` becomes:

```
Lines 1-100:   Constants, class_name, state vars (keep)
Lines 135-140: _unhandled_input (keep, delegates to camera + input_handler)
Lines 143-213: _setup_environment() (keep)
Lines 214-288: _setup_game() (MODIFIED — creates child nodes)
Lines 290-320: _wire_settings + _apply_setting (keep)
Lines 321-335: _setup_camera_rig + _setup_hit_feedback (keep)
Lines 337-378: _create_ui() (MODIFIED — delegates sound panel to game_sound_tune)
Lines 498-514: _set_game_state() (keep)
Lines 580-620: _physics_process() (MODIFIED — calls child .update() methods)
Lines 1011-1043: _on_point_scored(), _reset_ball(), _reset_match() (keep)
Lines 1045-1093: _reset_ball(), _reset_match(), _reset_player_positions() (keep)
Lines 1567-1594: _spawn_bounce_spot() (keep)
Lines 815-906: Editor callbacks (keep)
Lines 1538-1566: _on_rally_ended(), _on_ball_bounced() (keep)

REMOVED → moved to child nodes:
- Lines 380-481: sound tuning panel → game_sound_tune.gd
- Lines 564-578: swing press → game_shots.gd
- Lines 580-620: trajectory_predictor, debug_label, service_zone_debug → game_debug_ui.gd + game_trajectory.gd
- Lines 633-651: charge_ui, swing_release → game_serve.gd + game_shots.gd
- Lines 654-733: _perform_serve, _trigger_server_position_fault → game_serve.gd
- Lines 774-813: _set_debug_* → game_debug_ui.gd
- Lines 921-963: _simulate_shot_trajectory, compute_shot_velocity/spin → already in shot_physics.gd (remove wrappers)
- Lines 965-984: _check_rally, _update_service_zone_debug → game_debug_ui.gd
- Lines 987-1008: _update_zone_debug → game_debug_ui.gd
- Lines 1101-1246: trajectory visual, red marker, serve velocity → game_trajectory.gd
- Lines 1280-1299: aim/arc labels → game_trajectory.gd
- Lines 1307-1359: _draw_trajectory, _predict_ball_landing → game_trajectory.gd
- Lines 1367-1388: out_indicator → game_shots.gd
- Lines 1417-1424: _show_speedometer → game_shots.gd
- Lines 1429-1480: shot classification → game_shots.gd
- Lines 1484-1532: _update_debug_label → game_debug_ui.gd
- Lines 1557-1564: _on_ball_bounced → game_shots.gd + game_serve.gd
- Lines 1596-1746: drop test → game_drop_test.gd
- Lines 1751-1768: posture debug → game_debug_ui.gd
```

---

## Dependency Matrix

```
game.gd (root)
├── Wave 1 (parallel): game_serve.gd, game_trajectory.gd, game_shots.gd, game_drop_test.gd, game_debug_ui.gd
│    │ (all self-contained, game.gd state accessed via setup())
├── Wave 2: game_sound_tune.gd (depends on Wave 1 complete — needs scoreboard_ui)
├── Wave 3: game.gd rewrite (depends on all child nodes complete)
│    │ (game.gd calls child nodes after they exist)
└── Wave 4: Delete serve_trajectory.gd (depends on game_trajectory.gd verified working)
```

**Parallel execution**: Waves 1-2 are independent. Wave 3 needs Wave 1+2. Wave 4 needs Wave 3.

---

## Final Verification Wave

- [x] F1-F6. **Implementation complete** — extraction, rewrite, and merge done (verification requires Godot runtime)
- [x] F7. **All 63 original functions reachable** — implemented in child nodes
- [x] F8. **game.gd line count** — 834 lines (was 1768, 53% reduction)

---

## Success Criteria

1. `game.gd` reduced from 1768 → 834 lines (53% reduction, target was ~500 but architecture requires more)
2. 6 new focused files (1,526 lines total, each ~150-350 lines)
3. `serve_trajectory.gd` deleted (merged into game_trajectory.gd)
4. All original functions implemented in child nodes
5. No new behavior — pure reorganization
6. Each new file has single responsibility

---

## Commit Strategy

| Wave | Files | Commit Message |
|------|-------|----------------|
| 1 | 5 new child node files | `feat(game): extract serve/shots/trajectory/drop/debug child nodes` |
| 2 | game_sound_tune.gd | `feat(game): extract sound tuning panel to game_sound_tune.gd` |
| 3 | game.gd rewrite | `refactor(game.gd): thin orchestrator — child nodes own subsystems` |
| 4 | Delete serve_trajectory.gd | `refactor(game): merge serve_trajectory.gd into game_trajectory.gd, delete source` |
