# Graph Report - .  (2026-04-23)

## Corpus Check
- 131 files · ~292,296 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1704 nodes · 2679 edges · 38 communities detected
- Extraction: 53% EXTRACTED · 47% INFERRED · 0% AMBIGUOUS · INFERRED: 1268 edges (avg confidence: 0.74)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]

## God Nodes (most connected - your core abstractions)
1. `player.gd - Player Controller` - 70 edges
2. `game.gd - Game Orchestrator` - 68 edges
3. `TestRallyScorer` - 52 edges
4. `PostureConstants` - 51 edges
5. `PlayerAIBrain (player_ai_brain.gd — AI prediction, intercept, hitting)` - 48 edges
6. `_scorer()` - 42 edges
7. `_ball()` - 42 edges
8. `_player()` - 42 edges
9. `Posture Editor UI` - 33 edges
10. `PlayerPaddlePosture Class` - 32 edges
11. `_assert_eq()` - 31 edges
12. `BallAudioSynth` - 30 edges
13. `TestShotPhysics` - 27 edges
14. `_assert()` - 25 edges
15. `TransitionPlayer` - 25 edges

## Surprising Connections (you probably didn't know these)
- `run_optimization()` --calls--> `update()`  [INFERRED]
  scripts/synth_optimize.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/posture_editor/pose_trigger.gd
- `run()` --calls--> `open()`  [INFERRED]
  scripts/tests/test_e2e_ultrafast.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `run()` --calls--> `open()`  [INFERRED]
  scripts/tests/test_e2e_fast.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `run_test()` --calls--> `open()`  [INFERRED]
  scripts/tests/test_e2e_playwright.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `run()` --calls--> `close()`  [INFERRED]
  scripts/tests/test_e2e_mcp.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `load_wav()` --calls--> `open()`  [INFERRED]
  scripts/reclip_and_fix.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `save_wav()` --calls--> `open()`  [INFERRED]
  scripts/reclip_and_fix.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `main()` --calls--> `close()`  [INFERRED]
  scripts/reclip_and_fix.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `load_wav()` --calls--> `open()`  [INFERRED]
  scripts/clip_and_compare.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd
- `plot_comparison()` --calls--> `close()`  [INFERRED]
  scripts/clip_and_compare.py → /Users/arjomagno/Documents/github-repos/pickleball-godot/scripts/ui/pause_controller.gd

## Hyperedges (group relationships)
- **Player Module Composition** — player_gd, player_paddle_posture_gd, player_arm_ik_gd, player_leg_ik_gd, player_body_animation_gd, player_body_builder_gd, player_hitting_gd, player_ai_brain_gd, player_debug_visual_gd, pose_controller_gd [EXTRACTED 1.00]
- **Posture Editor Implementation Phases** — phase1_extract_schema, phase2_wire_loader, phase3_full_body_wiring, phase4_editor_ui, phase4b_3d_gizmos [EXTRACTED 1.00]
- **Trajectory to Commit Pipeline** — trajectory_prediction, green_pool_system, commit_state_machine, color_stages, scoring_rubric [EXTRACTED 1.00]
- **Ball Physics Aero Model** — air_drag_physics, magnus_force_physics, spin_damping_physics, velocity_dependent_cor [EXTRACTED 1.00]
- **Base Pose Runtime Architecture** — base_pose_definition_gd, base_pose_library_gd, pose_controller_gd, posture_definition_gd, posture_library_gd [EXTRACTED 1.00]
- **Code Harmony Critical Issues** — game_gd_3066_lines, fault_detection_duplication [EXTRACTED 1.00]
- **Shared Physics for Human and AI** — trajectory_prediction, ball_gd, player_paddle_posture_gd, player_ai_brain_gd [EXTRACTED 1.00]
- **Posture Definitions Architecture** — posture_definition_gd, posture_library_gd, player_paddle_posture_gd, pose_controller_gd [EXTRACTED 1.00]
- **Player Module Composition System** — player_controller, player_ai_brain, player_hitting, player_leg_ik, player_debug_visual [EXTRACTED 1.00]
- **Shared Shot Computation Pipeline (human + AI both call compute_shot_velocity)** — game_shot_system, game_swing_handler, ai_charge_hit_system, player_hitting [EXTRACTED 1.00]
- **AI Prediction & Intercept Pipeline** — ai_visuomotor_latency, ai_bounce_prediction, ai_intercept_solution, ai_posture_height_map, ai_charge_hit_system, ai_state_machine [EXTRACTED 1.00]
- **Posture Editor Sub-Module System** — posture_editor_ui, posture_editor_state_module, posture_editor_preview_module, posture_editor_transport_module, posture_editor_gizmos_module, posture_editor_tabs [EXTRACTED 1.00]
- **Debug Visualization Pipeline (trajectory → posture commit → intercept pool → AI indicators)** — player_debug_visual, debug_trajectory_arc, debug_intercept_pool, ai_trajectory_viz, debug_step_markers [INFERRED 0.90]
- **Swing Animation Pipeline (charge → follow-through → posture reset)** — hitting_charge_visual, hitting_follow_through, hitting_ft_families, hitting_paddle_velocity [EXTRACTED 1.00]
- **Ball Physics Subsystem** —  [EXTRACTED 1.00]
- **Posture Data Subsystem** —  [EXTRACTED 1.00]
- **Posture Commit Pipeline** —  [INFERRED 0.88]
- **Serve Subsystem** —  [EXTRACTED 0.95]
- **Rally Rules Subsystem** —  [EXTRACTED 1.00]
- **Shot System Subsystem** —  [EXTRACTED 1.00]
- **Debug & Calibration Subsystem** —  [EXTRACTED 1.00]
- **Player Animation Pipeline** —  [EXTRACTED 1.00]
- **Audio Tuning Subsystem** —  [EXTRACTED 1.00]
- **Input Delegation Flow** —  [EXTRACTED 1.00]
- **Practice & Training Subsystem** —  [EXTRACTED 1.00]
- **Court & Rules Subsystem** —  [EXTRACTED 1.00]
- **IK System** —  [EXTRACTED 1.00]
- **FX System** —  [EXTRACTED 1.00]
- **Camera System** —  [EXTRACTED 1.00]
- **Gizmo System** —  [EXTRACTED 1.00]
- **PickleballConstants Consumers** —  [EXTRACTED 1.00]
- **Posture Editor Tab System** —  [EXTRACTED 1.00]
- **Gizmo System** —  [EXTRACTED 1.00]
- **Preview Subsystem** —  [EXTRACTED 1.00]
- **Rally & Physics Test Group** —  [EXTRACTED 1.00]
- **Posture Editor Test Group** —  [EXTRACTED 1.00]
- **State ↔ Tab ↔ Gizmo Data Flow** —  [INFERRED 0.85]
- **Test Infrastructure** —  [EXTRACTED 1.00]
- **UI System** —  [EXTRACTED 1.00]
- **Fake/Mock Test Doubles** —  [EXTRACTED 1.00]
- **TimeScale Consumer Group** —  [EXTRACTED 1.00]
- **Posture Data Pipeline** —  [EXTRACTED 0.90]

## Communities

### Community 0 - "Community 0"
Cohesion: 0.02
Nodes (157): AI Bounce Prediction (_predict_first_bounce_position, _predict_ai_contact_candidates), AI Charge-Hit System (_try_ai_hit_ball — 3-phase: detect/charge/swing), AI Intercept Solution Solver (_get_ai_intercept_solution — cost scoring across postures), AI Posture-to-Height Mapping (_get_posture_for_height — LOW/MID_LOW/NORMAL/OVERHEAD tiers), AI State Machine (INTERCEPT_POSITION / CHARGING / HIT_BALL), AI Trajectory Visualization (ImmediateMesh arc after hit), Two-Bounce Rule Enforcement (volley gating, kitchen rule), Visuomotor Latency Ring Buffer (GAP-47 — difficulty-tiered reaction delay) (+149 more)

### Community 1 - "Community 1"
Cohesion: 0.02
Nodes (122): AIState Enum, BasePoseState Enum (22 states), PaddlePosture Enum (20 postures), PoseIntent Enum, ShotContactState Enum, ShotType Enum (NORMAL/FAST/DROP/LOB), AI Reaction Latency (GAP-47), BasePoseDefinition Resource (+114 more)

### Community 2 - "Community 2"
Cohesion: 0.02
Nodes (86): Quadratic Air Drag Physics, Autoload Singletons, Architecture Documentation, ball.gd - Ball Physics, ball_physics_probe.gd - Calibration Tool, BallTrail, BounceDecal, CameraRig (+78 more)

### Community 3 - "Community 3"
Cohesion: 0.03
Nodes (92): AI Brain (player_ai_brain.gd), BasePoseState Enum (22 states), PaddlePosture Enum (22 states), Player Controller (player.gd), Posture Editor Module, Posture Resource Pattern, Posture System, Testing Infrastructure (+84 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (68): Net Clearance Iterative Solver, Practice Ball Zone System, Shot Type System, Spin Injection System, Ball (ball.gd), PickleballConstants, get_court_bounds(), DropTest (+60 more)

### Community 5 - "Community 5"
Cohesion: 0.03
Nodes (66): Audio Synth Pools (thock/volley/smash/rim/frame — pre-generated, rotated per hit), Audio Live-Tuning Knobs (paddle_attack_tune, metallic_tune, etc. — 30+ sliders), BallAudioSynth, ObjectPool, Audio, Class, Constant, Constant (+58 more)

### Community 6 - "Community 6"
Cohesion: 0.04
Nodes (66): classify_hit(), detect_hits(), load_wav(), main(), plot_comparison(), Classify a hit as 'paddle' or 'bounce' based on spectral characteristics.     Pa, Compute spectral similarity between two sounds using cosine similarity     of th, Plot side-by-side waveform + overlaid spectrum comparison. (+58 more)

### Community 7 - "Community 7"
Cohesion: 0.04
Nodes (53): ArmsTab, ArmsTab, field_changed, _ready(), set_definition(), BasePoseDefinition, ChargeTab, ChargeTab (+45 more)

### Community 8 - "Community 8"
Cohesion: 0.04
Nodes (66): Quadratic Air Drag + Magnus Force, PlayerAwarenessGrid.get_posture_zone_scores(), PlayerAwarenessGrid.get_ttc_at_world_point(), PlayerAwarenessGrid.set_trajectory_points(), PlayerAwarenessGrid.ZoneID, Ball aero constants block, Ball Physics (ball.gd), Ball (+58 more)

### Community 9 - "Community 9"
Cohesion: 0.04
Nodes (48): force_posture_update(), is_frozen(), _build_charge_preview_def(), _build_follow_through_preview_defs(), build_preview_posture_for_editor(), _capture_live_restore_posture(), CHARGE_BACKHAND_POSTURE_ID, CHARGE_FOREHAND_POSTURE_ID (+40 more)

### Community 10 - "Community 10"
Cohesion: 0.04
Nodes (57): BasePoseLibrary, BasePoseLibrary.instance() [singleton], BasePoseLibrary, BasePoseLibrary, BasePoseLibrary, _ensure_dir(), _filename_for(), OUTPUT_DIR (+49 more)

### Community 11 - "Community 11"
Cohesion: 0.03
Nodes (69): AI Latency Ring Buffer - Visuomotor delay simulation, BasePoseState Enum - 22 body base pose states, compute_shot_velocity() - Unified shot velocity function, Game Subsystems - GameServe/GameTrajectory/GameShots, physics.gd - Pure math utilities, player_awareness_grid.gd - Volumetric ball proximity detector, Player Enums - PaddlePosture/BasePoseState/PoseIntent, PoseIntent Enum - NEUTRAL/DINK/DROP_RESET etc (+61 more)

### Community 12 - "Community 12"
Cohesion: 0.06
Nodes (54): PauseController, PauseMenu, _add_button(), _apply_bold(), _build(), _button_style(), _panel_stylebox(), _ready() (+46 more)

### Community 13 - "Community 13"
Cohesion: 0.08
Nodes (54): _apply_body_fields(), BasePoseDefinition, blend_onto_stroke(), _copy_fields_to(), duplicate_pose(), _PostureDefinition, to_preview_posture(), compose_preview_posture() (+46 more)

### Community 14 - "Community 14"
Cohesion: 0.16
Nodes (52): check_out_of_bounds(), _assert_eq(), _assert_false(), _ball(), _FakeBall, _FakePlayer, _player(), _RallyScorer (+44 more)

### Community 15 - "Community 15"
Cohesion: 0.07
Nodes (43): _apply_blended_state(), _calculate_target_bones(), _capture_current_bones(), _get_basis_from_rotation(), pose_released, pose_triggered, PoseTrigger, refresh_from_definition() (+35 more)

### Community 16 - "Community 16"
Cohesion: 0.04
Nodes (51): BLUE_DIST_FALLBACK, BLUE_HOLD_DURATION, DEBUG_POSTURE_NAMES, GHOST_CONTACT_MAX_DIST, GHOST_FORWARD_PLANE, GHOST_LERP_SPEED, GHOST_MIN_DISTANCE, GHOST_STRETCH_HEIGHT_MAX (+43 more)

### Community 17 - "Community 17"
Cohesion: 0.05
Nodes (29): PlayerAwarenessGrid.get_approach_info(), PostureCommitSelector.build_green_set(), PostureCommitSelector.find_best_green_posture(), _apply_full_body_posture(), _commit_selector, _find_closest_ghost_to_point(), grade_flashed signal, _green_lit_postures (+21 more)

### Community 18 - "Community 18"
Cohesion: 0.06
Nodes (26): GizmoHandle, _ready(), set_hovered(), set_selected(), _setup_visuals(), _update_visual_state(), _create_axis_handles(), _create_main_handle() (+18 more)

### Community 19 - "Community 19"
Cohesion: 0.06
Nodes (28): Hud, AI_DIFFICULTY_COLORS, _apply_font(), _build_fonts(), _build_labels(), _build_panels(), COL_AMBER, COL_BLUE (+20 more)

### Community 20 - "Community 20"
Cohesion: 0.11
Nodes (21): BounceDecal, DURATION, HEIGHT, is_active(), RADIUS, _add_burst(), _add_decal(), BounceDecalScript (+13 more)

### Community 21 - "Community 21"
Cohesion: 0.12
Nodes (22): E2EFastMode, _ready(), E2ETestRunner, EXPECTED_FRAMES, FAST_SCALE, _process(), quit_fail(), quit_pass() (+14 more)

### Community 22 - "Community 22"
Cohesion: 0.1
Nodes (15): FakeBall, FakeBall, FakeBallNode, FakeBallNode, FakePlayer, FakePlayer, ShotPhysics, Class (+7 more)

### Community 23 - "Community 23"
Cohesion: 0.14
Nodes (17): accuracy_pct(), error_metric(), exp_env(), load_mono(), make_objective(), Piecewise linear attack + exponential decay envelope., Pure Python port of GDScript _create_paddle_sound synthesis loop.      body_freq, Run synthesizer with given params and return spectral features. (+9 more)

### Community 24 - "Community 24"
Cohesion: 0.19
Nodes (11): HIT_SHAKE_BASE, HIT_SHAKE_SCALE, HitFeedback, HITSTOP_DURATION, HITSTOP_SCALE, HITSTOP_THRESHOLD, _on_bounce(), _on_hit() (+3 more)

### Community 25 - "Community 25"
Cohesion: 0.18
Nodes (10): BallTrail, COLOR_HEAD, COLOR_TAIL, MAX_POINTS, MIN_SPEED, _physics_process(), _rebuild_mesh(), _settings_allows_trail() (+2 more)

### Community 26 - "Community 26"
Cohesion: 0.17
Nodes (9): CameraShake, DECAY, _get_settings_node(), MAX_OFFSET_H, MAX_OFFSET_V, MAX_ROLL, NOISE_SPEED, TRAUMA_POWER (+1 more)

### Community 27 - "Community 27"
Cohesion: 0.18
Nodes (9): _ema_step(), _PADDLE_VEL_SMOOTH_HALFLIFE, _PADDLE_VEL_TRANSFER, _PhysicsUtils, test_halflife_reasonable_range(), test_transfer_scalar_bounds(), test_velocity_converges_to_target(), test_velocity_tracks_constant_motion() (+1 more)

### Community 28 - "Community 28"
Cohesion: 0.17
Nodes (13): Ball Physics System (ball.gd), Child Subsystem Pattern, Game Orchestrator (game.gd), Shot Physics (shot_physics.gd), Signal-Based Decoupling Pattern, Static Predictor Methods Pattern, _aero_step Duplicate in game.gd, game.gd Decomposition Proposal (+5 more)

### Community 29 - "Community 29"
Cohesion: 0.18
Nodes (12): AI Prediction System - bounce/contact/intercept candidates, ball_audio_synth.gd - Procedural audio synthesis, ball.gd - RigidBody3D with custom aero/spin physics, ball_physics_probe.gd - Diagnostic calibration tool, Ball Static Predictors - predict_aero_step/predict_bounce_spin, GameState Enum - WAITING/SERVING/PLAYING/POINT_SCORED, Aero Physics - Drag/Magnus/spin constants, Ball Bounce Detection - Manual floor bounce signal (+4 more)

### Community 30 - "Community 30"
Cohesion: 0.29
Nodes (5): Ghost Color Stages (PINK/PURPLE/BLUE), Reaction Timing Ring (TTC-driven), apply(), stage_colors(), update_from_stage()

### Community 31 - "Community 31"
Cohesion: 0.29
Nodes (7): Posture Editor Usability Confusion Issues, Posture Editor Design Principles, Explicit Editor Modes (Select/PreviewPose/PreviewSwing), Usability Improvement Phases Plan, Family-Aware Transition Preview Fix, Viewport-First Editing Principle, Workspace Model UX Redesign

### Community 32 - "Community 32"
Cohesion: 0.53
Nodes (5): PostureColors.apply(), PostureColors.green_fading(), PostureColors, PostureColors.stage_colors() / compute_stage(), PostureColors

### Community 34 - "Community 34"
Cohesion: 0.67
Nodes (1): Skeleton Bone Hierarchy

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (1): Sweet Spot Modeling (GAP-15)

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (1): _committed_incoming_posture

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (2): Phase 4b: 3D Gizmos, Posture Editor Phase 4b Notes

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (2): constants.gd - PickleballConstants autoload, project.godot - Autoloads and input config

## Ambiguous Edges - Review These
- `cycle_difficulty()` → `PickleballConstants`  [AMBIGUOUS]
  scripts/game_debug_ui.gd · relation: references
- `is_in_non_volley_zone()` → `Practice Ball Zone System`  [AMBIGUOUS]
  scripts/practice_launcher.gd · relation: uses

## Knowledge Gaps
- **591 isolated node(s):** `PostureDefinitionScript`, `PostureLibraryScript`, `OUTPUT_DIR`, `High-pass Butterworth filter to remove handling/wind noise.`, `Find the exact onset sample using envelope threshold.` (+586 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 34`** (3 nodes): `Skeleton Bone Hierarchy`, `build()`, `_create_skeleton()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (2 nodes): `Sweet Spot Modeling (GAP-15)`, `compute_sweet_spot_speed()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (2 nodes): `_committed_incoming_posture`, `force_paddle_head_to_ghost()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (2 nodes): `Phase 4b: 3D Gizmos`, `Posture Editor Phase 4b Notes`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (2 nodes): `constants.gd - PickleballConstants autoload`, `project.godot - Autoloads and input config`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.