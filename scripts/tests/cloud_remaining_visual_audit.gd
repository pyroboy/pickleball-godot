extends SceneTree
## Read-only production-method UI audit of the archived build28 cloud candidate.
## No screenshots, raster shimmer assertions, physics edits, or authored-pose edits.
const Guide = preload("res://scripts/ui/incoming_movement_guide.gd")
const Feeds = preload("res://tools/cloud_qa/movement_guide_fixtures.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const StaminaDisplay = preload("res://scripts/ui/stamina_display.gd")
var game
var guide
var stamina
var rate := 60
var output := "/tmp/cloud_remaining_visual.json"
var checks := 0
var failures: Array[String] = []
var records: Array = []
var expect_fixed := false
var fixed_sections := PackedStringArray()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--expect-fixed": expect_fixed = true
		if arg.begins_with("--expect-fixed-only="): fixed_sections = arg.trim_prefix("--expect-fixed-only=").split(",")
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func expects(section: String) -> bool: return expect_fixed or fixed_sections.has(section)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func observe(name: String, data: Dictionary) -> void:
	data["scenario"] = name
	records.append(data)
	print("REMAINING VISUAL ", JSON.stringify(data))

func freeze_callbacks(node: Node) -> void:
	node.set_process(false); node.set_physics_process(false)
	for child in node.get_children(): freeze_callbacks(child)

func prepare() -> void:
	paused = false
	game.hud._guide.hide()
	game.mobile_controls.cancel_all()
	Input.action_release("ui_accept")
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	game.input_handler.cancel_charge_input()
	game._reset_match()
	game.between_point_controller.cancel()
	game.game_state = game.GameState.PLAYING
	game.hud.set_gameplay_elements_visible(true)
	game.hud.set_between_point_active(false)
	game.match_over = false
	game.ball.freeze = true
	game.ball.is_in_play = true
	game.ball.last_hit_by = 1
	game.ball.bounces_since_last_hit = 0
	game.ball.both_bounces_complete = true
	game.ball.global_position = Vector3(0.42,1.1,2.2)
	game.ball.linear_velocity = Vector3(0,0,6)
	game.player_left.is_jumping = false
	game.player_left.current_velocity = Vector3.ZERO
	game.player_left.global_position = Vector3(0, game.player_left.ground_y, 3.2)
	game.player_left.hitting.charge_visual_active = true
	var human = game.player_left.posture.human_contact
	human._flight_id = game.ball.flight_id
	human.phase = -1
	human.footwork.cancel("read-only UI fixture")
	human.contact = {"point": Vector3(0.42,1.1,2.6), "time":0.1, "bounces":1, "def":PostureLibrary.instance().all_definitions()[0]}
	human.anticipated_contact = {}
	game.aim_focus.cancel()
	freeze_callbacks(game)

func run() -> void:
	root.content_scale_size = Vector2i(720,1280); root.size = Vector2i(720,1280)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	for frame in 12: await process_frame
	if game.player_left.posture.human_contact == null:
		game.player_left.posture.human_contact = load("res://scripts/human_contact_controller.gd").new(game.player_left,game.player_left.posture)
	Feeds.detach_automatic(game)
	Fixture.configure(game)
	freeze_callbacks(game)
	for child in game.get_children():
		if child.get_script() == StaminaDisplay: stamina = child
	check(stamina != null, "production stamina display exists")
	guide = Guide.new(); game.add_child(guide); guide.setup(game)
	freeze_callbacks(game)
	for size in [Vector2i(720,1280), Vector2i(1280,720), Vector2i(390,844)]:
		root.content_scale_size = size; root.size = size
		await process_frame; await process_frame
		game.hud._layout_desktop(); game.mobile_controls._layout()
		prepare()
		hud_reentry(str(size))
		stamina_visibility(str(size))
		stamina_warning(str(size))
		guide_caption(str(size))
		if size.y > size.x:
			timing_boundary(str(size))
			await interruptions(str(size))
	var report := {"scope":"Archived 0.3.25/build28 plus isolated cloud candidates; not unavailable Mac build30/31 or native/device acceptance", "rate":rate, "checks":checks, "failures":failures, "records":records}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("CLOUD REMAINING VISUAL %d Hz: %d checks, %d failures" % [rate,checks,failures.size()])
	paused = false; current_scene = null; game.queue_free()
	await process_frame; await process_frame
	var until := Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)

func hud_reentry(view: String) -> void:
	prepare()
	var ui = game.scoreboard_ui
	var hud = game.hud
	ui.show_speed(21.3); ui.show_shot_type("DROP")
	var sequence: Array = []
	for cycle in 3:
		ui.hide_all_hud()
		var hidden_alpha: float = hud.shot_type.modulate.a
		ui._process(1.0/rate)
		ui.show_all_hud()
		var state := {"cycle":cycle,"cleared_shot_alpha":hidden_alpha,"return_shot_alpha":hud.shot_type.modulate.a,"return_speed_alpha":hud.speed.modulate.a,"shot_timer":ui._shot_type_timer,"speed_timer":ui._speed_visible_timer}
		sequence.append(state)
		if expects("hud"): check(hud.shot_type.modulate.a == 0 and hud.speed.modulate.a == 0,"HUD stale feedback must not reappear after hide/show")
	observe("hud_hide_show_"+view,{"samples":sequence,"reproduction":float(sequence[0].return_shot_alpha)>0.0,"explanation":"hide_all_hud zeroes shot alpha but leaves timer; next real update writes it back before show_all_hud"})
	# Negative controls: intentional fade is monotone, and a fresh event can show.
	ui._shot_type_timer = 0; ui._speed_visible_timer = 0
	ui.show_shot_type("LOB"); ui.show_speed(18.7)
	var prev_shot := 1.0; var prev_speed := 1.0
	for frame in 4*rate:
		ui._update_shot_type_fade(1.0/rate); ui._update_timers(1.0/rate)
		check(hud.shot_type.modulate.a <= prev_shot+0.0001,"shot's intentional fade reverses")
		check(hud.speed.modulate.a <= prev_speed+0.0001,"speed's intentional fade reverses")
		prev_shot = hud.shot_type.modulate.a; prev_speed = hud.speed.modulate.a
	check(prev_shot == 0 and prev_speed == 0,"natural transient feedback expires")
	ui.hide_all_hud(); ui._process(1.0/rate); ui.show_all_hud()
	check(hud.shot_type.modulate.a == 0 and hud.speed.modulate.a == 0,"expired feedback resurrects")
	ui.show_shot_type("VOLLEY"); ui.show_speed(12.3)
	check(hud.shot_type.modulate.a==1 and hud.speed.modulate.a==1,"genuine new events do not display")

func stamina_visibility(view: String) -> void:
	prepare()
	var camera: Camera3D = game.camera_rig.camera
	var initial_camera := camera.global_transform
	game.ball.global_position = camera.project_position(Vector2(0,0),10)
	for frame in rate: stamina._process(1.0/rate)
	var bar: ProgressBar = stamina.bars[0]
	var margin := 20.0 * preload("res://scripts/ui/mobile_layout.gd").scale_for(root.get_visible_rect().size)
	var edge: Vector2 = Rect2(bar.position,bar.size).grow(margin).end
	edge.y = bar.position.y + bar.size.y*0.5
	var toggles := 0; var prev := bar.visible; var frames: Array = []
	for frame in 2*rate:
		var t := float(frame)/rate
		var point := edge + Vector2(0.25*cos(t*TAU*4.0),0)
		game.ball.global_position = camera.project_position(point,10)
		stamina._process(1.0/rate)
		if frame > 0 and bar.visible != prev: toggles += 1
		prev = bar.visible
		if frame < 12: frames.append({"frame":frame,"visible":bar.visible,"ball_screen":camera.unproject_position(game.ball.global_position),"bar_rect":Rect2(bar.position,bar.size)})
	observe("stamina_ball_margin_"+view,{"toggles":toggles,"ball_oscillation_amplitude_px":0.25,"duration_seconds":2,"samples":frames,"boundary":edge})
	if expects("stamina"): check(toggles <= 1,"stamina visibility chatters at ball suppression margin")
	# Static remote ball and smooth camera/player movement must stay visible.
	game.ball.global_position = camera.project_position(Vector2(0,0),10)
	# One deliberate recovery from suppression is expected before stable sampling.
	for frame in rate: stamina._process(1.0/rate)
	prev = bar.visible
	var stable_toggles := 0
	for frame in rate:
		camera.global_transform = initial_camera
		camera.position.x += sin(float(frame)/rate*TAU)*0.02
		stamina._process(1.0/rate)
		if frame > 0 and bar.visible != prev: stable_toggles += 1
		prev = bar.visible
	check(stable_toggles==0,"remote ball plus smooth camera unexpectedly toggles stamina")
	camera.global_transform = initial_camera
	observe("stamina_remote_ball_control_"+view,{"toggles":stable_toggles})
	# Conservative safety contracts for the proposed asymmetric visibility gate.
	game.ball.global_position = camera.project_position(bar.position+bar.size*0.5,10)
	stamina._process(1.0/rate)
	check(not bar.visible,"ball overlap must suppress stamina immediately")
	game.ball.global_position = camera.project_position(Vector2(0,0),10)
	for frame in rate: stamina._process(1.0/rate)
	check(bar.visible,"stamina fails to recover once ball is clearly away")
	var tool := Control.new(); game.add_child(tool); game.mobile_pose_editor=tool
	stamina._process(1.0/rate)
	check(not bar.visible,"tool screen must suppress stamina immediately")
	game.mobile_pose_editor=null; tool.queue_free()
	for frame in rate: stamina._process(1.0/rate)
	check(bar.visible,"stamina not restored after tool closes with clear ball")

func stamina_warning(view: String) -> void:
	prepare()
	var camera: Camera3D = game.camera_rig.camera
	game.ball.global_position = camera.project_position(Vector2(0,0),10)
	var state = game.player_left.stamina
	state.value = 25.0; state.recovery_delay = 0.0
	stamina.feedback[0].reset(state.value)
	var previous := Color.WHITE; var changes := 0
	var minimum := INF; var maximum := -INF; var samples: Array = []
	for frame in 2*rate:
		# Real stamina.advance, smooth speed around its 1.75 m/s equilibrium.
		var speed := 1.75+0.01*cos((float(frame)+0.5)/rate*TAU*4.0)
		state.advance(1.0/rate,speed,true,false)
		stamina._process(1.0/rate)
		var color: Color = stamina.fills[0].bg_color
		if frame>0 and color!=previous: changes += 1
		minimum=minf(minimum,state.value); maximum=maxf(maximum,state.value)
		previous=color
		if frame<12: samples.append({"frame":frame,"value":state.value,"color":color,"speed":speed,"alpha":stamina.bars[0].modulate.a})
	if expects("stamina"): check(changes<=1,"stamina warning color chatters across tiny25-point oscillation")
	observe("stamina_low_warning_"+view,{"color_changes":changes,"stamina_range":[minimum,maximum],"speed_range_mps":[1.74,1.76],"duration_seconds":2,"samples":samples,"note":"Actual stamina computation with smooth low-amplitude speed; UI-only warning threshold is discontinuous"})
	# Normal recovery is supposed to leave the warning once, not flash.
	state.value=24.9; state.recovery_delay=0.0; previous=Color.WHITE
	changes=0
	for frame in rate:
		state.advance(1.0/rate,0,true,false); stamina._process(1.0/rate)
		var color: Color=stamina.fills[0].bg_color
		if frame>0 and color!=previous: changes+=1
		previous=color
	check(changes<=1,"monotone recovery repeatedly changes warning color")
	check(stamina.fills[0].bg_color==Color(0.35,0.7,1.0),"stamina warning stays amber after comfortable recovery")
	state.value=24.9; var authoritative_value: float=state.value
	stamina._process(1.0/rate)
	check(stamina.fills[0].bg_color==Color(1.0,0.68,0.2),"low stamina warning did not enter immediately")
	check(state.value==authoritative_value,"warning presentation mutates actual stamina")
	observe("stamina_recovery_control_"+view,{"color_changes":changes})

func guide_caption(view: String) -> void:
	prepare()
	guide.player = Feeds.prepare(game,"MOVE",false)
	guide.advisor = Guide.Advisor.new(); guide._reset_generation = game._point_reset_generation
	guide.cancel(); guide.tick(0.0,Feeds.flight(game))
	var state: Dictionary = guide.presentation_state()
	check(not state.is_empty(),"MOVE guide fixture renders at "+view)
	if state.is_empty(): return
	var camera: Camera3D = game.camera_rig.camera
	var target: Vector3 = guide._advice.target_root
	var first: Rect2 = state.label_rect
	var gap: float = state.metrics.gap*2.0
	var edge := Vector2(first.end.x+gap,first.get_center().y)
	var old_rect: Rect2 = first
	var flips := 0; var max_step := 0.0; var samples: Array = []; var hidden := 0
	for frame in 2*rate:
		var point := edge + Vector2(0.25*cos(float(frame)/rate*TAU*4.0),0)
		game.ball.global_position = camera.project_position(point,10)
		guide._reproject()
		state = guide.presentation_state()
		if state.is_empty(): hidden += 1; continue
		var rect: Rect2 = state.label_rect
		if frame > 0 and rect.position != old_rect.position: flips += 1
		max_step = maxf(max_step,rect.position.distance_to(old_rect.position))
		old_rect = rect
		check(guide._advice.target_root==target,"caption reproject changes authoritative target")
		if frame < 12: samples.append({"frame":frame,"label":rect,"ball_screen":point})
	observe("guide_ball_caption_"+view,{"placement_switches":flips,"max_label_jump_px":max_step,"hidden_frames":hidden,"ball_oscillation_amplitude_px":0.25,"duration_seconds":2,"samples":samples})
	if expects("guide"): check(flips<=1,"guide caption switches sides at ball-clearance margin")
	# Actual hide/show within one synchronous projection is not raster flicker.
	game.ball.global_position = camera.project_position(Vector2(0,0),10)
	guide._reproject(); var stable: Dictionary = guide.presentation_state()
	var visible_signals := [0]
	var counted := func(): visible_signals[0] += 1
	guide._drawing.visibility_changed.connect(counted)
	var observed_toggles := 0; var previous_visible: bool = guide._drawing.visible
	for frame in rate:
		guide._reproject()
		if guide._drawing.visible != previous_visible: observed_toggles += 1
		previous_visible = guide._drawing.visible
		check(guide.presentation_state().label_rect==stable.label_rect,"static guide caption churn")
	guide._drawing.visibility_changed.disconnect(counted)
	check(observed_toggles==0,"static guide has frame-end visibility toggles")
	observe("guide_static_control_"+view,{"frame_end_visibility_toggles":observed_toggles,"internal_same_call_visibility_signals":visible_signals[0],"explanation":"Signals within a synchronous update do not by themselves prove a displayed blink"})

func timing_boundary(view: String) -> void:
	prepare()
	var mobile = game.mobile_controls
	mobile._begin_shot(17,mobile._charge_center,"FLAT")
	var human = game.player_left.posture.human_contact
	var stable: Dictionary = human.release_timing_state()
	check(stable.current_reachable and stable.release_ready,"timing fixture is reachable and release-ready")
	var previous := ""; var changes := 0; var max_radius_jump := 0.0; var previous_radius := -1.0; var samples: Array = []
	for frame in 2*rate:
		game.player_left.current_velocity = Vector3(0.35+0.01*cos(float(frame)/rate*TAU*4.0),0,0)
		mobile._update_hit_timing(false,1.0/rate)
		var caption: String = mobile._hit_timing.caption
		var radius: float = mobile._timing_radius()
		if frame > 0 and caption != previous: changes += 1
		if previous_radius >= 0: max_radius_jump = maxf(max_radius_jump,absf(radius-previous_radius))
		previous = caption; previous_radius = radius
		if frame < 12: samples.append({"frame":frame,"speed":game.player_left.current_velocity.length(),"caption":caption,"radius":radius,"release_ready":human.release_timing_state().release_ready})
	observe("timing_movement_boundary_"+view,{"caption_changes":changes,"max_radius_jump_px":max_radius_jump,"speed_range_mps":[0.34,0.36],"duration_seconds":2,"samples":samples,"note":"Readiness genuinely changes at the movement threshold; never retain RELEASE through an unsafe state"})
	# READY-to-invalid must clear immediately; delaying affirmative re-entry is
	# the only safe presentational stability proposal, not preserving RELEASE.
	game.player_left.current_velocity = Vector3.ZERO
	mobile._update_hit_timing(false,1.0/rate)
	check(mobile._hit_timing.ready,"stable input does not produce RELEASE")
	game.player_left.is_jumping = true
	mobile._update_hit_timing(false,1.0/rate)
	check(not mobile._hit_timing.ready,"unsafe airborne frame keeps RELEASE")
	game.player_left.is_jumping = false
	mobile.cancel_all()
	check(not mobile._hit_timing.active and not Input.is_action_pressed("ui_accept"),"cancel leaves timing/held action active")

func interruptions(view: String) -> void:
	prepare()
	var mobile = game.mobile_controls
	var controller = root.get_node("PauseController")
	var counts := {"guide":0,"pause_settings":0,"resize":0,"repeat_cancel":0}
	for cycle in 6:
		mobile._begin_shot(31,mobile._charge_center,"FLAT")
		mobile._update_hit_timing(false,1.0/rate)
		game.hud._toggle_guide()
		mobile._process(1.0/rate)
		check(not mobile.visible and mobile._charge_id==-1 and not mobile._hit_timing.active,"guide interrupt retained touch visuals")
		check(not Input.is_action_pressed("ui_accept"),"guide interrupt retained charge")
		game.hud._toggle_guide(); mobile._process(1.0/rate)
		check(mobile.visible and mobile._charge_id==-1,"guide close resurrected held touch")
		counts.guide += 1
	mobile._begin_shot(32,mobile._charge_center,"FLAT")
	controller.open(); mobile._process(1.0/rate)
	check(not mobile.visible and mobile._charge_id==-1 and not Input.is_action_pressed("ui_accept"),"pause retained touch")
	controller._menu._on_settings(); var settings = controller._menu._settings_overlay
	controller._menu._on_settings()
	check(controller._menu._settings_overlay==settings,"repeated settings stacks visuals")
	settings._on_close(); controller.close()
	await process_frame
	mobile._process(1.0/rate)
	check(mobile.visible and mobile._charge_id==-1,"pause/settings return resurrected touch")
	counts.pause_settings += 1
	mobile._begin_shot(33,mobile._charge_center,"FLAT")
	mobile._layout(); mobile._process(1.0/rate)
	check(mobile._charge_id==-1 and not Input.is_action_pressed("ui_accept"),"layout refresh retained held input")
	counts.resize += 1
	for cycle in 12:
		mobile._begin_shot(34,mobile._charge_center,"FLAT")
		mobile._drag(34,mobile._charge_center+Vector2(80,0))
		mobile.cancel_all(); mobile.cancel_all(); mobile._release(34,true)
		check(mobile._owners.is_empty() and mobile._charge_id==-1 and not mobile._hit_timing.active,"rapid repeated cancel resurrected visuals")
		check(not Input.is_action_pressed("ui_accept"),"rapid repeated cancel leaked action")
		counts.repeat_cancel += 1
	observe("touch_interruption_controls_"+view,{"completed":counts})
