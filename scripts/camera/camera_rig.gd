extends Node3D
class_name CameraRig
## Owns the main Camera3D and every camera behavior:
## - default fixed overhead follow (edge-threshold pan on X)
## - 3rd person cycle (P key) — behind Blue, behind Red, default
## - orbit drag + auto-orbit (O key + mouse)
## - FOV control (via set_fov, e.g. from Settings)
## - trauma-based shake (via CameraShake child)
##
## game.gd just calls setup() once, then forwards input events and calls update().
## All shake triggers go through add_shake(amount).

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

# External refs (set via setup)
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _ball: RigidBody3D
var _is_practice_cb: Callable  # optional callable returning bool

# State
var orbit_mode: int = 0  # 0=default, 1=behind blue, 2=behind red
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

func _ready() -> void:
	name = "CameraRig"

## Creates the Camera3D and the CameraShake child. Call once from game.gd._ready.
func setup(
		parent: Node,
		player_left: CharacterBody3D,
		player_right: CharacterBody3D,
		ball: RigidBody3D,
		is_practice_cb: Callable = Callable()) -> Camera3D:
	_player_left = player_left
	_player_right = player_right
	_ball = ball
	_is_practice_cb = is_practice_cb

	if get_parent() == null:
		parent.add_child(self)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.position = Vector3(0, 10.5, 11.0)
	camera.rotation_degrees = Vector3(-52, 0, 0)
	camera.fov = 60.0
	add_child(camera)

	_default_pos = camera.position
	_default_rot = camera.rotation_degrees

	_shake = CameraShakeScript.new()
	_shake.name = "Shake"
	add_child(_shake)
	_shake.setup(camera)

	return camera

## Add shake trauma (0..1). Scaled by Settings "video.shake" inside CameraShake.
func add_shake(amount: float) -> void:
	if _shake != null:
		_shake.add_trauma(amount)

func set_fov(new_fov: float) -> void:
	_base_fov = clampf(new_fov, 30.0, 110.0)
	if camera != null and orbit_mode != 3:
		camera.fov = _base_fov

## Forward P/O key presses from game.gd._physics_process here.
func cycle_third_person() -> void:
	orbit_mode = (orbit_mode + 1) % 3
	_orbit_dragging = false
	if orbit_mode == 0:
		if camera != null:
			camera.position = _default_pos
			camera.rotation_degrees = _default_rot
		if _shake != null:
			_shake.reset()
		print("[CAM] Default camera")
	elif orbit_mode == 1:
		print("[CAM] 3rd person BLUE — looking at red service line")
	elif orbit_mode == 2:
		print("[CAM] 3rd person RED — looking at blue service line")

func toggle_auto_orbit() -> void:
	if orbit_mode == 0:
		return
	orbit_auto = not orbit_auto
	print("[CAM] Auto orbit: ", "ON" if orbit_auto else "OFF")

## Forward _unhandled_input from game.gd here.
func handle_input(event: InputEvent) -> void:
	if orbit_mode == 0:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_pitch = clampf(orbit_pitch - 0.08, 0.05, 1.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_pitch = clampf(orbit_pitch + 0.08, 0.05, 1.3)
	elif event is InputEventMouseMotion and _orbit_dragging:
		orbit_angle -= event.relative.x * ORBIT_DRAG_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch - event.relative.y * ORBIT_DRAG_SENSITIVITY, 0.05, 1.3)

func update(delta: float) -> void:
	_update_follow(delta)
	if _shake != null:
		_shake.update(delta)
	
	if camera != null:
		var target_fov: float = 72.0 if orbit_mode == 3 else _base_fov
		camera.fov = lerpf(camera.fov, target_fov, 5.0 * delta)

func _is_practice() -> bool:
	if _is_practice_cb.is_valid():
		return bool(_is_practice_cb.call())
	return false

func _update_follow(delta: float) -> void:
	if camera == null or _player_left == null:
		return

	if orbit_mode != 0:
		_update_third_person(delta)
		return

	# Default camera — edge-threshold X pan
	var player_x: float = _player_left.global_position.x
	var camera_x: float = camera.position.x
	var target_x: float = 0.0
	var player_offset: float = player_x - camera_x
	if player_offset > EDGE_THRESHOLD:
		target_x = player_x - EDGE_THRESHOLD
	elif player_offset < -EDGE_THRESHOLD:
		target_x = player_x + EDGE_THRESHOLD
	target_x = clamp(target_x, -MAX_CAMERA_OFFSET, MAX_CAMERA_OFFSET)
	camera.position.x = lerp(camera_x, target_x, 4.0 * delta)

func _update_third_person(delta: float) -> void:
	var target_player: CharacterBody3D = _player_left if (orbit_mode == 1 or orbit_mode == 3) else _player_right
	if target_player == null:
		return
	var forward_sign: float = 1.0 if (orbit_mode == 1 or orbit_mode == 3) else -1.0

	if _orbit_dragging:
		_orbit_idle_timer = 0.0
	else:
		_orbit_idle_timer += delta
	if orbit_auto and not _orbit_dragging and _orbit_idle_timer > 5.0 and orbit_mode != 3:
		orbit_angle += ORBIT_SPEED * delta

	var player_pos: Vector3 = target_player.global_position
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
		
		# Keep the editor camera aimed at the ground area below the player so the
		# body stays visually centered in the open space above the bottom panel.
		var base_look: Vector3 = player_pos + Vector3(0, -1.45, 0)
		if editor_focus_point != Vector3.INF:
			var grounded_focus := Vector3(editor_focus_point.x, base_look.y, editor_focus_point.z)
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
			var ball_x: float = _ball.global_position.x - player_pos.x
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
			ball_height_boost = clampf(_ball.global_position.y - 1.5, 0.0, 0.8) * 0.3
		var cam_height: float = ORBIT_HEIGHT + ball_height_boost

		cam_pos = player_pos + Vector3(
			_cam_side_offset,
			cam_height,
			forward_sign * ORBIT_DISTANCE)

		var desired_look: Vector3
		if _ball != null and _ball.is_in_play and not _is_practice():
			var ball_pos: Vector3 = _ball.global_position
			var ahead_point: Vector3 = player_pos + Vector3(0.0, 0.5, -forward_sign * 5.0)
			desired_look = ahead_point.lerp(ball_pos, 0.25)
			desired_look.x = clampf(desired_look.x, player_pos.x - 2.5, player_pos.x + 2.5)
		else:
			desired_look = player_pos + Vector3(0.0, 0.5, -forward_sign * 5.0)
		_cam_look_target = _cam_look_target.lerp(desired_look, 4.0 * delta)
		look_target = _cam_look_target

	camera.global_position = cam_pos
	camera.look_at(look_target, Vector3.UP)
	camera.v_offset = EDITOR_CAMERA_V_OFFSET if orbit_mode == 3 else 0.0
