class_name SwingE2EProbe extends Node

## End-to-end probe for GAP-X: paddle velocity → ball speed coupling.
##
## GAP-X is applied in two places:
##   game.gd:588-608  (human player rally hit)
##   player_ai_brain.gd:721-729  (AI player rally hit)
##
## The probe:
##   1. Fires a serve (for rally setup)
##   2. Waits for AI to return the ball
##   3. Detects the player's RETURN hit (GAP-X fires here)
##   4. Computes predicted speed from compute_shot_velocity + paddle contribution
##   5. Compares predicted vs measured
##
## Run via: game.run_swing_e2e_test() from the MCP run_script tool.

const MAX_TEST_DURATION := 20.0
const RESULT_PRINT_DELAY  := 2.5
const SPEED_THRESHOLD_FOR_HIT := 2.5   # ball must be moving this fast to be "in play"

var _game: Node
var _player: Node
var _ball: RigidBody3D

var _active: bool = false
var _t: float = 0.0
var _shots_fired: int = 0
var _max_shots: int = 3

# Serve state
var _serve_fired: bool = false
var _serve_has_returned: bool = false   # AI has hit the ball back
var _player_has_hit: bool = false

# Measurement state
var _pending_charge: float = 0.5
var _paddle_vel_at_hit: Vector3 = Vector3.ZERO
var _pre_hit_ball_vel: Vector3 = Vector3.ZERO
var _post_hit_ball_vel: Vector3 = Vector3.ZERO
var _hit_detected: bool = false
var _post_hit_timer: float = 0.0

var _results: Array[Dictionary] = []
var _complete: bool = false
var _quit_scheduled: bool = false

func begin_test(game: Node, player: Node, ball: Node) -> void:
	_game = game
	_player = player
	_ball = ball
	_active = true
	_t = 0.0
	_shots_fired = 0
	_serve_fired = false
	_serve_has_returned = false
	_player_has_hit = false
	_hit_detected = false
	_post_hit_timer = 0.0
	_results.clear()
	_complete = false
	_quit_scheduled = false

	print("")
	print("══════════════════════════════════════════════════════")
	print("  GAP-X E2E PROBE — swing coupling test")
	print("  PADDLE_VEL_TRANSFER = %.2f" % _player.hitting.PADDLE_VEL_TRANSFER)
	print("  PADDLE_VEL_SMOOTH_HALFLIFE = %.3f s" % _player.hitting.PADDLE_VEL_SMOOTH_HALFLIFE)
	print("══════════════════════════════════════════════════════")
	print("")


func _physics_process(delta: float) -> void:
	if not _active or _complete:
		return

	_t += delta

	# Stage 1: Fire serve if not yet fired
	if not _serve_fired:
		_fire_serve()
		return

	# Stage 2: Wait for AI to return the ball
	if _serve_fired and not _serve_has_returned:
		_watch_for_ai_return()
		return

	# Stage 3: Watch for player's return hit (GAP-X fires here)
	if _serve_has_returned and not _player_has_hit:
		_watch_for_player_hit(delta)
		return

	# Stage 4: After player hit, record post-hit velocity then finalize
	if _player_has_hit and not _hit_detected:
		# Capture post-hit ball velocity
		_post_hit_ball_vel = _ball.linear_velocity
		_hit_detected = true
		_post_hit_timer = 0.0
		var ball_speed: float = _post_hit_ball_vel.length()
		var shot_dir: Vector3 = _post_hit_ball_vel.normalized()
		var paddle_comp: float = _paddle_vel_at_hit.dot(shot_dir)
		var transfer_active: bool = absf(paddle_comp) > 0.5
		var speed_gain: float = paddle_comp * _player.hitting.PADDLE_VEL_TRANSFER if transfer_active else 0.0

		# Compute predicted speed from compute_shot_velocity
		var sp = _game.shot_physics if _game else null
		var predicted_speed: float = 0.0
		if sp and sp.has_method("compute_shot_velocity"):
			var pred_vel: Vector3 = sp.compute_shot_velocity(_ball.global_position, _pending_charge, 0, "", 0)
			predicted_speed = pred_vel.length()

		var result: Dictionary = {
			"charge": _pending_charge,
			"paddle_vel": _paddle_vel_at_hit,
			"paddle_comp": paddle_comp,
			"transfer_active": transfer_active,
			"speed_gain": speed_gain,
			"predicted_speed": predicted_speed,
			"measured_speed": ball_speed,
		}
		_results.append(result)
		_player_has_hit = false   # reset for potential next shot
		_serve_has_returned = false
		_serve_fired = false
		_shots_fired += 1

		print("[PROBE] → PLAYER HIT detected!")
		print("[PROBE]   charge=%.1f  paddle_comp=%.2f  transfer=%s  gain=%.3f m/s" % [
			_pending_charge, paddle_comp, transfer_active, speed_gain])
		print("[PROBE]   measured=%.2f m/s  predicted=%.2f m/s  Δ=%.2f" % [
			ball_speed, predicted_speed, ball_speed - predicted_speed])

		# Check if done
		if _shots_fired >= _max_shots:
			_schedule_complete()
		return

	# Stage 5: After hit detected, wait briefly then fire next serve
	if _hit_detected:
		_post_hit_timer += delta
		if _post_hit_timer > 1.5 and _shots_fired < _max_shots:
			_serve_fired = false
			_serve_has_returned = false
			_player_has_hit = false
			_hit_detected = false
			_post_hit_timer = 0.0
			_pending_charge = [0.3, 0.6, 0.9][_shots_fired % 3] as float

	# Timeout: if no contact after MAX_TEST_DURATION, finish
	if _t >= MAX_TEST_DURATION:
		_schedule_complete()


func _fire_serve() -> void:
	if _game == null or _ball == null:
		_schedule_complete()
		return

	# Ensure game is in a state where serve can fire — set to WAITING if needed
	if _game.game_state != _game.GameState.WAITING:
		_game.game_state = _game.GameState.WAITING

	# Drive the serve charge mechanism: inject charge and release.
	# Use PickleballConstants.MAX_SERVE_CHARGE_TIME (the const is inside
	# game_serve.gd's get_predicted_serve_velocity but game.gd re-exports it).
	var target_charge: float = _pending_charge
	var max_charge: float = PickleballConstants.MAX_SERVE_CHARGE_TIME
	if _game.game_serve:
		_game.game_serve._serve_charge_time = target_charge * max_charge
		_game.game_serve._serve_is_charging = true
		_game.game_serve.release(target_charge)

	print("[PROBE] Serve fired at charge=%.1f" % target_charge)
	_serve_fired = true


func _watch_for_ai_return() -> void:
	if _ball == null:
		return
	var ball_vel: Vector3 = _ball.linear_velocity
	var ball_speed: float = ball_vel.length()

	# AI returns ball: ball was going toward +Z (AI side) and is now coming back toward player at -Z
	# Detection: ball is moving toward player's side (ball_vel.z < 0) after the serve
	if ball_speed > SPEED_THRESHOLD_FOR_HIT and ball_vel.z < -1.0:
		_serve_has_returned = true
		print("[PROBE] AI returned ball — ball_vel.z=%.2f  speed=%.2f" % [ball_vel.z, ball_speed])


func _watch_for_player_hit(_delta: float) -> void:
	if _ball == null or _player == null:
		return

	var ball_vel: Vector3 = _ball.linear_velocity
	var ball_speed: float = ball_vel.length()
	var paddle_vel: Vector3 = _player.hitting.get_paddle_velocity() if _player.hitting else Vector3.ZERO

	# Detect player hit: ball was coming toward player (ball_vel.z > 0 toward player side,
	# which is -Z for player on blue side) and suddenly changed direction/speed
	# after paddle made contact.
	# Simpler detection: ball is now moving AWAY from player (ball_vel.z > 0 means
	# going toward +Z = away from blue player) at good speed, AND paddle was moving.
	if ball_speed > SPEED_THRESHOLD_FOR_HIT and ball_vel.z > 1.0 and paddle_vel.length() > 0.5:
		_paddle_vel_at_hit = paddle_vel
		_pre_hit_ball_vel = ball_vel
		_player_has_hit = true


func _schedule_complete() -> void:
	if _complete:
		return
	_complete = true
	_quit_scheduled = true
	await get_tree().create_timer(RESULT_PRINT_DELAY).timeout
	_print_results()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _print_results() -> void:
	print("")
	print("══════════════════════════════════════════════════════")
	print("  GAP-X E2E RESULTS (%d hits)" % _results.size())
	print("══════════════════════════════════════════════════════")
	print("")
	print("  %-6s  %-10s  %-10s  %-12s  %-10s  %-8s" % [
		"charge", "paddle_comp", "transfer?", "speed_gain", "predicted", "measured"])
	print("  " + "-".repeat(70))

	var total_gain: float = 0.0
	var n_transfer: int = 0
	for r in _results:
		var t_mark: String = "✓" if r.transfer_active else "—"
		print("  %-6.1f  %-10.2f  %-10s  %-12.3f  %-10.2f  %-8.2f" % [
			r.charge, r.paddle_comp, t_mark, r.speed_gain, r.predicted_speed, r.measured_speed])
		if r.transfer_active:
			total_gain += r.speed_gain
			n_transfer += 1

	print("")
	if n_transfer > 0:
		var avg_gain: float = total_gain / float(n_transfer)
		print("  Avg paddle speed gain (when active): %.3f m/s" % avg_gain)
		print("  Transfer scalar (PADDLE_VEL_TRANSFER): %.2f" % _player.hitting.PADDLE_VEL_TRANSFER)
		print("")
	print("  Note: if measured << predicted → coupling not working.")
	print("        if measured ≈ predicted + gain → coupling IS working.")
	print("══════════════════════════════════════════════════════")
	print("")
