extends Node3D
class_name CameraRig
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")










const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
var _portrait_camera: = false
var _portrait_fit_view: = Vector2.ZERO
var _portrait_fit_safe: = Rect2()
var _portrait_fit_position: = Vector3.ZERO
var _portrait_fit_rotation: = Vector3.ZERO
var _portrait_fit_offset: = 0.0
const PORTRAIT_HORIZONTAL_FOV: = 34.0
var portrait_elevation_degrees: = 48.0
var _portrait_frame_elevation: = 40.0
var _portrait_fit_elevation: = INF
var portrait_anchor_z: = 6.8
var portrait_anchor_height: = 1.0
var portrait_max_baseline_view_angle: = 50.0
var _portrait_fit_anchor: = Vector3.INF
# Off: the rally view is one fixed framing. The adaptive fit re-zoomed and
# re-centred on the players and ball all the time, which read as a restless camera.
var portrait_adaptive_framing: = false
# The between-point close-up flew across the net to the ball pickup. Off: the
# camera stays in its overview on the near side of the court.
var between_point_cinematic_enabled: = false
# Rally view is pushed in from the whole-court fit so play reads on a phone:
# the camera sits PLAY_PUSH of the way toward a slow, damped play point (the
# ball while in play, else the player), which stays put on screen while the
# court grows around it. Clamped so both baselines' players stay in frame.
const PLAY_PUSH: = 0.26
const PLAY_FOLLOW_RATE: = 1.6      # 1/s: slow, so it never reads as a restless camera
var _play_point: = Vector3.INF
# Slow motion (aim hold): an extra push toward the ball with a slightly wider lens.
const SLOWMO_PUSH: = 0.24          # extra share of the remaining way to the ball at full effect
const SLOWMO_FOV_ADD: = 5.0        # degrees wider while pushed in (perspective stretch)
const SLOWMO_FULL_SCALE: = 0.55    # time scale at which the effect is complete
var _slowmo_focus: = 0.0
# Cinematic push-ins (camera only, nothing waits on them): serve intro, point-won hold,
# match point and win. Zero during rally play so the tuned rally framing is untouched.
const CINE_SERVE: = 0.10
const CINE_MATCH_POINT: = 0.17
const CINE_POINT_WON: = 0.12
const CINE_WIN: = 0.30
const CINE_POINT_HOLD: = 1.0
const CINE_FOV_ADD: = 3.0
const CinematicBannerScript = preload("res://scripts/ui/cinematic_banner.gd")
var cinematic_enabled: = true
var _banner: CanvasLayer
var _cine_amount: = 0.0
var _cine_point: = Vector3.ZERO
var _cine_state: = -1
var _cine_state_time: = 0.0
var _cine_skipped: = false
var _cine_end_pending: = false
var _cine_match_point_shown: = false
var _slowmo_point: = Vector3.ZERO
var _portrait_action_zoom: = 1.0
# Fixed zoom steps (measured from the fitted zoom: tight net play ~0.70,
# serve / between points ~0.87, wide rallies ~0.95). The camera eases between
# them instead of re-fitting continuously ("breathing").
const ZOOM_STEPS: Array[float] = [0.72, 0.88, 1.0]
const ZOOM_IN_HOLD := 0.6     # s the tighter step must fit before zooming in
var _zoom_step: float = 1.0
var _zoom_in_timer: float = 0.0

const GameplayCamera = preload("res://scripts/camera/gameplay_camera.gd")
var gameplay_camera = GameplayCamera.new()

const BetweenPointCamera = preload("res://scripts/camera/between_point_camera.gd")
var _between_point_camera = BetweenPointCamera.new()
var _game_root: Node

const CameraShakeScript = preload("res://scripts/camera/camera_shake.gd")

const ORBIT_DISTANCE: float = 4.0
const ORBIT_HEIGHT: float = 1.2
const ORBIT_SPEED: float = 0.8
const ORBIT_DRAG_SENSITIVITY: float = 0.005
const EDGE_THRESHOLD: float = 2.5
const MAX_CAMERA_OFFSET: float = 3.0
const EDITOR_CAMERA_V_OFFSET: float = 0.0

var camera: Camera3D
var _shake


var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _ball: RigidBody3D
var _is_practice_cb: Callable


var orbit_mode: int = 0
var orbit_angle: float = 0.0
var orbit_pitch: float = 0.35
var orbit_auto: bool = false
var _orbit_dragging: bool = false
var _orbit_idle_timer: float = 0.0
var _default_pos: Vector3 = Vector3.ZERO
var _default_rot: Vector3 = Vector3.ZERO
var _cam_side_offset: float = 0.3
var _cam_look_target: Vector3 = Vector3.ZERO
var editor_focus_point: Vector3 = Vector3.INF
var _base_fov: float = 60.0




var is_mouse_over_editor_ui_cb: Callable = Callable()

const EDITOR_MIN_DISTANCE: = 1.5
const EDITOR_MAX_DISTANCE: = 12.0
var editor_active: = false
var editor_distance: = 4.6
var editor_target: = Vector3.ZERO
var _editor_orbit_dragging: = false
var _editor_pan_dragging: = false
var _editor_saved_state: Dictionary = {}

func _ready() -> void :
	name = "CameraRig"
	process_priority = 1000
	get_viewport().size_changed.connect(_on_viewport_resized)


func setup(
		parent: Node, 
		player_left: CharacterBody3D, 
		player_right: CharacterBody3D, 
		ball: RigidBody3D, 
		is_practice_cb: Callable = Callable()) -> Camera3D:
	_game_root = parent
	_player_left = player_left
	_player_right = player_right
	_ball = ball
	_is_practice_cb = is_practice_cb

	if get_parent() == null:
		parent.add_child(self)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	# Moved every rendered frame (follow, ball framing, cinematics), so it must
	# not be physics-interpolated: with 30 Hz interpolation on, it showed only sky.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = Vector3(0, 10.5, 11.0)
	camera.rotation_degrees = Vector3(-52, 0, 0)
	camera.fov = 60.0
	add_child(camera)

	_default_pos = camera.position
	_default_rot = camera.rotation_degrees

	_banner = CinematicBannerScript.new()
	_banner.name = "CinematicBanner"
	add_child(_banner)

	_shake = CameraShakeScript.new()
	_shake.name = "Shake"
	add_child(_shake)
	_shake.setup(camera)
	if MobileLayout.is_portrait(get_viewport().get_visible_rect().size):
		_update_portrait_camera(get_viewport().get_visible_rect().size)

	return camera


# Gameplay camera follows what is drawn (interpolated), since it updates every
# rendered frame; reading the 30 Hz physics positions would make it step.
static func _drawn(node: Node3D) -> Vector3:
	return node.get_global_transform_interpolated().origin

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.camera_rig", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	# The camera moves every rendered frame (was in game._physics_process at 30 Hz,
	# which made it step on a 60 Hz screen). The pose editor path stays in physics.
	if camera != null and not get_tree().paused and not (_game_root != null and _game_root._tool_state_active()):
		update(delta)
	# Player presentation and the held ball update after the physics camera.
	# Correct against the actual rendered target, never a one-frame-old ball.
	if camera == null or editor_active or orbit_mode != 0 or _between_point_camera.active or get_tree().paused: return
	_apply_end_flip()
	if _game_root and _game_root.practice_launcher and _game_root.practice_launcher.is_wall() and gameplay_camera.mode == GameplayCamera.CENTER: return
	if gameplay_camera.mode == GameplayCamera.POV:
		gameplay_camera._update_pov(camera, _player_left, _ball, delta)
	elif gameplay_camera.active_kind != "center":
		gameplay_camera._keep_ball_visible(camera, _ball)

func _on_viewport_resized() -> void:
	end_between_point_cinematic()
	gameplay_camera.suspend()
	_portrait_action_zoom = 1.0
	_zoom_step = 1.0
	_zoom_in_timer = 0.0

func set_gameplay_camera_mode(value: int) -> void:
	end_between_point_cinematic()
	gameplay_camera.set_mode(value)
	if editor_active:
		_editor_saved_state["mode"] = 0
	elif orbit_mode == 3 and _game_root:
		_game_root._editor_previous_camera_mode = 0
	else:
		orbit_mode = 0

func add_shake(amount: float) -> void :
	if _shake != null and not editor_active:
		_shake.add_trauma(amount)

func set_fov(new_fov: float) -> void :
	_base_fov = clampf(new_fov, 30.0, 110.0)
	if camera != null and orbit_mode != 3:
		camera.fov = PORTRAIT_HORIZONTAL_FOV if _portrait_camera and orbit_mode == 0 else _base_fov


func cycle_third_person() -> void :
	end_between_point_cinematic()
	orbit_mode = (orbit_mode + 1) % 3
	_orbit_dragging = false
	if orbit_mode == 0:
		if camera != null:
			camera.position = _default_pos
			camera.rotation_degrees = _default_rot
		if _shake != null:
			_shake.reset()
		if RuntimePolicy.developer_tools: print("[CAM] Default camera")
	elif orbit_mode == 1:
		if RuntimePolicy.developer_tools: print("[CAM] 3rd person BLUE — looking at red service line")
	elif orbit_mode == 2:
		if RuntimePolicy.developer_tools: print("[CAM] 3rd person RED — looking at blue service line")

func toggle_auto_orbit() -> void :
	if orbit_mode == 0:
		return
	orbit_auto = not orbit_auto
	if RuntimePolicy.developer_tools: print("[CAM] Auto orbit: ", "ON" if orbit_auto else "OFF")


func handle_input(event: InputEvent) -> void :
	if editor_active:
		_handle_editor_input(event)
		return
	if orbit_mode == 0:
		return



	if event is InputEventMouse and is_mouse_over_editor_ui_cb.is_valid():
		if is_mouse_over_editor_ui_cb.call(event.position):


			if _orbit_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_orbit_dragging = false
			return

	var handled: = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = event.pressed
			handled = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_pitch = clampf(orbit_pitch - 0.08, 0.05, 1.3)
			handled = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_pitch = clampf(orbit_pitch + 0.08, 0.05, 1.3)
			handled = true
	elif event is InputEventMouseMotion and _orbit_dragging:
		orbit_angle -= event.relative.x * ORBIT_DRAG_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch - event.relative.y * ORBIT_DRAG_SENSITIVITY, 0.05, 1.3)
		handled = true

	if handled:
		get_viewport().set_input_as_handled()



# After a doubles change of ends the human plays from the far end. Turn the
# whole rig half a turn about the court centre so the view stays behind them:
# the court is symmetric, so this reads as the court flipping, not the camera.
func _apply_end_flip() -> void:
	var flipped: bool = not editor_active and _game_root != null and _game_root.has_method("view_flipped") and _game_root.view_flipped()
	var wanted: Basis = Basis(Vector3.UP, PI) if flipped else Basis.IDENTITY
	if not transform.basis.is_equal_approx(wanted):
		transform.basis = wanted
		# The half turn is a hard cut: cover it with a short black fade.
		if _banner != null and cinematic_enabled and not editor_active: _banner.cut_flash(0.6)

func update(delta: float) -> void :
	_apply_end_flip()
	# Visual-only hit-stop: hold the framing (and shake) still for ~50 ms on a hard hit.
	if not editor_active and not _between_point_camera.active and TimeScale.visual_hitstop_active(): return
	if _game_root != null and _game_root.practice_launcher and _game_root.practice_launcher.is_wall() and gameplay_camera.mode == GameplayCamera.CENTER:
		gameplay_camera.suspend()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.near = 0.05
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.frustum_offset = Vector2.ZERO
		_game_root.practice_launcher.wall_practice.update_camera(camera)
		return
	if _between_point_camera.active:
		if _cinematic_blocked(): end_between_point_cinematic()
		else: _between_point_camera.advance(delta)
		return
	if editor_active:
		_update_editor_camera()
	else:
		_update_follow(delta)
	if _shake != null and not editor_active and (orbit_mode != 0 or gameplay_camera.active_kind == "center"):
		var framing_offset: float = camera.v_offset if orbit_mode == 0 and _portrait_camera else 0.0
		_shake.update(delta)
		camera.v_offset += framing_offset

	if camera != null and (editor_active or orbit_mode != 0):
		var target_fov: float = 72.0 if editor_active or orbit_mode == 3 else PORTRAIT_HORIZONTAL_FOV if _portrait_camera and orbit_mode == 0 else _base_fov
		camera.fov = lerpf(camera.fov, target_fov, 5.0 * delta)

func _handle_editor_input(event: InputEvent) -> void :
	if event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_editor_orbit_dragging = false
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				_editor_pan_dragging = false
			return
		if is_mouse_over_editor_ui_cb.is_valid() and is_mouse_over_editor_ui_cb.call(event.position):
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_editor_orbit_dragging = true
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE:
				_editor_pan_dragging = true
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				editor_distance = clampf(editor_distance * 0.9, EDITOR_MIN_DISTANCE, EDITOR_MAX_DISTANCE)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				editor_distance = clampf(editor_distance * 1.1, EDITOR_MIN_DISTANCE, EDITOR_MAX_DISTANCE)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if is_mouse_over_editor_ui_cb.is_valid() and is_mouse_over_editor_ui_cb.call(event.position):
			return
		if _editor_orbit_dragging:
			orbit_angle -= event.relative.x * ORBIT_DRAG_SENSITIVITY
			orbit_pitch = clampf(orbit_pitch - event.relative.y * ORBIT_DRAG_SENSITIVITY, -1.35, 1.5)
			get_viewport().set_input_as_handled()
		elif _editor_pan_dragging and camera:
			var scale: float = editor_distance * 0.0015
			editor_target += camera.global_transform.basis.x * - event.relative.x * scale
			editor_target += camera.global_transform.basis.y * event.relative.y * scale
			get_viewport().set_input_as_handled()

func _update_editor_camera() -> void :
	if camera == null:
		return
	var horizontal: float = editor_distance * cos(orbit_pitch)
	camera.global_position = editor_target + Vector3(
		cos(orbit_angle) * horizontal, 
		editor_distance * sin(orbit_pitch), 
		sin(orbit_angle) * horizontal
	)
	camera.look_at(editor_target, Vector3.UP)
	camera.v_offset = 0.0
	var viewport_size: = get_viewport().get_visible_rect().size
	var dock_fraction: float = minf(0.48, 610.0 / maxf(viewport_size.x, 1.0))
	camera.h_offset = editor_distance * tan(deg_to_rad(camera.fov) * 0.5) * viewport_size.x / maxf(viewport_size.y, 1.0) * dock_fraction

func _is_practice() -> bool:
	if _is_practice_cb.is_valid():
		return bool(_is_practice_cb.call())
	return false

func _update_follow(delta: float) -> void :
	if camera == null or _player_left == null:
		return

	if orbit_mode != 0:
		gameplay_camera.suspend()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_update_third_person(delta)
		return

	gameplay_camera.update(self, delta)

func _update_centered(delta: float) -> void:
	var previous_x: float = camera.position.x
	camera.near = 0.05
	var viewport_size: = get_viewport().get_visible_rect().size
	if MobileLayout.is_portrait(viewport_size):
		_update_portrait_camera(viewport_size)
		if portrait_adaptive_framing: _apply_portrait_action_framing(delta)
		_apply_slowmo_focus(delta)
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = _base_fov
	camera.position = _default_pos
	camera.rotation_degrees = _default_rot
	camera.v_offset = 0.0
	camera.h_offset = 0.0
	if _portrait_camera:
		_portrait_camera = false
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.position = _default_pos
		camera.rotation_degrees = _default_rot
		camera.v_offset = 0.0
		camera.h_offset = 0.0


	var player_x: float = to_local(_drawn(_player_left)).x
	var camera_x: float = previous_x if gameplay_camera.active_kind == "center" and gameplay_camera.transition_done() else 0.0
	var target_x: float = 0.0
	var player_offset: float = player_x - camera_x
	if player_offset > EDGE_THRESHOLD:
		target_x = player_x - EDGE_THRESHOLD
	elif player_offset < - EDGE_THRESHOLD:
		target_x = player_x + EDGE_THRESHOLD
	target_x = clamp(target_x, - MAX_CAMERA_OFFSET, MAX_CAMERA_OFFSET)
	camera.position.x = lerp(camera_x, target_x, 4.0 * delta)
	_apply_slowmo_focus(delta)

# The only camera move during play besides shake: while time is slowed, push in
# toward the ball (it stays where it is on screen and grows) and widen the lens
# a little. Eased in real time, so it is as smooth at 0.1x as at 1x.
func _apply_slowmo_focus(delta: float) -> void:
	_apply_cinematic_push(delta)
	var time_scale: Node = get_node_or_null("/root/TimeScale")
	var slow: float = time_scale.slowmo_scale() if time_scale != null and time_scale.has_method("slowmo_scale") else 1.0
	var wanted: float = clampf((1.0 - slow) / (1.0 - SLOWMO_FULL_SCALE), 0.0, 1.0)
	var real_delta: float = clampf(delta / maxf(Engine.time_scale, 0.001), 0.0, 0.1)
	var subject: Node3D = _ball if is_instance_valid(_ball) and _ball.is_in_play else _player_left
	if not is_instance_valid(subject): return
	_apply_play_push(subject, real_delta)
	var point: Vector3 = _drawn(subject)
	point = Vector3(clampf(point.x, -3.5, 3.5), clampf(point.y, 0.4, 2.2), clampf(point.z, -7.0, 7.0))
	if _slowmo_focus <= 0.001: _slowmo_point = point
	else: _slowmo_point = _slowmo_point.lerp(point, 1.0 - exp(-5.0 * real_delta))
	_slowmo_focus = lerpf(_slowmo_focus, wanted, 1.0 - exp(-(5.0 if wanted > _slowmo_focus else 3.0) * real_delta))
	if _slowmo_focus <= 0.001:
		_slowmo_focus = 0.0
		return
	var amount: float = smoothstep(0.0, 1.0, _slowmo_focus)
	camera.global_position += (_slowmo_point - camera.global_position) * SLOWMO_PUSH * amount
	camera.fov += SLOWMO_FOV_ADD * amount

func _input(event: InputEvent) -> void:
	# Any press skips the current push-in (and the banner, in the banner itself).
	if _cine_amount > 0.001 and not _cine_skipped:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_cine_skipped = true

func _cine_wanted(real_delta: float) -> float:
	var g: Node = _game_root
	if g == null or not cinematic_enabled or _is_practice(): return 0.0
	var state: int = int(g.get("game_state"))
	if state != _cine_state:
		_cine_state = state
		_cine_state_time = 0.0
		_cine_skipped = false
	else:
		_cine_state_time += real_delta
	_update_cinematic_banners(g, state)
	if _cine_skipped: return 0.0
	if bool(g.get("match_over")): return CINE_WIN
	if state == 3: # POINT_SCORED: hold on the point for ~1 s
		return CINE_POINT_WON if _cine_state_time < CINE_POINT_HOLD else 0.0
	if state == 0: # WAITING: serve intro
		return CINE_MATCH_POINT if _is_match_point(g) else CINE_SERVE
	return 0.0

func _is_match_point(g: Node) -> bool:
	if g.get("doubles_mode") != true: return false
	var ds = g.get("doubles_state")
	if ds == null or ds.match_over: return false
	var mine: int = int(ds.scores[ds.serving_team])
	var theirs: int = int(ds.scores[1 - ds.serving_team])
	return mine >= int(ds.target_score) - 1 and mine - theirs >= 1

func _update_cinematic_banners(g: Node, state: int) -> void:
	if _banner == null or g.get("doubles_mode") != true: return
	var ds = g.get("doubles_state")
	if ds == null: return
	var pending: bool = bool(ds.end_change_pending)
	# Big "CHANGE COURT" banner for 2 s with the score, as the players set off.
	var between = g.get("between_point_controller")
	var walking: bool = pending and between != null and str(between.phase) == "END_WALK"
	if walking and not _cine_end_pending and not bool(g.get("match_over")):
		var hud = g.get("hud")
		var left_name: String = hud.team_name(0) if hud != null and hud.has_method("team_name") else "Blue"
		var right_name: String = hud.team_name(1) if hud != null and hud.has_method("team_name") else "Red"
		_banner.show_banner("CHANGE COURT", "%s %d  –  %d %s" % [left_name, int(ds.scores[0]), int(ds.scores[1]), right_name], 2.0, 0.35, 84, 34)
	_cine_end_pending = walking
	if state == 0 and _is_match_point(g):
		if not _cine_match_point_shown and not pending:
			_cine_match_point_shown = true
			_banner.show_banner("MATCH POINT", "", 1.6, 0.0)
	elif state != 0:
		_cine_match_point_shown = false

func _apply_cinematic_push(delta: float) -> void:
	var real_delta: float = clampf(delta / maxf(Engine.time_scale, 0.001), 0.0, 0.1)
	var wanted: float = _cine_wanted(real_delta)
	_cine_amount = lerpf(_cine_amount, wanted, 1.0 - exp(-(2.4 if wanted > _cine_amount else 3.5) * real_delta))
	if _cine_amount <= 0.001:
		_cine_amount = 0.0
		_cine_point = Vector3.ZERO
		return
	var subject: Node3D = null
	if _cine_state == 0 and _game_root != null and _game_root.has_method("get_server_actor"):
		subject = _game_root.get_server_actor()
	if not is_instance_valid(subject): subject = _ball if is_instance_valid(_ball) else _player_left
	if not is_instance_valid(subject): return
	var point: Vector3 = _drawn(subject)
	point = Vector3(clampf(point.x, -3.5, 3.5), clampf(point.y, 0.4, 1.4), clampf(point.z, -7.0, 7.0))
	_cine_point = point if _cine_point == Vector3.ZERO else _cine_point.lerp(point, 1.0 - exp(-4.0 * real_delta))
	var amount: float = smoothstep(0.0, 1.0, _cine_amount / CINE_WIN) * CINE_WIN
	camera.global_position += (_cine_point - camera.global_position) * amount
	camera.fov += CINE_FOV_ADD * clampf(amount / CINE_WIN, 0.0, 1.0)

func _update_third_person(delta: float) -> void :
	var target_player: CharacterBody3D = _player_left if (orbit_mode == 1 or orbit_mode == 3) else _player_right
	if target_player == null:
		return
	var forward_sign: float = 1.0 if (orbit_mode == 1 or orbit_mode == 3) else -1.0

	if _orbit_dragging:
		_orbit_idle_timer = 0.0
	else:
		_orbit_idle_timer += delta
	if orbit_auto and not _orbit_dragging and _orbit_idle_timer > 5.0:
		orbit_angle += ORBIT_SPEED * delta

	var player_pos: Vector3 = _drawn(target_player)
	var cam_pos: Vector3
	var look_target: Vector3

	if orbit_mode == 3:
		var orbit_radius: float = 4.6
		var h_dist: float = orbit_radius * cos(orbit_pitch)
		var v_height: float = orbit_radius * sin(orbit_pitch) + 0.1
		cam_pos = Vector3(
			player_pos.x + cos(orbit_angle) * h_dist, 
			player_pos.y + v_height, 
			player_pos.z + sin(orbit_angle) * h_dist)



		var base_look: Vector3 = player_pos + Vector3(0, -1.45, 0)
		if editor_focus_point != Vector3.INF:
			var grounded_focus: = Vector3(editor_focus_point.x, base_look.y, editor_focus_point.z)
			look_target = base_look.lerp(grounded_focus, 0.12)
		else:
			look_target = base_look
	elif orbit_auto:
		var orbit_radius: float = 4.0
		var h_dist: float = orbit_radius * cos(orbit_pitch)
		var v_height: float = orbit_radius * sin(orbit_pitch) + 0.4
		cam_pos = Vector3(
			player_pos.x + cos(orbit_angle) * h_dist, 
			player_pos.y + v_height, 
			player_pos.z + sin(orbit_angle) * h_dist)
		look_target = player_pos + Vector3(0, 0.1, 0)
	else:
		var desired_side: float = 0.3
		if _ball != null and _ball.is_in_play:
			var ball_x: float = _drawn(_ball).x - player_pos.x
			desired_side = clampf(ball_x * 0.6, -1.2, 1.2)
		elif target_player.posture:
			var posture: int = target_player.posture.paddle_posture
			if posture in target_player.BACKHAND_POSTURES:
				desired_side = -0.8
			elif posture in target_player.FOREHAND_POSTURES:
				desired_side = 0.8
		_cam_side_offset = lerpf(_cam_side_offset, desired_side, 3.0 * delta)

		var ball_height_boost: float = 0.0
		if _ball != null and _ball.is_in_play and not _is_practice():
			ball_height_boost = clampf(_drawn(_ball).y - 1.5, 0.0, 0.8) * 0.3
		var cam_height: float = ORBIT_HEIGHT + ball_height_boost

		cam_pos = player_pos + Vector3(
			_cam_side_offset, 
			cam_height, 
			forward_sign * ORBIT_DISTANCE)

		var desired_look: Vector3
		if _ball != null and _ball.is_in_play and not _is_practice():
			var ball_pos: Vector3 = _drawn(_ball)
			var ahead_point: Vector3 = player_pos + Vector3(0.0, 0.5, - forward_sign * 5.0)
			desired_look = ahead_point.lerp(ball_pos, 0.25)
			desired_look.x = clampf(desired_look.x, player_pos.x - 2.5, player_pos.x + 2.5)
		else:
			desired_look = player_pos + Vector3(0.0, 0.5, - forward_sign * 5.0)
		_cam_look_target = _cam_look_target.lerp(desired_look, 4.0 * delta)
		look_target = _cam_look_target

	camera.global_position = cam_pos
	camera.look_at(look_target, Vector3.UP)
	camera.v_offset = EDITOR_CAMERA_V_OFFSET if orbit_mode == 3 else 0.0


func _apply_play_push(subject: Node3D, real_delta: float) -> void:
	if not MobileLayout.is_portrait(get_viewport().get_visible_rect().size): return
	var p: Vector3 = _drawn(subject)
	# Pivot near the near baseline, so the zoom grows the court upward into the
	# open space under the scoreboard and the near player stays above the
	# controls; leans a little toward the action.
	var aim: Vector3 = Vector3(clampf(p.x * 0.4, -1.5, 1.5), 0.6, clampf(4.6 + p.z * 0.15, 3.4, 5.6))
	if _play_point == Vector3.INF: _play_point = aim
	else: _play_point = _play_point.lerp(aim, 1.0 - exp(-PLAY_FOLLOW_RATE * real_delta))
	camera.global_position += (_play_point - camera.global_position) * PLAY_PUSH

func _update_portrait_camera(viewport_size: Vector2) -> void :


	_portrait_camera = true
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = PORTRAIT_HORIZONTAL_FOV
	var safe: = MobileLayout.safe_rect(get_viewport())
	if viewport_size != _portrait_fit_view or safe != _portrait_fit_safe or not is_equal_approx(portrait_elevation_degrees, _portrait_fit_elevation) or _portrait_fit_anchor != Vector3(portrait_anchor_z, portrait_anchor_height, portrait_max_baseline_view_angle):
		var playable: = MobileLayout.court_rect(viewport_size, safe)



		var band_aspect: = playable.size.y / maxf(playable.size.x, 1.0)
		var responsive_elevation: = lerpf(40.0, 70.0, clampf((band_aspect - 0.85) / 0.45, 0.0, 1.0))
		_portrait_frame_elevation = minf(portrait_elevation_degrees, responsive_elevation)
		var low: = 10.0
		var high: = 55.0

		while not playable.encloses(_fit_portrait_at_distance(high, viewport_size, playable)) and high < 2048.0:
			high *= 2.0
		for _i in range(18):
			var distance: = (low + high) * 0.5
			var projected: = _fit_portrait_at_distance(distance, viewport_size, playable)
			if playable.encloses(projected): high = distance
			else: low = distance
		_fit_portrait_at_distance(high * 1.012, viewport_size, playable)
		_portrait_fit_position = camera.position
		_portrait_fit_rotation = camera.rotation
		_portrait_fit_offset = camera.v_offset
		_portrait_fit_view = viewport_size
		_portrait_fit_safe = safe
		_portrait_fit_elevation = portrait_elevation_degrees
		_portrait_fit_anchor = Vector3(portrait_anchor_z, portrait_anchor_height, portrait_max_baseline_view_angle)
	camera.position = _portrait_fit_position
	camera.rotation = _portrait_fit_rotation
	camera.v_offset = _portrait_fit_offset
	camera.h_offset = 0.0

func _fit_portrait_at_distance(distance: float, viewport_size: Vector2, playable: Rect2) -> Rect2:
	var target: = Vector3(0, 0.6, 0)
	var elevation: = deg_to_rad(_portrait_frame_elevation)
	camera.position = Vector3(0, portrait_anchor_height, portrait_anchor_z) + Vector3(0, sin(elevation), cos(elevation)) * distance
	camera.look_at(target, Vector3.UP)
	camera.v_offset = 0.0
	camera.h_offset = 0.0
	var focal_pixels: = viewport_size.x / (2.0 * tan(deg_to_rad(PORTRAIT_HORIZONTAL_FOV) * 0.5))
	var projected: = Rect2()
	for _i in range(4):
		projected = _portrait_projected_bounds()
		var error: = playable.get_center().y - projected.get_center().y
		camera.v_offset += error * camera.position.distance_to(target) / focal_pixels
		if portrait_max_baseline_view_angle > 0:


			var slope: = tan(deg_to_rad(portrait_max_baseline_view_angle))
			var up: = camera.basis.y
			var maximum_offset: float = (slope * (camera.position.z - 6.8) - (camera.position.y - 1.0)) / (up.y - slope * up.z)
			camera.v_offset = minf(camera.v_offset, maximum_offset)
	return _portrait_projected_bounds()

func _portrait_projected_bounds() -> Rect2:
	var minimum: = Vector2(INF, INF)
	var maximum: = Vector2( - INF, - INF)
	for x in [-3.4, 3.4]:
		for z in [-7.35, 7.35]:
			for y in [0.0, 2.15]:
				var point: = camera.unproject_position(Vector3(x, y, z))
				minimum = minimum.min(point)
				maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func begin_between_point_cinematic(focus_provider: Callable = Callable(), duration: float = 4.0) -> bool:
	if not between_point_cinematic_enabled: return false
	if camera == null or _between_point_camera.active or _cinematic_blocked(): return false
	if _game_root and int(_game_root.get("game_state")) != 3: return false
	return _between_point_camera.begin(camera, focus_provider, duration)

func end_between_point_cinematic() -> void :
	if _between_point_camera != null: _between_point_camera.end()

func _cinematic_blocked() -> bool:
	if gameplay_camera.mode != GameplayCamera.CENTER: return true
	if get_tree() == null or get_tree().paused or editor_active or _is_practice(): return true
	if _ball == null or not is_instance_valid(_ball) or _ball.is_in_play: return true
	if _game_root:
		if int(_game_root.get("game_state")) != 3: return true
		if bool(_game_root.get("match_over")): return true
		if _game_root.has_method("_tool_state_active") and _game_root._tool_state_active(): return true
	return false

func _notification(what: int) -> void :
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		end_between_point_cinematic()

func _exit_tree() -> void :
	gameplay_camera.restore_avatar()
	end_between_point_cinematic()

# Tighten the overview around actual play instead of keeping empty near apron
# and both unused near corners. Keep the whole opposite baseline and net.
# Pull out immediately as play widens; ease inward to avoid a breathing camera.
func _apply_portrait_action_framing(delta: float) -> void:
	var points: Array[Vector3] = _portrait_action_points()
	if points.is_empty(): return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var band: Rect2 = MobileLayout.court_rect(size, MobileLayout.safe_rect(get_viewport())).grow(-10.0 * MobileLayout.scale_for(size))
	if _game_root and _game_root.get("mobile_controls"):
		var controls: Node = _game_root.mobile_controls
		if controls.has_method("camera_occlusion_regions"):
			for region in controls.camera_occlusion_regions():
				band.end.y = minf(band.end.y, maxf(band.position.y + 80.0, region.position.y - 8.0 * MobileLayout.scale_for(size)))
	var full: Transform3D = camera.get_camera_transform()
	var forward: Vector3 = -full.basis.z
	var focus: Vector3 = full.origin + forward * ((0.8 - full.origin.y) / minf(forward.y, -0.01))
	camera.v_offset = 0.0; camera.h_offset = 0.0
	var low: = 0.68
	var high: = 1.0
	for i in 5:
		camera.global_transform = Transform3D(full.basis, focus + (full.origin - focus) * high)
		_center_action_bounds(points, band, focus)
		if _action_points_fit(points, band): break
		high *= 1.25
	for i in 9:
		var middle: float = (low + high) * 0.5
		camera.global_transform = Transform3D(full.basis, focus + (full.origin - focus) * middle)
		_center_action_bounds(points, band, focus)
		if _action_points_fit(points, band): high = middle
		else: low = middle
	var desired: float = high
	var wanted: float = ZOOM_STEPS[-1]
	for step in ZOOM_STEPS:
		if step >= desired - 0.005: wanted = step; break
	if wanted > _zoom_step:
		_zoom_step = wanted; _zoom_in_timer = 0.0          # out: switch now
	elif wanted < _zoom_step:
		_zoom_in_timer += maxf(delta, 0.0)
		if _zoom_in_timer >= ZOOM_IN_HOLD: _zoom_step = wanted; _zoom_in_timer = 0.0
	else: _zoom_in_timer = 0.0
	var rate: float = 14.0 if _zoom_step > _portrait_action_zoom else 4.0   # out fast, in gently
	_portrait_action_zoom = lerpf(_portrait_action_zoom, _zoom_step, 1.0 - exp(-rate * maxf(delta, 0.0)))
	camera.global_transform = Transform3D(full.basis, focus + (full.origin - focus) * _portrait_action_zoom)
	_center_action_bounds(points, band, focus)

func _center_action_bounds(points: Array[Vector3], band: Rect2, focus: Vector3) -> void:
	camera.v_offset = 0.0
	var focal_pixels: float = get_viewport().get_visible_rect().size.x / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	for i in 3:
		var top: = INF
		var bottom: = -INF
		for point in points:
			var y: float = camera.unproject_position(point).y
			top = minf(top, y); bottom = maxf(bottom, y)
		var error: float = band.get_center().y - (top + bottom) * 0.5
		camera.v_offset += error * camera.global_position.distance_to(focus) / focal_pixels

func _portrait_action_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for x in [-3.15, 3.15]:
		points.append(Vector3(x, 0.1, -6.9))
		points.append(Vector3(x, 0.1, 0))
		points.append(Vector3(x, 0.95, 0))
	var roster: Array = _game_root.get_players() if _game_root != null and _game_root.has_method("get_players") else [_player_left, _player_right]
	for player in roster:
		if not is_instance_valid(player): continue
		var head: Node3D = player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh")
		var top: float = maxf(_drawn(player).y + 0.55, _drawn(head).y + 0.2 if head else 1.65)
		for x in [-0.58, 0.58]:
			points.append(Vector3(_drawn(player).x + x, 0.08, _drawn(player).z + 0.25))
			points.append(Vector3(_drawn(player).x + x, top, _drawn(player).z))
	if is_instance_valid(_ball):
		for offset in [Vector3(-0.15, -0.15, 0), Vector3(0.15, 0.15, 0)]: points.append(_drawn(_ball) + offset)
	return points

func _action_points_fit(points: Array[Vector3], band: Rect2) -> bool:
	for point in points:
		if camera.is_position_behind(point) or not band.has_point(camera.unproject_position(point)): return false
	if _game_root and _game_root.get("mobile_controls") and is_instance_valid(_ball):
		var controls: Node = _game_root.mobile_controls
		if controls.has_method("camera_occlusion_regions"):
			var pixel: Vector2 = camera.unproject_position(_drawn(_ball))
			for region in controls.camera_occlusion_regions():
				if region.has_point(pixel): return false
	return true
