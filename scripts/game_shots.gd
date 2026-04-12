class_name GameShots
extends Node
## Owns shot classification, speedometer, and out-indicator UI.
## Consumed by game.gd for swing decisions and rally scoring.

# Exposed state — consumed by game.gd's _perform_player_swing
var _pending_shot_type: String = ""

# Internal rally state
var _awaiting_return: bool = false

# Injected dependencies
var _ball: RigidBody3D = null
var _player_left: CharacterBody3D = null
var _player_right: CharacterBody3D = null
var _scoreboard_ui: Node = null

# Court geometry (refreshed in setup / update)
var _court_half_len: float = 0.0
var _court_half_wid: float = 0.0
var _nvz: float = 0.0

# Out indicator — cached to avoid redundant UI calls
var _out_shown: bool = false


## Inject game references. Call once after dependencies are ready.
func setup(ball: RigidBody3D, player_left: CharacterBody3D, player_right: CharacterBody3D,
		scoreboard_ui: Node) -> void:
	_ball = ball
	_player_left = player_left
	_player_right = player_right
	_scoreboard_ui = scoreboard_ui
	_refresh_court_constants()


func _refresh_court_constants() -> void:
	_court_half_len = PickleballConstants.COURT_LENGTH / 2.0
	_court_half_wid = PickleballConstants.COURT_WIDTH / 2.0
	_nvz = PickleballConstants.NON_VOLLEY_ZONE


## Called when ball bounces (from ball.bounced signal wired in game.gd).
func on_ball_bounced(_bounce_pos: Vector3) -> void:
	_awaiting_return = true


## Called when any paddle hits the ball (wired from game.gd's paddle hit callbacks).
func on_paddle_hit(player_num: int) -> void:
	_awaiting_return = false


## Per-frame update. Returns the current pending shot type (empty outside of serves).
## game_state: current GameState enum value from game.gd (0=WAITING, 1=SERVING, 2=PLAYING, 3=POINT_SCORED)
func update(game_state: int, ball: RigidBody3D, serve_charge_time: float,
		player_left: CharacterBody3D, player_right: CharacterBody3D) -> String:
	_update_out_indicator()
	return _pending_shot_type


## Resets state at the start of each new rally.
func cleanup() -> void:
	_pending_shot_type = ""
	_awaiting_return = false
	_out_shown = false
	_hide_out_indicator()


## Classify the shot type from its post-hit velocity vector.
## Returns one of: "FAST", "NORMAL", "DROP", "LOB".
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


## Classify the intended shot BEFORE the swing happens, based on where the
## ball is right now and where the player is standing. Called on space press.
## Returns one of: VOLLEY, SMASH, DINK, DROP, LOB, RETURN, GROUNDSTROKE.
func _classify_intended_shot(ball_ref: RigidBody3D, player_node: CharacterBody3D) -> String:
	if ball_ref == null or player_node == null:
		return "GROUNDSTROKE"
	if _awaiting_return:
		_awaiting_return = false
		return "RETURN"
	var ball_y: float = ball_ref.global_position.y
	var player_z_abs: float = absf(player_node.global_position.z)
	var ball_speed: float = ball_ref.linear_velocity.length()
	var ball_not_bounced: bool = not ball_ref.ball_bounced_since_last_hit
	if ball_y > 1.8:
		return "SMASH"
	if ball_not_bounced and player_z_abs < _nvz + 0.8:
		return "VOLLEY"
	if player_z_abs < _nvz and ball_y < 0.6:
		return "DINK"
	if player_z_abs < _nvz + 1.5 and ball_y > 0.5 and ball_y < 1.1:
		return "DROP"
	if player_z_abs > 3.5 and ball_speed < 8.0:
		return "LOB"
	return "GROUNDSTROKE"


## Show shot type label and speed after a paddle hit.
func _show_shot_type(vel: Vector3, player_num: int) -> void:
	var shot_type: String = _classify_trajectory(vel)
	var player_name: String = "Blue" if player_num == 0 else "Red"
	print("[Shot] %s: %s  (speed=%.1f  vy=%.2f  vz=%.2f)" % [player_name, shot_type, vel.length(), vel.y, vel.z])
	_scoreboard_ui.show_shot_type(shot_type)


## Show speed in mph after a serve or rally hit.
func _show_speedometer(speed_ms: float) -> void:
	var mph: float = speed_ms * 2.23694  # m/s → mph
	_scoreboard_ui.show_speed(mph)


## Called when player presses swing (space bar). Classifies intent and shows pre-shot label.
func _on_player_swing_press() -> void:
	if _ball == null or _player_left == null:
		return
	_pending_shot_type = _classify_intended_shot(_ball, _player_left)
	_scoreboard_ui.show_shot_type(_pending_shot_type)
	print("[Shot] Blue intent: %s" % _pending_shot_type)


## Called when any paddle makes contact with the ball. Logs and displays shot type.
func _on_any_paddle_hit(player_num: int) -> void:
	if _ball == null:
		return
	var vel: Vector3 = _ball.linear_velocity
	_show_shot_type(vel, player_num)
	_show_speedometer(vel.length())


## Per-frame: check if ball is outside court bounds and update OUT indicator.
func _update_out_indicator() -> void:
	if _ball == null:
		_hide_out_indicator()
		return

	var bpos: Vector3 = _ball.global_position

	# Show OUT the moment the ball crosses a court boundary in x or z.
	# Applies in the air (flying out fast) and on the ground (rolling out).
	# No trajectory prediction — eliminates all false positives.
	if bpos.z > _court_half_len or bpos.z < -_court_half_len \
			or bpos.x < -_court_half_wid or bpos.x > _court_half_wid:
		_show_out_indicator()
	else:
		_hide_out_indicator()


func _show_out_indicator() -> void:
	if not _out_shown:
		_out_shown = true
		_scoreboard_ui.show_out()


func _hide_out_indicator() -> void:
	if _out_shown:
		_out_shown = false
		_scoreboard_ui.hide_out()
