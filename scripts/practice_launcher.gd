extends Node
class_name PracticeLauncher
const _Ball = preload("res://scripts/ball.gd")

## PracticeLauncher.gd - Logic for the training/practice ball launcher.
## Handles spawning balls from realistic court zones with USAPA-spec trajectory bundles.

const PRACTICE_LOOP_INTERVAL := 1.7

# Dependencies
var _game: Node
var _ball: RigidBody3D
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _ball_physics_probe: Node

# State
var is_active: bool = false
var loop_enabled: bool = false
var auto_hit_enabled: bool = true

var _loop_timer: float = 0.0
var _loop_vel: Vector3 = Vector3.ZERO
var _loop_origin: Vector3 = Vector3.ZERO
var _auto_hit_done: bool = false

# Temporary launch parameters for spin mode selection
var _launch_spin_min: float = 0.0
var _launch_spin_max: float = 0.0
var _launch_spin_mode_pref: int = -1

func setup(game: Node, ball: RigidBody3D, p_left: CharacterBody3D, p_right: CharacterBody3D, probe: Node) -> void:
	_game = game
	_ball = ball
	_player_left = p_left
	_player_right = p_right
	_ball_physics_probe = probe
	if OS.has_environment("GODOT_TEST_AUTO_LAUNCH"):
		launch_ball()

func _process(delta: float) -> void:
	if not loop_enabled or not _ball:
		return
	if _ball.is_time_frozen():
		return
	
	_loop_timer += delta
	if _loop_timer >= PRACTICE_LOOP_INTERVAL:
		_loop_timer = 0.0
		_ball.global_position = _loop_origin
		_ball.linear_velocity = _loop_vel
		_ball.angular_velocity = Vector3.ZERO # Reset spin for loop consistency
		_auto_hit_done = false
		
		if _ball_physics_probe:
			_ball_physics_probe.begin_probe(_ball)

	if auto_hit_enabled and not _auto_hit_done and _ball and _player_left:
		# Auto-hit logic (simplified proxy for reaction testing)
		var dist = _player_left.global_position.distance_to(_ball.global_position)
		if dist < 1.2 and _ball.global_position.z > 0.0:
			_auto_hit_done = true
			# Potential signal to game.gd to perform a swing?
			# For now just marking it done.

func launch_ball() -> void:
	if not _ball: return
	
	is_active = true
	_ball.reset_rally_state()
	_ball.is_in_play = true
	_ball.last_hit_by = 1 # Red hit it
	
	var blue_pos = _player_left.global_position
	var zone_roll = randf()
	var launch_x: float; var launch_z: float; var launch_y: float; var zone_name: String
	
	if zone_roll < 0.50:
		launch_x = randf_range(-2.8, 2.8); launch_z = randf_range(-6.5, -4.8); launch_y = randf_range(0.8, 1.5)
		zone_name = "BASELINE"
	elif zone_roll < 0.70:
		launch_x = randf_range(-2.6, 2.6); launch_z = randf_range(-4.8, -3.0); launch_y = randf_range(0.8, 1.4)
		zone_name = "MIDCOURT"
	elif zone_roll < 0.90:
		launch_x = randf_range(-2.4, 2.4); launch_z = randf_range(-2.8, -1.9); launch_y = randf_range(0.5, 1.1)
		zone_name = "NEAR-KITCHEN"
	else:
		launch_x = randf_range(-2.2, 2.2); launch_z = randf_range(-1.7, -0.3); launch_y = randf_range(0.35, 0.85)
		zone_name = "IN-KITCHEN"
	
	_ball.global_position = Vector3(launch_x, launch_y, launch_z)
	
	var target_x = clampf(blue_pos.x + randf_range(-0.8, 0.8), -2.80, 2.80)
	var target_z = clampf(blue_pos.z + randf_range(-0.5, 0.5), 0.20, 6.45)
	
	var shot_type: String = "RALLY"
	var shot_roll = randf()
	match zone_name:
		"BASELINE":
			if shot_roll < 0.30: shot_type = "RALLY"
			elif shot_roll < 0.48: shot_type = "DRIVE"
			elif shot_roll < 0.60: shot_type = "TOPSPIN_ROLL"
			elif shot_roll < 0.75: shot_type = "LOB_DEFENSIVE"
			elif shot_roll < 0.85: shot_type = "LOB_OFFENSIVE"
			elif shot_roll < 0.93: shot_type = "SLICE"
			else: shot_type = "KICK_SERVE"
		"MIDCOURT":
			if shot_roll < 0.25: shot_type = "DRIVE"
			elif shot_roll < 0.45: shot_type = "RALLY"
			elif shot_roll < 0.60: shot_type = "TOPSPIN_ROLL"
			elif shot_roll < 0.75: shot_type = "DROP"
			elif shot_roll < 0.88: shot_type = "LOB_DEFENSIVE"
			elif shot_roll < 0.96: shot_type = "SLICE"
			else: shot_type = "POPUP"
		"NEAR-KITCHEN":
			if shot_roll < 0.35: shot_type = "DROP"
			elif shot_roll < 0.55: shot_type = "DINK"
			elif shot_roll < 0.75: shot_type = "SPEEDUP"
			elif shot_roll < 0.85: shot_type = "LOB_OFFENSIVE"
			elif shot_roll < 0.93: shot_type = "POPUP"
			else: shot_type = "KICK_SERVE"
		"IN-KITCHEN", _:
			if shot_roll < 0.55: shot_type = "DINK"
			elif shot_roll < 0.75: shot_type = "DROP"
			elif shot_roll < 0.85: shot_type = "SPEEDUP"
			elif shot_roll < 0.92: shot_type = "POPUP"
			elif shot_roll < 0.98: shot_type = "LOB_DEFENSIVE"
			else: shot_type = "KICK_SERVE"

	match shot_type:
		"DRIVE", "TOPSPIN_ROLL":
			target_x = clampf(blue_pos.x + randf_range(-1.6, 1.6), -2.80, 2.80)
			target_z = randf_range(5.2, 6.40)
		"RALLY":
			target_x = clampf(blue_pos.x + randf_range(-1.4, 1.4), -2.80, 2.80)
			target_z = randf_range(4.2, 6.10)
		"DROP", "DINK":
			target_x = clampf(blue_pos.x + randf_range(-1.2, 1.2), -2.60, 2.60)
			target_z = randf_range(2.10, 3.40)
		"LOB_DEFENSIVE", "LOB_OFFENSIVE":
			target_x = clampf(blue_pos.x + randf_range(-1.5, 1.5), -2.70, 2.70)
			target_z = randf_range(5.5, 6.30)
		"SPEEDUP":
			target_x = clampf(blue_pos.x + randf_range(-0.6, 0.6), -2.70, 2.70)
			target_z = clampf(blue_pos.z + randf_range(-0.8, 0.5), 2.20, 6.20)
		"SLICE":
			target_x = clampf(blue_pos.x + randf_range(-1.4, 1.4), -2.80, 2.80)
			target_z = randf_range(3.5, 5.80)
		"KICK_SERVE":
			target_x = clampf(blue_pos.x + randf_range(-1.8, 1.8), -2.60, 2.60)
			target_z = randf_range(5.4, 6.30)

	var launch_angle_deg: float
	_launch_spin_min = 10.0; _launch_spin_max = 20.0; _launch_spin_mode_pref = -1
	match shot_type:
		"DRIVE":
			launch_angle_deg = randf_range(3.0, 11.0); _launch_spin_min = 18.0; _launch_spin_max = 32.0; _launch_spin_mode_pref = 0
		"RALLY":
			launch_angle_deg = randf_range(10.0, 20.0); _launch_spin_min = 10.0; _launch_spin_max = 22.0; _launch_spin_mode_pref = 0
		"TOPSPIN_ROLL":
			launch_angle_deg = randf_range(12.0, 24.0); _launch_spin_min = 28.0; _launch_spin_max = 42.0; _launch_spin_mode_pref = 0
		"DROP":
			launch_angle_deg = randf_range(22.0, 34.0); _launch_spin_min = 5.0; _launch_spin_max = 14.0; _launch_spin_mode_pref = 1
		"DINK":
			launch_angle_deg = randf_range(18.0, 30.0); _launch_spin_min = 3.0; _launch_spin_max = 10.0; _launch_spin_mode_pref = 0
		"LOB_DEFENSIVE":
			launch_angle_deg = randf_range(42.0, 55.0); _launch_spin_min = 4.0; _launch_spin_max = 12.0; _launch_spin_mode_pref = 0
		"LOB_OFFENSIVE":
			launch_angle_deg = randf_range(33.0, 45.0); _launch_spin_min = 22.0; _launch_spin_max = 38.0; _launch_spin_mode_pref = 0
		"POPUP":
			launch_angle_deg = randf_range(55.0, 75.0); _launch_spin_min = 2.0; _launch_spin_max = 10.0; _launch_spin_mode_pref = 1
			target_x = blue_pos.x + randf_range(-1.2, 1.2); target_z = randf_range(1.9, 3.5)
		"SPEEDUP":
			launch_angle_deg = randf_range(6.0, 14.0); _launch_spin_min = 20.0; _launch_spin_max = 34.0; _launch_spin_mode_pref = 0
		"SLICE":
			launch_angle_deg = randf_range(8.0, 20.0); _launch_spin_min = 28.0; _launch_spin_max = 44.0; _launch_spin_mode_pref = 1
		"KICK_SERVE":
			launch_angle_deg = randf_range(14.0, 26.0); _launch_spin_min = 25.0; _launch_spin_max = 40.0; _launch_spin_mode_pref = 2
		_:
			launch_angle_deg = randf_range(10.0, 20.0)

	var grav = _Ball.get_effective_gravity()
	var dx = target_x - _ball.global_position.x; var dz = target_z - _ball.global_position.z; var hdist = sqrt(dx * dx + dz * dz)
	
	const MAX_LAUNCH_V: float = 18.0
	var target_y: float = 0.5
	var drop_D: float = launch_y - target_y
	var angle: float; var cos_a: float; var sin_a: float; var v_sq: float; var _feasible: bool = false
	var retries: int = 0
	while retries < 12:
		angle = deg_to_rad(launch_angle_deg); cos_a = cos(angle); sin_a = sin(angle); var tan_a = tan(angle)
		var denom = cos_a * cos_a * (drop_D + hdist * tan_a)
		if denom < 0.01: denom = 0.01
		v_sq = 0.5 * grav * hdist * hdist / denom
		if v_sq <= MAX_LAUNCH_V * MAX_LAUNCH_V and v_sq >= 1.0:
			_feasible = true; break
		if launch_angle_deg < 45.0: launch_angle_deg = minf(launch_angle_deg + 3.0, 45.0)
		else: launch_angle_deg = minf(launch_angle_deg + 2.0, 70.0)
		retries += 1
	
	var v_total = clampf(sqrt(maxf(v_sq, 1.0)), 3.0, MAX_LAUNCH_V)
	var vx = (dx / hdist if hdist > 0.01 else 0.0) * v_total * cos_a
	var vz = (dz / hdist if hdist > 0.01 else 0.0) * v_total * cos_a
	var vy = v_total * sin_a

	if vz > 0.01:
		var t_net = (0.0 - _ball.global_position.z) / vz
		if t_net > 0.0:
			var y_at_net = launch_y + vy * t_net - 0.5 * grav * t_net * t_net
			if y_at_net < 1.05: vy += (1.15 - y_at_net) / t_net

	_ball.linear_velocity = Vector3(vx, vy, vz)
	
	# Spin mode selection
	var h_vel = Vector3(vx, 0, vz)
	var mode_roll = randf()
	var spin_mode = 0
	if h_vel.length() > 0.1:
		if _launch_spin_mode_pref >= 0:
			if mode_roll < 0.80: spin_mode = _launch_spin_mode_pref
			elif mode_roll < 0.92: spin_mode = 3
			else: spin_mode = (_launch_spin_mode_pref + 1 + (randi() % 2)) % 4
		else:
			if mode_roll < 0.5: spin_mode = 0
			elif mode_roll < 0.8: spin_mode = 1
			else: spin_mode = 2

		var roll_axis = Vector3.UP.cross(h_vel.normalized())
		var side_axis = Vector3.UP
		var base_mag = randf_range(_launch_spin_min, _launch_spin_max) if _launch_spin_mode_pref >= 0 else 15.0
		
		match spin_mode:
			0: _ball.angular_velocity = roll_axis * base_mag
			1: _ball.angular_velocity = -roll_axis * base_mag
			2: _ball.angular_velocity = side_axis * base_mag * (1.0 if randf() > 0.5 else -1.0)
			3:
				var topspin_sign = 1.0 if randf() > 0.2 else -1.0
				var curl_sign = 1.0 if randf() > 0.5 else -1.0
				_ball.angular_velocity = roll_axis * base_mag * 0.7 * topspin_sign + side_axis * base_mag * 0.5 * curl_sign

	if _game.has_method("_set_game_state"):
		_game._set_game_state(1) # GameState.PLAYING (or equivalent)
	
	if _player_right:
		_player_right.ai_ball_bounced_on_side = false
		
	if _ball_physics_probe:
		_ball_physics_probe.begin_probe(_ball)
		
	if _player_left and _player_left.posture:
		_player_left.posture.reset_incoming_highlight()
	if _player_left and _player_left.debug_visual:
		_player_left.debug_visual._traj_log_pending = true

	if loop_enabled:
		_loop_origin = _ball.global_position
		_loop_vel = _ball.linear_velocity
		_auto_hit_done = false

func toggle_loop() -> void:
	loop_enabled = not loop_enabled
	_loop_timer = 0.0
	if loop_enabled:
		launch_ball()
	print("[PRACTICE-LOOP] %s" % ("ON" if loop_enabled else "OFF"))

func toggle_auto_hit() -> void:
	auto_hit_enabled = not auto_hit_enabled
	print("[PRACTICE-AUTO-HIT] %s" % ("ON" if auto_hit_enabled else "OFF"))
