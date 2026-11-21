extends Node
## Normal-match owner for a physically admitted reach. Ball integration,
## outgoing launch, scoring, and earlier all-body contact remain game authority.
const Identity = preload("res://scripts/special_action_identity.gd")
const CancelBridge = preload("res://scripts/grounded_cancel_bridge.gd")
const Grounded = preload("res://scripts/match_grounded_reach.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Finite = preload("res://scripts/finite_paddle_contact.gd")
const ContactShape = preload("res://scripts/paddle_clearance.gd")
const QUERY_STEP := 1.0 / 120.0
const IK_FIELDS := ["right_foot_smooth", "left_foot_smooth", "right_foot_locked", "left_foot_locked", "right_foot_lock_pos", "left_foot_lock_pos", "right_step_t", "left_step_t", "_right_yaw", "_left_yaw", "right_contact_serial", "left_contact_serial", "_knee_yaw", "_run_active", "_run_stopping", "_moving", "_live_stance_initialized", "_active_side", "_live_step_origin", "_step_elapsed", "_step_duration", "_last_body_position", "_airborne"]
var game
var actor
var helper
var kind := "REACH"
var intent: Dictionary = {}
var active := false
var contact_window_active: bool:
	get: return active and not _recovery_only and helper != null and helper.contact_window()
var stroke_contact_active: bool:
	get: return active and not _recovery_only and helper != null and helper.elapsed >= helper.CONTACT_OPEN and helper.elapsed <= helper.CONTACT_CLOSE
var stroke_serial := 0
var max_physics_root_step := 0.0
var max_physics_speed := 0.0
var physics_steps := 0
var last_contact_evidence: Dictionary = {}
var status := "idle"
var dive_enabled := false
var _grounded
var _cancel_bridge
var _before_bridge_tick: Dictionary = {}
var movement_release_latency := -1.0
var cancel_pose_seconds := 0.0
var _dive
var _recovery_only := false
var _entry_channels: Array = []
var _entry_pose: PostureDefinition
var _previous_ball := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _previous_omega := Vector3.ZERO
var _previous_paddle := Transform3D.IDENTITY
var _previous_flight := -1
var _previous_bounces := -1
var _sweep_valid := false
var _epoch := 0
var elapsed_recovery_wait := 0.0
var activation_timing: Dictionary = {}
var automatic_attempts := 0
var automatic_last_status := "not considered"
var automatic_selection_receipt: Dictionary = {}
var _automatic_flight := -1
var _automatic_attempted_flight := -1
var _automatic_probe_wait := 0.0
const AUTOMATIC_PROBE_INTERVAL := 0.075

func setup(owner, player) -> void:
	game = owner; actor = player
	name = "SpecialReachDriver"
	_grounded = Grounded.new(actor)
	set_process(false); set_physics_process(false)

func owns_presentation() -> bool:
	return active

func owns_movement() -> bool:
	return active and not bridge_active()

func bridge_active() -> bool:
	return _cancel_bridge != null and _cancel_bridge.active

func _state() -> Dictionary:
	var ball = actor._get_ball_ref()
	if Identity.describe(actor).is_empty():
		return {"playing": false, "paused": false, "in_play": false, "actor_id": -1, "team_id": -1, "court_side": -1, "player_num": -1, "last_hit_by": -1, "flight_id": -1, "bounces": 0, "jumping": false}
	return Identity.annotate(actor, {"playing": game.game_state == game.GameState.PLAYING and not game._tool_state_active(),
		"paused": actor.get_tree().paused, "in_play": ball != null and ball.is_in_play,
		"player_num": actor.player_num, "last_hit_by": ball.last_hit_by if ball != null else -1,
		"bounces": ball.bounces_since_last_hit if ball != null else 0,
		"flight_id": ball.flight_id if ball != null else -1, "jumping": actor.is_jumping,
		"last_hit_actor_id": ball.get_last_hit_actor_id() if ball != null else -1, "last_hit_team_id": ball.get_last_hit_team_id() if ball != null else -1, "last_hit_court_side": ball.get_last_hit_court_side() if ball != null else -1})

## Call only after the normal contact planner reports no reachable route.
## This cheap forecast is not a strike certificate and never moves the actor.
func reach_opportunity(delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> Dictionary:
	if actor == null or active: return {}
	if actor.is_ai and not _valid_delayed_selection(delayed_prediction, observed_state): return {}
	var state := _state()
	if int(state.flight_id) != _automatic_flight:
		_automatic_flight = int(state.flight_id); _automatic_probe_wait = 0.0
	if _automatic_attempted_flight == int(state.flight_id) or _automatic_probe_wait > 0.0: return {}
	_automatic_probe_wait = AUTOMATIC_PROBE_INTERVAL
	if not _grounded._eligible(state) or not _grounded._supported_entry(): return {}
	if actor.hitting.serving_visual_active or actor.hitting.is_in_follow_through: return {}
	if not actor.is_ai and actor._get_human_input().length_squared() > 0.0001: return {}
	if not _grounded._necessary_entry_fit(): return {}
	var ball = actor._get_ball_ref()
	var prediction: Dictionary = delayed_prediction if actor.is_ai else (delayed_prediction if not delayed_prediction.is_empty() else Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 0.60))
	var base_bounces: int = int(observed_state.bounces) if actor.is_ai else ball.bounces_since_last_hit
	state["forecast_bounces"] = base_bounces
	var fault_time: float = Grounded.Planner.predicted_fault_time(actor, Identity.forecast_ball(ball, base_bounces), prediction)
	var bounds := Rect2(actor.min_x, actor.min_z, actor.max_x - actor.min_x, actor.max_z - actor.min_z)
	for sample: Dictionary in prediction.get("samples", []):
		var time := float(sample.get("time", 0.0))
		if time < 0.405: continue
		if time > Grounded.CONTACT_CLOSE or time >= fault_time: break
		if base_bounces + int(sample.get("bounces", 0)) != 1: continue
		var forecast := state.duplicate(); forecast.bounces = 1
		var point := sample.duplicate(); point.bounces = 0
		var coarse: Dictionary = Grounded.Candidate.choose_plan(actor.global_position, forecast, [point], bounds)
		if not coarse.is_empty():
			return Identity.annotate(actor, {"point": coarse.point, "time": coarse.time, "flight_id": ball.flight_id})
	return {}

func maybe_start_reach(charge: float, requested_intent: Dictionary, delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> bool:
	return _attempt_automatic(reach_opportunity(delayed_prediction, observed_state), charge, requested_intent, delayed_prediction, observed_state)

func maybe_start_ai(delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> bool:
	automatic_selection_receipt = {"opportunity_found": false, "attempt_consumed": false, "full_preflights": 0, "accepted": false, "reason": "no opportunity"}
	if actor == null or not actor.is_ai or actor.ai_brain == null: return false
	if not _valid_delayed_selection(delayed_prediction, observed_state):
		automatic_selection_receipt.reason = "missing or stale delayed perception"; return false
	var opportunity := reach_opportunity(delayed_prediction, observed_state)
	if opportunity.is_empty(): return false
	automatic_selection_receipt.opportunity_found = true
	var chosen: Dictionary = actor.ai_brain.get_or_commit_motion_intent(opportunity.point, opportunity.time)
	if chosen.is_empty(): return false
	var requested := chosen.duplicate(true)
	requested["shot_intent"] = str(chosen.get("intent", "AUTO"))
	requested["motion_context"] = actor.ai_brain.motion_context.duplicate(true)
	return _attempt_automatic(opportunity, float(chosen.get("charge", 0.25)), requested, delayed_prediction, observed_state)

func _attempt_automatic(opportunity: Dictionary, charge: float, requested: Dictionary, delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> bool:
	if not Identity.matches(actor, opportunity) or not requested.get("target", Vector3.INF).is_finite(): return false
	if actor.is_ai and not _valid_delayed_selection(delayed_prediction, observed_state): return false
	var ball = actor._get_ball_ref()
	if ball == null or ball.flight_id != int(opportunity.flight_id): return false
	# Even failed physical certification consumes this flight's one attempt.
	# Manual explicit activation remains available as a separate user action.
	_automatic_attempted_flight = ball.flight_id; automatic_attempts += 1
	var accepted := request_activation("REACH", charge, requested, delayed_prediction, observed_state)
	automatic_selection_receipt.merge({"opportunity_found": true, "attempt_consumed": true, "full_preflights": int(helper.timing.get("full_preflights", 0)) if helper != null and "timing" in helper else 0, "accepted": accepted, "reason": status}, true)
	automatic_last_status = status
	return accepted

func request_activation(requested_kind: String, charge: float, requested_intent: Dictionary, delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> bool:
	if active: return false
	var started := Time.get_ticks_usec()
	var accepted := _activate(requested_kind, charge, requested_intent, delayed_prediction, observed_state)
	activation_timing = {"total_usec": Time.get_ticks_usec() - started, "accepted": accepted,
		"helper": helper.timing.duplicate(true) if helper != null and "timing" in helper else {}}
	return accepted

func _activate(requested_kind: String, charge: float, requested_intent: Dictionary, delayed_prediction: Dictionary = {}, observed_state: Dictionary = {}) -> bool:
	if active or Identity.describe(actor).is_empty() or actor.posture.editor_preview_mode: return false
	if actor.is_ai and not _valid_delayed_selection(delayed_prediction, observed_state): status = "missing or stale delayed perception"; return false
	if actor.erne_action != null and actor.erne_action.active: status = "another movement owns presentation"; return false
	if actor.hitting.serving_visual_active or actor.hitting.is_in_follow_through: status = "current stroke is still active"; return false
	kind = requested_kind.to_upper()
	if kind not in ["REACH", "GROUNDED", "DIVE"]: status = "unknown reach kind"; return false
	if kind == "DIVE":
		if not dive_enabled: status = "dive physical acceptance is not complete"; return false
		if _dive == null: _dive = load("res://scripts/match_dive_action.gd").new(actor)
		helper = _dive
	else: kind = "REACH"; helper = _grounded
	intent = requested_intent.duplicate(true); intent["charge"] = clampf(charge, 0.0, 1.0)
	if kind == "DIVE": intent["emergency_dive"] = true
	var ball = actor._get_ball_ref()
	if ball == null: return false
	var state := _state()
	var prediction: Dictionary = delayed_prediction if actor.is_ai else (delayed_prediction if not delayed_prediction.is_empty() else Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 0.65))
	if actor.is_ai: state["forecast_bounces"] = int(observed_state.bounces)
	var candidate: Dictionary = helper.choose_plan(prediction, state, intent)
	if candidate.is_empty() or not helper.begin(candidate, state): status = helper.status; return false
	_entry_pose = actor.get_runtime_posture_def().duplicate(true)
	_entry_channels = [helper._channels(actor.right_arm_node, false), helper._channels(actor.left_arm_node, true)]
	if actor.posture.human_contact != null: actor.posture.human_contact.cancel(false)
	if actor.hitting.paddle_swing_tween != null and actor.hitting.paddle_swing_tween.is_valid(): actor.hitting.paddle_swing_tween.kill()
	actor.hitting.charge_visual_active = false; actor.hitting.is_in_follow_through = false
	actor.hitting.stroke_contact_active = false
	actor.cancel_contextual_jump()
	active = true; _recovery_only = false; _epoch += 1; stroke_serial += 1
	elapsed_recovery_wait = 0.0; last_contact_evidence = {}
	_cancel_bridge = null; movement_release_latency = -1.0; cancel_pose_seconds = 0.0
	max_physics_root_step = 0.0; max_physics_speed = 0.0; physics_steps = 0
	if not helper.apply(): active = false; status = helper.status; return false
	actor.reset_support_clock(); _remember_ball()
	status = "grounded reach" if kind == "REACH" else "emergency dive"
	return true

func physics_step(delta: float, manual_input := Vector3.ZERO) -> void:
	if not active or not is_finite(delta) or delta <= 0.0: return
	if actor.posture.editor_preview_mode or game._tool_state_active():
		reset()
		return
	var state := _state()
	if state.paused: return
	if manual_input.length_squared() > 0.0001: cancel("manual movement requested; recovering support")
	if bridge_active(): actor.reset_support_clock(); return
	var ball = actor._get_ball_ref()
	if not state.playing or not state.in_play or (not helper.contacted and int(state.flight_id) != int(helper.flight_id)):
		cancel("rally changed; recovering support")
	if bridge_active(): actor.reset_support_clock(); return
	var start_elapsed: float = helper.elapsed
	var start_root: Vector3 = actor.global_position
	var end_ball: Vector3 = ball.global_position
	var end_velocity: Vector3 = ball.linear_velocity
	var end_omega: Vector3 = ball.angular_velocity
	var movement: Dictionary
	if _recovery_only and kind == "REACH":
		# Presentation follows its certified physical finish after cancellation.
		# Contact is closed immediately; no fake hit/flight or extra deadline.
		helper.elapsed = minf(helper.Motion.DURATION, helper.elapsed + delta)
		helper.latest_motion = helper._motion(helper.elapsed)
		movement = {"root_target": helper._origin + helper.latest_motion.root_offset}
	else: movement = helper.advance(delta, state)
	if helper.active:
		_move_root(movement.get("root_target", actor.global_position))
		if not helper.apply():
			cancel("movement or actual pose blocked")
	else: _release_ownership()
	if not helper.active:
		_release_ownership(); _remember_ball(); return
	physics_steps += 1
	max_physics_root_step = maxf(max_physics_root_step, actor.global_position.distance_to(start_root))
	max_physics_speed = maxf(max_physics_speed, actor.global_position.distance_to(start_root) / delta)
	actor.current_velocity = (actor.global_position - start_root) / delta
	actor.current_velocity.y = 0.0; actor.velocity = actor.current_velocity
	var end_elapsed: float = helper.elapsed
	if not _recovery_only and not helper.contacted and _sweep_valid and _previous_flight == ball.flight_id and _previous_bounces == ball.bounces_since_last_hit:
		var callback_epoch: int = ball.contact_callback_epoch()
		var driver_epoch: int = _epoch
		_try_frame_contact(start_elapsed, end_elapsed, delta, end_ball, end_velocity, end_omega)
		if callback_epoch != ball.contact_callback_epoch() or driver_epoch != _epoch: return
	if _recovery_only: elapsed_recovery_wait += delta
	if actor.stamina != null: actor.stamina.advance(delta, actor.current_velocity.length(), state.playing, not state.playing)
	actor.reset_support_clock(); actor._nvz_state.update(actor)
	_remember_ball()
	if not helper.active: _release_ownership()

func _move_root(target: Vector3) -> void:
	# Use the same actual court-root bounds as ordinary Player movement.
	if actor.bounds_ready:
		target.x = clampf(target.x, actor.min_x, actor.max_x)
		target.z = clampf(target.z, actor.min_z, actor.max_z)
	target.y = actor.ground_y
	actor.global_position = target

func _present_at(time: float) -> bool:
	helper.elapsed = time
	var movement: Dictionary = helper.advance(0.0, _state())
	if not helper.active: return false
	_move_root(movement.get("root_target", actor.global_position))
	# Contact sees actual instantaneous root momentum, not the probe rewind.
	var epsilon := 0.0001
	var before: Dictionary = helper._motion(maxf(0.0, time - epsilon))
	var after: Dictionary = helper._motion(minf(helper.Motion.DURATION, time + epsilon))
	actor.current_velocity = (Vector3(after.root_offset) - Vector3(before.root_offset)) / (2.0 * epsilon)
	actor.velocity = actor.current_velocity
	return helper.apply()

func _try_frame_contact(start: float, finish: float, delta: float, end_ball: Vector3, end_velocity: Vector3, end_omega: Vector3) -> void:
	var low: float = maxf(start, helper.CONTACT_OPEN)
	var high: float = minf(finish, helper.CONTACT_CLOSE)
	if high < low or delta <= 0.0: return
	var endpoint := _snapshot_presentation()
	var epoch := _epoch
	var ball_epoch: int = actor._get_ball_ref().contact_callback_epoch()
	var count := maxi(1, ceili((high - low) / QUERY_STEP))
	var previous_time := low
	if not _present_at(previous_time): _restore_presentation(endpoint); cancel("TOI pose invalid"); return
	var previous_paddle: Transform3D = actor.paddle_node.global_transform
	for index in range(1, count + 1):
		var time := lerpf(low, high, float(index) / count)
		if not _present_at(time): _restore_presentation(endpoint); cancel("TOI pose invalid"); return
		var from_fraction := clampf((previous_time - start) / delta, 0.0, 1.0)
		var to_fraction := clampf((time - start) / delta, 0.0, 1.0)
		var fraction := Finite.physical_sweep_fraction(_previous_ball.lerp(end_ball, from_fraction), _previous_ball.lerp(end_ball, to_fraction), previous_paddle, actor.paddle_node.global_transform, actor._get_ball_ref().BALL_RADIUS)
		if fraction >= 0.0:
			var guess := lerpf(from_fraction, to_fraction, fraction)
			var found := _find_actual_touch(start, delta, guess, to_fraction, end_ball)
			if found >= 0.0:
				var ball = actor._get_ball_ref()
				ball.global_position = _previous_ball.lerp(end_ball, found)
				ball.linear_velocity = _previous_velocity.lerp(end_velocity, found)
				ball.angular_velocity = _previous_omega.lerp(end_omega, found)
				last_contact_evidence = {"swept": true, "fraction": found, "elapsed": delta,
					"ball_from": _previous_ball, "ball_to": end_ball, "paddle_from": _previous_paddle,
					"paddle_to": endpoint.paddle,
					"actual_paddle": actor.paddle_node.global_transform, "actual_root": actor.global_position,
					"flight_id": ball.flight_id, "stroke_serial": stroke_serial, "kind": kind,
					"physical_report": physical_contact_report(), "contact_window": contact_window_active, "stroke_contact_active": stroke_contact_active, "action_elapsed": helper.elapsed, "incoming_velocity": ball.linear_velocity}
				last_contact_evidence = Identity.annotate(actor, last_contact_evidence)
				var accepted: bool = game._apply_special_reach_contact(self, last_contact_evidence)
				if _epoch != epoch or ball_epoch != ball.contact_callback_epoch(): return
				if not accepted: last_contact_evidence["admission_authority"] = game.contact_authority.last_evidence.duplicate(true)
				_restore_presentation(endpoint)
				if accepted:
					helper.mark_contact(); status = "contact accepted; recovering support"
					game.contact_authority.capture_remainder_endpoint()
					last_contact_evidence["remainder"] = game.contact_authority.continue_paddle_remainder(actor, delta, found)
				else:
					if ball.is_in_play and ball.flight_id == _previous_flight:
						ball.global_position = end_ball; ball.linear_velocity = end_velocity; ball.angular_velocity = end_omega
					cancel("contact authority rejected; recovering support")
				return
		previous_time = time; previous_paddle = actor.paddle_node.global_transform
	_restore_presentation(endpoint)

func _find_actual_touch(start: float, delta: float, guess: float, end: float, end_ball: Vector3) -> float:
	# The finite sweep gives a bracket only. Reproduce the actual articulated
	# path at TOI and require real finite touch and original rig budgets there.
	var lower := guess
	for index in range(9):
		var probe := lerpf(guess, end, float(index) / 8.0)
		if not _present_at(start + delta * probe): return -1.0
		var report: Dictionary = helper.displayed_report(_previous_ball.lerp(end_ball, probe))
		if report.valid and _physical_touch(_previous_ball.lerp(end_ball, probe)) and contact_window_active:
			if index == 0: return probe
			var upper := probe
			for iteration in range(8):
				var middle := (lower + upper) * 0.5
				if not _present_at(start + delta * middle): return -1.0
				var tested: Dictionary = helper.displayed_report(_previous_ball.lerp(end_ball, middle))
				if tested.valid and _physical_touch(_previous_ball.lerp(end_ball, middle)): upper = middle
				else: lower = middle
			if not _present_at(start + delta * upper): return -1.0
			return upper
		lower = probe
	return -1.0

func _physical_touch(point: Vector3) -> bool:
	if not point.is_finite(): return false
	# Preview tolerance never awards a stroke. Match execution waits for the
	# real finite head surface, then the common all-body authority checks TOI.
	var ball = actor._get_ball_ref()
	var gap: float = ContactShape.distance_to_head_shape(actor.paddle_node.global_transform.affine_inverse() * point) - ball.BALL_RADIUS
	return is_finite(gap) and gap <= 0.0

func physical_contact_report() -> Dictionary:
	if helper == null or actor == null: return {"valid": false, "finite_touch": false}
	if bridge_active(): return _cancel_bridge.displayed_report()
	return helper.displayed_report(actor._get_ball_ref().global_position)

func _snapshot_presentation() -> Dictionary:
	var state := {"rig": helper._snapshot(), "ik": {}, "helper": {}, "velocity": actor.current_velocity, "body_velocity": actor.velocity, "paddle": actor.paddle_node.global_transform, "root": actor.global_position}
	for key in IK_FIELDS:
		var value: Variant = actor.leg_ik.get(key)
		state.ik[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	for key in ["elapsed", "active", "contacted", "latest_motion", "handoff", "status", "diagnostics", "_feet_planted", "_last_grip_basis", "_last_grip_anchor", "cancelled", "_blocked_root", "_floor_support", "_current_pelvis"]:
		if key in helper:
			var value: Variant = helper.get(key)
			state.helper[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return state

func _restore_presentation(saved: Dictionary) -> void:
	helper._restore(saved.rig)
	for key in saved.ik:
		var value: Variant = saved.ik[key]
		actor.leg_ik.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	for key in saved.helper:
		var value: Variant = saved.helper[key]
		helper.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	actor.current_velocity = saved.velocity; actor.velocity = saved.body_velocity

func idle_step(delta: float) -> void:
	_automatic_probe_wait = maxf(0.0, _automatic_probe_wait - maxf(delta, 0.0))
	if not active and _dive != null: _dive.advance(delta, _state())

func present(_delta: float) -> void:
	# Physics is the only writer. Render keeps that exact certified display.
	if active: actor.reset_support_clock()

func before_normal_movement() -> void:
	if not bridge_active(): return
	_before_bridge_tick = _snapshot_presentation()
	# Unlike a contact-time pose probe, ordinary locomotion advances cadence,
	# swing origins and nested turn/setup state. A rejected bridge tick must
	# restore those clocks as well as the displayed anchors.
	_before_bridge_tick["normal_ik"] = _capture_script_fields(actor.leg_ik)
	_before_bridge_tick["motion_state"] = _capture_script_fields(actor.leg_ik.motion_state)
	_before_bridge_tick["drive_preparation"] = _capture_script_fields(actor.leg_ik.drive_preparation)

func _capture_script_fields(object) -> Dictionary:
	var result: Dictionary = {}
	for property in object.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0: continue
		var value: Variant = object.get(property.name)
		result[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func _restore_script_fields(object, fields: Dictionary) -> void:
	for key in fields: object.set(key, fields[key])

func bridge_step(delta: float) -> void:
	if not bridge_active(): return
	cancel_pose_seconds += delta; elapsed_recovery_wait += delta
	var moved: bool = _cancel_bridge.step(delta)
	if not moved:
		if not _before_bridge_tick.is_empty():
			_restore_presentation(_before_bridge_tick)
			_restore_script_fields(actor.leg_ik, _before_bridge_tick.normal_ik)
			_restore_script_fields(actor.leg_ik.motion_state, _before_bridge_tick.motion_state)
			_restore_script_fields(actor.leg_ik.drive_preparation, _before_bridge_tick.drive_preparation)
		actor.current_velocity = Vector3.ZERO; actor.velocity = Vector3.ZERO
	else:
		var step: float = actor.global_position.distance_to(_before_bridge_tick.get("root", actor.global_position))
		max_physics_root_step = maxf(max_physics_root_step, step)
		max_physics_speed = maxf(max_physics_speed, step / maxf(delta, .000001))
		physics_steps += 1
		if movement_release_latency < 0.0 and step > 0.0001: movement_release_latency = cancel_pose_seconds
		actor._nvz_state.update(actor)
	actor.reset_support_clock()
	status = _cancel_bridge.status
	if not _cancel_bridge.active:
		_release_ownership()
		status = "normal movement and pose recovered"

func cancel(reason := "cancelled") -> void:
	if not active: return
	if bridge_active(): return
	_recovery_only = true; status = reason
	if kind == "DIVE":
		helper.cancel(reason)
		if not helper.active: _release_ownership()
	else:
		_cancel_bridge = CancelBridge.new()
		_cancel_bridge.begin(actor, helper, _entry_pose, _entry_channels)
		helper.cancel(reason)
		actor._manual_motion_active = actor.current_velocity.length_squared() > 0.0001


func reset() -> void:
	_epoch += 1
	for motion in [_grounded, _dive]:
		if motion == null: continue
		if motion.has_method("reset"): motion.reset()
		else: motion.cancel("explicit match reset")
	active = false; _recovery_only = false; _sweep_valid = false
	_cancel_bridge = null; _before_bridge_tick.clear()
	status = "idle"; last_contact_evidence = {}; automatic_selection_receipt = {}
	_automatic_flight = -1; _automatic_attempted_flight = -1; _automatic_probe_wait = 0.0
	if actor != null: actor.reset_support_clock()

func _release_ownership() -> void:
	if not active: return
	active = false; _sweep_valid = false
	if _cancel_bridge == null:
		actor.current_velocity = Vector3.ZERO; actor.velocity = Vector3.ZERO
	if _entry_pose != null:
		actor.posture.transition_pose_blend = _entry_pose
		if actor.posture.human_contact != null: actor.posture.human_contact.visual_pose = _entry_pose
	actor.reset_support_clock()
	status = "support recovered" if _recovery_only else helper.status

func _remember_ball() -> void:
	var ball = actor._get_ball_ref()
	if ball == null: _sweep_valid = false; return
	_previous_ball = ball.global_position; _previous_velocity = ball.linear_velocity; _previous_omega = ball.angular_velocity
	_previous_paddle = actor.paddle_node.global_transform
	_previous_flight = ball.flight_id; _previous_bounces = ball.bounces_since_last_hit
	_sweep_valid = active and ball.is_in_play

func _valid_delayed_selection(prediction: Dictionary, observed_state: Dictionary) -> bool:
	if actor == null or actor.ai_brain == null or not Identity.matches(actor, observed_state): return false
	var ball = actor._get_ball_ref()
	return ball != null and bool(observed_state.get("ready", false)) and int(observed_state.get("bounces", -1)) in [0, 1] and actor.ai_brain._perception_ready and int(observed_state.get("flight_id", -1)) == actor.ai_brain._observed_flight_id and ball.flight_id == actor.ai_brain._observed_flight_id and not prediction.get("samples", []).is_empty()
