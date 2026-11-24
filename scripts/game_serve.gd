extends Node
class_name GameServe
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const _Flight = preload("res://scripts/ball_flight_predictor.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const HeldMotion = preload("res://scripts/held_hit_motion.gd")
const Feet = preload("res://scripts/player_nvz_state.gd")








signal serve_launched(team: int)
signal serve_phase_changed(phase: String, style: int)
signal serve_style_changed(style: int)


var _serve_charge_time: float = 0.0
var held_hit_seconds: float = 0.0
var _held_visual_active: bool = false
var _held_recover_seconds: float = 0.0
var _held_visual_motion = HeldMotion.new()
var _held_visual_revision: int = -1
var _serve_is_charging: bool = false
var _service_fault_triggered: bool = false
var _serve_was_hit: bool = false
var _pending_release: Dictionary = {}
var _release_elapsed: float = 0.0
var _server_prepared: bool = false
# Physical preparation survives an interrupted release; service-rule context does not.
var _service_rules_need_rearm: bool = false
var _prepared_team: int = -1
var _prepared_actor: int = -1
var _prepared_pose_revision: int = 0
var _prepared_style: int = -1
var _ball_was_frozen: bool = false
var selected_serve_style: int = Styles.Style.FLAT
var _held_position: = Vector3.INF
var _follow_through: Dictionary = {}
var _physics_presentations: Dictionary = {}
var _preview_key: = ""
var _preview_launch: Dictionary = {}
var _last_style: int = Styles.Style.FLAT


var _serve_aim_offset_x: float = 0.0
var _trajectory_arc_offset: float = 0.0


var _game: Node
var ball: RigidBody3D
var player_left: CharacterBody3D
var player_right: CharacterBody3D
var rally_scorer
var scoreboard_ui
var _ShotPhysicsRef: Script





func setup(
	game: Node, 
	ball_node: RigidBody3D, 
	p_left: CharacterBody3D, 
	p_right: CharacterBody3D, 
	scorer, 
	ui, 
	shot_phys: Script
) -> void :
	_game = game
	ball = ball_node
	player_left = p_left
	player_right = p_right
	rally_scorer = scorer
	scoreboard_ui = ui
	_ShotPhysicsRef = shot_phys
	process_mode = Node.PROCESS_MODE_ALWAYS
	ball.bounced.connect(_on_delivery_bounce)





func _server():
	return _game.get_server_actor() if _game != null else null

func _server_for_record(record: Dictionary):
	if record.has("actor_id"): return _game.get_player_by_actor_id(int(record.actor_id))
	# Old isolated singles fixtures may supply a team-only record.
	if _game.doubles_mode: return null
	return player_left if int(record.get("team", -1)) == 0 else player_right

func _server_for_team(team: int):
	if team == _game.serving_team: return _server()
	var actors: Array = _game.get_team_players(team)
	return actors[0] if actors.size() == 1 else null

func _from_right() -> bool:
	return _game.get_server_logical_court() == 0

## ---- One writer for the serve charge pose (2026-11-25) ----
## While the server waits, the physics tick writes the whole serve pose 30 times a second and
## finishes it (arms refitted to the body, head turned to the ball). The held-HIT input also
## wrote the pose on every rendered frame, without that finish, so on alternate frames the head
## flipped about 27 degrees and the torso, head and body shifted about 5 mm: a 30-per-second
## shake through the whole charge. The input now only advances the held clock while the tick is
## presenting; the tick reads that clock and writes the pose. If no tick has presented for a
## moment (paused tools), the input writes as before.
const WAITING_TICK_STALE_USEC := 120000
var _waiting_tick_usec: int = 0

func tick_presents_waiting() -> bool:
	return Time.get_ticks_usec() - _waiting_tick_usec < WAITING_TICK_STALE_USEC

func has_committed_physics_presentation(actor) -> bool:
	if actor == null or _game == null or actor.get_parent() != _game: return false
	if get_tree().paused or _game._tool_state_active(): return false
	var record: Dictionary = _physics_presentations.get(actor.get_instance_id(), {})
	return int(record.get("tick", -1)) == Engine.get_physics_frames() and int(record.get("actor_id", -1)) == actor.get_actor_id() and int(record.get("team_id", -1)) == actor.get_team_id() and int(record.get("court_side", -1)) == actor.get_court_side()

func _commit_physics_presentation(actor, delta: float) -> void:
	if actor == null: return
	if not actor.complete_service_physics_presentation(delta if Engine.is_in_physics_frame() else 0.0): return
	if not Engine.is_in_physics_frame(): return
	_physics_presentations[actor.get_instance_id()] = {"tick": Engine.get_physics_frames(), "actor_id": actor.get_actor_id(), "team_id": actor.get_team_id(), "court_side": actor.get_court_side()}

func _present_service_pose(actor, pose: PostureDefinition) -> void:
	actor.hitting._apply_motion_pose(pose)
	_commit_physics_presentation(actor, get_physics_process_delta_time())

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.game_serve", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	if _game == null: return
	if get_tree().paused or _game._tool_state_active():
		_physics_presentations.clear()
		if not _pending_release.is_empty(): _cancel_pending_release()
		if _serve_is_charging:
			_serve_is_charging = false
			_serve_charge_time = 0.0
			var server = _server()
			server.hitting.clear_charge_visual()
		return
	if _game.game_state != _game.GameState.WAITING or not _ready_for_serve():
		return
	if _game.has_method("_tool_state_active") and _game._tool_state_active():
		return

	# Preparation is completed once on the physics owner below.
	# Explicit held-input updates remain immediate through _prepare_server.
	return

func _advance_waiting_presentation(delta: float) -> void:
	_held_recover_seconds = move_toward(_held_recover_seconds, 0.0, maxf(delta, 0.0) * 4.0)
	var charge: float = get_charge_ratio() if _serve_is_charging else 0.0
	if _game.server_is_ai():
		charge = clampf(_game.ai_serve_timer / 1.5, 0.0, 1.0) * 0.8
	var server = _server()
	var offset: Vector3 = Styles.hold_offset(selected_serve_style)
	var target: Vector3 = server.global_position + server._get_forehand_axis() * offset.x + Vector3.UP * offset.y + server._get_forward_axis() * offset.z
	if not _held_position.is_finite() or _held_position.distance_to(target) > 1.5:
		_held_position = target
	else:
		_held_position = _held_position.lerp(target, 1.0 - pow(0.5, maxf(delta, 0.0) / 0.045))
	_prepare_server(charge)


func owns_carried_cup_presentation(actor = null) -> bool:
	if _game == null or get_tree().paused or _game._tool_state_active() or _game._is_practice(): return false
	if _game.game_state != _game.GameState.WAITING or not _pending_release.is_empty() or not _ready_for_serve(): return false
	var server = _server()
	if actor != null and actor != server: return false
	return server != null and server.has_meta("carried_cup_continuity") and server.posture != null and not server.posture.editor_preview_mode and server._between_point_owner() == null and server.leg_ik != null and server.leg_ik.feet_initialized


func _ready_for_serve() -> bool:
	if _game == null: return false
	if "between_point_controller" in _game and _game.between_point_controller:
		return _game.between_point_controller.is_ready_for_serve()
	return true


func _attempt_permitted() -> bool:
	# Preparation remains on its normal fixed-physics path under the cover.
	return _ready_for_serve() and not (_game.has_method("_point_transition_blocks_attempt") and _game._point_transition_blocks_attempt())

func accept_handover(position: Vector3) -> void :

	_held_position = position
	_preview_key = ""
	var server = _server()
	if server and server.leg_ik and server.leg_ik.feet_initialized:
		_server_prepared = true
		_prepared_team = _game.serving_team
		_prepared_actor = server.get_actor_id()
	if _game.doubles_mode and _game.game_state == _game.GameState.WAITING and _ready_for_serve():
		_game.doubles_controller.record_score_call()
		_service_rules_need_rearm = false


func _prepare_server(charge: float, refresh_pose: bool = true) -> void :
	if _game == null or not _ready_for_serve(): return
	var server = _server()
	if server and server.hitting:
		if refresh_pose: server.hitting.set_underhand_serve_charge(charge)
		if refresh_pose and owns_carried_cup_presentation(server) and server.arm_ik:
			server.arm_ik.update_arm_ik(0.0, server.posture.transition_pose_blend)
		if not _server_prepared or _prepared_actor != server.get_actor_id() or _prepared_team != _game.serving_team or _prepared_pose_revision != Motion.ServeEdits.revision or (Motion.ServeEdits.revision > 0 and _prepared_style != selected_serve_style):
			if server.leg_ik and server.leg_ik.has_method("initialize_serve_stance"):
				server.leg_ik.initialize_serve_stance(server.posture.transition_pose_blend)


				if server.arm_ik: server.arm_ik.update_arm_ik(0.0, server.posture.transition_pose_blend)
			_server_prepared = true
			_prepared_actor = server.get_actor_id()
			if _game.doubles_mode:
				_game.doubles_controller.record_score_call()
				_service_rules_need_rearm = false
			_prepared_team = _game.serving_team
			_prepared_pose_revision = Motion.ServeEdits.revision
			_prepared_style = selected_serve_style


	# Explicit input can change the pose between physics ticks. Finish its rig
	# immediately without advancing the physics gaze/support clocks.
	if not Engine.is_in_physics_frame() and not tick_presents_waiting(): _commit_physics_presentation(server, 0.0)

func start_charge() -> void :
	if not _attempt_permitted(): return
	if not _pending_release.is_empty() or not _ready_for_serve() or ball.freeze: return
	held_hit_seconds = 0.0
	_held_recover_seconds = 0.0
	_held_visual_active = true
	_held_visual_motion.reset(false)
	_prepare_server(0.0)
	_serve_charge_time = 0.0
	_serve_is_charging = true

func advance_held_visual(delta: float) -> void:
	if not _serve_is_charging or not _held_visual_active: return
	held_hit_seconds = minf(held_hit_seconds + maxf(delta, 0.0), HeldMotion.STRONG_SECONDS)

func tick_charge(delta: float, refresh_pose: bool = true) -> void :
	if not _attempt_permitted(): return
	# Human input owns its real-time visual interval. Direct/AI service callers
	# keep their existing physics-clock fallback and do not count it twice.
	if not (_game.human_may_serve() and _game.input_handler and _game.input_handler.serve_is_charging): advance_held_visual(delta)
	var MAX_SERVE_CHARGE_TIME: = PickleballConstants.MAX_SERVE_CHARGE_TIME
	_serve_charge_time = minf(_serve_charge_time + delta, MAX_SERVE_CHARGE_TIME)
	_update_charge_ui(get_charge_ratio())
	# Input has already displayed this exact charge/held interval before UI sync.
	# Keep stance initialization, but do not regenerate and solve it a second time.
	_prepare_server(get_charge_ratio(), refresh_pose)

func get_charge_ratio() -> float:
	var MAX_SERVE_CHARGE_TIME: = PickleballConstants.MAX_SERVE_CHARGE_TIME
	return clampf(_serve_charge_time / MAX_SERVE_CHARGE_TIME, 0.0, 1.0)

func is_charging() -> bool:
	return _serve_is_charging

func cleanup(recover_held_visual: bool = false) -> void :
	_physics_presentations.clear()
	_held_recover_seconds = held_hit_seconds if recover_held_visual and _serve_is_charging else 0.0
	held_hit_seconds = 0.0
	_held_visual_active = false
	_held_visual_motion.reset(false)
	_cancel_pending_release()
	if not _follow_through.is_empty():
		var server = _server_for_record(_follow_through)
		if server and server.hitting: server.hitting.clear_charge_visual()
	_follow_through = {}
	_held_position = Vector3.INF
	_preview_key = ""
	_preview_launch = {}
	_server_prepared = false
	_service_rules_need_rearm = false
	_prepared_team = -1
	_prepared_actor = -1
	_serve_charge_time = 0.0
	_serve_is_charging = false
	_serve_aim_offset_x = 0.0
	_trajectory_arc_offset = 0.0
	_service_fault_triggered = false
	_serve_was_hit = false





func set_aim_offset(val: float) -> void :
	_serve_aim_offset_x = val

func set_arc_offset(val: float) -> void :
	_trajectory_arc_offset = val





func release(charge_ratio: float) -> void :
	if not _attempt_permitted(): return
	if not _serve_is_charging: return
	_serve_is_charging = false
	perform_serve(charge_ratio)





func perform_serve(charge_ratio: float) -> void :
	if not _attempt_permitted(): return
	if not _pending_release.is_empty() or _game.game_state != _game.GameState.WAITING or ball.freeze or get_tree().paused or not _ready_for_serve(): return
	_serve_is_charging = false
	var team: int = _game.serving_team
	var server = _server_for_team(team)
	if server == null: return
	var zone: Dictionary = rally_scorer.check_actor_server_position(server, _from_right()) if rally_scorer.has_method("check_actor_server_position") else rally_scorer.check_server_position(server.global_position, server.court_side, 1 if _from_right() else 0)
	if not zone.valid:
		trigger_server_position_fault(zone.reason)
		return
	_prepare_server(charge_ratio)
	if not server.is_ai: _game.capture_aim_target()
	var style: int = selected_serve_style
	var release_position: Vector3 = get_held_ball_position()
	var plan: Dictionary = Styles.release_plan(server.global_position, server.court_side == 1, style, release_position)
	if float(plan.contact_time) <= 0.0:
		if not server.is_ai: _game.release_aim_target()
		return
	var prep: PostureDefinition = get_preparation_pose(charge_ratio)
	_game.commit_execution_settings(server)
	_rearm_service_rule_context()
	if _game.doubles_mode and _game.doubles_controller.begin_service_attempt(server).is_empty():
		_game._execution_commits.erase(server.get_actor_id())
		if not server.is_ai: _game.release_aim_target()
		scoreboard_ui.set_state_text("Service setup must finish before release")
		return
	_pending_release = {"team": team, "actor_id": server.get_actor_id(), "court_side": server.court_side, "charge": clampf(charge_ratio, 0, 1), "style": style, "spin": Styles.spin_mode(style), 
		"target": _target_for_server(team), "arc": _game.trajectory_arc_offset, "plan": plan, 
		"origin": plan.contact_position, "server_position": server.global_position, "prep": prep, 
		"contact_at": plan.contact_time, "phase": "RELEASE", "observed_bounces": 0, "last_bounce": -1.0}
	_release_elapsed = 0.0
	_last_style = style
	_ball_was_frozen = ball.freeze
	ball.is_in_play = false
	ball.global_position = release_position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.can_register_floor_bounce = true
	ball.freeze = false
	ball.sleeping = false
	ball.suppress_paddle_collision(server.paddle_node)
	_game.game_state = _game.GameState.SERVING
	_game.freeze_spin_selection(Styles.spin_mode(style))
	server.hitting.begin_underhand_serve_release(charge_ratio, Styles.spin_mode(style))
	_present_service_pose(server, prep)
	if _game.contact_authority: _game.contact_authority.prime_serve_delivery(server)
	serve_phase_changed.emit("RELEASE", style)
	scoreboard_ui.set_state_text("%s serve" % Styles.options()[style].label)


func _rearm_service_rule_context() -> void:
	# Only a genuine, otherwise admissible retry reaches this seam. Do not reset
	# planted feet or a retained cup just to replace a canceled score-call token.
	if not _service_rules_need_rearm or not _game.doubles_mode: return
	_game.doubles_controller.record_score_call()
	_service_rules_need_rearm = false


func is_release_pending() -> bool:
	return not _pending_release.is_empty()


func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("serve.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	if _game == null: return
	if get_tree().paused or _game._tool_state_active():
		_physics_presentations.clear()
		if not _pending_release.is_empty(): _cancel_pending_release()
		return
	if _game.game_state == _game.GameState.WAITING and _ready_for_serve():
		_waiting_tick_usec = Time.get_ticks_usec()
		_advance_waiting_presentation(delta)
		_commit_physics_presentation(_server(), delta)
		_game._update_held_ball_position()
	if _pending_release.is_empty():
		_advance_follow_through(delta)
		return
	var server = _server_for_record(_pending_release)
	if _game.game_state != _game.GameState.SERVING or ball.freeze or ball.is_time_frozen()\
	or server.global_position.distance_to(_pending_release.server_position) > 0.03:
		_cancel_pending_release()
		return
	_release_elapsed += delta
	ball.suppress_paddle_collision(server.paddle_node)
	var style: int = _pending_release.style
	var dropped: bool = Styles.is_drop(style)
	var bounced: bool = int(_pending_release.observed_bounces) > 0
	var remaining: float = maxf(0.0, float(_pending_release.plan.contact_time) - _release_elapsed)
	var target_y: float = _pending_release.plan.contact_position.y
	if not dropped or bounced:
		var y: float = ball.global_position.y
		var vy: float = ball.linear_velocity.y
		var gravity: float = Ball.get_effective_gravity()
		if dropped:
			var discriminant: float = vy * vy - 2.0 * gravity * (target_y - y)
			if y >= target_y or vy <= 0.0: remaining = 0.0
			elif discriminant >= 0.0: remaining = maxf(0.0, (vy - sqrt(discriminant)) / gravity)
			else: remaining = maxf(0.0, vy / gravity)
		else:
			remaining = maxf(0.0, (vy + sqrt(maxf(0.0, vy * vy + 2.0 * gravity * (y - target_y)))) / gravity)
		_pending_release.contact_at = _release_elapsed + remaining
	var phase: String = "DROP" if dropped and not bounced else "RELEASE"
	if bounced: phase = "BOUNCE"
	var stroke_time: float = Styles.stroke_duration(style)
	var can_swing: bool = not dropped or bounced
	var target: Vector3 = Vector3(ball.global_position.x, target_y, ball.global_position.z)
	var local: Vector3 = _local_ball(server, target)
	if can_swing and remaining <= stroke_time:
		phase = "SWING"
		var start: PostureDefinition = Motion.serve_style_wait(_pending_release.prep, _release_elapsed / 0.12, style, local)
		var pose: PostureDefinition = Motion.serve_style_strike(start, 1.0 - remaining / stroke_time, style, local)
		_present_service_pose(server, pose)
	else:
		_present_service_pose(server, Motion.serve_style_wait(_pending_release.prep, _release_elapsed / 0.12, style, local))
	if phase != _pending_release.phase:
		_pending_release.phase = phase
		serve_phase_changed.emit(phase, style)
	if can_swing and remaining <= 0.0001:
		_launch_pending_serve()
	elif _release_elapsed > 2.0:
		_cancel_pending_release()


func _on_delivery_bounce(_position: Vector3) -> void :
	if _pending_release.is_empty() or ball.is_in_play: return
	_pending_release.observed_bounces += 1
	_pending_release.last_bounce = _release_elapsed
	_pending_release.phase = "BOUNCE"
	serve_phase_changed.emit("BOUNCE", int(_pending_release.style))


func _launch_pending_serve() -> void :
	if _pending_release.is_empty(): return
	var pending: Dictionary = _pending_release
	var team: int = pending.team
	var server = _server_for_record(pending)
	var feet_check: Dictionary = _check_service_feet(server, team)
	if not feet_check.valid:
		_cancel_pending_release(true)
		trigger_server_position_fault("FOOT_FAULT", feet_check.detail)
		return
	var origin: Vector3 = ball.global_position
	var local: Vector3 = _local_ball(server, origin)
	_present_service_pose(server, Motion.serve_style_contact(pending.style, local))
	if _game.contact_authority and not _game.contact_authority.before_serve_contact(server):
		var rejected: Dictionary = _game.contact_authority.last_evidence
		var admission: String = str(rejected.get("serve_admission", "unresolved"))
		if admission == "unresolved":
			_game.contact_authority._hold_unresolved(0.0, str(rejected.get("reason", "serve contact could not be resolved")))
		else:
			_cancel_pending_release(admission == "fault")
			if admission == "fault": trigger_server_position_fault("BODY_HIT", "Released serve ball struck the player before paddle contact")
		return
	var launch: Dictionary = Styles.solve_launch(_game.shot_physics, origin, pending.target, pending.charge, server.court_side, pending.style, pending.arc, not server.is_ai)
	if launch.is_empty():
		_cancel_pending_release()
		return
	launch = _game.apply_contact_execution(server, launch, pending.charge, _release_elapsed - float(pending.contact_at), true)
	_pending_release = {}
	# The ball may already have run this tick's drag/Magnus step on the delivery
	# velocity. Rewind it and redo it on the launch, as rally contacts do (before
	# reset_rally_state clears the delivery bounce the token checks); the
	# solver's flight starts with that step, else serves land ~0.35 m long.
	var aero: Dictionary = ball.take_prepared_aero()
	_game.ball_has_bounced = false
	ball.reset_rally_state()
	if ball.has_method("set_actor_serve_identity"):
		ball.set_actor_serve_identity(server)
	else:
		assert(not _game.doubles_mode, "Actor-aware Ball serve identity is required")
		ball.serve_team = team
	ball.suppress_paddle_collision(server.paddle_node)
	ball.freeze = _ball_was_frozen
	ball.linear_velocity = launch.velocity
	ball.angular_velocity = launch.omega
	if aero.get("taken", false): ball.reapply_prepared_aero(aero)
	ball.set_meta("shot_profile", launch.profile)
	ball.set_meta("serve_style", pending.style)
	ball.set_meta("serve_delivery_bounces", pending.observed_bounces)
	ball.set_meta("serve_release_elapsed", _release_elapsed)
	ball.set_meta("aim_target", launch.target)
	ball.last_hit_by = team
	ball.is_in_play = true
	server.stamina.spend_contact("SERVE", launch.velocity.length())
	ball.flight_id += 1
	if _game.contact_authority: _game.contact_authority.note_serve_contact(server)
	_follow_through = {"team": team, "actor_id": server.get_actor_id(), "court_side": server.court_side, "style": pending.style, "charge": pending.charge, "local": local, "elapsed": 0.0}
	_game.clear_frozen_spin_selection()
	if not server.is_ai: _game.release_aim_target()
	_log_serve(team, origin, launch.velocity, pending.charge)
	scoreboard_ui.set_state_text("Rally!")
	ball.audio_synth.play_serve_sound(ball.linear_velocity.length())
	scoreboard_ui.show_speed(ball.linear_velocity.length() * 2.23694)
	scoreboard_ui.show_shot_type(Styles.options()[int(pending.style)].label)
	_game._awaiting_return = true
	_serve_was_hit = true
	var event: Dictionary = ball.paddle_contact_context()
	serve_phase_changed.emit("CONTACT", int(pending.style))
	if not ball.paddle_contact_is_current(event): return
	serve_launched.emit(team)


func _advance_follow_through(delta: float) -> void :
	if _follow_through.is_empty(): return
	var motion: Dictionary = _follow_through
	var server = _server_for_record(motion)
	if _game.game_state != _game.GameState.PLAYING:
		server.hitting.clear_charge_visual()
		_follow_through = {}
		return
	_follow_through.elapsed += delta
	var elapsed: float = _follow_through.elapsed
	var sweep: float = Styles.sweep_duration(motion.style)
	if elapsed <= sweep:
		var t: float = clampf(elapsed / sweep, 0.0, 1.0)
		var factor: float = t + t * t - t * t * t
		_present_service_pose(server, Motion.serve_style_follow_through(motion.style, motion.charge, factor, motion.local))
	elif elapsed <= sweep + Motion.SERVE_HOLD_TIME:
		_present_service_pose(server, Motion.serve_style_follow_through(motion.style, motion.charge, 1.0, motion.local))
	else:
		var ready: PostureDefinition = PostureLibrary.instance().get_def(server.PaddlePosture.READY).duplicate(true)
		ready.front_foot_forward = -0.12
		ready.back_foot_back = -0.24
		var finish: PostureDefinition = Motion.serve_style_follow_through(motion.style, motion.charge, 1.0, motion.local)
		var progress: float = clampf((elapsed - sweep - Motion.SERVE_HOLD_TIME) / Motion.SERVE_RECOVERY_TIME, 0, 1)
		_present_service_pose(server, Motion.ServeJoint.recover_to_ready(finish, ready, progress))
		if progress >= 1.0:
			_follow_through = {}
			server.hitting._on_paddle_release_finished()
			_commit_physics_presentation(server, 0.0)


func _cancel_pending_release(preserve_service_attempt: bool = false) -> void :
	_physics_presentations.clear()
	if _pending_release.is_empty(): return
	var server = _server_for_record(_pending_release)
	_pending_release = {}
	_release_elapsed = 0.0
	if server and server.hitting: server.hitting.clear_charge_visual()
	if ball:
		ball._clear_paddle_collision_exception()
		ball.freeze = _ball_was_frozen
		ball.is_in_play = false
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		ball.reset_rally_state()
	if _game:
		if _game.doubles_mode and not preserve_service_attempt:
			_game.doubles_controller.cancel_rally()
			_service_rules_need_rearm = true
		_game.release_aim_target()
		_game.clear_frozen_spin_selection()
		if _game.game_state == _game.GameState.SERVING:
			_game._set_game_state(_game.GameState.WAITING)
			ball.global_position = get_held_ball_position()
			update_waiting_ui()


func _local_ball(server, world: Vector3) -> Vector3:
	var delta: Vector3 = world - server.global_position
	return Vector3(delta.dot(server._get_forehand_axis()), delta.y, delta.dot(server._get_forward_axis()))


func get_held_ball_position() -> Vector3:
	if _held_position.is_finite(): return _held_position
	var server = _server()
	var offset: Vector3 = Styles.hold_offset(selected_serve_style)
	return server.global_position + server._get_forehand_axis() * offset.x + Vector3.UP * offset.y + server._get_forward_axis() * offset.z


func prewarm_held_serve_curve() -> bool:
	# Resolve lazy private/packaged data before remembering its resulting revision.
	# This owner and these canonical sampler/key inputs are also used by live Hit.
	var source: PostureDefinition = Motion.ServeEdits.get_def(selected_serve_style)
	if source == null: return false
	if _held_visual_revision != Motion.ServeEdits.revision:
		_held_visual_revision = Motion.ServeEdits.revision
		_held_visual_motion.reset()
	_held_visual_motion.prewarm(source, Motion.ServeEdits.sample, "serve_%d" % selected_serve_style)
	return true


func get_preparation_pose(charge: float) -> PostureDefinition:
	var server = _server()
	var visual_seconds: float = held_hit_seconds if _held_visual_active else _held_recover_seconds
	var showing_held: bool = _held_visual_active or _held_recover_seconds > 0.0
	var visual_charge: float = smoothstep(0.0, HeldMotion.WINDUP_SECONDS, visual_seconds) if showing_held else charge
	var pose: PostureDefinition = Motion.serve_style_preparation(selected_serve_style, visual_charge, _local_ball(server, get_held_ball_position()))
	# Reuse the exact per-owner curve prepared under the entry gate when present.
	prewarm_held_serve_curve()
	if not showing_held: return pose
	var amount: float = smoothstep(HeldMotion.WINDUP_SECONDS, HeldMotion.STRONG_SECONDS, visual_seconds)
	if amount > 0.0:
		var source: PostureDefinition = Motion.ServeEdits.get_def(selected_serve_style)
		var extended: PostureDefinition = _held_visual_motion.extend_windup(source, pose, amount, server, Motion.ServeEdits.sample, "serve_%d" % selected_serve_style)
		# Raw baseline is also carried through the existing release/strike path.
		# Otherwise applying saved deltas again would discard the held extension.
		if pose.has_meta("mobile_serve_baseline"):
			extended.set_meta("mobile_serve_baseline", Motion.ServeEdits.carry_extension_baseline(pose, extended))
		pose = extended
	pose.set_meta("held_hit_seconds", held_hit_seconds)
	pose.set_meta("held_hit_power", charge)
	return pose


func select_serve_style(id: int) -> bool:
	if id != Styles.valid_style(id): return false
	if _game == null or _game.game_state != _game.GameState.WAITING or not _pending_release.is_empty(): return false
	selected_serve_style = Styles.valid_style(id)
	_preview_key = ""
	serve_style_changed.emit(selected_serve_style)
	return true


func get_serve_style_options() -> Array[Dictionary]:
	return Styles.options()


func get_serve_timing_state() -> Dictionary:
	if not _pending_release.is_empty():
		return {"phase": _pending_release.phase, "progress": clampf(_release_elapsed / maxf(float(_pending_release.contact_at), 0.001), 0, 1), 
			"style": _pending_release.style, "can_release": false, "locked": true, "time_to_contact": maxf(0.0, float(_pending_release.contact_at) - _release_elapsed)}
	if not _follow_through.is_empty():
		return {"phase": "CONTACT" if float(_follow_through.elapsed) < 0.06 else "RECOVERY", "progress": 1.0, 
			"style": _follow_through.style, "can_release": false, "locked": true, "time_to_contact": 0.0}
	return {"phase": "HELD", "progress": 0.0, "style": selected_serve_style, "can_release": _game != null and _game.game_state == _game.GameState.WAITING and not get_tree().paused and not ball.freeze and _attempt_permitted(), 
		"locked": false, "time_to_contact": 0.0, "charge": get_charge_ratio()}


func _legal_service_feet(server, team: int) -> bool:
	return _check_service_feet(server, team).valid


func _check_service_feet(server, team: int) -> Dictionary:
	var footprints: Array[Dictionary] = Feet.footprints(server)
	var grounded: int = 0
	var from_right: bool = _from_right()
	var positive_x: bool = from_right == (server.court_side == 0)
	for foot in footprints:
		if not foot.grounded: continue
		grounded += 1
		if (server.court_side == 0 and foot.min.z <= PickleballConstants.BASELINE_Z) or (server.court_side == 1 and foot.max.z >= - PickleballConstants.BASELINE_Z):
			return {"valid": false, "boundary": "baseline", "detail": "Keep grounded shoes fully behind the baseline"}
		if foot.min.x < - PickleballConstants.COURT_WIDTH * 0.5 or foot.max.x > PickleballConstants.COURT_WIDTH * 0.5:
			return {"valid": false, "boundary": "sideline", "detail": "Keep grounded shoes inside the sideline extension"}
		if (positive_x and foot.min.x <= 0.0) or (not positive_x and foot.max.x >= 0.0):
			return {"valid": false, "boundary": "centerline", "detail": "Keep grounded shoes on your %s service side" % ("right" if from_right else "left")}
	if grounded == 0:
		return {"valid": false, "boundary": "airborne", "detail": "Plant at least one foot before serving"}
	return {"valid": true, "boundary": "", "detail": ""}


func _target_for_server(team: int) -> Vector3:
	var server = _server_for_team(team)
	if server == null: return Vector3.INF
	if not server.is_ai and _game.aim_controller: return _game.aim_controller.get_target()
	if _game.doubles_mode:
		var target: Vector3 = _game.doubles_controller.service_target()
		target.y = _Flight.FLOOR_REST_Y
		return target
	var from_right: bool = (_game.get_server_score(team) % 2) == 0
	var x: float = maxf(_game.serve_aim_offset_x, 1.5) if from_right else minf(_game.serve_aim_offset_x, -1.5)
	if server.court_side == 0: x = -x
	return Vector3(x, _Flight.FLOOR_REST_Y, 4.6 if server.court_side == 1 else -4.6)





func get_serve_launch_position(is_red_side: bool) -> Vector3:
	var server = _server_for_team(1 if is_red_side else 0)
	if server == null: return Vector3.INF
	var release: Vector3 = get_held_ball_position() if is_red_side == (_game.serving_team == 1) else Vector3.INF
	return Styles.release_plan(server.global_position, server.court_side == 1, selected_serve_style, release).contact_position


func get_predicted_serve_launch(charge_ratio: float, from_red_side: bool = false, spin_mode: int = -1) -> Dictionary:
	var team: int = 1 if from_red_side else 0
	var style: int = selected_serve_style
	if spin_mode >= 0: style = [Styles.Style.FLAT, Styles.Style.TOPSPIN, Styles.Style.SLICE][clampi(spin_mode, 0, 2)]
	var server = _server_for_team(team)
	if server == null: return {}
	var release: Vector3 = get_held_ball_position() if team == _game.serving_team else Vector3.INF
	var plan: Dictionary = Styles.release_plan(server.global_position, server.court_side == 1, style, release)
	var target: Vector3 = _target_for_server(team)
	var key: String = "%d/%d/%.4f/%s/%s/%.3f" % [server.get_actor_id(), style, charge_ratio, str(plan.contact_position), str(target), _game.trajectory_arc_offset]
	if key == _preview_key and not _preview_launch.is_empty(): return _preview_launch
	_preview_key = key
	_preview_launch = Styles.solve_launch(_game.shot_physics, plan.contact_position, target, charge_ratio, server.court_side, style, _game.trajectory_arc_offset)
	return _preview_launch


func trigger_server_position_fault(reason: String = "", foot_detail: String = "") -> void :
	if _game.doubles_mode and _game.doubles_state.active_rally.is_empty():
		scoreboard_ui.set_state_text("Correct service setup before releasing the ball")
		return
	if _service_fault_triggered:
		return
	_service_fault_triggered = true

	var total_score: int = _game.get_server_score()
	var serve_from_right: bool = (total_score % 2) == 0
	var serving_team: = _game.serving_team as int
	var server_name: String = "Blue" if serving_team == 0 else "Red"
	var expected_side: String = ""
	var actual_pos: Vector3 = _server().global_position
	var winner: int = 1 - serving_team

	if serving_team == 0:
		expected_side = "RIGHT (X>0)" if serve_from_right else "LEFT (X<0)"
	else:
		expected_side = "RIGHT (X<0)" if serve_from_right else "LEFT (X>0)"

	if RuntimePolicy.developer_tools: print("[FAULT] %s served from wrong zone | reason=%s expected=%s actual=(x:%.1f z:%.1f)" % [
		server_name, reason if reason != "" else "UNSPECIFIED", 
		expected_side, snappedf(actual_pos.x, 0.1), snappedf(actual_pos.z, 0.1)
	])
	var detail: String = foot_detail
	if detail.is_empty():
		detail = "Serve from behind the baseline" if reason == "FOOT_FAULT" else "Serve from your %s service side" % ("right" if serve_from_right else "left")
	if _game._is_practice():
		_game.practice_launcher.finish_attempt(winner, reason, detail)
	else:
		scoreboard_ui.show_fault("SERVE FAULT", detail)
		_game._on_point_scored(winner)





func _update_charge_ui(charge_ratio: float) -> void :
	var percent: int = mini(100, maxi(0, int(round(charge_ratio * 100.0))))
	if _game.game_state == _game.GameState.WAITING:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\nPower: %d%%  Aim: %s  Arc: %s" % [percent, _get_aim_label(), _get_arc_label()])
	elif _game.game_state == _game.GameState.PLAYING:
		scoreboard_ui.set_state_text("Swing Power: %d%%  Arc: %s" % [percent, _get_arc_label()])

func update_waiting_ui() -> void :
	if _game.game_state == _game.GameState.WAITING and not _serve_is_charging:
		scoreboard_ui.set_state_text("Hold SPACE to charge serve\n%s  Aim: %s  Arc: %s" % [_format_serve_call(), _get_aim_label(), _get_arc_label()])

func _get_aim_label() -> String:
	if _serve_aim_offset_x < -0.2:
		return "Left"
	if _serve_aim_offset_x > 0.2:
		return "Right"
	return "Center"

func _get_arc_label() -> String:
	var ARC_INTENT_STEP: = PickleballConstants.ARC_INTENT_STEP
	if is_zero_approx(_trajectory_arc_offset):
		return "Auto"
	if _trajectory_arc_offset > 0.0:
		return "High +%d" % int(round(_trajectory_arc_offset / ARC_INTENT_STEP))
	return "Low %d" % int(round(_trajectory_arc_offset / ARC_INTENT_STEP))

func _format_serve_call() -> String:
	if _game.doubles_mode: return _game._format_serve_call()
	var serving_team: = _game.serving_team as int
	var score_left: = _game.score_left as int
	var score_right: = _game.score_right as int
	if serving_team == 0:
		return "Blue serves: %d - %d" % [score_left, score_right]
	else:
		return "Red serves: %d - %d" % [score_right, score_left]

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





func _log_serve(serving_team: int, pos: Vector3, vel: Vector3, charge: float) -> void :
	var score_left: = _game.score_left as int
	var score_right: = _game.score_right as int
	var total_score: int = score_left if serving_team == 0 else score_right
	var serve_from_right: bool = (total_score % 2) == 0
	var target_on_positive_x: bool = serve_from_right == (serving_team == 1)
	var target_diag: String = "RIGHT" if target_on_positive_x else "LEFT"
	var server_name: String = "BLUE" if serving_team == 0 else "RED"
	if RuntimePolicy.developer_tools: print("[SERVE %s] pos=%s vel=%s charge=%s score=%d from_right=%s target=%s (X<0=left, X>0=right)" % [
		server_name, pos, vel, snappedf(charge, 0.01), total_score, 
		serve_from_right, target_diag
	])
