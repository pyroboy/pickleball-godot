extends "res://scripts/tests/cloud_movement_integration.gd"
## Focus projection audit. Runtime candidate adds only a late presentation pass;
## original owner tick and slow-motion/deadline scheduling remain untouched.
var focus
var start_usec := 0
var auditing := false
var late_presentation := false
var target_error := 0.0
var path_error := 0.0
var uv_error := 0.0
var mismatch_frames := 0
var focus_frames := 0
var timeline: Array = []
var events: Dictionary = {}
var late_node
var input_node
var observer
var presentation_relay
var callback_total := 0
var callback_frames: Dictionary = {}
var native_capture := false
var geometry_only := false
var capture_index := 0
var capture_limit := 0
var capture_rows: Array = []
var simulation_seconds := 0.0
var gesture_restarts := 0

class Motion extends Node:
	var test
	func _process(delta: float) -> void: test.motion(delta)
class LatePresentation extends Node:
	var test
	func _process(_delta: float) -> void:
		if not test.auditing: return
		var before: Array = test.fingerprint()
		var deadlines: Array = [test.focus.deadline_usec, test.focus._rally_deadline_usec, test.focus.active, test.focus.holding, Engine.time_scale]
		if test.focus.active: test.focus._update_presentation(Time.get_ticks_usec())
		test.check(before == test.fingerprint(), "late focus presentation changed gameplay/input")
		test.check(deadlines == [test.focus.deadline_usec, test.focus._rally_deadline_usec, test.focus.active, test.focus.holding, Engine.time_scale], "late presentation changed focus deadlines or time scale")
class PresentationRelay extends RefCounted:
	var test
	func _present_after_camera() -> void:
		var frame := Engine.get_process_frames()
		test.callback_total += 1
		test.callback_frames[frame] = int(test.callback_frames.get(frame, 0)) + 1
		var before: Array = test.fingerprint()
		var deadlines: Array = [test.focus.deadline_usec, test.focus._rally_deadline_usec, test.focus.active, test.focus.holding, Engine.time_scale]
		test.focus._present_after_camera()
		if test.auditing:
			test.check(test.callback_frames[frame] == 1, "more than one native focus presentation callback per frame")
			test.check(before == test.fingerprint(), "actual late focus presentation changed gameplay/input/phase")
			test.check(deadlines == [test.focus.deadline_usec, test.focus._rally_deadline_usec, test.focus.active, test.focus.holding, Engine.time_scale], "actual presentation changed focus deadlines or time scale")
	func draw_preview(canvas: Control) -> void: test.focus.draw_preview(canvas)

class Observer extends Node:
	var test
	func _process(_delta: float) -> void: test.audit()
	func _physics_process(delta: float) -> void:
		if test.auditing: test.simulation_seconds += delta

func _initialize() -> void:
	super._initialize()
	late_presentation = OS.get_cmdline_user_args().has("--late-focus-presentation")
	native_capture = OS.get_cmdline_user_args().has("--capture")
	geometry_only = OS.get_cmdline_user_args().has("--geometry-only")
	if native_capture:
		Engine.max_fps = rate
		Engine.max_physics_steps_per_frame = 1
		capture_limit = ceili(rate * 2.3)

func run() -> void:
	if not OS.get_user_data_dir().contains("movement-rotation-"):
		push_error("Isolated movement-rotation HOME/XDG required"); quit(2); return
	create_timer(180.0 if native_capture else 30.0, true).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	var pause = root.get_node("PauseController")
	pause.set_process_input(false)
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.content_scale_size = Vector2i(720, 1280); root.size = Vector2i(390, 844)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(5); await physics_frame
	guide = game.movement_guide; focus = game.aim_focus
	game.input_handler.set_process(false)
	if focus.has_method("_present_after_camera"):
		# Transparent one-for-one forwarding counts the actual patched drawing
		# callback. No priority, clock, deadline or production logic is replaced.
		presentation_relay = PresentationRelay.new(); presentation_relay.test = self
		focus._drawing.owner_focus = presentation_relay
		check(focus.process_priority == 0 and focus._drawing.process_priority > game.camera_rig.process_priority, "production patch moved the focus clock or failed late ordering")
	game._reset_ball(); game.pvp_mode = false; focus._sync_realtime_mode()
	game.hud.set_gameplay_elements_visible(true); game.hud._guide.hide(); game.hud._between_point_active = false
	Input.action_press("ui_accept"); game._on_player_swing_press(); game.aim_controller.update(0.1, true, Vector2.ZERO)
	check(focus.active and focus.holding and focus.is_processing(), "actual serving hold did not activate automatic focus")
	input_node = Motion.new(); input_node.test = self; input_node.process_priority = -100; root.add_child(input_node)
	if late_presentation:
		late_node = LatePresentation.new(); late_node.test = self; late_node.process_priority = game.camera_rig.process_priority + 1; root.add_child(late_node)
	observer = Observer.new(); observer.test = self; observer.process_priority = 2001; root.add_child(observer)
	start_usec = Time.get_ticks_usec(); auditing = true
	if native_capture:
		while capture_index < capture_limit:
			if geometry_only: await process_frame
			else: await RenderingServer.frame_post_draw
			capture_frame()
	else:
		while Time.get_ticks_usec() - start_usec < 2300000: await process_frame
	auditing = false
	check(focus_frames > 10, "too few active automatic focus frames")
	check(mismatch_frames == 0, "focus differs from final camera in %d frames: target %.3f px, path %.3f px, protected UV %.3f px" % [mismatch_frames, target_error, path_error, uv_error])
	var report := {"scope": "Frozen portable cloud checkpoint C focus final-camera diagnostics", "scenario": "focus", "rate": rate,
		"checks": checks, "failures": failures, "active_focus_frames": focus_frames, "mismatch_frames": mismatch_frames,
		"max_target_error_pixels": target_error, "max_path_error_pixels": path_error, "max_protected_uv_error_pixels": uv_error,
		"late_presentation_candidate": late_presentation, "original_focus_priority": focus.process_priority, "camera_priority": game.camera_rig.process_priority,
		"original_tick_unchanged": true, "native_capture": native_capture, "rendered_images": native_capture and not geometry_only,
		"capture_frames": capture_rows, "capture_nominal_hz": rate, "capture_note": "Frame-driven camera replay; actual focus deadlines remain real-time. Natural expiry starts a fresh held gesture, explicitly recorded. Offline capture cadence is not device FPS.", "gesture_restarts": gesture_restarts, "native_presentation_callbacks": callback_total, "native_callback_frames": callback_frames.size(), "transparent_callback_counter": presentation_relay != null, "timeline": timeline, "events": events}
	FileAccess.open(OS.get_environment("MOVEMENT_INTEGRATION_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	Input.action_release("ui_accept"); game.input_handler.cancel_charge_input(); focus.cancel()
	observer.queue_free(); input_node.queue_free()
	if late_node != null: late_node.queue_free()
	game.queue_free(); current_scene = null; await frames(3)
	var until := Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("MOVEMENT FOCUS PROJECTION %d Hz: %d checks, %d failures, target %.3f path %.3f UV %.3f px" % [rate, checks, failures.size(), target_error, path_error, uv_error])
	quit(0 if failures.is_empty() else 1)

func event(key: String, time: float) -> bool:
	if events.has(key): return false
	events[key] = time; return true

func motion(delta: float) -> void:
	if not auditing: return
	var time := float(capture_index) / rate if native_capture else float(Time.get_ticks_usec() - start_usec) / 1000000.0
	if native_capture and (not focus.active or not focus.holding):
		# Never extend or fake a real focus deadline to accommodate PNG readback.
		# A fresh input gesture is explicit recording-fixture input after expiry.
		Input.action_release("ui_accept"); game.input_handler.cancel_charge_input(); focus.end_hold()
		Input.action_press("ui_accept"); game._on_player_swing_press()
		gesture_restarts += 1
	game.aim_controller.update(delta, true, Vector2(0.1, -0.05), true)
	if time >= 0.15 and event("third_person", time): game.camera_rig.set_gameplay_camera_mode(1)
	if time >= 0.45 and event("landscape", time): root.size = Vector2i(960, 540)
	if time >= 0.65 and event("pov", time): game.camera_rig.set_gameplay_camera_mode(2)
	if time >= 1.05 and event("portrait_return", time): root.size = Vector2i(430, 932)
	if time >= 1.5 and event("center", time): game.camera_rig.set_gameplay_camera_mode(0)

func audit() -> void:
	if not auditing or not focus._presentation: return
	focus_frames += 1
	if presentation_relay != null: check(callback_frames.get(Engine.get_process_frames(), 0) == 1, "native active frame lacks exactly one presentation callback")
	var camera: Camera3D = game.camera_rig.camera
	var size := root.get_visible_rect().size
	var target: Vector3 = game.aim_controller.get_target()
	var target_delta := 0.0
	var path_delta := 0.0
	var uv_delta := 0.0
	if camera.is_position_behind(target): target_delta = 1000000.0
	else: target_delta = camera.unproject_position(target).distance_to(focus._target_screen)
	var display: PackedVector3Array = focus._preview_stabilizer._path_current
	check(display.size() == focus._screen_path.size(), "screen path and current stabilized world path disagree")
	for index in mini(display.size(), focus._screen_path.size()):
		path_delta = maxf(path_delta, camera.unproject_position(display[index]).distance_to(focus._screen_path[index]))
	var protections := {"blue_uv": game.player_left.global_position + Vector3.UP * 0.10,
		"blue_head_uv": game.player_left.global_position + Vector3.UP * 1.75,
		"red_uv": game.player_right.global_position + Vector3.UP * 0.10,
		"red_head_uv": game.player_right.global_position + Vector3.UP * 1.75,
		"ball_uv": game.ball.global_position}
	for key in protections:
		var expected: Vector2 = focus._protected_uv(camera, protections[key], size)
		var actual: Vector2 = focus._material.get_shader_parameter(key)
		uv_delta = maxf(uv_delta, ((actual - expected) * size).length())
	target_error = maxf(target_error, target_delta); path_error = maxf(path_error, path_delta); uv_error = maxf(uv_error, uv_delta)
	if maxf(target_delta, maxf(path_delta, uv_delta)) > 0.05: mismatch_frames += 1
	timeline.append({"render_frame": Engine.get_process_frames(), "wall_seconds": float(Time.get_ticks_usec() - start_usec) / 1000000.0,
		"window_size": [root.size.x, root.size.y], "camera_mode": game.camera_rig.gameplay_camera.mode,
		"target_error_pixels": target_delta, "path_error_pixels": path_delta, "protected_uv_error_pixels": uv_delta,
		"camera_transform": str(camera.global_transform), "focus_active": focus.active, "focus_holding": focus.holding,
		"time_scale": Engine.time_scale, "preview_solves": focus.preview_solves})

func capture_frame() -> void:
	var output := OS.get_environment("MOVEMENT_INTEGRATION_REPORT").get_base_dir()
	var filename := "focus-%04d.png" % capture_index
	if not geometry_only:
		var image := root.get_texture().get_image()
		check(image.save_png(output.path_join(filename)) == OK, "native focus PNG save failed")
	var audit_row: Dictionary = timeline[-1] if not timeline.is_empty() and timeline[-1].render_frame == Engine.get_process_frames() else {}
	capture_rows.append({"image": "" if geometry_only else filename, "index": capture_index,
		"nominal_seconds": float(capture_index) / rate, "simulation_seconds": simulation_seconds,
		"wall_seconds": float(Time.get_ticks_usec() - start_usec) / 1000000.0,
		"window_size": [root.size.x, root.size.y], "camera_mode": game.camera_rig.gameplay_camera.mode,
		"focus_active": focus.active, "holding": focus.holding, "presentation": focus._presentation,
		"deadline_usec": focus.deadline_usec, "started_usec": focus.started_usec,
		"time_scale": Engine.time_scale, "human_phase": game.player_left.posture.human_contact.phase,
		"gesture_restarts": gesture_restarts, "projection_audit": audit_row})
	capture_index += 1
