extends RefCounted

const YAW_LIMIT: = deg_to_rad(85.0)
const PITCH_UP_LIMIT: = deg_to_rad(70.0)
const PITCH_DOWN_LIMIT: = deg_to_rad(55.0)
const RESPONSE: = 16.0
# The authored head (pose head_yaw_deg / head_pitch_deg) is the base; the gaze
# only pulls it toward the ball by at most these angles.
const GAZE_YAW_OFFSET: = deg_to_rad(25.0)
const GAZE_PITCH_OFFSET: = deg_to_rad(20.0)
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

## Authored head angles plus a clamped pull toward the ball direction.
static func gaze_offset_basis(player, parent_basis: Basis, world_direction: Vector3) -> Basis:
	var def = _displayed_def(player)
	var swing: float = player._get_swing_sign()
	var authored_yaw: float = - deg_to_rad(def.head_yaw_deg) if def else 0.0
	var authored_pitch: float = deg_to_rad(def.head_pitch_deg) * swing if def else 0.0
	var weight: float = clampf(def.head_track_ball_weight, 0.0, 1.0) if def else 1.0
	var forward: Vector3 = player._get_forward_axis()
	var gaze_yaw: = authored_yaw
	var gaze_pitch: = authored_pitch
	if world_direction.length_squared() > 1e-06:
		var local: Vector3 = parent_basis.orthonormalized().inverse() * world_direction.normalized()
		var flat: = Vector3(local.x, 0, local.z)
		if flat.length_squared() > 1e-06: gaze_yaw = clampf(forward.signed_angle_to(flat.normalized(), Vector3.UP), - YAW_LIMIT, YAW_LIMIT)
		gaze_pitch = clampf(atan2(local.y, maxf(flat.length(), 1e-05)), - PITCH_DOWN_LIMIT, PITCH_UP_LIMIT) * - forward.z
	var yaw: float = authored_yaw + clampf(angle_difference(authored_yaw, gaze_yaw), - GAZE_YAW_OFFSET, GAZE_YAW_OFFSET) * weight
	var pitch: float = authored_pitch + clampf(gaze_pitch - authored_pitch, - GAZE_PITCH_OFFSET, GAZE_PITCH_OFFSET) * weight
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

static func _displayed_def(player):
	var posture = player.posture if "posture" in player else null
	# The pose last applied to the rig is the one whose head the gaze offsets.
	if posture != null and posture._presented_body_pose != null: return posture._presented_body_pose
	if posture != null and posture.transition_pose_blend != null: return posture.transition_pose_blend
	return player.get_runtime_posture_def()

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
	head.basis = gaze_offset_basis(player, torso.global_transform.basis, _direction)
	_last_player = player.global_position
	_last_ball = ball.global_position
