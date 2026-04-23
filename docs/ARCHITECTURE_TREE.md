# Pickleball Godot - Full Architecture Tree

```
pickleball-godot/
│
├── [project.godot] ──────────────────────────────────────────────────────────
│   ├── config_version=5
│   ├── [autoload] ─────────────────────────────────────────────────────────
│   │   ├── PickleballConstants  →  scripts/constants.gd
│   │   ├── Settings             →  scripts/ui/settings.gd
│   │   ├── TimeScale            →  scripts/time/time_scale_manager.gd
│   │   ├── FXPool              →  scripts/fx/fx_pool.gd
│   │   └── PauseController      →  scripts/ui/pause_controller.gd
│   │
│   ├── [input] ────────────────────────────────────────────────────────────
│   │   ├── ui_accept           →  Space (serve charge)
│   │   ├── move_up             →  W / ArrowUp
│   │   ├── move_down           →  S / ArrowDown
│   │   ├── move_left           →  A / ArrowLeft
│   │   └── move_right          →  D / ArrowRight
│   │
│   └── [display / animation / application]
│
├── [scenes/] ──────────────────────────────────────────────────────────────
│   ├── game.tscn               # Main scene (root)
│   ├── ball.tscn
│   ├── court.tscn
│   ├── player.tscn
│   ├── paddle.tscn
│   ├── left_arm.tscn
│   ├── right_arm.tscn
│   ├── left_leg.tscn
│   └── right_leg.tscn
│
└── [scripts/] ────────────────────────────────────────────────────────────
    │
    ├── constants.gd  (AUTOLOAD: PickleballConstants) ───────────────────────
    │   ├── Player speed, AI speed, paddle force
    │   ├── Court dimensions (LENGTH, WIDTH, NET_HEIGHT, LINE_WIDTH)
    │   ├── Non-volley zone (NVZ) boundary
    │   ├── Ball constants (MASS, RADIUS, MAX_SPEED, SERVE_SPEED)
    │   ├── Physics (FLOOR_Y, GRAVITY_SCALE, BOUNCE_COR)
    │   ├── Serve constraints (MIN/MAX_SERVE_SPEED, SERVE_AIM_STEP/MAX)
    │   ├── Arc intent (ARC_INTENT_STEP/MIN/MAX)
    │   ├── Hit reach distance
    │   ├── Overhead trigger heights
    │   └── Jump velocity, jump gravity
    │
    ├── game.gd  ───────────────────────────────────────────────────────────
    │   ## Thin orchestrator — owns game state + scoring
    │   ## Delegates subsystem work to child nodes
    │   │
    │   ├── [ENUM] GameState ─────────────────────────────────────────────
    │   │   ├── WAITING          # Ball held, waiting for serve
    │   │   ├── SERVING          # Serve in progress
    │   │   ├── PLAYING          # Rally active
    │   │   └── POINT_SCORED    # Transition state
    │   │
    │   ├── [STATE VARIABLES] ─────────────────────────────────────────────
    │   │   ├── score_left: int
    │   │   ├── score_right: int
    │   │   ├── serving_team: int          # 0=blue, 1=red
    │   │   ├── game_state: GameState
    │   │   ├── serve_charge_time: float
    │   │   ├── serve_is_charging: bool
    │   │   ├── serve_aim_offset_x: float
    │   │   ├── trajectory_arc_offset: float
    │   │   ├── ball_has_bounced: bool
    │   │   ├── ai_difficulty: int         # 0=EASY, 1=MEDIUM, 2=HARD
    │   │   └── debug_visuals_visible: bool
    │   │
    │   ├── [CHILD NODE REFERENCES] ───────────────────────────────────────
    │   │   ├── player_left: CharacterBody3D
    │   │   ├── player_right: CharacterBody3D
    │   │   ├── ball: RigidBody3D
    │   │   ├── rally_scorer: RallyScorer
    │   │   ├── shot_physics: ShotPhysics
    │   │   ├── input_handler: InputHandler
    │   │   ├── scoreboard_ui: ScoreboardUI
    │   │   ├── practice_launcher: PracticeLauncher
    │   │   ├── ball_physics_probe: BallPhysicsProbe
    │   │   ├── swing_e2e_probe: SwingE2EProbe
    │   │   ├── camera_rig: CameraRig
    │   │   ├── hud: CanvasLayer
    │   │   ├── posture_editor_ui: PostureEditorUI
    │   │   ├── reaction_button: ReactionHitButton
    │   │   └── _transport_bar: Control
    │   │
    │   ├── [CHILD SUBSYSTEMS] ────────────────────────────────────────────
    │   │   ├── game_serve: GameServe         # Serve charge/aim/execute
    │   │   ├── game_trajectory: GameTrajectory  # Trajectory visualization
    │   │   ├── game_shots: GameShots         # Shot classification, out
    │   │   ├── game_drop_test: GameDropTest   # Bounce calibration
    │   │   ├── game_debug_ui: GameDebugUI    # Debug overlay
    │   │   └── game_sound_tune: GameSoundTune  # Audio tuning
    │   │
    │   ├── [LIFECYCLE] ──────────────────────────────────────────────────
    │   │   ├── _ready()                    → _setup_environment() + _setup_game()
    │   │   ├── _physics_process(delta)     → delegates to subsystems
    │   │   ├── _unhandled_input(event)     → camera_rig.handle_input()
    │   │   └── _exit_tree()                → frees orphaned helpers
    │   │
    │   ├── [SETUP] ──────────────────────────────────────────────────────
    │   │   ├── _setup_environment()        # Sky, sun, fill light
    │   │   ├── _setup_game()               # Creates all nodes
    │   │   ├── _setup_camera_rig()         # CameraRigScript.new()
    │   │   ├── _setup_hit_feedback()       # HitFeedback, BallTrail
    │   │   ├── _create_ui()               # HUD, reaction button, editor
    │   │   ├── _setup_subsystems()         # All game_* subsystems
    │   │   └── _wire_settings()            # Connects to Settings autoload
    │   │
    │   ├── [GAME STATE] ────────────────────────────────────────────────
    │   │   ├── _set_game_state(new_state)
    │   │   ├── _check_rally()
    │   │   ├── _format_scoreboard() → String
    │   │   └── _format_serve_call() → String
    │   │
    │   ├── [SCORING / RESET] ───────────────────────────────────────────
    │   │   ├── _on_rally_ended(winner, reason, detail)
    │   │   ├── _on_point_scored(winning_team)
    │   │   ├── _reset_ball()
    │   │   ├── _reset_match()
    │   │   ├── _reset_player_positions()
    │   │   └── _update_held_ball_position()
    │   │
    │   ├── [SWING / SERVE] ─────────────────────────────────────────────
    │   │   ├── _on_player_swing_press()
    │   │   ├── _on_player_swing_release(charge_ratio)
    │   │   ├── _perform_serve(charge_ratio)   → game_serve.perform_serve()
    │   │   ├── _perform_player_swing(charge_ratio)
    │   │   │   ├── compute_shot_velocity()
    │   │   │   ├── compute_sweet_spot_speed()
    │   │   │   ├── compute_shot_spin()
    │   │   │   └── compute_sweet_spot_spin()
    │   │   ├── _on_serve_launched(_team)
    │   │   └── _update_waiting_ui()
    │   │
    │   ├── [REACTION BUTTON / SLOW-MO] ─────────────────────────────────
    │   │   ├── _on_player_stage_changed(stage, posture, commit_dist, ball2ghost, ttc)
    │   │   ├── _on_player_grade_flashed(grade)
    │   │   ├── _on_reaction_auto_fire()
    │   │   ├── _enter_slow_mo()
    │   │   └── _exit_slow_mo()
    │   │
    │   ├── [BALL SIGNALS] ───────────────────────────────────────────────
    │   │   ├── _on_any_paddle_hit(player_num)
    │   │   ├── _on_ball_bounced(bounce_pos) → spawn_bounce_spot()
    │   │   └── _spawn_bounce_spot(spot_pos)
    │   │
    │   ├── [POSTURE EDITOR] ────────────────────────────────────────────
    │   │   ├── _toggle_posture_editor()
    │   │   ├── _on_editor_opened()
    │   │   ├── _on_editor_closed()
    │   │   ├── _expand_window_for_editor()
    │   │   └── _restore_window_after_editor()
    │   │
    │   ├── [DEBUG HOTKEYS] (delegated to subsystems) ───────────────────
    │   │   ├── _cycle_debug_visuals()       → game_debug_ui.cycle_debug_visuals()
    │   │   ├── _toggle_intent_indicators()  → game_debug_ui.toggle_intent_indicators()
    │   │   ├── _cycle_difficulty()          → game_debug_ui.cycle_difficulty()
    │   │   ├── _start_drop_test()           → game_drop_test.start()
    │   │   ├── _refresh_sound_tune_panel() → game_sound_tune._refresh_sound_tune_panel()
    │   │   └── _print_sound_tunings()      → ball.get_sound_tunings()
    │   │
    │   └── [PUBLIC API] ───────────────────────────────────────────────
    │       ├── _is_practice() → bool
    │       ├── is_awaiting_return() → bool
    │       ├── get_serve_charge_time() → float
    │       ├── get_ai_difficulty() → int
    │       ├── get_serve_aim_offset() → float
    │       ├── get_trajectory_arc_offset() → float
    │       ├── run_swing_e2e_test() → String
    │       ├── compute_shot_velocity(ball_pos, charge, player_num, shot_type, ai_difficulty) → Vector3
    │       ├── compute_shot_spin(shot_type, vel, charge, player_num, posture) → Vector3
    │       ├── compute_sweet_spot_spin(ball_pos, paddle_center, shot_vel) → Vector3
    │       ├── compute_sweet_spot_speed(ball_pos, paddle_center, shot_vel) → float
    │       └── _simulate_shot_trajectory(...) → Dictionary
    │
    ├── ball.gd  ───────────────────────────────────────────────────────────
    │   ## RigidBody3D with custom aero + spin physics
    │   ##
    │   ## GAP references: GAP-15, GAP-21, GAP-41, GAP-55, GAP-59, GAP-60, GAP-61
    │   │
    │   ├── [CONSTANTS] ─────────────────────────────────────────────────
    │   │   ├── BALL_MASS = 0.024  (kg)
    │   │   ├── BALL_RADIUS = 0.0375  (m, USAPA 73-75.5mm spec)
    │   │   ├── GRAVITY_SCALE = 1.0
    │   │   ├── MAX_SPEED = 20.0  (m/s)
    │   │   ├── SERVE_SPEED = 8.0  (m/s)
    │   │   ├── FLOOR_Y = 0.075
    │   │   ├── AIR_DENSITY = 1.225  (kg/m³)
    │   │   ├── DRAG_COEFFICIENT = 0.47
    │   │   ├── MAGNUS_COEFFICIENT = 0.0003
    │   │   ├── SPIN_DAMPING_HALFLIFE = 150.0  (s)
    │   │   ├── SPIN_BOUNCE_TRANSFER = 0.25
    │   │   ├── SPIN_BOUNCE_DECAY = 0.70
    │   │   ├── AERO_EFFECT_SCALE = 0.79  (master tuner)
    │   │   ├── BOUNCE_COR = 0.640  (calibrated to USAPA 30-34" drop)
    │   │   └── SHOW_SPIN_DEBUG = true
    │   │
    │   ├── [STATE] ─────────────────────────────────────────────────────
    │   │   ├── is_in_play: bool
    │   │   ├── last_hit_by: int           # player number
    │   │   ├── serve_team: int
    │   │   ├── bounce_count: int
    │   │   ├── ball_bounced_since_last_hit: bool
    │   │   ├── bounces_since_last_hit: int
    │   │   ├── was_volley: bool
    │   │   ├── serving_side_bounced: bool
    │   │   ├── receiving_side_bounced: bool
    │   │   └── both_bounces_complete: bool
    │   │
    │   ├── [SIGNALS] ───────────────────────────────────────────────────
    │   │   ├── hit_by_paddle(player_num: int)
    │   │   ├── bounced(position: Vector3)
    │   │   └── hit_player_body(player_num: int)   # fault on body hit
    │   │
    │   ├── [AERO PHYSICS] (_physics_process) ────────────────────────────
    │   │   ├── Quadratic drag: F = -0.5 * ρ * Cd * A * |v| * v
    │   │   │   └── gated by AERO_EFFECT_SCALE
    │   │   ├── Magnus curl: F = k * (ω × v)
    │   │   │   └── scales with AERO_EFFECT_SCALE
    │   │   ├── Spin damping: ω *= exp(-dt * 0.693 / (HL * AERO_SCALE))
    │   │   └── Speed clamp: MAX_SPEED
    │   │
    │   ├── [BOUNCE PHYSICS] ────────────────────────────────────────────
    │   │   ├── Velocity-dependent COR: cor_for_impact_speed(v)
    │   │   │   └── lerp(0.78, 0.56, clamp((v-3)/15, 0, 1))
    │   │   ├── Spin-tangential coupling:
    │   │   │   └── SPIN_BOUNCE_TRANSFER fraction absorbed per bounce
    │   │   └── Spin decay: ω *= lerpf(1, SPIN_BOUNCE_DECAY, AERO_SCALE)
    │   │
    │   ├── [STATIC PREDICTORS] ─────────────────────────────────────────
    │   │   ## Mirror _physics_process for AI/debug — no instance needed
    │   │   │
    │   │   ├── static predict_aero_step(pos, vel, omega, gravity, dt) → Array[pos, vel, omega]
    │   │   │   └── Includes: gravity, drag, Magnus, spin damping, speed clamp
    │   │   └── static predict_bounce_spin(vel, omega) → Array[vel, omega]
    │   │       └── Includes: spin-tangential transfer, COR, spin decay
    │   │
    │   ├── [SPIN VISUALIZER] ───────────────────────────────────────────
    │   │   ├── _setup_spin_debug_visuals()
    │   │   │   ├── _spin_axis_node: CylinderMesh (aligned to ω)
    │   │   │   │   └── Color: green=topspin, red=backspin, cyan=sidespin
    │   │   │   └── _equator_marker, _equator_marker_2: SphereMesh
    │   │   └── _update_spin_visualizer()  → called each frame
    │   │
    │   ├── [PUBLIC API] ────────────────────────────────────────────────
    │   │   ├── serve(team, direction)           # Launch serve
    │   │   ├── reset()                         # Reset to initial state
    │   │   ├── hit_by_player(player_num)       # Called on paddle contact
    │   │   ├── get_last_hit_by() → int
    │   │   ├── get_bounce_count() → int
    │   │   ├── record_bounce_side(bounce_z)    # Track two-bounce rule
    │   │   ├── can_volley() → bool            # both_bounces_complete
    │   │   ├── reset_rally_state()
    │   │   └── get_sound_tunings() → Dictionary
    │   │
    │   └── [SIGNAL HANDLERS] ───────────────────────────────────────────
    │       ├── _on_paddle_hit(player_num)        → audio_synth.on_paddle_hit()
    │       ├── _on_floor_bounce(position)       → audio_synth.on_floor_bounce()
    │       └── _on_body_entered(body)           → emit hit_player_body if CharacterBody3D
    │
    ├── ball_audio_synth.gd  ───────────────────────────────────────────────
    │   ## Procedural audio synthesis for ball sounds
    │   │   ## No audio files — pure synthesis via Oscillator + envelope
    │   ├── _on_paddle_hit(speed)
    │   ├── _on_floor_bounce(speed)
    │   ├── _on_body_entered(body, pos_y, velocity)
    │   └── update_cooldown(delta)
    │
    ├── ball_physics_probe.gd ───────────────────────────────────────────────
    │   ## Diagnostic tool — measures actual ball deceleration vs expected
    │   ├── setup(ball)
    │   ├── start()
    │   ├── tick()
    │   ├── is_active() → bool
    │   └── test_complete: signal
    │
    ├── player.gd  ────────────────────────────────────────────────────────
    │   ## CharacterBody3D — full player paddle with movement + IK animation
    │   ##
    │   ## Modules as child nodes: posture, hitting, pose_controller, arm_ik, leg_ik
    │   │
    │   ├── [ENUMS] ──────────────────────────────────────────────────────
    │   │   ├── PaddlePosture (22 states)
    │   │   │   ├── FOREHAND, FORWARD, BACKHAND
    │   │   │   ├── MEDIUM_OVERHEAD, HIGH_OVERHEAD
    │   │   │   ├── LOW_FOREHAND, LOW_FORWARD, LOW_BACKHAND
    │   │   │   ├── CHARGE_FOREHAND, CHARGE_BACKHAND
    │   │   │   ├── WIDE_FOREHAND, WIDE_BACKHAND
    │   │   │   ├── VOLLEY_READY
    │   │   │   ├── MID_LOW_FOREHAND, MID_LOW_BACKHAND, MID_LOW_FORWARD
    │   │   │   ├── MID_LOW_WIDE_FOREHAND, MID_LOW_WIDE_BACKHAND
    │   │   │   ├── LOW_WIDE_FOREHAND, LOW_WIDE_BACKHAND
    │   │   │   └── READY
    │   │   │
    │   │   ├── BasePoseState (22 states)
    │   │   │   ├── ATHLETIC_READY, SPLIT_STEP, RECOVERY_READY
    │   │   │   ├── KITCHEN_NEUTRAL, DINK_BASE, DROP_RESET_BASE
    │   │   │   ├── PUNCH_VOLLEY_READY, DINK_VOLLEY_READY, DEEP_VOLLEY_READY
    │   │   │   ├── GROUNDSTROKE_BASE, LOB_DEFENSE_BASE
    │   │   │   ├── FOREHAND_LUNGE, BACKHAND_LUNGE, LOW_SCOOP_LUNGE
    │   │   │   ├── OVERHEAD_PREP, JUMP_TAKEOFF, AIR_SMASH, LANDING_RECOVERY
    │   │   │   └── LATERAL_SHUFFLE, CROSSOVER_RUN, BACKPEDAL, DECEL_PLANT
    │   │   │
    │   │   ├── PoseIntent ───────────────────────────────────────────────
    │   │   │   ├── NEUTRAL, DINK, DROP_RESET, PUNCH_VOLLEY
    │   │   │   ├── DINK_VOLLEY, DEEP_VOLLEY, GROUNDSTROKE
    │   │   │   └── LOB_DEFENSE, OVERHEAD_SMASH
    │   │   │
    │   │   ├── ShotContactState
    │   │   │   └── CLEAN, STRETCHED, POPUP
    │   │   │
    │   │   └── AIState
    │   │       └── INTERCEPT_POSITION, CHARGING, HIT_BALL
    │   │
    │   ├── [STATE] ─────────────────────────────────────────────────────
    │   │   ├── player_num: int              # 0=blue/human, 1=red/AI
    │   │   ├── is_ai: bool
    │   │   ├── bounds (min_x, max_x, min_z, max_z)
    │   │   ├── ball_ref: RigidBody3D
    │   │   ├── paddle_node: Node3D
    │   │   ├── skeleton: Skeleton3D
    │   │   ├── current_velocity: Vector3
    │   │   ├── paddle_posture: int          # getter/setter → posture.paddle_posture
    │   │   ├── base_pose_state: int         # getter/setter → pose_controller.base_pose_state
    │   │   ├── pose_intent: int             # getter/setter → pose_controller.pose_intent
    │   │   └── paddle_posture_lerp: Vector3
    │   │
    │   ├── [CHILD NODE REFS] ───────────────────────────────────────────
    │   │   ├── posture: PlayerPaddlePosture
    │   │   ├── hitting: PlayerHitting
    │   │   ├── pose_controller: PoseController
    │   │   ├── body_animation: PlayerBodyAnimation
    │   │   ├── arm_ik: PlayerArmIK
    │   │   ├── leg_ik: PlayerLegIK
    │   │   ├── ai_brain: PlayerAIBrain
    │   │   ├── awareness_grid: PlayerAwarenessGrid
    │   │   ├── paddle_hitbox: Area3D
    │   │   └── hit_ball: Signal  # (body, direction)
    │   │
    │   ├── [LIFECYCLE] ─────────────────────────────────────────────────
    │   │   ├── _ready()           → setup() called by game.gd
    │   │   ├── _physics_process() → _update_movement() + arm_ik.update()
    │   │   └── _get_configuration_warnings() → String[]
    │   │
    │   ├── [SETUP] ──────────────────────────────────────────────────────
    │   │   ├── setup(player_num, bounds, color, reset_pos, is_ai)
    │   │   ├── _build_body()              # Creates collision capsule + skeleton
    │   │   ├── _setup_paddle()           # Paddle mesh + hitbox area
    │   │   ├── _create_limb(scene_path) → Node3D
    │   │   └── _build_ik_chains()       # arm_ik, leg_ik setup
    │   │
    │   ├── [MOVEMENT] ─────────────────────────────────────────────────
    │   │   ├── _update_movement(dt)
    │   │   │   ├── Human: WASD input → desired_velocity
    │   │   │   └── AI: ai_brain.get_ai_input() → desired_velocity
    │   │   ├── _apply_movement_velocity(dt)
    │   │   ├── _clamp_to_bounds(pos) → Vector3
    │   │   └── set_ai_movement_enabled(enabled)
    │   │
    │   ├── [SWING / CHARGE] ────────────────────────────────────────────
    │   │   ├── start_serve_charge()
    │   │   ├── set_serve_charge_visual(ratio)
    │   │   ├── animate_serve_release(charge_ratio)
    │   │   ├── notify_ball_hit()           → posture.notify_ball_hit()
    │   │   └── get_paddle_position() → Vector3  → posture.get_paddle_position()
    │   │
    │   ├── [POSTURE] ─────────────────────────────────────────────────
    │   │   ├── get_posture_offset_for(posture) → Vector3
    │   │   ├── _get_posture_rotation_offset_for(posture, swing_sign, fwd_sign) → Vector3
    │   │   ├── update_awareness_grid()
    │   │   └── notify_ball_bounced(pos) → awareness_grid.on_ball_bounced()
    │   │
    │   ├── [PUBLIC HELPERS] ───────────────────────────────────────────
    │   │   ├── _get_ball_ref() → RigidBody3D
    │   │   └── get_player_num() → int
    │   │
    │   └── [AI CALLBACKS] ─────────────────────────────────────────────
    │       └── _on_hitbox_body_entered(body, _paddle)
    │
    ├── player_ai_brain.gd  ────────────────────────────────────────────────
    │   ## AI prediction, intercept, and hitting logic
    │   ## Extracted from player.gd (formerly monolithic)
    │   ##
    │   ## GAP-47: visuomotor latency ring buffer (133-300ms based on difficulty)
    │   │
    │   ├── [AI DIFFICULTY] ─────────────────────────────────────────────
    │   │   ├── EASY:   18 frame latency, 0.70 speed scale, wide error tolerance
    │   │   ├── MEDIUM: 12 frame latency, 0.85 speed scale
    │   │   └── HARD:   8 frame latency, 1.00 speed scale, tight error tolerance
    │   │
    │   ├── [STATE] ─────────────────────────────────────────────────────
    │   │   ├── ai_state: AIState          # INTERCEPT / CHARGING / HIT_BALL
    │   │   ├── ai_difficulty: int
    │   │   ├── ai_target_position: Vector3
    │   │   ├── ai_predicted_bounce_position: Vector3
    │   │   ├── ai_predicted_contact_position: Vector3
    │   │   ├── ai_desired_posture: int
    │   │   ├── ai_is_charging: bool
    │   │   ├── ai_charge_time: float
    │   │   ├── ai_hit_cooldown: float
    │   │   └── _ball_history: Array       # Ring buffer for latency simulation
    │   │
    │   ├── [MAIN ENTRY] ────────────────────────────────────────────────
    │   │   └── get_ai_input() → Vector3
    │   │       ├── _sample_ball_history(ball)    # Update latency ring buffer
    │   │       ├── _predict_first_bounce_position(ball)  # Uses perceived state
    │   │       ├── _predict_ai_contact_point(ball)
    │   │       ├── _get_ai_intercept_solution(ball_pos)
    │   │       │   ├── _predict_ai_contact_candidates()  # 3 candidates: pre/1st/2nd bounce
    │   │       │   └── Scored by: reposition_cost + paddle_error + body_cost - preference
    │   │       └── Returns: normalized direction input vector
    │   │
    │   ├── [LATENCY / PERCEPTION] ─────────────────────────────────────
    │   │   ├── _get_latency_frames() → int       # Per difficulty
    │   │   ├── _sample_ball_history(ball)         # Push to ring buffer
    │   │   ├── _perceived_ball_pos() → Vector3    # Read from N frames ago
    │   │   ├── _perceived_ball_vel() → Vector3
    │   │   └── _perceived_ball_omega() → Vector3
    │   │
    │   ├── [PREDICTION] ───────────────────────────────────────────────
    │   │   ├── _predict_first_bounce_position(ball) → Vector3
    │   │   │   └── Uses: predict_aero_step in loop, AI_LANDING_PREDICTION_STEPS=14
    │   │   ├── _predict_ball_position(ball, time_ahead) → Vector3
    │   │   ├── _predict_ai_contact_candidates(ball) → Array[Vector3]
    │   │   │   └── 0=pre-bounce, 1=first bounce, 2=second bounce (or exit)
    │   │   ├── _predict_ai_contact_point(ball) → Vector3
    │   │   └── _predict_ai_intercept_marker_point(ball) → Vector3
    │   │       └── Height-filtered (0.28-1.45m) hittable point
    │   │
    │   ├── [POSTURE SELECTION] ─────────────────────────────────────────
    │   │   ├── _get_posture_for_height(rel_height) → Array[int]
    │   │   │   └── Returns ranked postures by height tier
    │   │   ├── _get_ai_posture_preference(posture) → float
    │   │   │   └── Hardcoded preference scores per posture per difficulty
    │   │   └── _get_ai_intercept_solution(ball_pos) → Dictionary
    │   │       └── { target, posture, contact }
    │   │
    │   ├── [AI HIT SYSTEM] ─────────────────────────────────────────────
    │   │   ├── _try_ai_hit_ball()
    │   │   │   ├── Phase 1: Start charge when paddle_distance <= AI_CHARGE_START_DISTANCE
    │   │   │   ├── Phase 2: Animate pullback via set_serve_charge_visual()
    │   │   │   ├── Phase 3: Fire when charge_ratio >= swing_threshold AND close_enough
    │   │   │   └── Fallback: Overlap detection if ball flies into paddle
    │   │   ├── _apply_ai_hit(body, charge_ratio)
    │   │   │   ├── compute_shot_velocity()  → target velocity
    │   │   │   ├── compute_shot_spin()
    │   │   │   ├── compute_sweet_spot_spin()
    │   │   │   ├── paddle velocity transfer (GAP-X)
    │   │   │   └── sweet-spot speed penalty (GAP-15)
    │   │   └── _on_hitbox_body_entered(body, _paddle)  # NOOP — charge system owns hitting
    │   │
    │   ├── [COMMIT HELPERS] ───────────────────────────────────────────
    │   │   ├── _commit_ai_target_position(new_target)    # Smoothed with threshold
    │   │   ├── _commit_ai_bounce_prediction(new_bounce)
    │   │   └── _commit_ai_contact_prediction(new_contact)
    │   │
    │   ├── [TRAJECTORY VISUALIZATION] ─────────────────────────────────
    │   │   ├── _setup_ai_trajectory()
    │   │   ├── _draw_ai_trajectory(ball_pos, ball_vel)
    │   │   └── _update_ai_trajectory_fade(delta)
    │   │
    │   └── [INTERCEPT POOL] ────────────────────────────────────────────
    │       ## AI reads human's committed intercept dots for positioning
    │       ├── human_committed_pre_intercepts: Array[Vector3]
    │       ├── human_committed_post_intercepts: Array[Vector3]
    │       ├── human_committed_contact_position: Vector3
    │       └── human_committed_target_position: Vector3
    │
    ├── player_arm_ik.gd  ─────────────────────────────────────────────────
    │   ## Two-bone IK for arm chains (shoulder → elbow → wrist)
    │   ├── setup(skeleton, bones)
    │   ├── update(target_hand_pos, elbow_pole_pos, shoulder_rot_deg)
    │   └── _solve_ik_2link() → bool
    │
    ├── player_leg_ik.gd  ─────────────────────────────────────────────────
    │   ## Leg IK for stance / foot placement
    │   ├── update()
    │   └── solve_leg_ik()
    │
    ├── player_awareness_grid.gd ─────────────────────────────────────────────
    │   ## Spatial grid tracking ball trajectory for AI
    │   ├── setup(player)
    │   ├── update_ball_prediction(ball_pos, ball_vel)
    │   ├── get_contact_point() → Vector3
    │   └── on_ball_bounced(pos)
    │
    ├── player_body_animation.gd ────────────────────────────────────────────
    │   ## Torso/hip animation blendspace
    │   ├── update()
    │   └── lerp_body_pose()
    │
    ├── player_body_builder.gd ─────────────────────────────────────────────
    │   ## Procedural body construction from capsule + skeleton
    │   ├── build() → void
    │   └── _create_bone_chain()
    │
    ├── player_debug_visual.gd ─────────────────────────────────────────────
    │   ## Debug overlays (zone viz, intent indicators)
    │   ├── setup()
    │   ├── set_visible()
    │   └── update()
    │
    ├── player_hitting.gd  ─────────────────────────────────────────────────
    │   ## Swing animation state machine
    │   ## Handles charge, release, follow-through
    │   ├── [ENUM] SwingPhase
    │   │   └── IDLE, WIND_UP, STRIKE, FOLLOW_THROUGH, SETTLE
    │   ├── [STATE]
    │   │   ├── phase: SwingPhase
    │   │   ├── charge_time: float
    │   │   ├── follow_through_time: float
    │   │   └── PADDLE_VEL_TRANSFER = 0.25  (GAP-X)
    │   ├── start_charge()
    │   ├── release(charge_ratio)
    │   ├── tick(dt)
    │   ├── get_paddle_velocity() → Vector3
    │   └── is_charging() → bool
    │
    ├── player_paddle_posture.gd  ───────────────────────────────────────────
    │   ## Paddle position/rotation from posture definitions
    │   ## Reads PostureDefinition resource + posture_library
    │   ├── [STATE]
    │   │   ├── paddle_posture: int          # Current posture enum
    │   │   ├── _current_posture_def: PostureDefinition
    │   │   └── _target_posture_def: PostureDefinition
    │   ├── setup(player, skeleton)
    │   ├── update(dt)
    │   ├── set_posture(posture_id)
    │   ├── get_paddle_position() → Vector3   # World space paddle center
    │   ├── get_paddle_rotation() → Vector3
    │   ├── notify_ball_hit()
    │   └── [ZONE TRACKING] ─────────────────────────────────────────
    │       ├── incoming_stage_changed: Signal  # (stage, posture, commit_dist, ball2ghost, ttc)
    │       ├── grade_flashed: Signal          # (grade: String)
    │       ├── _update_zone_tracking(ball_pos)
    │       └── _compute_stage() → int
    │
    ├── shot_physics.gd  ────────────────────────────────────────────────────
    │   ## Ball hitting calculations — velocity targeting + spin
    │   ##
    │   ## GAP references: GAP-15 (sweet-spot), GAP-X (paddle vel transfer)
    │   │
    │   ├── [CONSTANTS] ─────────────────────────────────────────────────
    │   │   ├── MIN_SWING_SPEED_MS = 7.0
    │   │   ├── MAX_SWING_SPEED_MS = 22.35
    │   │   └── NET_CLEAR_MIN = 1.30  (m, minimum net clearance)
    │   │
    │   ├── compute_shot_velocity(ball_pos, charge_ratio, player_num, shot_type, ai_difficulty) → Vector3
    │   │   ## Main entry — computes target launch velocity
    │   │   ├── Select target speed from charge_ratio curve (power function)
    │   │   ├── Select target landing zone by shot_type:
    │   │   │   ├── SMASH:  fast, deep, downward bias
    │   │   │   ├── FAST:   medium-fast, deep
    │   │   │   ├── VOLLEY: medium, kitchen-range
    │   │   │   ├── DINK:   slow, short, up-angle
    │   │   │   ├── DROP:   slow, short, moderate up
    │   │   │   ├── LOB:    medium, deep, high up
    │   │   │   └── RETURN: fast, medium-deep
    │   │   ├── Iterative solve (6 iterations):
    │   │   │   ├── simulate_shot_trajectory()
    │   │   │   ├── Check net clearance
    │   │   │   └── Adjust vy to hit target
    │   │   └── Return: solved velocity vector
    │   │
    │   ├── compute_shot_spin(shot_type, vel, charge_ratio, player_num, posture=-1) → Vector3
    │   │   ## Computes angular velocity from shot type
    │   │   ├── Topspin axis = UP × travel_direction
    │   │   ├── Magnitude by shot_type:
    │   │   │   ├── SMASH: 55 * charge_gain
    │   │   │   ├── FAST:   45 * charge_gain
    │   │   │   ├── LOB:    18 * charge_gain
    │   │   │   ├── RETURN: 22 * charge_gain
    │   │   │   ├── VOLLEY: -10 (slight backspin)
    │   │   │   ├── DROP:   -20 (backspin)
    │   │   │   └── DINK:   -12 (light backspin)
    │   │   └── Sidespin from posture (backhand vs forehand)
    │   │
    │   ├── compute_sweet_spot_speed(ball_pos, paddle_center, shot_vel) → float
    │   │   ## GAP-15: off-center hits reduce speed
    │   │   └── Sweet spot radius 0.04m → full speed; edge at 0.12m → 60% speed
    │   │
    │   ├── compute_sweet_spot_spin(ball_pos, paddle_center, shot_vel) → Vector3
    │   │   ## Off-center contact adds rim-torque spin
    │   │   └── Torque axis = offset_in_plane × travel_dir
    │   │
    │   └── simulate_shot_trajectory(start_pos, vel, omega, grav, target_z, net_sign) → Dictionary
    │       ## Iterative ballistic simulation with aero
    │       ├── Returns: { crossed_target, pos_at_target, y_at_net, t_at_net, t_total, apex_y }
    │       └── Uses: _Ball.predict_aero_step() in loop (200 steps max, dt=1/120)
    │
    ├── physics.gd  ────────────────────────────────────────────────────────
    │   ## Pure math utilities — no scene dependencies
    │   ## All functions: static, deterministic, unit-testable
    │   ├── _damp(current, target, halflife, dt) → float
    │   │   └── Exponential damping: lerp(current, target, 1 - exp(-0.693*dt/HL))
    │   └── _damp_v3(current, target, halflife, dt) → Vector3
    │
    ├── rally_scorer.gd  ───────────────────────────────────────────────────
    │   ## Pickleball scoring rules enforcement
    │   ├── bind(ball, player_left, player_right)
    │   ├── start_rally(team, from_right)
    │   ├── end_rally()
    │   └── rally_ended: Signal  # (winner, reason, detail)
    │
    ├── rules.gd  ──────────────────────────────────────────────────────────
    │   ## Game rules: fault conditions, out calls, kitchen rules
    │   └── check_fault() → bool
    │
    ├── input_handler.gd  ─────────────────────────────────────────────────
    │   ## Raw input → game intent mapping
    │   ├── setup(game, ball, player_left, player_right, camera_rig, practice_launcher, editor_ui, sound_panel, reaction_button)
    │   ├── _process_input()
    │   └── _handle_serve_input()
    │
    ├── court.gd  ──────────────────────────────────────────────────────────
    │   ## Court geometry creation (lines, surfaces)
    │   ├── create_court(parent)   → creates court mesh children
    │   ├── create_lines(parent)    → creates line meshes
    │   └── get_court_bounds() → Dictionary  # { min_x, max_x, min_z, max_z }
    │
    ├── net.gd  ────────────────────────────────────────────────────────────
    │   ## Net mesh creation
    │   └── create_net(parent)  → creates net mesh children
    │
    ├── camera/ ─────────────────────────────────────────────────────────────
    │   ├── camera_rig.gd  ────────────────────────────────────────────────
    │   │   ## Orbit/tilt camera rig
    │   │   ├── setup(game, player_left, player_right, ball, is_practice_cb) → Camera3D
    │   │   ├── handle_input(event)
    │   │   ├── update(delta)
    │   │   ├── set_fov(fov)
    │   │   ├── editor_focus_point: Vector3   # Camera target in editor mode
    │   │   └── orbit_mode: int              # 0=follow, 3=fixed editor view
    │   │
    │   └── camera_shake.gd  ───────────────────────────────────────────────
    │       ## Screen shake on impact
    │       ├── setup(camera)
    │       ├── add_impulse(intensity)
    │       └── _apply_shake()
    │
    ├── fx/ ─────────────────────────────────────────────────────────────────
    │   ├── fx_pool.gd  ──────────────────────────────────────────────────
    │   │   ## Object pool for impact effects
    │   │   ├── get_effect(prefab) → Node
    │   │   └── return_effect(node)
    │   │
    │   ├── ball_trail.gd  ────────────────────────────────────────────────
    │   │   ## Trail mesh following ball
    │   │   ├── setup(ball)
    │   │   └── update()
    │   │
    │   ├── bounce_decal.gd  ───────────────────────────────────────────────
    │   │   ## Court decal spawned on ball bounce
    │   │   └── spawn(pos)
    │   │
    │   ├── hit_feedback.gd  ──────────────────────────────────────────────
    │   │   ## Camera shake + flash on paddle hit
    │   │   ├── setup(ball, camera_rig, players)
    │   │   └── on_paddle_hit(player_num)
    │   │
    │   └── impact_burst.gd  ───────────────────────────────────────────────
    │       ## Particle burst on impact
    │       └── spawn(pos, normal)
    │
    ├── ui/ ─────────────────────────────────────────────────────────────────
    │   ├── hud.gd  ───────────────────────────────────────────────────────
    │   │   ## Main HUD canvas layer
    │   │   └── CanvasLayer root
    │   │
    │   ├── scoreboard_ui.gd  ─────────────────────────────────────────────
    │   │   ## Score display, state text, shot type labels
    │   │   ├── setup(hud)
    │   │   ├── update_score(left, right)
    │   │   ├── update_difficulty(d)
    │   │   ├── set_state_text(msg)
    │   │   ├── show_shot_type(type)
    │   │   ├── show_speed(speed)
    │   │   ├── show_fault(headline, detail)
    │   │   └── hide_out()
    │   │
    │   ├── pause_menu.gd  ───────────────────────────────────────────────
    │   │   ├── show()
    │   │   └── hide()
    │   │
    │   ├── pause_controller.gd  (AUTOLOAD: PauseController)
    │   │   ├── pause()
    │   │   ├── resume()
    │   │   └── is_paused() → bool
    │   │
    │   ├── settings.gd  (AUTOLOAD: Settings) ──────────────────────────────
    │   │   ├── get_value(key, default) → Variant
    │   │   ├── set_value(key, value)
    │   │   ├── settings_changed: Signal  # (key, value)
    │   │   └── [Keys]
    │   │       ├── video.fov
    │   │       ├── video.shadow_quality
    │   │       └── gameplay.difficulty
    │   │
    │   └── settings_panel.gd  ────────────────────────────────────────────
    │       └── _build_ui()
    │
    ├── game_serve.gd  ─────────────────────────────────────────────────────
    │   ## Serve state machine: charge → aim → arc → release
    │   ├── setup(game, ball, player_left, player_right, rally_scorer, scoreboard, shot_physics_class)
    │   ├── is_charging() → bool
    │   ├── start_charge()
    │   ├── tick_charge(dt)
    │   ├── get_charge_ratio() → float
    │   ├── release(charge_ratio)
    │   ├── perform_serve(charge_ratio)
    │   ├── get_serve_launch_position(is_red) → Vector3
    │   ├── cleanup()
    │   └── serve_launched: Signal  # (team)
    │
    ├── game_shots.gd  ─────────────────────────────────────────────────────
    │   ## Shot classification + out detection
    │   ├── setup(ball, player_left, player_right, scoreboard)
    │   ├── cleanup()
    │   ├── update(game_state, ball, serve_charge_time, p_left, p_right) → shot_type: String
    │   ├── _classify_intended_shot(ball, player) → String   # On swing press
    │   ├── _classify_trajectory(velocity) → String        # On swing release
    │   ├── on_ball_bounced(pos)
    │   └── _is_out() → bool
    │
    ├── game_trajectory.gd  ────────────────────────────────────────────────
    │   ## Trajectory arc visualization
    │   ├── setup(game, ball)
    │   ├── update(game_state, serving_team, aim_offset, arc_offset, charge_time, p_left_pos, p_right_pos)
    │   ├── get_aim_label() → String
    │   ├── get_arc_label() → String
    │   └── clear()
    │
    ├── game_drop_test.gd  ─────────────────────────────────────────────────
    │   ## Kinematic bounce calibration tool
    │   ├── setup(ball)
    │   ├── start()
    │   ├── tick()
    │   ├── is_active() → bool
    │   └── test_complete: Signal
    │
    ├── game_debug_ui.gd  ─────────────────────────────────────────────────
    │   ## Debug overlay: posture names, zone viz, difficulty cycling
    │   ├── setup(p_left, p_right, scoreboard, rally_scorer, ball, serve_charge, ai_diff, aim, arc)
    │   ├── update(game_state, ball, p_left, p_right)
    │   ├── update_refs(...)
    │   ├── cycle_debug_visuals()
    │   ├── toggle_intent_indicators()
    │   ├── cycle_difficulty()
    │   └── set_debug_visible(v)
    │
    ├── game_sound_tune.gd  ────────────────────────────────────────────────
    │   ## Sound signature tuning panel
    │   ├── setup(audio_synth, scoreboard, hud)
    │   ├── _create_sound_tune_panel(canvas)
    │   └── _refresh_sound_tune_panel()
    │
    ├── practice_launcher.gd  ─────────────────────────────────────────────
    │   ## Practice mode: auto-launch ball for solo drill
    │   ├── setup(game, ball, player_left, player_right, ball_probe)
    │   └── is_active() → bool
    │
    ├── swing_e2e_probe.gd  ──────────────────────────────────────────────
    │   ## End-to-end swing test harness
    │   ├── begin_test(game, player, ball)
    │   ├── get_verdict() → String
    │   └── _run_test()
    │
    ├── time/ ───────────────────────────────────────────────────────────────
    │   └── time_scale_manager.gd  (AUTOLOAD: TimeScale) ─────────────────
    │       ## Time dilation control (slow-mo for reaction)
    │       ├── request_slowmo(tag, scale)
    │       └── release(tag)
    │
    ├── posture_controller.gd  ─────────────────────────────────────────────
    │   ## Base pose state machine — full body positioning
    │   ## Maps PaddlePosture → BasePoseState transitions
    │   ├── [STATE] ──────────────────────────────────────────────────────
    │   │   ├── base_pose_state: BasePoseState
    │   │   ├── pose_intent: PoseIntent
    │   │   └── _cache_valid: bool
    │   ├── setup(player, skeleton)
    │   ├── invalidate_cache()
    │   └── get_pose_for_posture(posture) → { body_pos, body_rot, leg_targets }
    │
    ├── posture_definition.gd  ──────────────────────────────────────────────
    │   ## Resource — 40+ fields defining ONE posture
    │   ## Stored as .gd files or in posture_library
    │   ├── [IDENTITY]
    │   │   ├── posture_id: int
    │   │   ├── display_name: String
    │   │   ├── family: int        # 0=FH, 1=BH, 2=center, 3=overhead
    │   │   └── height_tier: int  # 0=LOW, 1=MID_LOW, 2=NORMAL, 3=OVERHEAD
    │   ├── [PADDLE POSITION]
    │   │   ├── paddle_forehand_mul: float   # side offset
    │   │   ├── paddle_forward_mul: float     # forward/back offset
    │   │   └── paddle_y_offset: float       # vertical
    │   ├── [PADDLE ROTATION]
    │   │   ├── paddle_pitch_base_deg + *_signed_deg + *_sign_source
    │   │   ├── paddle_yaw_base_deg + *_signed_deg + *_sign_source
    │   │   └── paddle_roll_base_deg + *_signed_deg + *_sign_source
    │   │   └── sign_source: 0=none, 1=swing_sign, 2=fwd_sign
    │   ├── [COMMIT ZONE]
    │   │   ├── has_zone: bool
    │   │   └── zone_x_min/max, zone_y_min/max
    │   ├── [ARM IK — RIGHT]
    │   │   ├── right_hand_offset: Vector3
    │   │   ├── right_elbow_pole: Vector3
    │   │   └── right_shoulder_rotation_deg: Vector3
    │   ├── [ARM IK — LEFT]
    │   │   ├── left_hand_mode: int  # Free, PaddleNeck, AcrossChest, OverheadLift
    │   │   ├── left_hand_offset: Vector3
    │   │   ├── left_elbow_pole: Vector3
    │   │   └── left_shoulder_rotation_deg: Vector3
    │   ├── [LEGS]
    │   │   ├── stance_width, front_foot_forward, back_foot_back
    │   │   ├── right/left_foot_yaw_deg
    │   │   ├── right/left_knee_pole: Vector3
    │   │   ├── lead_foot: int  # Right/Left
    │   │   ├── crouch_amount: float
    │   │   └── weight_shift: float
    │   ├── [TORSO]
    │   │   ├── hip_yaw_deg, torso_yaw/pitch/roll_deg
    │   │   └── spine_curve_deg
    │   ├── [BODY PIVOT]
    │   │   ├── body_yaw_deg, body_pitch_deg, body_roll_deg
    │   ├── [HEAD]
    │   │   ├── head_yaw_deg, head_pitch_deg
    │   │   └── head_track_ball_weight: float
    │   ├── [CHARGE] (pre-swing windup)
    │   │   ├── charge_paddle_offset/rotation_deg
    │   │   ├── charge_body_rotation_deg
    │   │   └── charge_hip_coil_deg, charge_back_foot_load
    │   ├── [FOLLOW-THROUGH]
    │   │   ├── ft_paddle_offset/rotation_deg
    │   │   ├── ft_hip_uncoil_deg, ft_front_foot_load
    │   │   └── ft_duration_strike/sweep/settle/hold, ft_ease_curve
    │   └── [METHODS]
    │       ├── resolve_paddle_rotation_deg(swing_sign, fwd_sign) → Vector3
    │       ├── resolve_paddle_offset(forehand_axis, forward_axis) → Vector3
    │       └── lerp_with(other, w) → PostureDefinition  # Blending
    │
    ├── posture_library.gd  ────────────────────────────────────────────────
    │   ## Runtime registry of all PostureDefinitions
    │   ├── _postures: Dictionary[int → PostureDefinition]
    │   ├── setup()
    │   ├── get_posture(id) → PostureDefinition
    │   └── get_all_postures() → Array[PostureDefinition]
    │
    ├── base_pose_definition.gd  ───────────────────────────────────────────
    │   ## Resource — full body pose (not just paddle)
    │   ├── pose_id: int
    │   ├── display_name: String
    │   ├── hips_offset: Vector3
    │   ├── torso_rotation: Vector3
    │   ├── head_rotation: Vector3
    │   ├── left_foot_target: Vector3
    │   ├── right_foot_target: Vector3
    │   ├── weight_distribution: float
    │   └── lerp_with(other, w) → BasePoseDefinition
    │
    ├── base_pose_library.gd  ──────────────────────────────────────────────
    │   ## Registry of BasePoseDefinitions
    │   ├── get_base_pose(id) → BasePoseDefinition
    │   └── get_all_base_poses() → Array[BasePoseDefinition]
    │
    ├── posture_skeleton_applier.gd  ────────────────────────────────────────
    │   ## Applies PostureDefinition to actual Skeleton3D bones
    │   ├── setup(skeleton, bones_dict)
    │   └── apply_posture(def: PostureDefinition, lerp_t: float)
    │
    ├── posture_offset_resolver.gd  ────────────────────────────────────────
    │   ## Computes paddle world position from posture + player axes
    │   └── resolve(posture_def, player_pos, forehand_axis, forward_axis) → Vector3
    │
    ├── posture_commit_selector.gd  ─────────────────────────────────────────
    │   ## Commit zone validation — is ball in valid contact zone?
    │   ├── setup(posture_def)
    │   └── is_in_zone(ball_pos, paddle_pos) → bool
    │
    ├── posture_colors.gd  ─────────────────────────────────────────────────
    │   ## Debug visualization colors per posture family
    │   └── get_color(family) → Color
    │
    ├── posture_constants.gd  ───────────────────────────────────────────────
    │   └── COMMITTED_BALL_2_GHOST_THRESHOLD = 0.15
    │
    ├── posture_editor_ui.gd  ───────────────────────────────────────────────
    │   ## Main posture editor panel UI (editor-only)
    │   ├── editor_opened: Signal
    │   ├── editor_closed: Signal
    │   ├── set_player(player)
    │   ├── get_current_paddle_position() → Vector3
    │   └── build_transport_bar() → Control
    │
    ├── reaction_hit_button.gd  ─────────────────────────────────────────────
    │   ## On-screen HIT button for reaction mode
    │   ├── auto_fire_requested: Signal
    │   ├── update_from_stage(stage, posture_name, commit_dist, ball2ghost, ttc)
    │   ├── show_grade(grade)
    │   └── enter_idle()
    │
    ├── base_pose_definition.gd  (duplicate? see above) ────────────────────
    │
    ├── base_pose_library.gd  (duplicate? see above) ──────────────────────
    │
    ├── drop_test.gd  (see game_drop_test.gd) ────────────────────────────
    │
    ├── game_drop_test.gd  ────────────────────────────────────────────────
    │
    ├── game_serve.gd  (see above) ─────────────────────────────────────────
    │
    ├── game_shots.gd  (see above) ─────────────────────────────────────────
    │
    ├── game_trajectory.gd  (see above) ────────────────────────────────────
    │
    ├── game_debug_ui.gd  (see above) ─────────────────────────────────────
    │
    ├── game_sound_tune.gd  (see above) ───────────────────────────────────
    │
    ├── posture_editor/  ───────────────────────────────────────────────────
    │   ## In-Editor posture editing tool (editor-only)
    │   ## NOT included in shipped game
    │   │
    │   ├── posture_editor_state.gd  ──────────────────────────────────────
    │   │   ## Editor state machine: IDLE, DRAGGING, ROTATING, PLAYING
    │   │   ├── current_state: int
    │   │   ├── selected_posture: int
    │   │   ├── selected_bone: String
    │   │   └── transitions: Array
    │   │
    │   ├── posture_editor_gizmos.gd  ─────────────────────────────────────
    │   │   ## Manages all gizmos in editor
    │   │   ├── gizmos: Array[GizmoController]
    │   │   ├── add_gizmo(type, position)
    │   │   └── remove_gizmo(gizmo)
    │   │
    │   ├── posture_editor_preview.gd  ────────────────────────────────────
    │   │   ## Live preview rendering of skeleton pose
    │   │   ├── setup(player_skeleton)
    │   │   └── refresh()
    │   │
    │   ├── posture_editor_transport.gd  ──────────────────────────────────
    │   │   ## Timeline transport: play/pause/step for animation preview
    │   │   ├── play()
    │   │   ├── pause()
    │   │   └── step_frame()
    │   │
    │   ├── gizmo_controller.gd  ─────────────────────────────────────────
    │   │   ## Base class for all gizmos
    │   │   ├── position: Vector3
    │   │   ├── rotation: Vector3
    │   │   └── _on_dragged(new_pos)
    │   │
    │   ├── gizmo_handle.gd  ────────────────────────────────────────────
    │   │   ## Drag handle (position gizmo)
    │   │   └── on_handle_dragged(axis, delta)
    │   │
    │   ├── position_gizmo.gd  ───────────────────────────────────────────
    │   │   ## Position manipulation gizmo (3-axis arrow)
    │   │   └── get_drag_delta() → Vector3
    │   │
    │   ├── rotation_gizmo.gd  ───────────────────────────────────────────
    │   │   ## Rotation gizmo (3-color rings)
    │   │   └── get_rotation_delta() → Vector3
    │   │
    │   ├── pose_trigger.gd  ──────────────────────────────────────────────
    │   │   ## Trigger zone gizmo (commit zone visualization)
    │   │   └── set_trigger_zone(rect)
    │   │
    │   ├── property_editors/ ─────────────────────────────────────────────
    │   │   ├── slider_field.gd     # Float slider with label
    │   │   └── vector3_editor.gd   # XYZ input fields
    │   │
    │   └── tabs/ ────────────────────────────────────────────────────────
    │       ├── arms_tab.gd           # Arm IK properties
    │       ├── legs_tab.gd           # Leg/stance properties
    │       ├── torso_tab.gd          # Torso/hip rotation
    │       ├── head_tab.gd          # Head rotation, eye tracking
    │       ├── paddle_tab.gd         # Paddle position/rotation
    │       ├── charge_tab.gd         # Charge animation properties
    │       └── follow_through_tab.gd  # Follow-through properties
    │
    └── tests/  ────────────────────────────────────────────────────────────
        ├── test_runner.gd           # Main test runner
        ├── test_all_suites.gd       # Runs all suites
        ├── e2e_test_runner.gd       # Godot-level integration
        ├── test_physics_utils.gd    # physics.gd unit tests
        ├── test_player_hitting.gd   # player_hitting.gd unit tests
        ├── test_base_pose_system.gd  # base pose tests
        ├── test_posture_editor.gd    # Editor tab tests
        ├── test_posture_persistence.gd
        ├── test_posture_zones.gd
        ├── test_rally_scorer.gd
        ├── test_shot_physics.gd
        ├── test_shot_physics_shallow.gd
        ├── test_editor_runner.gd
        ├── _e2e_fast_mode.gd
        ├── fakes/
        │   ├── fake_ball.gd
        │   ├── fake_ball_node.gd
        │   └── fake_player.gd
        └── [Python tests]
            ├── test_e2e_playwright.py  # Browser UI tests
            ├── test_e2e_mcp.py         # Claude agent integration
            └── test_e2e_ultrafast.py   # Fast smoke tests
```

---

## Signal Flow Diagram

```
BALL PHYSICS LOOP
─────────────────
ball._physics_process()
  ├── Apply gravity
  ├── Apply drag (if AERO_EFFECT_SCALE > 0)
  ├── Apply Magnus force (if AERO_EFFECT_SCALE > 0)
  ├── Apply spin damping
  ├── Check floor bounce
  │   ├── Apply COR (velocity-dependent)
  │   ├── Apply spin-tangential coupling
  │   └── emit bounced(pos)
  └── Clamp to MAX_SPEED

SERVE FLOW
──────────
WAITING state
  └── Hold SPACE → start_charge()
      └── tick_charge() updates serve_charge_time
  └── Release SPACE → game_serve.release()
      └── perform_serve()
          ├── compute_shot_velocity()  [shot_physics]
          ├── ball.serve()  [sets velocity + last_hit_by]
          └── set_game_state(SERVING)

RALLY FLOW
──────────
SERVING → PLAYING (on ball crossing net)
  └── rally_scorer.start_rally()

PLAYING state
  ├── Human: Release SPACE → _perform_player_swing()
  │   ├── compute_shot_velocity()  [shot_physics]
  │   ├── compute_shot_spin()
  │   ├── compute_sweet_spot_speed()
  │   ├── compute_sweet_spot_spin()
  │   └── ball.linear_velocity = computed_vel
  │
  ├── AI: ai_brain.get_ai_input() → move player
  │   └── ai_brain._try_ai_hit_ball() → _apply_ai_hit()
  │       ├── compute_shot_velocity()
  │       └── ball.linear_velocity = computed_vel
  │
  └── Ball bounces → emit bounced() → game._on_ball_bounced()

SCORING
───────
rally_scorer detects rally end
  └── emit rally_ended(winner, reason, detail)
      └── game._on_rally_ended()
          └── _on_point_scored(winner)
              ├── Update score
              ├── Check win condition (11pts, 2 ahead)
              └── _reset_ball() or _reset_match()
```

---

## File Dependency Tree

```
game.gd
├── constants.gd (autoload)
├── court.gd (helper, script.new())
├── net.gd (helper, script.new())
├── ball.gd (child node)
│   └── ball_audio_synth.gd (child)
├── player.gd × 2 (child nodes)
│   ├── player_ai_brain.gd (child, player_right only)
│   ├── posture (child, via player_gd)
│   │   └── posture_definition.gd (resource)
│   ├── hitting (child, via player_gd)
│   ├── pose_controller (child, via player_gd)
│   ├── arm_ik (child, via player_gd)
│   ├── leg_ik (child, via player_gd)
│   └── awareness_grid (child, via player_gd)
├── rally_scorer.gd (child)
├── shot_physics.gd (child)
├── input_handler.gd (child)
├── scoreboard_ui.gd (child)
├── practice_launcher.gd (child)
├── ball_physics_probe.gd (child)
├── swing_e2e_probe.gd (child)
├── camera_rig.gd (child)
│   └── camera_shake.gd (child)
├── hud.gd (child)
│   └── scoreboard_ui.gd (child)
├── posture_editor_ui.gd (child)
│   └── reaction_hit_button.gd (child)
├── game_serve.gd (child)
│   └── shot_physics.gd (reference)
├── game_trajectory.gd (child)
├── game_shots.gd (child)
├── game_drop_test.gd (child)
│   └── ball.gd (reference)
├── game_debug_ui.gd (child)
├── game_sound_tune.gd (child)
│   └── ball_audio_synth.gd (reference)
├── fx_pool.gd (autoload)
├── time_scale_manager.gd (autoload)
├── pause_controller.gd (autoload)
└── settings.gd (autoload)
    └── scoreboard_ui.gd (reference)

player.gd
├── player_ai_brain.gd (child, AI only)
├── player_arm_ik.gd (child)
├── player_leg_ik.gd (child)
├── player_hitting.gd (child)
├── player_paddle_posture.gd (child)
│   └── posture_library.gd
│       └── posture_definition.gd × 22
├── pose_controller.gd (child)
│   ├── base_pose_library.gd
│   │   └── base_pose_definition.gd × 22
│   └── posture_definition.gd
├── player_body_animation.gd (child)
├── player_awareness_grid.gd (child)
└── ball.gd (reference)

shot_physics.gd
├── ball.gd (static methods only)
└── constants.gd (autoload)

player_ai_brain.gd
├── ball.gd (predictors)
└── player.gd (parent ref)

game_serve.gd
├── ball.gd
├── player.gd × 2
├── rally_scorer.gd
└── shot_physics.gd

game_shots.gd
├── ball.gd
└── player.gd × 2

game_trajectory.gd
└── ball.gd
```

---

## Key Constants Reference

| Constant | Value | Used By |
|----------|-------|---------|
| `BALL_MASS` | 0.024 kg | ball.gd, physics.gd |
| `BALL_RADIUS` | 0.0375 m | ball.gd, shot_physics.gd |
| `GRAVITY_SCALE` | 1.0 | ball.gd |
| `DRAG_COEFFICIENT` | 0.47 | ball.gd |
| `MAGNUS_COEFFICIENT` | 0.0003 | ball.gd |
| `SPIN_DAMPING_HALFLIFE` | 150.0 s | ball.gd |
| `AERO_EFFECT_SCALE` | 0.79 | ball.gd |
| `BOUNCE_COR` | 0.640 | ball.gd |
| `PLAYER_SPEED` | ~5.0 m/s | player.gd |
| `AI_SPEED` | varies by difficulty | player.gd, ai_brain |
| `PADDLE_FORCE` | ~100.0 | player.gd |
| `NON_VOLLEY_ZONE` | ~2.0 m | player.gd, ai_brain |
| `NET_HEIGHT` | 0.914 m | shot_physics.gd |
| `MIN_SERVE_SPEED` | 3.0 m/s | game.gd |
| `MAX_SERVE_SPEED` | 26.0 m/s | game.gd |
| `MIN_SWING_SPEED_MS` | 7.0 m/s | shot_physics.gd |
| `MAX_SWING_SPEED_MS` | 22.35 m/s | shot_physics.gd |
| `PADDLE_VEL_TRANSFER` | 0.25 | player_hitting.gd, game.gd |
