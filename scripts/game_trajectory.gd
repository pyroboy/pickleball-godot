class_name GameTrajectory
extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")

const _Flight = preload("res://scripts/ball_flight_predictor.gd")
const ServeStyles = preload("res://scripts/serve_style.gd")
const CuePriority = preload("res://scripts/ui/player_cue_priority.gd")
const LabelPill = preload("res://scripts/ui/label_pill_3d.gd")






class CursorPresentation extends Node:
	var trajectory
	func _process(delta: float) -> void:
		if is_instance_valid(trajectory):
			trajectory._update_player_cursor(delta)
			trajectory._update_smash_marker()

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
# Smash guide: ring where to stand, post up to the contact point, the incoming
# arc and a label. Orange while the player must move, green once in position.
const SMASH_MOVE_COLOR := Color("ff9a3c")
const SMASH_READY_COLOR := Color("bde879")
var _smash_root: Node3D
var _smash_ring: MeshInstance3D
var _smash_dot: MeshInstance3D
var _smash_lines: ImmediateMesh
var _smash_label: Label3D
var _smash_material: StandardMaterial3D
var _smash_key: String = ""
var _execution_area_showing := false
## The smash guide has something to show this frame (read by player_cue_priority.gd).
var smash_wanted := false


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
	marker_mesh.radial_segments = 12
	marker_mesh.rings = 6
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



func _draw_trajectory(start_position: Vector3, start_velocity: Vector3, start_angular: Vector3 = Vector3.ZERO) -> void :
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, trajectory_material)
	var flight: Dictionary = _Flight.trace(start_position, start_velocity, start_angular, 3.0, 1, true)
	for sample in flight["samples"]:
		trajectory_mesh.surface_add_vertex(sample["pos"] + Vector3(0.0, 0.03, 0.0))
	trajectory_mesh.surface_end()
	trajectory_mesh_instance.visible = true




func _create_landing_cursor() -> void :
	landing_cursor = MeshInstance3D.new()
	landing_cursor.name = "PlayerLandingCursor"
	var ring: = TorusMesh.new()
	ring.inner_radius = 0.94
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 4
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
	LabelPill.attach(landing_label)
	_create_smash_marker()

func _create_smash_marker() -> void :
	_smash_root = Node3D.new()
	_smash_root.name = "SmashGuide"
	_smash_root.visible = false
	add_child(_smash_root)
	_smash_material = StandardMaterial3D.new()
	_smash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_smash_material.disable_fog = true
	_smash_ring = MeshInstance3D.new()
	var ring: = TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.42
	ring.rings = 24
	ring.ring_segments = 4
	_smash_ring.mesh = ring
	_smash_ring.scale.y = 0.12
	_smash_dot = MeshInstance3D.new()
	var dot: = SphereMesh.new()
	dot.radius = 0.11
	dot.height = 0.22
	dot.radial_segments = 8
	dot.rings = 4
	_smash_dot.mesh = dot
	var lines: = MeshInstance3D.new()
	_smash_lines = ImmediateMesh.new()
	lines.mesh = _smash_lines
	for node in [_smash_ring, _smash_dot, lines]:
		node.material_override = _smash_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smash_root.add_child(node)
	_smash_label = Label3D.new()
	_smash_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_smash_label.font_size = 40
	_smash_label.pixel_size = 0.005
	_smash_label.outline_size = 12
	_smash_label.no_depth_test = true
	_smash_root.add_child(_smash_label)
	LabelPill.attach(_smash_label)

func _update_smash_marker() -> void :
	if _smash_root == null or _game == null: return
	var actor = _game.get_human_actor() if _game.has_method("get_human_actor") else null
	var human = actor.posture.human_contact if actor != null and actor.posture != null else null
	var state: int = human.smash_state() if human != null and _game.game_state == 2 and not _game.match_over and not _game._tool_state_active() and _game.hud != null and _game.hud._gameplay_visible and not _game.hud._between_point_active else 0
	var spot: Dictionary = human.smash_spot if state > 0 else {}
	# In position the planned contact is the smash itself; show that point.
	if state == 2: spot = {"point": human.preparation_contact().point, "target_root": actor.global_position, "path": spot.get("path", PackedVector3Array())}
	smash_wanted = not spot.is_empty()
	# One player cue at a time (player_cue_priority.gd).
	if smash_wanted and CuePriority.current(_game) != CuePriority.SMASH: spot = {}
	_smash_root.visible = not spot.is_empty()
	if spot.is_empty():
		_smash_key = ""
		return
	var ready: bool = state == 2 or Vector2(spot.target_root.x - actor.global_position.x, spot.target_root.z - actor.global_position.z).length() < 0.3
	var color: Color = SMASH_READY_COLOR if ready else SMASH_MOVE_COLOR
	_smash_material.albedo_color = Color(color, 0.9)
	_smash_label.modulate = color
	var smash_text: String = "SMASH!" if ready else "SMASH HERE"
	if _smash_label.text != smash_text:
		_smash_label.text = smash_text
		LabelPill.fit(_smash_label)
	var point: Vector3 = spot.point
	var ground: = Vector3(spot.target_root.x, actor.COURT_FLOOR_Y + 0.02, spot.target_root.z)
	_smash_ring.global_position = ground
	_smash_dot.global_position = point
	_smash_label.global_position = point + Vector3(0, 0.38, 0)
	var key: String = "%v|%v|%d" % [point.snapped(Vector3.ONE * 0.02), ground.snapped(Vector3.ONE * 0.02), int(ready)]
	if key == _smash_key: return
	_smash_key = key
	_smash_lines.clear_surfaces()
	_smash_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	# Dashed post from the standing spot up to the contact point.
	var foot: = Vector3(point.x, ground.y, point.z)
	for dash in 8:
		_smash_lines.surface_add_vertex(foot.lerp(point, float(dash) / 8.0))
		_smash_lines.surface_add_vertex(foot.lerp(point, (float(dash) + 0.55) / 8.0))
	_smash_lines.surface_add_vertex(ground)
	_smash_lines.surface_add_vertex(foot)
	# Dashed incoming arc from the ball to the contact point.
	var path: PackedVector3Array = spot.get("path", PackedVector3Array())
	for index in range(0, path.size() - 1, 2):
		_smash_lines.surface_add_vertex(path[index])
		_smash_lines.surface_add_vertex(path[index + 1])
	_smash_lines.surface_end()

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
	var landing_text: String = "CHECK ARC" if estimated_warning else "AIM" if wall else "PERFECT TRAINING" if context.perfect else "ESTIMATED SPREAD"
	if landing_label.text != landing_text:
		landing_label.text = landing_text
		LabelPill.fit(landing_label)
