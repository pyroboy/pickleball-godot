extends RefCounted

# Gameplay viewpoints are separate from the pose editor's orbit controls.
const CENTER: = 0
const THIRD_PERSON: = 1
const POV: = 2
const TRANSITION_SECONDS: = 0.65
# Doubles serve view: a longer, softer move in and out (smootherstep), a
# damped follow so the server's small shuffles don't jolt the frame, and a
# slow push-in while the serve charges.
const DOUBLES_SERVE_TRANSITION: = 1.05
const DOUBLES_FOLLOW_RATE: = 6.0
var _transition_seconds: float = TRANSITION_SECONDS
var _serve_cam_pos: = Vector3.INF
var _serve_cam_look: = Vector3.INF
var _serve_push: float = 0.0
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var _controls: Node
var _ball_aim: float = 0.0      # 0 = normal framing, 1 = aimed at the ball
var _ball_aim_usec: int = 0

# The camera updates every rendered frame (camera_rig._process), so it follows
# what is drawn: interpolated transforms, not the last 30 Hz physics tick.
static func _d(node: Node3D) -> Vector3:
	return node.get_global_transform_interpolated().origin
var mode: = CENTER
var active_kind: = "center"
var _previous_kind: = ""
var _transition_from: = Transform3D.IDENTITY
var _transition_fov: = 60.0
var _transition_offset: = 0.0
var _transition_elapsed: = TRANSITION_SECONDS
var _last_direction: = Vector3.FORWARD
var _hidden_meshes: Array[Dictionary] = []

func set_mode(value: int) -> void:
	mode = clampi(value, CENTER, POV)
	_previous_kind = ""
	restore_avatar()

func suspend() -> void:
	restore_avatar()
	_previous_kind = ""

func restore_avatar() -> void:
	for entry in _hidden_meshes:
		if is_instance_valid(entry.mesh):
			entry.mesh.cast_shadow = entry.shadow
			entry.mesh.layers = entry.layers
	_hidden_meshes.clear()

func _hide_avatar(player: Node3D) -> void:
	if not _hidden_meshes.is_empty(): return
	# Keep pose data, physics and cast shadows. Hide the local avatar surfaces
	# from inside the head, where body/arms would otherwise cover a low ball.
	var body: Node = player.get_node_or_null("BodyPivot")
	if body == null: return
	for node in body.find_children("*", "GeometryInstance3D", true, false):
		_hidden_meshes.append({"mesh": node, "shadow": node.cast_shadow, "layers": node.layers})
		if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			node.layers = 0
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

func update(rig, delta: float) -> bool:
	var game: Node = rig._game_root
	var camera: Camera3D = rig.camera
	if game == null or camera == null: return false
	_controls = game.get("mobile_controls")
	# The controlled player is Blue. Receiving must retain Blue's centered
	# viewpoint rather than following the opponent's serving perspective.
	var serving: bool = not rig._is_practice() and not game.match_over and game.human_may_serve() and int(game.game_state) in [0, 1]
	var kind: String = "pov" if mode == POV else "third" if mode == THIRD_PERSON else ("serve2" if game.doubles_mode else "serve0") if serving else "center"
	var previous_transform: Transform3D = camera.global_transform
	var previous_fov: float = camera.fov
	var previous_aspect: int = camera.keep_aspect
	var previous_offset: float = camera.v_offset
	var player: Node3D = rig._player_left
	if kind == "serve2":
		var human: Node3D = game.get_human_actor()
		if human != null: player = human
	if kind == "pov":
		active_kind = kind
		_previous_kind = kind
		_transition_elapsed = TRANSITION_SECONDS
		_update_pov(camera, player, rig._ball, delta)
		return true
	restore_avatar()
	if kind == "center":
		rig._update_centered(delta)
	elif kind == "serve2":
		_update_doubles_serve(camera, player, game, delta, _previous_kind != kind)
	else:
		_update_third(camera, player, rig._ball, -1.0 if player.court_side == 1 else 1.0)
	var desired: Transform3D = camera.global_transform
	var desired_fov: float = camera.fov
	var desired_offset: float = camera.v_offset
	if kind != _previous_kind:
		_transition_from = previous_transform
		_transition_fov = convert_fov(previous_fov, previous_aspect, camera.keep_aspect, camera.get_viewport().get_visible_rect().size)
		_transition_offset = previous_offset
		# Into and out of the doubles serve view the move is longer and eased
		# at both ends; every other switch keeps the original timing.
		_transition_seconds = DOUBLES_SERVE_TRANSITION if kind == "serve2" or _previous_kind == "serve2" else TRANSITION_SECONDS
		_transition_elapsed = 0.0 if not _previous_kind.is_empty() else _transition_seconds
		_previous_kind = kind
	active_kind = kind
	_transition_elapsed = minf(_transition_seconds, _transition_elapsed + maxf(delta, 0.0))
	var blend: float = _ease_transition(_transition_elapsed / _transition_seconds, kind == "serve2" or _transition_seconds > TRANSITION_SECONDS)
	camera.global_transform = _transition_from.interpolate_with(desired, blend) if blend < 1.0 else desired
	camera.fov = lerpf(_transition_fov, desired_fov, blend)
	camera.v_offset = lerpf(_transition_offset, desired_offset, blend)
	# The centre view is a fixed framing: it never swings round to chase the
	# ball. The behind-the-player view still keeps the ball in frame.
	if kind != "center": _keep_ball_visible(camera, rig._ball)
	return true

func _update_third(camera: Camera3D, player: Node3D, ball: Node3D, side: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.04
	var portrait: bool = Layout.is_portrait(camera.get_viewport().get_visible_rect().size)
	camera.fov = 52.0 if portrait else 64.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var body: Vector3 = _d(player) + Vector3(0, -0.2, 0)
	var position: Vector3 = _d(player) + Vector3((0.45 if portrait else 0.65) * side, 2.8 if portrait else 2.0, 3.5 * side)
	# Stay in front of the far boards and inside the side boards, including a
	# Red baseline serve. This is camera placement, not drawing through scenery.
	position.z = clampf(position.z, -9.12, 9.12)
	position.x = clampf(position.x, -5.05, 5.05)
	camera.global_position = position
	var target: Vector3 = body + Vector3(0, 0.0, -3.0 * side)
	if is_instance_valid(ball): target = body.lerp(_d(ball), 0.55)
	# Lift the aim slightly to lower the scene on screen, while the higher
	# shoulder gives the court a scale/angle closer to the main rally view.
	target.y += 0.45 if portrait else 0.0
	_look_at(camera, target)
	_keep_ball_visible(camera, ball)

func transition_done() -> bool:
	return _transition_elapsed >= _transition_seconds

static func _ease_transition(t: float, soft: bool) -> float:
	t = clampf(t, 0.0, 1.0)
	if not soft: return t * t * (3.0 - 2.0 * t)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

## Doubles serve: behind the server's outside shoulder, looking down the
## diagonal at the receiver's box, so the crosscourt serve reads up the screen
## with the receiver and both partners in frame. Same height/fov family as the
## singles serve view so the two feel like one camera.
func _update_doubles_serve(camera: Camera3D, player: Node3D, game: Node, delta: float, entering: bool) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.04
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var portrait: bool = Layout.is_portrait(camera.get_viewport().get_visible_rect().size)
	var me: Vector3 = _d(player)
	var forward: float = 1.0 if me.z > 0.0 else -1.0   # toward the net from my side
	forward = -forward
	var receiver: Node3D = game.get_receiver_actor()
	var aim: Vector3 = _d(receiver) if receiver != null else Vector3(-me.x, 0.0, -me.z * 0.8)
	var diag: Vector3 = Vector3(aim.x - me.x, 0.0, aim.z - me.z)
	if diag.length_squared() < 1.0: diag = Vector3(0, 0, forward)
	diag = diag.normalized()
	# Lean the view only part-way onto the diagonal: fully diagonal hides the
	# near sideline; straight down the court loses the receiver.
	var view_dir: Vector3 = Vector3(0, 0, forward).lerp(diag, 0.7).normalized()
	var outside: Vector3 = Vector3(signf(me.x) if absf(me.x) > 0.05 else 1.0, 0, 0)
	var charging: bool = bool(game.get("serve_is_charging")) and game.game_serve != null
	var charge: float = game.game_serve.get_charge_ratio() if charging else 0.0
	var dt: float = maxf(delta, 0.0)
	_serve_push = move_toward(_serve_push, smoothstep(0.0, 1.0, charge), dt * (1.6 if charging else 2.5))
	var back: float = 3.55 - 0.55 * _serve_push
	var height: float = (3.0 if portrait else 2.1) - 0.25 * _serve_push
	var desired_pos: Vector3 = me - view_dir * back + Vector3.UP * height + outside * (0.95 if portrait else 1.1)
	desired_pos.z = clampf(desired_pos.z, -9.12, 9.12)
	desired_pos.x = clampf(desired_pos.x, -5.05, 5.05)
	# Look a little ahead of the server along the diagonal, lifted like the
	# singles view so the far court sits higher on screen.
	var desired_look: Vector3 = me + view_dir * (0.7 + 0.5 * _serve_push) + Vector3.UP * (0.5 if portrait else 0.2)
	if entering or not _serve_cam_pos.is_finite():
		_serve_cam_pos = desired_pos
		_serve_cam_look = desired_look
	else:
		var k: float = 1.0 - exp(-DOUBLES_FOLLOW_RATE * dt)
		_serve_cam_pos = _serve_cam_pos.lerp(desired_pos, k)
		_serve_cam_look = _serve_cam_look.lerp(desired_look, k)
	camera.fov = (50.0 if portrait else 62.0) - 3.0 * _serve_push
	camera.global_position = _serve_cam_pos
	_look_at(camera, _serve_cam_look)

func _update_pov(camera: Camera3D, player: Node3D, ball: Node3D, _delta: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 76.0
	camera.near = 0.025
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var head: Node3D = player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh")
	var desired_eye: Vector3 = head.get_global_transform_interpolated() * (Vector3.UP * 0.022 + player._get_forward_axis() * 0.0735) if head else _d(player) + Vector3.UP * 0.38
	# Use the current rendered eye position, without adding artificial bob or
	# borrowing the head gaze's anatomically limited/smoothed orientation.
	camera.global_position = desired_eye
	camera.frustum_offset = Vector2.ZERO
	_hide_avatar(player)
	if is_instance_valid(ball):
		var direction: Vector3 = _d(ball) - camera.global_position
		if direction.length_squared() < 0.04:
			# A coincident target has no look direction. Keep a tiny safe viewing
			# distance along the last valid ray instead of generating a NaN basis.
			camera.global_position = _d(ball) - _last_direction * 0.2
		_look_at(camera, _d(ball))

func _look_at(camera: Camera3D, target: Vector3) -> void:
	var direction: Vector3 = target - camera.global_position
	if direction.length_squared() < 1e-8: return
	_last_direction = direction.normalized()
	var up: Vector3 = Vector3.FORWARD if absf(_last_direction.dot(Vector3.UP)) > 0.995 else Vector3.UP
	camera.look_at(target, up)

func _keep_ball_visible(camera: Camera3D, ball: Node3D) -> void:
	if not is_instance_valid(ball): return
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var safe: Rect2 = Layout.safe_rect(camera.get_viewport())
	var band: Rect2 = Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-24.0)
	band = band.grow(-12.0 * Layout.scale_for(size))
	var point: Vector2 = camera.unproject_position(_d(ball))
	var covered: = false
	if is_instance_valid(_controls) and _controls.has_method("camera_occlusion_regions"):
		for region in _controls.camera_occlusion_regions():
			if region.has_point(point): covered = true; break
	var outside: bool = camera.is_position_behind(_d(ball)) or not band.has_point(point) or covered
	# Ease toward aiming at the ball when it leaves the usable band, and back when
	# it returns (was an instant snap both ways). Fast in, so the ball is never
	# lost for more than a few frames.
	var now: int = Time.get_ticks_usec()
	var dt: float = clampf((now - _ball_aim_usec) / 1000000.0, 0.0, 0.1) if _ball_aim_usec > 0 else 0.0
	_ball_aim_usec = now
	_ball_aim = move_toward(_ball_aim, 1.0 if outside else 0.0, dt * (12.0 if outside else 3.0))
	if _ball_aim <= 0.001: return
	var framed: Transform3D = camera.global_transform
	var framed_v: float = camera.v_offset
	var framed_h: float = camera.h_offset
	if camera.global_position.distance_squared_to(_d(ball)) < 0.04:
		camera.global_position = _d(ball) - _last_direction * 0.2
	_look_at(camera, _d(ball))
	var weight: float = smoothstep(0.0, 1.0, _ball_aim)
	camera.global_transform = framed.interpolate_with(camera.global_transform, weight)
	camera.v_offset = lerpf(framed_v, 0.0, weight)
	camera.h_offset = lerpf(framed_h, 0.0, weight)

static func convert_fov(value: float, from_aspect: int, to_aspect: int, size: Vector2) -> float:
	if from_aspect == to_aspect: return value
	var aspect: float = maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var tangent: float = tan(deg_to_rad(value) * 0.5)
	return rad_to_deg(2.0 * atan(tangent / aspect if from_aspect == Camera3D.KEEP_WIDTH else tangent * aspect))
