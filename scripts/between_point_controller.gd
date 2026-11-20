extends Node


const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const HandPresentation = preload("res://scripts/player_hand_presentation.gd")
const PixelCards = preload("res://scripts/graphics/pixel_card_rig.gd")
signal active_changed(active: bool)
signal phase_changed(phase: String)
signal finished(skipped: bool)
const WALK_SPEED: = 2.4
const RUN_SPEED: = 4.4
const CARRY_SPEED: = 3.4
const MOVE_ACCEL: = 9.0
const MOVE_BRAKE: = 7.0
const WALK_APPROACH_DISTANCE: = 0.6
# Farther than this from the ball: run. Closer: walk the whole way.
const RUN_DECISION_DISTANCE: = 1.2
# Ground pickup timing (bend down, lift back up).
const BEND_TIME: = 0.42
const LIFT_TIME: = 0.42
const TIMEOUT: = 15.0
const HAND_BALL_OFFSET: = Vector3(0, 0.075, 0)
var _end_route = preload("res://scripts/between_end_change_route.gd").new()
var end_change_status: Dictionary = {}
var _end_faced: Array = []
var _game: Node
var _active: = false
var phase: = "IDLE"
var elapsed: = 0.0
var _elapsed_limit: float = TIMEOUT
var phase_elapsed: = 0.0
var server: = 0
var retriever: = -1
var observed_bounces: = 0
var used_offscreen_helper: = false
var catch_after_bounce: = false
var pickup_contact_gap: = INF
var catch_contact_gap: = INF
var transfer_bounce_position: = Vector3.INF
var last_result: = ""
var _players: Array = []
var _targets: Array[Vector3] = []
var _motion_velocity: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _poses: Array = [null, null]
var _wrists: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _carry_team: = -1
var _carry_offset: = HAND_BALL_OFFSET
var _carry_direction: = Vector3.UP
var _grasp_direction: = Vector3.UP
var _pickup_wrist_position: = Vector3.ZERO
var _pickup_position: = Vector3.ZERO
var _catch_position: = Vector3.ZERO
var _saved_mask: = 7
var _generation: = -1
var _pass_attempts: = 0
var _run_id: = 0
var _initially_visible: = true
var _settle_pose: PostureDefinition
var _receiver_settle_poses: Array = []
var _serve_cup_entry: Vector3
var _entry_poses: Array = [null, null]
var _entry_wrists: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _arm_paths: Array = []
var _presentation_admission: Dictionary = {}
var _planned_catch_time: float = 0.0
var missed_physical_catches: int = 0
var pass_catch_declined: bool = false
var pass_catch_decision: Dictionary = {}
var missed_collection_plan: Dictionary = {}
var _phase_entry_wrists: Array = [Vector3.ZERO, Vector3.ZERO]
var _carry_heading: Array = [0.0, 0.0]
var _carry_heading_tick: Array = [-1, -1]
var _entry_side_relaxation: Array[bool] = [false, false]
# Who is catching the ball in the air: the server for a partner pass, or the
# retriever when the dead ball is still catchable on its way down.
var catcher: = 0
var _catch_open_time: = 0.0  # PASS phase time when the catching hand opened (reach starts here)
var _air_catch: = false
var _run_approach: Array[bool] = [false, false]
var _prev_ball_pos: = Vector3.INF

func setup(game: Node) -> void :
	_game = game
	process_priority = 100
	process_physics_priority = 100
	_players = game.get_players()
	_initialize_roster_storage()
	game.ball.bounced.connect(_on_bounced)

func is_active() -> bool:
	return _active

func get_cinematic_focus() -> Vector3:
	if _game == null: return Vector3(0, 0.8, 0)
	var focus: Vector3 = _players[server].global_position
	if phase in ["APPROACH", "BEND", "LIFT", "PASS_PREP"] and retriever >= 0:
		focus = _players[retriever].global_position.lerp(_game.ball.global_position, 0.35)
	elif phase == "PASS":
		focus = _game.ball.global_position
	focus.y = clampf(focus.y, 0.55, 1.5)
	return focus

func is_ready_for_serve() -> bool:
	return not _active

func capture_presentations() -> Array:
	var result: Array = []
	for team in _players.size():
		result.append({"pose": _players[team].posture.capture_displayed_pose(), "wrist": _actual_wrist(team)})
	return result

func begin(presentations: Array = []) -> bool:
	if _game == null or _game.match_over or _game._is_practice() or _game.game_state != _game.GameState.POINT_SCORED:
		return false
	if presentations.is_empty(): presentations = capture_presentations()
	_arm_paths.clear()
	for player in _players: _arm_paths.append(load("res://scripts/between_point_arm_path.gd").new(player))
	cancel()



	for team in _players.size():
		var player = _players[team]
		_carry_heading[team] = player.leg_ik.locomotion_hip_yaw_deg
		_carry_heading_tick[team] = -1
		var pose: PostureDefinition = presentations[team].pose
		_entry_poses[team] = pose.lerp_with(pose, 0.0)
		_entry_poses[team].set_meta("support_grip_weight", Path.support_grip_weight(pose))


		var serve_pose: bool = pose.display_name in ["Underhand Serve", "Serve Preparation", "Serve Finish"]
		_entry_side_relaxation[team] = serve_pose or (pose.paddle_forehand_mul > 0.1 and player.paddle_node.global_basis.y.dot(Vector3.UP) < 0.0)
		_entry_wrists[team] = presentations[team].wrist
		_poses[team] = _entry_poses[team]
		_wrists[team] = _entry_wrists[team]
	_initially_visible = _game.main_camera == null or _game.main_camera.is_position_in_frustum(_game.ball.global_position)
	_active = true
	_run_id += 1
	server = _players.find(_game.get_server_actor())
	if server < 0: return false
	_generation = _game._point_reset_generation
	elapsed = 0.0
	_elapsed_limit = TIMEOUT
	observed_bounces = 0
	used_offscreen_helper = false
	catch_after_bounce = false
	pickup_contact_gap = INF
	catch_contact_gap = INF
	transfer_bounce_position = Vector3.INF
	last_result = ""
	_pass_attempts = 0
	catcher = server
	_air_catch = false
	_prev_ball_pos = Vector3.INF
	missed_physical_catches = 0
	pass_catch_declined = false
	pass_catch_decision = {}
	missed_collection_plan = {}
	_carry_team = -1
	_targets.clear()
	for player in _players: _targets.append(player.global_position)
	_motion_velocity.fill(Vector3.ZERO)
	_saved_mask = _game.ball.collision_mask

	_game.ball.collision_mask = _saved_mask & ~ 2
	_game.ball.is_in_play = false
	_game.ball.freeze = false
	_game.ball.set_time_frozen(false)
	_game.game_serve.cleanup()
	_game.rally_scorer.end_rally()
	_game.input_handler.cancel_charge_input()
	if _game.mobile_controls: _game.mobile_controls.cancel_all()
	for player in _players:
		player.cancel_contextual_jump()
		player.hitting.clear_charge_visual()
		player.posture.reset_incoming_highlight()
		player.velocity = Vector3.ZERO
		player.current_velocity = Vector3.ZERO
		if player.ai_brain: player.ai_brain.incoming_pose_override = null
	_set_phase("SETTLE")
	active_changed.emit(true)
	return true

func cancel() -> void :
	for player in _players:
		if is_instance_valid(player) and player.has_meta("between_bounded_admission"): player.remove_meta("between_bounded_admission")
	_presentation_admission.clear()
	if not _active: return
	_active = false
	_end_route.cancel()
	_motion_velocity.fill(Vector3.ZERO)
	_run_id += 1
	_carry_team = -1
	_poses.fill(null)
	_wrists.fill(Vector3.INF)
	_game.ball.collision_mask = _saved_mask
	_game.ball.visible = true
	for player in _players:
		player.velocity = Vector3.ZERO
		player.current_velocity = Vector3.ZERO
	phase = "IDLE"
	if _game.hud: _game.hud.set_end_change_pending(false)
	active_changed.emit(false)

func skip() -> void :
	if not _active or get_tree().paused or _game._tool_state_active(): return
	if _game.doubles_mode and _game.doubles_state.end_change_pending: return
	_complete(true, "SKIPPED")

func _unhandled_key_input(event: InputEvent) -> void :
	if _active and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
		skip()
		get_viewport().set_input_as_handled()

func velocity_for(actor_id: int) -> Vector3:
	var team: int = index_for_actor_id(actor_id)
	if not _active or team < 0 or team >= _players.size() or _targets.size() != _players.size(): return Vector3.ZERO
	var offset: Vector3 = _targets[team] - _players[team].global_position
	offset.y = 0.0
	var distance: float = offset.length()


	if phase in ["END_WALK", "END_TURN"] and team < _end_faced.size() and int(_end_faced[team]) > 0:
		_motion_velocity[team] = Vector3.ZERO   # arrived and facing the net: stand still
		return _motion_velocity[team]
	if phase == "END_WALK" and _end_route.active:
		_motion_velocity[team] = _end_route.velocity_for(team, maxf(get_physics_process_delta_time(), 1e-05))
		return _motion_velocity[team]
	var chasing: bool = team == retriever and (phase == "APPROACH" or (phase == "PASS" and _air_catch))
	if not chasing:
		_motion_velocity[team] = offset.normalized() * minf(CARRY_SPEED, distance * 8.0) if distance > 0.025 else Vector3.ZERO
		return _motion_velocity[team]
	var dt: float = maxf(get_physics_process_delta_time(), 1e-05)



	var approach_cap: float = sqrt(WALK_SPEED * WALK_SPEED + 2.0 * MOVE_BRAKE * maxf(0.0, distance - WALK_APPROACH_DISTANCE))
	var top_speed: float = RUN_SPEED if _run_approach[team] else WALK_SPEED
	var speed: float = minf(top_speed, minf(approach_cap, distance * 8.0))
	var desired: Vector3 = offset.normalized() * speed if distance > 0.0001 else Vector3.ZERO
	var previous: Vector3 = _motion_velocity[team]
	var acceleration: float = MOVE_ACCEL if desired.length() > previous.length() else MOVE_BRAKE
	var motion: Vector3 = previous.move_toward(desired, acceleration * dt)

	if motion.length() * dt > distance: motion = offset / dt
	if distance < 0.01 and motion.length() < 0.025: motion = Vector3.ZERO
	_motion_velocity[team] = motion
	return motion

func _ready_to_pickup(team: int, strict: bool = true) -> bool:
	if not _at_target(team) or _players[team].current_velocity.length() > 0.001: return false
	var player = _players[team]
	var feet = player.leg_ik
	if feet == null or not feet.is_support_ready(0) or not feet.is_support_ready(1): return false
	# A ground pickup only needs both feet planted; the bend re-plants anyway.
	if not strict: return true
	# Contact readiness has a generous reach tolerance. Do not change phases
	# while the stricter live-stance planner is about to take another step.
	var base := Vector3(player.global_position.x, feet.ANKLE_HEIGHT, player.global_position.z)
	var targets: Array[Vector3] = feet._stance_targets(_poses[team], base)
	return feet.right_foot_smooth.distance_to(targets[0]) <= feet.STANCE_REPLANT_DISTANCE and feet.left_foot_smooth.distance_to(targets[1]) <= feet.STANCE_REPLANT_DISTANCE

# Standing still, both feet planted, no step or weight shift in progress:
# what the catch presentation (between_pose_admission) needs.
func _settled_for_catch(team: int) -> bool:
	var feet = _players[team].leg_ik
	return feet != null and _ready_to_pickup(team) and feet.right_foot_locked and feet.left_foot_locked and feet._active_side < 0 and not feet._run_active and not feet._airborne and feet.locomotion_state == "ready" and feet.locomotion_body_weight < 0.2

# Looser than _settled_for_catch: both feet down and not running is enough to reach for
# a pass (a weight shift may still be finishing), as a real receiver would.
func _planted_for_catch(team: int) -> bool:
	var feet = _players[team].leg_ik
	return feet != null and feet.right_foot_locked and feet.left_foot_locked and not feet._run_active and not feet._airborne

func pose_for(actor_id: int):
	var team: int = index_for_actor_id(actor_id)
	return _poses[team] if _active and team >= 0 and team < _players.size() else null

func support_hand_target_for(actor_id: int) -> Vector3:
	var team: int = index_for_actor_id(actor_id)
	return _wrists[team] if _active and team >= 0 and team < _players.size() else Vector3.INF

func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("between.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	if not _active: return
	if _generation != _game._point_reset_generation or _game._is_practice() or _game.match_over or _game.game_state != _game.GameState.POINT_SCORED:
		cancel()
		return
	if get_tree().paused or _game._tool_state_active(): return
	elapsed += delta
	phase_elapsed += delta
	if elapsed > _elapsed_limit and not _end_route.active and phase not in ["END_TURN", "END_BLOCKED"]:
		_complete(true, "TIMEOUT")
		return
	for team in _players.size():
		_poses[team] = _make_pose(team, 0.0)
		_wrists[team] = _carry_wrist(team)
	if _carry_team >= 0:
		_game.ball.global_position = _hand_ball_position(_carry_team, _carry_direction)
		_game.ball.linear_velocity = Vector3.ZERO
		_game.ball.angular_velocity = Vector3.ZERO
	match phase:
		"SETTLE":


			var weight: float = load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / 0.35)
			for team in _players.size():
				_poses[team] = Path.blend_pose(_entry_poses[team], _poses[team], weight)
				_wrists[team] = _entry_wrists[team].lerp(_wrists[team], weight)
			if phase_elapsed > 0.35: _choose_retriever()
		"APPROACH":
			if not _reachable_ball():
				_start_offscreen_return()
			else:
				var ball = _game.ball
				if missed_physical_catches == 0 and Engine.get_physics_frames() % maxi(1, Engine.physics_ticks_per_second / 10) == 0 and _try_air_catch(): return
				var player = _players[retriever]
				_targets[retriever] = _pickup_root(ball.global_position, player)
				if ball.global_position.y < 0.19:
					ball.linear_velocity.x = move_toward(ball.linear_velocity.x, 0.0, delta * 6.0)
					ball.linear_velocity.z = move_toward(ball.linear_velocity.z, 0.0, delta * 6.0)
				if _ready_to_pickup(retriever, false) and ball.global_position.y < 0.22 and ball.linear_velocity.length() < 0.85:
					_pickup_position = ball.global_position
					_pickup_wrist_position = _pickup_position - _hand_ball_offset(retriever, Vector3.DOWN)
					ball.freeze = true
					_set_phase("BEND")
		"BEND":
			_pickup_wrist_position = _pickup_position - _hand_ball_offset(retriever, Vector3.DOWN)
			var blend: float = smoothstep(0.0, BEND_TIME - 0.05, phase_elapsed)
			_poses[retriever] = _make_pose(retriever, blend)
			_wrists[retriever] = _carry_wrist(retriever).lerp(_pickup_wrist_position, blend)
			if phase_elapsed >= BEND_TIME and absf(_hand_surface_gap(retriever, _pickup_position)) < 0.012:
				pickup_contact_gap = _hand_surface_gap(retriever, _pickup_position)
				_carry_team = retriever
				_carry_offset = _pickup_position - _carry_anchor(retriever)
				_grasp_direction = -(_players[_carry_team].left_arm_node.hand_mesh.global_basis * _players[_carry_team].left_arm_node.articulated_hand.palm_contact_basis.z).normalized()
				_carry_direction = _grasp_direction
				_set_phase("LIFT")
			elif phase_elapsed > 1.8:
				_start_offscreen_return()
		"LIFT":
			var blend: float = smoothstep(0.0, LIFT_TIME - 0.08, phase_elapsed)
			_poses[retriever] = _make_pose(retriever, 1.0 - blend)
			_wrists[retriever] = (_pickup_wrist_position).lerp(_carry_wrist(retriever), blend)
			_carry_direction = _lift_direction(retriever, load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / (LIFT_TIME - 0.08)))
			if phase_elapsed > LIFT_TIME:
				if retriever == server:
					_targets[server] = _serve_position(server)
					_set_phase("CARRY")
				else:
					_set_phase("PASS_PREP")
		"PASS_PREP":
			var player = _players[retriever]
			var windup: Vector3 = _carry_wrist(retriever) - player._get_forward_axis() * .1 - Vector3.UP * .1
			var finish: Vector3 = _carry_wrist(retriever) + player._get_forward_axis() * .12 + Vector3.UP * .16
			if phase_elapsed < .15:
				_wrists[retriever] = Vector3(_phase_entry_wrists[retriever]).lerp(windup, load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / .15))
			else:
				_wrists[retriever] = windup.lerp(finish, load("res://scripts/between_point_arm_path.gd").clock_weight((phase_elapsed - .15) / .4))
			if phase_elapsed > 0.55 and _at_target(server) and (_settled_for_catch(server) or phase_elapsed > 3.5):
				_launch_pass(_game.ball.global_position)
		"PASS":
			var ball = _game.ball
			if retriever >= 0 and retriever != server and not _air_catch and phase_elapsed > .4:
				_targets[retriever] = _serve_position(retriever)
			# An air catch is decided while the catcher is still running; the hand
			# opens once they have stopped and planted, like a pass receiver.
			# Same for an ordinary pass: if the receiver had to shuffle to the catch spot, the
			# hand stayed shut for the whole flight and the ball went by. Open it once planted.
			if pass_catch_declined and _planted_for_catch(catcher) and phase_elapsed < _planned_catch_time - 0.12:
				pass_catch_declined = false
				_catch_open_time = phase_elapsed
				_phase_entry_wrists[catcher] = _actual_wrist(catcher)
			var reach_clock: float = maxf(0.0, phase_elapsed - _catch_open_time) if not _air_catch else maxf(0.0, phase_elapsed - maxf(0.0, _planned_catch_time - 0.6))
			if not pass_catch_declined:
				_wrists[catcher] = Vector3(_phase_entry_wrists[catcher]).lerp(_catch_position - HAND_BALL_OFFSET, load("res://scripts/between_point_arm_path.gd").clock_weight(reach_clock / .35))
			if retriever >= 0 and retriever != catcher: _wrists[retriever] = Vector3(_phase_entry_wrists[retriever]).lerp(_carry_wrist(retriever), load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / .4))
			var catchable: bool = observed_bounces > 0 or _air_catch
			if not pass_catch_declined and catchable and ball.global_position.distance_to(_catch_position) < 0.8:
				var shoulder: Vector3 = _players[catcher].left_arm_node.get_node("UpperArmPivot").global_position
				var next_ball: Dictionary = Flight.advance(ball.global_position, ball.linear_velocity, ball.angular_velocity, delta)
				var wrist: Vector3 = next_ball.pos - _hand_ball_offset(catcher, Vector3.UP)
				if shoulder.distance_to(wrist) <= 0.7: _wrists[catcher] = _actual_wrist(catcher).move_toward(wrist, 4.0 * delta)
				# The ball moves several centimetres per tick: test the whole step,
				# not just this tick's end point, then seat it in the cup.
				var cup: Vector3 = _hand_ball_position(catcher, Vector3.UP)
				var swept: Vector3 = ball.global_position
				if _prev_ball_pos.is_finite(): swept = Geometry3D.get_closest_point_to_segment(cup, _prev_ball_pos, ball.global_position)
				if absf(_hand_surface_gap(catcher, swept)) <= 0.06 and swept.y > 0.25 and _catch_presentation_valid(_players[catcher]):
					catch_contact_gap = _hand_surface_gap(catcher, swept)
					catch_after_bounce = observed_bounces > 0
					_carry_team = catcher
					_carry_offset = cup - _carry_anchor(catcher)
					_grasp_direction = -(_players[_carry_team].left_arm_node.hand_mesh.global_basis * _players[_carry_team].left_arm_node.articulated_hand.palm_contact_basis.z).normalized()
					_carry_direction = _grasp_direction
					ball.freeze = true
					ball.linear_velocity = Vector3.ZERO
					ball.global_position = cup
					_set_phase("CATCH")
			_prev_ball_pos = ball.global_position
			if phase == "PASS" and phase_elapsed > _planned_catch_time + .3 and catchable:
				# A missed decorative catch is still a real dead ball. Collect its
				# actual position instead of forcing another throw or awarding possession.
				missed_physical_catches += 1
				var on_server_end: bool = ball.global_position.z >= 0.0 if _players[server].court_side == 0 else ball.global_position.z <= 0.0
				_air_catch = false
				catcher = server
				retriever = server if on_server_end else _nearest_retriever(ball.global_position)
				if retriever < 0 or not _reachable_ball():
					_start_offscreen_return()
				else:
					_targets[retriever] = _pickup_root(ball.global_position, _players[retriever])
					_run_approach[retriever] = _players[retriever].global_position.distance_to(_targets[retriever]) > RUN_DECISION_DISTANCE
					if missed_physical_catches == 1:
						missed_collection_plan = _missed_collection_budget(ball, _players[retriever])
						_elapsed_limit = maxf(_elapsed_limit, elapsed + float(missed_collection_plan.seconds))
					_set_phase("APPROACH")
		"CATCH":
			_wrists[catcher] = Vector3(_phase_entry_wrists[catcher]).lerp(_carry_wrist(catcher), load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / .35))
			_carry_direction = _lift_direction(catcher, smoothstep(0.0, 0.35, phase_elapsed))
			if phase_elapsed > 0.45:
				if catcher == server:
					_targets[server] = _serve_position(server)
					_set_phase("CARRY")
				else:
					# Caught by a partner: toss it to the server from here.
					_air_catch = false
					retriever = catcher
					_targets[retriever] = _players[retriever].global_position
					_set_phase("PASS_PREP")
		"END_WALK":
			var route: Dictionary = _end_route.advance(delta)
			end_change_status = route
			# Whoever reaches their spot stops, then faces the net at once on the next
			# tick (no turning on the spot, no waiting for the others).
			# _end_faced: 0 walking, 1 stopping, 2 facing the net.
			for index in _players.size():
				var state: int = int(_end_faced[index])
				if state == 0 and _end_route.remaining(index) <= _end_route.ARRIVE: state = 1
				if state == 1 and _players[index].current_velocity.length() < .05 and _players[index].leg_ik != null:
					state = 2
					_players[index].leg_ik.face_ready_now(null)
					_carry_heading[index] = _players[index].leg_ik.locomotion_hip_yaw_deg
					_carry_heading_tick[index] = Engine.get_physics_frames()
				_end_faced[index] = state
				_targets[index] = _players[index].global_position if state > 0 else _end_route.target_for(index)
			if route.arrived:
				if not _end_faced.has(0) and not _end_faced.has(1): _set_phase("END_TURN")
			elif not route.active:
				_set_phase("END_BLOCKED")
		"END_TURN":
			# Exact supported facing/rig rebase is a separate commit gate.
			end_change_status = {"arrived": true, "committed": false, "reason": "supported visual rest-frame rebase pending"}
		"CARRY":
			if _game.doubles_mode and _game.doubles_state.end_change_pending and _end_route.begin(_game, _players):
				_end_faced = []; _end_faced.resize(_players.size()); _end_faced.fill(0)
				_elapsed_limit = TIMEOUT + _end_route.deadline_seconds
				for index in _players.size(): _targets[index] = _end_route.target_for(index)
				_set_phase("END_WALK")
			elif _all_support_ready() and phase_elapsed > 0.25:
				_game.game_serve.accept_handover(_game.ball.global_position)
				_serve_cup_entry = _game.ball.global_position
				_settle_pose = _poses[server]
				for index in _players.size():
					_receiver_settle_poses[index] = _poses[index].duplicate(true)
					_receiver_settle_poses[index].left_hand_offset = Vector3(-.11, -.10, -.23)
				for path in _arm_paths: path.begin_exit()
				_set_phase("SET_SERVE")
		"SET_SERVE":
			var ready: PostureDefinition = _game.game_serve.get_preparation_pose(0.0)
			var blend: float = load("res://scripts/between_point_arm_path.gd").clock_weight(phase_elapsed / .56)
			var player = _players[server]
			var offset: Vector3 = load("res://scripts/serve_style.gd").hold_offset(_game.game_serve.selected_serve_style)
			var target: Vector3 = player.global_position + player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + player._get_forward_axis() * offset.z
			var carry_blend: float = load("res://scripts/between_point_arm_path.gd").clock_weight((phase_elapsed - 0) / 0.56)
			_wrists[server] = _serve_cup_entry.lerp(target, carry_blend) + player._get_forward_axis() * (0.2 * sin(PI * carry_blend)) - _carry_direction.normalized() * HandPresentation.RETRIEVAL_BALL_DEPTH
			_poses[server] = Path.blend_pose(_settle_pose, ready, blend)
			# Lower progressively before the service-foot replant compresses the
			# supported body; return to the unchanged serve height at handover.
			_poses[server].crouch_amount += 0.10 * sin(PI * clampf(phase_elapsed / .72, 0.0, 1.0))
			for index in _players.size():
				if index == server: continue
				_poses[index] = Path.blend_pose(_receiver_settle_poses[index], PostureLibrary.instance().get_def(_players[index].PaddlePosture.READY), blend)
				_wrists[index] = Vector3.INF
			if phase_elapsed > 0.72 and _all_support_ready() and _game.game_serve._legal_service_feet(_players[server], _players[server].get_court_side()):
				_complete(false, "READY")

	if _active:
		for team in _players.size(): _players[team].present_between_point_physics(self, _poses[team], delta)
		if _carry_team >= 0: _game.ball.global_position = _hand_ball_position(_carry_team, _carry_direction)
		if phase == "SET_SERVE": _game.game_serve.accept_handover(_game.ball.global_position)
		if phase == "END_TURN" and phase_elapsed > .25: _try_commit_end_change()

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.between_point_controller", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:


	if _active and _carry_team >= 0 and not get_tree().paused:
		_game.ball.global_position = _hand_ball_position(_carry_team, _carry_direction)



func hand_presentation_for(actor_id: int) -> Dictionary:
	var team: int = index_for_actor_id(actor_id)
	if team < 0: return {}
	if not _active: return {}
	if team == retriever and phase == "BEND":
		return {"mode": "PICKUP", "normal": Vector3.DOWN, "closure": smoothstep(0.4, 0.65, phase_elapsed), "elapsed": phase_elapsed, "transition": smoothstep(0.0, 0.2, phase_elapsed)}
	if team == catcher and phase == "PASS" and not pass_catch_declined:
		return {"mode": "CATCH_OPEN", "normal": Vector3.UP, "closure": 0.15, "elapsed": phase_elapsed, "transition": smoothstep(0.0, 0.2, phase_elapsed)}
	if team == retriever and phase == "PASS" and not _air_catch and phase_elapsed < 0.2:
		return {"mode": "PASS_RELEASE", "normal": Vector3.UP, "closure": 0.0, "elapsed": phase_elapsed, "transition": smoothstep(0.0, 0.2, phase_elapsed)}
	if team == _carry_team and phase in ["LIFT", "CARRY", "PASS_PREP", "CATCH", "SET_SERVE", "END_WALK", "END_TURN", "END_BLOCKED"]:
		var closure: = 1.0
		if phase == "CATCH": closure = lerpf(0.15, 1.0, smoothstep(0.0, 0.1, phase_elapsed))
		elif phase == "PASS_PREP": closure = 1.0 - smoothstep(0.4, 0.55, phase_elapsed)
		return {"mode": "CARRY", "normal": _carry_direction, "closure": closure, "elapsed": phase_elapsed}
	return {}

func declined_pass_recovery_for(actor_id: int) -> bool:
	# No stale world-frame arm is restored. The normal free-hand path solves
	# against this frame's moving torso and supported feet until real pickup.
	return pass_catch_declined and index_for_actor_id(actor_id) == catcher

func support_wrist_for_body_fit(actor_id: int) -> Vector3:
	var team: int = index_for_actor_id(actor_id)
	if team < 0: return Vector3.INF
	if not _active or phase != "SET_SERVE" or team != _carry_team: return Vector3.INF
	var model = _players[team].left_arm_node.articulated_hand
	var center: Vector3 = _wrists[team] + _carry_direction.normalized() * HandPresentation.RETRIEVAL_BALL_DEPTH
	return center + _arm_paths[team].last_basis * (model.wrist_socket - model.cup_ball_center)

func support_cup_frame_for_body_fit(actor_id: int) -> Dictionary:
	var team: int = index_for_actor_id(actor_id)
	if team < 0: return {}
	var wrist: Vector3 = support_wrist_for_body_fit(_players[team].get_actor_id())
	if not wrist.is_finite(): return {}
	return {"wrist": wrist, "basis": _arm_paths[team].last_basis, "elbow": _arm_paths[team].last_elbow}

func _hand_ball_offset(_team: int, direction: Vector3) -> Vector3:


	return direction.normalized() * HandPresentation.RETRIEVAL_BALL_DEPTH

func _hand_ball_position(team: int, direction: Vector3) -> Vector3:
	var arm = _players[team].left_arm_node
	if arm.articulated_hand != null: return HandPresentation.ball_center(arm)
	return _carry_anchor(team) + _hand_ball_offset(team, direction)

func _hand_surface_gap(team: int, point: Vector3) -> float:
	var arm = _players[team].left_arm_node
	if arm.articulated_hand == null: return INF
	return HandPresentation.ball_surface_gap(arm, point, Ball.BALL_RADIUS)

func _lift_direction(team: int, progress: float) -> Vector3:
	var side: Vector3 = - _players[team]._get_forehand_axis()
	return _grasp_direction.slerp(side, progress * 2.0) if progress < 0.5 else side.slerp(Vector3.UP, (progress - 0.5) * 2.0)

func _choose_retriever() -> void:
	var _pt := Time.get_ticks_usec()
	_perf_choose_retriever()
	PerfMonitor.record("bp.choose_retriever", Time.get_ticks_usec() - _pt)

func _perf_choose_retriever() -> void:
	for index in _players.size():
		if index != server: _targets[index] = _serve_position(index)
	_targets[server] = _serve_position(server) + _players[server]._get_forward_axis() * 1.0
	if not _initially_visible or not _reachable_ball():
		_start_offscreen_return()
		return
	if _try_air_catch(): return
	retriever = _nearest_retriever(_game.ball.global_position)
	_targets[retriever] = _pickup_root(_game.ball.global_position, _players[retriever])
	_run_approach[retriever] = _players[retriever].global_position.distance_to(_targets[retriever]) > RUN_DECISION_DISTANCE
	_set_phase("APPROACH")

# Catch the dead ball out of the air when someone can get under it in time:
# a descending ball at chest height, on that player's side, reachable at a run
# with time left to stop and plant before it arrives.
func _try_air_catch() -> bool:
	var ball = _game.ball
	if ball.global_position.y < 0.3 and ball.linear_velocity.length() < 1.5: return false
	var flight: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 2.5, 2, false)
	for sample in flight.samples:
		var point: Vector3 = sample.pos
		var t: float = float(sample.time)
		if t < 0.35 or point.y < 0.62 or point.y > 1.35 or float(sample.vel.y) > 0.0: continue
		var team: int = _nearest_retriever(point)
		if team < 0: continue
		var player = _players[team]
		var root: Vector3 = point + player._get_forehand_axis() * 0.26 - player._get_forward_axis() * 0.32
		root.y = player.ground_y
		if root.x < player.min_x or root.x > player.max_x or root.z < player.min_z or root.z > player.max_z: continue
		var run: float = player.global_position.distance_to(root)
		# Run time at RUN_SPEED plus accel/brake and ~0.6 s to plant feet.
		if run / RUN_SPEED + minf(run, RUN_SPEED) / MOVE_ACCEL + 0.9 > t: continue
		retriever = team
		catcher = team
		_air_catch = true
		_catch_position = point
		_planned_catch_time = t
		_targets[team] = root
		_run_approach[team] = run > RUN_DECISION_DISTANCE
		pass_catch_declined = true # opens once the catcher has planted
		observed_bounces = 0
		_prev_ball_pos = Vector3.INF
		_carry_team = -1
		_set_phase("PASS")
		return true
	return false

func _missed_collection_budget(ball, player) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_missed_collection_budget(ball, player)
	PerfMonitor.record("bp.missed_collection_budget", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_missed_collection_budget(ball, player) -> Dictionary:
	# Forecast the actual released ball under the same aero/bounce model and
	# APPROACH's existing near-ground brake. This never advances the live ball.
	var dt: float = get_physics_process_delta_time()
	var gravity: float = maxf(.01, Ball.get_effective_gravity())
	var height: float = maxf(0.0, ball.global_position.y - Flight.FLOOR_REST_Y)
	var impact: float = sqrt(ball.linear_velocity.y * ball.linear_velocity.y + 2.0 * gravity * height)
	var air_time: float = (maxf(0.0, ball.linear_velocity.y) + impact) / gravity + 2.0 * impact * Ball.BOUNCE_COR / (gravity * (1.0 - Ball.BOUNCE_COR))
	var brake_time: float = Vector2(ball.linear_velocity.x, ball.linear_velocity.z).length() / 3.0
	var horizon: float = air_time + brake_time + 2.0 * dt
	var point: Vector3 = ball.global_position
	var velocity: Vector3 = ball.linear_velocity
	var omega: Vector3 = ball.angular_velocity
	var settling: float = 0.0
	for unused in ceili(horizon / dt):
		if point.y < .22 and velocity.length() < .85: break
		var forecast: Dictionary = Flight.advance(point, velocity, omega, dt)
		point = forecast.pos; velocity = forecast.vel; omega = forecast.omega
		if point.y < .19:
			velocity.x = move_toward(velocity.x, 0.0, dt * 3.0)
			velocity.z = move_toward(velocity.z, 0.0, dt * 3.0)
		settling += dt
	var pickup: Vector3 = _pickup_root(point, player)
	var approach: float = player.global_position.distance_to(pickup) / WALK_SPEED
	var carry: float = pickup.distance_to(_serve_position(index_for_actor(player))) / CARRY_SPEED
	var feet = player.leg_ik
	# Existing bounded bend/lift/setup intervals, two stance replants at each
	# of pickup, carry arrival and setup, plus a full supported facing turn.
	var support: float = 1.8 + .65 + .72 + 6.0 * feet.STANCE_STEP_DURATION + 2.0 * feet.STEP_DURATION_WALK + feet.RUN_SETTLE_DURATION + 180.0 / 160.0
	var braking: float = player.current_velocity.length() / MOVE_BRAKE
	return {"seconds": settling + approach + carry + support + braking, "actor_id": player.get_actor_id(), "ball_start": ball.global_position, "ball_velocity": ball.linear_velocity, "forecast_point": point, "forecast_settled": point.y < .22 and velocity.length() < .85, "forecast_horizon": horizon, "settling_seconds": settling, "walk_seconds": approach, "carry_seconds": carry, "support_seconds": support, "braking_seconds": braking}

func _reachable_ball() -> bool:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_reachable_ball()
	PerfMonitor.record("bp.reachable_ball", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_reachable_ball() -> bool:
	var pos: Vector3 = _game.ball.global_position
	if not pos.is_finite() or pos.y < -0.1: return false
	var team: int = _nearest_retriever(pos)
	if team < 0: return false
	var player = _players[team]
	var target: Vector3 = _pickup_root(pos, player)
	var planar: Vector3 = pos - target
	planar.y = 0.0
	# Root bounds constrain travel. A ball just beyond the preferred standing
	# offset can still be collected by the real bounded reach at the boundary.
	return planar.length() <= .62

func _pickup_root(pos: Vector3, player) -> Vector3:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_pickup_root(pos, player)
	PerfMonitor.record("bp.pickup_root", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_pickup_root(pos: Vector3, player) -> Vector3:
	var result: Vector3 = pos + player._get_forehand_axis() * 0.22 - player._get_forward_axis() * 0.27
	result.y = player.ground_y
	result.x = clampf(result.x, player.min_x, player.max_x)
	result.z = clampf(result.z, player.min_z, player.max_z)
	return result

func _serve_position(team: int) -> Vector3:
	if _game.doubles_mode: return _game.doubles_controller.reset_spawn_position(_players[team])
	var right: bool = _game.get_server_score() % 2 == 0
	return Vector3((1.5 if right else -1.5) * (1 if _players[team].get_court_side() == 0 else -1), _players[team].ground_y, _game.SERVE_RESET_DEPTH if _players[team].get_court_side() == 0 else -_game.SERVE_RESET_DEPTH)

# The foot planner owns travel/return heading and world-space planted contacts.
# Carry presentation follows that heading once at the body root; putting this on
# the hips alone leaves the paddle and support hand facing the old court axis.
func _facing_yaw(team: int) -> float:
	if not _active or _players[team].leg_ik == null: return 0.0
	if int(_carry_heading_tick[team]) != Engine.get_physics_frames():
		var difference: float = wrapf(_players[team].leg_ik.locomotion_hip_yaw_deg - float(_carry_heading[team]), -180.0, 180.0)
		var turn_rate: float = 330.0 if phase == "END_TURN" else 160.0   # change of ends: brisk turn-around
		_carry_heading[team] += clampf(difference, -turn_rate * _players[team].get_physics_process_delta_time(), turn_rate * _players[team].get_physics_process_delta_time())
		_carry_heading_tick[team] = Engine.get_physics_frames()
	return float(_carry_heading[team])

func _carry_wrist(team: int) -> Vector3:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_carry_wrist(team)
	PerfMonitor.record("bp.carry_wrist", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_carry_wrist(team: int) -> Vector3:
	var player = _players[team]
	var offset: Vector3 = - player._get_forehand_axis() * 0.26 + player._get_forward_axis() * 0.32 + Vector3.UP * 0.05
	return player.global_position + offset.rotated(Vector3.UP, deg_to_rad(-_facing_yaw(team)))

func _actual_wrist(team: int) -> Vector3:
	var arm = _players[team].left_arm_node
	return arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket



func _carry_anchor(team: int) -> Vector3:
	return _players[team].left_arm_node.hand_pivot.global_position

func _at_target(team: int) -> bool:
	return _players[team].global_position.distance_to(_targets[team]) < 0.06

func _make_pose(team: int, bend: float) -> PostureDefinition:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_make_pose(team, bend)
	PerfMonitor.record("bp.make_pose", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_make_pose(team: int, bend: float) -> PostureDefinition:
	var pose: PostureDefinition = PostureLibrary.instance().get_def(_players[team].PaddlePosture.READY).duplicate(true)


	pose.right_hand_offset = Vector3.ZERO
	# A carry is a neutral handle grip, independent of the live READY regrip.
	pose.main_grip_rotation_deg = pose.paddle_in_hand_rotation_deg
	pose.right_shoulder_rotation_deg = Vector3(0, -8, 0)
	pose.left_shoulder_rotation_deg = Vector3(0, 8, 0)
	pose.shoulder_protraction_m = 0.05
	pose.left_elbow_pole = Vector3( - 0.58, - 0.35, - 0.07)
	pose.left_hand_mode = 4
	pose.left_hand_offset = Vector3.ZERO
	# Between points a player stands up: feet under the hips, no crouch (the athletic READY
	# stance comes back in SET_SERVE). A pickup bends from there.
	pose.crouch_amount = lerpf(0.0, 0.64, bend)
	pose.body_pitch_deg = lerpf(0.0, 8.0, bend)
	pose.torso_pitch_deg = lerpf(0.0, 12.0, bend)
	pose.stance_width = lerpf(0.28, 0.5, bend)
	pose.front_foot_forward = lerpf(0.02, pose.front_foot_forward, bend)
	pose.back_foot_back = lerpf(-0.02, pose.back_foot_back, bend)
	pose.head_track_ball_weight = 0.4
	preload("res://scripts/player_carry_presentation.gd").apply(pose, bend)
	var facing: float = _facing_yaw(team)
	if absf(facing) > 0.00001:
		var turned: PostureDefinition = Path.rotate_guard(pose, facing)
		# rotate_guard also authors toe yaw for stationary guard poses. Retrieval
		# feet already receive this heading from their contact planner, so retain
		# only the original toe-out here instead of rotating the feet twice.
		turned.right_foot_yaw_deg = pose.right_foot_yaw_deg
		turned.left_foot_yaw_deg = pose.left_foot_yaw_deg
		return turned
	return pose

func _start_offscreen_return() -> void:
	var _pt := Time.get_ticks_usec()
	_perf_start_offscreen_return()
	PerfMonitor.record("bp.start_offscreen_return", Time.get_ticks_usec() - _pt)

func _perf_start_offscreen_return() -> void:
	used_offscreen_helper = true
	_carry_team = -1
	retriever = -1
	_game.ball.visible = false
	_game.ball.freeze = true
	for index in _players.size(): _targets[index] = _serve_position(index)
	_targets[server] += _players[server]._get_forward_axis() * 1.0
	_set_phase("HELPER_WAIT")

	call_deferred("_await_helper_position")

func _await_helper_position() -> void :
	var token: int = _run_id
	while _active and phase == "HELPER_WAIT" and token == _run_id:
		await get_tree().physics_frame
		if not _active or phase != "HELPER_WAIT" or token != _run_id: return
		if get_tree().paused or _game._tool_state_active(): continue
		if _at_target(server):
			var origin: Vector3 = _targets[server] + Vector3(7.0, 0.7, 0.0) + _players[server]._get_forward_axis() * 2.5
			var camera: Camera3D = _game.main_camera
			while camera != null and camera.is_position_in_frustum(origin) and origin.x < 100.0:
				origin.x += 1.0
			_game.ball.global_position = origin
			_launch_pass(origin)
			return

func _launch_pass(origin: Vector3) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_launch_pass(origin)
	PerfMonitor.record("bp.launch_pass", Time.get_ticks_usec() - _pt)

func _perf_launch_pass(origin: Vector3) -> void:
	var receiver = _players[server]
	var ideal_catch: Vector3 = _targets[server] - receiver._get_forehand_axis() * 0.26 + receiver._get_forward_axis() * 0.32 + Vector3.UP * 0.125
	var toward_origin: Vector3 = origin - ideal_catch
	toward_origin.y = 0
	var landing: Vector3 = ideal_catch + toward_origin.normalized() * 1.1
	landing.y = Flight.FLOOR_REST_Y
	var distance: float = Vector2(origin.x - landing.x, origin.z - landing.z).length()
	var duration: float = clampf(distance / 5.5 + 0.4, 0.85, 1.85)
	var velocity: Vector3 = (landing - origin) / duration + Vector3.UP * Ball.get_effective_gravity() * duration * 0.5
	for iteration in range(7):
		var flight: Dictionary = Flight.trace(origin, velocity, Vector3.ZERO, 3.0, 1, false)
		if float(flight.first_bounce_time) <= 0.0: break
		var error: Vector3 = landing - flight.first_bounce
		velocity.x += error.x / duration
		velocity.z += error.z / duration
	var prediction: Dictionary = Flight.trace(origin, velocity, Vector3.ZERO, 4.0, 2, false)
	var best: Dictionary = {}
	var best_cost: = INF
	for sample in prediction.samples:
		if int(sample.bounces) != 1 or float(sample.time) - float(prediction.first_bounce_time) < 0.15: continue
		var point: Vector3 = sample.pos
		if point.y < 0.75 or point.y > 1.4: continue
		var cost: float = point.distance_to(ideal_catch)
		if cost < best_cost:
			best_cost = cost
			best = sample
	if best.is_empty():
		_complete(true, "NO_SAFE_TRANSFER")
		return
	_catch_position = best.pos
	_planned_catch_time = float(best.time)
	catcher = server
	_air_catch = false
	_prev_ball_pos = Vector3.INF
	# Decide before requesting a catch pose, and before moving the receiver:
	# a near catch is taken with the arm from where they already stand.
	var feet = receiver.leg_ik
	var settled_now: bool = feet != null and _ready_to_pickup(server)
	if best_cost > 0.45:
		settled_now = false
		_targets[server] = _catch_position + receiver._get_forehand_axis() * 0.26 - receiver._get_forward_axis() * 0.32 - Vector3.UP * 0.125
		_targets[server].y = receiver.ground_y
	var settled: bool = settled_now and _settled_for_catch(server)
	pass_catch_declined = not settled
	_catch_open_time = 0.0
	pass_catch_decision = {"declined": pass_catch_declined, "reason": "receiver is not settled at the actual catch target" if pass_catch_declined else "stationary supported catch may be attempted", "actor_id": receiver.get_actor_id(), "root": receiver.global_transform, "target": _targets[server], "velocity": receiver.current_velocity, "active_side": feet._active_side if feet != null else -1, "right_locked": feet.right_foot_locked if feet != null else false, "left_locked": feet.left_foot_locked if feet != null else false}
	for index in _players.size():
		if index != server: _targets[index] = _players[index].global_position if index == retriever else _serve_position(index)
	_carry_team = -1
	observed_bounces = 0
	_pass_attempts += 1
	_game.ball.global_position = origin
	_game.ball.linear_velocity = velocity
	_game.ball.angular_velocity = Vector3.ZERO
	_game.ball.can_register_floor_bounce = true
	_game.ball.freeze = false
	_game.ball.sleeping = false
	_game.ball.visible = true
	_set_phase("PASS")

func _on_bounced(position: Vector3) -> void :
	if _active and phase == "PASS":
		observed_bounces += 1
		transfer_bounce_position = position

func _set_phase(value: String) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_set_phase(value)
	PerfMonitor.record("bp.set_phase", Time.get_ticks_usec() - _pt)

func _perf_set_phase(value: String) -> void:
	for team in _players.size(): _phase_entry_wrists[team] = _actual_wrist(team)
	phase = value
	phase_elapsed = 0.0
	phase_changed.emit(value)
	PerfMonitor.note("between_phase", {"phase": value})
	var text: = "Ball pickup · Skip to serve"
	if value in ["PASS_PREP", "PASS", "HELPER_WAIT", "CATCH"]: text = "Ball handover · Skip to serve"
	elif value == "CARRY": text = "Getting ready to serve · Skip to serve"
	var changing_ends: bool = _game.doubles_mode and _game.doubles_state.end_change_pending
	if changing_ends: text = "Changing ends · Pause or reset available"
	if _game.hud: _game.hud.set_end_change_pending(changing_ends)
	_game.scoreboard_ui.set_state_text(text)

func _complete(skipped: bool, result: String) -> void :
	if not _active: return
	# One line per between-point (not per frame): how the pre-serve pass/catch went.
	print("[catch] result=%s missed=%d gap=%s after_bounce=%s air=%s declined=%s" % [result, missed_physical_catches, ("%.3f" % catch_contact_gap) if is_finite(catch_contact_gap) else "none", catch_after_bounce, _air_catch, pass_catch_declined])
	last_result = result
	cancel()
	_game._reset_ball( not skipped)
	finished.emit(skipped)

func _catch_presentation_valid(player) -> bool:
	# Only a proven actual hand intersection reaches this edge. Cosmetic
	# preparation may fail, but it cannot award possession from an invalid rig.
	# Pixel cards: the certified 3D hand/sleeve surfaces are hidden; skip.
	if PixelCards.enabled(): return true
	var identity: int = player.get_actor_id()
	if not _presentation_admission.has(identity): _presentation_admission[identity] = load("res://scripts/between_pose_admission.gd").new(player)
	var report: Dictionary = _presentation_admission[identity].displayed_report()
	player.set_meta("between_catch_admission", report)
	return bool(report.valid)

func prepare_pose_admission(player) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_prepare_pose_admission(player)
	PerfMonitor.record("bp.prepare_pose_admission", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_prepare_pose_admission(player) -> Dictionary:
	if PixelCards.enabled(): return {}
	var identity: int = player.get_actor_id()
	if not _presentation_admission.has(identity): _presentation_admission[identity] = load("res://scripts/between_pose_admission.gd").new(player)
	return _presentation_admission[identity].begin(self)

func finish_pose_admission(player, token: Dictionary) -> void:
	var identity: int = player.get_actor_id()
	if _presentation_admission.has(identity): _presentation_admission[identity].finish(self, token)

func present_arm_path(player, pose) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_present_arm_path(player, pose)
	PerfMonitor.record("bp.present_arm_path", Time.get_ticks_usec() - _pt)

func _perf_present_arm_path(player, pose) -> void:
	if not _active or _arm_paths.size() != _players.size(): return
	var index: int = _players.find(player)
	if index < 0: return
	_arm_paths[index].apply(self, pose)
	if phase == "SETTLE" and not PixelCards.enabled():
		var sleeve: Script = load("res://scripts/live_ready_clearance.gd")
		if not sleeve.clearance_report(player).valid:
			var transaction = sleeve.Transaction.new(player)
			var correction: Dictionary = sleeve.search(player, transaction, pose)
			if not correction.is_empty(): sleeve.apply(player, correction)
			player.set_meta("between_entry_clearance", {"feasible": not correction.is_empty()})


func cup_can_fit_body_offset(actor_id: int, offset: Vector3) -> bool:
	var team: int = index_for_actor_id(actor_id)
	if team < 0: return false
	if not _active or phase != "SET_SERVE" or team != _carry_team: return false
	# Pixel cards don't draw the 3D hand/cup, so the exact cup-pose search
	# (thousands of candidates per tick) has nothing to protect.
	if PixelCards.enabled(): return true
	var center: Vector3 = _wrists[team] + _carry_direction.normalized() * HandPresentation.RETRIEVAL_BALL_DEPTH
	return _arm_paths[team].cup_kinematic_fit(_players[team].left_arm_node, center, offset)


func index_for_actor_id(actor_id: int) -> int:
	for index in _players.size():
		if _players[index].get_actor_id() == actor_id: return index
	return -1

func index_for_actor(actor) -> int:
	return _players.find(actor)

func _initialize_roster_storage() -> void:
	var count: int = _players.size()
	_targets.resize(count); _motion_velocity.resize(count); _motion_velocity.fill(Vector3.ZERO)
	_poses.resize(count); _poses.fill(null)
	_wrists.resize(count); _wrists.fill(Vector3.INF)
	_entry_poses.resize(count); _entry_wrists.resize(count)
	_phase_entry_wrists.resize(count); _carry_heading.resize(count); _carry_heading_tick.resize(count)
	_entry_side_relaxation.resize(count); _receiver_settle_poses.resize(count)
	_run_approach.resize(count); _run_approach.fill(false)

func _all_support_ready(include_server: bool = true) -> bool:
	for index in _players.size():
		if not include_server and index == server: continue
		if not _ready_to_pickup(index): return false
	return true

func _nearest_retriever(point: Vector3) -> int:
	var best: int = -1
	var distance: float = INF
	for index in _players.size():
		var player = _players[index]
		var on_side: bool = point.z >= 0.0 if player.get_court_side() == 0 else point.z <= 0.0
		if not on_side: continue
		var cost: float = player.global_position.distance_squared_to(point)
		if cost < distance: best = index; distance = cost
	return best

func ready_facing_for_actor(actor) -> float:
	if phase == "END_TURN": return 180.0
	# Change of ends: whoever reaches their new spot turns around right away instead
	# of standing until the last player arrives.
	if phase == "END_WALK" and (_end_route.active or _end_route.arrived):
		var index: int = index_for_actor(actor)
		if index >= 0 and _end_route.remaining(index) <= _end_route.ARRIVE: return 180.0
	return 0.0

func _try_commit_end_change() -> void:
	if not _all_support_ready(): return
	for index in _players.size():
		if absf(wrapf(float(_carry_heading[index]) - 180.0, -180.0, 180.0)) > .0001: return
	var frame: Script = load("res://scripts/runtime_court_frame.gd")
	var report: Dictionary = frame.commit_supported_roster(_game, self)
	end_change_status = report
	if not report.get("committed", false):
		_set_phase("END_BLOCKED")
		return
	for index in _players.size(): _targets[index] = _serve_position(index)
	_set_phase("CARRY")
