class_name GameTrajectory
extends Node

const _Flight = preload("res://scripts/ball_flight_predictor.gd")

## GameTrajectory - Owns all trajectory visualization for the game.
## Extracted from game.gd (trajectory predictor sections) and serve_trajectory.gd.
## Handles serve trajectory drawing, aim/arc labels, red target marker, and ball landing prediction.

# References to game and ball
var _game: Node = null
var _ball: RigidBody3D = null

# Trajectory mesh visuals
var trajectory_mesh_instance: MeshInstance3D
var trajectory_mesh: ImmediateMesh
var trajectory_material: StandardMaterial3D

# Red AI target marker (shown during Red serve aiming)
var target_marker: MeshInstance3D

# Cache key to avoid recomputing unchanged trajectories
var _last_trajectory_key: String = ""

# Serve aim/arc offsets (owned externally, passed in via update)
var _serve_aim_offset_x: float = 0.0
var _trajectory_arc_offset: float = 0.0

# Constants mirrored from PickleballConstants for standalone use
const MAX_SERVE_CHARGE_TIME: float = 1.5


## Setup the trajectory visualizer with references to game and ball.
func setup(game: Node, ball: RigidBody3D) -> void:
	_game = game
	_ball = ball
	_create_visuals()


## Main update called each frame.
## game_state: int (0=WAITING, 1=SERVING, 2=PLAYING, 3=POINT_SCORED) — mirrors GameState enum
## serving_team: int (0=Blue/PlayerLeft, 1=Red/PlayerRight)
## serve_aim_offset_x: float — lateral aim offset for serve
## trajectory_arc_offset: float — arc adjustment for serve
## serve_charge_time: float — how long serve has been charging
## player_left_pos: Vector3 — world position of PlayerLeft
## player_right_pos: Vector3 — world position of PlayerRight
func update(game_state: int, serving_team: int, serve_aim_offset_x: float,
		trajectory_arc_offset: float, serve_charge_time: float,
		player_left_pos: Vector3, player_right_pos: Vector3) -> void:
	
	_serve_aim_offset_x = serve_aim_offset_x
	_trajectory_arc_offset = trajectory_arc_offset
	
	if _ball == null or serve_charge_time <= 0.0:
		clear()
		_last_trajectory_key = ""
		return
	
	var charge_ratio: float = serve_charge_time / MAX_SERVE_CHARGE_TIME
	var start_position: Vector3 = _ball.global_position
	var start_velocity: Vector3 = Vector3.ZERO
	var start_angular: Vector3 = _ball.angular_velocity
	
	# Cache key: only recompute when inputs change
	var cache_key: String = ""
	
	# WAITING state — serve is charging
	if game_state == 0:  # GameState.WAITING
		if serving_team == 0:
			# Blue serving (PlayerLeft at +Z side)
			start_position = _get_serve_launch_position(false, player_left_pos)
			start_velocity = _get_predicted_serve_velocity(charge_ratio, false)
			if target_marker:
				target_marker.visible = false
			cache_key = "s0_%f_%f_%f_%v" % [charge_ratio, serve_aim_offset_x, trajectory_arc_offset, player_left_pos]
		else:
			# Red serving (PlayerRight at -Z side)
			start_position = _get_serve_launch_position(true, player_right_pos)
			start_velocity = _get_predicted_serve_velocity(charge_ratio, true)
			_update_red_target_marker()
			cache_key = "s1_%f_%f_%f_%v" % [charge_ratio, serve_aim_offset_x, trajectory_arc_offset, player_right_pos]
		start_angular = Vector3.ZERO
	
	# PLAYING state — rally trajectory from ball velocity + player impulse
	elif game_state == 2:  # GameState.PLAYING
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
	
	# Skip recomputation if cache matches
	if cache_key == _last_trajectory_key and trajectory_mesh_instance.visible:
		return
	_last_trajectory_key = cache_key
	
	_draw_trajectory(start_position, start_velocity, start_angular)


## Clear all trajectory visuals.
func clear() -> void:
	if trajectory_mesh == null or trajectory_mesh_instance == null:
		return
	trajectory_mesh.clear_surfaces()
	trajectory_mesh_instance.visible = false
	if target_marker != null:
		target_marker.visible = false


## Returns aim direction label: "Left", "Center", or "Right"
func get_aim_label() -> String:
	if _serve_aim_offset_x < -0.2:
		return "Left"
	if _serve_aim_offset_x > 0.2:
		return "Right"
	return "Center"


## Returns arc label: "Auto", "High +N", or "Low N"
func get_arc_label() -> String:
	if is_zero_approx(_trajectory_arc_offset):
		return "Auto"
	if _trajectory_arc_offset > 0.0:
		return "High +" + str(int(round(_trajectory_arc_offset / 0.05)))
	return "Low " + str(int(round(_trajectory_arc_offset / 0.05)))


## Applies arc intent offset to a shot impulse vector.
func apply_arc_intent_to_impulse(shot_impulse: Vector3) -> Vector3:
	if is_zero_approx(_trajectory_arc_offset):
		return shot_impulse
	var adjusted_impulse: Vector3 = shot_impulse
	adjusted_impulse.y += _trajectory_arc_offset * 3.6
	return adjusted_impulse


## Creates trajectory mesh and red target marker visuals.
func _create_visuals() -> void:
	# Trajectory mesh
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
	
	# Red AI target marker
	target_marker = MeshInstance3D.new()
	target_marker.name = "RedTargetMarker"
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.25
	marker_mesh.height = 0.5
	target_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.35, 0.35, 0.8)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	marker_mat.emission_energy_multiplier = 1.2
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_marker.material_override = marker_mat
	target_marker.visible = false
	add_child(target_marker)


## Positions the red sphere marker showing where Red AI is aiming their serve.
func _update_red_target_marker() -> void:
	if target_marker == null or _game == null:
		return
	
	var score_left: int = _game.score_left
	var score_right: int = _game.score_right
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var target_x: float
	
	if serve_from_right:
		# Even: Red at X<0, serves to X>0 (CYAN box)
		target_x = maxf(_serve_aim_offset_x, 1.5)
	else:
		# Odd: Red at X>0, serves to X<0 (LIME box)
		target_x = minf(_serve_aim_offset_x, -1.5)
	
	# Target is in Blue's service box at Z = 4.6
	target_marker.global_position = Vector3(target_x, 0.1, 4.6)
	target_marker.visible = true


## Computes the serve launch position from a player's body root (not paddle).
## Using body root keeps the position animation-independent during serve charge.
func _get_serve_launch_position(is_red_side: bool, player_pos: Vector3) -> Vector3:
	if is_red_side:
		return player_pos + Vector3(0.0, 0.8, 0.55)
	return player_pos + Vector3(0.0, 0.8, -0.55)


## Predicts the velocity of a serve at the given charge ratio.
func _get_predicted_serve_velocity(charge_ratio: float, from_red_side: bool) -> Vector3:
	return _game.game_serve.get_predicted_serve_velocity(charge_ratio, from_red_side)


## Draws the trajectory arc using ImmediateMesh with dashed line effect.
func _draw_trajectory(start_position: Vector3, start_velocity: Vector3, start_angular: Vector3 = Vector3.ZERO) -> void:
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, trajectory_material)
	var flight: Dictionary = _Flight.trace(start_position, start_velocity, start_angular, 3.0, 1, true)
	for sample in flight["samples"]:
		trajectory_mesh.surface_add_vertex(sample["pos"] + Vector3(0.0, 0.03, 0.0))
	trajectory_mesh.surface_end()
	trajectory_mesh_instance.visible = true


## Predicts where the ball will land on the court.
## Returns Vector3.INF if ball won't land within look-ahead window.
func _predict_ball_landing_pos() -> Vector3:
	if _ball == null:
		return Vector3.INF
	var flight: Dictionary = _Flight.trace(_ball.global_position, _ball.linear_velocity,
		_ball.angular_velocity, 3.0, 1, true)
	return flight["first_bounce"] if flight["first_bounce_time"] >= 0.0 else Vector3.INF


## Returns true if the given position is outside court boundaries.
func _is_landing_out_of_bounds(pos: Vector3) -> bool:
	if pos == Vector3.INF:
		return false
	# Court length: 13.4, width: 6.1
	var half_len: float = 6.7   # COURT_LENGTH / 2.0
	var half_wid: float = 3.05  # COURT_WIDTH / 2.0
	return pos.z > half_len or pos.z < -half_len or pos.x < -half_wid or pos.x > half_wid
