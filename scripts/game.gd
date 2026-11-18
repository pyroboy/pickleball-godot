extends Node3D
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")









enum GameState{WAITING, SERVING, PLAYING, POINT_SCORED}


var score_left: = 0
var score_right: = 0
var serving_team: = 0
var game_state: GameState = GameState.WAITING
var match_over: = false
var match_winner: = -1

var _point_reset_generation: = 0
var ball_has_bounced: = false
var serve_charge_time: = 0.0
var serve_is_charging: = false
var selected_spin_mode: int = 0
var selected_shot_intent: String = "AUTO"
var selected_movement_intent: String = "AUTO"
var dive_actions_enabled := false
var _execution_commits: Dictionary = {}
var _frozen_shot_intent: String = ""
var _frozen_spin_mode: int = -1
var last_shot_profile: Dictionary = {}
var _pending_auto_shot_type: String = ""
var _pending_shot_type: String = ""
var _awaiting_return: bool = false


const MIN_SERVE_SPEED: = PickleballConstants.MIN_SERVE_SPEED
const MAX_SERVE_SPEED: = PickleballConstants.MAX_SERVE_SPEED
const MAX_SERVE_CHARGE_TIME: = PickleballConstants.MAX_SERVE_CHARGE_TIME
const NON_VOLLEY_ZONE: = PickleballConstants.NON_VOLLEY_ZONE
# Keep automatic service setup behind the full shoe footprint of the approved
# forward Flat stance. Manual repositioning still uses the normal foot-fault gate.
const SERVE_RESET_DEPTH := 7.05
const BLUE_RESET_POSITION: = Vector3(1.5, 1.0, SERVE_RESET_DEPTH)
const RED_RESET_POSITION: = Vector3(-1.5, 1.0, -SERVE_RESET_DEPTH)
const SERVE_AIM_STEP: = PickleballConstants.SERVE_AIM_STEP
const SERVE_AIM_MAX: = PickleballConstants.SERVE_AIM_MAX
const ARC_INTENT_STEP: = PickleballConstants.ARC_INTENT_STEP
const ARC_INTENT_MIN: = PickleballConstants.ARC_INTENT_MIN
const ARC_INTENT_MAX: = PickleballConstants.ARC_INTENT_MAX
const SERVE_ZONE_CENTER_TOLERANCE: = 0.2


const _RallyScorer = preload("res://scripts/rally_scorer.gd")
const _ShotPhysics = preload("res://scripts/shot_physics.gd")
const _ShotProfile = preload("res://scripts/shot_profile.gd")
const _InputHandler = preload("res://scripts/input_handler.gd")
const _AimController = preload("res://scripts/aim_controller.gd")
const _ScoreboardUI = preload("res://scripts/scoreboard_ui.gd")
const _PracticeLauncher = preload("res://scripts/practice_launcher.gd")
const _GameServe = preload("res://scripts/game_serve.gd")
const _GameTrajectory = preload("res://scripts/game_trajectory.gd")
const _GameShots = preload("res://scripts/game_shots.gd")
const _ReactionHitButton = preload("res://scripts/reaction_hit_button.gd")


const _PostureDefinition = preload("res://scripts/posture_definition.gd")
const _BasePoseDefinition = preload("res://scripts/base_pose_definition.gd")
const _BasePoseLibrary = preload("res://scripts/base_pose_library.gd")
const _PostureLibrary = preload("res://scripts/posture_library.gd")
const _PostureSkeletonApplier = preload("res://scripts/posture_skeleton_applier.gd")





var player_left: CharacterBody3D
var player_right: CharacterBody3D
# Registry is authoritative for gameplay iteration; aliases above remain for
# existing human/tool UI until those consumers migrate explicitly.
var _players_by_actor: Dictionary = {}
var match_ai_seed: int = 0
var doubles_mode := false
var doubles_state = null
var doubles_controller = null
var team_coordination = null
var ball: RigidBody3D
var rally_scorer
var contact_authority
var shot_physics
var input_handler
var mobile_controls
var movement_actions
var _fast_point_transition
var aim_controller
var aim_focus
var movement_guide
var court_audio
var court_callouts
var pvp_mode: = false
var scoreboard_ui
var practice_launcher
var practice_panel
var ball_physics_probe
var hud: CanvasLayer


var game_serve
var between_point_controller
var game_trajectory
var game_shots
var game_drop_test
var game_debug_ui
var game_sound_tune


var ai_difficulty: int = 0
var debug_visuals_visible: bool = false
var _practice_mode: bool = false
var ai_serve_timer: float = 0.0


const CameraRigScript = preload("res://scripts/camera/camera_rig.gd")
var camera_rig
var main_camera: Camera3D


var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0


var posture_editor_ui
var posture_editor_v2
var mobile_pose_editor
var _mobile_poses_saved := false
var _transport_bar: Control
var reaction_button
var _in_slow_mo: bool = false
var _ball_frozen: bool = false
var _frozen_trajectory_points: Array[Vector3] = []


var _service_fault_triggered: bool = false
var _last_volley_player: int = -1
var _serve_was_hit: bool = false
var fault_headline: Label = null
var fault_detail: Label = null


var _court_helper: Node
var _net_helper: Node




func register_player(actor: CharacterBody3D) -> bool:
	if not is_instance_valid(actor) or not "actor_id" in actor or actor.actor_id < 0: return false
	if actor.team_id not in [0, 1] or actor.court_side not in [0, 1]: return false
	if _players_by_actor.has(actor.actor_id): return _players_by_actor[actor.actor_id] == actor
	_players_by_actor[actor.actor_id] = actor
	actor.set_meta("registered_actor_identity", [actor.actor_id, actor.team_id])
	return true

func get_players() -> Array:
	var ids: Array = _players_by_actor.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		var actor = _players_by_actor[id]
		if is_instance_valid(actor): result.append(actor)
	return result

func get_player_by_actor_id(id: int) -> CharacterBody3D:
	var actor = _players_by_actor.get(id)
	return actor if is_instance_valid(actor) else null

func get_team_players(team: int) -> Array:
	var result: Array = []
	for actor in get_players():
		if actor.team_id == team: result.append(actor)
	return result

func get_human_actor() -> CharacterBody3D:
	for actor in get_players():
		if not actor.is_ai: return actor
	return null

func actor_label(actor) -> String:
	if actor == null: return "Player"
	if not actor.is_ai: return "You"
	var human = get_human_actor()
	if human != null and actor.team_id == human.team_id: return "Partner"
	return "Opponent %d" % (get_team_players(actor.team_id).find(actor) + 1)

func human_may_serve() -> bool:
	var server = get_server_actor()
	return server != null and not server.is_ai and server == get_human_actor()

func server_is_ai() -> bool:
	var server = get_server_actor()
	return server != null and server.is_ai

func get_server_logical_court() -> int:
	return doubles_controller.server_logical_court() if doubles_mode and doubles_controller != null else (0 if get_server_score() % 2 == 0 else 1)

func set_ai_movement_for_roster(enabled: bool) -> void:
	for actor in get_players():
		if actor.is_ai: actor.set_ai_movement_enabled(enabled)

func observe_doubles_first_return(actor) -> Dictionary:
	if not doubles_mode: return {"valid": true}
	if doubles_controller == null or doubles_state == null or doubles_state.active_rally.is_empty():
		return {"valid": false, "unresolved": true, "winner": -1, "reason": "SERVICE_CONTEXT_UNRESOLVED", "detail": "Actual service attempt is not recorded"}
	if actor.team_id == doubles_state.serving_team or int(doubles_state.active_rally.first_return_actor) >= 0:
		return {"valid": true}
	var decision: Dictionary = doubles_controller.observe_first_return(actor)
	if not decision.get("valid", false):
		return {"valid": false, "unresolved": true, "winner": -1, "reason": "SERVICE_CONTEXT_UNRESOLVED", "detail": str(decision.get("reason", "Receiver identity unresolved"))}
	if int(decision.get("fault_team", -1)) >= 0:
		return {"valid": false, "winner": 1 - int(decision.fault_team), "reason": "WRONG_RECEIVER", "detail": "The incorrect receiver returned the serve after the correct score-call setup"}
	return {"valid": true}

func get_server_actor() -> CharacterBody3D:
	if doubles_mode and doubles_state != null:
		return get_player_by_actor_id(int(doubles_state.service_context().server_actor))
	var team: Array = get_team_players(serving_team)
	return team[0] if team.size() == 1 else null

func get_receiver_actor() -> CharacterBody3D:
	if doubles_mode and doubles_state != null:
		return get_player_by_actor_id(int(doubles_state.service_context().receiver_actor))
	var team: Array = get_team_players(1 - serving_team)
	return team[0] if team.size() == 1 else null

func get_team_court_side(team: int) -> int:
	var side := -1
	for actor in get_team_players(team):
		if side >= 0 and side != actor.court_side: return -1
		side = actor.court_side
	return side

func get_team_for_court_side(side: int) -> int:
	if side not in [0, 1]: return -1
	var team := -1
	for candidate in [0, 1]:
		if get_team_court_side(candidate) == side:
			if team >= 0: return -1
			team = candidate
	return team

func _is_practice() -> bool:
	return _practice_mode or (practice_launcher != null and practice_launcher.is_active)

func is_awaiting_return() -> bool:
	return _awaiting_return

func get_serve_charge_time() -> float:
	return serve_charge_time

func get_ai_difficulty() -> int:
	return ai_difficulty

func get_serve_aim_offset() -> float:
	return serve_aim_offset_x

func get_trajectory_arc_offset() -> float:
	return trajectory_arc_offset


func _unhandled_input(event: InputEvent) -> void :
	if event is InputEventMouseButton and event.pressed:
		if RuntimePolicy.developer_tools: print("[GAME] _unhandled_input: mouse button ", event.button_index)
	if camera_rig != null:
		camera_rig.handle_input(event)

func _ready() -> void :
	_setup_environment()
	_setup_game()




func _setup_environment() -> void :
	var env: WorldEnvironment = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment: Environment = Environment.new()

	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.1, 0.13, 0.18)
	sky_mat.ground_horizon_color = Color(0.38, 0.42, 0.5)
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

	if RuntimePolicy.developer_tools: print("[ENV] Sun created: energy=", sun.light_energy, " shadow=", sun.shadow_enabled, 
		" mode=ORTHOGONAL ambient=", environment.ambient_light_energy)




func _setup_game() -> void :
	if RuntimePolicy.bench_doubles: get_tree().set_meta("local_doubles", true)
	if RuntimePolicy.bench_seed >= 0:
		seed(RuntimePolicy.bench_seed)
		get_tree().set_meta("match_ai_seed", RuntimePolicy.bench_seed)
	doubles_mode = bool(get_tree().get_meta("local_doubles", false)) and not bool(get_tree().get_meta("open_practice", false))
	var court_script: Script = load("res://scripts/court.gd")
	var net_script: Script = load("res://scripts/net.gd")
	var ball_script: Script = load("res://scripts/ball.gd")
	var player_script: Script = load("res://scripts/player.gd")

	_court_helper = court_script.new()
	_net_helper = net_script.new()

	_court_helper.create_court(self)
	_court_helper.create_lines(self)
	_net_helper.create_net(self)
	var branding = preload("res://scripts/court_branding.gd").new()
	add_child(branding)
	branding.setup(self)

	var bounds: Dictionary = _court_helper.get_court_bounds()

	player_left = player_script.new()
	add_child(player_left)
	player_left.setup(0, bounds, Color(0.2, 0.5, 1.0), BLUE_RESET_POSITION, RuntimePolicy.autoplay)

	player_right = player_script.new()
	add_child(player_right)
	player_right.setup(1, bounds, Color(1.0, 0.35, 0.35), RED_RESET_POSITION, true)
	register_player(player_left)
	register_player(player_right)
	var rig_flush = preload("res://scripts/rig_arm_flush.gd").new()
	rig_flush.name = "RigArmFlush"
	add_child(rig_flush)
	if doubles_mode:
		for identity in [[2, 0], [3, 1]]:
			var actor = player_script.new()
			add_child(actor)
			var team: int = identity[1]
			var color := Color(0.35, 0.68, 1.0) if team == 0 else Color(1.0, 0.56, 0.30)
			actor.setup(team, bounds, color, Vector3(-1.5 if team == 0 else 1.5, 1.0, 7.05 if team == 0 else -3.0), true, identity[0], team, team)
			actor.name = "PlayerActor%d" % identity[0]
			register_player(actor)
		doubles_controller = preload("res://scripts/match_doubles_controller.gd").new()
		var doubles_setup_ok: bool = doubles_controller.setup(self)
		assert(doubles_setup_ok, "Doubles roster/service configuration failed")
		team_coordination = preload("res://scripts/team_coordination_bridge.gd").new()
		var coordination_setup_ok: bool = team_coordination.setup(self)
		assert(coordination_setup_ok, "Doubles coordination configuration failed")
	match_ai_seed = int(get_tree().get_meta("match_ai_seed")) if get_tree().has_meta("match_ai_seed") else randi()
	for actor in get_players():
		if actor.is_ai:
			actor.ai_brain.set_tactic_seed(preload("res://scripts/ai_playing_styles.gd").actor_seed(match_ai_seed, actor.actor_id))
			actor.set_ai_movement_enabled(false)
			actor.ai_brain._game_node = self

	ball = ball_script.new()
	ball.name = "Ball"
	add_child(ball)
	ball.bounced.connect(_on_ball_bounced)
	ball.hit_by_paddle.connect(_on_any_paddle_hit)

	get_node("Net").bind_ball(ball)
	var ground_shadows = preload("res://scripts/fx/ground_shadows.gd").new()
	add_child(ground_shadows)
	ground_shadows.setup(ball, player_left, player_right, get_players())
	var ball_readability = preload("res://scripts/fx/ball_readability.gd").new()
	ball_readability.ball_radius = Ball.BALL_RADIUS
	ball.add_child(ball_readability)

	rally_scorer = _RallyScorer.new()
	rally_scorer.name = "RallyScorer"
	add_child(rally_scorer)
	rally_scorer.bind(ball, player_left, player_right)
	contact_authority = preload("res://scripts/match_contact_authority.gd").new()
	add_child(contact_authority)
	contact_authority.setup(self)
	rally_scorer.rally_ended.connect(_on_rally_ended)
	rally_scorer.rally_pending.connect(_on_rally_pending)
	var court_net = get_node_or_null("Net")
	if court_net != null and court_net.has_signal("ball_hit_post"):
		court_net.ball_hit_post.connect(rally_scorer.on_ball_hit_post)

	shot_physics = _ShotPhysics.new()
	shot_physics.setup(ball, player_left, player_right)

	scoreboard_ui = _ScoreboardUI.new()
	add_child(scoreboard_ui)

	if RuntimePolicy.developer_tools:

		ball_physics_probe = load("res://scripts/debug/ball_physics_probe.gd").new()
		ball_physics_probe.name = "BallPhysicsProbe"
		add_child(ball_physics_probe)
	practice_launcher = _PracticeLauncher.new()
	add_child(practice_launcher)
	practice_launcher.setup(self, ball, player_left, player_right, ball_physics_probe)

	for actor in get_players():
		var driver = load("res://scripts/match_special_reach_driver.gd").new()
		driver.name = "SpecialReachDriver"
		actor.add_child(driver)
		driver.setup(self, actor)
		actor.special_reach_driver = driver

	_setup_camera_rig()
	_setup_hit_feedback()
	_create_ui()
	var stamina_display = preload("res://scripts/ui/stamina_display.gd").new()
	stamina_display.game = self
	add_child(stamina_display)

	_wire_settings()


	_setup_subsystems()

	aim_controller = _AimController.new()
	aim_controller.setup(self)
	if doubles_mode:
		var identities = preload("res://scripts/ui/doubles_identity_cues.gd").new()
		add_child(identities)
		identities.setup(self)


	input_handler = _InputHandler.new()
	add_child(input_handler)
	input_handler.setup(self, ball, player_left, player_right, camera_rig, practice_launcher, posture_editor_ui, game_sound_tune.sound_tune_panel if game_sound_tune else null, reaction_button)

	mobile_controls = preload("res://scripts/ui/mobile_controls.gd").new()
	hud.add_child(mobile_controls)
	mobile_controls.setup(self)
	movement_actions = load("res://scripts/ui/movement_action_picker.gd").new()
	hud.add_child(movement_actions)
	movement_actions.setup(self)

	practice_panel = preload("res://scripts/ui/practice_panel.gd").new()
	add_child(practice_panel)
	practice_panel.setup(self)

	aim_focus = preload("res://scripts/solo_aim_focus.gd").new()
	add_child(aim_focus)
	aim_focus.setup(self)
	# Incoming-ball movement guide (MOVE / TIGHT / NO TIME ring): off by default
	# and not even created then (it runs a flight trace every tick). Turn it on
	# in Settings > "Incoming movement guide"; takes effect next match.
	# Every use of movement_guide is null-guarded.
	if bool(Settings.get_value("gameplay.movement_guide", false)):
		movement_guide = preload("res://scripts/ui/incoming_movement_guide.gd").new()
		add_child(movement_guide)
		movement_guide.setup(self)
		# Sample immediately after the human's published predictor cache, before
		# the later ball callback applies this tick's aerodynamic velocity change.
		movement_guide.process_physics_priority = player_left.process_physics_priority
		move_child(movement_guide, player_left.get_index() + 1)
	court_audio = preload("res://scripts/court_audio.gd").new()
	court_audio.name = "CourtAudio"
	add_child(court_audio)
	court_audio.setup(self)
	court_callouts = preload("res://scripts/court_callouts.gd").new()
	add_child(court_callouts)
	court_callouts.setup(self)


	call_deferred("_set_debug_visuals_visible_deferred", false)
	if get_tree().has_meta("open_practice"):
		var requested_practice: bool = bool(get_tree().get_meta("open_practice", false))
		get_tree().remove_meta("open_practice")
		if requested_practice:
			var pause = get_node("/root/PauseController")
			if not pause.defer_entry_practice(self, practice_panel):
				practice_panel.call_deferred("open_practice")

func _setup_subsystems() -> void :

	game_serve = _GameServe.new()
	add_child(game_serve)
	game_serve.setup(self, ball, player_left, player_right, rally_scorer, scoreboard_ui, _ShotPhysics)
	game_serve.serve_launched.connect(_on_serve_launched)

	between_point_controller = preload("res://scripts/between_point_controller.gd").new()
	add_child(between_point_controller)
	between_point_controller.setup(self)
	between_point_controller.active_changed.connect( func(active: bool):
		if camera_rig == null: return
		if active and camera_rig.has_method("begin_between_point_cinematic"):
			camera_rig.begin_between_point_cinematic(between_point_controller.get_cinematic_focus, 4.0)
		elif not active and camera_rig.has_method("end_between_point_cinematic"):
			camera_rig.end_between_point_cinematic())
	if hud.has_method("set_between_point_active"):
		between_point_controller.active_changed.connect(hud.set_between_point_active)
	if hud.has_signal("skip_retrieval_requested"):
		hud.skip_retrieval_requested.connect(between_point_controller.skip)


	game_trajectory = _GameTrajectory.new()
	add_child(game_trajectory)
	game_trajectory.setup(self, ball)


	game_shots = _GameShots.new()
	add_child(game_shots)
	game_shots.setup(ball, player_left, player_right, scoreboard_ui)
	game_shots.cleanup()

	if not RuntimePolicy.developer_tools:
		return


	game_drop_test = load("res://scripts/debug/game_drop_test.gd").new()
	add_child(game_drop_test)
	game_drop_test.setup(ball)
	game_drop_test.test_complete.connect(_on_drop_test_complete)


	game_debug_ui = load("res://scripts/game_debug_ui.gd").new()
	add_child(game_debug_ui)
	game_debug_ui.setup(player_left, player_right, scoreboard_ui, rally_scorer, ball, 
		serve_charge_time, ai_difficulty, serve_aim_offset_x, trajectory_arc_offset)


	game_sound_tune = load("res://scripts/game_sound_tune.gd").new()
	add_child(game_sound_tune)
	game_sound_tune.setup(ball.audio_synth, scoreboard_ui, hud)
	game_sound_tune._create_sound_tune_panel(hud)




func _update_waiting_ui() -> void :
	if practice_launcher and practice_launcher.is_active:
		practice_launcher._set_status("Hold to serve into the diagonal box")
		return

	if game_state == 0:
		var serve_call: String = _format_serve_call()
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [serve_call, game_trajectory.get_aim_label(), game_trajectory.get_arc_label()])




func _wire_settings() -> void :
	var s: Node = get_node_or_null("/root/Settings")
	if s == null:
		return
	_apply_setting("video.camera_mode", s.call("get_value", "video.camera_mode", 0))
	_apply_setting("video.fov", s.call("get_value", "video.fov", 60.0))
	for style_key in preload("res://scripts/ai_playing_styles.gd").SETTINGS.values():
		_apply_setting(style_key, s.call("get_value", style_key))
	_apply_setting("gameplay.difficulty", s.call("get_value", "gameplay.difficulty", 0))
	_apply_setting("gameplay.reaction_delay", s.call("get_value", "gameplay.reaction_delay", 0.0))
	_apply_setting("video.shadow_quality", s.call("get_value", "video.shadow_quality", 1))
	if s.has_signal("settings_changed") and not s.settings_changed.is_connected(_apply_setting):
		s.settings_changed.connect(_apply_setting)

func _apply_setting(key: String, value: Variant) -> void :
	var styles = preload("res://scripts/ai_playing_styles.gd")
	for actor_id in styles.SETTINGS:
		if key == styles.SETTINGS[actor_id]:
			var actor = get_player_by_actor_id(actor_id)
			if actor != null and actor.is_ai: actor.ai_brain.set_playing_style(int(value))
			return
	match key:
		"video.camera_mode":
			if camera_rig != null: camera_rig.set_gameplay_camera_mode(int(value))
		"video.fov":
			if camera_rig != null:
				camera_rig.set_fov(float(value))
		"gameplay.difficulty":
			var d: int = clampi(int(value), 0, 2)
			if d != ai_difficulty:
				ai_difficulty = d
				if scoreboard_ui != null:
					scoreboard_ui.update_difficulty(ai_difficulty)
			for actor in get_players():
				if actor.is_ai and actor.ai_brain != null: actor.ai_brain.ai_difficulty = ai_difficulty
		"gameplay.reaction_delay":
			for actor in get_players():
				if actor.is_ai and actor.ai_brain != null: actor.ai_brain.extra_reaction_delay = clampf(float(value), 0.0, 0.5)
		"video.shadow_quality":
			var sun: DirectionalLight3D = get_node_or_null("Sun")
			if sun != null:
				sun.shadow_enabled = int(value) > 0




func _setup_camera_rig() -> void :
	camera_rig = CameraRigScript.new()
	main_camera = camera_rig.setup(self, player_left, player_right, ball, Callable(self, "_is_practice"))

func _setup_hit_feedback() -> void :
	var HitFeedbackScript = preload("res://scripts/fx/hit_feedback.gd")
	var hf: Node = HitFeedbackScript.new()
	hf.name = "HitFeedback"
	add_child(hf)
	hf.call("setup", ball, camera_rig, get_players())

	var BallTrailScript = preload("res://scripts/fx/ball_trail.gd")
	var trail: MeshInstance3D = BallTrailScript.new()
	add_child(trail)
	trail.call("setup", ball)




func _create_ui() -> void :
	var HudScript = preload("res://scripts/ui/hud.gd")
	hud = HudScript.new()
	add_child(hud)
	hud.pose_editor_requested.connect(_toggle_posture_editor_v2)
	hud.pause_requested.connect( func(): PauseController.open())

	if scoreboard_ui:
		scoreboard_ui.setup(hud)
		scoreboard_ui.update_difficulty(ai_difficulty)
		scoreboard_ui.update_score(score_left, score_right)
		_update_spin_selection_ui()

	var canvas: CanvasLayer = hud


	reaction_button = _ReactionHitButton.new()
	reaction_button.name = "ReactionHitButton"
	reaction_button.anchor_left = 1.0
	reaction_button.anchor_right = 1.0
	reaction_button.anchor_top = 1.0
	reaction_button.anchor_bottom = 1.0
	reaction_button.offset_left = -268.0
	reaction_button.offset_right = -20.0
	reaction_button.offset_top = -268.0
	reaction_button.offset_bottom = -20.0
	canvas.add_child(reaction_button)
	if player_left and player_left.posture:
		player_left.posture.incoming_stage_changed.connect(_on_player_stage_changed)
		player_left.posture.grade_flashed.connect(_on_player_grade_flashed)
	reaction_button.auto_fire_requested.connect(_on_reaction_auto_fire)

	if not RuntimePolicy.developer_tools:
		return


	posture_editor_ui = load("res://scripts/posture_editor_ui.gd").new()
	posture_editor_ui.name = "PostureEditorUI"
	posture_editor_ui.visible = false
	posture_editor_ui.editor_opened.connect(_on_editor_opened)
	posture_editor_ui.editor_closed.connect(_on_editor_closed)
	canvas.add_child(posture_editor_ui)





	posture_editor_v2 = load("res://scripts/posture_editor_v2.gd").new()
	posture_editor_v2.name = "PostureEditorV2"
	posture_editor_v2.editor_opened.connect(_on_editor_v2_opened)
	posture_editor_v2.editor_closed.connect(_on_editor_v2_closed)
	canvas.add_child(posture_editor_v2)
	if player_left:
		posture_editor_v2.set_player(player_left)
	if camera_rig != null:
		camera_rig.is_mouse_over_editor_ui_cb = Callable(posture_editor_v2, "contains_screen_point")
		posture_editor_v2.set_camera_rig(camera_rig)



	_transport_bar = posture_editor_ui.build_transport_bar()
	_transport_bar.visible = false
	canvas.add_child(_transport_bar)




func _set_game_state(new_state: GameState) -> void :
	if new_state == game_state:
		return
	if RuntimePolicy.developer_tools: print("[STATE] %s -> %s" % [GameState.keys()[game_state], GameState.keys()[new_state]])
	game_state = new_state
	if ball and ball.has_method("refresh_scene_contact_owner"): ball.refresh_scene_contact_owner()
	if movement_guide and new_state != GameState.PLAYING: movement_guide.cancel()
	if aim_focus and new_state not in [GameState.WAITING, GameState.PLAYING]: aim_focus.cancel()
	if new_state == GameState.POINT_SCORED and aim_controller: aim_controller.reset()
	if practice_launcher and practice_launcher.is_wall():
		rally_scorer.cancel_rally()
		set_ai_movement_for_roster(false)
		return
	if rally_scorer:
		if new_state == GameState.PLAYING:
			var from_right: bool = get_server_logical_court() == 0
			rally_scorer.start_rally(serving_team, from_right)
			set_ai_movement_for_roster(true)
		elif new_state != GameState.PLAYING and new_state != GameState.SERVING:
			rally_scorer.end_rally()




func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("game.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	if team_coordination != null: team_coordination.begin_physics_frame(delta)
	if _tool_state_active():
		if camera_rig and posture_editor_v2 and posture_editor_v2.visible:
			camera_rig.update(delta)
		return

	if _in_slow_mo and game_state != GameState.PLAYING:
		_exit_slow_mo()
		if reaction_button:
			reaction_button.enter_idle()


	if hud.debug_mode and Input.is_key_pressed(KEY_T) and not _t_was_pressed:
		_t_was_pressed = true
		if game_drop_test and not game_drop_test.is_active():
			game_drop_test.start()
	if not Input.is_key_pressed(KEY_T):
		_t_was_pressed = false


	if game_serve.is_charging():



		if not (human_may_serve() and input_handler and input_handler.serve_is_charging):
			game_serve.tick_charge(delta)
		serve_charge_time = game_serve.get_charge_ratio() * MAX_SERVE_CHARGE_TIME
		serve_is_charging = true
	else:
		serve_is_charging = false


	game_trajectory.update(game_state, serving_team, serve_aim_offset_x, trajectory_arc_offset, 
		serve_charge_time, player_left.global_position, player_right.global_position)


	var _shot_type: String = game_shots.update(game_state, ball, serve_charge_time, player_left, player_right)


	if game_debug_ui:
		game_debug_ui.update_refs(serve_charge_time, ai_difficulty, serve_aim_offset_x, trajectory_arc_offset)
		game_debug_ui.update(game_state, ball, player_left, player_right)


	if game_drop_test and game_drop_test.is_active():
		game_drop_test.tick()


	if camera_rig != null:
		if posture_editor_v2 and posture_editor_v2.visible and player_left:
			camera_rig.editor_focus_point = player_left.global_position
		elif posture_editor_ui and posture_editor_ui.visible:
			camera_rig.editor_focus_point = posture_editor_ui.get_current_paddle_position()
		else:
			camera_rig.editor_focus_point = Vector3.INF
		camera_rig.update(delta)


	if game_state == GameState.WAITING and (game_drop_test == null or not game_drop_test.is_active()):
		_update_held_ball_position()

		if server_is_ai() and not _point_transition_blocks_attempt():
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




func _format_scoreboard() -> String:
	var arrow_left: String = "▶ " if serving_team == 0 else "  "
	var arrow_right: String = " ◀" if serving_team == 1 else "  "
	return "%s%d  -  %d%s" % [arrow_left, score_left, score_right, arrow_right]

func _format_serve_call() -> String:
	if doubles_mode and doubles_state != null:
		var server = get_server_actor()
		var label: String = actor_label(server)
		return "%s serves · %s" % [label, doubles_state.score_call()]
	if serving_team == 0:
		return "Blue serves: %d - %d" % [score_left, score_right]
	else:
		return "Red serves: %d - %d" % [score_right, score_left]




func _on_player_stage_changed(stage: int, posture: int, commit_dist: float, ball2ghost: float, ttc: float) -> void :
	if _tool_state_active():
		return
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

func _on_player_grade_flashed(grade: String) -> void :
	if reaction_button:
		reaction_button.show_grade(grade)
	if RuntimePolicy.developer_tools: print("[REACT] grade=%s" % grade)

func _on_reaction_auto_fire() -> void :
	if game_state == GameState.PLAYING and not input_handler.serve_is_charging:
		_perform_player_swing(1.0)

func _enter_slow_mo() -> void :
	if _in_slow_mo:
		return
	_in_slow_mo = true
	TimeScale.request_slowmo("reaction", 0.55)

func _exit_slow_mo() -> void :
	if _in_slow_mo:
		_in_slow_mo = false
		TimeScale.release("reaction")




func _on_player_swing_press() -> void :
	if _point_transition_blocks_attempt(): return
	if aim_focus: aim_focus.begin_hold()
	if game_state == GameState.WAITING:
		game_serve.start_charge()
		return
	if game_state != GameState.PLAYING:
		return
	var human = player_left.posture.human_contact
	if human != null and human.phase >= 0:
		return

	if human != null: human.begin_held_hit()
	_pending_auto_shot_type = game_shots._classify_intended_shot(ball, player_left)
	_pending_shot_type = "DROP" if selected_shot_intent == "DROP" else _pending_auto_shot_type
	scoreboard_ui.show_shot_type(_pending_shot_type)
	if RuntimePolicy.developer_tools: print("[Shot] Blue intent: %s" % _pending_shot_type)

func _deactivate_reaction_button() -> void :
	if reaction_button:
		reaction_button.enter_idle()
	_exit_slow_mo()

func _on_player_swing_release(charge_ratio: float) -> void :
	if _point_transition_blocks_attempt(): return
	if aim_focus: aim_focus.end_hold()
	game_trajectory.clear()
	if game_state == GameState.WAITING:
		game_serve.release(charge_ratio)
		serve_charge_time = 0.0
	elif game_state == GameState.PLAYING:
		_perform_player_swing(charge_ratio)
	_deactivate_reaction_button()




func _perform_serve(charge_ratio: float) -> void :
	if _point_transition_blocks_attempt(): return
	game_serve.perform_serve(charge_ratio)

func _on_serve_launched(_team: int) -> void :
	_set_game_state(GameState.PLAYING)




func _update_charge_ui(charge_ratio: float, pose_already_presented: bool = false) -> void :
	if _point_transition_blocks_attempt(): return
	if game_state == GameState.WAITING:
		if human_may_serve() and input_handler and input_handler.serve_is_charging and game_serve.is_charging():


			var desired_time: float = clampf(charge_ratio, 0.0, 1.0) * MAX_SERVE_CHARGE_TIME
			var current_time: float = game_serve.get_charge_ratio() * MAX_SERVE_CHARGE_TIME
			game_serve.tick_charge(maxf(0.0, desired_time - current_time), not pose_already_presented)
			serve_charge_time = desired_time
			serve_is_charging = true
		else:
			game_serve._update_charge_ui(charge_ratio)
	elif game_state == GameState.PLAYING:
		var human = player_left.posture.human_contact
		if human != null and not human.preparation_contact().is_empty() and _pending_auto_shot_type != "RETURN":
			var predicted_type: String = game_shots._classify_intended_shot(ball, player_left)
			if predicted_type != _pending_auto_shot_type:
				_pending_auto_shot_type = predicted_type
				_pending_shot_type = "DROP" if selected_shot_intent == "DROP" else predicted_type
				scoreboard_ui.show_shot_type(_pending_shot_type)
		var charge_label: String = "Drop touch" if selected_shot_intent == "DROP" else "Power"
		var preparation_status: String = human.preparation_status_text() if human != null else ""
		if not preparation_status.is_empty():


			scoreboard_ui.set_state_text(preparation_status if hud._portrait else "%s · %s: %d%%\nRelease SPACE to queue" % [preparation_status, charge_label, roundi(charge_ratio * 100)])
		else:
			scoreboard_ui.set_state_text("Move into paddle reach" if hud._portrait else "Move into reach of the incoming ball\n%s: %d%%" % [charge_label, roundi(charge_ratio * 100)])

func _perform_player_swing(charge_ratio: float) -> void :
	if _point_transition_blocks_attempt(): return
	var driver = player_left.special_reach_driver
	if driver != null and driver.owns_presentation(): return
	if selected_movement_intent == "DIVE" and not dive_actions_enabled:
		selected_movement_intent = "AUTO"
		scoreboard_ui.set_state_text("Dive is not available")
		return
	if selected_movement_intent in ["REACH", "DIVE"]:
		var chosen: String = selected_movement_intent
		selected_movement_intent = "AUTO"
		var intent := {"target": aim_controller.get_target(), "charge": charge_ratio,
			"spin_mode": selected_spin_mode, "aim_mode": selected_shot_intent,
			"shot_intent": "GROUNDSTROKE", "arc": trajectory_arc_offset}
		commit_execution_settings(player_left)
		if driver != null and driver.request_activation(chosen, charge_ratio, intent):
			scoreboard_ui.set_state_text("Grounded reach" if chosen == "REACH" else "Dive save")
		else:
			player_left.hitting.clear_charge_visual()
			scoreboard_ui.set_state_text("No safe reach window" if chosen == "REACH" else "No safe dive window")
		return
	var human = player_left.posture.human_contact
	if human != null and human.phase >= 0: return
	commit_execution_settings(player_left)
	if _pending_auto_shot_type != "RETURN" and human != null and not human.preparation_contact().is_empty():
		_pending_auto_shot_type = game_shots._classify_intended_shot(ball, player_left)
	_pending_shot_type = "DROP" if selected_shot_intent == "DROP" else _pending_auto_shot_type
	# Capture the chosen shot before a failed ordinary preparation clears its
	# held-input state. Automatic extension is a fallback, never a second swing.
	var reach_intent := {"target": aim_controller.get_target(), "charge": charge_ratio,
		"spin_mode": selected_spin_mode, "aim_mode": selected_shot_intent,
		"shot_intent": "GROUNDSTROKE", "arc": trajectory_arc_offset}
	if human == null or not human.request_swing(charge_ratio):
		if selected_movement_intent == "AUTO" and driver != null and driver.maybe_start_reach(charge_ratio, reach_intent):
			scoreboard_ui.set_state_text("Grounded reach")
			return
		player_left.hitting.clear_charge_visual()
		scoreboard_ui.set_state_text("Move into reach of the incoming ball")
	else:
		var prepared: PostureDefinition = human.preparation_contact().def
		scoreboard_ui.set_state_text("Swing queued · %s" % prepared.display_name)

func commit_execution_settings(actor) -> void:
	var difficulty: int = clampi(int(Settings.get_value("gameplay.difficulty", 0)), 0, 2)
	_execution_commits[actor.get_actor_id()] = {"flight_id": ball.flight_id,
		"perfect": int(Settings.get_value("gameplay.execution_accuracy", 1)) == 0,
		"skill_scale": [1.25, 1.0, 0.75][difficulty] if actor.is_ai else 1.0}

func apply_contact_execution(actor, launch: Dictionary, charge: float, timing_error_seconds: float = 0.0, serve: bool = false, certificate: Dictionary = {}) -> Dictionary:
	if launch.is_empty(): return launch
	var quality = preload("res://scripts/shot_contact_quality.gd")
	var model = preload("res://scripts/shot_execution_error.gd")
	var context: Dictionary = quality.capture(actor, ball, charge, timing_error_seconds, serve)
	var physical_paddle: Transform3D = actor.paddle_node.global_transform
	if not certificate.is_empty():
		if contact_authority == null or not contact_authority.validates_settlement(actor, certificate): return {}
		physical_paddle = certificate.paddle
		var local_surface: Vector3 = physical_paddle.affine_inverse() * Vector3(certificate.evidence.surface)
		var offset: Vector3 = local_surface - PaddleDimensions.HEAD_OFFSET
		var face_offset: float = Vector2(offset.x / PaddleDimensions.HEAD_RADIUS, offset.y / (PaddleDimensions.HEAD_LENGTH * .5)).length()
		context.surface_point = certificate.evidence.surface
		context.face_offset_normalized = face_offset; context.off_center = clampf(face_offset, 0.0, 1.0)
		context["geometry_source"] = "final_published_affine_toi"
		context["anatomy_source"] = "displayed_endpoint"
		context["contact_normal"] = certificate.evidence.normal
	var commit: Dictionary = _execution_commits.get(actor.get_actor_id(), {})
	if commit.is_empty() or int(commit.flight_id) != ball.flight_id:
		commit_execution_settings(actor)
		commit = _execution_commits[actor.get_actor_id()]
	context["perfect"] = commit.perfect
	context["skill_scale"] = commit.skill_scale
	var intended_velocity: Vector3 = launch.velocity
	var intended_omega: Vector3 = launch.omega
	var contact_quality := 1.0
	var head: Vector3 = physical_paddle * PaddleDimensions.HEAD_OFFSET
	var peripheral: bool = head.distance_to(ball.global_position) > preload("res://scripts/incoming_contact_planner.gd").IMPACT_DISTANCE
	if peripheral:
		contact_quality = shot_physics.compute_sweet_spot_speed(context.surface_point, head, intended_velocity)
		intended_velocity *= contact_quality
		intended_omega += shot_physics.compute_sweet_spot_spin(context.surface_point, head, intended_velocity)
	var rng_before: int = shot_physics.accuracy.rng.state
	var result: Dictionary = model.apply(intended_velocity, intended_omega, context, shot_physics.accuracy.rng)
	shot_physics.accuracy.samples += 1
	var actual: Dictionary = launch.duplicate(true)
	actual.profile = launch.get("profile", {}).duplicate(true)
	actual.profile["intended_velocity"] = launch.velocity
	actual.profile["intended_omega"] = launch.omega
	actual.profile["intended_landing"] = launch.get("landing", launch.get("target", Vector3.ZERO))
	actual.profile["contact_quality"] = contact_quality
	actual.profile["peripheral_contact"] = peripheral
	actual.profile["physical_preexecution_velocity"] = intended_velocity
	actual.profile["physical_preexecution_omega"] = intended_omega
	actual.profile["execution_context"] = context
	actual.profile["execution_error"] = result
	actual.profile["execution_rng_before"] = str(rng_before)
	actual.profile["execution_rng_after"] = str(shot_physics.accuracy.rng.state)
	actual.profile["accuracy_sample_index"] = shot_physics.accuracy.samples
	actual.profile["accuracy_intended_target"] = launch.get("target", Vector3.ZERO)
	actual.profile["accuracy_region_reliable"] = false
	actual.profile["accuracy_preview_estimate_only"] = true
	actual.velocity = result.velocity; actual.omega = result.omega
	actual["intended_landing"] = launch.get("landing", launch.get("target", Vector3.ZERO))
	# The old solver landing no longer predicts this perturbed launch. Keep it
	# explicitly intended; actual ball/net/floor integration decides the result.
	actual["intended_solution_feasible"] = launch.get("feasible", false)
	actual["intended_net_clear"] = launch.get("net_clear", false)
	for key in ["landing", "feasible", "net_clear", "net_y"]: actual.erase(key)
	return actual

func execution_preview_context(charge: float, serve: bool = false) -> Dictionary:
	var context: Dictionary = preload("res://scripts/shot_contact_quality.gd").capture(player_left, ball, charge, 0.0, serve)
	# The ball is not touching the current paddle during preparation. Never
	# treat its distance from the head as an actual off-center contact sample.
	context.off_center = 0.0
	context["perfect"] = int(Settings.get_value("gameplay.execution_accuracy", 1)) == 0
	context["skill_scale"] = 1.0
	return context

func _apply_special_reach_contact(driver, evidence: Dictionary = {}) -> bool:
	# The special driver owns only a certified displayed motion. This remains
	# the same legal physical-contact and shot-response boundary as a rally hit.
	if driver == null or not driver.active or not driver.contact_window_active: return false
	if game_state != GameState.PLAYING or get_tree().paused or ball == null or not ball.is_in_play or _tool_state_active(): return false
	var actor = driver.actor
	if actor not in get_players(): return false
	var planner = preload("res://scripts/incoming_contact_planner.gd")
	if not planner.legal_contact(actor, ball): return false
	var actual: Dictionary = driver.physical_contact_report()
	if not actual.get("valid", false) or not actual.get("finite_touch", false): return false
	if not preload("res://scripts/finite_paddle_contact.gd").touches(actor.paddle_node.global_transform, ball.global_position, ball.BALL_RADIUS): return false
	if contact_authority and not contact_authority.before_paddle(actor, evidence): return false
	var intent: Dictionary = driver.intent
	var target: Vector3 = intent.get("target", Vector3.INF)
	if not target.is_finite(): return false
	var charge: float = clampf(float(intent.get("charge", 0.25)), 0.0, 1.0)
	var mode: int = int(intent.get("spin_mode", 0))
	var aim_mode: String = str(intent.get("aim_mode", "AUTO"))
	var shot_kind: String = str(intent.get("shot_intent", "GROUNDSTROKE"))
	var launch: Dictionary = shot_physics.solve_aimed_launch(ball.global_position, target, charge, actor.court_side, mode, aim_mode, shot_kind, float(intent.get("arc", 0.0)), true)
	if launch.is_empty(): return false
	var timing_error: float = driver.helper.elapsed - float(driver.helper.plan.get("time", driver.helper.elapsed))
	launch = apply_contact_execution(actor, launch, charge, timing_error)
	launch.profile = launch.profile.duplicate(true)
	launch.profile["movement_action"] = driver.kind
	launch.profile["motion_profile"] = "LONG_REACH" if driver.kind == "REACH" else "EMERGENCY_DIVE"
	launch.profile["actual_contact_position"] = ball.global_position
	launch.profile["contact_stroke_serial"] = driver.stroke_serial
	ball.set_meta("aim_target", target)
	ball.set_meta("shot_profile", launch.profile)
	ball.suppress_paddle_collision(actor.paddle_node)
	ball.linear_velocity = launch.velocity
	ball.angular_velocity = launch.omega
	if actor.posture: actor.posture.notify_ball_hit()
	var recorded: bool = ball.hit_by_actor(actor) if ball.has_method("hit_by_actor") else ball.hit_by_player(actor.player_num)
	if not recorded: return false
	var event: Dictionary = ball.paddle_contact_context()
	actor.set_meta("legal_net_followthrough_flight", ball.flight_id)
	if contact_authority: contact_authority.note_paddle_contact(actor)
	actor.stamina.spend_contact(shot_kind, launch.velocity.length())
	last_shot_profile = launch.profile
	if actor.player_num == 0:
		clear_frozen_spin_selection()
		scoreboard_ui.show_speed(launch.velocity.length() * 2.23694)
		scoreboard_ui.show_shot_type("REACH SAVE" if driver.kind == "REACH" else "DIVE SAVE")
		scoreboard_ui.set_state_text("Rally!")
	else:
		actor.ai_brain.ai_hit_cooldown = actor.ai_brain.AI_HIT_COOLDOWN
	return ball.paddle_contact_is_current(event)

func _apply_player_contact_hit(charge_ratio: float, _contact_posture: int, spin_mode: int = -1, shot_intent: String = "", target_override: Vector3 = Vector3.INF) -> bool:
	if game_state != GameState.PLAYING or ball == null: return false
	var planner = preload("res://scripts/incoming_contact_planner.gd")
	if not planner.legal_contact(player_left, ball): return false
	var human = player_left.posture.human_contact
	if human == null or not human.owns_contact_window(ball): return false
	if not human.motion_context.is_empty() and ball.bounces_since_last_hit != int(human.motion_context.get("required_bounces", human.motion_context.get("bounces", ball.bounces_since_last_hit))): return false
	var paddle_pos: Vector3 = PaddleReach.head_world(player_left)
	var contact_error: float = paddle_pos.distance_to(ball.global_position)


	var geometry = preload("res://scripts/paddle_clearance.gd")
	if geometry.distance_to_head_shape(player_left.paddle_node.to_local(ball.global_position)) > ball.BALL_RADIUS + geometry.contact_surface_tolerance(): return false
	var pose: PostureDefinition = player_left.posture.transition_pose_blend
	if pose == null: pose = PostureLibrary.instance().get_def(_contact_posture)
	var actual_shoulder: Vector3 = WristReach.live_shoulder(player_left, pose)
	if paddle_pos.distance_to(actual_shoulder) > PaddleReach.MAX_HEAD_DISTANCE + 0.001: return false
	if not WristReach.fits(player_left.paddle_node.global_transform, pose, actual_shoulder, WristReach.link_budget(player_left, pose)): return false
	if contact_authority and not contact_authority.before_paddle(player_left, human.last_contact_evidence): return false

	var committed_mode: int = selected_spin_mode if spin_mode < 0 else spin_mode
	var committed_intent: String = selected_shot_intent if shot_intent.is_empty() else shot_intent


	var shot_target: Vector3 = aim_controller.get_target() if target_override == Vector3.INF else target_override
	var launch: Dictionary
	if practice_launcher and practice_launcher.is_wall():
		launch = practice_launcher.wall_practice.solve_launch(ball.global_position, shot_target, charge_ratio, committed_mode, committed_intent)
	elif practice_launcher and practice_launcher.is_exchange() and ( not practice_launcher.allow_attacks or practice_launcher.demo_enabled):
		launch = practice_launcher.solve_exchange_launch(ball.global_position, 0)
	else:
		launch = shot_physics.solve_aimed_launch(ball.global_position, shot_target,
			charge_ratio, player_left.court_side, committed_mode, committed_intent, str(human.motion_context.get("shot_type", _pending_shot_type)), float(human.motion_context.get("arc", trajectory_arc_offset)), true)
		if launch.is_empty(): return false
	if contact_error > planner.IMPACT_DISTANCE and practice_launcher and (practice_launcher.is_wall() or practice_launcher.is_exchange() and (not practice_launcher.allow_attacks or practice_launcher.demo_enabled)):
		var local_ball: Vector3 = player_left.paddle_node.to_local(ball.global_position)
		var local_incoming: Vector3 = player_left.paddle_node.global_basis.inverse() * ball.linear_velocity
		var surface_point: Vector3 = player_left.paddle_node.to_global(geometry.closest_head_surface(local_ball, local_incoming))
		var quality: float = shot_physics.compute_sweet_spot_speed(surface_point, paddle_pos, launch.velocity)
		launch.velocity *= quality
		launch.omega += shot_physics.compute_sweet_spot_spin(surface_point, paddle_pos, launch.velocity)

		launch.profile = launch.profile.duplicate()
		launch.profile["contact_quality"] = quality
		launch.profile["peripheral_contact"] = true
		launch.profile["accuracy_region_reliable"] = false
	if not (practice_launcher and (practice_launcher.is_wall() or practice_launcher.is_exchange() and (not practice_launcher.allow_attacks or practice_launcher.demo_enabled))):
		launch = apply_contact_execution(player_left, launch, charge_ratio, human.elapsed - human.strike_time)
	launch["profile"] = launch.profile.duplicate(true)
	launch.profile["motion_profile"] = str(human.motion_context.get("profile", "LEGACY"))
	_pending_shot_type = str(launch.profile.get("shot_type", _pending_shot_type))
	ball.set_meta("aim_target", launch.target)
	ball.suppress_paddle_collision(player_left.paddle_node)
	ball.linear_velocity = launch.velocity
	ball.angular_velocity = launch.omega
	last_shot_profile = launch.profile
	ball.set_meta("shot_profile", launch.profile)
	player_left.posture.notify_ball_hit()
	if not ball.hit_by_actor(player_left): return false
	var event: Dictionary = ball.paddle_contact_context()
	player_left.set_meta("legal_net_followthrough_flight", ball.flight_id)
	if contact_authority: contact_authority.note_paddle_contact(player_left)
	if player_left.erne_action.active: player_left.erne_action.notify_hit()
	player_left.stamina.spend_contact(_pending_shot_type, ball.linear_velocity.length())
	clear_frozen_spin_selection()
	scoreboard_ui.show_speed(ball.linear_velocity.length() * 2.23694)
	if _pending_shot_type != "":
		scoreboard_ui.show_shot_type(_pending_shot_type)
	else:
		scoreboard_ui.show_shot_type(game_shots._classify_trajectory(ball.linear_velocity))
	_pending_shot_type = ""
	_pending_auto_shot_type = ""
	scoreboard_ui.set_state_text(practice_launcher.status_text if practice_launcher and practice_launcher.is_active else "Rally!")
	player_left.posture.grade_flashed.emit(player_left.posture._commit_selector.grade_ball_to_ghost(contact_error))
	return ball.paddle_contact_is_current(event)

func settle_human_contact_intent(actor, intent: Dictionary, certificate: Dictionary) -> bool:
	if contact_authority == null or not contact_authority.validates_settlement(actor, certificate): return false
	var human = actor.posture.human_contact
	if human == null or not human.contact_intent_is_current(intent): return false
	if ball.bounces_since_last_hit != int(intent.motion_context.get("required_bounces", ball.bounces_since_last_hit)): return false
	var at_elapsed: float = float(intent.elapsed) - (1.0 - float(certificate.evidence.fraction)) * float(intent.control_seconds)
	if at_elapsed < 0.0 or at_elapsed > float(intent.strike_time) + .1: return false
	var charge_ratio: float = intent.charge_ratio
	var actual_paddle: Transform3D = certificate.paddle
	var paddle_pos: Vector3 = actual_paddle * preload("res://scripts/paddle_dimensions.gd").HEAD_OFFSET
	var contact_error: float = paddle_pos.distance_to(ball.global_position)
	var planner = preload("res://scripts/incoming_contact_planner.gd")
	var geometry = preload("res://scripts/paddle_clearance.gd")
	var committed_mode: int = int(intent.spin_mode)
	var committed_intent: String = str(intent.shot_intent)


	var shot_target: Vector3 = Vector3(intent.target)
	var launch: Dictionary
	if practice_launcher and practice_launcher.is_wall():
		launch = practice_launcher.wall_practice.solve_launch(ball.global_position, shot_target, charge_ratio, committed_mode, committed_intent)
	elif practice_launcher and practice_launcher.is_exchange() and ( not practice_launcher.allow_attacks or practice_launcher.demo_enabled):
		launch = practice_launcher.solve_exchange_launch(ball.global_position, 0)
	else:
		launch = shot_physics.solve_aimed_launch(ball.global_position, shot_target,
			charge_ratio, actor.court_side, committed_mode, committed_intent, str(intent.motion_context.get("shot_type", _pending_shot_type)), float(intent.motion_context.get("arc", trajectory_arc_offset)), true)
		if launch.is_empty(): return false
	if launch.is_empty() or not contact_authority.intended_velocity_leaves_surface(actor, certificate, launch.velocity, "authored"): return false
	if contact_error > planner.IMPACT_DISTANCE and practice_launcher and (practice_launcher.is_wall() or practice_launcher.is_exchange() and (not practice_launcher.allow_attacks or practice_launcher.demo_enabled)):
		var local_ball: Vector3 = actual_paddle.affine_inverse() * ball.global_position
		var local_incoming: Vector3 = actual_paddle.basis.inverse() * ball.linear_velocity
		var surface_point: Vector3 = Vector3(certificate.evidence.surface)
		var quality: float = shot_physics.compute_sweet_spot_speed(surface_point, paddle_pos, launch.velocity)
		launch.velocity *= quality
		launch.omega += shot_physics.compute_sweet_spot_spin(surface_point, paddle_pos, launch.velocity)

		launch.profile = launch.profile.duplicate()
		launch.profile["contact_quality"] = quality
		launch.profile["peripheral_contact"] = true
		launch.profile["accuracy_region_reliable"] = false
	if not (practice_launcher and (practice_launcher.is_wall() or practice_launcher.is_exchange() and (not practice_launcher.allow_attacks or practice_launcher.demo_enabled))):
		launch = apply_contact_execution(actor, launch, charge_ratio, float(intent.elapsed) - (1.0 - float(certificate.evidence.fraction)) * float(intent.control_seconds) - float(intent.strike_time), false, certificate)
	if not contact_authority.intended_velocity_leaves_surface(actor, certificate, launch.velocity, "executed"): return false
	launch["profile"] = launch.profile.duplicate(true)
	launch.profile["motion_profile"] = str(intent.motion_context.get("profile", "LEGACY"))
	_pending_shot_type = str(launch.profile.get("shot_type", _pending_shot_type))
	ball.set_meta("aim_target", launch.target)
	ball.suppress_paddle_collision(actor.paddle_node)
	ball.linear_velocity = launch.velocity
	ball.angular_velocity = launch.omega
	last_shot_profile = launch.profile
	ball.set_meta("shot_profile", launch.profile)
	actor.posture.notify_ball_hit()
	if not ball.hit_by_actor(actor): return false
	var event: Dictionary = ball.paddle_contact_context()
	actor.set_meta("legal_net_followthrough_flight", ball.flight_id)
	if actor.erne_action.active: actor.erne_action.notify_hit()
	actor.stamina.spend_contact(_pending_shot_type, ball.linear_velocity.length())
	clear_frozen_spin_selection()
	scoreboard_ui.show_speed(ball.linear_velocity.length() * 2.23694)
	if _pending_shot_type != "":
		scoreboard_ui.show_shot_type(_pending_shot_type)
	else:
		scoreboard_ui.show_shot_type(game_shots._classify_trajectory(ball.linear_velocity))
	_pending_shot_type = ""
	_pending_auto_shot_type = ""
	scoreboard_ui.set_state_text(practice_launcher.status_text if practice_launcher and practice_launcher.is_active else "Rally!")
	actor.posture.grade_flashed.emit(actor.posture._commit_selector.grade_ball_to_ghost(contact_error))
	return ball.paddle_contact_is_current(event)





func _check_rally() -> void :
	if ball.global_position.y < 0.1 and ball.linear_velocity.y < -1.0:
		ball_has_bounced = true
		scoreboard_ui.set_state_text("Ball bounced!")




func _on_rally_pending(_winner: int, reason: String, _detail: String) -> void:
	# The ball is dead; player recovery and landing must keep running so a
	# late NVZ momentum fault can still determine the point before scoring.
	ball.is_in_play = false
	if movement_guide: movement_guide.cancel()
	if aim_focus: aim_focus.cancel()
	if _in_slow_mo: _exit_slow_mo()
	var human = player_left.posture.human_contact if player_left != null and player_left.posture != null else null
	if human != null and human.phase < 2:
		human.cancel(false)
	set_ai_movement_for_roster(false)
	scoreboard_ui.set_state_text("Landing check · " + reason.replace("_", " "))

func _on_rally_ended(winner: int, reason: String, detail: String) -> void :
	if _is_practice():
		if practice_launcher: practice_launcher.finish_attempt(winner, reason, detail)
		return
	if game_state == GameState.POINT_SCORED or match_over:
		return


	var line_call: bool = reason == RallyScorer.FAULT_OUT_OF_BOUNDS and ball.last_hit_by in [0, 1] and ball.bounces_since_last_hit <= 1 and winner == 1 - ball.last_hit_by
	if not line_call: scoreboard_ui.show_fault(reason.replace("_", " "), detail)
	_on_point_scored(winner)

func _on_point_scored(winning_team: int) -> void :
	if _is_practice():
		if practice_launcher: practice_launcher.finish_attempt(winning_team, "FAULT", "Try the same shot again")
		return
	if game_state == GameState.POINT_SCORED or match_over or winning_team not in [0, 1]:
		return
	var side_out: bool = winning_team != serving_team
	if doubles_mode:
		var outcome: Dictionary = doubles_controller.settle_rally(winning_team)
		if not outcome.get("accepted", false):
			scoreboard_ui.set_state_text("Point settlement pending · " + str(outcome.get("reason", "service context")))
			return
		side_out = bool(outcome.side_out)
	var presentations: Array = between_point_controller.capture_presentations()
	_point_reset_generation += 1
	_set_game_state(GameState.POINT_SCORED)
	ball.is_in_play = false
	set_ai_movement_for_roster(false)
	ai_serve_timer = 0.0
	_last_volley_player = -1

	if doubles_mode:
		scoreboard_ui.update_score(score_left, score_right)
		scoreboard_ui.set_state_text(_format_serve_call())
	elif winning_team == serving_team:
		if winning_team == 0:
			score_left += 1
		else:
			score_right += 1
		scoreboard_ui.update_score(score_left, score_right)
		scoreboard_ui.set_state_text("Point! %d - %d" % [score_left, score_right])
	else:
		serving_team = winning_team
		scoreboard_ui.set_state_text("Sideout · %s serves" % hud.team_name(winning_team))

	if maxi(score_left, score_right) >= 11 and absi(score_left - score_right) >= 2:
		ball.freeze = true
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		match_over = true
		match_winner = 0 if score_left > score_right else 1
		_clear_finished_match_controls(presentations)
		scoreboard_ui.show_rally_result(winning_team, side_out, true)
		if court_audio: court_audio.play_point_cue(winning_team, side_out, true)
		scoreboard_ui.set_state_text("%s · %d - %d\nChoose Rematch to play again" % ["%s win%s!" % [hud.team_name(match_winner), "" if hud.team_name(match_winner) in ["You", "Opponents"] else "s"], score_left, score_right])
		return
	scoreboard_ui.show_rally_result(winning_team, side_out)
	if court_audio: court_audio.play_point_cue(winning_team, side_out, false)
	if not _try_fast_point_transition(): between_point_controller.begin(presentations)

func _clear_finished_match_controls(presentations: Array) -> void :



	if aim_focus: aim_focus.cancel()
	if movement_guide: movement_guide.cancel()
	_exit_slow_mo()
	TimeScale.release_all_slowmo()
	TimeScale.cancel_hitstop()
	game_serve.cleanup()
	input_handler.cancel_charge_input()
	if mobile_controls: mobile_controls.cancel_all()
	clear_frozen_spin_selection()
	for player in get_players():
		var actor_index: int = get_players().find(player)
		player.hitting.clear_charge_visual()
		if player.ai_brain:
			player.ai_brain.cancel_execution_commit()
			player.ai_brain.ai_is_charging = false
			player.ai_brain.ai_charge_time = 0.0
			player.ai_brain.ai_state = player.ai_brain.AIState.INTERCEPT_POSITION
			player.ai_brain.incoming_pose_override = null
			player.ai_brain.ai_reach_pose = null
			player.ai_brain._charge_reach_pose = null
		if actor_index < presentations.size() and presentations[actor_index].get("pose") != null:
			var pose: PostureDefinition = presentations[actor_index].pose
			player.posture.transition_pose_blend = pose
			if player.posture.human_contact:
				player.posture.human_contact.visual_pose = pose

func get_server_score(team: int = -1) -> int:
	var selected_team: int = serving_team if team < 0 else team
	return score_left if selected_team == 0 else score_right

# True when the human has changed ends and plays from the far (-z) end. The
# camera rig turns half a turn and screen-relative input is turned with it.
func view_flipped() -> bool:
	return doubles_mode and player_left != null and player_left.court_side == 1

func _point_transition_blocks_attempt() -> bool:
	return _fast_point_transition != null and _fast_point_transition.blocks_attempt()

func _point_transition_blocks_movement() -> bool:
	return _fast_point_transition != null and _fast_point_transition.blocks_movement()

func _try_fast_point_transition() -> bool:
	# Sample customization only at the accepted finalized-point boundary.
	if int(Settings.get_value("gameplay.point_transition")) != 1: return false
	if _fast_point_transition == null:
		_fast_point_transition = load("res://scripts/fast_point_transition.gd").new()
		add_child(_fast_point_transition)
		_fast_point_transition.setup(self)
	return _fast_point_transition.begin()

func request_fast_point_reset(expected_generation: int) -> bool:
	if _fast_point_transition == null or not _fast_point_transition.can_reset(expected_generation): return false
	_reset_ball(false, expected_generation)
	return _fast_point_transition.active and _point_reset_generation == expected_generation + 1 and game_state == GameState.WAITING

func request_rematch() -> void :
	if not match_over or _is_practice(): return
	_reset_match()

func _reset_ball(preserve_positions: bool = false, quick_generation: int = -1) -> void :
	if _fast_point_transition != null: _fast_point_transition.observe_reset_request(quick_generation)
	_execution_commits.clear()
	if rally_scorer: rally_scorer.cancel_rally()
	if doubles_mode and not preserve_positions: doubles_controller.cancel_rally()
	selected_movement_intent = "AUTO"
	for player in get_players():
		if player.ai_brain: player.ai_brain.cancel_execution_commit()
		if player.erne_action: player.erne_action.reset()
		if player.special_reach_driver: player.special_reach_driver.reset()
	scoreboard_ui.clear_rally_result()
	# A reset starts a new rally/drill context; dismiss the previous fault and timer.
	scoreboard_ui.clear_fault()
	if movement_guide: movement_guide.cancel()
	if aim_focus: aim_focus.cancel()
	if court_audio and court_audio.has_method("reset_contacts"): court_audio.reset_contacts()
	var handover_position: Vector3 = ball.global_position
	if between_point_controller: between_point_controller.cancel()
	_point_reset_generation += 1
	game_serve.cleanup()
	if get("mobile_controls") and mobile_controls.has_method("cancel_all"):
		mobile_controls.cancel_all()
	if input_handler and input_handler.has_method("cancel_charge_input"):
		input_handler.cancel_charge_input()
	if aim_controller: aim_controller.reset()
	_pending_shot_type = ""
	_pending_auto_shot_type = ""
	clear_frozen_spin_selection()
	ball.freeze = false
	ball.set_time_frozen(false)
	ball.reset()
	ball.reset_rally_state()
	if contact_authority: contact_authority.reset()
	ball_has_bounced = false
	_set_game_state(GameState.WAITING)
	serve_charge_time = 0.0
	serve_is_charging = false
	serve_aim_offset_x = 0.0
	trajectory_arc_offset = 0.0
	ai_serve_timer = 0.0
	_service_fault_triggered = false
	_serve_was_hit = false
	game_shots.cleanup()
	game_trajectory.clear()
	var trail = get_node_or_null("BallTrail")
	if trail: trail.reset()
	if not preserve_positions: _reset_player_positions()
	if player_left and player_left.posture:
		player_left.posture.reset_incoming_highlight()
	if player_left and player_left.hitting:
		player_left.hitting.clear_charge_visual()
	if player_right and player_right.posture:
		player_right.posture.reset_incoming_highlight()
	if player_right and player_right.hitting:
		player_right.hitting.clear_charge_visual()
	set_ai_movement_for_roster(false)
	if preserve_positions and game_serve.has_method("accept_handover"):
		game_serve.accept_handover(handover_position)



	for player in get_players():
		player._between_pose_active = false
		player._between_last_pose = null
		player._ai_guard_active = false
		player._ai_incoming_active = false
		if player.ai_brain: player.ai_brain.incoming_pose_override = null
		if not preserve_positions:
			player.leg_ik.feet_initialized = false
			if player.has_meta("carried_cup_continuity"): player.remove_meta("carried_cup_continuity")
		var ready: PostureDefinition = PostureLibrary.instance().get_def(player.PaddlePosture.READY)
		if player == get_server_actor():
			game_serve._prepare_server(0.0)
			ready = player.posture.transition_pose_blend
		else:
			player.posture.transition_pose_blend = ready
			player.posture.force_posture_update(ready)
		if player.posture.human_contact: player.posture.human_contact.visual_pose = ready
	_update_held_ball_position()
	scoreboard_ui.hide_out()
	var serve_call: String = _format_serve_call()
	if serving_team == 0:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [serve_call, game_trajectory.get_aim_label(), game_trajectory.get_arc_label()])
	else:
		scoreboard_ui.set_state_text("%s..." % serve_call)

func _reset_match() -> void :
	for actor in get_players(): actor.stamina.reset_match()
	if doubles_mode:
		doubles_controller.restart()
		for actor in get_players(): actor.configure_identity(actor.actor_id, actor.team_id, 0 if doubles_state.court_ends[actor.team_id] == 1 else 1)
	match_over = false
	match_winner = -1
	score_left = 0
	score_right = 0
	serving_team = 0
	scoreboard_ui.update_score(score_left, score_right)
	_reset_ball()

func _reset_player_positions() -> void :
	if doubles_mode and doubles_controller != null:
		for actor in get_players():
			actor.global_position = doubles_controller.reset_spawn_position(actor)
			actor.reset_physics_interpolation()
			actor.velocity = Vector3.ZERO
			actor.current_velocity = Vector3.ZERO
			actor.cancel_contextual_jump()
			actor.vertical_velocity = 0.0
			actor.is_jumping = false
			actor.jump_landing_remaining = 0.0
			actor._jump_was_airborne = false
			actor._jump_position_initialized = false
		return
	var server_score: int = get_server_score()
	var serve_from_right: bool = (server_score % 2) == 0
	var blue_x: float = 1.5 if serve_from_right else -1.5
	player_left.global_position = Vector3(blue_x, 1.0, SERVE_RESET_DEPTH)
	var red_x: float = -1.5 if serve_from_right else 1.5
	player_right.global_position = Vector3(red_x, 1.0, -SERVE_RESET_DEPTH)
	player_left.reset_physics_interpolation(); player_right.reset_physics_interpolation()
	for player in get_players():
		player.velocity = Vector3.ZERO
		player.current_velocity = Vector3.ZERO
		player.cancel_contextual_jump()
		player.vertical_velocity = 0.0
		player.is_jumping = false
		player.jump_landing_remaining = 0.0
		player._jump_was_airborne = false
		player._jump_position_initialized = false
	if RuntimePolicy.developer_tools: print("[SPAWN] score=", server_score, " serve_from_right=", serve_from_right, 
		" Blue@X=", blue_x, " Red@X=", red_x)

func _update_held_ball_position() -> void :
	if ball == null:
		return
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = game_serve.get_held_ball_position()




func _on_any_paddle_hit(_player_num: int) -> void :
	if game_state != GameState.PLAYING:
		return
	if ball != null:
		scoreboard_ui.show_speed(ball.linear_velocity.length() * 2.23694)
		scoreboard_ui.show_shot_type(game_shots._classify_trajectory(ball.linear_velocity))

func _on_ball_bounced(bounce_pos: Vector3) -> void :
	if game_state == GameState.SERVING and game_serve.is_release_pending() and not ball.is_in_play: return
	_spawn_bounce_spot(bounce_pos)
	if between_point_controller and between_point_controller.is_active(): return
	ball.record_bounce_side(bounce_pos.z)
	if practice_launcher and practice_launcher.is_wall(): return
	# Every actor observes the actual bounce; court-side filtering belongs to
	# Player.notify_ball_bounced so team identity survives an end change.
	for actor in get_players():
		actor.notify_ball_bounced(bounce_pos)
	game_shots.on_ball_bounced(bounce_pos)




func _set_debug_visuals_visible_deferred(v: bool) -> void :
	_set_debug_visuals_visible(v)

func _set_debug_visuals_visible(v: bool) -> void :
	if not RuntimePolicy.developer_tools: v = false
	if ball and ball.has_method("set_spin_debug_visible"): ball.set_spin_debug_visible(v)
	if game_debug_ui: game_debug_ui.set_debug_visible(v)
	if not v:
		_set_debug_zones_visible(false)
	if scoreboard_ui:
		scoreboard_ui.set_debug_visuals_active(v)
	if RuntimePolicy.developer_tools: print("[DEBUG] visuals ", "ON" if v else "OFF")

func _set_debug_zones_visible(v: bool) -> void :
	var dz_node: Node = find_child("DebugZones", true, false)
	if dz_node:
		dz_node.visible = v



func _cycle_debug_visuals() -> void :

	if game_debug_ui and game_debug_ui.has_method("cycle_debug_visuals"):
		game_debug_ui.cycle_debug_visuals()

func _toggle_intent_indicators() -> void :

	if game_debug_ui and game_debug_ui.has_method("toggle_intent_indicators"):
		game_debug_ui.toggle_intent_indicators()

func _cycle_difficulty() -> void :

	if game_debug_ui and game_debug_ui.has_method("cycle_difficulty"):
		game_debug_ui.cycle_difficulty()

func _start_drop_test() -> void :

	if game_drop_test and game_drop_test.has_method("start"):
		game_drop_test.start()

func is_ball_frozen() -> bool:
	return _ball_frozen

func _toggle_ball_freeze() -> void :
	if game_serve and game_serve.is_release_pending():
		game_serve.cleanup()
	_ball_frozen = not _ball_frozen
	if _ball_frozen:
		if RuntimePolicy.developer_tools: print("[FREEZE] Ball frozen")
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
		if RuntimePolicy.developer_tools: print("[FREEZE] Ball unfrozen")
		if ball:
			ball.set_time_frozen(false)
		_frozen_trajectory_points.clear()
		if hud and hud.get("freeze_indicator"):
			hud.freeze_indicator.visible = false

func _feed_frozen_trajectory() -> void :
	for p in [player_left, player_right]:
		if p and p.posture:
			p.posture.set_trajectory_points(_frozen_trajectory_points.duplicate())
		if p and p.awareness_grid:
			p.awareness_grid.set_trajectory_points(_frozen_trajectory_points.duplicate())

func _refresh_sound_tune_panel() -> void :

	if game_sound_tune and game_sound_tune.has_method("_refresh_sound_tune_panel"):
		game_sound_tune._refresh_sound_tune_panel()

func _print_sound_tunings() -> void :
	if ball and ball.has_method("get_sound_tunings"):
		var tunings: Dictionary = ball.get_sound_tunings()
		if RuntimePolicy.developer_tools: print("[SOUND TUNINGS] ", tunings)



func _toggle_posture_editor() -> void :
	if posture_editor_ui == null:
		push_warning("[POSTURE EDITOR] posture_editor_ui is null — editor not initialized")
		return
	var was_visible = posture_editor_ui.visible
	posture_editor_ui.visible = not was_visible
	if not was_visible:
		_on_editor_opened()
		if RuntimePolicy.developer_tools: print("[POSTURE EDITOR] ON")
	else:
		_on_editor_closed()
		if RuntimePolicy.developer_tools: print("[POSTURE EDITOR] OFF")

func _toggle_posture_editor_v2() -> void :
	if posture_editor_v2 == null:
		push_warning("[POSTURE EDITOR V2] posture_editor_v2 is null — editor not initialized")
		return
	if not posture_editor_v2.visible and game_sound_tune.sound_tune_panel.visible:
		_toggle_sound_panel()
	posture_editor_v2.toggle()
	if posture_editor_v2.visible:
		if RuntimePolicy.developer_tools: print("[POSTURE EDITOR V2] ON")
	else:
		if RuntimePolicy.developer_tools: print("[POSTURE EDITOR V2] OFF")

func _on_editor_v2_opened() -> void :
	_suspend_tool_gameplay()
	if scoreboard_ui:
		scoreboard_ui.hide_all_hud()
	if reaction_button:
		reaction_button.hide()
	if _transport_bar:
		_transport_bar.hide()
	if camera_rig != null and player_left != null:
		camera_rig.begin_editor_view(player_left)

	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(true)

func _on_editor_v2_closed() -> void :
	_resume_tool_gameplay()
	if scoreboard_ui:
		scoreboard_ui.show_all_hud()
		scoreboard_ui.set_debug_visuals_active(debug_visuals_visible)
	if reaction_button and ai_difficulty == 0:
		reaction_button.enter_idle()
	if camera_rig != null:
		camera_rig.end_editor_view()

	if player_left and player_left.posture:
		player_left.posture.set_ghosts_visible(debug_visuals_visible)

var _editor_previous_camera_mode: int = 0
var _editor_previous_camera_pos: Vector3 = Vector3.ZERO
var _editor_previous_camera_rot: Vector3 = Vector3.ZERO
var _editor_previous_window_mode: int = Window.MODE_WINDOWED
var _editor_previous_window_size: Vector2i = Vector2i.ZERO
var _editor_previous_window_position: Vector2i = Vector2i.ZERO
var _editor_window_geometry_saved: bool = false

func _expand_window_for_editor() -> void :
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

func _restore_window_after_editor() -> void :
	var window: Window = get_window()
	if window == null:
		return
	window.mode = _editor_previous_window_mode as Window.Mode
	if not _editor_window_geometry_saved:
		return
	window.size = _editor_previous_window_size
	window.position = _editor_previous_window_position
	_editor_window_geometry_saved = false

func _on_editor_opened() -> void :
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
		if RuntimePolicy.developer_tools: print("[EDITOR] Camera adjusted for editing")

func _on_editor_closed() -> void :
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
		if RuntimePolicy.developer_tools: print("[EDITOR] Camera restored")




func _simulate_shot_trajectory(start_pos: Vector3, vel: Vector3, omega: Vector3, grav: float, target_z: float, net_sign: float) -> Dictionary:
	return shot_physics.simulate_shot_trajectory(start_pos, vel, omega, grav, target_z, net_sign)

func compute_shot_velocity(ball_pos: Vector3, charge_ratio: float, player_num: int, shot_type: String) -> Vector3:
	return shot_physics.compute_shot_velocity(ball_pos, charge_ratio, player_num, shot_type, ai_difficulty)

func solve_ai_launch(ball_pos: Vector3, charge: float, posture: int, paddle_pos: Vector3,
		paddle_velocity: Vector3, transfer: float, actor = null) -> Dictionary:
	if actor == null: actor = player_right
	if actor not in get_players() or actor.ai_brain == null: return {}
	if practice_launcher and practice_launcher.is_exchange():
		if not practice_launcher.allow_attacks or practice_launcher.demo_enabled:
			return practice_launcher.solve_exchange_launch(ball_pos, actor.team_id)
		return actor.ai_brain.solve_practice_launch(ball_pos)
	return actor.ai_brain.solve_match_launch(ball_pos)

func compute_shot_spin(shot_type: String, vel: Vector3, charge_ratio: float, player_num: int, posture: int = -1) -> Vector3:
	return shot_physics.compute_shot_spin(shot_type, vel, charge_ratio, player_num, posture)

func compute_sweet_spot_spin(ball_pos: Vector3, paddle_center: Vector3, shot_vel: Vector3) -> Vector3:
	return shot_physics.compute_sweet_spot_spin(ball_pos, paddle_center, shot_vel)

func compute_sweet_spot_speed(ball_pos: Vector3, paddle_center: Vector3, shot_vel: Vector3) -> float:
	return shot_physics.compute_sweet_spot_speed(ball_pos, paddle_center, shot_vel)




func _spawn_bounce_spot(spot_pos: Vector3) -> void :
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




func _on_drop_test_complete() -> void :
	pass

func _exit_tree() -> void :







	if _court_helper != null:
		_court_helper.free()
		_court_helper = null
	if _net_helper != null:
		_net_helper.free()
		_net_helper = null


var _tool_suspended_nodes: Dictionary = {}
var _tool_ball_was_frozen: bool = false

func _tool_state_active() -> bool:
	return is_instance_valid(mobile_pose_editor) or (posture_editor_v2 != null and posture_editor_v2.visible) or (game_sound_tune != null and game_sound_tune.sound_tune_panel != null and game_sound_tune.sound_tune_panel.visible)

func close_active_tool() -> bool:
	if movement_actions != null and movement_actions.is_open():
		movement_actions.close_picker()
		return true
	if is_instance_valid(mobile_pose_editor):
		mobile_pose_editor.close()
		return true
	if posture_editor_v2 and posture_editor_v2.visible:
		posture_editor_v2.close()
		return true
	if game_sound_tune and game_sound_tune.sound_tune_panel.visible:
		_toggle_sound_panel()
		return true
	if hud and hud._guide and hud._guide.visible:
		hud._guide.hide()
		return true
	return false

func _toggle_sound_panel() -> void :
	if game_sound_tune == null: return
	if posture_editor_v2 and posture_editor_v2.visible:
		return
	var panel: Control = game_sound_tune.sound_tune_panel
	panel.visible = not panel.visible
	if panel.visible:
		_suspend_tool_gameplay()
		scoreboard_ui.hide_all_hud()
		reaction_button.hide()
		game_sound_tune._refresh_sound_tune_panel()
	else:
		_resume_tool_gameplay()
		scoreboard_ui.show_all_hud()
		scoreboard_ui.set_debug_visuals_active(debug_visuals_visible)
		if ai_difficulty == 0:
			reaction_button.enter_idle()

func _suspend_tool_gameplay() -> void :
	if aim_focus: aim_focus.cancel()
	if movement_guide: movement_guide.cancel()
	if between_point_controller and between_point_controller.is_active():
		between_point_controller.cancel()
		_reset_ball()
	if aim_controller: aim_controller.reset()
	if game_trajectory: game_trajectory.clear()
	if not _tool_suspended_nodes.is_empty():
		return
	game_serve.cleanup()
	serve_charge_time = 0.0
	serve_is_charging = false
	if player_left and player_left.hitting:
		player_left.hitting.clear_charge_visual()
	_tool_ball_was_frozen = ball.freeze
	ball.freeze = true
	if ball.has_method("refresh_scene_contact_owner"): ball.refresh_scene_contact_owner()
	for node in [ball, player_left, player_right, rally_scorer, practice_launcher]:
		if node:
			_tool_suspended_nodes[node] = {"physics": node.is_physics_processing(), "process": node.is_processing()}
			node.set_physics_process(false)
			if node == practice_launcher:
				node.set_process(false)

func _resume_tool_gameplay() -> void :
	if ball.has_method("refresh_scene_contact_owner"): ball.refresh_scene_contact_owner()
	ball.freeze = _tool_ball_was_frozen
	for node in _tool_suspended_nodes:
		if is_instance_valid(node):
			node.set_physics_process(_tool_suspended_nodes[node]["physics"])
			node.set_process(_tool_suspended_nodes[node]["process"])
	_tool_suspended_nodes.clear()


func select_drop_shot() -> void :
	selected_shot_intent = "DROP"
	selected_spin_mode = 0
	_update_spin_selection_ui()

func cycle_spin_mode() -> void :
	if selected_shot_intent == "DROP":
		selected_shot_intent = "AUTO"
		selected_spin_mode = 0
	else:
		selected_spin_mode = _ShotProfile.next_mode(selected_spin_mode)
	_update_spin_selection_ui()

func freeze_spin_selection(mode: int, intent: String = "AUTO") -> void :
	_frozen_shot_intent = intent
	_frozen_spin_mode = _ShotProfile.valid_mode(mode)
	_update_spin_selection_ui()

func clear_frozen_spin_selection() -> void :
	_frozen_shot_intent = ""
	_frozen_spin_mode = -1
	_update_spin_selection_ui()

func _update_spin_selection_ui() -> void :
	if scoreboard_ui and scoreboard_ui.has_method("set_spin_selection"):
		var locked: String = _ShotProfile.mode_name(_frozen_spin_mode) if _frozen_spin_mode >= 0 else ""
		scoreboard_ui.set_spin_selection(_ShotProfile.mode_name(selected_spin_mode), locked, selected_shot_intent, _frozen_shot_intent)


func capture_aim_target() -> Vector3:
	return aim_controller.capture() if aim_controller else Vector3.INF

func release_aim_target() -> void :
	if aim_controller: aim_controller.release()

func request_match_reset() -> void :

	if aim_focus: aim_focus.cancel()
	_exit_slow_mo()
	if practice_launcher and practice_launcher.is_active: practice_launcher.stop_practice()
	if practice_panel:
		practice_panel._picker_open = false
		practice_panel._shown_result = false
		practice_panel.hide()
	_reset_match()

func cancel_aim_focus() -> void :
	if aim_focus: aim_focus.cancel()

# Mobile editor is an explicit, lazy Pause-menu workspace. No live rig is edited.
func open_mobile_pose_editor() -> void:
	if is_instance_valid(mobile_pose_editor): return
	if not get_tree().paused: PauseController.open()
	mobile_pose_editor = load("res://scripts/ui/mobile_pose_editor.gd").new()
	mobile_pose_editor.editor_closed.connect(_close_mobile_pose_editor)
	mobile_pose_editor.poses_saved.connect(func(): _mobile_poses_saved = true)
	add_child(mobile_pose_editor)
	if is_instance_valid(PauseController._menu): PauseController._menu.hide()

func _close_mobile_pose_editor() -> void:
	if not is_instance_valid(mobile_pose_editor): return
	mobile_pose_editor.queue_free()
	mobile_pose_editor = null
	if _mobile_poses_saved:
		# Refresh cached selection zones only after successful persistence.
		for player in get_players():
			if player and player.posture: player.posture.refresh_posture_zones()
			if player and player.pose_controller:
				player.pose_controller._library.load_or_default()
				player.pose_controller.invalidate_cache()
		_mobile_poses_saved = false
	if is_instance_valid(PauseController._menu):
		PauseController._menu.show()
		PauseController._menu.focus_pose_editor()
