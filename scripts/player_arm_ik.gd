class_name PlayerArmIK extends Node
const _PostureSkeletonApplier = preload("res://scripts/posture_skeleton_applier.gd")

var _player

func _ready() -> void:
	_player = get_parent() as CharacterBody3D

func update_arm_ik(delta: float, def_override = null) -> void:
	var b = _player._get_ball_ref()
	var def = def_override if def_override != null else _player.get_runtime_posture_def()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()

	if _player.paddle_node:
		var left_dominant: bool = def != null and def.paddle_hand == 1
		var dominant_arm = _player.left_arm_node if left_dominant else _player.right_arm_node
		var support_arm = _player.right_arm_node if left_dominant else _player.left_arm_node
		var main_offset: Vector3 = (def.left_hand_offset if left_dominant else def.right_hand_offset) if def else Vector3.ZERO
		var support_offset: Vector3 = (def.right_hand_offset if left_dominant else def.left_hand_offset) if def else Vector3.ZERO
		var main_pole: Vector3 = (def.left_elbow_pole if left_dominant else def.right_elbow_pole) if def else Vector3.ZERO
		var support_pole: Vector3 = (def.right_elbow_pole if left_dominant else def.left_elbow_pole) if def else Vector3.ZERO
		var side: float = -1.0 if left_dominant else 1.0
		var main_target: Vector3 = _player.paddle_node.to_global(Vector3(0, 0.07, 0) + main_offset)
		var main_pole_world: Vector3 = _player.global_position + forehand_axis * 0.5 * side + Vector3.DOWN + forward_axis * -0.5
		if main_pole.length_squared() > 1e-10:
			main_pole_world = _player.global_position + _PostureSkeletonApplier.stance_offset(main_pole, forehand_axis, forward_axis)
		if dominant_arm and def:
			var shoulder_rotation: Vector3 = def.left_shoulder_rotation_deg if left_dominant else def.right_shoulder_rotation_deg
			main_pole_world = _rotate_shoulder_pole(dominant_arm, main_pole_world, shoulder_rotation)
		if dominant_arm and dominant_arm.has_method("solve_ik"):
			dominant_arm.solve_ik(main_target, main_pole_world, _player.paddle_node.global_transform)

		var support_target: Vector3 = get_support_hand_target(def)
		support_target += _PostureSkeletonApplier.stance_offset(support_offset, forehand_axis, forward_axis)
		var support_pole_world: Vector3 = _player.global_position - forehand_axis * 0.5 * side + Vector3.DOWN + forward_axis * -0.5
		if support_pole.length_squared() > 1e-10:
			support_pole_world = _player.global_position + _PostureSkeletonApplier.stance_offset(support_pole, forehand_axis, forward_axis)
		if support_arm and def:
			var shoulder_rotation: Vector3 = def.right_shoulder_rotation_deg if left_dominant else def.left_shoulder_rotation_deg
			support_pole_world = _rotate_shoulder_pole(support_arm, support_pole_world, shoulder_rotation)
		if support_arm and support_arm.has_method("solve_ik"):
			support_arm.solve_ik(support_target, support_pole_world, Transform3D())

	# Human intercept indicator updates
	if not _player.is_ai and b != null and _player.debug_visual and _player.posture.human_contact == null:
		if _player.debug_visual.human_committed_contact_position != Vector3.ZERO:
			var dist_to_ball = b.global_position.distance_to(_player.debug_visual.human_committed_contact_position)
			var inbound = (_player.debug_visual.human_committed_contact_position.z - _player.global_position.z) < 0.2

			if _player.debug_visual.human_intercept_indicator:
				_player.debug_visual.human_intercept_indicator.global_position = _player.debug_visual.human_intercept_indicator.global_position.lerp(
					_player._clamp_to_court(_player.debug_visual.human_committed_contact_position), 15.0 * delta)
				if inbound:
					var ms = Time.get_ticks_msec()
					_player.debug_visual.human_intercept_indicator.visible = (ms % 400 > 150)
				else:
					_player.debug_visual.human_intercept_indicator.visible = true
				var mat = _player.debug_visual.human_intercept_indicator.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color.a = clamp(1.0 - dist_to_ball * 0.08, 0.15, 0.6)

			if _player.debug_visual.human_target_indicator:
				if _player.debug_visual.human_target_indicator.global_position == Vector3.ZERO:
					_player.debug_visual.human_target_indicator.global_position = _player._clamp_to_court(_player.debug_visual.human_committed_target_position)
				else:
					_player.debug_visual.human_target_indicator.global_position = _player.debug_visual.human_target_indicator.global_position.lerp(
						_player._clamp_to_court(_player.debug_visual.human_committed_target_position), 10.0 * delta)
				var reactive_size = clamp(dist_to_ball * 0.4, 0.45, 2.5)
				_player.debug_visual.human_target_indicator.scale = _player.debug_visual.human_target_indicator.scale.lerp(Vector3(reactive_size, 1.0, reactive_size), 22.0 * delta)
				_player.debug_visual.human_target_indicator.visible = true
				var tmat = _player.debug_visual.human_target_indicator.material_override as StandardMaterial3D
				if tmat:
					tmat.albedo_color.a = clamp(1.0 - dist_to_ball * 0.07, 0.08, 0.4)
					tmat.emission_energy_multiplier = clamp(1.2 - dist_to_ball * 0.1, 0.2, 1.2)


## Auto preserves the existing pose-family grip; explicit Free never falls back to it.
func _rotate_shoulder_pole(arm: Node3D, pole: Vector3, angles: Vector3) -> Vector3:
	if angles.length_squared() < 0.0001: return pole
	var stance := Basis(_player._get_forehand_axis(), Vector3.UP, -_player._get_forward_axis())
	var rotation: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
	var shoulder: Vector3 = arm.get_node("UpperArmPivot").global_position
	return shoulder + rotation * (pole - shoulder)


func get_support_hand_target(def) -> Vector3:
	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	var mode: int = def.left_hand_mode if def else 0
	var left_dominant: bool = def != null and def.paddle_hand == 1
	var side: float = 1.0 if left_dominant else -1.0
	if mode == 0:
		var both: bool = _player.paddle_posture in _player.BACKHAND_POSTURES or _player.paddle_posture in [
			_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD,
			_player.PaddlePosture.VOLLEY_READY, _player.PaddlePosture.READY]
		mode = 1 if both else 4
	match mode:
		1: return _player.paddle_node.to_global(Vector3(0, 0.20, 0))
		2: return _player.global_position + fh * 0.2 * side + fwd * 0.2 + Vector3(0, 0.45, 0)
		3: return _player.global_position + Vector3(0, 1.05, 0) + fwd * 0.15
		_: return _player.global_position + fwd * 0.55 + fh * 0.15 * side + Vector3(0, 0.15, 0)
