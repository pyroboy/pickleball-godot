extends CanvasLayer


const MAX_REAL_USEC: = 4000000
const START_FOCUS_SCALE: = 0.6
const END_FOCUS_SCALE: = 0.12
const DEFAULT_RALLY_SECONDS: = 3.0
const RALLY_MIN_SCALE: = 0.001
const CONTACT_SAFETY_SECONDS: = 0.03
const REACH_ENTER_USEC: = 60000
const REACH_EXIT_USEC: = 120000
const URGENT_CONTACT_SECONDS: = 0.18
const FOCUS_ENTER_TTC: = 0.85
const FOCUS_EXIT_TTC: = 1.0
const PREVIEW_INTERVAL_USEC: = 250000
const MAX_PREVIEW_POINTS: = 48
const Accuracy = preload("res://scripts/shot_accuracy.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Estimate = preload("res://scripts/aim_preview_estimate.gd")
const ContactPlanner = preload("res://scripts/incoming_contact_planner.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const FocusShader = preload("res://shaders/solo_aim_focus.gdshader")
const FocusDimShader = preload("res://shaders/solo_aim_focus_dim.gdshader")
const VISUAL_ENTER_USEC: = 120000
const PreviewStabilizer = preload("res://scripts/ui/aim_preview_stabilizer.gd")
const ArcStyle = preload("res://scripts/ui/aim_arc_style.gd")
var game
var active: = false
var holding: = false
var exhausted: = false
var started_usec: = 0
var deadline_usec: = 0
var _rally_hold: = false
var _rally_flight_id: = -1
var _rally_deadline_usec: = 0
var _rally_window_usec: = 0
var _reach_enter_usec: = -1
var _reach_exit_usec: = -1
var _last_rally_scale: = START_FOCUS_SCALE
var preview_solves: = 0
var preview_hint: = "ESTIMATED ARC"
var _last_estimate: Dictionary = {}
var _preview_target: = Vector3.INF
var _preview_start: = Vector3.INF
var _last_preview_usec: = -1000000
var _last_preview_key: = ""
var _world_path: = PackedVector3Array()
var _screen_path: = PackedVector2Array()
var _realtime_locked: = false
var _dim: ColorRect
var _material: ShaderMaterial
var _drawing: Control
var _target_screen: = Vector2.ZERO
var _accuracy_outline: = PackedVector2Array()
var _presentation: = false
var _visual_enter_usec: = -1
var _preview_context_key: = ""
var _preview_revision: = 0
var _preview_stabilizer = PreviewStabilizer.new()

class FocusDrawing extends Control:
	var owner_focus
	func _process(_delta: float) -> void:
		# Projection must use CameraRig's final eye/ball correction, but the
		# owner's gameplay clock/deadline tick keeps its original early order.
		if is_instance_valid(owner_focus): owner_focus._present_after_camera()
	func _draw() -> void :
		if owner_focus: owner_focus.draw_preview(self)

func setup(owner_game) -> void :
	game = owner_game
	name = "SoloAimFocus"
	layer = -1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = FocusShader
	_dim.material = _material
	add_child(_dim)
	_drawing = FocusDrawing.new()
	_drawing.process_priority = 1001 # After CameraRig (1000); presentation only.
	_drawing.owner_focus = self
	_drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_drawing)
	_hide_presentation()
	_sync_realtime_mode()

func is_solo() -> bool:
	if game == null or game.pvp_mode or not game.player_right.is_ai: return false
	var peer = game.multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer

func _sync_realtime_mode() -> void :
	var required: bool = not is_solo()
	if required == _realtime_locked: return
	_realtime_locked = required
	TimeScale.set_realtime_required("pvp", required)
	if required: cancel()

func _eligible() -> bool:
	if game == null or not is_solo() or get_tree().paused or game._tool_state_active() or game.match_over: return false
	if not game.hud._gameplay_visible or game.hud._guide.visible: return false
	if game.practice_panel and game.practice_panel.visible: return false
	if game.practice_launcher and game.practice_launcher.demo_enabled and game.practice_launcher.is_active: return false
	return game.game_state == 0 and game.human_may_serve() or game.game_state == 2 and game.ball.is_in_play

func begin_hold(now_usec: int = -1) -> bool:
	_sync_realtime_mode()
	if holding or not _eligible(): return false
	holding = true
	exhausted = false
	started_usec = Time.get_ticks_usec() if now_usec < 0 else now_usec
	_rally_hold = game.game_state == 2
	_reset_reach_gate()
	if _rally_hold:
		_update_rally_focus(started_usec)
	else:
		deadline_usec = started_usec + MAX_REAL_USEC
		_start(START_FOCUS_SCALE)
	return true

func _start(scale: float) -> void :
	active = true
	_last_preview_usec = -1000000
	_last_preview_key = ""
	TimeScale.request_slowmo("aim_focus", scale)

func _reset_reach_gate() -> void :
	_reach_enter_usec = -1
	_reach_exit_usec = -1

func rally_window_seconds() -> float:
	var seconds: float = float(Settings.get_value("gameplay.aim_focus_seconds", DEFAULT_RALLY_SECONDS))
	return clampf(seconds, 1.0, 5.0) if is_finite(seconds) else DEFAULT_RALLY_SECONDS

static func adaptive_rally_scale(ttc: float, remaining_seconds: float, progressive_scale: float) -> float:
	if remaining_seconds <= 0.0: return 1.0
	# A finite, nonzero brake. Near-zero or already-passed contact cannot promise
	# the full window; never freeze the ball or invent a reachable contact.
	return minf(progressive_scale, maxf(RALLY_MIN_SCALE, (ttc - CONTACT_SAFETY_SECONDS) / remaining_seconds))

func _rally_contact_sample() -> Dictionary:
	var ball = game.ball
	var human = game.player_left.posture.human_contact
	if ball.last_hit_by == game.player_left.player_num or ball.bounces_since_last_hit >= 2 or human == null or human.phase >= 0:
		return {}
	var timing: Dictionary = human.release_timing_state()
	if not bool(timing.get("current_reachable", false)) or int(timing.get("flight_id", -1)) != int(ball.flight_id): return {}
	var ttc: float = float(timing.get("time", -1.0))
	if not is_finite(ttc) or ttc < 0.0: return {}
	if is_zero_approx(ttc) and not human.contact.is_empty():
		# The planner reports zero throughout its live contact slab, including
		# balls still ahead of the paddle. Preserve that remaining opportunity
		# instead of misclassifying every live-window entry as already too late.
		var forward: Vector3 = game.player_left._get_forward_axis()
		var relative_forward: float = (ball.global_position - game.player_left.global_position).dot(forward)
		var plane: float = human.contact.def.zone_forward_offset
		var closing_speed: float = -ball.linear_velocity.dot(forward)
		if absf(relative_forward - plane) <= ContactPlanner.LIVE_WINDOW + 0.0001 and closing_speed > 0.1:
			ttc = maxf(0.0, (relative_forward - plane + ContactPlanner.LIVE_WINDOW) / closing_speed)
	return {"ttc": ttc, "locked": game.aim_controller.mode == "AIM" and game.aim_controller.planted}

func _update_rally_focus(now_usec: int) -> void :
	var ball = game.ball
	if ball.last_hit_by != game.player_left.player_num and int(ball.flight_id) != _rally_flight_id:
		_rally_flight_id = int(ball.flight_id)
		_rally_deadline_usec = 0
		_rally_window_usec = 0
		exhausted = false
		_stop()
		_reset_reach_gate()
	deadline_usec = _rally_deadline_usec
	# Wall time outside reach and released-button time still count. Only a new
	# incoming flight resets this deadline, never zone wiggles or repeated presses.
	if _rally_deadline_usec > 0 and now_usec >= _rally_deadline_usec:
		exhausted = true
		_stop()
		return
	var human = game.player_left.posture.human_contact
	if ball.last_hit_by == game.player_left.player_num or ball.bounces_since_last_hit >= 2 or human == null or human.phase >= 0:
		_stop()
		_reset_reach_gate()
		return
	var sample: Dictionary = _rally_contact_sample()
	var reachable: bool = not sample.is_empty() and bool(sample.locked) and float(sample.ttc) <= (FOCUS_EXIT_TTC if active else FOCUS_ENTER_TTC)
	if not reachable:
		_reach_enter_usec = -1
		if active:
			if _reach_exit_usec < 0: _reach_exit_usec = now_usec
			if now_usec - _reach_exit_usec >= REACH_EXIT_USEC: _stop()
		return
	_reach_exit_usec = -1
	if not active:
		if _reach_enter_usec < 0: _reach_enter_usec = now_usec
		if float(sample.ttc) > URGENT_CONTACT_SECONDS and now_usec - _reach_enter_usec < REACH_ENTER_USEC: return
		if _rally_deadline_usec == 0:
			_rally_window_usec = roundi(rally_window_seconds() * 1000000.0)
			_rally_deadline_usec = now_usec + _rally_window_usec
			deadline_usec = _rally_deadline_usec
	var remaining: float = float(_rally_deadline_usec - now_usec) / 1000000.0
	var elapsed_fraction: float = 1.0 - float(_rally_deadline_usec - now_usec) / float(_rally_window_usec)
	_last_rally_scale = adaptive_rally_scale(float(sample.ttc), remaining, scale_for_elapsed(roundi(elapsed_fraction * MAX_REAL_USEC)))
	if not active: _start(_last_rally_scale)
	else: TimeScale.request_slowmo("aim_focus", _last_rally_scale)

static func scale_for_elapsed(elapsed_usec: int) -> float:


	var progress: float = clampf(float(elapsed_usec) / MAX_REAL_USEC, 0.0, 1.0)
	return lerpf(START_FOCUS_SCALE, END_FOCUS_SCALE, progress * progress)

func end_hold() -> void :
	holding = false
	exhausted = false
	_reset_reach_gate()
	_stop()

func cancel() -> void :


	holding = false
	exhausted = false
	_reset_reach_gate()
	_stop()

func _stop() -> void :
	active = false
	TimeScale.release("aim_focus")
	_hide_presentation()

func tick(now_usec: int, held: bool) -> void :
	_sync_realtime_mode()
	if not held:
		if holding or active: end_hold()
		return
	if not holding: return
	if not _eligible():
		cancel()
		if game and game.input_handler and (get_tree().paused or game._tool_state_active() or not game.hud._gameplay_visible or game.hud._guide.visible or game.practice_panel and game.practice_panel.visible):
			game.input_handler.cancel_charge_input()
		return
	if _rally_hold:
		_update_rally_focus(now_usec)
		return
	if active:
		if now_usec >= deadline_usec:
			exhausted = true
			_stop()
		else:
			TimeScale.request_slowmo("aim_focus", scale_for_elapsed(now_usec - started_usec))

func _process(_delta: float) -> void :
	tick(Time.get_ticks_usec(), Input.is_action_pressed("ui_accept"))
	if not active: _hide_presentation()

func _present_after_camera() -> void:
	if not active:
		_hide_presentation()
		return
	_update_presentation(Time.get_ticks_usec())

func _hide_presentation() -> void :
	_presentation = false
	_visual_enter_usec = -1
	_preview_stabilizer.reset()
	if _dim: _dim.hide()
	if _drawing: _drawing.hide()

func _update_presentation(now_usec: int) -> void :
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null: _hide_presentation();return
	var target: Vector3 = game.aim_controller.get_target()
	if not ArcStyle.is_projectable(target, camera): _hide_presentation();return
	var previous_hint: String = preview_hint
	_refresh_preview(now_usec, target)
	var stale: bool = not _last_estimate.is_empty() and target.distance_to(_preview_target) > 0.12
	var current_start: Vector3 = game.game_serve.get_serve_launch_position(false) if game.game_state == 0 else Vector3.INF
	var contact_valid: bool = game.game_state == 0
	if game.game_state == 2:
		var human = game.player_left.posture.human_contact
		contact_valid = human != null and not human.contact.is_empty() and int(human._flight_id) == int(game.ball.flight_id)
		if contact_valid:
			current_start = human.contact.point
			stale = stale or current_start.distance_to(_preview_start) > 0.12
	var context: String = _current_preview_context()
	var aim_locked: bool = game.aim_controller.mode == "AIM"
	# Raw charge/arc motion keeps the label neutral between quantized solver
	# refreshes. Quantization remains an unchanged solver-cost optimization.
	var motion_context: String = context + "|%.4f|%.4f" % [game.input_handler.serve_charge_time, game.trajectory_arc_offset]
	var settling: bool = _preview_stabilizer.observe(now_usec, target, current_start, motion_context, contact_valid, aim_locked, game.practice_launcher.is_wall() or Estimate.risk_label(_last_estimate) == "ESTIMATED ARC")
	stale = stale or not contact_valid or not aim_locked or context != _preview_context_key or settling
	preview_hint = "UPDATING ARC" if stale else ("ESTIMATED ARC" if game.practice_launcher.is_wall() else Estimate.risk_label(_last_estimate))
	if preview_hint != previous_hint and game.hud:
		# InputHandler publishes aim mode before this presentation pass. Refresh
		# only changed meaning so HUD and arc never disagree for a frame.
		game.hud.set_aim_state(game.aim_controller.mode)
	# The actual aim target stays immediate and stable. Risk belongs to the
	# estimated arc, not a second cached highlight that jumps between net/landing.
	_target_screen = camera.unproject_position(target)
	var show_preview: bool = bool(Settings.get_value("video.focus_preview", true))
	_accuracy_outline.clear()
	if show_preview and not game.practice_launcher.is_wall():
		var serve: bool = game.game_state == 0
		var charge: float = game.game_serve.get_charge_ratio() if serve else game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME
		var mode: int = Styles.spin_mode(game.game_serve.selected_serve_style) if serve else game.selected_spin_mode
		var axes: Vector2 = Accuracy.display_radii(charge, mode, "AUTO" if serve else game.selected_shot_intent, serve)
		for index in range(49):
			var angle: float = TAU * float(index) / 48.0
			var outline_point: Vector3 = target + Vector3(cos(angle) * axes.x, 0.012, sin(angle) * axes.y)
			if not ArcStyle.is_projectable(outline_point, camera):
				_accuracy_outline.clear()
				break
			_accuracy_outline.append(camera.unproject_position(outline_point))
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0: _hide_presentation();return
	var dim_amount: float = float(Settings.get_value("video.focus_dim", 0.14))
	var blur_amount: float = float(Settings.get_value("video.focus_blur", 0.65))
	var desired_shader: Shader = FocusShader if blur_amount > 0.0 else FocusDimShader
	if _material.shader != desired_shader: _material.shader = desired_shader
	if _visual_enter_usec < 0: _visual_enter_usec = now_usec
	var progress: float = clampf(float(now_usec - _visual_enter_usec) / VISUAL_ENTER_USEC, 0.0, 1.0)
	var visual_mix: float = smoothstep(0.0, 1.0, progress)
	_material.set_shader_parameter("viewport_size", size)
	_material.set_shader_parameter("target_uv", _target_screen / size)
	_material.set_shader_parameter("blue_uv", _protected_uv(camera, game.player_left.global_position + Vector3.UP * 0.10, size))
	_material.set_shader_parameter("blue_head_uv", _protected_uv(camera, game.player_left.global_position + Vector3.UP * 1.75, size))
	_material.set_shader_parameter("red_uv", _protected_uv(camera, game.player_right.global_position + Vector3.UP * 0.10, size))
	_material.set_shader_parameter("red_head_uv", _protected_uv(camera, game.player_right.global_position + Vector3.UP * 1.75, size))
	_material.set_shader_parameter("ball_uv", _protected_uv(camera, game.ball.global_position, size))
	_material.set_shader_parameter("radius", 70.0 * Layout.scale_for(size))
	_material.set_shader_parameter("strength", dim_amount * visual_mix)
	if blur_amount > 0.0:
		_material.set_shader_parameter("blur_radius", blur_amount * 2.0 * Layout.scale_for(size))
		_material.set_shader_parameter("effect_mix", visual_mix)
	var display_path: PackedVector3Array = _preview_stabilizer.present(_world_path, _preview_revision, Estimate.risk_label(_last_estimate), now_usec)
	# Advance present() above even while hidden, so reveal uses the current
	# trajectory/blend state. Only unused screen geometry is skipped.
	_screen_path = ArcStyle.project_path(display_path, camera) if show_preview else PackedVector2Array()
	_presentation = true
	_dim.visible = dim_amount > 0.0 or blur_amount > 0.0
	_drawing.visible = show_preview
	if show_preview: _drawing.queue_redraw()

func _protected_uv(camera: Camera3D, point: Vector3, size: Vector2) -> Vector2:
	# Behind-camera objects cannot leave a stale bright hole on the screen.
	return Vector2(-2.0, -2.0) if camera.is_position_behind(point) else camera.unproject_position(point) / size

func _current_preview_context() -> String:
	var charge: float = snappedf(game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.1)
	return "%.1f|%d|%s|%d|%d|%.2f|%s" % [charge, game.selected_spin_mode, game.selected_shot_intent, game.game_state, game.game_serve.selected_serve_style, game.trajectory_arc_offset, game._pending_shot_type]

func _refresh_preview(now_usec: int, target: Vector3) -> void :
	if now_usec - _last_preview_usec < PREVIEW_INTERVAL_USEC: return
	_last_preview_usec = now_usec
	var start: Vector3
	var charge: float = snappedf(game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.1)
	if game.game_state == 0:
		start = game.game_serve.get_serve_launch_position(false)
	else:
		var human = game.player_left.posture.human_contact
		if human == null or human.contact.is_empty() or int(human._flight_id) != int(game.ball.flight_id):
			# Keep only a visibly uncertain estimate during the existing reach
			# grace period. Invalidating the key guarantees same-contact recovery.
			_last_preview_key = ""
			preview_hint = "UPDATING ARC"
			return
		start = human.contact.point
	var key: String = "%s|%s|%.1f|%d|%s|%d|%d|%.2f|%s" % [start.snapped(Vector3.ONE * 0.06), target.snapped(Vector3.ONE * 0.08), charge, game.selected_spin_mode, game.selected_shot_intent, game.game_state, game.game_serve.selected_serve_style, game.trajectory_arc_offset, game._pending_shot_type]
	if key == _last_preview_key: return
	_last_preview_usec = now_usec
	_last_preview_key = key


	_preview_target = target;_preview_start = start
	_preview_context_key = _current_preview_context()
	if game.practice_launcher.is_wall():
		_last_estimate = game.practice_launcher.wall_practice.preview(start, target, charge, game.selected_spin_mode, game.selected_shot_intent)
	else:
		_last_estimate = Estimate.solve(start, target, charge, game.selected_spin_mode, game.selected_shot_intent, game._pending_shot_type, game.trajectory_arc_offset, game.game_serve.selected_serve_style if game.game_state == 0 else -1)
	preview_solves += 1
	_preview_revision += 1
	preview_hint = Estimate.risk_label(_last_estimate)
	_world_path = _last_estimate.points

func draw_preview(canvas: Control) -> void :
	if not _presentation: return
	var scale: float = Layout.scale_for(get_viewport().get_visible_rect().size)
	var color: = Color(0.82, 1.0, 0.52, 0.92) if preview_hint == "ESTIMATED ARC" else Color(1.0, 0.66, 0.35, 0.95)
	ArcStyle.draw(canvas, _screen_path, get_viewport().get_visible_rect(), color, scale, int(Settings.get_value("video.focus_arc_style", ArcStyle.DASHED)))
	if not _accuracy_outline.is_empty():
		canvas.draw_colored_polygon(_accuracy_outline, Color(color, 0.12))
		canvas.draw_polyline(_accuracy_outline, color, 1.8 * scale, true)
	else:
		canvas.draw_arc(_target_screen, 8 * scale, 0, TAU, 24, color, 1.5 * scale, true)

func _notification(what: int) -> void :
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]: cancel()

func _exit_tree() -> void :
	TimeScale.release("aim_focus")
	TimeScale.set_realtime_required("pvp", false)
