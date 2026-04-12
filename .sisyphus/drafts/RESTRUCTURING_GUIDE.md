# Pickleball Godot — Restructuring Guide

> **Status**: In Progress
> **Vision**: Harmonious codebase — no duplicated logic, every file <= ~500 lines, easy to navigate
> **Approach**: One file at a time (Approach C), keeping full directory restructure in mind

---

## Why Restructure?

| Problem | Impact |
|---------|--------|
| Files > 500 lines (Godot best practice threshold) | Hard to navigate, high bug risk |
| Duplicated functions (same logic in 2+ files) | Inconsistent behavior, double maintenance |
| Mixed responsibilities in one file | Can't reuse, can't test in isolation |
| Flat directory structure | Have to search everywhere for related files |

---

## The Target Structure

```
scripts/
├── autoloads/              # Singletons — global managers
│   ├── game_manager.gd     # Game state, scoring, rules (extracted from game.gd)
│   ├── audio_manager.gd   # Sound synthesis (extracted from ball_audio_synth.gd)
│   └── events.gd           # Signal bus — decouple systems
│
├── components/             # Reusable behavior — attach to any node
│   ├── damping.gd          # _damp() + _damp_v3() — one source of truth
│   ├── trajectory.gd       # Serve/trajectory math — deduped
│   └── shot_math.gd       # compute_shot_velocity/spin — deduped
│
├── entities/               # Game objects with composed behavior
│   ├── player/
│   │   ├── player_controller.gd   # Main player — thin, delegates to modules
│   │   ├── player_hitting.gd
│   │   │   ├── player_arm_ik.gd
│   │   │   ├── player_leg_ik.gd
│   │   │   ├── player_body_animation.gd
│   │   │   ├── player_body_builder.gd
│   │   │   ├── player_paddle_posture.gd   # SPLIT: ghosts | commit | zones | skeleton
│   │   │   ├── player_awareness_grid.gd
│   │   │   └── ai/
│   │   │       └── player_ai_brain.gd
│   └── ball/
│       ├── ball.gd
│       └── ball_audio_synth.gd   # SPLIT: per-sound-type modules
│
├── ui/
│   ├── hud.gd
│   ├── scoreboard_ui.gd
│   ├── pause_menu.gd
│   ├── settings.gd
│   └── reaction_hit_button.gd
│
├── court/
│   ├── court.gd
│   └── net.gd
│
├── editor/                 # (renamed from posture_editor/)
│   ├── posture_editor_ui.gd
│   ├── pose_trigger.gd
│   ├── gizmo_controller.gd
│   ├── transition_player.gd
│   ├── tabs/
│   │   ├── paddle_tab.gd
│   │   ├── legs_tab.gd
│   │   ├── arms_tab.gd
│   │   ├── head_tab.gd
│   │   ├── torso_tab.gd
│   │   └── follow_through_tab.gd
│   └── property_editors/
│       ├── vector3_editor.gd
│       └── slider_field.gd
│
├── camera/
│   ├── camera_rig.gd
│   └── camera_shake.gd
│
├── fx/
│   ├── fx_pool.gd
│   ├── impact_burst.gd
│   ├── bounce_decal.gd
│   ├── ball_trail.gd
│   └── hit_feedback.gd
│
├── resources/             # Data definitions (.gd files that define data, not behavior)
│   ├── posture_library.gd
│   ├── posture_definition.gd
│   ├── base_pose_library.gd
│   └── base_pose_definition.gd
│
├── tests/
│   ├── fakes/
│   └── test_*.gd
│
├── time/
│   └── time_scale_manager.gd
│
└── utilities/            # Pure utilities — no node dependency
    ├── constants.gd       # PickleballConstants — single source of truth
    ├── physics.gd
    ├── rules.gd
    ├── shot_physics.gd    # Merged: deduped shot math
    ├── rally_scorer.gd
    ├── input_handler.gd
    ├── practice_launcher.gd
    ├── drop_test.gd
    └── ball_physics_probe.gd
```

---

## Principles

### 1. File Size Cap: ~500 Lines
- If a file approaches 500 lines, split it.
- Each file does ONE thing.

### 2. No Duplicated Logic
- `_damp` → `components/damping.gd` only
- `compute_shot_velocity` → `components/shot_math.gd` only
- `compute_shot_spin` → `components/shot_math.gd` only
- Trajectory math → `components/trajectory.gd` only
- Delete `archive/game.gd` (old dead code)

### 3. Composition Over Monolith
- Player is NOT one giant file.
- Player is `player_controller.gd` + child modules attached in `_ready()`.
- Each module has ONE job.

### 4. Naming Conventions (Godot 4 Standard)
| Thing | Convention | Example |
|-------|------------|---------|
| File names | `snake_case.gd` | `player_controller.gd` |
| Class names | `PascalCase` | `class_name PlayerController` |
| Variables/functions | `snake_case` | `move_speed`, `_physics_process` |
| Private variables | `_snake_case` | `_health`, `_velocity` |
| Constants | `ALL_CAPS` | `MAX_SPEED` |
| Enum values | `ALL_CAPS` | `State.IDLE` |
| Directories | `snake_case` | `player/`, `fx/` |

### 5. Decouple with Signals
- Systems communicate via signals, not direct method calls.
- Use an `events.gd` autoload as the event bus.

---

## File Split Plan

Files listed in order of priority (largest/most critical first):

### Phase 1: Game.gd Split (1768 → ~5 files)
**Current state**: One 1768-line file doing everything
**Target**: ~5 focused files

| New File | Responsibility | Approx Lines |
|----------|---------------|-------------|
| `game.gd` | Thin: wires nodes, owns game state enum | ~400 |
| `game_scoring.gd` | Score tracking, point logic, reset | ~200 |
| `game_serve.gd` | Serve charge, release, fault detection | ~300 |
| `game_trajectory.gd` | Trajectory visual, serve aim, arc intent | ~300 |
| `game_environment.gd` | Sky, lighting, environment setup | ~200 |
| `game_debug.gd` | Debug visuals, labels, HUD wiring | ~200 |
| `game_sound_tune.gd` | Sound tuning panel, settings wiring | ~150 |

### Phase 2: Player Paddle Posture Split (1595 → ~4 files)
**Current state**: Ghosts + commit + zones + full-body skeleton in one file
**Target**: ~4 focused files

| New File | Responsibility | Approx Lines |
|----------|---------------|-------------|
| `paddle_posture_ghosts.gd` | Ghost creation, coloring, green pool | ~450 |
| `paddle_posture_commit.gd` | Commit system: FIRST/TRACE/LOCK | ~400 |
| `paddle_posture_zones.gd` | Posture zone definitions, height detection | ~300 |
| `paddle_posture_skeleton.gd` | Full-body posture application (skeleton IK) | ~400 |

### Phase 3: Deduplicate Shot Math
**Current state**: `compute_shot_velocity/spin/sweet_spot_spin` exist in BOTH `game.gd` AND `shot_physics.gd`
**Fix**: Move to `components/shot_math.gd`, update all callers

| Caller | Change |
|--------|--------|
| `game.gd` | Call `ShotMath.compute_shot_velocity()` instead of local function |
| `player_ai_brain.gd` | Call `ShotMath.compute_shot_velocity()` instead of local function |
| `shot_physics.gd` | Call `ShotMath.compute_shot_velocity()` instead of local function |
| Delete | `serve_trajectory.gd` duplicates → merge into `components/trajectory.gd` |

### Phase 4: Extract Damping Utility (shared across player modules)
**Current state**: `_damp()` + `_damp_v3()` only in `player.gd:406-409`
**Issue**: `player_leg_ik.gd` and `player_body_animation.gd` call `_player._damp()` — tight coupling
**Fix**: Extract to `components/damping.gd` as `class_name Damping`

### Phase 5: Ball Audio Synth Split (905 → ~3 files)
**Current state**: 905-line file with all synth logic
**Target**: `synth/` subdirectory

| New File | Responsibility |
|----------|---------------|
| `synth/paddle_synth.gd` | Paddle hit sounds |
| `synth/court_synth.gd` | Court bounce sounds |
| `synth/net_synth.gd` | Net tape/mesh sounds |
| `synth/base_synth.gd` | Common wave generation utilities |

### Phase 6: Delete Dead Code
- `scripts/archive/game.gd` — old version, confirmed replaced by `game.gd`
- Any `.gd` files that only contain commented-out code

---

## Consolidation Map

Functions that need to be merged/deduped:

```
Shot Physics (shot_math.gd / components/)
├── compute_shot_velocity()     ← game.gd:925  AND  shot_physics.gd:19
├── compute_shot_spin()         ← game.gd:944  AND  shot_physics.gd:179
├── compute_sweet_spot_spin()  ← game.gd:961  AND  shot_physics.gd:217
└── simulate_shot_trajectory()  ← game.gd:921  AND  shot_physics.gd:230

Trajectory (trajectory.gd / components/)
├── get_predicted_serve_velocity()  ← game.gd:1191  AND  serve_trajectory.gd:55
├── draw_trajectory()              ← game.gd:1307  AND  serve_trajectory.gd:116
├── clear_trajectory_predictor()   ← game.gd:1390  AND  serve_trajectory.gd:139
├── get_aim_label()               ← game.gd:1280  AND  serve_trajectory.gd:95
├── get_arc_label()               ← game.gd:1287  AND  serve_trajectory.gd:102
└── apply_arc_intent_to_impulse() ← game.gd:1294  AND  serve_trajectory.gd:109

Damping (damping.gd / components/)
└── _damp() + _damp_v3()  ← player.gd:406  (used by player_leg_ik, player_body_animation)

Utilities
└── _get_basis_from_rotation()  ← pose_trigger.gd:246  AND  player_paddle_posture.gd:1590
```

---

## What Gets Deleted

| File | Reason |
|------|--------|
| `scripts/archive/game.gd` | Dead — replaced by `game.gd` |
| `scripts/serve_trajectory.gd` | Duplicates `components/trajectory.gd` after dedup |
| `scripts/shot_physics.gd` | Logic moved to `components/shot_math.gd` |

---

## Naming Corrections Needed

Some files don't match their `class_name`:

| File | class_name | File Name | Fix |
|------|-----------|-----------|-----|
| `player.gd` | `PlayerController` | ✓ matches | Rename file to `player_controller.gd` |
| `posture_editor_ui.gd` | `PostureEditorUI` | ✓ matches | Rename directory to `editor/` |
| `posture_editor/` | — | — | Rename to `editor/` |

---

## Existing Plans to Merge

When execution reaches these files, coordinate with existing plans:

| Existing Plan | Files It Touches | Integration Point |
|---------------|-----------------|-------------------|
| `charge-ft-pairs.md` | `player_hitting.gd`, `posture_library.gd` | Phase 3 (hitting) |
| `posture-editor-enhancement.md` | `posture_editor_ui.gd`, `pose_trigger.gd` | Phase 2 (editor split) |

---

## Rules for Every Refactor

1. **Byte-identical behavior** — unless explicitly changing gameplay, refactors must not alter runtime behavior
2. **One task per file** — each file does one thing well
3. **No backward refs** — if file A used to import from file B, after restructure the import path changes but the API stays the same
4. **Test after each split** — run the game, verify the split section still works before moving on
5. **Update this guide** — as splits land, update the file counts and status below

---

## Progress Tracker

| Phase | File | Status | Lines (before → after) |
|-------|------|--------|----------------------|
| 1 | **game.gd** | ✅ **PLAN CREATED** | 1768 → 1 orchestrator (~500) + 7 child nodes |
| 2 | player_paddle_posture.gd | ⬜ Not started | 1595 → ~4 files |
| 2 | player_paddle_posture.gd | ⬜ Not started | 1595 → ~4 files |
| 3 | shot_math dedup | ⬜ Not started | 2 copies → 1 |
| 4 | damping.gd extract | ⬜ Not started | coupled → decoupled |
| 5 | ball_audio_synth.gd | ⬜ Not started | 905 → ~3 files |
| 6 | Delete archive/game.gd | ⬜ Not started | 1379 lines gone |
| 7 | Delete serve_trajectory.gd | ⬜ Not started | 143 lines gone |

---

*Last updated: 2026-04-12*
