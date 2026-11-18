extends SceneTree
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var checks: = 0
var failures: Array[String] = []
var game
var accepted: = 0
var output: = ""
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = index;event.position = point;event.pressed = pressed;event.canceled = canceled
	game.mobile_controls._input(event)
func drag(index: int, point: Vector2) -> void :
	var event: = InputEventScreenDrag.new()
	event.index = index;event.position = point
	game.mobile_controls._input(event)
func seed_ball() -> void :
	if game.practice_launcher.is_active: game.practice_launcher.stop_practice()
	game._reset_match();game._set_game_state(game.GameState.PLAYING);game.rally_scorer._serve_was_hit = true
	var player = game.player_left
	player.global_position = Vector3(0, player.ground_y, 3.2)
	player.hitting.clear_charge_visual();player.hitting.serving_visual_active = false
	player.leg_ik.feet_initialized = false;player._process(0);player.can_volley_from_feet()
	game.player_right.set_ai_movement_enabled(false)
	game.ball.reset_rally_state();game.ball.both_bounces_complete = true;game.ball.is_in_play = true;game.ball.last_hit_by = 1
	game.ball.global_position = Vector3(0.42, 1.12, 1.5);game.ball.linear_velocity = Vector3(0, 1.5, 8);game.ball.angular_velocity = Vector3.ZERO;game.ball.flight_id += 1
func settle_reachable_focus() -> void:
	# Rally focus arms on press and starts only after authoritative AIM lock-in.
	var deadline: int = Time.get_ticks_usec() + 600000
	while not game.aim_focus.active and Time.get_ticks_usec() < deadline:
		game.aim_controller.update(0.1, true, Vector2.ZERO, true)
		game.aim_focus.tick(Time.get_ticks_usec(), true)
		if game.aim_focus.active: break
		await process_frame
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): output = arg.trim_prefix("--capture=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false);game.reaction_button.auto_fire_on_perfect = false
	game.ball.hit_by_paddle.connect(_record_contact)
	var mobile = game.mobile_controls
	for size in [Vector2i(1080, 2340), Vector2i(600, 960)]:
		root.content_scale_size = size;root.size = size; await process_frame; await process_frame
		seed_ball(); await physics_frame; await physics_frame
		var count: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		touch(12, mobile._charge_center, true)
		game.input_handler._handle_swing_charge(0.08)
		mobile._process(0.2)
		await settle_reachable_focus()
		check(mobile._charge_owns_action and game.aim_focus.active, "touch hold did not own charge/focus (hold=%s mode=%s timing=%s)" % [game.aim_focus.holding, game.aim_controller.mode, game.player_left.posture.human_contact.release_timing_state()])
		check( not game.hud.state.text.contains("\n"), "portrait charge status crosses its icon row")
		for selection in [{"name": "TOPSPIN", "axis": Vector2(-1, -1).normalized()}, {"name": "SLICE", "axis": Vector2(1, -1).normalized()}, {"name": "DROP", "axis": Vector2.DOWN}, {"name": "FLAT", "axis": Vector2.ZERO}]:
			var point: Vector2 = mobile._charge_origin + selection.axis * mobile._charge_radius * 1.1
			drag(12, point)
			check(mobile._selected_shot() == "FLAT", "HIT directional drag changed Flat intent " + selection.name)
			check(mobile.aim_direction().is_equal_approx(selection.axis), "right-thumb directional aiming mismatch " + selection.name)
			if selection.name != "FLAT":
				var index: int = mobile.GUIDE_LABELS.find(selection.name)
				check(mobile._guide_nodes[index].distance_to(mobile._charge_center) > mobile._shot_button_radius + mobile._charge_radius, "skill overlaps HIT " + selection.name)
		for index in 3:
			check(mobile._guide_nodes[index].distance_to(mobile._charge_center) > mobile._charge_radius + 20 * mobile._s, "skill button must sit outside HIT")
			var safe: Rect2 = Layout.safe_rect(root)
			check(safe.has_point(mobile._guide_labels[index]), "skill label outside safe screen")
		check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == count, "guide hold/drag allocated new nodes")
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			drag(12, mobile._charge_origin + Vector2(-1, -1).normalized() * mobile._charge_radius * 1.1)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("hit_y_%dx%d.png" % [size.x, size.y]))
			game.aim_controller.update(0.1, true, Vector2.ZERO, true)
			game.aim_focus._update_presentation(Time.get_ticks_usec())
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("focus_aim_%dx%d.png" % [size.x, size.y]))
		drag(12, mobile._charge_origin + Vector2.LEFT * mobile._charge_radius * 3.2)
		check(not mobile._cancel_armed, "long aiming drag must not cancel")
		drag(12, mobile._cancel_center)
		check(mobile._cancel_armed, "explicit cancel target did not arm")
		touch(12, mobile._cancel_center, false)
		check( not Input.is_action_pressed("ui_accept") and mobile._guide_show == 0 and not game.aim_focus.active, "cancel release retained guide/charge/focus")
		# Each external skill owns its own hold-drag-release gesture. Exercise
		# focus and cancellation independently; the real-contact case below remains.
		for index in 3:
			seed_ball(); await physics_frame; await physics_frame
			var id: int = 40 + index
			var origin: Vector2 = mobile._guide_nodes[index]
			touch(id, origin, true);game.input_handler._handle_swing_charge(0.08)
			await settle_reachable_focus()
			check(mobile._charge_id == id and mobile._charge_owns_action and game.aim_focus.active, "skill hold must own charge and focus " + mobile.GUIDE_LABELS[index])
			var node_count: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			drag(id, origin + Vector2.RIGHT * mobile._charge_radius)
			check(mobile._selected_shot() == mobile.GUIDE_LABELS[index], "skill drag changed held shot intent")
			check(mobile.aim_direction().x > 0 and is_zero_approx(mobile.aim_direction().y), "skill drag did not aim from its own origin")
			touch(id + 10, mobile._charge_center, true)
			check(mobile._charge_id == id and not mobile._owners.has(id + 10), "second shot finger stole skill ownership")
			check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == node_count, "skill drag allocated new nodes")
			drag(id, mobile._cancel_center);touch(id, mobile._cancel_center, false)
			game.input_handler._handle_swing_charge(0)
			check(not Input.is_action_pressed("ui_accept") and not game.aim_focus.active and is_equal_approx(Engine.time_scale, 1), "skill cancel-release retained charge or focus")
		seed_ball(); await physics_frame; await physics_frame
		touch(13, mobile._charge_center, true);game.input_handler._handle_swing_charge(0.12)
		for frame in range(3): await physics_frame
		var human = game.player_left.posture.human_contact
		check(game.player_left.hitting.charge_visual_active and human.phase < 0 and human._charge_target_pose != null, "held touch lost prep ownership to tracking")
		check(game.player_left.posture.transition_pose_blend == human.visual_pose, "tracking overwrote held touch visual pose")
		touch(13, mobile._charge_center, false);game.input_handler._handle_swing_charge(0)
		check( not game.aim_focus.active and is_equal_approx(Engine.time_scale, 1), "touch release retained slow motion")
		var phases: Dictionary = {}
		for frame in range(180):
			await physics_frame;phases[human.phase] = true
			if not game.ball.is_in_play or game.ball.last_hit_by == 0 and human.phase < 0: break
		check(game.ball.last_hit_by == 0, "reachable touch hold/release failed real paddle return")
		check(phases.has(2) and phases.has(4), "touch release did not finish and recover")
		mobile.cancel_all()
		check(mobile._guide_show == 0, "cancel_all retained constellation")


		seed_ball(); await physics_frame; await physics_frame
		var mouse: = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT;mouse.position = mobile._charge_center;mouse.pressed = true
		check(mobile._handle_desktop_pointer(mouse), "desktop pointer did not enter Hit")
		game.input_handler._handle_swing_charge(0.08);mobile._process(0.2)
		await settle_reachable_focus()
		check(mobile._charge_id == mobile.MOUSE_POINTER and mobile._guide_show > 0 and game.aim_focus.active, "desktop hold lost guide/focus ownership (owner=%s guide=%s focus=%s hold=%s mode=%s contact=%s)" % [mobile._charge_id, mobile._guide_show, game.aim_focus.active, game.aim_focus.holding, game.aim_controller.mode, game.player_left.posture.human_contact.release_timing_state()])
		touch(24, mobile._charge_center, true)
		check(mobile._charge_id == mobile.MOUSE_POINTER and not mobile._owners.has(24), "touch stole desktop-held Hit")
		mobile.cancel_all();game.input_handler._handle_swing_charge(0)
		check( not Input.is_action_pressed("ui_accept") and not game.aim_focus.active and mobile._guide_show == 0, "desktop cancel retained charge/focus/guide")
	game.queue_free(); await process_frame; await process_frame


	var audio_deadline: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < audio_deadline:
		OS.delay_msec(5)
		await process_frame
	await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("HIT Y FOCUS INPUT: %d checks, %d failures; real returns=%d" % [checks, failures.size(), accepted])
	quit(0 if failures.is_empty() else 1)

func _record_contact(team: int) -> void :
	if team == 0: accepted += 1
