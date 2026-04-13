extends Node
class_name GameServe

## GameServe.gd - Serve subsystem child node.
## Owns all serve state: charge tracking, aim/arc offsets, serve execution,
## server-position fault detection, and serve-related UI updates.
##
## Parent (game.gd) passes references via setup() and delegates serve calls to
## this node. The game node retains game_state, scoring, and rally logic.

signal serve_launched(team: int)

# ── Serve charge state ─────────────────────────────────────────────────────────
var _serve_charge_time: float = 0.0
var _serve_is_charging: bool = false
var _service_fault_triggered: bool = false
var _serve_was_hit: bool = false

# ── Serve aim / arc intent (state lives here so it survives across serve cycles) ─
var _serve_aim_offset_x: float = 0.0
var _trajectory_arc_offset: float = 0.0

# ── External references (set via setup) ───────────────────────────────────────
var _game: Node                       # game.gd (parent)
var ball: RigidBody3D
var player_left: CharacterBody3D
var player_right: CharacterBody3D
var rally_scorer
var scoreboard_ui
var _ShotPhysicsRef: Script           # ShotPhysics class (renamed to avoid shadowing global class)

# ═══════════════════════════════════════════════════════════════════════════════
# Setup
# ═══════════════════════════════════════════════════════════════════════════════

func setup(
	game: Node,
	ball_node: RigidBody3D,
	p_left: CharacterBody3D,
	p_right: CharacterBody3D,
	scorer,
	ui,
	shot_phys: Script
) -> void:
	_game = game
	ball = ball_node
	player_left = p_left
	player_right = p_right
	rally_scorer = scorer
	scoreboard_ui = ui
	_ShotPhysicsRef = shot_phys

# ═══════════════════════════════════════════════════════════════════════════════
# Charge control
# ═══════════════════════════════════════════════════════════════════════════════

func start_charge() -> void:
	_serve_charge_time = 0.0
	_serve_is_charging = true

func tick_charge(delta: float) -> void:
	var MAX_SERVE_CHARGE_TIME := PickleballConstants.MAX_SERVE_CHARGE_TIME
	_serve_charge_time = minf(_serve_charge_time + delta, MAX_SERVE_CHARGE_TIME)
	_update_charge_ui(get_charge_ratio())

func get_charge_ratio() -> float:
	var MAX_SERVE_CHARGE_TIME := PickleballConstants.MAX_SERVE_CHARGE_TIME
	return clampf(_serve_charge_time / MAX_SERVE_CHARGE_TIME, 0.0, 1.0)

func is_charging() -> bool:
	return _serve_is_charging

func cleanup() -> void:
	_serve_charge_time = 0.0
	_serve_is_charging = false
	_serve_aim_offset_x = 0.0
	_trajectory_arc_offset = 0.0
	_service_fault_triggered = false
	_serve_was_hit = false

# ═══════════════════════════════════════════════════════════════════════════════
# Public accessors (for trajectory predictor and AI serve timer in game.gd)
# ═══════════════════════════════════════════════════════════════════════════════

func get_aim_offset() -> float:
	return _serve_aim_offset_x

func get_arc_offset() -> float:
	return _trajectory_arc_offset

func set_aim_offset(val: float) -> void:
	_serve_aim_offset_x = val

func set_arc_offset(val: float) -> void:
	_trajectory_arc_offset = val

# ═══════════════════════════════════════════════════════════════════════════════
# Release — stop charging and fire the serve
# ═══════════════════════════════════════════════════════════════════════════════

func release(charge_ratio: float) -> void:
	_serve_is_charging = false
	perform_serve(charge_ratio)

# ═══════════════════════════════════════════════════════════════════════════════
# Serve execution
# ═══════════════════════════════════════════════════════════════════════════════

func perform_serve(charge_ratio: float) -> void:
	var serving_team := _game.serving_team as int
	var server_pos: Vector3 = player_left.global_position if serving_team == 0 else player_right.global_position
	var zone_check: Dictionary = rally_scorer.check_server_position(server_pos)
	if not zone_check["valid"]:
		trigger_server_position_fault(zone_check["reason"])
		return

	_game.game_state = _game.GameState.SERVING
	_game.ball_has_bounced = false
	ball.reset_rally_state()
	ball.serve_team = serving_team

	if serving_team == 0:
		player_left.animate_serve_release(charge_ratio)
		ball.global_position = get_serve_launch_position(false)
		ball.linear_velocity = get_predicted_serve_velocity(charge_ratio, false)
		ball.last_hit_by = 0
		_log_serve(serving_team, ball.global_position, ball.linear_velocity, charge_ratio)
	else:
		player_right.animate_serve_release(charge_ratio)
		ball.global_position = get_serve_launch_position(true)
		ball.linear_velocity = get_predicted_serve_velocity(charge_ratio, true)
		ball.last_hit_by = 1
		_log_serve(serving_team, ball.global_position, ball.linear_velocity, charge_ratio)

	scoreboard_ui.set_state_text("Rally!")
	ball.audio_synth.play_serve_sound()
	scoreboard_ui.show_speed(ball.linear_velocity.length())
	scoreboard_ui.show_shot_type(_classify_trajectory(ball.linear_velocity))
	_game._awaiting_return = true  # using direct write; getter is_awaiting_return() exists for warning suppression
	_serve_was_hit = true
	serve_launched.emit(serving_team)

# ═══════════════════════════════════════════════════════════════════════════════
# Serve aim / velocity helpers
# ═══════════════════════════════════════════════════════════════════════════════

func get_serve_launch_position(is_red_side: bool) -> Vector3:
	if is_red_side:
		return player_right.global_position + Vector3(0.0, 0.8, 0.55)
	return player_left.global_position + Vector3(0.0, 0.8, -0.55)

func get_predicted_serve_velocity(charge_ratio: float, from_red_side: bool = false) -> Vector3:
	var MIN_SERVE_SPEED := PickleballConstants.MIN_SERVE_SPEED
	var MAX_SERVE_SPEED := PickleballConstants.MAX_SERVE_SPEED
	var _SERVE_AIM_MAX := PickleballConstants.SERVE_AIM_MAX
	var _SERVE_AIM_STEP := PickleballConstants.SERVE_AIM_STEP
	var _ARC_INTENT_MIN := PickleballConstants.ARC_INTENT_MIN
	var _ARC_INTENT_MAX := PickleballConstants.ARC_INTENT_MAX
	var _ARC_INTENT_STEP := PickleballConstants.ARC_INTENT_STEP

	var serve_speed: float = lerp(MIN_SERVE_SPEED, MAX_SERVE_SPEED, clampf(charge_ratio, 0.0, 1.0))
	var serve_origin: Vector3 = get_serve_launch_position(from_red_side)

	var total_score: int = _game.score_left + _game.score_right as int
	var serve_from_right: bool = (total_score % 2) == 0  # Even = serve from right side

	var target_x_offset: float = _serve_aim_offset_x

	if not from_red_side:
		# BLUE SERVE (serving to red's side at Z > 0)
		# Even score: stand RIGHT (X>0), serve to LEFT diagonal (X<0)
		# Odd score:  stand LEFT  (X<0), serve to RIGHT diagonal (X>0)
		if serve_from_right:
			target_x_offset = minf(_serve_aim_offset_x, -1.5)
		else:
			target_x_offset = maxf(_serve_aim_offset_x, 1.5)

		var target_z: float = -4.6  # Red's service box (negative Z)
		var target_position: Vector3 = Vector3(target_x_offset, 0.08, target_z)
		var target_dir: Vector3 = (target_position - serve_origin).normalized()
		target_dir.y = 0.32 + 0.22 * clampf(charge_ratio, 0.0, 1.0) + _trajectory_arc_offset
		return target_dir.normalized() * serve_speed
	else:
		# RED SERVE (serving to blue's side at Z < 0)
		# Even score: stand RIGHT (X<0 in world), serve to LEFT diagonal (X>0 in world)
		# Odd score:  stand LEFT  (X>0 in world), serve to RIGHT diagonal (X<0 in world)
		if serve_from_right:
			target_x_offset = maxf(_serve_aim_offset_x, 1.5)
		else:
			target_x_offset = minf(_serve_aim_offset_x, -1.5)

		var target_z: float = 4.6   # Blue's service box (positive Z)
		var target_position: Vector3 = Vector3(target_x_offset, 0.08, target_z)
		var target_dir: Vector3 = (target_position - serve_origin).normalized()
		target_dir.y = 0.32 + 0.22 * clampf(charge_ratio, 0.0, 1.0) + _trajectory_arc_offset
		return target_dir.normalized() * serve_speed

# ═══════════════════════════════════════════════════════════════════════════════
# Server position fault
# ═══════════════════════════════════════════════════════════════════════════════

func trigger_server_position_fault(reason: String = "") -> void:
	if _service_fault_triggered:
		return
	_service_fault_triggered = true

	var total_score: int = _game.score_left + _game.score_right as int
	var serve_from_right: bool = (total_score % 2) == 0
	var serving_team := _game.serving_team as int
	var server_name: String = "Blue" if serving_team == 0 else "Red"
	var expected_side: String = ""
	var actual_pos: Vector3 = player_left.global_position if serving_team == 0 else player_right.global_position
	var winner: int = 1 - serving_team

	if serving_team == 0:
		expected_side = "RIGHT (X>0)" if serve_from_right else "LEFT (X<0)"
	else:
		expected_side = "RIGHT (X<0)" if serve_from_right else "LEFT (X>0)"

	print("[FAULT] %s served from wrong zone | reason=%s expected=%s actual=(x:%.1f z:%.1f)" % [
		server_name, reason if reason != "" else "UNSPECIFIED",
		expected_side, snappedf(actual_pos.x, 0.1), snappedf(actual_pos.z, 0.1)
	])
	scoreboard_ui.show_fault("FAULT", reason)

	await get_tree().create_timer(1.0).timeout
	_game._on_point_scored(winner)

# ═══════════════════════════════════════════════════════════════════════════════
# Serve-aim keyboard controls (called from game.gd input handler)
# ═══════════════════════════════════════════════════════════════════════════════

func adjust_aim(direction: int) -> void:  # direction: -1=left, 1=right
	var SERVE_AIM_STEP := PickleballConstants.SERVE_AIM_STEP
	var SERVE_AIM_MAX := PickleballConstants.SERVE_AIM_MAX
	_serve_aim_offset_x = clampf(_serve_aim_offset_x + direction * SERVE_AIM_STEP, -SERVE_AIM_MAX, SERVE_AIM_MAX)

func adjust_arc(direction: int) -> void:  # direction: -1=lower, 1=raise
	var ARC_INTENT_STEP := PickleballConstants.ARC_INTENT_STEP
	var ARC_INTENT_MIN := PickleballConstants.ARC_INTENT_MIN
	var ARC_INTENT_MAX := PickleballConstants.ARC_INTENT_MAX
	_trajectory_arc_offset = clampf(_trajectory_arc_offset + direction * ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)

# ═══════════════════════════════════════════════════════════════════════════════
# UI helpers
# ═══════════════════════════════════════════════════════════════════════════════

func _update_charge_ui(charge_ratio: float) -> void:
	var percent: int = mini(100, maxi(0, int(round(charge_ratio * 100.0))))
	if _game.game_state == _game.GameState.WAITING:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\nPower: %d%%  Aim: %s  Arc: %s" % [percent, _get_aim_label(), _get_arc_label()])
	elif _game.game_state == _game.GameState.PLAYING:
		scoreboard_ui.set_state_text("Swing Power: %d%%  Arc: %s" % [percent, _get_arc_label()])

func update_waiting_ui() -> void:
	if _game.game_state == _game.GameState.WAITING and not _serve_is_charging:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [_format_serve_call(), _get_aim_label(), _get_arc_label()])

func _get_aim_label() -> String:
	if _serve_aim_offset_x < -0.2:
		return "Left"
	if _serve_aim_offset_x > 0.2:
		return "Right"
	return "Center"

func _get_arc_label() -> String:
	var ARC_INTENT_STEP := PickleballConstants.ARC_INTENT_STEP
	if is_zero_approx(_trajectory_arc_offset):
		return "Auto"
	if _trajectory_arc_offset > 0.0:
		return "High +%d" % int(round(_trajectory_arc_offset / ARC_INTENT_STEP))
	return "Low %d" % int(round(_trajectory_arc_offset / ARC_INTENT_STEP))

func _format_serve_call() -> String:
	var serving_team := _game.serving_team as int
	var score_left := _game.score_left as int
	var score_right := _game.score_right as int
	if serving_team == 0:
		return "Blue serves: %d - %d" % [score_left, score_right]
	else:
		return "Red serves: %d - %d" % [score_right, score_left]

func _classify_trajectory(vel: Vector3) -> String:
	var speed: float = vel.length()
	var horiz_speed: float = Vector2(vel.x, vel.z).length()
	var arc_ratio: float = 0.0
	if horiz_speed > 0.01:
		arc_ratio = vel.y / horiz_speed  # positive = upward arc

	# Thresholds tuned for pickleball (max ~20 m/s, gravity_scale 1.5)
	if speed < 7.0 and arc_ratio < 0.6:
		return "DROP"
	elif arc_ratio > 0.7:
		return "LOB"
	elif speed > 14.0 and arc_ratio < 0.35:
		return "FAST"
	else:
		return "NORMAL"

# ═══════════════════════════════════════════════════════════════════════════════
# Logging helper
# ═══════════════════════════════════════════════════════════════════════════════

func _log_serve(serving_team: int, pos: Vector3, vel: Vector3, charge: float) -> void:
	var score_left := _game.score_left as int
	var score_right := _game.score_right as int
	var total_score: int = score_left + score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var target_diag: String = "LEFT" if serve_from_right else "RIGHT"
	var server_name: String = "BLUE" if serving_team == 0 else "RED"
	print("[SERVE %s] pos=%s vel=%s charge=%s score=%d from_right=%s target=%s (X<0=left, X>0=right)" % [
		server_name, pos, vel, snappedf(charge, 0.01), total_score,
		serve_from_right, target_diag
	])
