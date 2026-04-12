extends Node3D
## Game.gd - Main game controller with full pickleball rules

var score_left := 0
var score_right := 0
var serving_team := 0
var game_state := "waiting"
var ball_has_bounced := false
var serve_charge_time := 0.0
var serve_is_charging := false

const MIN_SERVE_SPEED := 6.4
const MAX_SERVE_SPEED := 13.8
const MAX_SERVE_CHARGE_TIME := 0.45
const HIT_REACH_DISTANCE := 1.15  # wider: WIDE_FOREHAND/BACKHAND extends arm further
# Speed curve — 50 mph = 22.352 m/s
const MIN_SWING_SPEED_MS := 5.0   # light tap (~11 mph)
const MAX_SWING_SPEED_MS := 22.35 # full charge = 50 mph
const NON_VOLLEY_ZONE := 1.8
const BLUE_RESET_POSITION := Vector3(1.5, 1.0, 6.8)   # Start on RIGHT side (X > 0), further back for serve
const RED_RESET_POSITION := Vector3(-1.5, 1.0, -6.15)  # Start on RIGHT side (X < 0)
const TRAJECTORY_STEP_TIME := 0.08
const TRAJECTORY_STEPS := 28
const SERVE_AIM_STEP := 0.35
const SERVE_AIM_MAX := 2.2
const ARC_INTENT_STEP := 0.06
const ARC_INTENT_MIN := -0.12
const ARC_INTENT_MAX := 0.24

var player_left: CharacterBody3D
var player_right: CharacterBody3D
var ball: RigidBody3D
var score_label: Label
var state_label: Label
var debug_label: Label
var fault_label: Label  # Big text for fault indication
var zone_label: Label  # Big text showing what zone ball landed in
var speed_label: Label   # Speedometer — mph of last hit
var speedometer_timer: float = 0.0
var trajectory_mesh_instance: MeshInstance3D
var trajectory_mesh: ImmediateMesh
var trajectory_material: StandardMaterial3D
var target_marker: MeshInstance3D  # Shows where Red AI is aiming
var main_camera: Camera3D  # Reference to the main camera for following player
var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0
var ai_serve_timer: float = 0.0
var arc_raise_was_pressed: bool = false
var arc_lower_was_pressed: bool = false

# Drop test
var _test_active: bool = false
var _test_peak_y: float = 0.0
var _test_bounces: Array = []
var _test_frame: int = 0
var _t_was_pressed: bool = false
var _sound_test_key_state: Dictionary = {}
var _sound_panel_key_state: Dictionary = {}
var _sound_panel_toggle_pressed := false
var _sound_panel_print_pressed := false
var sound_tune_panel: PanelContainer
var sound_tune_rows: Array[Label] = []
var sound_tune_sliders: Array[HSlider] = []
var sound_tune_settings := [
	{"id": "paddle_pitch", "label": "Paddle Pitch"},
	{"id": "paddle_sub_pitch", "label": "Paddle Sub Pitch"},
	{"id": "paddle_pitch_blend", "label": "Paddle Pitch Blend"},
	{"id": "paddle_upper_pitch", "label": "Paddle Upper Pitch"},
	{"id": "paddle_body_pitch", "label": "Paddle Body Pitch"},
	{"id": "paddle_hollow_pitch", "label": "Paddle Hollow Pitch"},
	{"id": "paddle_body", "label": "Paddle Body"},
	{"id": "paddle_wood", "label": "Paddle Wood"},
	{"id": "paddle_hollow", "label": "Paddle Hollow"},
	{"id": "paddle_rumble", "label": "Paddle Rumble"},
	{"id": "paddle_core_softness", "label": "Paddle Core Softness"},
	{"id": "paddle_metallic", "label": "Paddle Metallic"},
	{"id": "paddle_ring", "label": "Paddle Ring"},
	{"id": "paddle_presence", "label": "Paddle Presence"},
	{"id": "paddle_attack", "label": "Paddle Attack"},
	{"id": "paddle_clack", "label": "Paddle Clack"},
	{"id": "paddle_noise", "label": "Paddle Noise"},
	{"id": "paddle_crackle", "label": "Paddle Crackle"},
	{"id": "paddle_compress", "label": "Paddle Compression"},
	{"id": "paddle_dead", "label": "Paddle Deadness"},
	{"id": "paddle_sweet_spot", "label": "Paddle Sweet Spot"},
	{"id": "paddle_variation", "label": "Paddle Variation"},
	{"id": "paddle_damp", "label": "Paddle Damp"},
	{"id": "paddle_tail", "label": "Paddle Tail"},
	{"id": "paddle_reflection", "label": "Paddle Reflection"},
	{"id": "paddle_echo", "label": "Paddle Echo"},
	{"id": "paddle_chirp", "label": "Ball Chirp"},
	{"id": "paddle_helmholtz", "label": "Ball Resonance"},
	{"id": "court_weight", "label": "Court Weight"},
	{"id": "court_snap", "label": "Court Snap"},
	{"id": "court_decay", "label": "Court Decay"},
	{"id": "court_hardness", "label": "Court Hardness"},
	{"id": "court_surface", "label": "Court Surface"}
]
var sound_tune_selected := 0

func _ready() -> void:
	_setup_environment()
	_setup_game()

func _setup_environment() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.4, 0.6, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = environment
	add_child(env)
	
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.position = Vector3(8, 12, 8)
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	light.light_energy = 1.2
	add_child(light)
	
	main_camera = Camera3D.new()
	main_camera.position = Vector3(0, 10.5, 11.0)
	main_camera.rotation_degrees = Vector3(-52, 0, 0)
	main_camera.fov = 60.0
	main_camera.name = "MainCamera"
	add_child(main_camera)
	
	_setup_trajectory_visual()

func _setup_game() -> void:
	var court_script: Script = load("res://scripts/court.gd")
	var net_script: Script = load("res://scripts/net.gd")
	var ball_script: Script = load("res://scripts/ball.gd")
	var player_script: Script = load("res://scripts/player.gd")
	# var rules_script: Script = load("res://scripts/rules.gd")
	
	var court: Node = court_script.new()
	var net_node: Node = net_script.new()
	# var rules: Node = rules_script.new()
	
	court.create_court(self)
	court.create_lines(self)
	# No walls - open court
	print("DEBUG: Court created")
	
	net_node.create_net(self)
	
	var bounds: Dictionary = court.get_court_bounds()
	
	# Player 0 = Human (WASD), Player 1 = AI
	player_left = player_script.new()
	add_child(player_left)
	player_left.setup(0, bounds, Color(0.2, 0.5, 1.0), BLUE_RESET_POSITION, false)  # Human
	
	player_right = player_script.new()
	add_child(player_right)
	player_right.setup(1, bounds, Color(1.0, 0.35, 0.35), RED_RESET_POSITION, true)  # AI
	player_right.set_ai_movement_enabled(false)
	
	ball = ball_script.new()
	add_child(ball)
	ball.bounced.connect(_on_ball_bounced)
	ball.hit_by_paddle.connect(_on_any_paddle_hit)
	
	_create_ui()

func _create_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	
	score_label = Label.new()
	score_label.text = "0 - 0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)
	score_label.anchor_left = 0.0
	score_label.anchor_right = 1.0
	score_label.anchor_top = 0.0
	score_label.offset_top = 8.0
	score_label.offset_bottom = 50.0
	canvas.add_child(score_label)

	state_label = Label.new()
	state_label.text = "Hold SPACE to charge serve | 6/7/8 paddle | Y/U/I court | P tuner"
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.add_theme_font_size_override("font_size", 18)
	state_label.add_theme_color_override("font_color", Color(1, 1, 0.3, 1))
	state_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	state_label.add_theme_constant_override("shadow_offset_x", 1)
	state_label.add_theme_constant_override("shadow_offset_y", 1)
	state_label.anchor_left = 0.0
	state_label.anchor_right = 1.0
	state_label.anchor_top = 0.0
	state_label.offset_top = 50.0
	state_label.offset_bottom = 90.0
	canvas.add_child(state_label)

	# Debug label — shows live popup error tendency (bottom-left)
	debug_label = Label.new()
	debug_label.text = ""
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 0.9))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
	debug_label.anchor_left = 0.0
	debug_label.anchor_right = 0.5
	debug_label.anchor_top = 1.0
	debug_label.anchor_bottom = 1.0
	debug_label.offset_top = -140.0
	debug_label.offset_left = 10.0
	canvas.add_child(debug_label)
	
	# Fault label — big text for service faults (wrong service box)
	fault_label = Label.new()
	fault_label.text = ""
	fault_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fault_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fault_label.add_theme_font_size_override("font_size", 48)
	fault_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	fault_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fault_label.add_theme_constant_override("shadow_offset_x", 3)
	fault_label.add_theme_constant_override("shadow_offset_y", 3)
	fault_label.anchor_left = 0.0
	fault_label.anchor_right = 1.0
	fault_label.anchor_top = 0.0
	fault_label.anchor_bottom = 1.0
	fault_label.modulate.a = 0.0  # Start hidden
	canvas.add_child(fault_label)
	
	# Zone debug label — shows which zone the ball landed in (big text, below fault)
	zone_label = Label.new()
	zone_label.text = ""
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone_label.add_theme_font_size_override("font_size", 32)
	zone_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 1.0))
	zone_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	zone_label.add_theme_constant_override("shadow_offset_x", 2)
	zone_label.add_theme_constant_override("shadow_offset_y", 2)
	zone_label.anchor_left = 0.0
	zone_label.anchor_right = 1.0
	zone_label.anchor_top = 0.0
	zone_label.anchor_bottom = 1.0
	zone_label.offset_top = 80.0  # Below fault label
	zone_label.modulate.a = 0.0  # Start hidden
	canvas.add_child(zone_label)

	# Speedometer — top-right, shows mph of last hit
	speed_label = Label.new()
	speed_label.text = ""
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label.add_theme_font_size_override("font_size", 28)
	speed_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
	speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	speed_label.add_theme_constant_override("shadow_offset_x", 2)
	speed_label.add_theme_constant_override("shadow_offset_y", 2)
	speed_label.anchor_left = 0.5
	speed_label.anchor_right = 1.0
	speed_label.anchor_top = 0.0
	speed_label.offset_top = 8.0
	speed_label.offset_right = -12.0
	speed_label.offset_bottom = 50.0
	speed_label.modulate.a = 0.0  # Start hidden
	canvas.add_child(speed_label)

	_create_sound_tune_panel(canvas)

func _create_sound_tune_panel(canvas: CanvasLayer) -> void:
	sound_tune_panel = PanelContainer.new()
	sound_tune_panel.anchor_left = 0.5
	sound_tune_panel.anchor_right = 0.5
	sound_tune_panel.anchor_top = 0.5
	sound_tune_panel.anchor_bottom = 0.5
	sound_tune_panel.offset_left = -260.0
	sound_tune_panel.offset_top = -430.0
	sound_tune_panel.offset_right = 260.0
	sound_tune_panel.offset_bottom = 430.0
	sound_tune_panel.focus_mode = Control.FOCUS_NONE
	sound_tune_panel.visible = false
	canvas.add_child(sound_tune_panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	sound_tune_panel.add_child(margin)
	
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)
	
	var title := Label.new()
	title.text = "Sound Signature  P: Toggle  Arrows: Select/Adjust"
	title.add_theme_font_size_override("font_size", 14)
	title.focus_mode = Control.FOCUS_NONE
	vb.add_child(title)
	
	for setting in sound_tune_settings:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		row.focus_mode = Control.FOCUS_NONE
		vb.add_child(row)
		sound_tune_rows.append(row)
		
		var slider := HSlider.new()
		slider.min_value = -1.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.editable = false
		slider.focus_mode = Control.FOCUS_NONE
		vb.add_child(slider)
		sound_tune_sliders.append(slider)
	
	_refresh_sound_tune_panel()

func _refresh_sound_tune_panel() -> void:
	if ball == null:
		return
	var tunings: Dictionary = ball.get_sound_tunings()
	for i in range(sound_tune_settings.size()):
		var setting: Dictionary = sound_tune_settings[i]
		var id: String = setting["id"]
		var value: float = tunings.get(id, 0.0)
		if i < sound_tune_rows.size():
			var prefix := "> " if i == sound_tune_selected else "  "
			var label_text: String = prefix + String(setting["label"]) + ": " + str(snapped(value, 0.05))
			if id == "paddle_pitch" and ball.has_method("get_paddle_pitch_note") and ball.has_method("get_paddle_pitch_frequency"):
				label_text += "  [" + ball.get_paddle_pitch_note() + " / " + str(int(round(ball.get_paddle_pitch_frequency()))) + " Hz]"
			sound_tune_rows[i].text = label_text
			sound_tune_rows[i].modulate = Color(1.0, 0.95, 0.55, 1.0) if i == sound_tune_selected else Color(0.88, 0.88, 0.88, 1.0)
		if i < sound_tune_sliders.size():
			sound_tune_sliders[i].value = value
			sound_tune_sliders[i].modulate = Color(1.0, 0.85, 0.35, 1.0) if i == sound_tune_selected else Color(0.7, 0.7, 0.7, 1.0)

func _handle_sound_panel_input() -> void:
	if ball == null:
		return
	if not sound_tune_panel.visible:
		return
	
	if _consume_panel_key("up", KEY_UP):
		sound_tune_selected = wrapi(sound_tune_selected - 1, 0, sound_tune_settings.size())
		_refresh_sound_tune_panel()
	if _consume_panel_key("down", KEY_DOWN):
		sound_tune_selected = wrapi(sound_tune_selected + 1, 0, sound_tune_settings.size())
		_refresh_sound_tune_panel()
	if _consume_panel_key("left", KEY_LEFT):
		_adjust_sound_tuning(-0.05)
	if _consume_panel_key("right", KEY_RIGHT):
		_adjust_sound_tuning(0.05)

func _consume_panel_key(key_name: String, keycode: Key) -> bool:
	var pressed: bool = Input.is_key_pressed(keycode)
	var was_pressed: bool = _sound_panel_key_state.get(key_name, false)
	_sound_panel_key_state[key_name] = pressed
	return pressed and not was_pressed

func _adjust_sound_tuning(delta: float) -> void:
	if ball == null:
		return
	var setting: Dictionary = sound_tune_settings[sound_tune_selected]
	var id: String = setting["id"]
	var tunings: Dictionary = ball.get_sound_tunings()
	var next_value: float = clamp(tunings.get(id, 0.0) + delta, -1.0, 1.0)
	ball.set_sound_tuning(id, next_value)
	_refresh_sound_tune_panel()

func _physics_process(delta: float) -> void:
	# Drop test T key
	var t_pressed: bool = Input.is_key_pressed(KEY_T)
	if t_pressed and not _t_was_pressed:
		_start_drop_test()
	_t_was_pressed = t_pressed
	_drop_test_tick()
	_handle_sound_panel_toggle()
	_handle_sound_panel_input()
	_handle_sound_test_input()

	_update_blue_charge(delta)
	_update_trajectory_predictor()
	_update_debug_label()
	_update_speedometer(delta)
	_check_service_fault()
	_update_camera_follow(delta)
	
	if game_state == "waiting" and not _test_active:
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
	elif game_state == "playing":
		_check_rally()
		_check_ball_out_of_bounds()

func _handle_sound_test_input() -> void:
	if ball == null:
		return
	
	_trigger_test_sound_key(KEY_6, "6", "paddle", 0)
	_trigger_test_sound_key(KEY_7, "7", "paddle", 1)
	_trigger_test_sound_key(KEY_8, "8", "paddle", 2)
	_trigger_test_sound_key(KEY_Y, "Y", "court", 0)
	_trigger_test_sound_key(KEY_U, "U", "court", 1)
	_trigger_test_sound_key(KEY_I, "I", "court", 2)

func _trigger_test_sound_key(keycode: Key, key_name: String, sound_type: String, sound_index: int) -> void:
	var pressed: bool = Input.is_key_pressed(keycode)
	var was_pressed: bool = _sound_test_key_state.get(key_name, false)
	if pressed and not was_pressed:
		if sound_type == "paddle":
			ball.play_test_paddle_sound(sound_index)
		else:
			ball.play_test_court_sound(sound_index)
	_sound_test_key_state[key_name] = pressed

func _handle_sound_panel_toggle() -> void:
	var pressed: bool = Input.is_key_pressed(KEY_P)
	if pressed and not _sound_panel_toggle_pressed and sound_tune_panel != null:
		sound_tune_panel.visible = not sound_tune_panel.visible
		if sound_tune_panel.visible:
			_refresh_sound_tune_panel()
	_sound_panel_toggle_pressed = pressed
	
	var print_pressed: bool = Input.is_key_pressed(KEY_O)
	if print_pressed and not _sound_panel_print_pressed:
		_print_sound_tunings()
	_sound_panel_print_pressed = print_pressed

func _print_sound_tunings() -> void:
	if ball == null:
		return
	var tunings: Dictionary = ball.get_sound_tunings()
	print("")
	print("=== SOUND TUNINGS ===")
	for setting in sound_tune_settings:
		var id: String = setting["id"]
		print(setting["label"], ": ", snapped(float(tunings.get(id, 0.0)), 0.01))

func _update_camera_follow(delta: float) -> void:
	# Camera stays centered unless player goes near screen edge
	if main_camera == null or player_left == null:
		return
	
	# Define screen edge threshold - only move camera when player exceeds this
	const EDGE_THRESHOLD: float = 2.5
	const MAX_CAMERA_OFFSET: float = 3.0
	
	var player_x: float = player_left.global_position.x
	var camera_x: float = main_camera.position.x
	var target_x: float = 0.0
	
	# Calculate how far player is from camera center in screen space
	var player_offset: float = player_x - camera_x
	
	# Only move camera if player is beyond edge threshold
	if player_offset > EDGE_THRESHOLD:
		# Player near right edge - move camera right to catch up
		target_x = player_x - EDGE_THRESHOLD
	elif player_offset < -EDGE_THRESHOLD:
		# Player near left edge - move camera left to catch up
		target_x = player_x + EDGE_THRESHOLD
	else:
		# Player is in safe zone - slowly return camera to center
		target_x = 0.0
	
	# Clamp camera movement
	target_x = clamp(target_x, -MAX_CAMERA_OFFSET, MAX_CAMERA_OFFSET)
	
	# Smoothly interpolate camera position
	main_camera.position.x = lerp(camera_x, target_x, 4.0 * delta)

func _update_blue_charge(delta: float) -> void:
	_update_serve_aim_input(delta)
	_update_arc_intent_input()
	
	if Input.is_action_just_pressed("ui_accept"):
		serve_is_charging = true
		serve_charge_time = 0.0
	
	if serve_is_charging and Input.is_action_pressed("ui_accept"):
		serve_charge_time = min(serve_charge_time + delta, MAX_SERVE_CHARGE_TIME)
		var charge_ratio: float = serve_charge_time / MAX_SERVE_CHARGE_TIME
		player_left.set_serve_charge_visual(charge_ratio)
		var percent: int = int(round(charge_ratio * 100.0))
		if game_state == "waiting":
			state_label.text = "Hold SPACE to charge serve\nPower: " + str(percent) + "%  Aim: " + _get_aim_label() + "  Arc: " + _get_arc_label()
		elif game_state == "playing":
			state_label.text = "Swing Power: " + str(percent) + "%  Arc: " + _get_arc_label()
	
	if serve_is_charging and Input.is_action_just_released("ui_accept"):
		serve_is_charging = false
		var charge_ratio: float = serve_charge_time / MAX_SERVE_CHARGE_TIME
		serve_charge_time = 0.0
		_clear_trajectory_predictor()
		if game_state == "waiting":
			_perform_serve(charge_ratio)
		elif game_state == "playing":
			_perform_player_swing(charge_ratio)
		trajectory_arc_offset = 0.0

func _perform_serve(charge_ratio: float) -> void:
	game_state = "serving"
	ball_has_bounced = false
	ball.reset_rally_state()
	ball.serve_team = serving_team
	
	if serving_team == 0:
		player_left.animate_serve_release(charge_ratio)
		ball.global_position = player_left.global_position + Vector3(0, 0.8, -0.55)
		ball.linear_velocity = _get_predicted_serve_velocity(charge_ratio)
		# Log serve targeting logic
		var total_score: int = score_left + score_right
		var serve_from_right: bool = (total_score % 2) == 0
		var target_diag: String = "LEFT" if serve_from_right else "RIGHT"
		print("[SERVE BLUE] pos=", ball.global_position, " vel=", ball.linear_velocity, 
			" charge=", snapped(charge_ratio, 0.01), " score=", total_score, 
			" from_right=", serve_from_right, " target=", target_diag, " (X<0=left, X>0=right)")
	else:
		player_right.animate_serve_release(charge_ratio)
		ball.global_position = player_right.global_position + Vector3(0, 0.8, 0.55)
		ball.linear_velocity = _get_predicted_serve_velocity(charge_ratio, true)
		# Log serve targeting logic
		var total_score: int = score_left + score_right
		var serve_from_right: bool = (total_score % 2) == 0
		var target_diag: String = "LEFT" if serve_from_right else "RIGHT"
		print("[SERVE RED] pos=", ball.global_position, " vel=", ball.linear_velocity, 
			" charge=", snapped(charge_ratio, 0.01), " score=", total_score, 
			" from_right=", serve_from_right, " target=", target_diag, " (X>0=left, X<0=right)")
		ball.last_hit_by = 1
	
	ball.angular_velocity = Vector3(randf() * 3, randf() * 3, randf() * 3)
	game_state = "playing"
	player_right.set_ai_movement_enabled(true)
	state_label.text = "Rally!"
	
	# Play serve sound effect
	ball.play_serve_sound()
	_show_speedometer(ball.linear_velocity.length())

func _perform_player_swing(charge_ratio: float) -> void:
	player_left.animate_serve_release(charge_ratio)

	if ball == null:
		return

	var paddle_pos: Vector3 = player_left.get_paddle_position()
	# Wide posture extends reach — use player body distance as secondary check
	var reach := HIT_REACH_DISTANCE
	var player_to_ball: float = player_left.global_position.distance_to(ball.global_position)
	if player_to_ball < 1.80:
		reach = max(reach, player_to_ball * 0.85)
	if paddle_pos.distance_to(ball.global_position) > reach:
		state_label.text = "Rally!"
		return

	# Speed curve: power 0.7 gives more granularity at low charge, peaks at 50 mph
	var speed_curve: float = pow(clamp(charge_ratio, 0.0, 1.0), 0.7)
	var target_speed: float = lerp(MIN_SWING_SPEED_MS, MAX_SWING_SPEED_MS, speed_curve)

	# Harder hits go deeper in the court — full charge reaches back baseline
	var depth_min: float = lerp(-3.0, -5.5, speed_curve)
	var depth_max: float = lerp(-2.0, -2.5, speed_curve)
	var _target_z: float = randf_range(depth_min, depth_max)
	var _target_x: float = randf_range(-2.0, 2.0)
	var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * ball.gravity_scale
	var bpos: Vector3 = ball.global_position
	var _dz: float = _target_z - bpos.z
	var _dx: float = _target_x - bpos.x
	var _hdist: float = sqrt(_dz * _dz + _dx * _dx)
	var _ftime: float = clamp(_hdist / target_speed * 1.05, 0.3, 1.8)
	var _vz: float = _dz / _ftime
	var _vx: float = _dx / _ftime
	var _vy: float = (0.08 - bpos.y + 0.5 * _gravity * _ftime * _ftime) / _ftime
	# Clear net check
	if _vz < -0.01:
		var _t_net: float = (0.0 - bpos.z) / _vz
		if _t_net > 0.0 and _t_net < _ftime:
			var _y_at_net: float = bpos.y + _vy * _t_net - 0.5 * _gravity * _t_net * _t_net
			if _y_at_net < 1.2:
				_vy += (1.2 - _y_at_net) / _t_net
	var _vel: Vector3 = Vector3(_vx, _vy, _vz)
	# Clamp to target_speed (preserves direction, enforces charge-based speed cap)
	if _vel.length() > target_speed:
		_vel = _vel.normalized() * target_speed
	elif _vel.length() < MIN_SWING_SPEED_MS * 0.6:
		_vel = _vel.normalized() * (MIN_SWING_SPEED_MS * 0.6)
	ball.linear_velocity = _vel
	ball.hit_by_player(0)
	_show_speedometer(ball.linear_velocity.length())
	state_label.text = "Rally!"

func _check_rally() -> void:
	if ball.global_position.y < 0.1 and ball.linear_velocity.y < -1.0:
		if not ball_has_bounced:
			ball_has_bounced = true
			state_label.text = "Ball bounced!"

func _check_ball_out_of_bounds() -> void:
	if game_state != "playing":
		return
	# Only check out-of-bounds when ball is near ground — don't penalize mid-flight
	if ball.global_position.y > 0.5:
		return

	var bpos: Vector3 = ball.global_position
	var margin: float = 1.5
	var bounds: Dictionary = {
		"left": -3.05,
		"right": 3.05,
		"top": -6.7,
		"bottom": 6.7
	}

	if bpos.z > bounds.bottom + margin:
		_on_point_scored(0)
	elif bpos.z < bounds.top - margin:
		_on_point_scored(1)
	elif bpos.x < bounds.left - margin or bpos.x > bounds.right + margin:
		if bpos.z > 0:
			_on_point_scored(0)
		else:
			_on_point_scored(1)

# Service fault detection — check if ball lands in wrong service box
var _service_fault_triggered: bool = false
var _serve_was_hit: bool = false  # Track if ball has been hit back after serve

func _check_service_fault() -> void:
	if game_state != "playing" or ball == null:
		return
	
	var bpos: Vector3 = ball.global_position
	
	# Only check when ball is near ground (about to land)
	if bpos.y > 0.4:
		return
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# PICKLEBALL DIAGONAL SERVE RULES (same as _get_predicted_serve_velocity):
	#   - Even total score: server stands on RIGHT → serve to LEFT diagonal of opponent
	#   - Odd total score: server stands on LEFT → serve to RIGHT diagonal of opponent
	#
	# For BLUE (serving to Z < 0, red's side):
	#   - Even: serve from RIGHT (X>0), target LEFT diagonal (X<0)
	#   - Odd: serve from LEFT (X<0), target RIGHT diagonal (X>0)
	#
	# For RED (serving to Z > 0, blue's side):
	#   - Even: serve from RIGHT (X<0 in world), target LEFT diagonal (X>0 in world)
	#   - Odd: serve from LEFT (X>0 in world), target RIGHT diagonal (X<0 in world)
	# ═══════════════════════════════════════════════════════════════════════════════
	
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0  # Even = from right side
	
	# Debug: log ball position and what's being checked
	print("[FAULT CHECK] ball=(x:", snapped(bpos.x, 0.1), " z:", snapped(bpos.z, 0.1), 
		") score=", total_score, " serve_from_right=", serve_from_right, " serving_team=", serving_team)
	
	# Show zone debug (what zone ball landed in)
	_update_zone_debug(bpos)
	
	if serving_team == 0:
		# BLUE serving to RED's side (Z < 0 = negative Z, red's half)
		# Ball must land PAST the net on RED's side: Z < -1.8 (beyond kitchen)
		var correct_side: bool = bpos.z < -1.8
		print("[FAULT] Blue serve: bpos.z=", snapped(bpos.z, 0.1), " < -1.8 = ", correct_side)
		
		var correct_diagonal: bool = false
		if serve_from_right:
			# Even: blue at X>0 (CYAN), serves to opposite = PURPLE (X<0)
			correct_diagonal = bpos.x < 0.0
			print("[FAULT] Blue even: check PURPLE (X<0), bpos.x=", snapped(bpos.x, 0.1))
		else:
			# Odd: blue at X<0 (LIME), serves to opposite = MAGENTA (X>0)
			correct_diagonal = bpos.x > 0.0
			print("[FAULT] Blue odd: check MAGENTA (X>0), bpos.x=", snapped(bpos.x, 0.1))
		
		# Check if ball landed in correct place (valid serve)
		if correct_side and correct_diagonal:
			_serve_was_hit = true  # Valid serve landed
			_hide_fault_label()
			print("[FAULT] Valid serve! Landed in correct diagonal")
		elif not correct_side:
			# Ball landed on serving side (kitchen or wrong side) - FAULT
			if not _serve_was_hit:
				print("[FAULT] Ball didn't cross net to opponent side!")
				_trigger_service_fault(1)
		elif correct_side and not correct_diagonal:
			# Ball landed on correct side but wrong diagonal - FAULT
			if not _serve_was_hit:
				print("[FAULT] Wrong diagonal!")
				_trigger_service_fault(1)
	else:
		# RED serving to BLUE's side (Z > 0 = positive Z, blue's half)
		var correct_side: bool = bpos.z > 1.8  # Must land on blue's side (beyond kitchen)
		
		var correct_diagonal: bool = false
		if serve_from_right:
			# Even: red at X<0 (MAGENTA), serves to opposite = CYAN (X>0)
			correct_diagonal = bpos.x > 0.0
			print("[FAULT] Red even: check CYAN (X>0), bpos.x=", snapped(bpos.x, 0.1))
		else:
			# Odd: red at X>0 (PURPLE), serves to opposite = LIME (X<0)
			correct_diagonal = bpos.x < 0.0
			print("[FAULT] Red odd: check LIME (X<0), bpos.x=", snapped(bpos.x, 0.1))
		
		# Check if ball landed in correct place (valid serve)
		if correct_side and correct_diagonal:
			_serve_was_hit = true
			_hide_fault_label()
			print("[FAULT] Valid serve! Landed in correct diagonal")
		elif not correct_side:
			# Ball landed on serving side (kitchen or wrong side) - FAULT
			if not _serve_was_hit:
				print("[FAULT] Ball landed on serving side!")
				_trigger_service_fault(0)
		elif correct_side and not correct_diagonal:
			# Ball landed on correct side but wrong diagonal - FAULT
			if not _serve_was_hit:
				print("[FAULT] Wrong diagonal!")
				_trigger_service_fault(0)

func _trigger_service_fault(winner: int) -> void:
	if _service_fault_triggered:
		return
	_service_fault_triggered = true
	
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var expected_diagonal: String = ""
	var fault_message: String = ""
	
	if serving_team == 0:
		if serve_from_right:
			expected_diagonal = "PURPLE (X<0)"
			fault_message = "SERVICE FAULT!\nBlue: Serve to PURPLE (X<0)"
		else:
			expected_diagonal = "MAGENTA (X>0)"
			fault_message = "SERVICE FAULT!\nBlue: Serve to MAGENTA (X>0)"
	else:
		if serve_from_right:
			expected_diagonal = "CYAN (X>0)"
			fault_message = "SERVICE FAULT!\nRed: Serve to CYAN (X>0)"
		else:
			expected_diagonal = "LIME (X<0)"
			fault_message = "SERVICE FAULT!\nRed: Serve to LIME (X<0)"
	
	print("[FAULT] Expected ", expected_diagonal, " | ball=(x:", 
		snapped(ball.global_position.x, 0.1), " z:", snapped(ball.global_position.z, 0.1), 
		") | score:", score_left, "-", score_right)
	
	_show_fault_label(fault_message)
	
	# Award point to receiving team
	await get_tree().create_timer(1.0).timeout
	_on_point_scored(winner)

func _show_fault_label(message: String) -> void:
	fault_label.text = message
	fault_label.modulate.a = 1.0
	
	# Persist for 2 seconds, then fade out over 0.5 seconds
	var tween: Tween = create_tween()
	tween.tween_property(fault_label, "modulate:a", 0.0, 0.5).set_delay(2.0)

func _hide_fault_label() -> void:
	if fault_label != null:
		fault_label.modulate.a = 0.0
		_service_fault_triggered = false

# Debug: Show which zone ball landed in
func _update_zone_debug(bpos: Vector3) -> void:
	if game_state != "playing" or ball == null:
		zone_label.modulate.a = 0.0
		return
	
	# Determine what zone ball is in
	var zone: String = ""
	var color: Color = Color.WHITE
	
	if bpos.z > 1.8:
		# BLUE'S SIDE (red serving, ball on blue side)
		if bpos.x > 0.0:
			zone = "BLUE RIGHT (CYAN)"
			color = Color(0, 1, 1, 1)
		elif bpos.x < 0.0:
			zone = "BLUE LEFT (LIME)"
			color = Color(0, 1, 0, 1)
		else:
			zone = "BLUE CENTER"
			color = Color(0.5, 0.5, 0.5, 1)
	elif bpos.z < -1.8:
		# RED'S SIDE (blue serving, ball on red side)
		if bpos.x > 0.0:
			zone = "RED RIGHT (MAGENTA)"
			color = Color(1, 0, 1, 1)
		elif bpos.x < 0.0:
			zone = "RED LEFT (PURPLE)"
			color = Color(0.5, 0, 0.8, 1)
		else:
			zone = "RED CENTER"
			color = Color(0.5, 0.5, 0.5, 1)
	else:
		# KITCHEN / NVZ
		if bpos.z > 0:
			zone = "BLUE KITCHEN (RED)"
			color = Color(1, 0, 0, 1)
		else:
			zone = "RED KITCHEN (RED)"
			color = Color(1, 0, 0, 1)
	
	zone_label.text = zone
	zone_label.add_theme_color_override("font_color", color)
	zone_label.modulate.a = 0.8

func _on_point_scored(winning_team: int) -> void:
	game_state = "point_scored"
	ai_serve_timer = 0.0

	# Side-out scoring: only serving team scores
	if winning_team == serving_team:
		if winning_team == 0:
			score_left += 1
		else:
			score_right += 1
		score_label.text = str(score_left) + " - " + str(score_right)
		state_label.text = "Point! " + str(score_left) + " - " + str(score_right)
	else:
		# Side-out: receiving team wins rally, gets serve
		serving_team = winning_team
		state_label.text = "Side Out! Serve to " + ("Blue" if winning_team == 0 else "Red")

	score_label.text = str(score_left) + " - " + str(score_right)

	if score_left >= 11 and score_left - score_right >= 2:
		state_label.text = "GAME OVER! BLUE WINS!"
		await get_tree().create_timer(3.0).timeout
		_reset_match()
	elif score_right >= 11 and score_right - score_left >= 2:
		state_label.text = "GAME OVER! RED WINS!"
		await get_tree().create_timer(3.0).timeout
		_reset_match()
	else:
		await get_tree().create_timer(1.5).timeout
		_reset_ball()

func _reset_ball() -> void:
	ball.reset()
	ball_has_bounced = false
	game_state = "waiting"
	serve_charge_time = 0.0
	serve_is_charging = false
	serve_aim_offset_x = 0.0
	trajectory_arc_offset = 0.0
	ai_serve_timer = 0.0
	_service_fault_triggered = false
	_serve_was_hit = false
	_reset_player_positions()
	player_right.set_ai_movement_enabled(false)
	_update_held_ball_position()
	_hide_fault_label()
	if target_marker != null:
		target_marker.visible = false
	if serving_team == 0:
		state_label.text = "Hold SPACE to charge serve\nBlue's serve  Aim: " + _get_aim_label() + "  Arc: " + _get_arc_label()
	else:
		state_label.text = "Red's serve..."

func _reset_match() -> void:
	score_left = 0
	score_right = 0
	serving_team = 0
	score_label.text = "0 - 0"
	_reset_ball()

func _reset_player_positions() -> void:
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0  # Even = serve from right side
	
	# Blue (player_left) - spawns at Z > 0 (bottom of court)
	# Even: stand on RIGHT (X > 0), Odd: stand on LEFT (X < 0)
	var blue_x: float = 1.5 if serve_from_right else -1.5
	player_left.global_position = Vector3(blue_x, 1.0, 6.8)
	
	# Red (player_right) - spawns at Z < 0 (top of court)
	# Even: stand on RIGHT (X < 0, towards center), Odd: stand on LEFT (X > 0, away from center)
	var red_x: float = -1.5 if serve_from_right else 1.5
	player_right.global_position = Vector3(red_x, 1.0, -6.15)
	
	print("[SPAWN] score=", total_score, " serve_from_right=", serve_from_right,
		" Blue@X=", blue_x, " Red@X=", red_x)

func _update_held_ball_position() -> void:
	if ball == null:
		return
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	if serving_team == 0:
		ball.global_position = player_left.get_paddle_position() + Vector3(0.0, 0.08, -0.05)
	else:
		ball.global_position = player_right.get_paddle_position() + Vector3(0.0, 0.08, 0.05)

func _setup_trajectory_visual() -> void:
	trajectory_mesh_instance = MeshInstance3D.new()
	trajectory_mesh_instance.name = "TrajectoryPredictor"
	trajectory_mesh = ImmediateMesh.new()
	trajectory_mesh_instance.mesh = trajectory_mesh
	trajectory_material = StandardMaterial3D.new()
	trajectory_material.albedo_color = Color(0.95, 0.98, 1.0, 0.95)
	trajectory_material.emission_enabled = true
	trajectory_material.emission = Color(0.45, 0.9, 1.0, 1.0)
	trajectory_material.emission_energy_multiplier = 0.8
	trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trajectory_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trajectory_mesh_instance.material_override = trajectory_material
	trajectory_mesh_instance.visible = false
	add_child(trajectory_mesh_instance)
	
	# Setup target marker for Red AI serve aim
	target_marker = MeshInstance3D.new()
	target_marker.name = "RedTargetMarker"
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.25
	marker_mesh.height = 0.5
	target_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.35, 0.35, 0.8)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	marker_mat.emission_energy_multiplier = 1.2
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_marker.material_override = marker_mat
	target_marker.visible = false
	add_child(target_marker)

func _update_trajectory_predictor() -> void:
	if ball == null or not serve_is_charging:
		_clear_trajectory_predictor()
		return
	
	var charge_ratio: float = serve_charge_time / MAX_SERVE_CHARGE_TIME
	var start_position: Vector3 = ball.global_position
	var start_velocity: Vector3 = Vector3.ZERO
	
	if game_state == "waiting":
		start_position = player_left.get_paddle_position() + Vector3(0.0, 0.08, -0.05)
		# Use correct serve function based on who's serving
		if serving_team == 0:
			start_velocity = _get_predicted_serve_velocity(charge_ratio, false)
			target_marker.visible = false  # Hide target when Blue is serving
		else:
			# For red serving, trajectory starts from their paddle position
			start_position = player_right.get_paddle_position() + Vector3(0.0, 0.08, 0.05)
			start_velocity = _get_predicted_serve_velocity(charge_ratio, true)
			# Show and update target marker position
			_update_red_target_marker()
	elif game_state == "playing":
		start_velocity = ball.linear_velocity + (player_left.get_shot_impulse(ball.global_position, charge_ratio) / ball.mass)
	else:
		_clear_trajectory_predictor()
		return
	
	_draw_trajectory(start_position, start_velocity)

func _get_predicted_serve_velocity(charge_ratio: float, from_red_side: bool = false) -> Vector3:
	var serve_speed: float = lerp(MIN_SERVE_SPEED, MAX_SERVE_SPEED, clamp(charge_ratio, 0.0, 1.0))
	var serve_origin: Vector3 = player_left.get_paddle_position() + Vector3(0.0, 0.08, -0.05)
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# PICKLEBALL DIAGONAL SERVE RULES (opposite adjacent box):
	#   - Even total score: server stands on RIGHT → serve to LEFT diagonal of opponent
	#   - Odd total score: server stands on LEFT → serve to RIGHT diagonal of opponent
	#
	# For BLUE (serving from Z > 0, bottom of court):
	#   - Even score: stand on RIGHT (X > 0), serve to LEFT diagonal (X < 0, target Z < 0)
	#   - Odd score: stand on LEFT (X < 0), serve to RIGHT diagonal (X > 0, target Z < 0)
	#
	# For RED (serving from Z < 0, top of court):
	#   - Even score: stand on RIGHT (X < 0 in world, closer to center), serve to LEFT diagonal (X > 0 in world)
	#   - Odd score: stand on LEFT (X > 0 in world, farther from center), serve to RIGHT diagonal (X < 0 in world)
	# ═══════════════════════════════════════════════════════════════════════════════
	
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0  # Even = serve from right side
	
	# Debug: log the score and which diagonal we're targeting
	print("[SERVE TARGET] score=", total_score, " serve_from_right=", serve_from_right)
	
	var target_x_offset: float = serve_aim_offset_x
	
	if not from_red_side:
		# BLUE SERVE (serving to red's side at Z > 0)
		# At 0-0 (even): Blue starts RIGHT (X>0, CYAN), serves to opposite diagonal = LEFT (X<0, PURPLE)
		# At 1-0 (odd): Blue starts LEFT (X<0, LIME), serves to opposite diagonal = RIGHT (X>0, MAGENTA)
		if serve_from_right:
			# Even: stand right (X>0, CYAN), serve to opposite diagonal (X<0, PURPLE)
			target_x_offset = min(serve_aim_offset_x, -1.5)  # Force negative X, farther from center
			print("[BLUE] Even → target PURPLE (X<0), got X=", target_x_offset)
		else:
			# Odd: stand left (X<0, LIME), serve to opposite diagonal (X>0, MAGENTA)
			target_x_offset = max(serve_aim_offset_x, 1.5)   # Force positive X, farther from center
			print("[BLUE] Odd → target MAGENTA (X>0), got X=", target_x_offset)
		
		var target_z: float = -4.6  # Red's service box (negative Z)
		var target_position: Vector3 = Vector3(target_x_offset, 0.08, target_z)
		var target_dir: Vector3 = (target_position - serve_origin).normalized()
		target_dir.y = 0.32 + 0.22 * clamp(charge_ratio, 0.0, 1.0) + trajectory_arc_offset
		return target_dir.normalized() * serve_speed
	else:
		# RED SERVE (serving to blue's side at Z < 0)
		serve_origin = player_right.get_paddle_position() + Vector3(0.0, 0.08, 0.05)
		
		# At 0-0 (even): Red starts at X<0 (MAGENTA), serves to opposite diagonal = RIGHT (X>0, CYAN)
		# At 1-0 (odd): Red starts at X>0 (PURPLE), serves to opposite diagonal = LEFT (X<0, LIME)
		if serve_from_right:
			# Even: stand right (X<0, MAGENTA), serve to opposite diagonal (X>0, CYAN)
			target_x_offset = max(serve_aim_offset_x, 1.5)   # Force positive X, farther from center
			print("[RED] Even → target CYAN (X>0), got X=", target_x_offset)
		else:
			# Odd: stand left (X>0, PURPLE), serve to opposite diagonal (X<0, LIME)
			target_x_offset = min(serve_aim_offset_x, -1.5)  # Force negative X, farther from center
			print("[RED] Odd → target LIME (X<0), got X=", target_x_offset)
		
		var target_z: float = 4.6   # Blue's service box (positive Z)
		var target_position: Vector3 = Vector3(target_x_offset, 0.08, target_z)
		var target_dir: Vector3 = (target_position - serve_origin).normalized()
		target_dir.y = 0.32 + 0.22 * clamp(charge_ratio, 0.0, 1.0) + trajectory_arc_offset
		return target_dir.normalized() * serve_speed

func _update_serve_aim_input(delta: float) -> void:
	if game_state != "waiting":
		return
	if Input.is_key_pressed(KEY_Q):
		serve_aim_offset_x = clamp(serve_aim_offset_x - SERVE_AIM_STEP * delta * 10.0, -SERVE_AIM_MAX, SERVE_AIM_MAX)
	elif Input.is_key_pressed(KEY_E):
		serve_aim_offset_x = clamp(serve_aim_offset_x + SERVE_AIM_STEP * delta * 10.0, -SERVE_AIM_MAX, SERVE_AIM_MAX)
	
	if not serve_is_charging:
		state_label.text = "Hold SPACE to charge serve\nBlue's serve  Aim: " + _get_aim_label() + "  Arc: " + _get_arc_label()

func _update_arc_intent_input() -> void:
	var raise_pressed: bool = Input.is_key_pressed(KEY_R)
	var lower_pressed: bool = Input.is_key_pressed(KEY_F)
	
	if not serve_is_charging:
		arc_raise_was_pressed = raise_pressed
		arc_lower_was_pressed = lower_pressed
		return
	if raise_pressed and not arc_raise_was_pressed:
		trajectory_arc_offset = clamp(trajectory_arc_offset + ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)
	if lower_pressed and not arc_lower_was_pressed:
		trajectory_arc_offset = clamp(trajectory_arc_offset - ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)
	
	arc_raise_was_pressed = raise_pressed
	arc_lower_was_pressed = lower_pressed

func _get_aim_label() -> String:
	if serve_aim_offset_x < -0.2:
		return "Left"
	if serve_aim_offset_x > 0.2:
		return "Right"
	return "Center"

func _get_arc_label() -> String:
	if is_zero_approx(trajectory_arc_offset):
		return "Auto"
	if trajectory_arc_offset > 0.0:
		return "High +" + str(int(round(trajectory_arc_offset / ARC_INTENT_STEP)))
	return "Low " + str(int(round(trajectory_arc_offset / ARC_INTENT_STEP)))

func _apply_arc_intent_to_impulse(shot_impulse: Vector3) -> Vector3:
	if is_zero_approx(trajectory_arc_offset):
		return shot_impulse
	var adjusted_impulse: Vector3 = shot_impulse
	adjusted_impulse.y += trajectory_arc_offset * 3.6
	return adjusted_impulse

func _draw_trajectory(start_position: Vector3, start_velocity: Vector3) -> void:
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, trajectory_material)
	
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * ball.gravity_scale
	var pos: Vector3 = start_position
	var velocity: Vector3 = start_velocity
	
	for step in range(TRAJECTORY_STEPS):
		trajectory_mesh.surface_add_vertex(pos + Vector3(0.0, 0.03, 0.0))
		velocity.y -= gravity * TRAJECTORY_STEP_TIME
		pos += velocity * TRAJECTORY_STEP_TIME
		if pos.y <= 0.08:
			pos.y = 0.08
			trajectory_mesh.surface_add_vertex(pos + Vector3(0.0, 0.03, 0.0))
			break
	
	trajectory_mesh.surface_end()
	trajectory_mesh_instance.visible = true

func _clear_trajectory_predictor() -> void:
	if trajectory_mesh == null or trajectory_mesh_instance == null:
		return
	trajectory_mesh.clear_surfaces()
	trajectory_mesh_instance.visible = false
	if target_marker != null:
		target_marker.visible = false

func _update_red_target_marker() -> void:
	if target_marker == null or player_right == null:
		return
	
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var target_x: float
	
	if serve_from_right:
		# Even: Red at X<0, serves to X>0 (CYAN box)
		target_x = max(serve_aim_offset_x, 1.5)
	else:
		# Odd: Red at X>0, serves to X<0 (LIME box)
		target_x = min(serve_aim_offset_x, -1.5)
	
	# Target is in Blue's service box at Z = 4.6
	target_marker.global_position = Vector3(target_x, 0.1, 4.6)
	target_marker.visible = true

func _show_speedometer(speed_ms: float) -> void:
	if speed_label == null:
		return
	var mph: float = speed_ms * 2.23694  # m/s → mph
	speed_label.text = str(int(round(mph))) + " mph"
	# Color: green <25, yellow 25-40, orange 40-48, red 48+
	if mph >= 48.0:
		speed_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1, 1.0))
	elif mph >= 40.0:
		speed_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.0, 1.0))
	elif mph >= 25.0:
		speed_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
	else:
		speed_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	speed_label.modulate.a = 1.0
	speedometer_timer = 2.5

func _update_speedometer(delta: float) -> void:
	if speed_label == null or speedometer_timer <= 0.0:
		return
	speedometer_timer -= delta
	if speedometer_timer <= 0.6:
		speed_label.modulate.a = speedometer_timer / 0.6
	else:
		speed_label.modulate.a = 1.0

func _update_debug_label() -> void:
	if debug_label == null or ball == null:
		return
	
	# Always log ball data in playing state
	if game_state == "playing":
		var b_pos: Vector3 = ball.global_position
		var b_vel: Vector3 = ball.linear_velocity
		var b_paddle: Vector3 = player_left.get_paddle_position()
		var r_paddle: Vector3 = player_right.get_paddle_position()
		var b_dist: float = b_paddle.distance_to(b_pos)
		var r_dist: float = r_paddle.distance_to(b_pos)
		
		print("[DEBUG] ball=(x:", snapped(b_pos.x, 0.01), 
			" z:", snapped(b_pos.z, 0.01), 
			" y:", snapped(b_pos.y, 0.01), 
			") vel:", snapped(b_vel.length(), 0.1),
			" blue_d:", snapped(b_dist, 0.01),
			" red_d:", snapped(r_dist, 0.01),
			" last_hit:", ball.get_last_hit_by())
	
	if game_state != "playing":
		debug_label.text = ""
		return

	# ── Popup Error Tendency — live calculation ──
	# Formula (from player.gd _get_popup_tendency):
	#   popup = height_factor + distance_factor + charge_factor + contact_penalty
	#
	#   height_factor   = clamp((ball_y - 0.25) * 0.28, 0, 0.45)
	#     → higher ball above 0.25 = more upward error
	#   distance_factor = clamp((paddle_dist - 0.35) * 0.55, 0, 0.45)
	#     → reaching beyond 0.35 units = more error
	#   charge_factor   = clamp((0.45 - charge_ratio) * 0.4, 0, 0.45)
	#     → less charge time = more error (rushed shot)
	#   contact_penalty = +0.08 if STRETCHED, +0.18 if POPUP contact state
	#     → CLEAN: dist<0.52, ball_y<0.55, charge>0.32
	#     → STRETCHED: dist<0.72, ball_y<1.0, charge>0.18
	#     → POPUP: anything worse than STRETCHED
	#   Total clamped to [0.0, 0.6]
	#
	# Effect: popup_tendency adds upward angle to the shot impulse,
	# making the ball fly higher and shorter — a weak "popup" return.

	var ball_y: float = ball.global_position.y
	var bpos: Vector3 = ball.global_position

	# Blue player (human)
	var blue_paddle: Vector3 = player_left.get_paddle_position()
	var blue_dist: float = blue_paddle.distance_to(bpos)
	var blue_charge: float = clamp(serve_charge_time / 0.8, 0.0, 1.0)
	var blue_contact: int = player_left._get_contact_state(blue_dist, ball_y, blue_charge)
	var blue_popup: float = player_left._get_popup_tendency(blue_contact, blue_dist, ball_y, blue_charge)
	var blue_contact_name: String = ["CLEAN", "STRETCH", "POPUP"][blue_contact]

	# Red player (AI)
	var red_paddle: Vector3 = player_right.get_paddle_position()
	var red_dist: float = red_paddle.distance_to(bpos)
	var red_charge: float = clamp(player_right.ai_charge_time / 0.25, 0.0, 1.0) if player_right.ai_is_charging else 0.0
	var red_contact: int = player_right._get_contact_state(red_dist, ball_y, red_charge)
	var red_popup: float = player_right._get_popup_tendency(red_contact, red_dist, ball_y, red_charge)
	var red_contact_name: String = ["CLEAN", "STRETCH", "POPUP"][red_contact]

	debug_label.text = (
		"BLUE  dist=" + str(snapped(blue_dist, 0.01))
		+ " contact=" + blue_contact_name
		+ " popup=" + str(snapped(blue_popup, 0.01))
		+ "\nRED   dist=" + str(snapped(red_dist, 0.01))
		+ " contact=" + red_contact_name
		+ " popup=" + str(snapped(red_popup, 0.01))
		+ "\nBall y=" + str(snapped(ball_y, 0.01))
	)

func _on_any_paddle_hit(_player_num: int) -> void:
	if ball != null:
		_show_speedometer(ball.linear_velocity.length())

func _on_ball_bounced(_position: Vector3) -> void:
	_spawn_bounce_spot(_position)
	# Track which side bounced for two-bounce rule
	ball.record_bounce_side(_position.z)
	# Notify AI about bounce so it knows when it can hit
	if player_right != null:
		player_right.notify_ball_bounced(_position)

	# Double-bounce fault: ball bounced twice since last hit
	if ball.bounces_since_last_hit >= 2:
		var _last_hitter: int = ball.get_last_hit_by()
		if _position.z > 0:
			# Bounced twice on blue's side — red wins
			_on_point_scored(1)
		else:
			# Bounced twice on red's side — blue wins
			_on_point_scored(0)

func _spawn_bounce_spot(_position: Vector3) -> void:
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
	
	spot.position = position + Vector3(0.0, 0.09, 0.0)
	add_child(spot)
	
	var tween: Tween = create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 2.0)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 2.0)
	tween.finished.connect(spot.queue_free)

# ── DROP TEST (press T) ──────────────────────────────────────

func _start_drop_test() -> void:
	if _test_active:
		print("Drop test already running...")
		return

	# Use the GAME BALL for accurate physics
	_test_active = true
	_test_peak_y = 0.0
	_test_bounces.clear()
	_test_frame = 0
	_last_vy = 0.0
	_test_hit_floor = false

	# Save state and freeze game
	ball.is_in_play = false
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO

	# Drop from 78 inches above court at safe position
	var drop_m: float = 78.0 * 0.0254
	ball.global_position = Vector3(0.0, 0.075 + 0.06 + drop_m, 4.0)

	print("")
	print("=== DROP TEST STARTED (game ball) ===")
	print("  Bounce coeff: ", ball.physics_material_override.bounce)
	print("  Mass: ", ball.mass, " kg")
	print("  Gravity scale: ", ball.gravity_scale)
	print("  Drop: 78 in (", snapped(drop_m, 0.001), " m)")
	print("  Ball pos: ", ball.global_position)

var _last_vy: float = 0.0
var _test_hit_floor: bool = false

func _drop_test_tick() -> void:
	if not _test_active:
		return

	_test_frame += 1
	var h: float = ball.global_position.y - 0.06 - 0.075
	var vy: float = ball.linear_velocity.y

	if _test_frame % 20 == 0:
		print("  [F", _test_frame, "] h=", snapped(h, 0.001), "m vy=", snapped(vy, 0.01))

	# Detect first floor impact: vy was negative (falling), now positive (bouncing up)
	if not _test_hit_floor:
		if _last_vy < -1.0 and vy > 0.0:
			_test_hit_floor = true
			_test_peak_y = 0.0
			print("  IMPACT at frame ", _test_frame)
		_last_vy = vy
		return

	# Track peak height while rising
	if h > _test_peak_y:
		_test_peak_y = h

	# Detect peak: velocity flipped from up to down
	if _last_vy > 0.1 and vy <= 0.0 and _test_peak_y > 0.005:
		var peak_in: float = _test_peak_y / 0.0254
		_test_bounces.append(peak_in)
		var n: int = _test_bounces.size()
		print("  Bounce ", n, ": ", snapped(peak_in, 0.1), " in (", snapped(_test_peak_y, 0.001), " m)")
		_test_peak_y = 0.0
		if n >= 2:
			_end_drop_test()

	_last_vy = vy

func _end_drop_test() -> void:
	_test_active = false
	var b1: float = _test_bounces[0]
	var cor: float = sqrt(b1 / 78.0)
	print("")
	print("=== DROP TEST RESULTS ===")
	print("  Bounce 1: ", snapped(b1, 0.1), " in  (from 78 in drop)")
	if _test_bounces.size() > 1:
		print("  Bounce 2: ", snapped(_test_bounces[1], 0.1), " in")
	print("  Measured COR: ", snapped(cor, 0.001))
	print("  USA PB spec: 30-34 in (COR 0.620-0.660)")
	if b1 >= 30.0 and b1 <= 34.0:
		print("  PASS")
	elif b1 < 30.0:
		print("  FAIL - too dead (increase bounce)")
	else:
		print("  FAIL - too bouncy (decrease bounce)")
	print("=========================")
	print("  Press T again to re-test, SPACE to resume game")
