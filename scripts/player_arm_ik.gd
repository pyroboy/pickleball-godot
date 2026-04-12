class_name PlayerArmIK extends Node

var _player: PlayerController

func _ready() -> void:
	_player = get_parent() as CharacterBody3D

func update_arm_ik(delta: float) -> void:
	var b = _player._get_ball_ref()
	var def: PostureDefinition = _player.get_runtime_posture_def()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()

	if _player.right_arm_node and _player.paddle_node:
		var target_global: Vector3 = _player.paddle_node.to_global(Vector3(0, 0.07, 0))
		if def and def.right_hand_offset.length_squared() > 1e-10:
			target_global = _player.paddle_node.to_global(Vector3(0, 0.07, 0) + def.right_hand_offset)
		var pole_global: Vector3 = _player.global_position + forehand_axis * 0.5 + Vector3(0, -1.0, 0) + forward_axis * -0.5
		if def and def.right_elbow_pole.length_squared() > 1e-10:
			pole_global = _player.global_position + PostureSkeletonApplier.stance_offset(def.right_elbow_pole, forehand_axis, forward_axis)
		if _player.right_arm_node.has_method("solve_ik"):
			_player.right_arm_node.solve_ik(target_global, pole_global, _player.paddle_node.global_transform)

	if _player.left_arm_node:
		var target_global_left: Vector3
		var pass_transform: Transform3D = Transform3D()

		var used_data_mode: bool = false
		if def:
			match def.left_hand_mode:
				1:
					if _player.paddle_node:
						target_global_left = _player.paddle_node.to_global(Vector3(0, 0.20, 0))
						used_data_mode = true
				2:
					target_global_left = _player.global_position + forehand_axis * -0.2 + forward_axis * 0.2 + Vector3(0, 0.45, 0)
					used_data_mode = true
				3:
					target_global_left = _player.global_position + Vector3(0, 1.05, 0) + forward_axis * 0.15
					used_data_mode = true

		if not used_data_mode:
			var is_overhead_grip: bool = _player.paddle_posture in [
				_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD,
				_player.PaddlePosture.VOLLEY_READY, _player.PaddlePosture.READY,
			]
			var is_backhand_grip: bool = _player.paddle_posture in _player.BACKHAND_POSTURES
			if (is_overhead_grip or is_backhand_grip) and _player.paddle_node:
				# Backhand: left hand grips the handle neck (slightly higher than overhead grip)
				var neck_y: float = 0.20 if is_backhand_grip else 0.12
				target_global_left = _player.paddle_node.to_global(Vector3(0, neck_y, 0))
			else:
				var default_rest = _player.global_position + _player._get_forward_axis() * 0.55 + _player._get_forehand_axis() * -0.15 + Vector3(0, 0.15, 0)
				var desired_rest = default_rest

				if _player.ball_ref and is_instance_valid(_player.ball_ref):
					var intercept = _player.ai_brain._predict_first_bounce_position(_player.ball_ref) if _player.ai_brain else _player.ball_ref.global_position
					var chest_pos = _player.global_position + Vector3(0, 0.15, 0)
					var z_diff = intercept.z - _player.global_position.z
					if (_player.player_num == 0 and z_diff < 0) or (_player.player_num == 1 and z_diff > 0):
						var to_ball_flat = Vector3(intercept.x - _player.global_position.x, 0, intercept.z - _player.global_position.z)
						var dist = to_ball_flat.length()
						if dist < 3.0 and dist > 0.5:
							var blend = clamp(1.0 - dist / 3.0, 0.0, 0.6)
							var point_target = Vector3(intercept.x, chest_pos.y, intercept.z)
							desired_rest = default_rest.lerp(point_target, blend)

				if _player.left_hand_rest_pos == Vector3.ZERO:
					_player.left_hand_rest_pos = desired_rest
				else:
					_player.left_hand_rest_pos = _player.left_hand_rest_pos.lerp(desired_rest, 8.0 * delta)
				target_global_left = _player.left_hand_rest_pos

		if def and def.left_hand_offset.length_squared() > 1e-10:
			target_global_left += PostureSkeletonApplier.stance_offset(def.left_hand_offset, forehand_axis, forward_axis)

		var pole_global_left: Vector3 = _player.global_position + forehand_axis * -0.5 + Vector3(0, -1.0, 0) + forward_axis * -0.5
		if def and def.left_elbow_pole.length_squared() > 1e-10:
			pole_global_left = _player.global_position + PostureSkeletonApplier.stance_offset(def.left_elbow_pole, forehand_axis, forward_axis)
		if _player.left_arm_node.has_method("solve_ik"):
			_player.left_arm_node.solve_ik(target_global_left, pole_global_left, pass_transform)

		if _player.player_num == 0 and not _player.has_debug_printed:
			_player.has_debug_printed = true
			var elbow = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
			var hand = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot")
			if elbow and hand:
				print("[P0] L arm IK: elbow=", elbow.global_position)

	# Human intercept indicator updates
	if not _player.is_ai and b != null and _player.debug_visual:
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
