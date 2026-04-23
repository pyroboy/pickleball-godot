# Pickleball Godot — Product Requirements Document (Graph-Extracted)

_Derived 2026-04-23 from `graphify-out/GRAPH_REPORT.md` (1704 nodes · 2679 edges · 38 communities) + `CLAUDE.md`._

## 1. Product Summary
3D pickleball simulator in Godot 4.6.2 (GDScript). Single-player vs AI on a regulation pickleball court, with procedurally animated players, 20-posture paddle system, physics-grounded ball behavior, and a built-in posture editor for tuning player animations.

**Primary experience loop:** serve → rally → shot-selection → scoring. **Secondary experience loop:** posture editor (author/tune 20 paddle postures + 22 body base poses live against the running game).

## 2. God Nodes (Core Abstractions)
Ranked by graph centrality — these are the files/classes anything else in the system eventually touches.
| Rank | Abstraction | Role |
|------|-------------|------|
| 1 | `player.gd` — **PlayerController** (70 edges) | Owns movement, bounds, enums (`PaddlePosture`, `ShotContactState`, `ShotType`, `AIState`), composes all player modules |
| 2 | `game.gd` — **Game Orchestrator** (68 edges) | Main scene script, game loop, scoring, serve state, UI, speedometer, `compute_shot_velocity()` |
| 3 | `TestRallyScorer` (52) | Rule-enforcement test harness driving the scoring rubric |
| 4 | `PostureConstants` (51) | Thresholds, lerp speeds, ghost tuning — referenced across posture, AI, debug |
| 5 | `PlayerAIBrain` — `player_ai_brain.gd` (48) | AI state machine, bounce/intercept prediction, charge-hit |
| 6 | `Posture Editor UI` (33) | Live editor shell and wire-up for 5 sub-modules |
| 7 | `PlayerPaddlePosture` (32) | 20-posture tracking, ghost pool, trajectory-centric commit |
| 8 | `BallAudioSynth` (30) | Procedural thock/volley/smash/rim/frame audio |

## 3. Subsystems (from graph hyperedges)
Each subsystem below is a group-relationship extracted directly from the graph.

### 3.1 Player Composition
- Entry: `player.gd:_ready()` attaches child nodes.
- Modules: `player_paddle_posture.gd`, `player_arm_ik.gd`, `player_leg_ik.gd`, `player_body_animation.gd`, `player_body_builder.gd`, `player_hitting.gd`, `player_ai_brain.gd`, `player_debug_visual.gd`, `pose_controller.gd`.
- Requirement: any new body-level behavior attaches as a composable child; no monolith behavior in `player.gd`.

### 3.2 Paddle Posture System
- 20-value `PaddlePosture` enum (forehand, backhand, overheads, LOW_*, MID_LOW_*, WIDE_*, CHARGE_*).
- Height thresholds drive posture selection: LOW <0.22, MID_LOW 0.22-0.55, NORMAL ≥0.55 (above `COURT_FLOOR_Y = 0.075`).
- LOW postures invert paddle (180 roll, face net) and trigger body crouch when `ball.is_in_play`.
- Backhand postures activate two-handed grip (left hand on neck).
- Lerp speeds: wide 22, normal 16, low 12 per-second.

### 3.3 Trajectory-to-Commit Pipeline (Community 17, 30, 32)
Pipeline: `ball_in_play → debug_visual draws arc → trajectory points → set_trajectory_points() → ghosts within 0.45m glow GREEN → _find_closest_ghost_to_point() → COMMIT → color stages (PINK 3m+ → PURPLE <3m → BLUE <0.35m) → score rubric`.
- Commit state machine: **FIRST** (initial ghost pick, 0.20m center bias), **TRACE** (player >0.4m moved AND different ghost closest AND ball >1.5m, 0.15s cooldown), **LOCK** (ball <1.5m, no switching).
- Scoring grades at BLUE / closest-approach: PERFECT <0.25m, GREAT <0.40m, GOOD <0.60m, OK <0.80m, MISS ≥0.80m.

### 3.4 Shot System (4 shot types)
- Enum `ShotType`: `NORMAL`, `FAST`, `DROP`, `LOB`.
- Selection is **context-determined** (same code path for human & AI): charge_ratio, player_position, opponent_position, ball_height, contact_state, distance_to_kitchen.
- Unified velocity: both sides call `game.compute_shot_velocity(shot_type, charge, origin, player_num)`.
- Per-type parameters: `target_speed_range`, `arc_boost`, `target_z_range`, `force_multiplier`.
- Iteratively-solved net clearance + out-of-bounds correction.

### 3.5 AI Brain (Communities 0, 11, 29)
- State machine: `INTERCEPT_POSITION → CHARGING → HIT_BALL`.
- Prediction pipeline: visuomotor latency ring buffer (GAP-47), `_predict_first_bounce_position`, `_predict_ai_contact_candidates`, intercept cost-scoring across postures, posture-to-height mapping (LOW/MID_LOW/NORMAL/OVERHEAD).
- Charge gate: `ball.global_position.z < 0` (AI side).
- Shot velocity via shared `compute_shot_velocity(..., 1)`.
- Difficulty tiers (X key): EASY 80% dinks / MEDIUM 55/45 soft-firm mix / HARD 35/65 medium-drives + smart lateral targeting.
- Configurable `reaction_delay` (secs) + post-shot recovery `reaction_delay * 1.5`.

### 3.6 Ball Physics & Aero Model (Communities 2, 8, 29)
- `RigidBody3D`, mass 0.024 kg, radius 0.06, gravity scale 1.5, bounce 0.685, max speed 20.0, serve 8.0.
- Godot built-in damping **must remain 0** (`ball.tscn`); aero code in `ball.gd` is the sole drag/spin source.
- Tunable constants: `AIR_DENSITY=1.225`, `DRAG_COEFFICIENT=0.47`, `MAGNUS_COEFFICIENT=0.00012`, `SPIN_DAMPING_HALFLIFE=1.5`, `SPIN_BOUNCE_TRANSFER=0.25`, `SPIN_BOUNCE_DECAY=0.70`, `AERO_EFFECT_SCALE=0.5`.
- Forces: quadratic drag `F=-½·ρ·Cd·A·|v|·v`, Magnus `F=k·(ω×v)`, spin damping (exp decay), spin-tangential bounce coupling, ~30% spin energy loss per floor hit.
- Bounce emission: fires from inside manual floor-bounce code (not threshold-based) so fast serves register.
- Calibration: `BallPhysicsProbe` (key `4` launches + logs); drop test (key `T`) calibrates COR.

### 3.7 Serve & Rally Rules
- Two-bounce rule, volley gating, kitchen (non-volley zone) rule — enforced via `TestRallyScorer` in test harness and runtime checks in `game.gd`.
- Court: 13.4 × 6.1, net at Z=0, player-left on +Z, player-right on −Z, kitchen 1.8 from net.
- `get_court_bounds()` in `PickleballConstants` — single source of truth.

### 3.8 Posture Editor (God node #6)
Modular editor with sub-modules:
- `posture_editor_ui` (shell, `scripts/posture_editor_ui.gd`)
- `posture_editor_state.gd` (undo/redo, dirty flags)
- `posture_editor_preview.gd` (charge/follow-through preview)
- `posture_editor_transport.gd` (play/scrub/loop bar)
- `posture_editor_gizmos.gd` (3D gizmo controller wrapper)
- `posture_editor_tabs.gd` + per-tab files (paddle/legs/arms/head/torso/charge/follow-through).

**Two workspaces:** `STROKE_POSTURES` (20 paddle postures), `BASE_POSES` (22 body states).
**Interaction model:** click 3D gizmos or use per-tab form fields; preview context option toggles charge/contact/follow-through scrub.
**Hotkey E toggles editor; ESC closes.** Data persisted to `res://data/postures/*.tres` and `res://data/base_poses/*.tres`.

### 3.9 Base Pose Runtime
- 22-state `BasePoseState` enum.
- `BasePoseLibrary` (singleton, `instance()`), `BasePoseDefinition` resources.
- `PoseController` blends base poses onto strokes via `blend_onto_stroke()`, `compose_preview_posture()`, `to_preview_posture()`.
- `PoseTrigger` (Community 15) emits `pose_triggered`/`pose_released` and maps intent → pose.

### 3.10 IK System
- Right-arm IK → paddle grip (`player_arm_ik.gd`).
- Left arm two-handed grip activated by backhand postures.
- Leg IK (`player_leg_ik.gd`): gait system, step planning, foot lock.
- Body animation: lean, crouch, idle sway, walk bob.
- Procedural body mesh generation: `player_body_builder.gd`.

### 3.11 Awareness Grid
- `PlayerAwarenessGrid` — volumetric ball-proximity detector with per-vertex TTC coloring.
- API: `set_trajectory_points()`, `get_ttc_at_world_point()`, `get_posture_zone_scores()`, `get_approach_info()`, `ZoneID`.
- Open gaps: GAP-33 through GAP-39 (grid wiring to posture commit, AI anticipation, body-kinematic).

### 3.12 Camera System
- `CameraRig` (owns Camera3D + `CameraShake`): default overhead edge-threshold pan, 3rd-person cycle (P key), orbit drag (left-mouse) + auto-orbit (O), configurable FOV, trauma-based shake.
- Orbit modes: 0 default, 1 behind blue, 2 behind red, 3 posture-editor view.
- Editor mode uses FOV 72.

### 3.13 Audio System (Community 5, 23)
- `BallAudioSynth` — procedural synthesis of paddle-thock, volley, smash, rim, frame sounds.
- Pre-generated pools rotated per hit (`ObjectPool`).
- Live-tuning panel (key `M`) with 30+ sliders (paddle_attack_tune, metallic_tune, etc.).
- Python-side calibration: `synth_optimize.py` + `clip_and_compare.py` for spectral matching against recorded references.

### 3.14 FX & Feedback
- `BallTrail` (ribbon of past positions, speed-gated).
- `BounceDecal` (fading floor mark + dust burst).
- `HitFeedback` (hit-stop: `HITSTOP_DURATION`, `HITSTOP_SCALE`, `HITSTOP_THRESHOLD`; shake amount via `HIT_SHAKE_BASE/SCALE`).
- `Reaction Timing Ring` (TTC-driven UI ring) + color-stage visual.

### 3.15 UI System
- `Hud` (`scripts/ui/hud.gd`, extends CanvasLayer): score panel, status panel, speed, posture debug, shot-type label, difficulty.
- `PauseController` + `PauseMenu`.
- `ScoreboardUI` presents HUD-backed state.
- `ReactionHitButton` (easy-mode auto-fire assist).
- Sound tuning panel (toggle M).

### 3.16 Input Delegation
- `InputHandler` (`scripts/input_handler.gd`): polls keys every `_process`, dispatches to `game.gd` methods. No mouse-event consumption (polling only).
- Hotkeys: `4` practice launcher, `X` difficulty, `Z` debug visuals, `P` 3rd-person, `E` editor, `ESC` close editor, `T` drop test, `C` crouch, `O` auto-orbit, `M` sound panel, `N` intent indicators, `6-8/Y/U/I` sound tests.

### 3.17 Practice & Training
- `practice_launcher.gd` — spawns balls with configurable arcs toward Blue; auto-hit loop toggles via `1`/`2`.
- Practice zone system integrates with `PickleballConstants.get_court_bounds()`.

### 3.18 Test Infrastructure (Communities 14, 21, 22)
- Fake doubles: `_FakeBall`, `_FakePlayer`, `_RallyScorer` for isolation.
- `TestRallyScorer`, `TestShotPhysics`, E2E suites: `e2e_test_runner.gd`, `_e2e_fast_mode.gd`, plus Python drivers `test_e2e_playwright.py`, `test_e2e_mcp.py`, `test_e2e_ultrafast.py`, `test_e2e_fast.py`.
- Posture editor tests: `test_posture_editor_controls.gd`, `test_posture_persistence.gd`.
- Unit assertions: `_assert`, `_assert_eq`, `_assert_false`.

### 3.19 Debug & Calibration
- Drop test (`T`) + `ball_physics_probe.gd` (fires from key `4`).
- Debug visuals (`Z` cycle): trajectory arc, intercept pool, AI trajectory post-hit (ImmediateMesh), step markers, awareness-grid visualization, ghost pool, gizmos.
- Posture debug HUD label: STANDING/CROUCHING + posture name for both players.

## 4. Game Flow (Implicit State Machine)
`GameState` enum: `WAITING → SERVING → PLAYING → POINT_SCORED → (back to SERVING)`.
Across-system events:
1. Serve charge (space hold) → release `→` `compute_shot_velocity(SERVE)` → ball freed.
2. Bounce signal → emitted from inside floor-bounce code → consumed by rally scorer + audio + decals + trail-gating.
3. Paddle contact → `player_hitting._on_hit` → posture-aware impulse + shot-type determination → `compute_shot_velocity`.
4. Two-bounce / out-of-bounds / kitchen violation → `TestRallyScorer` rule fires → point scored.
5. UI score updates → camera shake cue on hard hits → state returns to SERVING.

## 5. Open Gaps (from CLAUDE.md + audit)
**High priority / open:**
- GAP-7b Posture-aware pole IK.
- GAP-25 AI jump capability.
- GAP-43 AI body-kinematic anticipation.
- GAP-15 Sweet-spot hit modeling (Community 35 thin cluster).
- GAP-33–39 Awareness grid fully wired into commit / AI pipelines.

**Resolved anchors:** GAP-1, 3, 4, 6, 9, 20, 28, 33, 34, 40, 41, 44, 45, 47.

**Code-harmony issues (Community 28):**
- `_aero_step` duplicate in `game.gd` (should delegate to ball static predictor).
- Fault detection duplication.
- `game.gd` was 3066 lines → decomposed to 965 via Graphify chunk-03.

## 6. Non-Functional Requirements
- **Godot 4.6.2** required (`brew install godot`).
- **GDScript only** (no C# dependencies); Python used for audio synthesis calibration and E2E harness.
- **Autoloads:** `PickleballConstants` (scripts/constants.gd). Input config in `project.godot`.
- **Bundled-physics policy:** Godot damping off; all aero/spin in `ball.gd`.
- **God-file ceiling:** ~500 lines per file per user preference — split proactively (recent example: `posture_editor_ui.gd` split into 5 focused modules).
- **Platform:** Desktop (macOS primary dev target); no mobile input bindings.

## 7. Success Criteria (extractable metrics)
- `BallPhysicsProbe` reports "MATCHES real reference ✓" for all deltas at current aero constants.
- Rally scorer test suite green.
- E2E fast-mode runs at FAST_SCALE timing without frame drops (`EXPECTED_FRAMES` target).
- Posture editor: no UI/input leaks (current known regression — see session log), round-trip `.tres` persistence verified by `test_posture_persistence.gd`.
- AI difficulty tiers yield distinct shot-distribution histograms at EASY/MEDIUM/HARD.

## 8. Documentation Anchors
- **`CLAUDE.md`** — canonical project-level rules and conventions.
- **`docs/paddle-posture-audit.md`** (~1650 lines) — must-read before touching posture, AI, IK, or ball physics.
- **`docs/ARCHITECTURE.md`**, **`docs/ARCHITECTURE_TREE.md`**, **`docs/graphify-howto.md`** — supplementary.
- **`graphify-out/GRAPH_REPORT.md`** — source of truth for this PRD's structure.

## 9. Knowledge Gaps Flagged by Graph
- 591 isolated nodes (≤1 connection) — possible undocumented components or incomplete extraction.
- Ambiguous edges: `cycle_difficulty() → PickleballConstants` (game_debug_ui.gd), `is_in_non_volley_zone() → Practice Ball Zone System` (practice_launcher.gd) — need explicit relation type.
- Thin communities worth investigating: `Skeleton Bone Hierarchy` (Community 34), `Sweet Spot Modeling GAP-15` (Community 35), `_committed_incoming_posture` (Community 36) — all plausibly under-edged rather than truly isolated.
