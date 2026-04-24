extends Node3D
## Game.gd - Thin orchestrator (~500 lines).
## Owns all game state and scoring. Delegates subsystem work to child nodes:
##   GameServe      - serve charge, aim/arc, serve execution
##   GameTrajectory - trajectory visualization
##   GameShots      - shot classification, out indicator
##   GameDropTest   - kinematic bounce calibration
##   GameDebugUI    - debug labels, posture display
##   GameSoundTune  - sound signature tuning panel

enum GameState { WAITING, SERVING, PLAYING, POINT_SCORED }

# ── Game state ────────────────────────────────────────────────────────────────
var score_left := 0
var score_right := 0
var serving_team := 0
var game_state: GameState = GameState.WAITING
var ball_has_bounced := false
var serve_charge_time := 0.0         # Updated by game_serve.tick_charge
var serve_is_charging := false        # Updated by game_serve.start_charge/cleanup
var _pending_shot_type: String = ""  # set on space press, consumed by _perform_player_swing
var _awaiting_return: bool = false  # set by game_serve, read by game_serve to track serve state

# ── Constants ────────────────────────────────────────────────────────────────
const MIN_SERVE_SPEED := PickleballConstants.MIN_SERVE_SPEED
const MAX_SERVE_SPEED := PickleballConstants.MAX_SERVE_SPEED
const MAX_SERVE_CHARGE_TIME := PickleballConstants.MAX_SERVE_CHARGE_TIME
const HIT_REACH_DISTANCE := PickleballConstants.HIT_REACH_DISTANCE
const NON_VOLLEY_ZONE := PickleballConstants.NON_VOLLEY_ZONE
const BLUE_RESET_POSITION := Vector3(1.5, 1.0, 6.8)
const RED_RESET_POSITION := Vector3(-1.5, 1.0, -6.8)
const SERVE_AIM_STEP := PickleballConstants.SERVE_AIM_STEP
const SERVE_AIM_MAX := PickleballConstants.SERVE_AIM_MAX
const ARC_INTENT_STEP := PickleballConstants.ARC_INTENT_STEP
const ARC_INTENT_MIN := PickleballConstants.ARC_INTENT_MIN
const ARC_INTENT_MAX := PickleballConstants.ARC_INTENT_MAX
const SERVE_ZONE_CENTER_TOLERANCE := 0.2

# ── Preloaded class_name scripts (force load order to avoid parse errors) ──
const _RallyScorer = preload("res://scripts/rally_scorer.gd")
const _ShotPhysics = preload("res://scripts/shot_physics.gd")
const _InputHandler = preload("res://scripts/input_handler.gd")
const _ScoreboardUI = preload("res://scripts/scoreboard_ui.gd")
const _PracticeLauncher = preload("res://scripts/practice_launcher.gd")
const _BallPhysicsProbe = preload("res://scripts/ball_physics_probe.gd")
const _GameServe = preload("res://scripts/game_serve.gd")
const _GameTrajectory = preload("res://scripts/game_trajectory.gd")
const _GameShots = preload("res://scripts/game_shots.gd")
const _GameDropTest = preload("res://scripts/game_drop_test.gd")
const _GameDebugUI = preload("res://scripts/game_debug_ui.gd")
const _GameSoundTune = preload("res://scripts/game_sound_tune.gd")
const _PostureEditorUI = preload("res://scripts/posture_editor_ui.gd")
const _PostureEditorV2 = preload("res://scripts/posture_editor_v2.gd")
const _ReactionHitButton = preload("res://scripts/reaction_hit_button.gd")
const _SwingE2EProbe = preload("res://scripts/swing_e2e_probe.gd")

# ── Posture system class_name scripts (subfolder scripts need early preload for class resolution) ──
const _PostureDefinition = preload("res://scripts/posture_definition.gd")
const _BasePoseDefinition = preload("res://scripts/base_pose_definition.gd")
const _BasePoseLibrary = preload("res://scripts/base_pose_library.gd")
const _PostureLibrary = preload("res://scripts/posture_library.gd")
const _PostureSkeletonApplier = preload("res://scripts/posture_skeleton_applier.gd")

# ── Posture editor subfolder class_name scripts (loaded lazily by PostureEditorUI) ──
# GizmoHandle/RotationGizmo hierarchy has complex interdependencies - loaded at runtime by PostureEditorUI

# ── Node references ──────────────────────────────────────────────────────────
var player_left: CharacterBody3D
var player_right: CharacterBody3D
var ball: RigidBody3D
var rally_scorer
var shot_physics
var input_handler
var scoreboard_ui
var practice_launcher
var ball_physics_probe
var swing_e2e_probe  # typed after setup() to avoid load-order issue
var hud: CanvasLayer

# ── Child subsystems ─────────────────────────────────────────────────────────
var game_serve
var game_trajectory
var game_shots
var game_drop_test
var game_debug_ui
var game_sound_tune

# ── AI / Debug ───────────────────────────────────────────────────────────────
var ai_difficulty: int = 0          # 0=EASY, 1=MEDIUM, 2=HARD
var debug_visuals_visible: bool = false
var _practice_mode: bool = false
var ai_serve_timer: float = 0.0

# ── Camera ──────────────────────────────────────────────────────────────────
const CameraRigScript = preload("res://scripts/camera/camera_rig.gd")
var camera_rig
var main_camera: Camera3D

# ── Serve aim/arc (delegated to game_serve but kept here for quick access) ──
var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0

# ── Reaction button ──────────────────────────────────────────────────────────
var posture_editor_ui
var posture_editor_v2
var _transport_bar: Control
var reaction_button
var _in_slow_mo: bool = false
var _ball_frozen: bool = false
var _frozen_trajectory_points: Array[Vector3] = []

# ── Missing variable declarations ────────────────────────────────────────────
var _service_fault_triggered: bool = false
var _last_volley_player: int = -1
var _serve_was_hit: bool = false
var fault_headline: Label = null
var fault_detail: Label = null

# ── Orphaned helper nodes (freed in _exit_tree) ──────────────────────────────
var _court_helper: Node        # court_script.new() — used for create_court/create_lines
var _net_helper: Node          # net_script.new()  — used for create_net

# ── Helpers ─────────────────────────────────────────────────────────────────


func _is_practice() -> bool:
	return _practice_mode or (practice_launcher != null and practice_launcher.is_active)

func is_awaiting_return() -> bool:
	return _awaiting_return  # read by game_serve.gd externally; getter marks variable as "used"

func get_serve_charge_time() -> float:
	return serve_charge_time

func get_ai_difficulty() -> int:
	return ai_difficulty

func get_serve_aim_offset() -> float:
	return serve_aim_offset_x

func get_trajectory_arc_offset() -> float:
	return trajectory_arc_offset

# ── Lifecycle ───────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[GAME] _unhandled_input: mouse button ", event.button_index)
	if camera_rig != null:
		camera_rig.handle_input(event)

func _ready() -> void:
	_setup_environment()
	_setup_game()

# ═══════════════════════════════════════════════════════════════════════════════
# _setup_environment — sky, sun, fill light (no game state needed)
# ═══════════════════════════════════════════════════════════════════════════════
func _setup_environment() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment: Environment = Environment.new()

	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.10, 0.13, 0.18)
	sky_mat.ground_horizon_color = Color(0.38, 0.42, 0.50)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.55, 0.62, 0.72)
	environment.fog_density = 0.006
	environment.fog_sun_scatter = 0.1
	env.environment = environment
	add_child(env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-60, 35, 0)
	sun.light_energy = 1.8
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.3
	sun.shadow_opacity = 0.85
	add_child(sun)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.name = "CourtFill"
	fill.position = Vector3(0, 8.5, 0)
	fill.light_energy = 0.25
	fill.omni_range = 22.0
	fill.light_color = Color(0.9, 0.95, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

	print("[ENV] Sun created: energy=", sun.light_energy, " shadow=", sun.shadow_enabled,
		" mode=ORTHOGONAL ambient=", environment.ambient_light_energy)

# ═══════════════════════════════════════════════════════════════════════════════
# _setup_game — create all game nodes + child subsystems
# ═══════════════════════════════════════════════════════════════════════════════
func _setup_game() -> void:
	var court_script: Script = load("res://scripts/court.gd")
	var net_script: Script = load("res://scripts/net.gd")
	var ball_script: Script = load("res://scripts/ball.gd")
	var player_script: Script = load("res://scripts/player.gd")

	_court_helper = court_script.new()
	_net_helper = net_script.new()

	_court_helper.create_court(self)
	_court_helper.create_lines(self)
	_net_helper.create_net(self)

	var bounds: Dictionary = _court_helper.get_court_bounds()

	player_left = player_script.new()
	add_child(player_left)
	player_left.setup(0, bounds, Color(0.2, 0.5, 1.0), BLUE_RESET_POSITION, false)

	player_right = player_script.new()
	add_child(player_right)
	player_right.setup(1, bounds, Color(1.0, 0.35, 0.35), RED_RESET_POSITION, true)
	player_right.set_ai_movement_enabled(false)
	if player_right.ai_brain:
		player_right.ai_brain._game_node = self

	ball = ball_script.new()
	ball.name = "Ball"
	add_child(ball)
	ball.bounced.connect(_on_ball_bounced)
	ball.hit_by_paddle.connect(_on_any_paddle_hit)

	rally_scorer = _RallyScorer.new()
	rally_scorer.name = "RallyScorer"
	add_child(rally_scorer)
	rally_scorer.bind(ball, player_left, player_right)
	rally_scorer.rally_ended.connect(_on_rally_ended)

	shot_physics = _ShotPhysics.new()
	shot_physics.setup(ball, player_left, player_right)

	scoreboard_ui = _ScoreboardUI.new()
	add_child(scoreboard_ui)

	# Ball physics probe must be created BEFORE practice_launcher.setup()
	ball_physics_probe = _BallPhysicsProbe.new()
	ball_physics_probe.name = "BallPhysicsProbe"
	add_child(ball_physics_probe)

	swing_e2e_probe = _SwingE2EProbe.new()
	swing_e2e_probe.name = "SwingE2EProbe"
	add_child(swing_e2e_probe)

	practice_launcher = _PracticeLauncher.new()
	add_child(practice_launcher)
	practice_launcher.setup(self, ball, player_left, player_right, ball_physics_probe)

	_setup_camera_rig()
	_setup_hit_feedback()
	_create_ui()

	_wire_settings()

	# Instantiate and setup child subsystems
	_setup_subsystems()

	# input_handler must be set up AFTER game_sound_tune exists (so sound_tune_panel is available)
	input_handler = _InputHandler.new()
	add_child(input_handler)
	input_handler.setup(self, ball, player_left, player_right, camera_rig, practice_launcher, posture_editor_ui, game_sound_tune.sound_tune_panel, reaction_button)

	# Hide debug visuals by default
	call_deferred("_set_debug_visuals_visible_deferred", false)

func _setup_subsystems() -> void:
	# GameServe — serve charge, aim, arc, execution
	game_serve = _GameServe.new()
	add_child(game_serve)
	game_serve.setup(self, ball, player_left, player_right, rally_scorer, scoreboard_ui, _ShotPhysics)
	game_serve.serve_launched.connect(_on_serve_launched)

	# GameTrajectory — trajectory visualization
	game_trajectory = _GameTrajectory.new()
	add_child(game_trajectory)
	game_trajectory.setup(self, ball)

	# GameShots — shot classification, out indicator
	game_shots = _GameShots.new()
	add_child(game_shots)
	game_shots.setup(ball, player_left, player_right, scoreboard_ui)
	game_shots.cleanup()  # init state

	# GameDropTest — kinematic bounce calibration
	game_drop_test = _GameDropTest.new()
	add_child(game_drop_test)
	game_drop_test.setup(ball)
	game_drop_test.test_complete.connect(_on_drop_test_complete)

	# GameDebugUI — posture debug, zone debug, difficulty cycling
	game_debug_ui = _GameDebugUI.new()
	add_child(game_debug_ui)
	game_debug_ui.setup(player_left, player_right, scoreboard_ui, rally_scorer, ball,
		serve_charge_time, ai_difficulty, serve_aim_offset_x, trajectory_arc_offset)

	# GameSoundTune — sound signature tuning panel
	game_sound_tune = _GameSoundTune.new()
	add_child(game_sound_tune)
	game_sound_tune.setup(ball.audio_synth, scoreboard_ui, hud)

# ═══════════════════════════════════════════════════════════════════════════════
# Serve aim UI update (called from input_handler during WAITING state)
# ═══════════════════════════════════════════════════════════════════════════════
func _update_waiting_ui() -> void:
	# Update serve aim/arc display during aiming
	if game_state == 0:  # WAITING
		var serve_call: String = _format_serve_call()
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [serve_call, game_trajectory.get_aim_label(), game_trajectory.get_arc_label()])

# ═══════════════════════════════════════════════════════════════════════════════
# Settings wiring
# ═══════════════════════════════════════════════════════════════════════════════
func _wire_settings() -> void:
	var s: Node = get_node_or_null("/root/Settings")
	if s == null:
		return
	_apply_setting("video.fov", s.call("get_value", "video.fov", 60.0))
	_apply_setting("gameplay.difficulty", s.call("get_value", "gameplay.difficulty", 0))
	_apply_setting("video.shadow_quality", s.call("get_value", "video.shadow_quality", 1))
	if s.has_signal("settings_changed") and not s.settings_changed.is_connected(_apply_setting):
		s.settings_changed.connect(_apply_setting)

func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"video.fov":
			if camera_rig != null:
				camera_rig.set_fov(float(value))
		"gameplay.difficulty":
			var d: int = clampi(int(value), 0, 2)
			if d != ai_difficulty:
				ai_difficulty = d
				if scoreboard_ui != null:
					scoreboard_ui.update_difficulty(ai_difficulty)
				if player_right != null and player_right.ai_brain != null:
					player_right.ai_brain.ai_difficulty = ai_difficulty
		"video.shadow_quality":
			var sun: DirectionalLight3D = get_node_or_null("Sun")
			if sun != null:
				sun.shadow_enabled = int(value) > 0

# ═══════════════════════════════════════════════════════════════════════════════
# Camera + FX setup
# ═══════════════════════════════════════════════════════════════════════════════
func _setup_camera_rig() -> void:
	camera_rig = CameraRigScript.new()  # CameraRigScript is a preload const
	main_camera = camera_rig.setup(self, player_left, player_right, ball, Callable(self, "_is_practice"))

func _setup_hit_feedback() -> void:
	var HitFeedbackScript = preload("res://scripts/fx/hit_feedback.gd")
	var hf: Node = HitFeedbackScript.new()
	hf.name = "HitFeedback"
	add_child(hf)
	hf.call("setup", ball, camera_rig, [player_left, player_right])

	var BallTrailScript = preload("res://scripts/fx/ball_trail.gd")
	var trail: MeshInstance3D = BallTrailScript.new()
	add_child(trail)
	trail.call("setup", ball)

# ═══════════════════════════════════════════════════════════════════════════════
# UI creation (HUD, reaction button, posture editor, sound tune panel)
# ═══════════════════════════════════════════════════════════════════════════════
func _create_ui() -> void:
	var HudScript = preload("res://scripts/ui/hud.gd")
	hud = HudScript.new()
	add_child(hud)

	if scoreboard_ui:
		scoreboard_ui.setup(hud)
		scoreboard_ui.update_difficulty(ai_difficulty)
		scoreboard_ui.update_score(score_left, score_right)

	var canvas: CanvasLayer = hud

	# Reaction HIT button — lower-right, easy mode only
	reaction_button = _ReactionHitButton.new()
	reaction_button.name = "ReactionHitButton"
	reaction_button.anchor_left = 1.0
	reaction_button.anchor_right = 1.0
	reaction_button.anchor_top = 1.0
	reaction_button.anchor_bottom = 1.0
	reaction_button.offset_left = -380.0
	reaction_button.offset_right = -20.0
	reaction_button.offset_top = -380.0
	reaction_button.offset_bottom = -20.0
	canvas.add_child(reaction_button)
	if player_left and player_left.posture:
		player_left.posture.incoming_stage_changed.connect(_on_player_stage_changed)
		player_left.posture.grade_flashed.connect(_on_player_grade_flashed)
	reaction_button.auto_fire_requested.connect(_on_reaction_auto_fire)

	# Posture Editor UI
	posture_editor_ui = _PostureEditorUI.new()
	posture_editor_ui.name = "PostureEditorUI"
	posture_editor_ui.visible = false
	posture_editor_ui.editor_opened.connect(_on_editor_opened)
	posture_editor_ui.editor_closed.connect(_on_editor_closed)
	canvas.add_child(posture_editor_ui)
	# V1 archived — do not init player/gizmos so they don't steal input.
	# if player_left:
	# 	posture_editor_ui.set_player(player_left)

	# Posture Editor v2 — clean-slate rewrite, triggered by Q / E.
	posture_editor_v2 = _PostureEditorV2.new()
	posture_editor_v2.name = "PostureEditorV2"
	posture_editor_v2.editor_opened.connect(_on_editor_v2_opened)
	posture_editor_v2.editor_closed.connect(_on_editor_v2_closed)
	canvas.add_child(posture_editor_v2)
	if player_left:
		posture_editor_v2.set_player(player_left)
	if camera_rig != null:
		camera_rig.is_mouse_over_editor_ui_cb = Callable(posture_editor_v2, "contains_screen_point")

	# Transport bar — sibling of posture_editor_ui on canvas (spans viewport 0.0-0.65)
	# Hidden by default; shown only when posture editor is open.
	_transport_bar = posture_editor_ui.build_transport_bar()
	_transport_bar.visible = false
	canvas.add_child(_transport_bar)

	# Sound tune panel — created via game_sound_tune subsystem
	# (called after _setup_subsystems so game_sound_tune is initialized)
	if game_sound_tune != null:
		game_sound_tune._create_sound_tune_panel(canvas)

# ═══════════════════════════════════════════════════════════════════════════════
# State machine
# ═══════════════════════════════════════════════════════════════════════════════
func _set_game_state(new_state: GameState) -> void:
	if new_state == game_state:
		return
	print("[STATE] %s -> %s" % [GameState.keys()[game_state], GameState.keys()[new_state]])
	game_state = new_state
	if rally_scorer:
		if new_state == GameState.PLAYING:
			var total_score: int = score_left + score_right
			var from_right: bool = (total_score % 2) == 0
			rally_scorer.start_rally(serving_team, from_right)
			player_right.set_ai_movement_enabled(true)
		elif new_state != GameState.PLAYING and new_state != GameState.SERVING:
			rally_scorer.end_rally()

# ═══════════════════════════════════════════════════════════════════════════════
# Physics process — main game loop (delegates to subsystems)
# ═══════════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	# Exit slow-mo if we leave PLAYING
	if _in_slow_mo and game_state != GameState.PLAYING:
		_exit_slow_mo()
		if reaction_button:
			reaction_button.enter_idle()

	# Drop test T key
	if Input.is_key_pressed(KEY_T) and not _t_was_pressed:
		_t_was_pressed = true
		if not game_drop_test.is_active():
			game_drop_test.start()
	if not Input.is_key_pressed(KEY_T):
		_t_was_pressed = false

	# Serve charge update
	if game_serve.is_charging():
		game_serve.tick_charge(delta)
		serve_charge_time = game_serve.get_charge_ratio() * MAX_SERVE_CHARGE_TIME
		serve_is_charging = true
	else:
		serve_is_charging = false

	# Trajectory update
	game_trajectory.update(game_state, serving_team, serve_aim_offset_x, trajectory_arc_offset,
		serve_charge_time, player_left.global_position, player_right.global_position)

	# Shots update (out indicator, returns current pending shot type)
	var _shot_type: String = game_shots.update(game_state, ball, serve_charge_time, player_left, player_right)

	# Debug UI update
	game_debug_ui.update_refs(serve_charge_time, ai_difficulty, serve_aim_offset_x, trajectory_arc_offset)
	game_debug_ui.update(game_state, ball, player_left, player_right)

	# Drop test tick
	if game_drop_test.is_active():
		game_drop_test.tick()

	# Camera update
	if camera_rig != null:
		if posture_editor_v2 and posture_editor_v2.visible and player_left:
			camera_rig.editor_focus_point = player_left.global_position
		elif posture_editor_ui and posture_editor_ui.visible:
			camera_rig.editor_focus_point = posture_editor_ui.get_current_paddle_position()
		else:
			camera_rig.editor_focus_point = Vector3.INF
		camera_rig.update(delta)

	# Game state logic
	if game_state == GameState.WAITING and not game_drop_test.is_active():
		_update_held_ball_position()
		# AI auto-serve after a short delay
		if serving_team == 1:
			ai_serve_timer += delta
			if ai_serve_timer >= 1.5:
				var ai_charge: float = randf_range(0.5, 0.8)
				serve_aim_offset_x = randf_range(-0.3, 0.3)
				trajectory_arc_offset = randf_range(-0.1, 0.1)
				_perform_serve(ai_charge)
				ai_serve_timer = 0.0
	elif game_state == GameState.PLAYING:
		if not _is_practice():
			_check_rally()

var _t_was_pressed: bool = false

# ═══════════════════════════════════════════════════════════════════════════════
# Score helpers
# ═══════════════════════════════════════════════════════════════════════════════
func _format_scoreboard() -> String:
	var arrow_left: String = "▶ " if serving_team == 0 else "  "
	var arrow_right: String = " ◀" if serving_team == 1 else "  "
	return "%s%d  -  %d%s" % [arrow_left, score_left, score_right, arrow_right]

func _format_serve_call() -> String:
	if serving_team == 0:
		return "Blue serves: %d - %d" % [score_left, score_right]
	else:
		return "Red serves: %d - %d" % [score_right, score_left]

# ═══════════════════════════════════════════════════════════════════════════════
# Reaction button / slow-mo
# ═══════════════════════════════════════════════════════════════════════════════
func _on_player_stage_changed(stage: int, posture: int, commit_dist: float, ball2ghost: float, ttc: float) -> void:
	if stage < 0:
		if reaction_button:
			reaction_button.enter_idle()
		_exit_slow_mo()
		return
	if game_state != GameState.PLAYING:
		if reaction_button:
			reaction_button.enter_idle()
		_exit_slow_mo()
		return
	var posture_name: String = ""
	if posture >= 0 and player_left and posture < player_left.DEBUG_POSTURE_NAMES.size():
		posture_name = player_left.DEBUG_POSTURE_NAMES[posture]
	if reaction_button:
		reaction_button.update_from_stage(stage, posture_name, commit_dist, ball2ghost, ttc)

func _on_player_grade_flashed(grade: String) -> void:
	if reaction_button:
		reaction_button.show_grade(grade)
	print("[REACT] grade=%s" % grade)

func _on_reaction_auto_fire() -> void:
	if game_state == GameState.PLAYING:
		_perform_player_swing(1.0)

func _enter_slow_mo() -> void:
	if _in_slow_mo:
		return
	_in_slow_mo = true
	TimeScale.request_slowmo("reaction", 0.55)

func _exit_slow_mo() -> void:
	if _in_slow_mo:
		_in_slow_mo = false
		TimeScale.release("reaction")

# ═══════════════════════════════════════════════════════════════════════════════
# Swing handling (space press/release) — delegates to game_serve + game_shots
# ═══════════════════════════════════════════════════════════════════════════════
func _on_player_swing_press() -> void:
	if game_state != GameState.PLAYING:
		return
	_enter_slow_mo()
	_pending_shot_type = game_shots._classify_intended_shot(ball, player_left)
	scoreboard_ui.show_shot_type(_pending_shot_type)
	print("[Shot] Blue intent: %s" % _pending_shot_type)

func _deactivate_reaction_button() -> void:
	if reaction_button:
		reaction_button.enter_idle()
	_exit_slow_mo()

func _on_player_swing_release(charge_ratio: float) -> void:
	game_trajectory.clear()
	if game_state == GameState.WAITING:
		game_serve.release(charge_ratio)
	elif game_state == GameState.PLAYING:
		_perform_player_swing(charge_ratio)
	_deactivate_reaction_button()

# ═══════════════════════════════════════════════════════════════════════════════
# Serve execution (AI + manual)
# ═══════════════════════════════════════════════════════════════════════════════
func _perform_serve(charge_ratio: float) -> void:
	game_serve.perform_serve(charge_ratio)

func _on_serve_launched(_team: int) -> void:
	# game_serve.perform_serve already set game_state = SERVING
	pass

# ═══════════════════════════════════════════════════════════════════════════════
# Player swing (human)
# ═══════════════════════════════════════════════════════════════════════════════
func _perform_player_swing(charge_ratio: float) -> void:
	player_left.animate_serve_release(charge_ratio)
	if player_left.posture:
		player_left.posture.notify_ball_hit()

	if ball == null:
		return

	var paddle_pos: Vector3 = player_left.global_position + player_left._get_posture_offset_for(player_left.paddle_posture)
	var reach := HIT_REACH_DISTANCE
	var player_to_ball: float = player_left.global_position.distance_to(ball.global_position)
	if player_to_ball < 1.80:
		reach = maxf(reach, player_to_ball * 0.85)
	if paddle_pos.distance_to(ball.global_position) > reach:
		scoreboard_ui.set_state_text("Rally!")
		return

	var _vel: Vector3 = compute_shot_velocity(ball.global_position, charge_ratio, 0, _pending_shot_type)
	# GAP-X: paddle velocity at impact contributes to ball speed.
	# The animated paddle has real velocity from the kinetic chain motion.
	# Only the component in the shot direction transfers to ball speed.
	var paddle_vel: Vector3 = player_left.hitting.get_paddle_velocity()
	var shot_dir: Vector3 = _vel.normalized()
	var paddle_vel_in_shot_dir: float = paddle_vel.dot(shot_dir)
	var vel_transfer: float = player_left.hitting.PADDLE_VEL_TRANSFER
	if absf(paddle_vel_in_shot_dir) > 0.5:
		_vel += shot_dir * paddle_vel_in_shot_dir * vel_transfer
	# GAP-15: sweet-spot speed reduction — off-center hits lose up to 40% speed
	var speed_factor := compute_sweet_spot_speed(ball.global_position, paddle_pos, _vel)
	_vel = _vel * speed_factor
	ball.linear_velocity = _vel
	var _shot_spin: Vector3 = compute_shot_spin(_pending_shot_type, _vel, charge_ratio, 0, player_left.paddle_posture)
	var _sweet_spin: Vector3 = compute_sweet_spot_spin(ball.global_position, paddle_pos, _vel)
	ball.angular_velocity = _shot_spin + _sweet_spin
	ball.hit_by_player(0)
	scoreboard_ui.show_speed(ball.linear_velocity.length())
	if _pending_shot_type != "":
		scoreboard_ui.show_shot_type(_pending_shot_type)
	else:
		scoreboard_ui.show_shot_type(game_shots._classify_trajectory(ball.linear_velocity))
	_pending_shot_type = ""
	scoreboard_ui.set_state_text("Rally!")

# ═══════════════════════════════════════════════════════════════════════════════
# Rally helpers — delegate to game_shots
# ═══════════════════════════════════════════════════════════════════════════════
func _check_rally() -> void:
	if ball.global_position.y < 0.1 and ball.linear_velocity.y < -1.0:
		ball_has_bounced = true
		scoreboard_ui.set_state_text("Ball bounced!")

# ═══════════════════════════════════════════════════════════════════════════════
# Scoring / reset
# ═══════════════════════════════════════════════════════════════════════════════
func _on_rally_ended(winner: int, reason: String, detail: String) -> void:
	if game_state == GameState.POINT_SCORED or _is_practice():
		return
	scoreboard_ui.show_fault(reason.replace("_", " "), detail)
	_on_point_scored(winner)

func _on_point_scored(winning_team: int) -> void:
	if game_state == GameState.POINT_SCORED or _is_practice():
		return
	_set_game_state(GameState.POINT_SCORED)
	ai_serve_timer = 0.0
	_last_volley_player = -1

	if winning_team == serving_team:
		if winning_team == 0:
			score_left += 1
		else:
			score_right += 1
		scoreboard_ui.update_score(score_left, score_right)
		scoreboard_ui.set_state_text("Point! " + str(score_left) + " - " + str(score_right))
	else:
		serving_team = winning_team
		scoreboard_ui.set_state_text("Side Out! Serve to " + ("Blue" if winning_team == 0 else "Red"))

	if score_left >= 11 and score_left - score_right >= 2:
		scoreboard_ui.set_state_text("GAME OVER! BLUE WINS!")
		await get_tree().create_timer(3.0).timeout
		_reset_match()
	elif score_right >= 11 and score_right - score_left >= 2:
		scoreboard_ui.set_state_text("GAME OVER! RED WINS!")
		await get_tree().create_timer(3.0).timeout
		_reset_match()
	else:
		await get_tree().create_timer(1.5).timeout
		_reset_ball()

func _reset_ball() -> void:
	ball.reset()
	ball_has_bounced = false
	_set_game_state(GameState.WAITING)
	serve_charge_time = 0.0
	serve_is_charging = false
	serve_aim_offset_x = 0.0
	trajectory_arc_offset = 0.0
	ai_serve_timer = 0.0
	_service_fault_triggered = false
	_serve_was_hit = false
	game_serve.cleanup()
	game_shots.cleanup()
	game_trajectory.clear()
	_reset_player_positions()
	if player_left and player_left.posture:
		player_left.posture.reset_incoming_highlight()
	if player_right and player_right.posture:
		player_right.posture.reset_incoming_highlight()
	player_right.set_ai_movement_enabled(false)
	_update_held_ball_position()
	scoreboard_ui.hide_out()
	var serve_call: String = _format_serve_call()
	if serving_team == 0:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [serve_call, game_trajectory.get_aim_label(), game_trajectory.get_arc_label()])
	else:
		scoreboard_ui.set_state_text("%s..." % serve_call)

func _reset_match() -> void:
	score_left = 0
	score_right = 0
	serving_team = 0
	scoreboard_ui.update_score(score_left, score_right)
	_reset_ball()

func _reset_player_positions() -> void:
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var blue_x: float = 1.5 if serve_from_right else -1.5
	player_left.global_position = Vector3(blue_x, 1.0, 6.8)
	var red_x: float = -1.5 if serve_from_right else 1.5
	player_right.global_position = Vector3(red_x, 1.0, -6.8)
	print("[SPAWN] score=", total_score, " serve_from_right=", serve_from_right,
		" Blue@X=", blue_x, " Red@X=", red_x)

func _update_held_ball_position() -> void:
	if ball == null:
		return
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = game_serve.get_serve_launch_position(serving_team == 1)

# ═══════════════════════════════════════════════════════════════════════════════
# Ball signal handlers
# ═══════════════════════════════════════════════════════════════════════════════
func _on_any_paddle_hit(_player_num: int) -> void:
	if game_state != GameState.PLAYING:
		return
	if ball != null:
		scoreboard_ui.show_speed(ball.linear_velocity.length())
		scoreboard_ui.show_shot_type(game_shots._classify_trajectory(ball.linear_velocity))

func _on_ball_bounced(bounce_pos: Vector3) -> void:
	_spawn_bounce_spot(bounce_pos)
	ball.record_bounce_side(bounce_pos.z)
	if player_right != null:
		player_right.notify_ball_bounced(bounce_pos)
	game_shots.on_ball_bounced(bounce_pos)

# ═══════════════════════════════════════════════════════════════════════════════
# Debug / editor
# ═══════════════════════════════════════════════════════════════════════════════
func _set_debug_visuals_visible_deferred(v: bool) -> void:
	_set_debug_visuals_visible(v)

func _set_debug_visuals_visible(v: bool) -> void:
	game_debug_ui.set_debug_visible(v)
	if not v:
		_set_debug_zones_visible(false)
	if scoreboard_ui:
		scoreboard_ui.set_debug_visuals_active(v)
	print("[DEBUG] visuals ", "ON" if v else "OFF")

func _set_debug_zones_visible(v: bool) -> void:
	var dz_node: Node = find_child("DebugZones", true, false)
	if dz_node:
		dz_node.visible = v

# ── Hotkey delegation callbacks (input_handler.gd uses has_method() to call these) ──

func _cycle_debug_visuals() -> void:
	# Delegates to game_debug_ui which owns the debug visual cycling state
	if game_debug_ui and game_debug_ui.has_method("cycle_debug_visuals"):
		game_debug_ui.cycle_debug_visuals()

func _toggle_intent_indicators() -> void:
	# Delegates to game_debug_ui which owns the intent indicator state
	if game_debug_ui and game_debug_ui.has_method("toggle_intent_indicators"):
		game_debug_ui.toggle_intent_indicators()

func _cycle_difficulty() -> void:
	# Delegates to game_debug_ui which owns the difficulty cycling state
	if game_debug_ui and game_debug_ui.has_method("cycle_difficulty"):
		game_debug_ui.cycle_difficulty()

func _start_drop_test() -> void:
	# Delegates to game_drop_test which owns the drop test state
	if game_drop_test and game_drop_test.has_method("start"):
		game_drop_test.start()

func is_ball_frozen() -> bool:
	return _ball_frozen

func _toggle_ball_freeze() -> void:
	_ball_frozen = not _ball_frozen
	if _ball_frozen:
		print("[FREEZE] Ball frozen")
		if ball:
			ball.set_frozen_state(ball.global_position, ball.linear_velocity, ball.angular_velocity)
			ball.set_time_frozen(true)
		if player_left and player_left.debug_visual:
			player_left.debug_visual.set_trajectory_visible(true)
			if player_left.debug_visual.incoming_traj_instance:
				player_left.debug_visual.incoming_traj_instance.visible = true
			_frozen_trajectory_points = player_left.debug_visual._last_trajectory_points.duplicate()
		_feed_frozen_trajectory()
		if hud and hud.get("freeze_indicator"):
			hud.freeze_indicator.visible = true
	else:
		print("[FREEZE] Ball unfrozen")
		if ball:
			ball.set_time_frozen(false)
		_frozen_trajectory_points.clear()
		if hud and hud.get("freeze_indicator"):
			hud.freeze_indicator.visible = false

func _feed_frozen_trajectory() -> void:
	for p in [player_left, player_right]:
		if p and p.posture:
			p.posture.set_trajectory_points(_frozen_trajectory_points.duplicate())
		if p and p.awareness_grid:
			p.awareness_grid.set_trajectory_points(_frozen_trajectory_points.duplicate())

func _refresh_sound_tune_panel() -> void:
	# Delegates to game_sound_tune which owns the sound panel
	if game_sound_tune and game_sound_tune.has_method("_refresh_sound_tune_panel"):
		game_sound_tune._refresh_sound_tune_panel()

func _print_sound_tunings() -> void:
	if ball and ball.has_method("get_sound_tunings"):
		var tunings: Dictionary = ball.get_sound_tunings()
		print("[SOUND TUNINGS] ", tunings)

# ── Posture editor callbacks ────────────────────────────────────────────────────

func _toggle_posture_editor() -> void:
	if posture_editor_ui == null:
		push_warning("[POSTURE EDITOR] posture_editor_ui is null — editor not initialized")
		return
	var was_visible = posture_editor_ui.visible
	posture_editor_ui.visible = not was_visible
	if not was_visible:
		_on_editor_opened()
		print("[POSTURE EDITOR] ON")
	else:
		_on_editor_closed()
		print("[POSTURE EDITOR] OFF")

func _toggle_posture_editor_v2() -> void:
	if posture_editor_v2 == null:
		push_warning("[POSTURE EDITOR V2] posture_editor_v2 is null — editor not initialized")
		return
	posture_editor_v2.toggle()
	if posture_editor_v2.visible:
		print("[POSTURE EDITOR V2] ON")
	else:
		print("[POSTURE EDITOR V2] OFF")

func _on_editor_v2_opened() -> void:
	# CP2 — editor camera: orbit around player from a fixed angle.
	if camera_rig != null and camera_rig.camera != null:
		_editor_previous_camera_mode = camera_rig.orbit_mode
		_editor_previous_camera_pos = camera_rig.camera.position
		_editor_previous_camera_rot = camera_rig.camera.rotation_degrees
		camera_rig.orbit_mode = 3
		camera_rig.orbit_pitch = 0.24
		camera_rig.orbit_angle = PI
		camera_rig.orbit_auto = false
		print("[EDITOR V2] Camera switched to editor orbit")
	# Show posture ghosts for editor
	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(true)

func _on_editor_v2_closed() -> void:
	# CP2 — restore previous camera.
	if camera_rig != null and camera_rig.camera != null:
		camera_rig.orbit_mode = _editor_previous_camera_mode
		if _editor_previous_camera_mode == 0:
			camera_rig.camera.position = _editor_previous_camera_pos
			camera_rig.camera.rotation_degrees = _editor_previous_camera_rot
		print("[EDITOR V2] Camera restored")
	# Restore ghost visibility to match debug state
	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(debug_visuals_visible)

var _editor_previous_camera_mode: int = 0
var _editor_previous_camera_pos: Vector3 = Vector3.ZERO
var _editor_previous_camera_rot: Vector3 = Vector3.ZERO
var _editor_previous_window_mode: int = Window.MODE_WINDOWED
var _editor_previous_window_size: Vector2i = Vector2i.ZERO
var _editor_previous_window_position: Vector2i = Vector2i.ZERO
var _editor_window_geometry_saved: bool = false

func _expand_window_for_editor() -> void:
	var window: Window = get_window()
	if window == null:
		return
	_editor_previous_window_mode = window.mode
	if _editor_previous_window_mode != Window.MODE_WINDOWED:
		_editor_window_geometry_saved = false
		return
	_editor_previous_window_size = window.size
	_editor_previous_window_position = window.position
	_editor_window_geometry_saved = true
	window.mode = Window.MODE_MAXIMIZED

func _restore_window_after_editor() -> void:
	var window: Window = get_window()
	if window == null:
		return
	window.mode = _editor_previous_window_mode as Window.Mode
	if not _editor_window_geometry_saved:
		return
	window.size = _editor_previous_window_size
	window.position = _editor_previous_window_position
	_editor_window_geometry_saved = false

func _on_editor_opened() -> void:
	if scoreboard_ui:
		scoreboard_ui.hide_all_hud()
	if reaction_button:
		reaction_button.visible = false
	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(true)
	if _transport_bar:
		_transport_bar.visible = true
	_expand_window_for_editor()
	if camera_rig != null and camera_rig.camera != null:
		_editor_previous_camera_mode = camera_rig.orbit_mode
		_editor_previous_camera_pos = camera_rig.camera.position
		_editor_previous_camera_rot = camera_rig.camera.rotation_degrees
		camera_rig.orbit_mode = 3
		camera_rig.orbit_pitch = 0.24
		camera_rig.orbit_angle = PI
		camera_rig.orbit_auto = false
		print("[EDITOR] Camera adjusted for editing")

func _on_editor_closed() -> void:
	if scoreboard_ui:
		scoreboard_ui.show_all_hud()
	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(debug_visuals_visible)
	if _transport_bar:
		_transport_bar.visible = false
	_restore_window_after_editor()
	if camera_rig != null and camera_rig.camera != null:
		camera_rig.orbit_mode = _editor_previous_camera_mode
		if _editor_previous_camera_mode == 0:
			camera_rig.camera.position = _editor_previous_camera_pos
			camera_rig.camera.rotation_degrees = _editor_previous_camera_rot
		print("[EDITOR] Camera restored")

# ═══════════════════════════════════════════════════════════════════════════════
# Shot physics delegation (used by human swing + AI brain)
# ═══════════════════════════════════════════════════════════════════════════════
func _simulate_shot_trajectory(start_pos: Vector3, vel: Vector3, omega: Vector3, grav: float, target_z: float, net_sign: float) -> Dictionary:
	return shot_physics.simulate_shot_trajectory(start_pos, vel, omega, grav, target_z, net_sign)

func compute_shot_velocity(ball_pos: Vector3, charge_ratio: float, player_num: int, shot_type: String) -> Vector3:
	return shot_physics.compute_shot_velocity(ball_pos, charge_ratio, player_num, shot_type, ai_difficulty)

func compute_shot_spin(shot_type: String, vel: Vector3, charge_ratio: float, player_num: int, posture: int = -1) -> Vector3:
	return shot_physics.compute_shot_spin(shot_type, vel, charge_ratio, player_num, posture)

func compute_sweet_spot_spin(ball_pos: Vector3, paddle_center: Vector3, shot_vel: Vector3) -> Vector3:
	return shot_physics.compute_sweet_spot_spin(ball_pos, paddle_center, shot_vel)

func compute_sweet_spot_speed(ball_pos: Vector3, paddle_center: Vector3, shot_vel: Vector3) -> float:
	return shot_physics.compute_sweet_spot_speed(ball_pos, paddle_center, shot_vel)

# ═══════════════════════════════════════════════════════════════════════════════
# Bounce spot (visual)
# ═══════════════════════════════════════════════════════════════════════════════
func _spawn_bounce_spot(spot_pos: Vector3) -> void:
	if not debug_visuals_visible:
		return
	var spot: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 0.012
	spot.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.92, 0.2, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.9, 0.25, 1.0)
	material.emission_energy_multiplier = 0.9
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	spot.material_override = material
	spot.position = spot_pos + Vector3(0.0, 0.09, 0.0)
	spot.add_to_group("bounce_spots")
	add_child(spot)
	var tween: Tween = create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 2.0)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 2.0)
	tween.finished.connect(spot.queue_free)

# ═══════════════════════════════════════════════════════════════════════════════
# Drop test complete signal
# ═══════════════════════════════════════════════════════════════════════════════
func _on_drop_test_complete() -> void:
	pass  # game.gd doesn't need to react specifically; test_complete signal is for external listeners

func run_swing_e2e_test() -> String:
	if swing_e2e_probe:
		swing_e2e_probe.begin_test(self, player_left, ball)
	return "SwingE2EProbe started — results in ~4s via get_verdict()"

func _exit_tree() -> void:
	# Free orphaned helper nodes created via script.new() that were never added to the scene tree.
	# These are the script-instance wrappers for court.gd and net.gd — their methods
	# (create_court/create_lines/create_net) add children to 'self', but the wrapper nodes
	# themselves stay unparented and require explicit cleanup to avoid:
	#   WARNING: ObjectDB instances leaked at exit
	#   ERROR: 2 resources still in use at exit
	#   (plus orphaned StringNames from the script's static constants)
	if _court_helper != null:
		_court_helper.free()
		_court_helper = null
	if _net_helper != null:
		_net_helper.free()
		_net_helper = null
