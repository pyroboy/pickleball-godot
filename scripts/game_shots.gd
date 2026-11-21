class_name GameShots
extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")




var _pending_shot_type: String = ""


var _awaiting_return: bool = false


var _ball: RigidBody3D = null
var _player_left: CharacterBody3D = null
var _player_right: CharacterBody3D = null
var _scoreboard_ui: Node = null


var _court_half_len: float = 0.0
var _court_half_wid: float = 0.0
var _nvz: float = 0.0


var _out_shown: bool = false



func setup(ball: RigidBody3D, player_left: CharacterBody3D, player_right: CharacterBody3D, 
		scoreboard_ui: Node) -> void :
	_ball = ball
	_player_left = player_left
	_player_right = player_right
	_scoreboard_ui = scoreboard_ui
	_refresh_court_constants()


func _refresh_court_constants() -> void :
	_court_half_len = PickleballConstants.COURT_LENGTH / 2.0
	_court_half_wid = PickleballConstants.COURT_WIDTH / 2.0
	_nvz = PickleballConstants.NON_VOLLEY_ZONE



func on_ball_bounced(_bounce_pos: Vector3) -> void :
	_awaiting_return = true



func on_paddle_hit(_player_num: int) -> void :
	_awaiting_return = false




func update(_game_state: int, _p_ball: RigidBody3D, _serve_charge_time: float, 
		_p_player_left: CharacterBody3D, _p_player_right: CharacterBody3D) -> String:
	_update_out_indicator()
	return _pending_shot_type



func cleanup() -> void :
	_pending_shot_type = ""
	_awaiting_return = false
	_out_shown = false
	_hide_out_indicator()




func _classify_trajectory(vel: Vector3) -> String:
	var speed: float = vel.length()
	var horiz_speed: float = Vector2(vel.x, vel.z).length()
	var arc_ratio: float = 0.0
	if horiz_speed > 0.01:
		arc_ratio = vel.y / horiz_speed


	if speed < 7.0 and arc_ratio < 0.6:
		return "DROP"
	elif arc_ratio > 0.7:
		return "LOB"
	elif speed > 14.0 and arc_ratio < 0.35:
		return "FAST"
	else:
		return "NORMAL"





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
	var predicted_human_contact: = false
	var predicted_contact: = false


	if not player_node.is_ai and player_node.posture and player_node.posture.human_contact:
		var preparation: Dictionary = player_node.posture.human_contact.preparation_contact()
		if not preparation.is_empty():
			predicted_contact = true
			ball_y = preparation.point.y
			player_z_abs = absf(preparation.get("target_root", player_node.global_position).z)
			ball_not_bounced = ball_ref.bounces_since_last_hit + int(preparation.get("bounces", 0)) == 0
			# An overhead contact from 1.5 m up is a smash (the AI's rule too);
			# before, only balls above 1.8 m counted.
			if preload("res://scripts/charged_footwork.gd").is_smash_contact(player_node, preparation): return "SMASH"
	if ball_y > 1.8:
		return "SMASH"
	if "wall_practice_active" in ball_ref and ball_ref.wall_practice_active:

		return "VOLLEY" if ball_not_bounced else "GROUNDSTROKE"
	if ball_not_bounced and player_z_abs < _nvz + 0.8:
		return "VOLLEY"
	if player_z_abs < _nvz and ball_y < 0.6:
		return "DINK"
	if player_z_abs < _nvz + 1.5 and ball_y > 0.5 and ball_y < 1.1:
		return "DROP"


	if not predicted_contact and player_z_abs > 3.5 and ball_speed < 8.0:
		return "LOB"
	return "GROUNDSTROKE"



func _show_shot_type(vel: Vector3, player_num: int) -> void :
	var shot_type: String = _classify_trajectory(vel)
	var player_name: String = "Blue" if player_num == 0 else "Red"
	if RuntimePolicy.developer_tools: print("[Shot] %s: %s  (speed=%.1f  vy=%.2f  vz=%.2f)" % [player_name, shot_type, vel.length(), vel.y, vel.z])
	_scoreboard_ui.show_shot_type(shot_type)



func _show_speedometer(speed_ms: float) -> void :
	var mph: float = speed_ms * 2.23694
	_scoreboard_ui.show_speed(mph)



func _on_player_swing_press() -> void :
	if _ball == null or _player_left == null:
		return
	_pending_shot_type = _classify_intended_shot(_ball, _player_left)
	_scoreboard_ui.show_shot_type(_pending_shot_type)
	if RuntimePolicy.developer_tools: print("[Shot] Blue intent: %s" % _pending_shot_type)



func _on_any_paddle_hit(player_num: int) -> void :
	if _ball == null:
		return
	var vel: Vector3 = _ball.linear_velocity
	_show_shot_type(vel, player_num)
	_show_speedometer(vel.length())



func _update_out_indicator() -> void :
	# Airborne boundary crossings are not line calls. The rally scorer confirms
	# Out at the first ground contact and CourtCallouts presents that result.
	_hide_out_indicator()


func _hide_out_indicator() -> void :
	if _out_shown:
		_out_shown = false
		_scoreboard_ui.hide_out()
