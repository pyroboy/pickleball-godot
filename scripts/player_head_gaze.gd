extends RefCounted

const YAW_LIMIT: = deg_to_rad(85.0)
const PITCH_UP_LIMIT: = deg_to_rad(70.0)
const PITCH_DOWN_LIMIT: = deg_to_rad(55.0)
const RESPONSE: = 16.0
var _initialized: = false
var _direction: = Vector3.FORWARD
var _last_player: = Vector3.ZERO
var _last_ball: = Vector3.ZERO
var _rest_body_angle: = 0.0

static func smooth_direction(previous: Vector3, target: Vector3, delta: float) -> Vector3:
	if target.length_squared() < 1e-06: return previous
	var desired: = target.normalized()
	if previous.length_squared() < 1e-06: return desired
	var from: = previous.normalized()
	var axis: = from.cross(desired)
	var angle: = acos(clampf(from.dot(desired), -1.0, 1.0))
	if angle < 1e-05: return desired
	if axis.length_squared() < 1e-06:
		axis = Vector3.UP if absf(from.y) < 0.95 else Vector3.RIGHT
	return from.rotated(axis.normalized(), angle * (1.0 - exp( - maxf(delta, 0.0) * RESPONSE))).normalized()

static func local_gaze_basis(parent_basis: Basis, forward: Vector3, world_direction: Vector3) -> Basis:
	if world_direction.length_squared() < 1e-06: return Basis.IDENTITY
	var local: Vector3 = parent_basis.orthonormalized().inverse() * world_direction.normalized()
	var flat: = Vector3(local.x, 0, local.z)
	var yaw: float = forward.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length_squared() > 1e-06 else 0.0
	var pitch: float = atan2(local.y, maxf(flat.length(), 1e-05))
	yaw = clampf(yaw, - YAW_LIMIT, YAW_LIMIT)
	pitch = clampf(pitch, - PITCH_DOWN_LIMIT, PITCH_UP_LIMIT)
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch * - forward.z)

static func rest_body_yaw(player, ball, delta: float = 1.0 / 60.0) -> float:
	var target: = 0.0
	if ball != null:
		var direction: Vector3 = ball.global_position - player.global_position
		direction.y = 0.0
		var forward: Vector3 = player._get_forward_axis()




		if direction.length_squared() >= 0.01:
			var yaw: float = forward.signed_angle_to(direction.normalized(), Vector3.UP)
			target = - rad_to_deg(clampf(yaw, - deg_to_rad(95.0), deg_to_rad(95.0)))
	if not "_head_gaze" in player or player._head_gaze == null: return target
	var state = player._head_gaze


	var desired: float = state._rest_body_angle + wrapf(target - state._rest_body_angle, -180.0, 180.0)
	state._rest_body_angle = move_toward(state._rest_body_angle, desired, 240.0 * maxf(delta, 0.0))
	return state._rest_body_angle

func update(player, ball, delta: float) -> void :
	if player.body_pivot == null or ball == null: return
	var torso: Node3D = player.body_pivot.get_node_or_null("TorsoMesh")
	var head: Node3D = torso.get_node_or_null("HeadMesh") if torso else null
	if head == null: return
	var target: Vector3 = ball.global_position - head.global_position
	var reset: bool = not _initialized or player.global_position.distance_to(_last_player) > 1.5 or ball.global_position.distance_to(_last_ball) > 3.0
	if target.length_squared() > 1e-06:
		_direction = target.normalized() if reset else smooth_direction(_direction, target, delta)
		_initialized = true
	elif not _initialized:
		_direction = torso.global_transform.basis * player._get_forward_axis()
		_initialized = true
	head.basis = local_gaze_basis(torso.global_transform.basis, player._get_forward_axis(), _direction)
	_last_player = player.global_position
	_last_ball = ball.global_position
