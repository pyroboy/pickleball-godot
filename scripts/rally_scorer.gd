class_name RallyScorer extends Node
const ActorIdentity = preload("res://scripts/contact_actor_identity.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")






















signal rally_ended(winner: int, reason: String, detail: String)
## Ball is dead, but scoring waits for any unfinished volley momentum.
signal rally_pending(winner: int, reason: String, detail: String)
## A body-hit fault was accepted (the rally is over or pending for it). Cosmetic
## listeners only (fx/body_hit_fx.gd): evidence holds "point"/"normal" when the
## contact authority found it; empty for a physics-capsule contact.
signal body_struck(actor_id: int, evidence: Dictionary)
const SurfaceContacts = preload("res://scripts/player_surface_contacts.gd")
var _pending_result: Dictionary = {}
var _scene_rule_epoch := 0
var _deferred_rule_interval: Dictionary = {}
var _physical_body_contacts: Dictionary = {}

const _NetProfile = preload("res://scripts/net_profile.gd")
const _NVZState = preload("res://scripts/player_nvz_state.gd")


const FAULT_OUT_OF_BOUNDS: = "OUT_OF_BOUNDS"
const FAULT_DOUBLE_BOUNCE: = "DOUBLE_BOUNCE"
const FAULT_BALL_IN_NET: = "BALL_IN_NET"
const FAULT_KITCHEN_VOLLEY: = "KITCHEN_VOLLEY"
const FAULT_MOMENTUM: = "MOMENTUM"
const FAULT_TWO_BOUNCE_RULE: = "TWO_BOUNCE_RULE"
const FAULT_DOUBLE_CONTACT := "DOUBLE_CONTACT"
const FAULT_BODY_HIT: = "BODY_HIT"
const FAULT_SHORT_SERVE: = "SHORT_SERVE"
const FAULT_WRONG_SERVICE_COURT: = "WRONG_SERVICE_COURT"
const FAULT_FOOT_FAULT: = "FOOT_FAULT"
const FAULT_WRONG_HALF: = "WRONG_HALF"
const FAULT_NET_PLANE := "NET_PLANE"
const FAULT_OPPONENT_COURT := "OPPONENT_COURT"
const FAULT_NET_POST := "NET_POST"
const FAULT_NET_TOUCH: = "NET_TOUCH"


const NET_TOUCH_Z_TOLERANCE: float = 0.15
const BODY_HIT_COOLDOWN_MS: int = 300
const COURT_LINE_EPSILON: float = 0.000001


var _ball
var _actor_registry = null
var _serve_court_side := 0
var _player_left
var _player_right
var _active: bool = false
var _serving_team: int = 0
var _serving_from_right: bool = true
var _serve_was_hit: bool = false
var _service_fault_triggered: bool = false

var _last_volley_time_msec: int = 0
var _last_volley_player: int = -1


var _volley_momentum_watches: Dictionary = {}
const SHOE_HALF_LENGTH: = 0.13
const BALANCE_CONFIRM_MS: = 120

var _last_paddle_hit_msec: int = 0

var _net_touch_fired: bool = false




func bind(ball_ref, player_left_ref, player_right_ref) -> void :
	_ball = ball_ref
	_player_left = player_left_ref
	_player_right = player_right_ref
	for index in 2:
		var actor = [_player_left, _player_right][index]
		if is_instance_valid(actor) and not ActorIdentity.valid(actor): actor.set_meta("legacy_contact_actor_id", index)
	if "actor_registry" in ball_ref: _actor_registry = ball_ref.actor_registry


	if ball_ref is Object and ball_ref.has_signal("bounced"):
		ball_ref.bounced.connect(_on_ball_bounced)
	if ball_ref is Object and ball_ref.has_signal("hit_by_paddle"):
		ball_ref.hit_by_paddle.connect(_on_any_paddle_hit)
	if ball_ref is Object and ball_ref.has_signal("hit_player_body"):
		ball_ref.hit_player_body.connect(_on_ball_hit_player_body)


func start_rally(serving_team: int, serving_from_right: bool) -> void :
	_scene_rule_epoch += 1
	_deferred_rule_interval.clear()
	_pending_result.clear()
	_physical_body_contacts.clear()
	_serving_team = serving_team
	_serve_court_side = _court_side_for_team(serving_team)
	_serving_from_right = serving_from_right
	_serve_was_hit = false
	_service_fault_triggered = false
	_last_volley_time_msec = 0
	_last_volley_player = -1
	_volley_momentum_watches.clear()
	_last_paddle_hit_msec = 0
	_net_touch_fired = false
	_active = true

func end_rally() -> void:
	# A dead ball does not erase momentum (11.A.2). Explicit practice/reset
	# cancellation uses cancel_rally(); ordinary scoring uses the pending API.
	_active = false
	_net_touch_fired = false

func cancel_rally() -> void:
	_scene_rule_epoch += 1
	_deferred_rule_interval.clear()
	_active = false
	_pending_result.clear()
	_last_volley_player = -1
	_volley_momentum_watches.clear()
	_net_touch_fired = false

func set_active(active: bool) -> void:
	_active = active

func has_pending_settlement() -> bool:
	return not _pending_result.is_empty()

func settle_pending_rally(delta: float = -1.0) -> bool:
	if _contact_simulation_unresolved(): return false
	if _pending_result.is_empty(): return true
	var momentum: Dictionary = check_momentum_fault(delta)
	if momentum.get("unresolved", false): return false
	if not momentum.get("valid", true):
		_pending_result.clear()
		_finalize(momentum)
		return true
	if _volley_momentum_watches.is_empty():
		var settled: Dictionary = _pending_result.duplicate()
		_pending_result.clear()
		_finalize(settled)
		return true
	return false

func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("rally_scorer.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	if _contact_simulation_unresolved(): return
	if _ball != null and _ball.has_method("deferred_scene_interval"):
		var pending: Dictionary = _ball.deferred_scene_interval()
		if not pending.is_empty():
			# Observe rules after the same completed physical interval, once.
			# End-rally retains momentum; explicit start/cancel invalidates this ticket.
			_deferred_rule_interval = {"frame": pending.frame, "flight": pending.flight,
				"delta": delta, "epoch": _scene_rule_epoch}
			return
	_process_ordered_rules(delta)

func resume_deferred_scene_rules(pending: Dictionary) -> void:
	if _deferred_rule_interval.is_empty() or _contact_simulation_unresolved(): return
	var ticket: Dictionary = _deferred_rule_interval
	if int(ticket.frame) != int(pending.get("frame", -1)) or int(ticket.flight) != int(pending.get("flight", -1)): return
	_deferred_rule_interval = {}
	if int(ticket.epoch) != _scene_rule_epoch or int(ticket.frame) != Engine.get_physics_frames(): return
	_process_ordered_rules(float(ticket.delta))

func _process_ordered_rules(delta: float) -> void:
	if _contact_simulation_unresolved(): return
	if has_pending_settlement():
		settle_pending_rally(delta)
		return
	if not _active or _ball == null: return
	var result: Dictionary = check_net_touch()
	if not result.get("valid", true):
		_emit(result); return
	result = check_net_plane()
	if not result.get("valid", true):
		_emit(result); return
	result = check_momentum_fault(delta)
	if not result.get("valid", true): _emit(result)


func on_ball_hit_post(_point: Vector3) -> void:
	if not _active or _ball == null: return
	var hitter: int = int(_ball.get("last_hit_by"))
	if hitter not in [0, 1]: return
	_emit({"valid": false, "winner": 1 - hitter, "reason": FAULT_NET_POST,
		"detail": "%s: ball struck a net post" % ("BLUE" if hitter == 0 else "RED")})

func _on_ball_bounced(bounce_pos: Vector3) -> void :
	if not _active:
		return

	# Only the first ground contact determines whether the shot landed out.
	# Crossing a boundary in the air, before or after a legal bounce, stays live.
	if _ball != null and int(_ball.get("bounces_since_last_hit")) == 1:
		var landing: = check_out_of_bounds(bounce_pos)
		if not landing.get("valid", true):
			_emit(landing);return

	if not _serve_was_hit and _ball != null and _ball.get("last_hit_by") == _serving_team and _ball.get("bounces_since_last_hit") == 1:
		var svc: = check_service_ball_landed(bounce_pos)
		if not svc.get("valid", true):
			_emit(svc);return
		_serve_was_hit = true

	var result: = check_double_bounce_and_net_ball(bounce_pos)
	if not result.get("valid", true):
		_emit(result)

func _on_any_paddle_hit(team_id: int) -> void:
	var number: int = _ball.get_last_hit_actor_id() if _ball != null and _ball.has_method("get_last_hit_actor_id") else -1
	if number < 0: number = ActorIdentity.actor_id(ActorIdentity.unique_team_actor(_actor_registry, team_id, [_player_left, _player_right]))
	if _actor(number) == null or _team(number) != team_id: return
	_on_actor_paddle_hit(number)

func _on_actor_paddle_hit(actor_id: int) -> void :
	if not _active or _actor(actor_id) == null:
		return
	_last_paddle_hit_msec = Time.get_ticks_msec()

	var tbr: = check_actor_two_bounce_rule(actor_id)
	if not tbr.get("valid", true):
		_emit(tbr);return

	var player_z: float = _actor(actor_id).global_position.z
	var kv: = check_actor_kitchen_volley_at_hit(actor_id, player_z)
	if not kv.get("valid", true):
		_emit(kv);return

	if _ball != null and _ball.get("was_volley") == true:
		_last_volley_time_msec = Time.get_ticks_msec()
		_last_volley_player = actor_id
		_volley_momentum_watches[actor_id] = {"time": _last_volley_time_msec, "stable_since": -1}

func on_actor_illegal_hitting_surface_contact(actor_id: int, reason: String, evidence: Dictionary) -> void:
	if not _active or _ball == null or _actor(actor_id) == null: return
	if _event_actor(_team(actor_id), evidence) != actor_id: return
	if reason not in [FAULT_TWO_BOUNCE_RULE, FAULT_KITCHEN_VOLLEY, FAULT_NET_PLANE, FAULT_DOUBLE_CONTACT]: return
	if not evidence.get("hit", false) or evidence.get("ambiguous", false) or evidence.get("kind", "body") not in ["legal_hand", "legal_paddle"]: return
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else -1
	var key: String = "illegal_hitting_surface/%d/%d/%s" % [flight, actor_id, reason]
	if _physical_body_contacts.has(key): return
	_physical_body_contacts[key] = true
	_emit({"valid": false, "winner": 1 - _team(actor_id), "reason": reason,
		"detail": "%s: illegal hitting-surface contact (%s)" % [("BLUE" if _team(actor_id) == 0 else "RED"), reason.replace("_", " ").to_lower()], "contact": evidence})

func on_actor_illegal_repeat_contact(actor_id: int, evidence: Dictionary) -> void:
	if not _active or _ball == null or _actor(actor_id) == null: return
	if _event_actor(_team(actor_id), evidence) != actor_id: return
	if int(_ball.get("last_hit_by")) != _team(actor_id): return
	if not evidence.get("new_contact", false) or not evidence.get("fault", false): return
	if evidence.get("ambiguous", false): return
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else -1
	var key: String = "repeat/%d/%d" % [flight, actor_id]
	if _physical_body_contacts.has(key): return
	_physical_body_contacts[key] = true
	_emit({"valid": false, "winner": 1 - _team(actor_id), "reason": FAULT_DOUBLE_CONTACT,
		"detail": "%s: repeated contact outside one continuous single-direction stroke" % ("BLUE" if _team(actor_id) == 0 else "RED"), "contact": evidence})

func on_actor_body_contact(actor_id: int, evidence: Dictionary) -> void:
	# Exact rig contacts have no global post-paddle immunity. Ambiguous CCD
	# blocks a strike in the caller but is not evidence for awarding a fault.
	if not _active or _ball == null or _actor(actor_id) == null: return
	if _event_actor(_team(actor_id), evidence) != actor_id: return
	if not evidence.get("hit", false) or evidence.get("ambiguous", false): return
	if evidence.get("kind", "body") in ["legal_hand", "legal_paddle"]: return
	if int(_ball.get("bounces_since_last_hit")) >= 2: return
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else -1
	var key: String = "%d/%d" % [flight, actor_id]
	if _physical_body_contacts.has(key): return
	_physical_body_contacts[key] = true
	# Bench evidence for tools/shot_report.py: which body part the ball struck.
	var struck: Vector3 = evidence.get("point", Vector3.ZERO)
	PerfMonitor.note("body_hit", {"actor": actor_id, "part": str(evidence.get("part", "")), "height": snappedf(struck.y, 0.01),
		"own_shot": int(_ball.get("last_hit_actor_id")) == actor_id if "last_hit_actor_id" in _ball else false})
	_emit({"valid": false, "winner": 1 - _team(actor_id), "reason": FAULT_BODY_HIT,
		"detail": "%s: ball struck the player" % ("BLUE" if _team(actor_id) == 0 else "RED"), "contact": evidence})
	if not _active: body_struck.emit(actor_id, evidence)

func _on_ball_hit_player_body(player_num: int) -> void :
	if not _active:
		return
	var since_paddle: int = Time.get_ticks_msec() - _last_paddle_hit_msec
	if since_paddle < BODY_HIT_COOLDOWN_MS:
		return

	if _ball != null and int(_ball.get("bounces_since_last_hit")) >= 2:
		return
	var hitter_name: String = "Blue" if player_num == 0 else "Red"
	_emit({
		"valid": false, 
		"winner": 1 - player_num, 
		"reason": FAULT_BODY_HIT, 
		"detail": "%s: Ball struck the player" % hitter_name.to_upper(), 
	})
	if not _active and _ball != null:
		var struck = _nearest_team_actor_to_ball(player_num)
		if struck != null: body_struck.emit(ActorIdentity.actor_id(struck), {})





func _nearest_team_actor_to_ball(team: int):
	var best = null
	var best_d: float = INF
	for actor in ActorIdentity.players(_actor_registry, [_player_left, _player_right]):
		if not is_instance_valid(actor) or ActorIdentity.team_id(actor) != team: continue
		var d: float = actor.global_position.distance_squared_to(_ball.global_position)
		if d < best_d: best = actor; best_d = d
	return best

func check_out_of_bounds(bounce_pos: Vector3) -> Dictionary:
	if _ball == null:
		return {"valid": true}
	if not is_outside_painted_court(bounce_pos):
		return {"valid": true}

	var last_hit: int = int(_ball.get("last_hit_by"))
	var winner: int = 1 - last_hit if last_hit in [0, 1] else _team_for_side(1 if bounce_pos.z > 0 else 0)
	var detail: String = "%s shot out" % ("Blue" if last_hit == 0 else "Red") if last_hit in [0, 1] else "ball out (no hit recorded)"
	return {
		"valid": false,
		"winner": winner,
		"reason": FAULT_OUT_OF_BOUNDS,
		"detail": detail,
	}


static func is_outside_painted_court(bounce_pos: Vector3) -> bool:
	# Court lines are drawn centered on the nominal court bounds. Their full
	# painted width is in; the ball's floor-contact point is below its center,
	# so its visible sphere radius must not enlarge the legal court further.
	var line_half_width: float = PickleballConstants.LINE_WIDTH * 0.5
	var half_width: float = PickleballConstants.COURT_WIDTH * 0.5 + line_half_width
	var half_length: float = PickleballConstants.BASELINE_Z + line_half_width
	return absf(bounce_pos.x) > half_width + COURT_LINE_EPSILON or absf(bounce_pos.z) > half_length + COURT_LINE_EPSILON



func check_service_ball_landed(bounce_pos: Vector3) -> Dictionary:
	var nvz: float = PickleballConstants.NON_VOLLEY_ZONE
	if _serve_court_side == 0:

		var correct_side: bool = bounce_pos.z < - nvz
		var correct_diag: bool
		if _serving_from_right:
			correct_diag = bounce_pos.x < 0.0
		else:
			correct_diag = bounce_pos.x > 0.0
		if not correct_side:
			return {"valid": false, "winner": 1 - _serving_team, "reason": FAULT_SHORT_SERVE, "detail": ("Blue" if _serving_team == 0 else "Red") + ": serve landed in kitchen"}
		if not correct_diag:
			return {"valid": false, "winner": 1 - _serving_team, "reason": FAULT_WRONG_SERVICE_COURT, "detail": ("Blue" if _serving_team == 0 else "Red") + ": wrong service court"}
	else:

		var correct_side2: bool = bounce_pos.z > nvz
		var correct_diag2: bool
		if _serving_from_right:
			correct_diag2 = bounce_pos.x > 0.0
		else:
			correct_diag2 = bounce_pos.x < 0.0
		if not correct_side2:
			return {"valid": false, "winner": 1 - _serving_team, "reason": FAULT_SHORT_SERVE, "detail": ("Blue" if _serving_team == 0 else "Red") + ": serve landed in kitchen"}
		if not correct_diag2:
			return {"valid": false, "winner": 1 - _serving_team, "reason": FAULT_WRONG_SERVICE_COURT, "detail": ("Blue" if _serving_team == 0 else "Red") + ": wrong service court"}
	return {"valid": true}



func check_actor_server_position(actor, from_right: bool) -> Dictionary:
	if not ActorIdentity.valid(actor): return {"valid": false, "unresolved": true, "reason": "UNKNOWN_ACTOR"}
	if is_instance_valid(_actor_registry) and _actor(ActorIdentity.actor_id(actor)) != actor: return {"valid": false, "unresolved": true, "reason": "UNKNOWN_ACTOR"}
	return ActorIdentity.annotate(_check_server_position_geometry(actor.global_position, ActorIdentity.court_side(actor), from_right), actor)

func check_server_position(server_pos: Vector3, serving_team_override: int = -1, serving_from_right_override: int = -1) -> Dictionary:
	var checked_team: int = _serving_team if serving_team_override == -1 else serving_team_override
	var from_right: bool = _serving_from_right if serving_from_right_override == -1 else serving_from_right_override == 1
	return _check_server_position_geometry(server_pos, _court_side_for_team(checked_team), from_right)

func _check_server_position_geometry(server_pos: Vector3, physical_side: int, from_right: bool) -> Dictionary:
	if physical_side not in [0, 1]: return {"valid": false, "unresolved": true, "reason": "UNKNOWN_COURT_SIDE"}
	var baseline_edge: float = PickleballConstants.BASELINE_Z - PickleballConstants.FOOT_FAULT_TOLERANCE
	var on_correct_half: bool
	var on_correct_side: bool
	var behind_baseline: bool
	if physical_side == 0:
		on_correct_half = server_pos.z > 0.2
		on_correct_side = (server_pos.x > 0.2) if from_right else (server_pos.x < -0.2)
		behind_baseline = server_pos.z >= baseline_edge
	else:
		on_correct_half = server_pos.z < -0.2
		on_correct_side = (server_pos.x < -0.2) if from_right else (server_pos.x > 0.2)
		behind_baseline = server_pos.z <= - baseline_edge
	var reason: String = ""
	if not on_correct_half:
		reason = FAULT_WRONG_HALF
	elif not on_correct_side:
		reason = FAULT_WRONG_SERVICE_COURT
	elif not behind_baseline:
		reason = FAULT_FOOT_FAULT
	return {"valid": reason == "", "reason": reason}



func check_actor_kitchen_volley_at_hit(actor_id: int, player_z: float) -> Dictionary:
	if _ball == null or _ball.get("was_volley") != true:
		return {"valid": true}
	var player = _actor(actor_id)
	if player == null: return {"valid": false, "unresolved": true, "reason": "UNKNOWN_ACTOR"}
	var in_kitchen: bool = absf(player_z) <= PickleballConstants.NON_VOLLEY_ZONE
	if player != null:
		if player.has_method("can_volley_from_feet"):
			in_kitchen = not player.can_volley_from_feet()
		else:
			in_kitchen = _ground_contact_in_kitchen(player)
			if "is_jumping" in player and player.is_jumping and "jump_takeoff_position" in player:
				in_kitchen = absf(player.jump_takeoff_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + SHOE_HALF_LENGTH
	if not in_kitchen:
		return {"valid": true}
	var hitter: String = "Blue" if _team(actor_id) == 0 else "Red"
	return {
		"valid": false, 
		"winner": 1 - _team(actor_id), 
		"reason": FAULT_KITCHEN_VOLLEY, 
		"detail": "%s volleyed in the kitchen" % hitter.to_upper(), 
	}





func check_actor_two_bounce_rule(actor_id: int) -> Dictionary:
	if _actor(actor_id) == null: return {"valid": false, "unresolved": true, "reason": "UNKNOWN_ACTOR"}
	if _ball == null:
		return {"valid": true}
	if _ball.get("both_bounces_complete") == true:
		return {"valid": true}


	if _ball.get("was_volley") == false:
		return {"valid": true}
	var hitter: String = "Blue" if _team(actor_id) == 0 else "Red"
	return {
		"valid": false, 
		"winner": 1 - _team(actor_id), 
		"reason": FAULT_TWO_BOUNCE_RULE, 
		"detail": "%s: let it bounce first" % hitter.to_upper(), 
	}


func check_double_bounce_and_net_ball(bounce_pos: Vector3) -> Dictionary:
	if _ball == null:
		return {"valid": true}
	var bounces: int = int(_ball.get("bounces_since_last_hit"))
	var last_hit: int = int(_ball.get("last_hit_by"))

	if bounces >= 2 and last_hit >= 0:
		var _loser_name: String = "Blue" if last_hit == 1 else "Red"


		var winner: int = last_hit
		return {
			"valid": false, 
			"winner": winner, 
			"reason": FAULT_DOUBLE_BOUNCE, 
			"detail": "%s: failed to return in time" % ("Blue" if winner == 1 else "Red").to_upper(), 
		}


	if last_hit >= 0:
		var hitter_side_positive: bool = (_ball.get_last_hit_court_side() == 0) if _ball.has_method("get_last_hit_court_side") else (_court_side_for_team(last_hit) == 0)
		var bounce_side_positive: bool = bounce_pos.z > 0
		if hitter_side_positive == bounce_side_positive and bounces == 1:


			var hitter: String = "Blue" if last_hit == 0 else "Red"
			return {
				"valid": false, 
				"winner": 1 - last_hit, 
				"reason": FAULT_BALL_IN_NET, 
				"detail": "%s: ball did not cross the net" % hitter.to_upper(), 
			}
	return {"valid": true}



func _ground_contact_in_kitchen(player) -> bool:
	return _NVZState.touches_ground(player)

func _has_regained_balance(player) -> bool:
	if "is_jumping" in player and player.is_jumping: return false
	if "jump_landing_remaining" in player and player.jump_landing_remaining > 0.0: return false
	var contacts: Array[Dictionary] = _NVZState.ground_contacts(player)
	if not contacts.is_empty():
		var grounded_support := false
		for contact in contacts:
			if contact.grounded and contact.inside: return false
			grounded_support = grounded_support or contact.grounded
		if not grounded_support: return false
	elif "body_pivot" in player:
		return false
	# Two feet are required for fresh NVZ eligibility, not for regaining
	# control after a legal volley. A stable one-foot/hand-supported stop is
	# observable ground support and must not leave scoring pending forever.
	var velocity: Vector3 = player.current_velocity if "current_velocity" in player else Vector3.ZERO
	if absf(velocity.y) > 0.15: return false
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() <= 0.15: return true
	# Controlled travel parallel to/away from the bounded NVZ ends the
	# relevant momentum once grounded, without a fictitious time limit.
	var position: Vector3 = player.global_position
	var nearest := Vector2(clampf(position.x, -PickleballConstants.COURT_WIDTH * 0.5, PickleballConstants.COURT_WIDTH * 0.5),
		clampf(position.z, -PickleballConstants.NON_VOLLEY_ZONE, PickleballConstants.NON_VOLLEY_ZONE))
	var toward := nearest - Vector2(position.x, position.z)
	return toward.length_squared() > 0.000001 and horizontal.dot(toward.normalized()) <= 0.01


## True while this actor's last volley is still watched for momentum (not yet balanced):
## stepping into the kitchen now is a fault. The AI reads it to hold behind the line.
func momentum_watched(actor_id: int) -> bool:
	return _volley_momentum_watches.has(actor_id) or _last_volley_player == actor_id

func check_momentum_fault(delta: float = -1.0) -> Dictionary:

	if _volley_momentum_watches.is_empty() and _last_volley_player >= 0:
		_volley_momentum_watches[_last_volley_player] = {"time": _last_volley_time_msec, "stable_since": -1}
	var now: int = Time.get_ticks_msec()
	for pnum in _volley_momentum_watches.keys():
		var watched = _actor(int(pnum))
		if not is_instance_valid(watched):
			# A roster change is not evidence of completed volley momentum.
			# Explicit reset cancels it; settlement retains the unfinished watch.
			return {"valid": false, "unresolved": true, "reason": "UNKNOWN_MOMENTUM_ACTOR", "actor_id": int(pnum)}
		var watch: Dictionary = _volley_momentum_watches[pnum]
		var physical_state: bool = "is_jumping" in watched or "current_velocity" in watched

		if not physical_state and now - int(watch.time) > PickleballConstants.MOMENTUM_FAULT_WINDOW_MS:
			_volley_momentum_watches.erase(pnum)
			if _last_volley_player == pnum: _last_volley_player = -1
			continue
		if _ground_contact_in_kitchen(watched):
			_volley_momentum_watches.clear()
			_last_volley_player = -1
			var hitter: String = "Blue" if _team(pnum) == 0 else "Red"
			return {"valid": false, "winner": 1 - _team(pnum), "reason": FAULT_MOMENTUM, 
				"detail": "%s: crossed kitchen line after volley" % hitter.to_upper()}
		if physical_state and _has_regained_balance(watched):
			if int(watch.stable_since) < 0: watch.stable_since = now
			watch.stable_elapsed = float(watch.get("stable_elapsed", 0.0)) + maxf(delta, 0.0)
			if now - int(watch.stable_since) >= BALANCE_CONFIRM_MS or float(watch.stable_elapsed) >= float(BALANCE_CONFIRM_MS) / 1000.0:
				_volley_momentum_watches.erase(pnum)
				if _last_volley_player == pnum: _last_volley_player = -1
		else:
			watch.stable_since = -1
			watch.stable_elapsed = 0.0
	return {"valid": true}


## Perf: a rigged player standing further than NET_CHECK_DEPTH_M from the net cannot reach it
## or its plane (body lean + arm + paddle is well under 2 m), so its meshes are not scanned.
## The two net checks scanned every mesh of all four players every tick (0.65 ms of a tick).
const NET_CHECK_DEPTH_M := 2.2
func _far_from_net(player) -> bool:
	return player is Node3D and "body_pivot" in player and absf(player.global_position.z) > NET_CHECK_DEPTH_M

func check_net_touch() -> Dictionary:
	for player in _players():
		var pnum: int = ActorIdentity.actor_id(player)
		if not is_instance_valid(player): continue
		if _far_from_net(player): continue
		var contact: Dictionary = ActorIdentity.annotate(SurfaceContacts.net_contact(player), player)
		if not contact.hit and not ("body_pivot" in player):
			# Non-rig fixtures retain a narrow compatibility path, now finite-x.
			var root_pos: Vector3 = player.global_position
			contact.hit = _NetProfile.spans_x(root_pos.x) and absf(root_pos.z) < NET_TOUCH_Z_TOLERANCE and root_pos.y >= _NetProfile.FLOOR_Y and root_pos.y < _NetProfile.top_y_at(root_pos.x)
			if not contact.hit and player.has_method("get_paddle_position"):
				var pad: Vector3 = player.get_paddle_position()
				contact.hit = _NetProfile.spans_x(pad.x) and absf(pad.z) < NET_TOUCH_Z_TOLERANCE and pad.y >= _NetProfile.FLOOR_Y and pad.y < _NetProfile.top_y_at(pad.x)
		if contact.hit:
			var hitter: String = "Blue" if _team(pnum) == 0 else "Red"
			return {"valid": false, "winner": 1 - _team(pnum), "reason": FAULT_NET_TOUCH,
				"detail": "%s: touched the net" % hitter.to_upper(), "contact": contact}
	return {"valid": true}


func check_net_plane() -> Dictionary:
	if _ball == null: return {"valid": true}
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else -1
	for player in _players():
		var pnum: int = ActorIdentity.actor_id(player)
		if not is_instance_valid(player) or not (player is Node3D): continue
		if _far_from_net(player): continue
		var extent: Dictionary = ActorIdentity.annotate(SurfaceContacts.net_plane_extent(player, ActorIdentity.court_side(player)), player)
		if not extent.crossed: continue
		# Follow-through never authorizes grounded opponent-court contact.
		for contact in SurfaceContacts.ground_contacts(player, true):
			if (1 - ActorIdentity.court_side(player)) in contact.court_sides:
				return {"valid": false, "winner": 1 - _team(pnum), "reason": FAULT_OPPONENT_COURT,
					"detail": "%s: touched opponent court" % ("BLUE" if _team(pnum) == 0 else "RED"), "contact": contact}
		var after_hit: bool = flight >= 0 and int(player.get_meta("legal_net_followthrough_flight", -2)) == flight and _last_actor() == pnum
		var returned_over: bool = flight >= 0 and int(player.get_meta("legal_return_over_net_flight", -2)) == flight
		if "receiver_returned_across_net" in _ball and "receiver_entire_ball_crossed" in _ball and "receiver_side_bounced" in _ball:
			returned_over = returned_over or (bool(_ball.receiver_returned_across_net) and bool(_ball.receiver_entire_ball_crossed) and bool(_ball.receiver_side_bounced) and int(_ball.last_hit_by) == 1 - _team(pnum) and int(_ball.bounces_since_last_hit) == 1)
		if after_hit or returned_over: continue
		return {"valid": false, "winner": 1 - _team(pnum), "reason": FAULT_NET_PLANE,
			"detail": "%s: crossed net plane before contact" % ("BLUE" if _team(pnum) == 0 else "RED"), "contact": extent}
	return {"valid": true}


func _contact_simulation_unresolved() -> bool:
	return _ball is Object and bool(_ball.get_meta("contact_authority_unresolved", false))

func _emit(result: Dictionary) -> void:
	if result.get("unresolved", false): return
	if _contact_simulation_unresolved(): return
	if has_pending_settlement(): return
	_active = false
	var momentum: Dictionary = check_momentum_fault()
	if momentum.get("unresolved", false):
		_pending_result = result.duplicate(true)
		rally_pending.emit(int(result.get("winner", -1)), String(result.get("reason", "")), String(result.get("detail", "")))
		return
	if not momentum.get("valid", true):
		_finalize(momentum)
		return
	if not _volley_momentum_watches.is_empty():
		_pending_result = result.duplicate(true)
		rally_pending.emit(int(result.get("winner", -1)), String(result.get("reason", "")), String(result.get("detail", "")))
		return
	_finalize(result)

func _finalize(result: Dictionary) -> void:
	_active = false
	_pending_result.clear()
	_last_volley_player = -1
	_volley_momentum_watches.clear()
	var winner: int = int(result.get("winner", -1))
	var reason: String = String(result.get("reason", ""))
	var detail: String = String(result.get("detail", ""))
	if RuntimePolicy.developer_tools: print("[RALLY END] winner=%d reason=%s detail=%s" % [winner, reason, detail])
	rally_ended.emit(winner, reason, detail)

func set_actor_registry(registry) -> void:
	_actor_registry = registry

func _players() -> Array:
	return ActorIdentity.players(_actor_registry, [_player_left, _player_right])

func _actor(number: int):
	return ActorIdentity.find_actor(_actor_registry, number, [_player_left, _player_right])

func _team(number: int) -> int:
	return ActorIdentity.team_id(_actor(number))

func _legacy_actor(team: int) -> int:
	return ActorIdentity.actor_id(ActorIdentity.unique_team_actor(_actor_registry, team, [_player_left, _player_right]))

func _event_actor(team: int, evidence: Dictionary) -> int:
	var observed: Dictionary = evidence.duplicate()
	if not observed.has("player_num"): observed["player_num"] = team
	return ActorIdentity.evidence_actor(observed, _actor_registry, [_player_left, _player_right])

func _last_actor() -> int:
	if _ball != null and _ball.has_method("get_last_hit_actor_id"): return _ball.get_last_hit_actor_id()
	return _legacy_actor(int(_ball.get("last_hit_by"))) if _ball != null else -1

func _court_side_for_team(team: int) -> int:
	var side: int = ActorIdentity.team_side(_actor_registry, team, [_player_left, _player_right])
	return side if side >= 0 else team if not is_instance_valid(_actor_registry) else -1

func _team_for_side(side: int) -> int:
	var found := -1
	for player in _players():
		if ActorIdentity.court_side(player) != side: continue
		if found >= 0 and found != ActorIdentity.team_id(player): return -1
		found = ActorIdentity.team_id(player)
	return found if found >= 0 else side if not is_instance_valid(_actor_registry) else -1

func on_actor_receiving_contact_fault(actor_id: int, result: Dictionary, evidence: Dictionary) -> void:
	if not _active or _actor(actor_id) == null or result.get("valid", true) or result.get("unresolved", false): return
	if result.get("reason", "") != "WRONG_RECEIVER" or int(result.get("winner", -1)) != 1 - _team(actor_id): return
	if not evidence.get("hit", false) or evidence.get("ambiguous", false) or evidence.get("kind", "body") not in ["legal_paddle", "legal_hand"]: return
	if _event_actor(_team(actor_id), evidence) != actor_id: return
	var observed: Dictionary = result.duplicate(true)
	observed["contact"] = evidence.duplicate(true)
	_emit(observed)
