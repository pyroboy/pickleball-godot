extends "res://scripts/tests/cloud_movement_f_visual_soak_projection.gd"
## Read-only end-of-frame presentation observations over real touch-driven gameplay.
## No direct ball, contact, score, semantic status, camera transform or target writes.
var detail_file: FileAccess
var detail_rows := 0
var schedule_profile := "standard"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): schedule_profile = arg.trim_prefix("--profile=")
	super._initialize()

func build_schedule() -> void:
	super.build_schedule()
	if schedule_profile == "drive":
		schedule = [[0.2,"practice_DRIVE"],[duration*0.45,"practice_RETURN"],[duration*0.8,"practice_DRIVE"]]

func lifecycle(kind: String, nominal: float) -> void:
	await super.lifecycle(kind,nominal)
	if is_instance_valid(game):
		event("temporal_lifecycle_state",{"action":kind,"reset_before":reset_before,"ball_position":game.ball.global_position,"score":[game.score_left,game.score_right],"serving":game.serving_team,"paused":paused})

func driver(now: int) -> void:
	super.driver(now)

func observe(delta: float) -> void:
	super.observe(delta)
	if not monitor or changing_scene or not is_instance_valid(game): return
	if detail_file == null: detail_file = FileAccess.open(output.path_join("temporal_detail.jsonl"),FileAccess.WRITE)
	var camera: Camera3D = root.get_camera_3d()
	var trajectory = game.game_trajectory
	var aim = game.aim_controller
	var focus = game.aim_focus
	var mobile = game.mobile_controls
	var target: Vector3 = aim.get_target()
	var wall: bool = game.practice_launcher.is_wall()
	var expected_cursor: Vector3 = target + Vector3(0,0,0.035) if wall else Vector3(target.x,0.105,target.z)
	var cursor: MeshInstance3D = trajectory.landing_cursor
	var cursor_error := cursor.global_position.distance_to(expected_cursor) if cursor.visible else 0.0
	var expected_label := "CHECK ARC" if focus.active and focus.preview_hint != "ESTIMATED ARC" else "AIM" if wall else "ESTIMATED AREA"
	var expected_visible: bool = aim.cursor_visible and Input.is_action_pressed("ui_accept") and not aim.is_locked() and not mobile._cancel_armed and not game._tool_state_active()
	var cursor_screen_error := 0.0
	if cursor.visible and camera and not camera.is_position_behind(expected_cursor) and not camera.is_position_behind(cursor.global_position):
		cursor_screen_error = camera.unproject_position(cursor.global_position).distance_to(camera.unproject_position(expected_cursor))
	var trail = game.get_node_or_null("BallTrail")
	var trail_points := 0
	var trail_max_segment := 0.0
	var trail_first_last := 0.0
	if trail:
		trail_points = trail._points.size()
		for i in range(1,trail_points): trail_max_segment = maxf(trail_max_segment,trail._points[i].distance_to(trail._points[i-1]))
		if trail_points > 1: trail_first_last = trail._points[0].distance_to(trail._points[-1])
	var guide = game.movement_guide
	var row := {"elapsed":elapsed(),"usec":Time.get_ticks_usec(),"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"scene":scene_number,
		"flight":game.ball.flight_id,"bounce":game.ball.bounces_since_last_hit,"state":game.game_state,"blocked":mobile._blocked(),"held":Input.is_action_pressed("ui_accept"),"mode":aim.mode,"practice":last_state.get("practice",""),
		"focus":focus.active,"focus_hint":focus.preview_hint,"focus_visible":focus._drawing.visible,"cursor_visible":cursor.visible,"cursor_expected_visible":expected_visible,
		"cursor_error_world":cursor_error,"cursor_error_px":cursor_screen_error,"cursor_label":trajectory.landing_label.text,"cursor_expected_label":expected_label,
		"cursor_target":cursor.global_position,"current_target":expected_cursor,"charge":game.hud._charge_bar.value,"camera":camera.global_transform if camera else Transform3D.IDENTITY,
		"trail_points":trail_points,"trail_max_segment_world":trail_max_segment,"trail_first_last_world":trail_first_last,"ball_speed":game.ball.linear_velocity.length(),
		"guide_visible":not guide._presentation.is_empty(),"guide_status":guide._presentation.get("status",""),"guide_advice_status":guide._advice.get("status",""),"guide_reason":guide._advice.get("reason",""),
		"guide_generation":game._point_reset_generation,"guide_target":guide._advice.get("target_root",Vector3.INF),"hit_ready":mobile._hit_timing.ready,"hit_caption":mobile._hit_timing.caption,"hit_draw_fraction":mobile._timing_draw_fraction}
	detail_file.store_line(JSON.stringify(row));detail_rows+=1
	if detail_rows%rate==0:detail_file.flush()
