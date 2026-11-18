extends Node



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const HandPresentation = preload("res://scripts/player_hand_presentation.gd")
const ArmAnatomy = preload("res://scripts/arm_anatomy.gd")
const BodySurface = preload("res://scripts/body_clearance.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const BALL_RADIUS: = 0.0375
const VIEW_SIZE: = Vector2i(384, 432)
var game
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var view_columns: Array[Control] = []
var camera_index: = 0
var source_hashes: = {}
var started_at: = ""
var reconnect_focus_exit: = false
var reconnect_focus_enter: = false
var old_fx_visible: = true
var observed_bounces: Array[int] = [0, 0]
var feet_established: Array[bool] = [false, false]
var volley_follow_active: Array[bool] = [false, false]
var last_bounce_frame: = -1
var scenarios: Array[Dictionary] = []
var results: Array[Dictionary] = []
var current: Dictionary = {}
var samples: Array[Dictionary] = []
var output: = "user://pose_review"
var batch: = false
var render: = false
var save_frames: = false
var playing: = false
var selected: = 0
var frame_number: = 0
var slow: = false
var status: Label
var selector: OptionButton
var stage: = "READY"
var hit_frame: = -1
var requested_next: = -1
var surface: Array[Vector3] = []
var sim_time: = 0.0



var sample_time_seconds: = 0.0
var capture_stride: = 1
var last_captured_stage: = ""
signal presentation_ready
signal after_animation_ready

func _ready() -> void :
	process_priority = 10000
	if OS.has_environment("POSE_REVIEW_HZ"):
		var hz: = OS.get_environment("POSE_REVIEW_HZ").to_int()
		if hz not in [30, 60, 120]:
			push_error("POSE_REVIEW_HZ must be 30, 60 or 120")
			get_tree().quit(2)
			return
		Engine.physics_ticks_per_second = hz
	started_at = Time.get_datetime_string_from_system(true)
	source_hashes = _source_hashes()
	batch = OS.has_environment("POSE_REVIEW_BATCH")
	render = DisplayServer.get_name() != "headless"
	save_frames = render and OS.has_environment("POSE_REVIEW_CAPTURE")
	if OS.has_environment("POSE_REVIEW_OUT"): output = OS.get_environment("POSE_REVIEW_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if OS.has_environment("POSE_REVIEW_STRIDE"): capture_stride = maxi(1, OS.get_environment("POSE_REVIEW_STRIDE").to_int())
	seed(77811)
	surface = Geometry.sample_head_surface()
	_build_scenarios()
	var pause = get_node("/root/PauseController")
	var window = get_tree().root
	reconnect_focus_exit = window.focus_exited.is_connected(pause._on_window_focus_exited)
	reconnect_focus_enter = window.focus_entered.is_connected(pause._on_window_focus_entered)
	if reconnect_focus_exit: window.focus_exited.disconnect(pause._on_window_focus_exited)
	if reconnect_focus_enter: window.focus_entered.disconnect(pause._on_window_focus_entered)
	old_fx_visible = get_node("/root/FXPool").visible
	get_tree().paused = false
	if render: _build_review_ui()
	if OS.has_environment("POSE_REVIEW_SLOW"): _toggle_slow()
	call_deferred("_start")

func _process(_delta: float) -> void :
	presentation_ready.emit()
	if playing: create_tween().tween_callback( func(): after_animation_ready.emit())

func _physics_process(delta: float) -> void :
	sample_time_seconds += delta

func _wait_seconds(duration: float) -> void :
	var start: = sim_time
	while sim_time - start < duration - 1e-05: await _tick()

func _build_scenarios() -> void :
	for def in PostureLibrary.instance().all_definitions():
		if def.has_zone:
			scenarios.append({"id": "pose_%02d" % def.posture_id, "name": def.display_name, "pose": def.posture_id, "power": 0.65, "bounce": 0})
	scenarios.append_array([
		{"id": "charge_forehand", "name": "Charge Forehand / full drive", "pose": 0, "catalog_context": 8, "power": 1.0, "bounce": 1}, 
		{"id": "charge_backhand", "name": "Charge Backhand / full drive", "pose": 2, "catalog_context": 9, "power": 1.0, "bounce": 1}, 
		{"id": "ready", "name": "Ready / track incoming", "pose": 0, "catalog_context": 20, "power": 0.3, "bounce": 1}, 
		{"id": "kitchen_dink", "name": "Kitchen dink", "pose": 13, "power": 0.3, "bounce": 1, "kitchen": true}, 
		{"id": "kitchen_block", "name": "Kitchen-line compact block", "pose": 1, "power": 0.5, "bounce": 0, "kitchen_line": true}, 
		{"id": "topspin_drive", "name": "Topspin drive", "pose": 0, "power": 1.0, "bounce": 1, "spin": 1}, 
		{"id": "slice_drive", "name": "Slice backhand", "pose": 2, "power": 1.0, "bounce": 1, "spin": 2}, 
		{"id": "drop", "name": "Drop reset", "pose": 0, "power": 0.65, "bounce": 1, "intent": "DROP"}, 
		{"id": "jump_smash", "name": "Jump smash + landing", "pose": 4, "power": 0.95, "bounce": 0, "jump": true}, 
		{"id": "slow_lateral", "name": "Slow lateral / stop / drive", "pose": 0, "power": 1.0, "bounce": 1, "move": "move_right", "move_speed": 0.8}, 
		{"id": "fast_diagonal", "name": "Fast diagonal / stop / drive", "pose": 0, "power": 1.0, "bounce": 1, "move": "move_right", "second_move": "move_up", "move_speed": 6.5}, 
		{"id": "approach_stop", "name": "Lateral approach / plant / drive", "pose": 0, "power": 1.0, "bounce": 1, "move": "move_right"}, 
		{"id": "backpedal_stop", "name": "Backpedal / plant / overhead", "pose": 4, "power": 0.85, "bounce": 0, "move": "move_down"}, 
		{"id": "dink_exchange", "name": "Crosscourt dink exchange", "pose": 13, "drill_mode": "DINK", "direction": 1, "expected_hits": 3, "duration": 18.0}, 
		{"id": "hands_exchange", "name": "Fast FH/BH kitchen exchange", "pose": 1, "drill_mode": "HANDS", "direction": 1, "expected_hits": 4, "duration": 12.0}, 
		{"id": "hands_red_view", "name": "Fast blocks / red player view", "pose": 1, "drill_mode": "HANDS", "direction": 1, "camera_player": 1, "expected_hits": 4, "duration": 12.0}, 
		{"id": "wide_dink_exchange", "name": "Wide crosscourt dink / recovery", "pose": 13, "drill_mode": "DINK", "direction": -1, "variant": "WIDE", "expected_hits": 3, "duration": 20.0}, 
		{"id": "popup_attack", "name": "Red attacks a pop-up / legal feet", "pose": -1, "popup_seed": 112, "camera_player": 1, "expected_hits": 0, "expected_opponent_hits": 1, "expected_tactic": "ATTACK"}, 
		{"id": "popup_blue_recovery", "name": "Blue tracks an attack / recovery", "pose": -1, "popup_seed": 112, "camera_player": 0, "expected_hits": 0, "expected_opponent_hits": 1, "expected_tactic": "ATTACK"}, 
		{"id": "popup_soft", "name": "Red chooses soft reply / same pop-up", "pose": -1, "popup_seed": 116, "camera_player": 1, "expected_hits": 0, "expected_opponent_hits": 1, "expected_tactic": "SOFT"}, 
		{"id": "nvz_toe_reject", "name": "NVZ toe contact / reject volley", "pose": 12, "power": 0.5, "bounce": 0, "root_z": 2.24, "expected_hits": 0, "expect_rejected": true}, 
		{"id": "body_jam", "name": "Body jam / short elbow space", "pose": 12, "power": 0.45, "bounce": 0, "speed": 12.0, "lead": 1.2}, 
		{"id": "low_reversal", "name": "Late low ball / stop and reverse", "pose": 5, "power": 0.55, "bounce": 1, "combo": "LOW_REVERSAL"}, 
		{"id": "jump_next_ball", "name": "Jump landing / immediate next ball", "pose": 4, "power": 0.95, "bounce": 0, "combo": "JUMP_NEXT", "expected_hits": 2}, 
		{"id": "cancel_speedup", "name": "Cancel queued charge / speed-up", "pose": 0, "power": 0.75, "bounce": 0, "combo": "CANCEL_SPEEDUP"}, 
		{"id": "late_tap_reject", "name": "Late tap after ball passes / reject", "pose": 2, "combo": "LATE_TAP", "expected_hits": 0, "expect_rejected": true}, 
		{"id": "gait_slow_shuffle", "name": "Sustained slow shuffle / reversal", "gait": true, "move_speed": 0.8, "start": Vector3(-0.8, 0, 4.2), "actions": ["move_right"], "reverse": ["move_left"], "duration": 1.8, "expected_hits": 0}, 
		{"id": "gait_analog_quarter", "name": "Quarter stick / controlled shuffle", "gait": true, "move_speed": 5.8, "strength": 0.25, "start": Vector3(-0.8, 0, 4.2), "actions": ["move_right"], "reverse": ["move_left"], "duration": 0.9, "expected_hits": 0}, 
		{"id": "gait_analog_half", "name": "Half stick / controlled lateral", "gait": true, "move_speed": 5.8, "strength": 0.5, "start": Vector3(-1.3, 0, 4.2), "actions": ["move_right"], "reverse": ["move_left"], "duration": 0.9, "expected_hits": 0}, 
		{"id": "gait_fast_lateral", "name": "Lateral run / plant / reversal", "gait": true, "move_speed": 5.8, "start": Vector3(-1.8, 0, 4.2), "actions": ["move_right"], "reverse": ["move_left"], "duration": 0.65, "expected_hits": 0}, 
		{"id": "gait_fast_diagonal", "name": "Diagonal run / plant / return", "gait": true, "move_speed": 5.8, "start": Vector3(-1.5, 0, 5.6), "actions": ["move_right", "move_up"], "reverse": ["move_left", "move_down"], "duration": 0.55, "expected_hits": 0}, 
		{"id": "gait_forward_back", "name": "Forward shuffle / stop / backpedal", "gait": true, "move_speed": 1.8, "start": Vector3(0, 0, 5.2), "actions": ["move_up"], "reverse": ["move_down"], "duration": 1.15, "expected_hits": 0}, 
	])
	for option in Styles.options():
		scenarios.append({"id": "serve" if option.id == 0 else "serve_" + option.key.to_lower(), "name": option.label + " serve / " + option.delivery, "pose": -1, "power": 0.85, "serve": true, "serve_style": option.id, "requires_serve_bounce": Styles.is_drop(option.id)})

func _build_review_ui() -> void :
	var layer: = CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var panel: = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	var toolbar: = HBoxContainer.new()
	panel.add_child(toolbar)
	selector = OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.custom_minimum_size.y = 80
	selector.add_theme_font_size_override("font_size", 20)
	for item in scenarios: selector.add_item(item.name)
	selector.item_selected.connect( func(index): requested_next = index; if not playing: _run_requested())
	panel.move_child(toolbar, 0)
	panel.add_child(selector)
	panel.move_child(selector, 0)
	for item in [["Replay", _replay], ["1x / ¼x", _toggle_slow], ["Angle", _cycle_camera], ["Exit", _exit_review]]:
		var button: = Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(80, 80)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(item[1])
		toolbar.add_child(button)
	status = Label.new()
	status.custom_minimum_size.y = 48
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	var strip: = HBoxContainer.new()
	strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(strip)
	for angle in ["FRONT", "SIDE", "THREE-QUARTER"]:
		var column: = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(column)
		view_columns.append(column)
		var label: = Label.new()
		label.text = angle
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		var viewport: = SubViewport.new()
		viewport.size = VIEW_SIZE
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.handle_input_locally = false
		add_child(viewport)
		views.append(viewport)
		var camera: = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.65
		viewport.add_child(camera)
		camera.current = true
		cameras.append(camera)
		var texture: = TextureRect.new()
		texture.texture = viewport.get_texture()
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(texture)
	get_viewport().size_changed.connect(_fit_cameras)
	_fit_cameras()

func _cycle_camera() -> void :
	camera_index = (camera_index + 1) % 3
	_fit_cameras()

func _fit_cameras() -> void :
	var portrait: = get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
	for index in range(view_columns.size()): view_columns[index].visible = not portrait or index == camera_index

func _replay() -> void :
	requested_next = selected
	if not playing: _run_requested()

func _toggle_slow() -> void :
	slow = not slow
	if slow: get_node("/root/TimeScale").request_slowmo("pose_review", 0.25)
	else: get_node("/root/TimeScale").release("pose_review")

func _exit_tree() -> void :
	Input.action_release("ui_accept")
	for action in ["move_up", "move_down", "move_left", "move_right"]: Input.action_release(action)
	if is_inside_tree():
		var time_scale = get_node_or_null("/root/TimeScale")
		if time_scale: time_scale.release("pose_review")
		var fx = get_node_or_null("/root/FXPool")
		if fx: fx.visible = old_fx_visible
		var pause = get_node_or_null("/root/PauseController")
		if pause:
			var window = get_tree().root
			if reconnect_focus_exit and not window.focus_exited.is_connected(pause._on_window_focus_exited): window.focus_exited.connect(pause._on_window_focus_exited)
			if reconnect_focus_enter and not window.focus_entered.is_connected(pause._on_window_focus_entered): window.focus_entered.connect(pause._on_window_focus_entered)

func _exit_review() -> void :
	get_node("/root/TimeScale").release("pose_review")
	get_tree().root.disable_3d = false
	get_node("/root/FXPool").show()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _start() -> void :
	if batch:
		var only: = OS.get_environment("POSE_REVIEW_ONLY")
		if only != "":
			for requested_id in only.split(","):
				if not scenarios.any( func(item): return item.id == requested_id):
					push_error("Unknown review scenario: " + requested_id)
					get_tree().quit(2)
					return
		for index in range(scenarios.size()):
			if only != "" and not scenarios[index].id in only.split(","): continue
			selected = index
			await _run_case(scenarios[index])
		_write_report()
		var failed: = 0
		for result in results:
			if not result.passed: failed += 1
		print("POSE REVIEW: %d scenarios, %d failed; metrics: %s" % [results.size(), failed, output])


		get_node("/root/TimeScale").release("pose_review")
		if is_instance_valid(game): game.process_mode = Node.PROCESS_MODE_DISABLED
		var retire_frame: = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 3
		while Engine.get_physics_frames() < retire_frame: await get_tree().physics_frame
		if is_instance_valid(game): game.queue_free()
		await get_tree().process_frame
		get_tree().quit(0 if failed == 0 else 1)
	else:
		requested_next = 0
		_run_requested()

func _run_requested() -> void :
	while requested_next >= 0:
		selected = requested_next
		requested_next = -1
		await _run_case(scenarios[selected])
	_write_report()

func _setup_game() -> void :
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.input_handler.set_process(false)
	game.reaction_button.auto_fire_on_perfect = false
	game.ai_difficulty = 2
	game.game_serve.cleanup()
	game.player_left.hitting.clear_charge_visual()
	game.player_left.hitting.is_in_follow_through = false
	game.player_left.posture.transition_pose_blend = null
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.start_rally(0, true)
	game.rally_scorer._serve_was_hit = true
	game.player_left.global_position = Vector3(0, game.player_left.ground_y, 3.2)
	game.player_right.set_ai_movement_enabled(false)
	game.player_right.set_process(false)
	game.player_right.set_physics_process(false)
	game.player_right.hide()
	game.ball.is_in_play = false
	game.ball.freeze = true
	game.ball.hide()
	game.ball.global_position = Vector3(0, 1.2, 0.5)
	game._set_debug_visuals_visible(false)
	game._set_debug_zones_visible(false)
	for actor in [game.player_left, game.player_right]:
		if actor.posture.posture_ghost_root: actor.posture.posture_ghost_root.hide()
		actor.debug_visual.set_debug_visible(false)
		actor.debug_visual.set_intent_indicators_visible(false)
	get_node("/root/FXPool").hide()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()
	for viewport in views: viewport.world_3d = game.get_world_3d()
	if batch and render: get_tree().root.disable_3d = true

func _feed(item: Dictionary) -> void :
	var p = game.player_left
	var b = game.ball
	b.freeze = false
	b.show()
	var def = PostureLibrary.instance().get_def(item.pose)
	b.reset_rally_state()
	b.both_bounces_complete = true
	b.serving_side_bounced = true
	b.receiving_side_bounced = true
	b.bounces_since_last_hit = 0
	b.ball_bounced_since_last_hit = false
	observed_bounces = [0, 0]
	b.global_position = Vector3(p.global_position.x + def.paddle_forehand_mul, 1.0 + def.paddle_y_offset, p.global_position.z - def.zone_forward_offset - item.get("lead", 0.65))
	b.linear_velocity = Vector3(0, item.get("vertical_speed", 1.1), item.get("speed", 4.0))
	b.angular_velocity = Vector3.ZERO
	b.last_hit_by = 1
	b.is_in_play = true
	b.flight_id += 1
	if not item.has("speed") and not item.has("lead") and not item.get("jump", false) and item.get("bounce", 0) == 0:
		var target: = Vector3(p.global_position.x + def.paddle_forehand_mul, maxf(0.4, 1.0 + def.paddle_y_offset), p.global_position.z - def.zone_forward_offset)
		_launch_for_duration(target, 0.65)
	if item.get("bounce", 0) > 0:
		if not _select_bounced_feed(item, def): current.issues.append("No physically bounced feed found for pose%d" % item.pose)
	if item.get("jump", false):
		_launch_for_duration(Vector3(0, 2.15, p.global_position.z - 0.45), 0.8)

func _launch_for_duration(target: Vector3, duration: float) -> void :
	var origin: = Vector3(target.x, maxf(0.65, target.y + 0.25), target.z - 4.0 * duration)
	var velocity: Vector3 = (target - origin) / duration
	velocity.y += 0.5 * preload("res://scripts/ball.gd").get_effective_gravity() * duration
	for step in range(12):
		velocity += (target - game.shot_physics._spin_position_after(origin, velocity, Vector3.ZERO, duration)) / duration * 0.86
	game.ball.global_position = origin
	game.ball.linear_velocity = velocity

func _select_bounced_feed(item: Dictionary, def: PostureDefinition) -> bool:


	var p = game.player_left
	var b = game.ball
	for lead in [1.5, 2.4, 3.0, 3.8]:
		for speed in [3.0, 4.0, 6.0]:
			for height in [0.8, 1.2, 1.6, 2.0, 2.6, 3.0]:
				for vertical in [-4.0, -2.0, -6.0]:
					b.global_position = Vector3(p.global_position.x + def.paddle_forehand_mul, height, p.global_position.z - def.zone_forward_offset - lead)
					b.linear_velocity = Vector3(0, vertical, speed)
					var flight: Dictionary = Flight.trace(b.global_position, b.linear_velocity, Vector3.ZERO)
					var bounce: Vector3 = flight.get("first_bounce", Vector3.INF)
					if bounce.z <= 0 or absf(bounce.x) >= PickleballConstants.COURT_WIDTH * 0.5 or flight.get("net_hit", false): continue
					var plan: Dictionary = Planner.select(p, b, flight)
					if not plan.is_empty() and plan.posture == item.pose and plan.get("bounces", 0) == 1 and plan.time > maxf(0.3, item.get("power", 0.65) * PickleballConstants.MAX_SERVE_CHARGE_TIME + 0.12):
						_event("Real-bounce feed: start=%s velocity=%s predicted_bounce=%s" % [b.global_position, b.linear_velocity, bounce])
						return true
	return false

func _on_observed_bounce(_position: Vector3) -> void :
	if current.get("serve", false) and current.hits.is_empty():
		current.serve_drop_bounces += 1
		last_bounce_frame = frame_number
		stage = "BOUNCE"
		_event("Observed serve drop/floor bounce")
	if game.ball.is_in_play and game.ball.last_hit_by in [0, 1]:
		var receiver: int = 1 - game.ball.last_hit_by
		observed_bounces[receiver] += 1
		_event("Observed incoming floor bounce for player%d" % receiver)
		if receiver == current.get("camera_player", 0):
			last_bounce_frame = frame_number
			stage = "BOUNCE"

func _foot_nvz(player) -> Dictionary:
	var minimum_abs_z: = INF
	var minimum_sole_y: = INF
	var touching_inside: = false
	var projected_inside: = false
	var foot_records: = []
	for leg in [player.right_leg_node, player.left_leg_node]:
		var mesh: MeshInstance3D = leg.foot_mesh


		var bounds: AABB = mesh.mesh.get_aabb()
		var sole: = INF
		var foot_inside: = false
		var bounds_min: = Vector3.INF
		var bounds_max: = - Vector3.INF
		for corner in range(8):
			var point: Vector3 = mesh.global_transform * bounds.get_endpoint(corner)
			bounds_min = bounds_min.min(point)
			bounds_max = bounds_max.max(point)
			minimum_abs_z = minf(minimum_abs_z, absf(point.z))
			sole = minf(sole, point.y)
			if absf(point.z) <= PickleballConstants.NON_VOLLEY_ZONE and absf(point.x) <= PickleballConstants.COURT_WIDTH * 0.5: foot_inside = true
		var grounded: bool = sole <= player.COURT_FLOOR_Y + 0.015
		minimum_sole_y = minf(minimum_sole_y, sole)
		projected_inside = projected_inside or foot_inside
		touching_inside = touching_inside or (foot_inside and grounded)
		foot_records.append({"sole_floor_gap_m": sole - player.COURT_FLOOR_Y, "grounded": grounded, "projected_in_nvz": foot_inside, "box_min": _v(bounds_min), "box_max": _v(bounds_max)})
	return {"in_nvz": touching_inside, "projected_in_nvz": projected_inside, "nearest_foot_z": minimum_abs_z, "lowest_sole_y": minimum_sole_y, "sole_floor_gap_m": minimum_sole_y - player.COURT_FLOOR_Y, "feet": foot_records}

func _observe_feet(side: int, geometry: Dictionary) -> void :
	var both: = true
	for foot in geometry.feet:
		if foot.grounded and foot.projected_in_nvz: feet_established[side] = false
		both = both and foot.grounded and not foot.projected_in_nvz
	if both: feet_established[side] = true

func _run_case(item: Dictionary) -> void :
	playing = true
	current = item.duplicate(true)
	samples = []
	frame_number = 0
	sim_time = 0.0
	hit_frame = -1
	stage = "READY"
	current.hits = []
	current.opponent_hits = []
	current.serve_drop_bounces = 0
	feet_established = [false, false]
	volley_follow_active = [false, false]
	current.events = []
	last_bounce_frame = -1
	observed_bounces = [0, 0]
	current.issues = []
	current.stages = {}
	last_captured_stage = ""
	await _setup_game()
	var p = game.player_left
	if item.get("gait", false):
		await _run_gait(item)
		_finish_case(item)
		return
	if item.has("popup_seed"):
		await _run_popup(item)
		_finish_case(item)
		return
	if item.has("combo"):
		await _run_combo(item)
		_finish_case(item)
		return
	if item.has("drill_mode"):
		await _run_live_drill(item)
		_finish_case(item)
		return
	if item.has("root_z"): p.global_position.z = item.root_z
	if item.get("kitchen", false): p.global_position.z = 1.9
	if item.get("kitchen_line", false): p.global_position.z = 2.55
	if item.get("jump", false): p.global_position.z = 3.5
	game.selected_spin_mode = item.get("spin", 0)
	game.selected_shot_intent = item.get("intent", "AUTO")
	if item.get("serve", false):
		game.serving_team = 0
		game.ball.freeze = false
		game.ball.show()
		game._reset_ball()
		if not game.game_serve.select_serve_style(item.get("serve_style", 0)):
			current.issues.append("Serve style selection rejected")
		game.game_serve.serve_phase_changed.connect( func(value: String, style_id: int):
			stage = value
			_event("Serve phase %s style %d" % [value, style_id]))
	game.ball.bounced.connect(_on_observed_bounce)
	game.ball.hit_by_paddle.connect(_on_hit)
	game.game_serve.serve_launched.connect(_on_serve_hit)
	if item.id in ["approach_stop", "fast_diagonal"]: p.global_position.x = -1.2
	if item.id == "fast_diagonal": p.global_position.z = 5.8
	if item.has("move"):
		p.move_speed = item.get("move_speed", 5.8)
		Input.action_press(item.move)
		if item.has("second_move"): Input.action_press(item.second_move)
		await _wait_seconds(0.5)
		Input.action_release(item.move)
		if item.has("second_move"): Input.action_release(item.second_move)
		await _wait_seconds(0.4)
	else: await _wait_seconds(0.4)
	if item.get("serve", false):
		stage = "PREP"
		await _press_release(item.power)
	else:
		await get_tree().physics_frame
		_feed(item)
		await _wait_seconds(1.0 / 30.0)
		var human = p.posture.human_contact
		current.selected_pose = human.contact.get("posture", -1)
		if item.get("expect_rejected", false):
			if not human.contact.is_empty(): current.issues.append("Foot-in-NVZ volley was incorrectly selected")
		elif human.contact.is_empty(): current.issues.append("No live incoming contact selected")
		elif human.contact.posture != item.pose: current.issues.append("Expected pose %d, selected %d" % [item.pose, human.contact.posture])
		stage = "PREP"
		await _press_release(item.power)
	await _wait_seconds(2.3 if item.get("serve", false) else 1.67)
	_finish_case(item)

func _finish_case(item: Dictionary) -> void :
	var p = game.player_left
	var expected_hits: int = item.get("expected_hits", 1)
	current.samples = samples
	_assert_live_geometry()
	if current.hits.size() != expected_hits: current.issues.append("Expected %d real hits, got %d" % [expected_hits, current.hits.size()])
	if p.posture.human_contact.phase != -1: current.issues.append("Did not recover")
	if p.is_jumping: current.issues.append("Did not land")
	if item.has("expected_opponent_hits") and current.opponent_hits.size() != item.expected_opponent_hits: current.issues.append("Expected %d actual opponent hits, got %d" % [item.expected_opponent_hits, current.opponent_hits.size()])
	if item.has("expected_tactic") and current.get("last_kitchen_tactic", "") != item.expected_tactic: current.issues.append("Expected tactic %s, got %s" % [item.expected_tactic, current.get("last_kitchen_tactic", "none")])
	if item.get("requires_serve_bounce", false) and current.serve_drop_bounces < 1: current.issues.append("Drop serve launched without an observed pre-contact floor bounce")
	if item.get("serve", false):
		if not item.get("requires_serve_bounce", false) and current.serve_drop_bounces > 0: current.issues.append("Volley serve unexpectedly bounced before contact")
		if game.game_serve.is_release_pending() or game.game_serve.get_serve_timing_state().get("locked", false): current.issues.append("Serve delivery or recovery did not finish")
	if item.has("strength"):
		var observed_speed: = 0.0
		for sample in samples:
			observed_speed = maxf(observed_speed, Vector3(sample.velocity[0], sample.velocity[1], sample.velocity[2]).length())
		current.observed_analog_speed = observed_speed
		current.expected_analog_speed = item.move_speed * item.strength
		if absf(observed_speed - current.expected_analog_speed) > 0.02: current.issues.append("Analog magnitude lost: expected %.3f, observed %.3fm/s" % [current.expected_analog_speed, observed_speed])
	current.passed = current.issues.is_empty()
	results.append(current.duplicate(true))
	print("POSE REVIEW CASE: %s selected=%s hits=%d passed=%s issues=%s" % [item.id, current.get("selected_pose", "serve"), current.hits.size(), current.passed, current.issues])
	_write_report()
	playing = false

func _run_gait(item: Dictionary) -> void :
	var p = game.player_left
	p.global_position = Vector3(item.start.x, p.ground_y, item.start.z)
	p.move_speed = item.move_speed
	await _wait_seconds(0.4)
	for segment in ["actions", "reverse"]:
		stage = "MOVE" if segment == "actions" else "REVERSE"
		_event(stage)
		for action in item[segment]: Input.action_press(action, item.get("strength", 1.0))
		await _wait_seconds(item.duration)
		for action in item[segment]: Input.action_release(action)
		stage = "PLANT"
		_event("Stop and establish support")
		await _wait_seconds(0.45)
	stage = "READY AGAIN"
	await _wait_seconds(0.5)

func _assert_live_geometry() -> void :
	var worst_grip: = {"value": 0.0, "frame": -1}
	var worst_wrist: = {"value": 0.0, "frame": -1}
	var worst_leg: = {"value": 0.0, "frame": -1}
	var minimums: = {"face_clearance_m": {"value": INF, "frame": -1}, "chest_clearance_m": {"value": INF, "frame": -1}, "paddle_floor_clearance_m": {"value": INF, "frame": -1}, "limb": {"value": INF, "frame": -1, "name": ""}}
	var body_minimums: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	var actor_samples: Array = []
	for sample in samples:
		var primary: Dictionary = sample.duplicate()
		primary.actor = "blue"
		actor_samples.append(primary)
		if sample.has("opponent"):
			var opponent: Dictionary = sample.opponent.duplicate()
			opponent.frame = sample.frame
			opponent.actor = "red"
			actor_samples.append(opponent)
	for sample in actor_samples:
		if sample.grip_reach_m > worst_grip.value: worst_grip = {"value": sample.grip_reach_m, "frame": sample.frame, "actor": sample.actor}
		if sample.anatomical_wrist_reach_m > worst_wrist.value: worst_wrist = {"value": sample.anatomical_wrist_reach_m, "frame": sample.frame, "actor": sample.actor}
		for foot in sample.feet:
			if foot.extension_ratio > worst_leg.value: worst_leg = {"value": foot.extension_ratio, "frame": sample.frame, "actor": sample.actor}
		for key in ["face_clearance_m", "chest_clearance_m", "paddle_floor_clearance_m"]:
			if sample[key] < minimums[key].value: minimums[key] = {"value": sample[key], "frame": sample.frame}
		for key in sample.limb_clearance_m:
			if sample.limb_clearance_m[key] < minimums.limb.value: minimums.limb = {"value": sample.limb_clearance_m[key], "frame": sample.frame, "name": "%s %s" % [sample.actor, key]}
		for region in sample.body_surface_clearance_m:
			body_minimums[region] = minf(body_minimums[region], sample.body_surface_clearance_m[region])



	if worst_leg.value > 1.001: current.issues.append("%s leg extension %.4f > 1.001 at frame%d" % [worst_leg.get("actor", ""), worst_leg.value, worst_leg.frame])
	for key in ["face_clearance_m", "chest_clearance_m", "paddle_floor_clearance_m", "limb"]:
		var tolerance: = -0.002 if key in ["paddle_floor_clearance_m", "limb"] else 0.0
		if minimums[key].value < tolerance: current.issues.append("%s %.4fm at frame%d %s" % [key, minimums[key].value, minimums[key].frame, minimums[key].get("name", "")])
	for region in body_minimums:
		if body_minimums[region] < 0.0: current.issues.append("Paddle intersects actual %s body region %.4fm" % [region, body_minimums[region]])
	var grip_issue: = false
	var rotation_issue: = false
	var rotation_diagnostics: = []
	for sample in actor_samples:
		if sample.grip_error_m > 0.025 and not grip_issue:
			current.issues.append("%s hand misses grip %.4fm at frame%d" % [sample.actor, sample.grip_error_m, sample.frame])
			grip_issue = true
		var orientation: Dictionary = sample.orientations
		if orientation.hand_step_deg > 40.0:
			rotation_diagnostics.append({"actor": sample.actor, "frame": sample.frame, "hand_step_deg": orientation.hand_step_deg, "rate_deg_s": orientation.hand_rate_deg_s})


		if orientation.hand_step_deg > 90.0 and orientation.hand_rate_deg_s > 5400.0 and not rotation_issue:
			current.issues.append("%s hand/paddle rotation discontinuity %.1fdeg at frame%d" % [sample.actor, orientation.hand_step_deg, sample.frame])
			rotation_issue = true
	current.rotation_diagnostics = rotation_diagnostics
	var arm_issue: = false
	for sample in actor_samples:
		for index in range(sample.arms.size()):
			var arm: Dictionary = sample.arms[index]
			var invalid: bool = arm.visible_wrist_reach_m > arm.link_budget_m + 1e-05 or arm.visual_stretch > 1.001 or arm.upper_length_error_m > 0.0001 or arm.forearm_length_error_m > 0.0001
			if invalid and not arm_issue:
				current.issues.append("%s arm%d anatomical wrist reach %.4fm / %.4fm, scale %.5f, link errors %.6f/%.6fm at frame%d" % [sample.actor, index, arm.visible_wrist_reach_m, arm.link_budget_m, arm.visual_stretch, arm.upper_length_error_m, arm.forearm_length_error_m, sample.frame])
				arm_issue = true
	var hold_issue: = false
	for sample in actor_samples:
		if sample.serve_held_surface_gap_m != null and absf(sample.serve_held_surface_gap_m) > 0.003 and not hold_issue:
			current.issues.append("Held ball/hand surface gap %.4fm at frame%d" % [sample.serve_held_surface_gap_m, sample.frame])
			hold_issue = true
	var floor_issue: = false
	var plant_issue: = false
	for sample in actor_samples:
		if not sample.has("foot_nvz"): continue
		for index in range(sample.foot_nvz.feet.size()):
			var foot: Dictionary = sample.foot_nvz.feet[index]
			if foot.sole_floor_gap_m < -0.002 and not floor_issue:
				current.issues.append("%s shoe sole below floor %.4fm at frame%d" % [sample.actor, foot.sole_floor_gap_m, sample.frame])
				floor_issue = true
			if not sample.airborne and sample.foot_lock[index] and Vector3(sample.velocity[0], sample.velocity[1], sample.velocity[2]).length() < 0.15 and foot.sole_floor_gap_m > 0.015 and not plant_issue:
				current.issues.append("%s planted shoe floats %.4fm at frame%d" % [sample.actor, foot.sole_floor_gap_m, sample.frame])
				plant_issue = true
	for hit in current.hits + current.opponent_hits:
		if absf(hit.head_surface_gap_m) > 0.002: current.issues.append("Contact surface gap %.4fm at frame%d" % [hit.head_surface_gap_m, hit.frame])
	current.geometry = {"max_grip": worst_grip, "max_anatomical_wrist_reach": worst_wrist, "grip_reach_note": "Legacy virtual grip anchor distance is diagnostic; actual socket, exact segment lengths and scale enforce arm reach", "max_leg": worst_leg, "minimum_clearances": minimums, "body_surface_minimums": body_minimums, "limb_method": "Actual tapered mesh vertices, edge midpoints and triangle centroids against unchanged paddle signed distance; old capsules retained separately"}

func _event(label: String) -> void :
	current.events.append({"frame": frame_number, "sim_time": sim_time, "label": label})

func _press_release(power: float) -> void :

	game.input_handler.set_process(true)
	Input.action_press("ui_accept")
	_event("Press cue TTC %.4fs" % game.player_left.posture.human_contact.contact.get("time", -1.0))
	var held: = 0.0
	var target_duration: = power * PickleballConstants.MAX_SERVE_CHARGE_TIME
	var human = game.player_left.posture.human_contact
	while held + 1e-05 < target_duration:
		if not current.get("serve", false):
			if human.contact.is_empty(): break
			if held > 0.0 and human.contact.get("time", 0.0) <= 0.075: break
		await _tick()
		held += Engine.time_scale / Engine.physics_ticks_per_second
	current.actual_charge = game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME
	_event("Release actual charge %.3f TTC %.4fs" % [current.actual_charge, human.contact.get("time", -1.0)])
	Input.action_release("ui_accept")
	await _tick()
	game.input_handler.set_process(false)

func _queue_fixture(feed: Dictionary, power: float) -> void :
	await get_tree().physics_frame
	_feed(feed)
	_event("Feed %s at %.1fm/s" % [feed.pose, feed.get("speed", 4.0)])

	await _wait_seconds(1.0 / 30.0)
	stage = "PREP"
	current.selected_pose = game.player_left.posture.human_contact.contact.get("posture", -1)
	await _press_release(power)

func _run_combo(item: Dictionary) -> void :
	game.ball.bounced.connect(_on_observed_bounce)
	game.ball.hit_by_paddle.connect(_on_hit)
	var p = game.player_left
	var human = p.posture.human_contact
	await _wait_seconds(0.4)
	if item.combo == "LOW_REVERSAL":
		await get_tree().physics_frame
		_feed({"pose": 5, "bounce": 1})
		var deadline: = sim_time + 1.2
		while sim_time < deadline:
			await _tick()
			if not human.contact.is_empty() and human.contact.time <= 0.24: break
		p.move_speed = 2.8
		Input.action_press("move_right")
		await _wait_seconds(4.0 / 60.0)
		Input.action_release("move_right")
		Input.action_press("move_left")
		_event("Late right-to-left reversal with low bounced ball approaching")
		await _wait_seconds(4.0 / 60.0)
		Input.action_release("move_left")
		_event("Plant and release at late low contact")
		stage = "PREP"
		await _press_release(item.power)
		await _wait_seconds(1.5)
	elif item.combo == "JUMP_NEXT":
		p.global_position.z = 3.5
		await _queue_fixture({"pose": 4, "bounce": 0, "jump": true}, 0.95)
		var deadline: = sim_time + 1.2
		while sim_time < deadline and (current.hits.is_empty() or p.is_jumping): await _tick()
		_event("Landing; launch next ball immediately")
		if current.hits.is_empty() or not current.hits[0].airborne: current.issues.append("First ball was not an airborne contact")
		await _queue_fixture({"pose": 2, "bounce": 0, "speed": 6.0, "lead": 1.32}, (1.0 / 15.0) / PickleballConstants.MAX_SERVE_CHARGE_TIME)
		var recover_deadline: = sim_time + 1.5
		while sim_time < recover_deadline:
			await _tick()
			if current.hits.size() < 2 and human.phase < 0 and not human.contact.is_empty(): await _press_release(0.6)
	elif item.combo == "CANCEL_SPEEDUP":
		await _queue_fixture({"pose": 0, "bounce": 0, "speed": 4.0, "lead": 1.3}, (2.0 / 15.0) / PickleballConstants.MAX_SERVE_CHARGE_TIME)
		var previous_flight: int = game.ball.flight_id
		if human.phase != 0: current.issues.append("Slow first feed did not queue charge")
		await get_tree().physics_frame
		_feed({"pose": 2, "bounce": 0, "speed": 10.0, "lead": 2.2})
		_event("Speed-up replaces queued flight")
		await _wait_seconds(1.0 / 30.0)
		if game.ball.flight_id == previous_flight or human.phase != -1: current.issues.append("Old queued charge survived new faster flight")
		if not current.hits.is_empty(): current.issues.append("Cancelled flight fabricated a contact")
		await _press_release((1.0 / 15.0) / PickleballConstants.MAX_SERVE_CHARGE_TIME)
		await _wait_seconds(1.6)
	elif item.combo == "LATE_TAP":
		await get_tree().physics_frame
		_feed({"pose": 2, "bounce": 0, "speed": 10.0, "lead": 1.4})
		await _wait_seconds(0.22)
		stage = "PREP"
		_event("Deliberately late press after ball has passed contact plane")
		game.input_handler.set_process(true)
		Input.action_press("ui_accept")
		await _wait_seconds(1.0 / 15.0)
		Input.action_release("ui_accept")
		await _tick()
		game.input_handler.set_process(false)
		await _wait_seconds(1.0)

func _run_popup(item: Dictionary) -> void :
	game.ball.freeze = false
	game.ball.show()
	game.player_right.show()
	game.player_right.set_process(true)
	game.player_right.set_physics_process(true)
	game.ball.bounced.connect(_on_observed_bounce)
	game.ball.hit_by_paddle.connect(_on_hit)
	await get_tree().physics_frame
	preload("res://scripts/debug/kitchen_review_feeds.gd").popup(game, item.popup_seed)
	stage = "PREP"
	_event("Canonical seeded pop-up feed; actual red tactic and hit")
	while sim_time < 2.5 and current.opponent_hits.is_empty(): await _tick()
	await _wait_seconds(0.8)

func _run_live_drill(item: Dictionary) -> void :
	game.ball.freeze = false
	game.ball.show()


	game.player_right.show()
	game.player_right.set_process(true)
	game.player_right.set_physics_process(true)
	game.ball.bounced.connect(_on_observed_bounce)
	game.ball.hit_by_paddle.connect(_on_hit)
	game.practice_launcher.start_drill(item.drill_mode, true, item.get("direction", 1), item.get("variant", "STANDARD"))
	game.practice_launcher.loop_enabled = false
	var expected_hits: int = item.get("expected_hits", 3)
	var deadline: float = item.get("duration", 9.0)
	var last_hit_time: = -1.0
	var count: = 0
	while sim_time < deadline:
		await _tick()
		var human = game.player_left.posture.human_contact
		if current.hits.size() > count:
			count = current.hits.size()
			last_hit_time = sim_time
		if count >= expected_hits:
			game.practice_launcher.demo_enabled = false
			if human.phase == -1 and sim_time - last_hit_time >= 0.2: break
			continue
		if not game.practice_launcher.is_exchange_demo() and human.phase < 0 and not human.contact.is_empty():
			stage = "PREP"
			Input.action_press("ui_accept")
			game.input_handler._handle_swing_charge(item.get("power", 0.6) * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			Input.action_release("ui_accept")
			game.input_handler._handle_swing_charge(0.0)

func _on_hit(side: int) -> void :
	_record_contact(side)
	observed_bounces[1 - side] = 0

func _on_serve_hit(side: int) -> void :
	if side != 0: return
	_record_contact()
	current.serve_release_elapsed = game.ball.get_meta("serve_release_elapsed", -1.0)
	current.serve_delivery_bounces = game.ball.get_meta("serve_delivery_bounces", -1)
	current.serve_contact_style = game.ball.get_meta("serve_style", -1)

func _record_contact(side: int = 0) -> void :
	if side == current.get("camera_player", 0):
		hit_frame = frame_number
		stage = "CONTACT"
	var p = game.player_left if side == 0 else game.player_right
	var local: Vector3 = p.paddle_node.to_local(game.ball.global_position)
	var error: float = PaddleReach.head_world(p).distance_to(game.ball.global_position)
	if side == 1: current.last_kitchen_tactic = p.ai_brain.last_kitchen_tactic
	var feet: = _foot_nvz(p)
	_observe_feet(side, feet)
	var volley: bool = game.ball.was_volley
	if not current.get("serve", false):
		if volley and (feet.in_nvz or not feet_established[side]): current.issues.append("Player%d NVZ volley before both shoes re-established outside at frame%d" % [side, frame_number])
		if not volley and observed_bounces[side] < 1: current.issues.append("Player%d groundstroke without observed incoming bounce at frame%d" % [side, frame_number])
	else:
		var grounded_count: = 0
		var positive_x: bool = (game.get_server_score(side) % 2 == 0) == (side == 0)
		for foot in feet.feet:
			if not foot.grounded: continue
			grounded_count += 1
			var lo: Array = foot.box_min
			var hi: Array = foot.box_max
			if (side == 0 and lo[2] <= PickleballConstants.BASELINE_Z) or (side == 1 and hi[2] >= - PickleballConstants.BASELINE_Z): current.issues.append("Serve shoe touches baseline at frame%d" % frame_number)
			if lo[0] < - PickleballConstants.COURT_WIDTH * 0.5 or hi[0] > PickleballConstants.COURT_WIDTH * 0.5: current.issues.append("Serve shoe outside sideline extension at frame%d" % frame_number)
			if (positive_x and lo[0] <= 0.0) or ( not positive_x and hi[0] >= 0.0): current.issues.append("Serve shoe crosses centerline extension at frame%d" % frame_number)
		if grounded_count == 0: current.issues.append("Serve contact without a grounded support foot at frame%d" % frame_number)
	var hit_list: Array = current.hits if side == 0 else current.opponent_hits
	var active_pose: PostureDefinition = p.posture.transition_pose_blend
	hit_list.append({"frame": frame_number, "sim_time": sim_time, "flight_id": game.ball.flight_id, "was_volley": volley, "observed_incoming_bounces": observed_bounces[side], "feet": feet, "feet_established_outside": feet_established[side], "pose": active_pose.posture_id if active_pose else -1, "head_error_m": error, "outgoing_velocity": _v(game.ball.linear_velocity), "outgoing_speed_mps": game.ball.linear_velocity.length(), "head_surface_gap_m": Geometry.distance_to_head_shape(local) - BALL_RADIUS, "ball_local": _v(local), "airborne": p.is_jumping})
	volley_follow_active[side] = volley and not current.get("serve", false)
	if error > Planner.IMPACT_DISTANCE + 0.0001: current.issues.append("Contact outside runtime hit radius")

func _tick() -> void :
	await get_tree().physics_frame
	await presentation_ready

	await after_animation_ready
	sim_time += Engine.time_scale / Engine.physics_ticks_per_second
	var capture_now: = render and ( not batch or frame_number % capture_stride == 0 or stage != last_captured_stage)
	if capture_now:
		_position_cameras()
		for viewport in views: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	var p = game.player_left
	var human = p.posture.human_contact
	var viewed_player = game.player_right if current.get("camera_player", 0) == 1 else p
	var view_phase: int = (2 if viewed_player.hitting.is_in_follow_through else -1) if current.get("camera_player", 0) == 1 else human.phase
	if stage == "BOUNCE" and frame_number > last_bounce_frame + 1: stage = "PREP"
	if hit_frame >= 0 and frame_number > hit_frame + 1:
		stage = "FOLLOW-THROUGH" if view_phase in [2, 3] or viewed_player.hitting.is_in_follow_through else "RECOVERY"
	if not current.stages.has(stage): current.stages[stage] = frame_number
	var sample: = _measure_body()
	sample.sim_time = sim_time
	sample.frame = frame_number
	sample.stage = stage
	sample.phase = human.phase
	sample.view_phase = view_phase
	sample.incoming_bounces = observed_bounces.duplicate()
	if current.get("serve", false): sample.serve_timing = game.game_serve.get_serve_timing_state()
	if current.has("drill_mode") or current.has("popup_seed"): sample.opponent = _measure_body(game.player_right)
	var observed_actors: = [sample]
	if sample.has("opponent"): observed_actors.append(sample.opponent)
	for side in range(observed_actors.size()):
		var actor_sample: Dictionary = observed_actors[side]
		_observe_feet(side, actor_sample.foot_nvz)
		if volley_follow_active[side] and actor_sample.foot_nvz.in_nvz:
			current.issues.append("Player%d volley momentum carries shoe into NVZ at frame%d" % [side, frame_number])
			volley_follow_active[side] = false
		elif volley_follow_active[side] and feet_established[side] and not actor_sample.airborne and not actor_sample.in_follow_through and Vector3(actor_sample.velocity[0], actor_sample.velocity[1], actor_sample.velocity[2]).length() < 0.1:
			volley_follow_active[side] = false
	samples.append(sample)
	if status: status.text = "%s  |  %s  |  %s  |  frame %d  |  hits %d\nLive physics + actual controller. %s" % [current.name, "¼ SPEED" if slow else "NORMAL SPEED", stage, frame_number, current.hits.size(), "; ".join(current.issues)]
	if save_frames and capture_now:
		last_captured_stage = stage
		var dir: = output.path_join(current.id)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var image: = Image.create(VIEW_SIZE.x * 3, VIEW_SIZE.y, false, Image.FORMAT_RGB8)
		for index in range(views.size()):
			var frame_image: Image = views[index].get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGB8)
			image.blit_rect(frame_image, Rect2i(Vector2i.ZERO, VIEW_SIZE), Vector2i(VIEW_SIZE.x * index, 0))
		image.save_png(dir.path_join("frame_%04d.png" % frame_number))
	frame_number += 1

func _position_cameras() -> void :
	var p = game.player_right if current.get("camera_player", 0) == 1 else game.player_left
	var target: = Vector3(p.global_position.x, 1.05, p.global_position.z)
	var forward: Vector3 = p._get_forward_axis()
	var right: Vector3 = p._get_forehand_axis()
	var distance: float = minf(2.4, maxf(0.8, absf(p.global_position.z) - 0.45))
	var positions: Array[Vector3] = [forward * distance, right * distance, (forward + right).normalized() * distance]
	for index in range(cameras.size()):
		cameras[index].global_position = target + positions[index] + Vector3.UP * 0.18
		cameras[index].look_at(target)

func _v(point: Vector3) -> Array: return [point.x, point.y, point.z]
func _q(value: Quaternion) -> Array: return [value.x, value.y, value.z, value.w]
func _review_transform(value: Transform3D) -> Array: return [_v(value.basis.x), _v(value.basis.y), _v(value.basis.z), _v(value.origin)]
func _from_q(values: Array) -> Quaternion: return Quaternion(values[0], values[1], values[2], values[3])
func _short_angle(a: Quaternion, b: Quaternion) -> float: return rad_to_deg(2.0 * acos(clampf(absf(a.normalized().dot(b.normalized())), 0.0, 1.0)))

func _measure_body(player_override = null) -> Dictionary:
	var p = player_override if player_override != null else game.player_left
	var pose: PostureDefinition = p.posture.transition_pose_blend
	if pose == null and p.posture.human_contact != null: pose = p.posture.human_contact.visual_pose
	if pose == null: pose = p.get_runtime_posture_def()
	var chest = p.body_pivot.get_node("TorsoMesh")
	var head = chest.get_node("HeadMesh")
	var paddle: Transform3D = p.paddle_node.global_transform
	var face_clearance: = Geometry.distance_to_paddle_shape(paddle.affine_inverse() * head.global_position) - 0.12
	var chest_clearance: = INF
	var floor_clearance: = INF
	var chest_from_paddle: Transform3D = chest.global_transform.affine_inverse() * paddle
	for point in surface:
		chest_clearance = minf(chest_clearance, Geometry.signed_box_distance(chest_from_paddle * point, Vector3(0.18, 0.16, 0.1)))
		floor_clearance = minf(floor_clearance, (paddle * point).y - p.COURT_FLOOR_Y)
	var hand = p.left_arm_node if pose != null and pose.paddle_hand == 1 else p.right_arm_node
	var hand_offset: Vector3 = pose.left_hand_offset if pose != null and pose.paddle_hand == 1 else (pose.right_hand_offset if pose != null else Vector3.ZERO)
	var grip: Vector3 = paddle * (PaddleSize.MAIN_GRIP_OFFSET + hand_offset)
	var main_wrist: Vector3 = hand.hand_mesh.global_transform * hand.articulated_hand.wrist_socket
	var paddle_q: Quaternion = paddle.basis.orthonormalized().get_rotation_quaternion()
	var hand_basis: Basis = hand.hand_mesh.global_basis * hand.articulated_hand.anatomical_basis
	var hand_q: Quaternion = hand_basis.orthonormalized().get_rotation_quaternion()
	var forearm_q: Quaternion = hand.forearm_pivot.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var grip_relative_q: Quaternion = paddle_q.inverse() * hand_q
	var forearm_relative_q: Quaternion = forearm_q.inverse() * hand_q
	var hand_step: = 0.0
	var paddle_step: = 0.0
	var forearm_step: = 0.0
	var grip_relative_step: = 0.0
	var delta: = 0.0
	if not samples.is_empty():
		var previous: Dictionary = samples.back() if p.player_num == 0 else samples.back().get("opponent", {})
		if previous.has("orientations"):
			delta = sample_time_seconds - float(previous.get("sample_time_seconds", sample_time_seconds))
			hand_step = _short_angle(hand_q, _from_q(previous.orientations.hand_world))
			paddle_step = _short_angle(paddle_q, _from_q(previous.orientations.paddle_world))
			forearm_step = _short_angle(forearm_q, _from_q(previous.orientations.forearm_world))
			grip_relative_step = _short_angle(grip_relative_q, _from_q(previous.orientations.hand_relative_to_paddle))
	var forearm_axis: Vector3 = (main_wrist - hand.forearm_pivot.global_position).normalized()
	var orientations: = {"hand_world": _q(hand_q), "paddle_world": _q(paddle_q), "forearm_world": _q(forearm_q), "hand_relative_to_paddle": _q(grip_relative_q), "hand_relative_to_forearm": _q(forearm_relative_q), "hand_step_deg": hand_step, "paddle_step_deg": paddle_step, "forearm_step_deg": forearm_step, "relative_grip_step_deg": grip_relative_step, "sample_delta_seconds": delta, "hand_rate_deg_s": hand_step / maxf(delta, 1e-06), "paddle_rate_deg_s": paddle_step / maxf(delta, 1e-06), "forearm_rate_deg_s": forearm_step / maxf(delta, 1e-06), "shaft_forearm_angle_deg": rad_to_deg(paddle.basis.y.angle_to(forearm_axis)), "note": "Rates use actual accumulated scaled physics time between observations; shaft/forearm angle is not anatomical wrist bend. Calibrated channels are in arms.anatomical_channels."}
	var held_surface_gap = null
	if current.get("serve", false) and p == game.player_left and p.hitting.serving_visual_active and not game.ball.is_in_play and not game.game_serve.is_release_pending():
		var support = p.left_arm_node if hand == p.right_arm_node else p.right_arm_node
		var hand_mesh: MeshInstance3D = support.hand_mesh
		held_surface_gap = HandPresentation.ball_surface_gap(support, game.ball.global_position, BALL_RADIUS)
	var gaze: Vector3 = head.global_transform.basis * p._get_forward_axis()
	var to_ball: Vector3 = (game.ball.global_position - head.global_position).normalized()
	var feet: = []
	for leg in [p.right_leg_node, p.left_leg_node]:
		var hip: Vector3 = leg.thigh_pivot.global_position
		var knee: Vector3 = leg.shin_pivot.global_position
		var ankle: Vector3 = leg.foot_pivot.global_position
		var angle: = rad_to_deg(PI - (hip - knee).angle_to(ankle - knee))
		var toe_forward: Vector3 = - leg.foot_mesh.global_transform.basis.z
		toe_forward.y = 0.0
		var movement: Vector3 = p.current_velocity
		movement.y = 0.0
		feet.append({"position": _v(ankle), "hip": _v(hip), "knee": _v(knee), "toe_forward": _v(toe_forward.normalized()), "foot_heading_vs_motion_deg": rad_to_deg(toe_forward.angle_to(movement)) if movement.length() > 0.1 else null, "knee_flex_deg": angle, "extension_ratio": hip.distance_to(ankle) / (leg.thigh_length + leg.shin_length)})
	var arms: = []
	for arm in [p.right_arm_node, p.left_arm_node]:
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_pivot.global_position
		var row: Dictionary = {"root_local_transform": _review_transform(arm.transform), "upper_local_transform": _review_transform(arm.upper_pivot.transform), "forearm_local_transform": _review_transform(arm.forearm_pivot.transform), "shoulder": _v(shoulder), "elbow": _v(elbow), "wrist": _v(wrist), "reach_m": shoulder.distance_to(wrist), "elbow_flex_deg": rad_to_deg(PI - (shoulder - elbow).angle_to(wrist - elbow))}
		if arm.articulated_hand != null:
			var model = arm.articulated_hand
			var socket: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
			var frame: Basis = ArmAnatomy.forearm_reference_for_arm(arm, socket, arm == p.left_arm_node)
			row["visible_wrist"] = _v(socket)
			row["visible_wrist_reach_m"] = shoulder.distance_to(socket)
			row["link_budget_m"] = arm.upper_arm_length + arm.forearm_length
			row["upper_length_error_m"] = absf(shoulder.distance_to(elbow) - arm.upper_arm_length)
			row["forearm_length_error_m"] = absf(elbow.distance_to(socket) - arm.forearm_length)
			row["visible_forearm_length_m"] = elbow.distance_to(socket)
			row["visual_stretch"] = arm.visual_stretch
			row["visual_wrist_lag_deg"] = arm.visual_wrist_lag_deg
			row["anatomical_channels"] = ArmAnatomy.decompose(frame, arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
			row["hand_pose"] = model.debug_metadata()
		arms.append(row)
	var limb_clearance: = _limb_clearances(p, paddle)
	var displayed_body: PostureDefinition = p.posture._presented_body_pose if p.posture._presented_body_pose != null else pose
	var skin = p.body_pivot.get_meta("articulated_torso", null)
	var skin_frames: Array[Transform3D] = []
	var exported_skin_frames: Array = []
	if skin != null:
		skin_frames = [skin._last_pelvis, skin._last_abdomen, skin._last_chest]
		for frame in skin_frames: exported_skin_frames.append(_review_transform(frame))
	var body_geometry: Dictionary = BodySurface.volumes(p, displayed_body, p.body_pivot.global_transform, skin_frames if skin_frames.size() == 3 else null)
	var body_clearance: Dictionary = BodySurface.sample_paddle(paddle, surface, body_geometry)
	var pose_fields: = {}
	var displayed_body_fields: = {}
	if pose:
		for field in ["paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset", "body_yaw_deg", "body_pitch_deg", "body_roll_deg", "hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg", "shoulder_protraction_m", "crouch_amount", "paddle_yaw_base_deg", "paddle_yaw_signed_deg", "paddle_pitch_base_deg", "paddle_pitch_signed_deg", "paddle_roll_base_deg", "paddle_roll_signed_deg", "paddle_hand", "left_hand_offset", "right_hand_offset", "left_hand_mode", "left_elbow_pole", "right_elbow_pole", "left_shoulder_rotation_deg", "right_shoulder_rotation_deg", "weight_shift", "left_knee_pole", "right_knee_pole", "stance_width", "front_foot_forward", "back_foot_back"]:
			var value = pose.get(field)
			pose_fields[field] = _v(value) if value is Vector3 else value
			if displayed_body != null:
				var body_value = displayed_body.get(field)
				displayed_body_fields[field] = _v(body_value) if body_value is Vector3 else body_value
	return {"sample_time_seconds": sample_time_seconds, "orientations": orientations, "serve_held_surface_gap_m": held_surface_gap, "arms": arms, "pose_fields": pose_fields, "displayed_body_pose_fields": displayed_body_fields, "displayed_body_pose_id": displayed_body.posture_id if displayed_body != null else -1, "body_pivot_transform": _review_transform(p.body_pivot.global_transform), "displayed_skin_frames": exported_skin_frames, "body_surface_frame_source": body_geometry.frame_source, "shoulder_from_displayed_body_pose": _v(Body.shoulder_world(p, displayed_body, p.body_pivot.global_transform)) if displayed_body != null else [], "shoulder_from_cached_chest": _v(p.body_pivot.global_transform * skin_frames[2] * Body.shoulder_local(p, displayed_body, -1.0 if hand == p.left_arm_node else 1.0)) if skin_frames.size() == 3 and displayed_body != null else [], "shoulder_actual": _v(hand.upper_pivot.global_position), "shoulder_computed": _v(Body.shoulder_world(p, pose, p.body_pivot.global_transform)) if pose else [], "shoulder_planner_unfitted": _v(Body.shoulder_world(p, pose)) if pose else [], "paddle_transform": [_v(paddle.basis.x), _v(paddle.basis.y), _v(paddle.basis.z), _v(paddle.origin)], "limb_clearance_m": limb_clearance, "limb_capsule_diagnostic_m": _limb_capsule_clearances(p, paddle), "body_surface_clearance_m": body_clearance, "body_surface_fallback_cells": body_geometry.fallback_cells, "pose": pose.posture_id if pose else -1, "body_root": _v(p.global_position), "velocity": _v(p.current_velocity), "foot_lock": [p.leg_ik.right_foot_locked, p.leg_ik.left_foot_locked], "foot_nvz": _foot_nvz(p), "in_follow_through": p.hitting.is_in_follow_through, "head": _v(head.global_position), "ball": _v(game.ball.global_position), "gaze_error_deg": rad_to_deg(gaze.angle_to(to_ball)), "face_clearance_m": face_clearance, "chest_clearance_m": body_clearance.ribcage, "legacy_chest_box_clearance_m": chest_clearance, "paddle_floor_clearance_m": floor_clearance, "grip_error_m": hand.hand_pivot.global_position.distance_to(grip), "grip_reach_m": hand.global_position.distance_to(grip), "anatomical_wrist_reach_m": hand.upper_pivot.global_position.distance_to(main_wrist), "feet": feet, "feet_established_outside": feet_established[p.player_num], "airborne": p.is_jumping}

func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var span: = b - a
	return point.distance_to(a + span * clampf((point - a).dot(span) / maxf(span.length_squared(), 1e-06), 0.0, 1.0))

func _limb_clearances(p, paddle: Transform3D) -> Dictionary:
	var meshes: Array = []
	for index in range(2):
		var arm = p.right_arm_node if index == 0 else p.left_arm_node
		var leg = p.right_leg_node if index == 0 else p.left_leg_node
		meshes.append_array([["%s_upper_arm" % index, arm.upper_mesh], ["%s_forearm" % index, arm.fore_mesh], ["%s_thigh" % index, leg.thigh_mesh], ["%s_shin" % index, leg.shin_mesh]])
	var distances: Dictionary = {}
	for item in meshes:
		var mesh: MeshInstance3D = item[1]
		var to_paddle: Transform3D = paddle.affine_inverse() * mesh.global_transform
		var margin: float = INF
		for point in BodySurface.mesh_surface_points(mesh):
			margin = minf(margin, Geometry.distance_to_paddle_shape(to_paddle * point))
		distances[item[0]] = margin
	return distances



func _limb_capsule_clearances(p, paddle: Transform3D) -> Dictionary:
	var segments: = []
	for arm_index in range(2):
		var arm = p.right_arm_node if arm_index == 0 else p.left_arm_node
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_pivot.global_position
		var upper_axis: Vector3 = (elbow - shoulder).normalized()
		var fore_axis: Vector3 = (wrist - elbow).normalized()


		segments.append(["%s_upper_arm" % arm_index, shoulder + upper_axis * 0.055, elbow - upper_axis * 0.055, 0.055])
		segments.append(["%s_forearm" % arm_index, elbow + fore_axis * 0.045, wrist - fore_axis * 0.09, 0.045, wrist])
	for leg_index in range(2):
		var leg = p.right_leg_node if leg_index == 0 else p.left_leg_node
		var hip: Vector3 = leg.thigh_pivot.global_position
		var knee: Vector3 = leg.shin_pivot.global_position
		var ankle: Vector3 = leg.foot_pivot.global_position
		var thigh_axis: Vector3 = (knee - hip).normalized()
		var shin_axis: Vector3 = (ankle - knee).normalized()
		segments.append(["%s_thigh" % leg_index, hip + thigh_axis * 0.06, knee - thigh_axis * 0.06, 0.06])
		segments.append(["%s_shin" % leg_index, knee + shin_axis * 0.05, ankle - shin_axis * 0.05, 0.05])
	var distances: = {}
	for segment in segments: distances[segment[0]] = INF
	for point in surface:
		var world: Vector3 = paddle * point
		for segment in segments:
			if segment.size() > 4 and point.y <= 0.25 and world.distance_to(segment[4]) < 0.12: continue
			distances[segment[0]] = minf(distances[segment[0]], _segment_distance(world, segment[1], segment[2]) - segment[3])
	return distances

func _source_hashes() -> Dictionary:
	var hashes: = {}
	for file in ["player.gd", "player_nvz_state.gd", "player_leg_ik.gd", "player_arm_ik.gd", "player_body_builder.gd", "player_head_gaze.gd", "human_contact_controller.gd", "incoming_contact_planner.gd", "drive_serve_motion.gd", "stroke_body_pose.gd", "stroke_swing_path.gd", "incoming_ready_motion.gd", "ball.gd", "ball_flight_predictor.gd", "net.gd", "game.gd", "game_serve.gd", "game_shots.gd", "player_ai_brain.gd", "practice_launcher.gd", "debug/kitchen_review_feeds.gd", "ai_kitchen_tactics.gd", "input_handler.gd", "player_hitting.gd", "shot_physics.gd", "debug/pose_simulation_review.gd"]:
		hashes[file] = FileAccess.get_sha256("res://scripts/" + file)
	for filename in DirAccess.get_files_at("res://scripts"):
		if filename.ends_with(".gd"): hashes[filename] = FileAccess.get_sha256("res://scripts/" + filename)
	for path in ["res://project.godot", "res://scripts/ui/mobile_controls.gd", "res://scripts/ui/mobile_layout.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	for filename in DirAccess.get_files_at("res://scenes"):
		if filename.ends_with(".tscn"): hashes["res://scenes/" + filename] = FileAccess.get_sha256("res://scenes/" + filename)
	for resource in PostureLibrary.instance().all_definitions():
		if resource.resource_path != "": hashes[resource.resource_path] = FileAccess.get_sha256(resource.resource_path)
	return hashes

func _write_report() -> void :
	var report: = {"schema": 2, "opening_double_bounce_initialized": true, "groundstrokes_require_observed_bounce": true, "started_at_utc": started_at, "source_hashes_at_start": source_hashes, "source_hashes_at_report": _source_hashes(), "seed": 77811, "engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second, "rendered": render, "camera_order": ["front", "side", "threequarter"], "catalog_note": "18 receiving zones; 8/9 charge resources are represented by actual forehand/backhand preparation, not invented selectable incoming zones; 20 Ready appears before each feed.", "results": results}
	var temporary: = output.path_join("review.json.tmp")
	var file: = FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	DirAccess.rename_absolute(temporary, output.path_join("review.json"))
