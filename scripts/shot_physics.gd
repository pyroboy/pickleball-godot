extends RefCounted
class_name ShotPhysics

const _Ball = preload("res://scripts/ball.gd")

## ShotPhysics.gd - Encapsulates ball-hitting physics for pickleball.
## Calculates target velocities, spin injection, and iterative aero-trajectories.

const MIN_SWING_SPEED_MS := 7.0
const MAX_SWING_SPEED_MS := 22.35
const NET_CLEAR_MIN := 1.30

# Static dependencies (passed in)
var _player_left: Node
var _player_right: Node

func setup(_ball: Node, p_left: Node, p_right: Node) -> void:
	_player_left = p_left
	_player_right = p_right

func compute_shot_velocity(ball_pos: Vector3, charge_ratio: float, player_num: int, shot_type: String, ai_difficulty: int) -> Vector3:
	var speed_curve: float = pow(clamp(charge_ratio, 0.0, 1.0), 0.7)
	var target_speed: float = lerp(MIN_SWING_SPEED_MS, MAX_SWING_SPEED_MS, speed_curve)
	var grav: float = _Ball.get_effective_gravity()

	var target_z: float = 0.0
	var target_x: float = randf_range(-2.0, 2.0)
	
	if player_num == 0:
		var d_min: float = lerp(-3.0, -5.5, speed_curve)
		var d_max: float = lerp(-2.0, -2.5, speed_curve)
		target_z = randf_range(d_min, d_max)
	else:
		var ai_speed_scale: float = 1.0
		var d_min_near: float = 3.5
		var d_max_near: float = 4.5
		var d_min_far: float = 4.5
		var d_max_far: float = 6.0
		match ai_difficulty:
			0:  # EASY
				ai_speed_scale = 0.80
				d_min_near = 1.5; d_max_near = 3.0
				d_min_far = 2.5; d_max_far = 4.5
			1:  # MEDIUM
				ai_speed_scale = 0.85
				d_min_near = 2.5; d_max_near = 3.8
				d_min_far = 3.5; d_max_far = 5.0
			_:  # HARD
				ai_speed_scale = 1.0
		target_speed *= ai_speed_scale
		var d_min: float = lerp(d_min_near, d_min_far, speed_curve)
		var d_max: float = lerp(d_max_near, d_max_far, speed_curve)
		target_z = randf_range(d_min, d_max)
		
		if ai_difficulty >= 1:
			var opp_x: float = _player_left.global_position.x
			if opp_x > 0.5:
				target_x = randf_range(-2.5, -0.3)
			elif opp_x < -0.5:
				target_x = randf_range(0.3, 2.5)
			else:
				target_x = randf_range(1.0, 2.5) if randf() > 0.5 else randf_range(-2.5, -1.0)

	var vy_boost: float = 0.0
	var speed_floor: float = MIN_SWING_SPEED_MS * 0.6
	var speed_cap: float = MAX_SWING_SPEED_MS
	
	if shot_type != "":
		var dir_sign: float = -1.0 if player_num == 0 else 1.0
		match shot_type:
			"SMASH":
				target_speed = min(target_speed * 1.25, MAX_SWING_SPEED_MS)
				target_z = dir_sign * randf_range(5.0, 6.0)
				vy_boost = -1.5
			"FAST":
				target_speed = min(target_speed * 1.15, MAX_SWING_SPEED_MS)
				target_z = dir_sign * randf_range(5.0, 6.0)
				vy_boost = -0.5
			"VOLLEY":
				target_speed = target_speed * 0.95
				target_z = dir_sign * randf_range(3.5, 4.5)
				vy_boost = -0.4
			"DINK":
				speed_cap = 6.0; speed_floor = 3.5
				target_speed = clamp(target_speed, speed_floor, speed_cap)
				target_z = dir_sign * randf_range(0.3, 1.2)
				vy_boost = 0.8
			"DROP":
				speed_cap = 7.5; speed_floor = 4.0
				target_speed = clamp(target_speed, speed_floor, speed_cap)
				target_z = dir_sign * randf_range(1.0, 2.0)
				vy_boost = 0.6
			"LOB":
				target_speed = target_speed * 0.9
				target_z = dir_sign * randf_range(5.0, 6.0)
				vy_boost = 3.5
			"RETURN":
				target_speed = min(target_speed * 1.05, MAX_SWING_SPEED_MS)
				target_z = dir_sign * randf_range(3.5, 5.0)

	var dz: float = target_z - ball_pos.z
	var dx: float = target_x - ball_pos.x
	var hdist: float = sqrt(dz * dz + dx * dx)
	var ftime: float = clamp(hdist / target_speed * 1.05, 0.3, 1.8)
	var vx: float = dx / ftime
	var vz: float = dz / ftime
	var vy: float = (0.08 - ball_pos.y + 0.5 * grav * ftime * ftime) / ftime + vy_boost

	var net_sign: float = -1.0 if player_num == 0 else 1.0
	var drag_free_vel: Vector3 = Vector3(vx, vy, vz)
	var drag_free_apex_y: float = ball_pos.y + (vy * vy) / (2.0 * grav)
	
	var solve_omega: Vector3 = compute_shot_spin(shot_type, drag_free_vel, charge_ratio, player_num, -1)
	var target_pos_3d: Vector3 = Vector3(target_x, 0.08, target_z)
	var is_soft_shot: bool = shot_type == "DROP" or shot_type == "DINK"
	var needs_net_check: bool = (target_z * net_sign) > 0.0

	var best_vel: Vector3 = drag_free_vel
	var best_err: float = INF
	var best_clears_net: bool = false
	var cur_vel: Vector3 = drag_free_vel

	for _iter in range(6):
		var sim: Dictionary = simulate_shot_trajectory(ball_pos, cur_vel, solve_omega, grav, target_z, net_sign)
		var landing: Vector3 = sim["pos_at_target"]
		var y_net_this: float = sim["y_at_net"]
		var t_net_this: float = sim["t_at_net"]
		var clears_net: bool = (not needs_net_check) or (y_net_this != -INF and y_net_this >= NET_CLEAR_MIN)

		var err_x: float = target_pos_3d.x - landing.x
		var err_y: float = target_pos_3d.y - landing.y
		var total_err: float = sqrt(err_x * err_x + err_y * err_y)

		var is_better: bool = false
		if clears_net and not best_clears_net:
			is_better = true
		elif clears_net == best_clears_net and total_err < best_err:
			is_better = true
		if is_better:
			best_err = total_err; best_vel = cur_vel; best_clears_net = clears_net

		if clears_net and total_err < 0.15 and sim["crossed_target"]:
			break

		if needs_net_check and y_net_this != -INF and y_net_this < NET_CLEAR_MIN and t_net_this > 0.01:
			cur_vel.y += (NET_CLEAR_MIN - y_net_this) / t_net_this

		var actual_dx: float = landing.x - ball_pos.x
		var actual_dz: float = landing.z - ball_pos.z
		var actual_hdist: float = sqrt(actual_dx * actual_dx + actual_dz * actual_dz)
		if actual_hdist > 0.1:
			var h_scale: float = clampf(lerpf(1.0, hdist / actual_hdist, 0.7), 0.5, 2.0)
			cur_vel.x *= h_scale; cur_vel.z *= h_scale

		var t_flight: float = maxf(sim["t_total"], 0.1)
		var vy_damping: float = 0.4 if is_soft_shot else 0.7
		if not (needs_net_check and y_net_this != -INF and y_net_this < NET_CLEAR_MIN):
			cur_vel.y += err_y / t_flight * vy_damping

	var solved_vel: Vector3 = best_vel
	if needs_net_check and not best_clears_net:
		var t_net_dragfree: float = maxf(absf(ball_pos.z) / maxf(absf(drag_free_vel.z), 0.1), 0.1)
		var vy_floor: float = (NET_CLEAR_MIN - ball_pos.y + 0.5 * grav * t_net_dragfree * t_net_dragfree) / t_net_dragfree
		solved_vel = drag_free_vel
		solved_vel.y = maxf(solved_vel.y, vy_floor * 1.15)
	elif best_err > 1.5:
		solved_vel = drag_free_vel
		solved_vel.y = maxf(best_vel.y, drag_free_vel.y)
	
	if is_soft_shot and best_clears_net:
		var cur_apex_y: float = ball_pos.y + (solved_vel.y * solved_vel.y) / (2.0 * grav)
		if absf(cur_apex_y - drag_free_apex_y) / maxf(drag_free_apex_y, 0.01) > 0.30:
			solved_vel.y = lerpf(drag_free_vel.y, solved_vel.y, 0.3)

	if solved_vel.length() > speed_cap:
		solved_vel = solved_vel.normalized() * speed_cap
	if solved_vel.length() < speed_floor:
		solved_vel = solved_vel.normalized() * speed_floor
	return solved_vel

func compute_shot_spin(shot_type: String, vel: Vector3, charge_ratio: float, _player_num: int, posture: int = -1) -> Vector3:
	var travel: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if travel.length() < 0.1:
		return Vector3.ZERO
	# Topspin axis = UP × travel (right-hand rule).
	var topspin_axis: Vector3 = Vector3.UP.cross(travel.normalized())
	var side_axis: Vector3 = Vector3.UP

	var topspin_mag: float = 0.0
	match shot_type:
		"SMASH": topspin_mag = 55.0
		"FAST": topspin_mag = 45.0
		"LOB": topspin_mag = 18.0
		"RETURN": topspin_mag = 22.0
		"GROUNDSTROKE", "NORMAL", "": topspin_mag = 25.0
		"VOLLEY": topspin_mag = -10.0
		"DROP": topspin_mag = -20.0
		"DINK": topspin_mag = -12.0

	var charge_gain: float = lerpf(0.55, 1.25, clamp(charge_ratio, 0.0, 1.0))
	topspin_mag *= charge_gain

	var sidespin_mag: float = 0.0
	if posture >= 0:
		# BACKHAND=2, WIDE_BACKHAND=11, LOW_BACKHAND=7, MID_LOW_BACKHAND=14, LOW_WIDE_BACKHAND=19, MID_LOW_WIDE_BACKHAND=17, CHARGE_BACKHAND=9
		var is_backhand: bool = posture in [2, 11, 7, 14, 19, 17, 9]
		var lateral_sign: float = signf(vel.x)
		sidespin_mag = lateral_sign * (8.0 if not is_backhand else -6.0) * charge_gain

	return topspin_axis * topspin_mag + side_axis * sidespin_mag

func compute_sweet_spot_spin(ball_pos: Vector3, paddle_pos: Vector3, velocity: Vector3) -> Vector3:
	var vel_mag: float = velocity.length()
	if vel_mag < 0.1: return Vector3.ZERO
	var offset: Vector3 = ball_pos - paddle_pos
	var travel_dir: Vector3 = velocity.normalized()
	var offset_in_plane: Vector3 = offset - travel_dir * (offset.dot(travel_dir))
	var offset_mag: float = offset_in_plane.length()
	if offset_mag < 0.03: return Vector3.ZERO
	var torque_axis: Vector3 = offset_in_plane.cross(travel_dir)
	var lever: float = clamp((offset_mag - 0.03) / 0.08, 0.0, 1.0)
	var mag: float = lever * vel_mag * 2.5
	return torque_axis.normalized() * mag

## GAP-15: off-center contact reduces ball speed.
## Sweet spot radius ~0.04m (4cm). Edge penalty ramps from 0.04m to 0.12m (40% speed loss at edge).
func compute_sweet_spot_speed(ball_pos: Vector3, paddle_pos: Vector3, velocity: Vector3) -> float:
	var offset := paddle_pos - ball_pos
	var travel_dir := velocity.normalized() if velocity.length_squared() > 0.01 else Vector3.FORWARD
	var offset_in_plane := offset - travel_dir * offset.dot(travel_dir)
	var offset_mag := offset_in_plane.length()
	const SWEET_SPOT_RADIUS := 0.04   # 4cm center zone — full speed
	const EDGE_RADIUS := 0.12           # 12cm — 40% speed reduction at extreme edge
	if offset_mag <= SWEET_SPOT_RADIUS:
		return 1.0  # center hit — no penalty
	var penalty := clampf((offset_mag - SWEET_SPOT_RADIUS) / (EDGE_RADIUS - SWEET_SPOT_RADIUS), 0.0, 0.4)
	return 1.0 - penalty

func simulate_shot_trajectory(start_pos: Vector3, vel: Vector3, omega: Vector3, grav: float, target_z: float, net_sign: float) -> Dictionary:
	var pos: Vector3 = start_pos
	var cur_vel: Vector3 = vel
	var cur_omega: Vector3 = omega
	var dt: float = 1.0 / 120.0
	var max_steps: int = 200
	var y_at_net: float = -INF
	var t_at_net: float = -1.0
	var apex_y: float = start_pos.y
	var crossed_target: bool = false
	var pos_at_target: Vector3 = start_pos
	var t_total: float = 0.0
	var prev_pos: Vector3 = pos
	var prev_z_rel: float = (start_pos.z - target_z) * net_sign

	for _step in range(max_steps):
		prev_pos = pos
		var stepped: Array = _Ball.predict_aero_step(pos, cur_vel, cur_omega, grav, dt)
		pos = stepped[0]
		cur_vel = stepped[1]
		cur_omega = stepped[2]
		t_total += dt
		apex_y = maxf(apex_y, pos.y)
		if y_at_net == -INF and ((prev_pos.z > 0.0 and pos.z <= 0.0) or (prev_pos.z < 0.0 and pos.z >= 0.0)):
			var t_frac: float = 0.0; var dz: float = pos.z - prev_pos.z
			if absf(dz) > 0.0001: t_frac = (0.0 - prev_pos.z) / dz
			y_at_net = lerpf(prev_pos.y, pos.y, clampf(t_frac, 0.0, 1.0))
			t_at_net = t_total - dt + dt * clampf(t_frac, 0.0, 1.0)
		var z_rel: float = (pos.z - target_z) * net_sign
		if prev_z_rel < 0.0 and z_rel >= 0.0:
			var tz_frac: float = 0.0; var dz_target: float = z_rel - prev_z_rel
			if absf(dz_target) > 0.0001: tz_frac = -prev_z_rel / dz_target
			pos_at_target = prev_pos.lerp(pos, clampf(tz_frac, 0.0, 1.0))
			crossed_target = true; break
		prev_z_rel = z_rel
		if pos.y < 0.0:
			pos_at_target = pos; break
	if not crossed_target: pos_at_target = pos
	return { "crossed_target": crossed_target, "pos_at_target": pos_at_target, "y_at_net": y_at_net, "t_at_net": t_at_net, "t_total": t_total, "apex_y": apex_y }
