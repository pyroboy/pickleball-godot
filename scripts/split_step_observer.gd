extends RefCounted
## Observes public animation/contact events only. Opponent target, shot choice,
## trajectory forecasts and Red's private future contact plan are never read.
const Split = preload("res://scripts/split_step_timing.gd")
const Paddle = preload("res://scripts/paddle_reach.gd")
var _flight := -1
var _rebounds := -1
var _wall_active := false
var last_context: Dictionary = {}

func update(player, timing, delta: float) -> void:
	if delta <= 0.0: return
	var ball = player._get_ball_ref()
	if ball == null:
		timing.update(delta, {"live": false})
		return
	var game = player.get_parent()
	var wall = null
	if game != null and "practice_launcher" in game and game.practice_launcher != null and game.practice_launcher.is_wall():
		wall = game.practice_launcher.wall_practice
	var serving_receive: bool = game != null and "game_serve" in game and game.game_serve != null and game.game_serve.is_release_pending() and game.serving_team != player.player_num
	var active: bool = (ball.is_in_play or serving_receive) and not player.is_jumping
	active = active and player.posture != null and not player.posture.editor_preview_mode and player._between_point_owner() == null
	active = active and not player.hitting.serving_visual_active and not player.get_tree().paused
	var context: Dictionary = {"live": active, "hop_allowed": _supports_hop(player, timing), "direction": player.current_velocity, "direction_ready": false, "time_to_contact": INF, "own_stroke": player.hitting.is_in_follow_through}
	var human = player.posture.human_contact if player.posture != null else null
	if player.is_ai:
		var brain = player.ai_brain
		var read: bool = brain != null and brain._perception_ready and brain._observed_flight_id == ball.flight_id
		context.direction_ready = read and ball.last_hit_by != player.player_num
		if read and brain.ai_selected_contact_reachable and brain.ai_selected_contact_time >= 0:
			context.time_to_contact = brain.ai_selected_contact_time
	elif human != null:
		context.direction_ready = ball.is_in_play and ball.last_hit_by != player.player_num
		context.own_stroke = context.own_stroke or human.phase in [0, 1]
		var contact: Dictionary = human.preparation_contact()
		if not contact.is_empty(): context.time_to_contact = float(contact.get("time", INF))
	# A flight change alone is insufficient for wall mode: initial feeds and
	# resets are not wall impacts. Only the actual physical rebound counter is.
	if wall != null:
		if _wall_active and _rebounds >= 0 and wall.rebounds > _rebounds and ball.is_in_play:
			context.strike_id = ball.flight_id
		_rebounds = wall.rebounds
		if active and not ball.wall_return_ready and ball.last_hit_by == player.player_num and ball.linear_velocity.z < -0.2:
			var lead: float = (ball.global_position.z - 0.0375) / -ball.linear_velocity.z
			var impact_x: float = ball.global_position.x + ball.linear_velocity.x * maxf(lead, 0.0)
			if lead >= 0.0 and absf(impact_x) < wall.HALF_WIDTH:
				context.cue_id = ball.flight_id + 1
				context.cue_lead = lead
				context.cue_source = "visible wall approach"
	else:
		if _flight >= 0 and ball.flight_id != _flight and ball.is_in_play and ball.last_hit_by >= 0 and ball.last_hit_by != player.player_num:
			context.strike_id = ball.flight_id
		if serving_receive:
			var serve: Dictionary = game.game_serve.get_serve_timing_state()
			if serve.get("phase", "") == "SWING":
				context.cue_id = ball.flight_id + 1
				context.cue_lead = float(serve.time_to_contact)
				context.cue_source = "visible serve swing"
		elif active and ball.last_hit_by == player.player_num:
			var opponent = game.player_right if player.player_num == 0 else game.player_left
			var lead: float = _visible_swing_lead(opponent, ball)
			if lead >= 0.0:
				context.cue_id = ball.flight_id + 1
				context.cue_lead = lead
				context.cue_source = "visible opponent swing"
	_flight = ball.flight_id
	_wall_active = wall != null
	last_context = context
	timing.update(delta, context)

func _supports_hop(player, timing) -> bool:
	if Vector2(player.current_velocity.x, player.current_velocity.z).length() > 0.1: return false
	var legs = player.leg_ik
	if legs == null or not legs.feet_initialized: return false
	if legs.drive_preparation.active() or legs._active_side >= 0 or legs._run_active or legs._run_stopping or legs._airborne or legs._landing_remaining > 0.0: return false
	# Released contact flags are expected during this helper's small unweight.
	if timing.phase in ["split_load", "split_unweight"]: return true
	return legs.right_foot_locked and legs.left_foot_locked

func _visible_swing_lead(opponent, ball) -> float:
	if opponent == null or opponent.posture == null: return -1.0
	var human = opponent.posture.human_contact
	if human != null and human.phase == 1 and not human.hit:
		# Remaining visible stroke-animation time, not an intercept prediction.
		return maxf(0.0, human.strike_time - human.elapsed)
	if not opponent.is_ai or opponent.ai_brain == null or not opponent.ai_brain.ai_is_charging: return -1.0
	# Red's charge pose is visible. Estimate only the very short paddle approach
	# from current positions/velocity; do not inspect its selected contact/aim.
	var relative: Vector3 = Paddle.head_world(opponent) - ball.global_position
	var speed: float = ball.linear_velocity.length()
	if speed < 0.2: return -1.0
	var closing: float = relative.dot(ball.linear_velocity / speed)
	if closing <= 0.0: return -1.0
	var lead: float = closing / speed
	var miss: float = (relative - ball.linear_velocity * lead).length()
	return lead if miss < 0.55 and lead <= Split.CUE_WINDOW else -1.0
