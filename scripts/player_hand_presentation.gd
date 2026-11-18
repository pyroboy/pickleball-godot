extends RefCounted


const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const HandModel = preload("res://scripts/articulated_hand.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ServeGrasp = preload("res://scripts/serve_ball_grasp_profile.gd")
const BALL_RADIUS: = 0.0375
const RETRIEVAL_BALL_DEPTH: = 0.075


const GRIP_BEVEL_DEG: = GripFrame.BEVEL_DEG
var _player
var _last_held_mount: = Transform3D.IDENTITY
var _held_mount_valid: = false
var _last_support_arm
var _between_mode: = ""
var _between_entry_local: = Transform3D.IDENTITY
var _between_last_elapsed: = -1.0
var _support_grip_weight: = 0.0
var _support_grip_rotation_deg: = 0.0
var _grasp_key: = Vector2.INF
var _grasp_basis: = Basis.IDENTITY
var mode: = "RELAXED"

func initialize(player) -> void :
	_player = player
	for arm in [player.right_arm_node, player.left_arm_node]:
		if arm.articulated_hand == null:
			arm.articulated_hand = HandModel.new()
			arm.articulated_hand.initialize(arm, arm == player.left_arm_node)

func main_mount(arm, anchor: Vector3, paddle_basis: Basis, pose = null) -> Transform3D:
	arm.articulated_hand.set_pose("GRIP")
	return Transform3D(_grip_basis(arm, paddle_basis, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg if pose != null else 0.0), anchor)



func _grip_basis(arm, paddle_basis: Basis, rotation_deg: float = 0.0) -> Basis:
	return GripFrame.basis(paddle_basis, arm.articulated_hand.is_left, rotation_deg)

func support_mount(arm, anchor: Vector3, _def, grip: bool, pole: Vector3 = Vector3.INF) -> Transform3D:
	var model = arm.articulated_hand
	_support_grip_weight = 0.0
	_support_grip_rotation_deg = _def.support_grip_rotation_deg - _def.paddle_in_hand_rotation_deg if _def != null else 0.0
	if arm != _last_support_arm:
		_held_mount_valid = false
		_last_support_arm = arm
		_between_mode = ""
	if grip:
		_between_mode = ""
		mode = "GRIP"
		_set_support_pose(model, _def, "GRIP", 1.0)
		return Transform3D(_grip_basis(arm, _player.paddle_node.global_basis, _support_grip_rotation_deg), anchor)
	var free: = _free_mount(arm, anchor)
	var between = _player._between_point_owner()
	if between != null:
		var info: Dictionary = between.hand_presentation_for(_player.get_actor_id())
		if not info.is_empty():
			return _retrieval_mount(arm, anchor, free, info)
	_between_mode = ""
	_between_last_elapsed = -1.0
	if _player.posture.editor_preview_mode and _def != null and bool(_def.get_meta("runtime_preview_serve", false)):
		_held_mount_valid = false
		var offset: Vector3 = _def.get_meta("preview_serve_held_offset", Vector3.ZERO)
		var center: Vector3 = _player.global_position + _player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + _player._get_forward_axis() * offset.z
		var charge: float = float(_def.get_meta("preview_serve_charge", _def.charge_duration / PickleballConstants.MAX_SERVE_CHARGE_TIME))
		var held: Transform3D = _serve_grasp_mount(arm, center, charge, offset.y)
		if str(_def.get_meta("preview_serve_phase", "")) == "HELD":
			mode = "EDITOR_CUP"
			model.set_pose("CUP", 1.0)
			return held
		var elapsed: float = float(_def.get_meta("preview_serve_release_elapsed", 0.0))
		if elapsed < 0.18:
			mode = "EDITOR_RELEASE"
			if pole.is_finite(): free = _free_mount_for_pole(arm, anchor, pole)
			return _release_mount(model, held, free, elapsed)
	var game = _player.get_parent()
	var serve = game.get("game_serve")
	var serving: bool = serve != null and _player.hitting.serving_visual_active and int(game.serving_team) == _player.player_num and not _player.posture.editor_preview_mode



	if serving and game.game_state == game.GameState.WAITING and not serve.is_release_pending() and not game.ball.is_in_play:
		mode = "SERVE_CUP"
		model.set_pose("CUP", 1.0)
		var center: Vector3 = serve.get_held_ball_position()
		var charge: float = float(_def.get_meta("serve_phase_charge", serve.get_charge_ratio())) if _def != null else serve.get_charge_ratio()
		_last_held_mount = _serve_grasp_mount(arm, center, charge, center.y - _player.global_position.y)
		_held_mount_valid = true
		return _last_held_mount
	if serving and serve.is_release_pending() and _held_mount_valid:
		mode = "RELEASE"
		var t: float = clampf(float(serve._release_elapsed) / 0.18, 0.0, 1.0)
		if t < 1.0:
			if pole.is_finite(): free = _free_mount_for_pole(arm, anchor, pole)
			return _release_mount(model, _last_held_mount, free, float(serve._release_elapsed))
	_held_mount_valid = false
	_support_grip_weight = clampf(float(_def.get_meta("support_grip_weight", 0.0)) if _def != null else 0.0, 0.0, 1.0)
	if _support_grip_weight > 1e-05:
		mode = "REGRIP"
		if pole.is_finite(): free = _free_mount_for_pole(arm, anchor, pole)


		_set_support_pose(model, _def, "GRIP", lerpf(HandModel.RELAXED_CLOSURE, 1.0, _support_grip_weight))
		return _blended_support_mount(arm, anchor, free, _support_grip_weight)
	mode = "RELAXED"
	_set_support_pose(model, _def, "RELAXED", 1.0)
	return free



func _set_support_pose(model, pose, requested: String, closure: float) -> void :
	if pose != null and pose.has_meta("grip_transition_open"):
		model.set_recovery_pose(float(pose.get_meta("grip_transition_open")), 0.0, pose.support_index_closure, pose.support_grip_style)
	elif pose != null and pose.has_meta("serve_recovery_open"):
		model.set_recovery_pose(float(pose.get_meta("serve_recovery_open")), float(pose.get_meta("serve_recovery_relaxed", 0.0)), pose.support_index_closure)
	else:
		model.set_pose(requested, closure, pose.support_index_closure if pose != null else 1.0, pose.support_grip_style if pose != null else 0.0)



func callout_mount(arm, wrist: Vector3, pole: Vector3, weight: float) -> Transform3D:
	mode = "CALLOUT"
	_support_grip_weight = 0.0
	arm.articulated_hand.set_pose("RELAXED", 1.0 - weight)
	return _free_mount_for_pole(arm, wrist, pole)

func support_orientation_grip_weight() -> float:
	return 1.0 if mode == "GRIP" else (_support_grip_weight if mode == "REGRIP" else 0.0)


func _release_mount(model, held: Transform3D, free: Transform3D, elapsed: float) -> Transform3D:
	var t: float = clampf(elapsed / 0.18, 0.0, 1.0)
	if t < 0.45: model.set_pose("CUP", 1.0 - smoothstep(0.0, 0.45, t))
	else: model.set_pose("RELAXED", smoothstep(0.45, 1.0, t))




	return _release_transform(model, held, free, elapsed)

func _release_transform(model, held: Transform3D, free: Transform3D, elapsed: float) -> Transform3D:
	var t: float = clampf(elapsed / 0.18, 0.0, 1.0)
	var away: Vector3 = - (held.basis * model.palm_normal).normalized()
	var outboard: Vector3 = _player._get_forehand_axis() * (-1.0 if model.is_left else 1.0)
	var start: Vector3 = held * model.cup_ball_center
	var finish: Vector3 = free * model.cup_ball_center
	var first: Vector3 = start + outboard * 0.14 + away * 0.055
	var second: Vector3 = finish + outboard * 0.1 + away * 0.04
	var u: float = smoothstep(0.0, 1.0, t)
	var center: Vector3 = pow(1.0 - u, 3) * start + 3.0 * pow(1.0 - u, 2) * u * first + 3.0 * (1.0 - u) * u * u * second + u * u * u * finish
	var basis: Basis = held.basis.slerp(free.basis, smoothstep(0.15, 0.85, t)).orthonormalized()
	return Transform3D(basis, center - basis * model.cup_ball_center)




func _free_mount_for_pole(arm, anchor: Vector3, pole: Vector3) -> Transform3D:
	return _free_mount_for_shoulder(arm, anchor, pole, arm.upper_pivot.global_position)

func _free_mount_for_shoulder(arm, anchor: Vector3, pole: Vector3, shoulder: Vector3) -> Transform3D:
	var span: Vector3 = anchor - shoulder
	var distance: float = span.length()
	if distance < 1e-05: return _free_mount_for_elbow(arm, anchor, arm.forearm_pivot.global_position + (shoulder - arm.upper_pivot.global_position))
	var axis: Vector3 = span / distance
	var stretch: float = maxf(distance / (arm.upper_arm_length + arm.forearm_length), 1.0)
	var upper: float = arm.upper_arm_length * stretch
	var fore: float = arm.forearm_length * stretch
	var solved_distance: float = minf(distance, upper + fore - 0.001)
	var along: float = clampf((upper * upper + solved_distance * solved_distance - fore * fore) / (2.0 * solved_distance), - upper, upper)
	var radius: float = sqrt(maxf(0.0, upper * upper - along * along))
	var hint: Vector3 = (pole - shoulder).normalized()
	if absf(axis.dot(hint)) > 0.999: hint = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var transverse: Vector3 = (hint - axis * hint.dot(axis)).normalized()
	var elbow: Vector3 = shoulder + axis * along + transverse * radius
	var radial: Vector3 = Vector3.DOWN if arm == _player.left_arm_node else Vector3.UP
	var basis: Basis = Anatomy.frame((anchor - elbow).normalized(), radial) * arm.articulated_hand.anatomical_basis.inverse()
	return Transform3D(basis, anchor - basis * arm.articulated_hand.wrist_socket)

func _blended_support_mount(arm, wrist: Vector3, free: Transform3D, weight: float) -> Transform3D:
	var grip_basis: Basis = _grip_basis(arm, _player.paddle_node.global_basis, _support_grip_rotation_deg)
	var basis: Basis = free.basis.slerp(grip_basis, weight).orthonormalized()


	return Transform3D(basis, wrist - basis * arm.articulated_hand.wrist_socket)





func _retrieval_mount(arm, anchor: Vector3, free: Transform3D, info: Dictionary) -> Transform3D:
	var model = arm.articulated_hand
	var elapsed: float = float(info.get("elapsed", 0.0))
	var next_mode: String = str(info.mode)
	if next_mode != _between_mode or elapsed < _between_last_elapsed:
		_between_entry_local = _player.global_transform.affine_inverse() * arm.hand_mesh.global_transform
		_between_mode = next_mode
	_between_last_elapsed = elapsed
	mode = next_mode
	var t: float = float(info.get("transition", 1.0))
	var target: Transform3D = free
	if mode == "PASS_RELEASE":
		model.set_pose("RELAXED", t)
	else:
		if mode == "PICKUP" and t < 1.0:
			model.set_pose("RELAXED", 1.0 - t)
		elif mode == "CATCH_OPEN" and t < 0.5:
			model.set_pose("RELAXED", 1.0 - smoothstep(0.0, 0.5, t))
		else:
			var closure: float = float(info.closure)
			if mode == "CATCH_OPEN": closure *= smoothstep(0.5, 1.0, t)
			model.set_pose("CUP", closure)
		var normal: Vector3 = info.normal
		target = _cup_mount(model, anchor + normal * RETRIEVAL_BALL_DEPTH, normal)
	if t < 1.0:
		return (_player.global_transform * _between_entry_local).interpolate_with(target, t)
	return target

func _free_mount(arm, anchor: Vector3) -> Transform3D:
	return _free_mount_for_elbow(arm, anchor, arm.forearm_pivot.global_position)

func _free_mount_for_elbow(arm, anchor: Vector3, elbow: Vector3) -> Transform3D:
	var model = arm.articulated_hand
	var distal: Vector3 = (anchor - elbow).normalized()
	if distal.length_squared() < 0.5: distal = _player._get_forward_axis()
	var radial: Vector3 = Vector3.UP
	if arm == _player.left_arm_node: radial = - radial
	var hand_world: Basis = Anatomy.frame(distal, radial)
	var basis: Basis = hand_world * model.anatomical_basis.inverse()
	return Transform3D(basis, anchor - basis * model.wrist_socket)

func _serve_grasp_mount(arm, center: Vector3, charge: float, held_height: float) -> Transform3D:


	if not arm.articulated_hand.is_left: return _cup_mount(arm.articulated_hand, center, Vector3.UP)
	var key: = Vector2(clampf(charge, 0.0, 1.0), held_height)
	if not key.is_equal_approx(_grasp_key):
		_grasp_key = key
		_grasp_basis = ServeGrasp.basis(key.x, key.y)
	var stance: = Basis(_player._get_forehand_axis(), Vector3.UP, - _player._get_forward_axis())
	var basis: Basis = stance * _grasp_basis
	return Transform3D(basis, center - basis * arm.articulated_hand.cup_ball_center)

func _cup_mount(model, center: Vector3, normal: Vector3, distal_hint: Vector3 = Vector3.ZERO) -> Transform3D:
	var dorsal: Vector3 = - normal.normalized()
	var distal: Vector3 = distal_hint if distal_hint.length_squared() > 1e-06 else _player._get_forward_axis()
	distal = (distal - dorsal * distal.dot(dorsal)).normalized()
	if distal.length_squared() < 0.01: distal = _player._get_forehand_axis()
	var radial: Vector3 = dorsal.cross(distal).normalized()


	var basis: Basis = Basis(distal, radial, dorsal) * model.palm_contact_basis.inverse()
	return Transform3D(basis, center - basis * model.cup_ball_center)

func apply_mount(arm, mount: Transform3D, is_support: bool = false) -> void :
	if is_support and mode == "RELAXED":
		mount = _free_mount(arm, arm.hand_pivot.global_position)
	elif is_support and mode == "REGRIP":
		var wrist: Vector3 = arm.hand_pivot.global_position
		mount = _blended_support_mount(arm, wrist, _free_mount(arm, wrist), _support_grip_weight)
	arm.articulated_hand.set_mesh_world_transform(mount)
	arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)

static func wrist_for(arm, mount: Transform3D) -> Vector3:
	return mount * arm.articulated_hand.wrist_socket

static func ball_center(arm) -> Vector3:
	return arm.hand_mesh.global_transform * arm.articulated_hand.cup_ball_center

static func ball_surface_gap(arm, world_center: Vector3, radius: float) -> float:
	return arm.articulated_hand.palm_surface_gap(arm.hand_mesh.to_local(world_center), radius)

func apply_live_regrip_shape(arm, pose: PostureDefinition) -> void:
	if mode not in ["REGRIP", "GRIP"] or _player.posture.editor_preview_mode or _player._between_point_owner() != null: return
	if pose.has_meta("grip_transition_open") or pose.has_meta("serve_recovery_open"): return
	var state: Dictionary = arm.get_meta("live_support_frame", {})
	if state.is_empty() or mode == "GRIP" and float(state.get("open_weight", 0.0)) <= 0.0: return
	var desired: Basis = _grip_basis(arm, _player.paddle_node.global_basis, _support_grip_rotation_deg)
	var relative: Quaternion = arm.hand_mesh.global_basis.orthonormalized().get_rotation_quaternion().inverse() * desired.get_rotation_quaternion()
	var angle: float = rad_to_deg(2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w)))
	# Fingers open before crossing the handle and only close as the actual
	# rate-limited hand approaches its seated orientation, not a tween clock.
	var wanted: float = 0.0 if mode == "GRIP" else smoothstep(5.0, 20.0, angle) * smoothstep(.05, .25, _support_grip_weight)
	if float(state.get("open_time", -1.0)) != float(state.time):
		state.open_time = state.time
		state.open_start = float(state.get("open_weight", 0.0))
	var amount: float = move_toward(float(state.open_start), wanted, 8.0 * float(state.dt))
	state.open_weight = amount
	arm.articulated_hand.set_recovery_pose(amount, 0.0, pose.support_index_closure, pose.support_grip_style)

## Pure body-fit dependency. The actual support owner uses the same free-mount
## and release-transform functions after the candidate body translation.
func preview_serve_release(pose, body_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	if pose == null or _player == null or not _held_mount_valid: return {}
	if _player.posture == null or _player.posture.editor_preview_mode: return {}
	if _player.hitting == null or not _player.hitting.serving_visual_active: return {}
	if _player._between_point_owner() != null: return {}
	var game = _player.get_parent()
	if game == null or game.game_serve == null or game.get_server_actor() != _player: return {}
	var serve = game.game_serve
	if not serve.is_release_pending() or game.game_state != game.GameState.SERVING: return {}
	var elapsed: float = float(serve._release_elapsed)
	if elapsed < 0.0 or elapsed >= 0.18: return {}
	var left_dominant: bool = pose.paddle_hand == 1
	var arm = _player.right_arm_node if left_dominant else _player.left_arm_node
	if arm != _last_support_arm or Path._support_mode(pose) == 1: return {}
	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	var side: float = -1.0 if left_dominant else 1.0
	var offset: Vector3 = pose.right_hand_offset if left_dominant else pose.left_hand_offset
	var anchor: Vector3 = _player.arm_ik.get_support_hand_target(pose)
	anchor += fh * offset.x + Vector3.UP * offset.y + fwd * offset.z
	var pole: Vector3 = _player.global_position - fh * 0.5 * side + Vector3.DOWN + fwd * -0.5
	var authored_pole: Vector3 = pose.right_elbow_pole if left_dominant else pose.left_elbow_pole
	if authored_pole.length_squared() > 1e-10:
		pole = _player.global_position + fh * authored_pole.x + Vector3.UP * authored_pole.y + fwd * authored_pole.z
	var shoulder: Vector3 = arm.upper_pivot.global_position + body_offset
	var angles: Vector3 = pose.right_shoulder_rotation_deg if left_dominant else pose.left_shoulder_rotation_deg
	if angles.length_squared() >= 0.0001:
		var stance: Basis = Basis(fh, Vector3.UP, -fwd)
		var rotation: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
		pole = shoulder + rotation * (pole - shoulder)
	var free: Transform3D = _free_mount_for_shoulder(arm, anchor, pole, shoulder)
	var mount: Transform3D = _release_transform(arm.articulated_hand, _last_held_mount, free, elapsed)
	return {"mount": mount, "wrist": mount * arm.articulated_hand.wrist_socket,
		"basis": mount.basis, "elapsed": elapsed, "side": 0 if left_dominant else 1}
