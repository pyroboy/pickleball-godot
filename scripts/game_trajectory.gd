class_name GameTrajectory
extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")

const _Flight = preload("res://scripts/ball_flight_predictor.gd")
const Accuracy = preload("res://scripts/shot_accuracy.gd")
const ServeStyles = preload("res://scripts/serve_style.gd")






class CursorPresentation extends Node:
	var trajectory
	func _process(delta: float) -> void:
		if is_instance_valid(trajectory): trajectory._update_player_cursor(delta)

var _cursor_presentation: Node
var _game: Node = null
var _ball: RigidBody3D = null


var trajectory_mesh_instance: MeshInstance3D
var trajectory_mesh: ImmediateMesh
var trajectory_material: StandardMaterial3D


var target_marker: MeshInstance3D
var landing_cursor: MeshInstance3D
var landing_label: Label3D
var _cursor_material: StandardMaterial3D
var _execution_axes := Vector2.ZERO
var _execution_area_showing := false


var _last_trajectory_key: String = ""
var _last_preview_ms: int = -1000


var _serve_aim_offset_x: float = 0.0
var _trajectory_arc_offset: float = 0.0


const MAX_SERVE_CHARGE_TIME: float = 1.5



func setup(game: Node, ball: RigidBody3D) -> void :
	_game = game
	_ball = ball
	_create_visuals()
	# Only presentation follows render-time aim input and final focus meaning.
	# The trajectory owner/cache update remains in the original physics call.
	_cursor_presentation = CursorPresentation.new()
	_cursor_presentation.trajectory = self
	_cursor_presentation.process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor_presentation.process_priority = 1002
	add_child(_cursor_presentation)










func update(game_state: int, serving_team: int, serve_aim_offset_x: float, 
		trajectory_arc_offset: float, serve_charge_time: float, 
		player_left_pos: Vector3, player_right_pos: Vector3) -> void :

	_serve_aim_offset_x = serve_aim_offset_x
	_trajectory_arc_offset = trajectory_arc_offset
	if _game and "aim_focus" in _game and _game.aim_focus and _game.aim_focus.active:


		_clear_arc()
		return
	if not RuntimePolicy.developer_tools: return

	if _ball == null or serve_charge_time <= 0.0 or game_state == 2:
		_clear_arc()
		_last_trajectory_key = ""
		return


	if game_state == 0 and _game.human_may_serve() and _game.aim_controller.planted and Input.get_vector("move_left", "move_right", "move_up", "move_down").length_squared() > 0.01:
		_clear_arc()
		return
	var charge_ratio: float = snappedf(serve_charge_time / MAX_SERVE_CHARGE_TIME, 0.08)
	var start_position: Vector3 = _ball.global_position
	var start_velocity: Vector3 = Vector3.ZERO
	var start_angular: Vector3 = _ball.angular_velocity


	var cache_key: String = ""


	if game_state == 0:
		var server = _game.get_server_actor()
		if server == null: _clear_arc(); return
		start_position = _game.game_serve.get_serve_launch_position(serving_team == 1)
		if target_marker: target_marker.visible = false
		cache_key = "serve_%d_%f_%f_%f_%v" % [server.get_actor_id(), charge_ratio, serve_aim_offset_x, trajectory_arc_offset, server.global_position]
		if _game.human_may_serve() and _game.aim_controller:
			cache_key += "_target%v" % _game.aim_controller.get_target().snapped(Vector3(0.04, 0.04, 0.04))
		cache_key += "_mode%d_style%d" % [int(_game.selected_spin_mode), int(_game.game_serve.selected_serve_style)]
		if cache_key == _last_trajectory_key and trajectory_mesh_instance.visible: return
		var now: int = Time.get_ticks_msec()
		if now - _last_preview_ms < 167 and trajectory_mesh_instance.visible: return
		_last_preview_ms = now
		var launch: Dictionary = _game.game_serve.get_predicted_serve_launch(charge_ratio, serving_team == 1)
		start_velocity = launch.velocity
		start_angular = launch.omega


	elif game_state == 2:
		var shot_impulse: Vector3 = Vector3.ZERO
		if _game.has_method("player_left") and _game.player_left != null:
			var p_left = _game.player_left
			if p_left.has_method("get_shot_impulse"):
				shot_impulse = p_left.get_shot_impulse(_ball.global_position, charge_ratio, true)
		start_velocity = _ball.linear_velocity + (shot_impulse / _ball.mass)
		cache_key = "p_%v_%f" % [_ball.global_position, charge_ratio]

	else:
		clear()
		return


	if cache_key == _last_trajectory_key and trajectory_mesh_instance.visible:
		return
	_last_trajectory_key = cache_key

	_draw_trajectory(start_position, start_velocity, start_angular)



func clear() -> void :
	_clear_arc()
	if landing_cursor: landing_cursor.visible = false
	if landing_label: landing_label.visible = false

func _clear_arc() -> void :
	if trajectory_mesh == null or trajectory_mesh_instance == null:
		return
	trajectory_mesh.clear_surfaces()
	trajectory_mesh_instance.visible = false
	if target_marker != null:
		target_marker.visible = false



func get_aim_label() -> String:
	if _serve_aim_offset_x < -0.2:
		return "Left"
	if _serve_aim_offset_x > 0.2:
		return "Right"
	return "Center"



func get_arc_label() -> String:
	if is_zero_approx(_trajectory_arc_offset):
		return "Auto"
	if _trajectory_arc_offset > 0.0:
		return "High +" + str(int(round(_trajectory_arc_offset / 0.05)))
	return "Low " + str(int(round(_trajectory_arc_offset / 0.05)))



func apply_arc_intent_to_impulse(shot_impulse: Vector3) -> Vector3:
	if is_zero_approx(_trajectory_arc_offset):
		return shot_impulse
	var adjusted_impulse: Vector3 = shot_impulse
	adjusted_impulse.y += _trajectory_arc_offset * 3.6
	return adjusted_impulse



func _create_visuals() -> void :
	if not RuntimePolicy.developer_tools:
		_create_landing_cursor()
		return

	trajectory_mesh_instance = MeshInstance3D.new()
	trajectory_mesh_instance.name = "TrajectoryPredictor"
	trajectory_mesh = ImmediateMesh.new()
	trajectory_mesh_instance.mesh = trajectory_mesh
	trajectory_material = StandardMaterial3D.new()
	trajectory_material.albedo_color = Color(0.95, 0.98, 1.0, 0.95)
	trajectory_material.emission_enabled = true
	trajectory_material.emission = Color(0.45, 0.9, 1.0, 1.0)
	trajectory_material.emission_energy_multiplier = 0.8
	trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trajectory_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trajectory_mesh_instance.material_override = trajectory_material
	trajectory_mesh_instance.visible = false
	add_child(trajectory_mesh_instance)


	target_marker = MeshInstance3D.new()
	target_marker.name = "RedTargetMarker"
	var marker_mesh: = SphereMesh.new()
	marker_mesh.radius = 0.25
	marker_mesh.height = 0.5
	target_marker.mesh = marker_mesh
	var marker_mat: = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.35, 0.35, 0.8)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	marker_mat.emission_energy_multiplier = 1.2
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_marker.material_override = marker_mat
	target_marker.visible = false
	add_child(target_marker)
	_create_landing_cursor()



func _update_red_target_marker() -> void :
	if target_marker == null or _game == null:
		return

	var score_right: int = _game.score_right
	var total_score: int = score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var target_x: float

	if serve_from_right:

		target_x = maxf(_serve_aim_offset_x, 1.5)
	else:

		target_x = minf(_serve_aim_offset_x, -1.5)


	target_marker.global_position = Vector3(target_x, 0.1, 4.6)
	target_marker.visible = true




func _get_serve_launch_position(is_red_side: bool, _player_pos: Vector3) -> Vector3:
	return _game.game_serve.get_serve_launch_position(is_red_side)



func _get_predicted_serve_velocity(charge_ratio: float, from_red_side: bool) -> Vector3:
	return _game.game_serve.get_predicted_serve_velocity(charge_ratio, from_red_side)



func _draw_trajectory(start_position: Vector3, start_velocity: Vector3, start_angular: Vector3 = Vector3.ZERO) -> void :
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, trajectory_material)
	var flight: Dictionary = _Flight.trace(start_position, start_velocity, start_angular, 3.0, 1, true)
	for sample in flight["samples"]:
		trajectory_mesh.surface_add_vertex(sample["pos"] + Vector3(0.0, 0.03, 0.0))
	trajectory_mesh.surface_end()
	trajectory_mesh_instance.visible = true




func _predict_ball_landing_pos() -> Vector3:
	if _ball == null:
		return Vector3.INF
	var flight: Dictionary = _Flight.trace(_ball.global_position, _ball.linear_velocity, 
		_ball.angular_velocity, 3.0, 1, true)
	return flight["first_bounce"] if flight["first_bounce_time"] >= 0.0 else Vector3.INF



func _is_landing_out_of_bounds(pos: Vector3) -> bool:
	if pos == Vector3.INF:
		return false

	var half_len: float = 6.7
	var half_wid: float = 3.05
	return pos.z > half_len or pos.z < - half_len or pos.x < - half_wid or pos.x > half_wid


func _create_landing_cursor() -> void :
	landing_cursor = MeshInstance3D.new()
	landing_cursor.name = "PlayerLandingCursor"
	var ring: = TorusMesh.new()
	ring.inner_radius = 0.94
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 12
	landing_cursor.mesh = ring
	landing_cursor.scale.y = 0.3
	_cursor_material = StandardMaterial3D.new()
	_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_material.emission_enabled = true
	_cursor_material.emission_energy_multiplier = 1.5
	landing_cursor.material_override = _cursor_material
	landing_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landing_cursor.visible = false
	add_child(landing_cursor)
	landing_label = Label3D.new()
	landing_label.name = "LandingCursorLabel"
	landing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	landing_label.font_size = 28
	landing_label.pixel_size = 0.005
	landing_label.outline_size = 10
	landing_label.no_depth_test = true
	landing_label.visible = false
	add_child(landing_label)

func _update_player_cursor(delta: float = 1.0 / 60.0) -> void :
	if landing_cursor == null or _game == null or _game.aim_controller == null: return
	var aim = _game.aim_controller
	var mobile = _game.mobile_controls
	var cancel_armed: bool = mobile != null and mobile._cancel_armed
	var blocked: bool = get_tree().paused or _game._tool_state_active() or _game.match_over or _game.hud == null or not _game.hud._gameplay_visible or _game.hud._guide.visible or _game.hud._between_point_active or _game.practice_panel != null and _game.practice_panel.visible
	var current_context: bool = _game.game_state == 0 and _game.human_may_serve() or _game.game_state == 2 and _ball != null and _ball.is_in_play and _ball.last_hit_by != _game.player_left.player_num and _ball.bounces_since_last_hit < 2
	var show: bool = aim.cursor_visible and Input.is_action_pressed("ui_accept") and not aim.is_locked() and not cancel_armed and not blocked and current_context
	landing_cursor.visible = show
	landing_label.visible = show
	if not show:
		_execution_area_showing = false
		return
	var point: Vector3 = aim.get_target()
	var wall: bool = _game.practice_launcher and _game.practice_launcher.is_wall()
	var serve: bool = _game.game_state == 0 and _game.human_may_serve()
	var charge: float = _game.game_serve.get_charge_ratio() if serve else float(_game.hud._charge_bar.value)
	var mode: int = ServeStyles.spin_mode(_game.game_serve.selected_serve_style) if serve else int(_game.selected_spin_mode)
	var context: Dictionary = _game.execution_preview_context(charge, serve)
	var origin: Vector3 = _ball.global_position
	var human = _game.player_left.posture.human_contact
	if not serve and human != null:
		var preparation: Dictionary = human.preparation_contact()
		if not preparation.is_empty(): origin = preparation.point
	var span: float = Vector2(point.x - origin.x, point.z - origin.z).length()
	var desired: Vector2 = preload("res://scripts/shot_execution_error.gd").estimated_landing_axes(span, context)
	if not _execution_area_showing: _execution_axes = desired
	else: _execution_axes = _execution_axes.lerp(desired, 1.0 - exp(-maxf(delta, 0.0) / 0.12))
	_execution_area_showing = true
	var radii: Vector2 = _execution_axes
	landing_cursor.scale = Vector3(0.25, 0.12, 0.25) if wall else Vector3(radii.x, 0.12, radii.y)
	landing_cursor.rotation.x = PI * 0.5 if wall else 0.0
	landing_cursor.global_position = point + Vector3(0, 0, 0.035) if wall else Vector3(point.x, 0.105, point.z)
	landing_label.global_position = point + Vector3(0, 0.28, 0.05) if wall else Vector3(point.x, 0.39, point.z)
	var estimated_warning: bool = _game.aim_focus != null and _game.aim_focus.active and _game.aim_focus.preview_hint != "ESTIMATED ARC"
	var color: = Color("ffc964") if estimated_warning else Color("5ff0ff")
	_cursor_material.albedo_color = color
	_cursor_material.emission = color
	landing_label.modulate = color
	landing_label.text = "CHECK ARC" if estimated_warning else "AIM" if wall else "PERFECT TRAINING" if context.perfect else "ESTIMATED SPREAD"
