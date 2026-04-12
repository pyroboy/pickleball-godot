# Draft: Big File Refactor — Harmonious Code

## Existing Plans
- `charge-ft-pairs.md` — charge + FT data + runtime refactor
- `posture-editor-enhancement.md` — posture editor enhancements (gizmos, trigger pose, scrubber)

## Largest Files Identified
| File | Lines | Primary Responsibility |
|------|-------|----------------------|
| game.gd | 1768 | Game loop, scoring, serve, UI, speedometer |
| player_paddle_posture.gd | 1595 | Paddle posture tracking, ghost system, commit |
| posture_editor_ui.gd | 1283 | Editor UI, gizmos, tabs |
| ball_audio_synth.gd | 905 | Audio synthesis |
| player_debug_visual.gd | 881 | Debug markers, intercept/step/traj |
| player_ai_brain.gd | 790 | AI state machine, trajectory prediction |

## User Stated Goals
- "all code to be harmonious"
- "improve upon" existing plan
- Wants to refactor big files

## Godot Best Practices (Research Findings)

**Key recommendations from Godot docs + GDQuest:**
1. **Project structure**: `snake_case` everywhere; group scripts by domain (`entities/`, `components/`, `autoloads/`, `states/`)
2. **Composition over inheritance**: Attach reusable behavior as child nodes (e.g., `HealthComponent`, `MovementComponent`)
3. **File size**: Split files approaching ~500 lines; multiple focused files over monoliths
4. **DRY**: Extract shared logic into components, `class_name` types, and constants
5. **Naming**: `PascalCase` class names, `snake_case` files/vars, `ALL_CAPS` constants, enums with `ALL_CAPS` values

## Key Findings: Duplication & Organization Issues

### 🔴 Duplicate/Redundant Files
1. **`game.gd` (1768) vs `archive/game.gd` (1379)** — archive is OLD version. Both exist in `scripts/`, not truly archived.
2. **`compute_shot_velocity`** — exists BOTH in `game.gd:925` AND `shot_physics.gd:19`
3. **`compute_shot_spin`** — exists BOTH in `game.gd:944` AND `shot_physics.gd:179`
4. **`compute_sweet_spot_spin`** — exists BOTH in `game.gd:961` AND `shot_physics.gd:217`
5. **`simulate_shot_trajectory`** — exists BOTH in `game.gd:921` AND `shot_physics.gd:230`
6. **`serve_trajectory.gd`** — DUPLICATES trajectory/aim/arc code from `game.gd`
7. **`_get_basis_from_rotation`** — duplicated in `pose_trigger.gd:246` and `player_paddle_posture.gd:1590`
8. **`_damp`** (damping pattern) — only in `player.gd:406` but USED by `player_leg_ik.gd` and `player_body_animation.gd` via `_player._damp()` — these are tightly coupled to PlayerController

### 🟡 Structural Issues
1. **`ball_audio_synth.gd` (905 lines)** — large file doing audio synthesis. Could be split into `synth/` subdirectory with per-sound-type modules
2. **`player_debug_visual.gd` (881 lines)** — debug-only, but large. Should be clearly separated from gameplay code
3. **`player_paddle_posture.gd` (1595 lines)** — mixes 4 concerns: ghost system, commit logic, posture zones, full-body skeleton application
4. **`game.gd` (1768 lines)** — mixes: environment setup, game state, scoring, UI, audio tuning, drop test, trajectory, camera. Needs `autoloads/` for managers and `components/` for subsystems
5. **Constants scattered** — `constants.gd` exists but `game.gd` still redefines some constants locally (e.g., `BLUE_RESET_POSITION`, `RED_RESET_POSITION`)
6. **Player modules loosely organized** — `player_arm_ik.gd`, `player_leg_ik.gd`, `player_body_animation.gd`, `player_hitting.gd`, `player_awareness_grid.gd` are all player sub-modules but sit at top level instead of `player/` subdirectory

### 🟢 What's Good
1. Class names properly declared with `class_name` throughout (57 classes)
2. Constants centralized in `PickleballConstants` (mostly)
3. Posture editor well-structured with `tabs/` and `property_editors/` subdirs
4. FX system with pool pattern (`fx_pool.gd`)
5. State machine patterns in `player_ai_brain.gd`

## Proposed Directory Restructure (Godot-aligned)

```
scripts/
├── autoloads/              # Singleton managers (NEW)
│   ├── game_manager.gd     # (extracted from game.gd)
│   ├── audio_manager.gd    # (extracted from ball_audio_synth.gd)
│   └── events.gd           # Signal bus
├── components/             # Reusable behavior (NEW)
│   ├── damping.gd          # _damp + _damp_v3 (extract from player.gd)
│   ├── trajectory.gd       # Shared serve/trajectory math
│   └── shot_math.gd        # compute_shot_velocity/spin (dedup game.gd + shot_physics.gd)
├── entities/               # (rename player-related)
│   ├── player/
│   │   ├── player_controller.gd   # (rename from player.gd)
│   │   ├── player_movement.gd    # (extract from player.gd)
│   │   ├── player_hitting.gd
│   │   ├── player_arm_ik.gd
│   │   ├── player_leg_ik.gd
│   │   ├── player_body_animation.gd
│   │   ├── player_body_builder.gd
│   │   ├── player_debug_visual.gd
│   │   ├── player_awareness_grid.gd
│   │   └── ai/
│   │       └── player_ai_brain.gd
│   └── ball/
│       ├── ball.gd
│       └── ball_audio_synth.gd   # (to be split further)
├── ui/
│   ├── hud.gd
│   ├── scoreboard_ui.gd
│   ├── pause_menu.gd + pause_controller.gd  # (merge?)
│   ├── settings.gd + settings_panel.gd       # (merge?)
│   └── reaction_hit_button.gd
├── court/
│   ├── court.gd
│   └── net.gd
├── editor/                 # (rename from posture_editor/)
│   ├── posture_editor_ui.gd
│   ├── pose_trigger.gd
│   ├── gizmo_controller.gd
│   └── tabs/ + property_editors/
├── states/                # State machines (NEW location for future)
├── resources/             # .tres files
│   ├── posture_library.gd
│   ├── posture_definition.gd
│   └── base_pose_library.gd + base_pose_definition.gd
├── camera/
│   ├── camera_rig.gd
│   └── camera_shake.gd
├── fx/
│   ├── fx_pool.gd
│   ├── impact_burst.gd
│   ├── bounce_decal.gd
│   ├── ball_trail.gd
│   └── hit_feedback.gd
├── tests/
├── time/
│   └── time_scale_manager.gd
└── [utilities]
    ├── constants.gd
    ├── physics.gd
    ├── rules.gd
    ├── shot_physics.gd           # (to be merged/deduped)
    ├── rally_scorer.gd
    ├── serve_trajectory.gd       # (dedup with trajectory.gd component)
    ├── input_handler.gd
    ├── practice_launcher.gd
    ├── drop_test.gd
    ├── ball_physics_probe.gd
    └── [archive/]               # (DELETE after confirming game.gd replaces it)
```

## Decisions Made
- **Approach**: C — one file at a time, with full directory restructure as north star
- **"Harmonious" meaning**: No duplicated functions + code easy to access/navigate
- **Behavior preservation**: Byte-identical gameplay after each split
- **Priority**: game.gd first (largest, 63 functions, 10+ responsibilities)

## Plan Created
- `game-gd-split.md` — full split plan for game.gd (1768 → 7 focused files)

## Open Questions
1. Which specific files does user want to focus on first?
2. What does "harmonious" mean? (naming conventions, code organization, patterns?)
3. Is the user OK with the existing plans being incorporated into a unified refactor plan?
4. What are the pain points with current file organization?
5. Should I prioritize gameplay-critical files (game.gd, player_paddle_posture.gd) vs tool files (posture_editor_ui.gd)?

## Scope Boundaries (TBD)
- IN: Splitting large files, consistent naming, pattern alignment
- OUT: (not yet defined)

## Technical Approach (TBD)
- How should files be split? By feature? By concern?
- What naming conventions to enforce?
- How to ensure refactored code maintains byte-identical gameplay behavior?