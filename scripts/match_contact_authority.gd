extends Node
## Actual displayed surfaces are the ball/body authority. Character capsules
## remain movement proxies. Every hand impact continues the unconsumed time.
const IntentQueue = preload("res://scripts/contact_intent_queue.gd")
const ActorIdentity = preload("res://scripts/contact_actor_identity.gd")
const SupportEvidence = preload("res://scripts/paddle_support_evidence.gd")
const Manifold = preload("res://scripts/finite_face_manifold.gd")
const ArmBudget = preload("res://scripts/live_arm_budget.gd")
const Surface = preload("res://scripts/player_surface_contacts.gd")
const Remainder = preload("res://scripts/contact_remainder_physics.gd")
const HandResponse = preload("res://scripts/legal_hand_response.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const PaddleShape = preload("res://scripts/paddle_clearance.gd")
const History = preload("res://scripts/player_surface_history.gd")
const ServeHistory = preload("res://scripts/serve_surface_history.gd")
const ServeStyles = preload("res://scripts/serve_style.gd")
var _intents = IntentQueue.new()
var _published_intents: Dictionary = {}
var _intent_interval: Dictionary = {}
var _settlement_scope: Dictionary = {}
var _settlement_serial := 0
var settlement_receipts: Array = []
var _control_delta := 0.0
var _ordered_live := false
var _ordered_initial_bounces := -1
var _ordered_floor_events := 0
var _ordered_first_floor: Dictionary = {}
var _preparing_event_intent: Dictionary = {}
var _last_consumed_native_serial := -1
var support_observation: Dictionary = {}
var _manifold: Dictionary = {}
var _face_free: Dictionary = {}
var manifold_receipts: Array = []
var performance_receipts: Array = []
var _manifold_step_count := 0
var _first_resolution := true
var _first_query := true
var _maintained_faces: Dictionary = {}
var _maintained_player := -1
var _query_radius_adjustment := 0.0
var _confirm_actual_contact := false
var _serve_history = ServeHistory.new()
var _serve_admitted := false
var _serve_serial := 0
var _serve_strokes: Dictionary = {}
const MAX_HAND_IMPACTS := 8
const MAX_FRAME_TRIANGLE_QUERIES := 8192
const MAX_FRAME_ALGEBRA_QUERIES := 24
var _algebra_work := 0
var _algebra_units := 0
var algebra_query_count := 0
var _query_work := 0
var _query_frame := -1
var game
var _interval_reset_epoch := 0
var _deferred_age_fraction := -1.0
var _deferred_age_delta := 0.0
var _passive_age_waiting_floor := false
var _consumed_motion: Dictionary = {}
var _controller_incoming_bounds := AABB()
var _controller_incoming_frame := -1
var _record_consumed_motion := false
var _consumed_path_bounds := AABB()
var _snapshots: Dictionary = {}
var _frame_current: Dictionary = {}
# Perf: _snapshots takes a shallow copy of _frame_current. _capture_current() builds
# brand-new per-actor snapshot dictionaries every tick and never edits old ones,
# so the previous deep duplicate(true) of all mesh arrays each tick was wasted work.
var _contact_pose_snapshots: Dictionary = {}
var _remainder_geometry_start := -1.0
var _previous_ball := Vector3.ZERO
var _flight := -1
var _contact_incoming_flight := -1
var _admitted_paddle_mesh := -1
var last_evidence: Dictionary = {}
var _delta := 1.0 / 60.0
var _last_contact: Dictionary = {}
var _separated := true
var _strokes: Dictionary = {}
var query_count := 0
var ambiguous_count := 0
var unresolved_continuation: Dictionary = {}

func setup(owner) -> void:
	game = owner
	if game.ball != null and not game.ball.actor_hit_paddle.is_connected(_on_actor_hit_paddle): game.ball.actor_hit_paddle.connect(_on_actor_hit_paddle)
	game.ball.set_actor_registry(game)
	game.ball.set_scene_interval_owner(self)
	if game.rally_scorer != null: game.rally_scorer.set_actor_registry(game)
	name = "MatchContactAuthority"
	process_physics_priority = 200
	for player in _players(): game.ball.add_collision_exception_with(player)
	game.ball.set_authoritative_paddles(_paddles())
	reset()

func reset() -> void:
	_interval_reset_epoch += 1
	_intents.reset(); _published_intents.clear(); _intent_interval.clear(); _settlement_scope.clear(); _ordered_live = false
	_ordered_initial_bounces = -1; _ordered_floor_events = 0; _ordered_first_floor.clear(); _preparing_event_intent.clear()
	_consumed_motion.clear(); _record_consumed_motion = false; _controller_incoming_frame = -1
	_deferred_age_fraction = -1.0; _deferred_age_delta = 0.0; _passive_age_waiting_floor = false
	_manifold = {}; _face_free = {}; support_observation = {}; manifold_receipts.clear(); performance_receipts.clear(); _manifold_step_count = 0; _first_resolution = true; _first_query = true; _maintained_faces = {}; _maintained_player = -1; _query_radius_adjustment = 0.0; _confirm_actual_contact = false
	if not unresolved_continuation.is_empty() and game != null: game.ball.set_time_frozen(false)
	_snapshots.clear(); _frame_current.clear(); _contact_pose_snapshots.clear(); _remainder_geometry_start = -1.0; _last_contact = {}; unresolved_continuation = {}; _strokes.clear()
	_separated = true; last_evidence = {}; _flight = -1
	_serve_history.clear(); _serve_admitted = false; _serve_strokes.clear()
	_query_frame = -1; _query_work = 0; _algebra_work = 0; _algebra_units = 0
	if game == null or game.ball == null: return
	for actor in _players(): game.ball.add_collision_exception_with(actor)
	game.ball.set_authoritative_paddles(_paddles())
	game.ball.set_meta("contact_authority_unresolved", false)
	game.ball.cancel_prepared_aero()
	_previous_ball = game.ball.global_position; _flight = game.ball.flight_id
	_contact_incoming_flight = _flight
	for player in _players(): _snapshots[ActorIdentity.actor_id(player)] = Surface.snapshot(player, true)

func prime_serve_delivery(server) -> void:
	if game == null or game.ball == null: return
	_serve_admitted = false
	if ActorIdentity.find_actor(game, ActorIdentity.actor_id(server)) != server:
		_serve_history.clear(); return
	_serve_history.prime(_players(), server, game.ball.global_position, game.ball.BALL_RADIUS)

func before_serve_contact(server) -> bool:
	_serve_admitted = false
	if game == null or game.ball.is_in_play or not unresolved_continuation.is_empty(): return false
	if ActorIdentity.find_actor(game, ActorIdentity.actor_id(server)) != server or _serve_history.server_actor_id != ActorIdentity.actor_id(server):
		last_evidence = {"blocked": true, "reason": "unknown_serve_actor", "serve_admission": "unresolved"}; return false
	var observed: Dictionary = _serve_history.sample(_players(), game.ball.global_position, game.ball.BALL_RADIUS)
	if observed.get("ambiguous", false) or observed.get("reason", "") in ["serve_release_not_observed", "serve_body_contact"]:
		last_evidence = observed.duplicate(true)
		last_evidence["serve_admission"] = "unresolved" if observed.get("ambiguous", false) or observed.get("reason", "") == "serve_release_not_observed" else "fault"
		return false
	var rig: Dictionary = ArmBudget.displayed_report(server)
	if not rig.valid:
		last_evidence = {"blocked": true, "reason": "infeasible_actual_arm", "rig": rig, "serve_admission": "unresolved"}
		return false
	if not preload("res://scripts/finite_paddle_contact.gd").touches(server.paddle_node.global_transform, game.ball.global_position, game.ball.BALL_RADIUS):
		last_evidence = {"blocked": true, "reason": "serve_face_not_touching", "serve_admission": "miss"}
		return false
	_capture_current(); _contact_pose_snapshots = _frame_current.duplicate()
	_admitted_paddle_mesh = -1
	for id in _frame_current[ActorIdentity.actor_id(server)].parts:
		var part: Dictionary = _frame_current[ActorIdentity.actor_id(server)].parts[id]
		if part.get("equipment", false) and part.part == "Head": _admitted_paddle_mesh = int(id); break
	_serve_admitted = _admitted_paddle_mesh >= 0
	last_evidence = {"hit": _serve_admitted, "kind": "legal_paddle", "actor_id": ActorIdentity.actor_id(server), "team_id": ActorIdentity.team_id(server), "court_side": ActorIdentity.court_side(server), "player_num": ActorIdentity.team_id(server),
		"mesh_id": _admitted_paddle_mesh, "point": game.ball.global_position, "serve_admission": "accepted", "delivery": observed}
	return _serve_admitted

func note_serve_contact(server) -> void:
	if not _serve_admitted: return
	if game.ball.get_last_hit_actor_id() != ActorIdentity.actor_id(server) or game.ball.last_hit_team_id != ActorIdentity.team_id(server) or game.ball.last_hit_court_side != ActorIdentity.court_side(server):
		if not game.ball.set_actor_serve_identity(server): return
	_serve_serial += 1
	var serial: int = 2000000000 + _serve_serial
	_serve_strokes[ActorIdentity.actor_id(server)] = serial
	var head: Vector3 = server.paddle_node.global_transform * PaddleDimensions.HEAD_OFFSET
	var previous_head: Vector3 = head
	if _snapshots.has(ActorIdentity.actor_id(server)): previous_head = _snapshots[ActorIdentity.actor_id(server)].paddle * PaddleDimensions.HEAD_OFFSET
	var direction: Vector3 = (head - previous_head).normalized() if head.distance_to(previous_head) > .0005 else Vector3.ZERO
	_strokes[ActorIdentity.actor_id(server)] = {"serial": serial, "active": true, "head": head, "direction": direction, "hit_direction": direction, "continuous": true}
	_last_contact = {"actor_id": ActorIdentity.actor_id(server), "team_id": ActorIdentity.team_id(server), "court_side": ActorIdentity.court_side(server), "player_num": ActorIdentity.team_id(server), "stroke_serial": serial, "mesh_id": _admitted_paddle_mesh}
	_separated = false; _previous_ball = game.ball.global_position; _flight = game.ball.flight_id
	_snapshots = _frame_current.duplicate()
	_serve_admitted = false; _serve_history.clear()

func before_paddle(player, evidence: Dictionary = {}) -> bool:
	_ensure_all_arms()
	var began: int = Time.get_ticks_usec()
	var queries_before: int = _query_work
	var algebra_before: int = _algebra_units
	var steps_before: int = _manifold_step_count
	var result: bool = _before_paddle_impl(player, evidence)
	_record_performance("strike_admission", began, queries_before, algebra_before, steps_before)
	return result

func _before_paddle_impl(player, evidence: Dictionary = {}) -> bool:
	_admitted_paddle_mesh = -1
	_remainder_geometry_start = -1.0
	if uses_two_phase_contact(player):
		last_evidence = {"blocked": true, "reason": "two_phase_intent_required"}
		return false
	if game == null or not game.ball.is_in_play or not unresolved_continuation.is_empty(): return false
	if ActorIdentity.find_actor(game, ActorIdentity.actor_id(player)) != player:
		last_evidence = {"blocked": true, "hit": false, "reason": "unknown_contact_actor"}; return false
	if not _manifold.is_empty():
		last_evidence = {"blocked": true, "reason": "maintained_physical_contact"}; return false
	if player.posture == null or player.hitting == null or (not player.is_ai and player.posture.human_contact == null):
		last_evidence = {"blocked": true, "hit": false, "reason": "contact_controller_uninitialized"}
		return false
	if _query_frame != Engine.get_physics_frames():
		_query_frame = Engine.get_physics_frames(); _query_work = 0; _algebra_work = 0; _algebra_units = 0
	var rig: Dictionary = ArmBudget.displayed_report(player)
	if not rig.valid:
		last_evidence = {"blocked": true, "hit": false, "reason": "infeasible_actual_arm", "rig": rig}
		return false
	var ball = game.ball
	_contact_incoming_flight = ball.flight_id
	if not ball.global_position.is_finite() or not ball.linear_velocity.is_finite():
		last_evidence = {"blocked": true, "hit": false, "reason": "nonfinite_ball"}
		return false
	var from: Vector3 = evidence.get("ball_from", _previous_ball if _flight == ball.flight_id else ball.global_position)
	if not from.is_finite(): return false
	_controller_incoming_bounds = AABB(from, Vector3.ZERO).expand(ball.global_position).grow(ball.BALL_RADIUS)
	_controller_incoming_frame = Engine.get_physics_frames()
	var earlier_scene: Dictionary = Remainder._first_collision(from, ball.global_position, ball.linear_velocity, ball.BALL_RADIUS, _scene_context())
	if from != ball.global_position and earlier_scene.get("hit", false) and float(earlier_scene.fraction) < 1.0 - 1e-8:
		last_evidence = {"blocked": true, "hit": false, "reason": "earlier_scene_boundary", "scene": earlier_scene}
		return false
	_observe_stroke(player)
	_capture_current()
	_contact_pose_snapshots = _frame_current.duplicate()
	var result: Dictionary = _query_range(from, ball.global_position, 0.0, 1.0, ball.flight_id)
	if result.get("blocked", false):
		last_evidence = result
		# An unresolved earlier triangle must never become a later known fault
		# or save. The full-frame pass will retain/freeze unresolved elapsed.
		if result.get("ambiguous", false): return false
		if result.get("hit", false):
			if result.get("kind", "body") == "legal_paddle" and _evidence_actor(result) == ActorIdentity.actor_id(player):
				# The controller is committing this player's first real paddle
				# manifold, not jumping over an earlier hand/body/opponent hit.
				var reason: String = _illegal_hand_reason(player, result, false)
				if reason != "":
					game.rally_scorer.on_actor_illegal_hitting_surface_contact(ActorIdentity.actor_id(player), reason, result)
					return false
				var receiving: Dictionary = _observe_receiving_contact(player, result)
				if not receiving.allowed:
					if receiving.get("unresolved", false):
						last_evidence["service_context"] = receiving.rule
						_hold_unresolved(get_physics_process_delta_time() * (1.0 - clampf(float(evidence.get("fraction", 1.0)), 0.0, 1.0)), "service context unresolved")
					return false
				_admitted_paddle_mesh = int(result.get("mesh_id", -1))
				return true
			if result.get("kind", "body") not in ["legal_hand", "legal_paddle"]: _fault(result)
		return false
	if game.get("doubles_mode") == true:
		# A controller may arrive a numerical contact slop before the posed
		# triangle query. Certify its real finite head here before consuming
		# the first-return ledger; a move label or planned point is not proof.
		var gap: float = PaddleShape.distance_to_head_shape(player.paddle_node.global_transform.affine_inverse() * ball.global_position) - ball.BALL_RADIUS
		if not is_finite(gap) or gap > History.CONTACT_EPSILON:
			last_evidence = {"blocked": true, "hit": false, "reason": "unobserved_receiving_contact", "gap": gap}; return false
		var physical: Dictionary = ActorIdentity.annotate({"hit": true, "blocked": true, "ambiguous": false, "kind": "legal_paddle", "point": ball.global_position, "fraction": float(evidence.get("fraction", 1.0)), "source": "finite_head_at_controller_toi", "gap": gap}, player)
		var reason: String = _illegal_hand_reason(player, physical, false)
		if reason != "":
			game.rally_scorer.on_actor_illegal_hitting_surface_contact(ActorIdentity.actor_id(player), reason, physical); return false
		var receiving: Dictionary = _observe_receiving_contact(player, physical)
		if not receiving.allowed:
			last_evidence = physical
			if receiving.get("unresolved", false):
				last_evidence["service_context"] = receiving.rule
				_hold_unresolved(get_physics_process_delta_time() * (1.0 - clampf(float(evidence.get("fraction", 1.0)), 0.0, 1.0)), "service context unresolved")
			return false
	return true

func _capture_current() -> void:
	var _pt := Time.get_ticks_usec()
	_perf_capture_current()
	PerfMonitor.record("contact.capture", Time.get_ticks_usec() - _pt)

func _ensure_all_arms() -> void:
	for p in _players():
		if "posture" in p and p.posture != null: p.posture.ensure_arm_pose()

const CONTACT_CAPTURE_RADIUS_M := 3.0

## This tick's snapshot of an actor, capturing it now if it was skipped as out of reach.
func _current_snapshot(actor) -> Dictionary:
	var id: int = ActorIdentity.actor_id(actor)
	if not _frame_current.has(id):
		var snapshot: Dictionary = Surface.snapshot(actor, true)
		snapshot["endpoint_anatomy"] = ArmBudget.displayed_report(actor)
		_frame_current[id] = snapshot
	return _frame_current[id]

func _perf_capture_current() -> void:
	_ensure_all_arms()
	_frame_current.clear()
	# Perf: in a live rally, skip players the ball cannot reach this tick (ball moves
	# ~0.33 m/tick; arm + paddle reach ~1.5 m). A skipped player has no previous
	# snapshot, so when they come in range their sweep starts fresh (previous falls
	# back to current). Serves and hit validation still capture everyone.
	var ball = game.ball if game != null else null
	var cull: bool = ball != null and ball.is_in_play and game.game_state == game.GameState.PLAYING
	for player in _players():
		if cull and player.global_position.distance_to(ball.global_position) > CONTACT_CAPTURE_RADIUS_M: continue
		var snapshot: Dictionary = Surface.snapshot(player, true)
		snapshot["endpoint_anatomy"] = ArmBudget.displayed_report(player)
		_frame_current[ActorIdentity.actor_id(player)] = snapshot

func _query_range(from: Vector3, to: Vector3, start: float, end: float, incoming_flight: int, physical_displacement: Vector3 = Vector3.INF, physical_velocity: Vector3 = Vector3.INF) -> Dictionary:
	var began: int = Time.get_ticks_usec()
	var queries_before: int = _query_work
	var algebra_before: int = _algebra_units
	var steps_before: int = _manifold_step_count
	var result: Dictionary = _query_range_impl(from, to, start, end, incoming_flight, physical_displacement, physical_velocity)
	_record_performance("surface_query", began, queries_before, algebra_before, steps_before)
	return result

func _query_range_impl(from: Vector3, to: Vector3, start: float, end: float, incoming_flight: int, physical_displacement: Vector3 = Vector3.INF, physical_velocity: Vector3 = Vector3.INF) -> Dictionary:
	var earliest: Dictionary = {"hit": false, "blocked": false, "ambiguous": false, "fraction": 2.0}
	for player in _players():
		if _query_work >= MAX_FRAME_TRIANGLE_QUERIES:
			return {"hit": false, "blocked": true, "ambiguous": true, "fraction": start, "reason": "frame_contact_budget"}
		if not _frame_current.has(ActorIdentity.actor_id(player)): continue   # out of ball reach this tick
		var current: Dictionary = _frame_current[ActorIdentity.actor_id(player)]
		var previous: Dictionary = _snapshots.get(ActorIdentity.actor_id(player), current) if _flight == incoming_flight else current
		var departing: int = int(_last_contact.get("mesh_id", -1)) if _evidence_actor(_last_contact) == ActorIdentity.actor_id(player) else -1
		if _confirm_actual_contact: departing = -1
		var query_start: float = start
		var query_end: float = end
		var geometry_span := 1.0
		if _remainder_geometry_start >= 0.0:
			previous = _contact_pose_snapshots.get(ActorIdentity.actor_id(player), current)
			geometry_span = maxf(1.0 - _remainder_geometry_start, 1e-12)
			query_start = clampf((start - _remainder_geometry_start) / geometry_span, 0.0, 1.0)
			query_end = clampf((end - _remainder_geometry_start) / geometry_span, query_start, 1.0)
		if _legs_pass(player):
			previous = _without_legs(previous)
			current = _without_legs(current)
		if _own_paddle_pass(player):
			if Engine.get_physics_frames() - int(_paddle_hit_tick.get(ActorIdentity.actor_id(player), -1000)) <= OWN_SHOT_LEG_TICKS: continue
			previous = _without_paddle(previous)
			current = _without_paddle(current)
		var remaining_units: int = maxi(0, MAX_FRAME_ALGEBRA_QUERIES * History.ALGEBRA_UNITS_PER_QUERY - _algebra_units)
		var result: Dictionary = History.query_range(previous, current, from, to, game.ball.BALL_RADIUS + _query_radius_adjustment, query_start, query_end, true, departing, MAX_FRAME_TRIANGLE_QUERIES - _query_work, {}, ceili(float(remaining_units) / History.ALGEBRA_UNITS_PER_QUERY), _maintained_faces if ActorIdentity.actor_id(player) == _maintained_player else {}, physical_displacement, remaining_units, physical_velocity, _delta * geometry_span)
		if _remainder_geometry_start >= 0.0:
			for key in ["fraction", "hit_fraction", "uncertain_fraction"]:
				if result.has(key) and float(result[key]) >= 0.0: result[key] = _remainder_geometry_start + float(result[key]) * geometry_span
			if result.has("surface_displacement"): result.surface_displacement = Vector3(result.surface_displacement) / geometry_span
		_query_work += int(result.get("queries", 0))
		_algebra_units += int(result.get("algebra_work_units", 0))
		_algebra_work = ceili(float(_algebra_units) / History.ALGEBRA_UNITS_PER_QUERY)
		algebra_query_count += int(result.get("algebra_queries", 0))
		query_count += 1
		ActorIdentity.annotate(result, player); result["flight_id"] = game.ball.flight_id
		if result.get("ambiguous", false): ambiguous_count += 1
		earliest = ActorIdentity.earliest(earliest, result)
	return earliest

# Low receptions put the front thigh between the ball and the paddle. Bench (6
# seeds): 27 of 40 body-hit faults were the thigh, 22 of them with the paddle
# planned centimetres behind it, and 8 were the hitter's own shot clipping a
# leg. While a player is playing a low or mid-low ball, and for a moment after
# their own hit, the ball does not collide with that player's thighs and shins.
const LEG_PARTS: Array[String] = ["ThighMesh", "ShinMesh"]
const OWN_SHOT_LEG_TICKS := 8
var _paddle_hit_tick: Dictionary = {}   # actor id -> physics tick of its last paddle hit

func _on_actor_hit_paddle(actor_id: int, _team_id: int, _court_side: int) -> void:
	_paddle_hit_tick[actor_id] = Engine.get_physics_frames()

func _legs_pass(player) -> bool:
	var ball = game.ball
	if ball == null or not ball.is_in_play: return false
	var id: int = ActorIdentity.actor_id(player)
	if ball.get_last_hit_actor_id() == id:
		return Engine.get_physics_frames() - int(_paddle_hit_tick.get(id, -1000)) <= OWN_SHOT_LEG_TICKS
	if ball.get_last_hit_team_id() == ActorIdentity.team_id(player): return false
	var pose: PostureDefinition = null
	if player.is_ai:
		var brain = player.ai_brain
		if brain == null or not brain.ai_is_charging or not brain.ai_selected_contact_reachable: return false
		pose = brain.ai_reach_pose if brain.ai_reach_pose != null else PostureLibrary.instance().get_def(brain.ai_desired_posture)
	else:
		var human = player.posture.human_contact if player.posture != null else null
		if human == null or human.phase < 0 or human.phase > 1: return false
		pose = human.preparation_contact().get("def")
	return pose != null and pose.has_zone and pose.height_tier <= 1

func _without_legs(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("parts"): return snapshot
	var kept := {}
	for id in snapshot.parts:
		if not str(snapshot.parts[id].get("part", "")) in LEG_PARTS: kept[id] = snapshot.parts[id]
	var copy: Dictionary = snapshot.duplicate()
	copy["parts"] = kept
	return copy

# Ball flight comes only from the solved launch, never from the paddle face.
# After a player's hit, their own paddle and paddle hand do not touch the ball
# again (follow-through, carry) until another player touches it: no extra push,
# no double-hit fault. Measured: ~7% of serves were knocked 1.5-2 m off target.
# For OWN_SHOT_LEG_TICKS after the hit the whole hitter is skipped: without the
# paddle in the way the launch could clip their own body (3 faults in 2 runs).
func _own_paddle_pass(player) -> bool:
	var ball = game.ball
	return ball != null and ball.is_in_play and ball.get_last_hit_actor_id() == ActorIdentity.actor_id(player)

func _without_paddle(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("parts"): return snapshot
	var kept := {}
	for id in snapshot.parts:
		var part: Dictionary = snapshot.parts[id]
		if not part.get("equipment", false) and Dictionary(part.get("hand", {})).is_empty(): kept[id] = part
	var copy: Dictionary = snapshot.duplicate()
	copy["parts"] = kept
	return copy

func _fault(evidence: Dictionary) -> void:
	game.rally_scorer.on_actor_body_contact(_evidence_actor(evidence), evidence)

func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("contact.authority", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	var pending: Dictionary = game.ball.deferred_scene_interval() if game != null and game.ball != null else {}
	_process_authoritative_interval(delta)
	if not pending.is_empty() and unresolved_continuation.is_empty() and game.rally_scorer.has_method("resume_deferred_scene_rules"):
		game.rally_scorer.resume_deferred_scene_rules(pending)

func _process_authoritative_interval(delta: float) -> void:
	var reset_epoch: int = _interval_reset_epoch
	if game == null or game.ball == null or not unresolved_continuation.is_empty(): return
	var ball = game.ball
	if _serve_history.active and not ball.is_in_play:
		if game.game_serve._pending_release.is_empty(): _serve_history.clear()
		else:
			var delivery: Dictionary = _serve_history.sample(_players(), ball.global_position, ball.BALL_RADIUS)
			if delivery.get("reason", "") in ["serve_body_contact", "unresolved_serve_delivery"]: last_evidence = delivery.duplicate(true)
	_control_delta = maxf(0.0, delta)
	_delta = _control_delta
	_face_free = {}
	_remainder_geometry_start = -1.0
	if _query_frame != Engine.get_physics_frames():
		_query_frame = Engine.get_physics_frames(); _query_work = 0; _algebra_work = 0; _algebra_units = 0
	for player in _players(): _observe_stroke(player)
	_capture_current()
	if ball.is_in_play and game.game_state == game.GameState.PLAYING and not game._tool_state_active():
		var ordered: Dictionary = ball.deferred_scene_interval()
		if not ordered.is_empty() and ordered.get("kind", "") == "ordered_live_interval":
			_process_ordered_live(ordered, delta)
			_finish_published_intents()
			if reset_epoch != _interval_reset_epoch: return
			_previous_ball = ball.global_position; _flight = ball.flight_id
			_snapshots = _frame_current.duplicate()
			return
		var from: Vector3 = _previous_ball if _flight == ball.flight_id else ball.global_position
		if not _manifold.is_empty():
			var pending: Dictionary = ball.deferred_scene_interval()
			if not pending.is_empty():
				if ball.time_since_last_bounce != float(pending.bounce_age_before): _hold_unresolved(delta, "deferred bounce age changed"); return
				_deferred_age_fraction = 0.0; _deferred_age_delta = delta
			var held: Dictionary = ball.take_prepared_aero()
			if held.get("blocked", false): _hold_unresolved(delta, held.reason); return
			ball.global_position = from
			var fresh: Dictionary = _face_for_contact({"actor_id": _evidence_actor(_manifold), "mesh_id": _manifold.mesh_id, "triangle_offset": _manifold.source, "normal": _manifold.normal})
			if fresh.is_empty(): _hold_unresolved(delta, "maintained topology changed"); return
			_manifold.face = fresh
			_continue_motion(0.0, delta, ball.flight_id)
			_deferred_age_fraction = -1.0
			if reset_epoch != _interval_reset_epoch: return
			if unresolved_continuation.is_empty(): ball.reapply_prepared_aero(held)
			_previous_ball = ball.global_position; _flight = ball.flight_id; _snapshots = _frame_current.duplicate()
			return
		if not ball.deferred_scene_interval().is_empty():
			_resolve_deferred_scene(delta)
			if reset_epoch != _interval_reset_epoch: return
			_previous_ball = ball.global_position; _flight = ball.flight_id; _snapshots = _frame_current.duplicate()
			return
		var result: Dictionary = _query_range(from, ball.global_position, 0.0, 1.0, ball.flight_id)
		if result.get("ambiguous", false):
			last_evidence = result.duplicate(true)
			ball.global_position = from
			_hold_unresolved(delta, "body contact query budget")
		elif result.get("hit", false):
			last_evidence = result.duplicate(true)
			if result.get("kind", "body") in ["legal_hand", "legal_paddle"]:
				var prepared: Dictionary = ball.take_prepared_aero()
				if prepared.get("blocked", false): _hold_unresolved(delta * (1.0 - float(result.fraction)), prepared.reason)
				else:
					_hand_contact(result, delta)
					if unresolved_continuation.is_empty(): ball.reapply_prepared_aero(prepared)
			else: _fault(result)
		_update_separation()
	ball.clear_dead_scene_interval()
	_previous_ball = ball.global_position; _flight = ball.flight_id
	# Preserve the sampled geometry even when hit notifications changed pose.
	_snapshots = _frame_current.duplicate()

func owns_live_scene_motion() -> bool:
	return game != null and game.ball != null and game.ball.is_in_play and game.game_state in [game.GameState.PLAYING, game.GameState.SERVING] and not game._tool_state_active()

func _scene_context() -> Dictionary:
	var ball = game.ball
	var net = game.get_node_or_null("Net") if game is Node else null
	var context: Dictionary = {"net_active": net != null and (int(net.collision_layer) & int(ball.collision_mask)) != 0}
	var guard = ball._net_contact_guard
	if is_instance_valid(guard) and guard.has_method("ordered_scene_geometry"):
		context["wall"] = guard.ordered_scene_geometry()
	return context

func completed_scene_boundary(drift_velocity: Vector3) -> Dictionary:
	var ball = game.ball
	var from: Vector3 = _previous_ball if _flight == ball.flight_id else ball.global_position
	return Remainder._first_collision(from, ball.global_position, drift_velocity, ball.BALL_RADIUS, _scene_context())

func should_defer_scene_boundary() -> bool:
	return game != null and game.ball != null and game.ball.is_in_play and game.game_state == game.GameState.PLAYING and not game._tool_state_active()

func _resolve_deferred_scene(delta: float) -> void:
	var reset_epoch: int = _interval_reset_epoch
	var ball = game.ball
	var pending: Dictionary = ball.deferred_scene_interval()
	if pending.is_empty(): return
	if int(pending.frame) != Engine.get_physics_frames() or int(pending.flight) != ball.flight_id or _flight != ball.flight_id or float(pending.delta) != delta:
		_hold_unresolved(delta, "deferred scene interval identity changed"); return
	if ball.time_since_last_bounce != float(pending.bounce_age_before):
		_hold_unresolved(delta, "deferred bounce age changed"); return
	if ball.receiver_path_state() != pending.receiver_before:
		_hold_unresolved(delta, "deferred scene rule state changed"); return
	var prepared: Dictionary = ball.take_prepared_aero()
	if prepared.get("blocked", false): _hold_unresolved(delta, prepared.reason); return
	if not prepared.get("taken", false): _hold_unresolved(delta, "deferred scene force token missing"); return
	var endpoint: Vector3 = ball.global_position
	var expected: Vector3 = _previous_ball + ball.linear_velocity * delta
	# Error bound for the float32 drift operations only, capped at existing
	# geometry slop. This never relaxes the exact protected-state token.
	var scale: float = maxf(_previous_ball.abs().length(), endpoint.abs().length()) + (ball.linear_velocity * delta).abs().length()
	var reserve: float = minf(History.CONTACT_EPSILON, 8.0 * 1.1920928955078125e-7 * maxf(1.0, scale))
	last_evidence = {"source": "deferred_native_scene_interval", "boundary": pending.kind, "drift_residual": endpoint - expected, "roundoff_bound": reserve}
	if endpoint.distance_to(expected) > reserve:
		_hold_unresolved(delta, "unowned native scene drift"); return
	ball.global_position = _previous_ball
	_deferred_age_fraction = 0.0; _deferred_age_delta = delta
	_continue_motion(0.0, delta, ball.flight_id)
	_deferred_age_fraction = -1.0
	if reset_epoch != _interval_reset_epoch: return
	if unresolved_continuation.is_empty(): ball.reapply_prepared_aero(prepared)
	_update_separation()

func _advance_deferred_bounce_age(fraction: float) -> void:
	if _deferred_age_fraction < 0.0: return
	var next: float = clampf(fraction, _deferred_age_fraction, 1.0)
	if not _passive_age_waiting_floor and game.ball.time_since_last_bounce >= 0.0:
		game.ball.time_since_last_bounce += (next - _deferred_age_fraction) * _deferred_age_delta
	_deferred_age_fraction = next

func _stroke_state(player) -> Dictionary:
	if _serve_strokes.has(ActorIdentity.actor_id(player)) and not game.game_serve._follow_through.is_empty():
		var serve: Dictionary = game.game_serve._follow_through
		if int(serve.get("actor_id", _serve_history.server_actor_id)) == ActorIdentity.actor_id(player):
			return {"serial": int(_serve_strokes[ActorIdentity.actor_id(player)]), "active": float(serve.elapsed) <= ServeStyles.sweep_duration(int(serve.style))}
	if "special_reach_driver" in player and player.special_reach_driver != null:
		var special = player.special_reach_driver
		if special.active:
			# Distinct namespace avoids colliding with human/AI serials.
			return {"serial": 1000000000 + int(special.stroke_serial), "active": bool(special.stroke_contact_active)}
	if player.hitting == null or player.posture == null: return {"serial": -1, "active": false}
	if player.is_ai: return {"serial": player.hitting.stroke_serial, "active": player.hitting.stroke_contact_active}
	var human = player.posture.human_contact
	if human == null: return {"serial": -1, "active": false}
	return {"serial": human.stroke_serial, "active": human.phase in [1, 2]}

func _observe_stroke(player) -> void:
	var state: Dictionary = _stroke_state(player)
	var head: Vector3 = player.paddle_node.global_transform * PaddleDimensions.HEAD_OFFSET
	var previous: Dictionary = _strokes.get(ActorIdentity.actor_id(player), {})
	if previous.is_empty() or int(previous.serial) != int(state.serial):
		state.merge({"direction": Vector3.ZERO, "continuous": true, "hit_direction": Vector3.ZERO})
	else:
		state.merge({"direction": previous.direction, "continuous": previous.continuous, "hit_direction": previous.get("hit_direction", Vector3.ZERO)})
		var motion: Vector3 = head - Vector3(previous.head)
		if state.active and motion.length() > 0.0005:
			var reference: Vector3 = state.hit_direction
			# Anchor only after a real accepted contact, not preparation/regrip.
			if reference.length_squared() > 0.5 and motion.normalized().dot(reference) < 0.0: state.continuous = false
			state.direction = motion.normalized()
	state["head"] = head
	_strokes[ActorIdentity.actor_id(player)] = state

func note_paddle_contact(player) -> void:
	_observe_stroke(player)
	_anchor_stroke(ActorIdentity.actor_id(player))
	if _admitted_paddle_mesh < 0:
		# The finite face sweep may lead the triangle surface by its certified
		# numerical tolerance. Its actual Head is still the admitted manifold;
		# every departing triangle must independently prove separation.
		for id in _contact_pose_snapshots.get(ActorIdentity.actor_id(player), {}).get("parts", {}):
			var part: Dictionary = _contact_pose_snapshots[ActorIdentity.actor_id(player)].parts[id]
			if part.get("equipment", false) and part.part == "Head": _admitted_paddle_mesh = int(id); break
	_last_contact = {"actor_id": ActorIdentity.actor_id(player), "team_id": ActorIdentity.team_id(player), "court_side": ActorIdentity.court_side(player), "player_num": ActorIdentity.team_id(player), "stroke_serial": int(_stroke_state(player).serial), "mesh_id": _admitted_paddle_mesh}
	_separated = false

func continue_paddle_remainder(_actor, elapsed: float, global_fraction: float) -> Dictionary:
	var reset_epoch: int = _interval_reset_epoch
	## Call immediately after accepted physical contact and note_paddle_contact.
	## before_paddle captured contact geometry; the owner may provide the full
	## current-frame pose snapshot by calling capture_remainder_endpoint first.
	if not unresolved_continuation.is_empty():
		return {"complete": false, "blocked": true, "remaining_seconds": unresolved_continuation.remaining_seconds}
	if _frame_current.is_empty(): _capture_current()
	var prior_geometry: Dictionary = _snapshots.duplicate(true)
	_consumed_path_bounds = AABB(game.ball.global_position, Vector3.ZERO).grow(game.ball.BALL_RADIUS)
	if _controller_incoming_frame == Engine.get_physics_frames(): _consumed_path_bounds = _consumed_path_bounds.merge(_controller_incoming_bounds)
	_record_consumed_motion = true
	_observe_stroke(_actor)
	_remainder_geometry_start = clampf(global_fraction, 0.0, 1.0)
	_deferred_age_fraction = clampf(global_fraction, 0.0, 1.0); _deferred_age_delta = maxf(elapsed, 0.0)
	_continue_motion(clampf(global_fraction, 0.0, 1.0), maxf(elapsed, 0.0), _contact_incoming_flight)
	_deferred_age_fraction = -1.0
	_record_consumed_motion = false
	if reset_epoch != _interval_reset_epoch:
		return {"complete": true, "blocked": false, "remaining_seconds": 0.0, "reset": true}
	game.ball.mark_bounce_age_consumed()
	if unresolved_continuation.is_empty():
		_consumed_motion = {"frame": Engine.get_physics_frames(), "flight": game.ball.flight_id, "epoch": reset_epoch,
			"delta": elapsed, "fraction": global_fraction, "position": game.ball.global_position, "velocity": game.ball.linear_velocity,
			"omega": game.ball.angular_velocity, "bounces": game.ball.bounce_count, "bounds": _consumed_path_bounds,
			"geometry": _frame_current.duplicate(true), "prior_geometry": prior_geometry}
	_previous_ball = game.ball.global_position
	_flight = game.ball.flight_id
	_snapshots = _frame_current.duplicate()
	_update_separation()
	_remainder_geometry_start = -1.0
	return {"complete": unresolved_continuation.is_empty(), "blocked": not unresolved_continuation.is_empty(),
		"remaining_seconds": float(unresolved_continuation.get("remaining_seconds", 0.0))}


func _record_consumed_path(from: Vector3, to: Vector3, reserve: float) -> void:
	if _record_consumed_motion:
		_consumed_path_bounds = _consumed_path_bounds.merge(AABB(from, Vector3.ZERO).expand(to).grow(game.ball.BALL_RADIUS + reserve))

func _consume_controller_motion_receipt(delta: float) -> bool:
	if _consumed_motion.is_empty(): return false
	var receipt: Dictionary = _consumed_motion
	_consumed_motion = {}
	var ball = game.ball
	if int(receipt.frame) != Engine.get_physics_frames() or int(receipt.flight) != ball.flight_id or int(receipt.epoch) != _interval_reset_epoch: return false
	if float(receipt.delta) != delta or not ball.matches_consumed_motion(receipt):
		last_evidence["consumed_motion"] = receipt
		_hold_unresolved(delta, "controller consumed motion state changed")
		return true
	# Endpoint publication can happen after a controller's own callback. An
	# endpoint alone cannot certify an intervening crossing. Only unchanged
	# actual geometry or disjoint whole-interval bounds certify this receipt.
	for actor_id in _frame_current:
		var current: Dictionary = _frame_current[actor_id]
		var captured: Dictionary = receipt.geometry.get(actor_id, {})
		var prior: Dictionary = receipt.prior_geometry.get(actor_id, captured)
		if not _late_geometry_clear(prior, captured, current, receipt.bounds):
			last_evidence["consumed_motion"] = {"frame": receipt.frame, "flight": receipt.flight, "actor_id": actor_id, "delta": delta, "fraction": receipt.fraction, "path_bounds": receipt.bounds}
			_hold_unresolved(delta, "later actor geometry intersects consumed interval bounds")
			return true
	return true

func _late_geometry_clear(prior: Dictionary, captured: Dictionary, current: Dictionary, path_bounds: AABB) -> bool:
	if prior.is_empty() or captured.is_empty() or current.is_empty(): return false
	if captured.parts.size() != current.parts.size(): return false
	for id in current.parts:
		if not captured.parts.has(id) or not prior.parts.has(id): return false
		var now: Dictionary = current.parts[id]
		var old: Dictionary = captured.parts[id]
		if now.mesh_key == old.mesh_key and now.transform == old.transform and now.palette == old.palette and now.get("hand", {}) == old.get("hand", {}): continue
		var swept: AABB = prior.parts[id].bounds.merge(old.bounds).merge(now.bounds)
		if swept.intersects(path_bounds): return false
	return true

func capture_remainder_endpoint() -> void:
	_capture_current()

func _anchor_stroke(player_num: int) -> void:
	var observed: Dictionary = _strokes[player_num]
	observed["hit_direction"] = observed.direction
	observed["continuous"] = true

func _illegal_hand_reason(player, evidence: Dictionary, recontact: bool) -> String:
	var ball = game.ball
	if evidence.get("simultaneous_partner_contact", false): return "DOUBLE_CONTACT"
	if recontact: return ""
	if ball.get_last_hit_team_id() == ActorIdentity.team_id(player): return "DOUBLE_CONTACT"
	if ball.bounces_since_last_hit == 0:
		if not ball.both_bounces_complete: return "TWO_BOUNCE_RULE"
		if not player.can_volley_from_feet(): return "KITCHEN_VOLLEY"
	var own: float = 1.0 if ActorIdentity.court_side(player) == 0 else -1.0
	var returned: bool = ball.receiver_entire_ball_crossed and ball.receiver_side_bounced and ball.receiver_returned_across_net and ball.bounces_since_last_hit == 1 and ball.get_last_hit_team_id() == 1 - ActorIdentity.team_id(player)
	if Vector3(evidence.point).z * own < ball.BALL_RADIUS and not returned: return "NET_PLANE"
	return ""

func _resolve_hand(evidence: Dictionary, full_delta: float) -> Dictionary:
	var began: int = Time.get_ticks_usec()
	var queries_before: int = _query_work
	var algebra_before: int = _algebra_units
	var steps_before: int = _manifold_step_count
	var result: Dictionary = _resolve_hand_impl(evidence, full_delta)
	_record_performance("physical_resolution", began, queries_before, algebra_before, steps_before)
	return result

func _resolve_hand_impl(evidence: Dictionary, full_delta: float) -> Dictionary:
	var ball = game.ball
	var player = ActorIdentity.find_actor(game, _evidence_actor(evidence))
	if player == null: return {"stop": false, "unresolved": true, "reason": "unknown contact actor"}
	var stroke: Dictionary = _strokes.get(ActorIdentity.actor_id(player), _stroke_state(player))
	if evidence.get("kind", "body") in ["legal_paddle", "legal_hand"]:
		var rig: Dictionary = ArmBudget.displayed_report(player)
		# Pixel cards don't draw the 3D wrist, so an over-budget wrist pose is not
		# visible; rejecting the contact would freeze the rally and pause the game.
		if not rig.valid and not load("res://scripts/graphics/pixel_card_rig.gd").enabled():
			last_evidence["rejected_rig"] = rig
			return {"stop": false, "unresolved": true, "reason": "infeasible actual hitting-surface rig"}
	var live_stroke: Dictionary = _stroke_state(player)
	var direction_known: bool = Vector3(stroke.get("hit_direction", Vector3.ZERO)).length_squared() > 0.5 and int(live_stroke.serial) == int(stroke.serial)
	var previous_contact: Dictionary = _last_contact.duplicate()
	previous_contact["actor_id"] = _evidence_actor(_last_contact)
	var decision: Dictionary = HandResponse.classify_actor_contact(previous_contact, ActorIdentity.actor_id(player), ActorIdentity.team_id(player), ball.get_last_hit_actor_id(), ball.get_last_hit_team_id(), int(stroke.serial),
		true, _separated, bool(live_stroke.active), bool(stroke.get("continuous", false)) and direction_known)
	if decision.get("fault", false):
		var fault_evidence: Dictionary = evidence.duplicate(true); fault_evidence.merge(decision, true)
		game.rally_scorer.on_actor_illegal_repeat_contact(ActorIdentity.actor_id(player), fault_evidence)
		return {"stop": true}
	var recontact: bool = decision.classification != "NEW_CONTACT"
	var reason: String = _illegal_hand_reason(player, evidence, recontact)
	if reason != "":
		game.rally_scorer.on_actor_illegal_hitting_surface_contact(ActorIdentity.actor_id(player), reason, evidence)
		return {"stop": true}
	# Advisory permission is checked against the sealed pre-event state. The
	# receiving hook below is this same event's own authoritative mutation.
	var event_permission: Dictionary = _prepare_event_intent(player, evidence) if _ordered_live and not recontact and evidence.get("kind", "") == "legal_paddle" else {}
	var receiving_epoch: int = _interval_reset_epoch
	var receiving: Dictionary = _observe_receiving_contact(player, evidence)
	if receiving_epoch != _interval_reset_epoch: return {"stop": true, "reset": true}
	if not receiving.allowed:
		last_evidence["service_context"] = receiving.rule
		return {"stop": not receiving.get("unresolved", false), "unresolved": receiving.get("unresolved", false), "reason": "service context unresolved"}
	var face: Dictionary = _face_for_contact(evidence)
	if _ordered_live and not recontact and evidence.get("kind", "") == "legal_paddle":
		var aimed: Dictionary = _settle_intended_paddle(player, evidence, full_delta, event_permission)
		if aimed.get("reset", false): return {"stop": true, "reset": true}
		if aimed.get("accepted", false):
			_face_free = {} if face.is_empty() else {"mesh_id": int(evidence.mesh_id), "source": int(face.source), "position": ball.global_position, "fraction": float(evidence.fraction)}
			_observe_stroke(player); _anchor_stroke(ActorIdentity.actor_id(player))
			_last_contact = {"actor_id": ActorIdentity.actor_id(player), "team_id": ActorIdentity.team_id(player), "court_side": ActorIdentity.court_side(player), "player_num": ActorIdentity.team_id(player), "stroke_serial": int(_stroke_state(player).serial), "mesh_id": int(evidence.mesh_id)}
			_separated = false
			return {"stop": not ball.is_in_play, "unresolved": false, "intended": true}
		if aimed.get("unresolved", false): return aimed
	if recontact and not face.is_empty() and not _face_free.is_empty() and int(_face_free.get("mesh_id", -1)) == int(evidence.get("mesh_id", -2)) and int(_face_free.get("source", -1)) == int(face.source):
		var certificate: Dictionary = Manifold.qualify_interval(face, _face_free.position, evidence.point, float(_face_free.fraction), float(evidence.fraction), ball.BALL_RADIUS)
		if certificate.qualified:
			support_observation = SupportEvidence.initial()
			_manifold = {"actor_id": ActorIdentity.actor_id(player), "team_id": ActorIdentity.team_id(player), "court_side": ActorIdentity.court_side(player), "player_num": ActorIdentity.team_id(player), "mesh_id": int(evidence.mesh_id), "source": int(face.source), "face": face, "normal": evidence.normal}
			_record_manifold({"event": "maintained_entry", "fraction": evidence.fraction, "certificate": certificate, "incoming": ball.linear_velocity})
			return {"stop": false, "unresolved": false, "maintained": true}
	var response: Dictionary = HandResponse.solve(ball.linear_velocity, evidence, full_delta)
	if not response.qualified: return {"stop": false, "unresolved": true, "reason": response.reason}
	# Contiguous manifolds do not award another stroke/flight, but an actual
	# closing surface can still require a physical normal impulse.
	if not response.responded:
		last_evidence["separating_response"] = response
		if recontact:
			_last_contact = {"actor_id": ActorIdentity.actor_id(player), "team_id": ActorIdentity.team_id(player), "court_side": ActorIdentity.court_side(player), "player_num": ActorIdentity.team_id(player), "stroke_serial": int(stroke.serial), "mesh_id": int(evidence.get("mesh_id", -1))}
			_separated = false
			return {"stop": false, "unresolved": false, "separating": true}
		return {"stop": false, "unresolved": true, "reason": "unproven separating manifold"}
	ball.linear_velocity = response.velocity
	_face_free = {} if face.is_empty() else {"mesh_id": int(evidence.mesh_id), "source": int(face.source), "position": ball.global_position, "fraction": float(evidence.fraction)}
	if not recontact:
		var callback_epoch: int = _interval_reset_epoch
		var ball_epoch: int = ball.contact_callback_epoch()
		var recorded: bool = ball.hit_by_actor(player)
		var boundary: Dictionary = _contact_callback_boundary(callback_epoch, ball_epoch, recorded)
		if not boundary.is_empty(): return boundary
		player.set_meta("legal_net_followthrough_flight", ball.flight_id)
		_anchor_stroke(ActorIdentity.actor_id(player))
		if not player.is_ai and player.posture.human_contact != null: player.posture.human_contact.notify_physical_hand_contact(evidence)
		if player.erne_action != null and player.erne_action.active: player.erne_action.notify_hit()
		player.stamina.spend_contact("VOLLEY" if ball.was_volley else "GROUNDSTROKE", ball.linear_velocity.length())
		game.scoreboard_ui.show_speed(ball.linear_velocity.length() * 2.23694)
	_last_contact = {"actor_id": ActorIdentity.actor_id(player), "team_id": ActorIdentity.team_id(player), "court_side": ActorIdentity.court_side(player), "player_num": ActorIdentity.team_id(player), "stroke_serial": int(stroke.serial), "mesh_id": int(evidence.get("mesh_id", -1))}
	_separated = false
	last_evidence["response"] = response; last_evidence["classification"] = decision.classification
	return {"stop": not ball.is_in_play, "unresolved": false, "response": response}

func _hand_contact(evidence: Dictionary, full_delta: float) -> void:
	var ball = game.ball
	var incoming_flight: int = ball.flight_id
	var fraction: float = clampf(float(evidence.fraction), 0.0, 1.0)
	ball.global_position = evidence.point
	ball.observe_receiver_position(ball.global_position)
	var resolution: Dictionary = _resolve_hand(evidence, full_delta)
	if resolution.get("stop", false): return
	if resolution.get("unresolved", false):
		_hold_unresolved(full_delta * (1.0 - fraction), resolution.reason); return
	# Ball already advanced the incoming frame clock before this late query.
	# Preserve that clock until an actual outgoing floor resets it; only its
	# newly consumed tail needs age advancement. No earlier Ball callback is
	# marked newly consumed by this late continuation.
	_deferred_age_fraction = fraction; _deferred_age_delta = full_delta
	_passive_age_waiting_floor = true
	_continue_motion(fraction, full_delta, incoming_flight)
	_deferred_age_fraction = -1.0; _passive_age_waiting_floor = false

func _continue_motion(impact_fraction: float, full_delta: float, incoming_flight: int) -> void:
	var reset_epoch: int = _interval_reset_epoch
	_delta = full_delta
	var ball = game.ball
	var fraction: float = impact_fraction
	var drift_remaining: float = full_delta * (1.0 - fraction) # native current-interval kick already consumed
	var hand_event := 0
	var maintained_scene_events := 0
	while hand_event < MAX_HAND_IMPACTS:
		if not _manifold.is_empty():
			var maintained: Dictionary = _advance_manifold(fraction, full_delta, incoming_flight)
			if not maintained.get("complete", false) or maintained.get("stop", false): return
			fraction = float(maintained.fraction)
			if maintained.has("body"):
				var contact: Dictionary = maintained.body
				if contact.get("kind", "body") not in ["legal_hand", "legal_paddle"]: _fault(contact); return
				ball.observe_receiver_position(ball.global_position)
				var resolution: Dictionary = _resolve_hand(contact, full_delta)
				if not resolution.get("maintained", false): hand_event += 1
				if resolution.get("stop", false): return
				if resolution.get("unresolved", false): _hold_unresolved(full_delta * (1.0 - fraction), resolution.reason); return
			elif maintained.has("scene"):
				maintained_scene_events += 1
				if maintained_scene_events > Remainder.MAX_EVENTS: _hold_unresolved(full_delta * (1.0 - fraction), "maintained scene event budget"); return
				var event: Dictionary = Remainder.response_event(maintained.scene, ball.linear_velocity, ball.angular_velocity)
				_apply_static_event(event)
				if not unresolved_continuation.is_empty(): return
				if reset_epoch != _interval_reset_epoch: return
				ball.global_position += Vector3(event.normal) * Remainder.CONTACT_EPSILON
				if not ball.is_in_play: return
				if not _manifold.is_empty(): continue
			drift_remaining = full_delta * (1.0 - fraction)
			if fraction >= 1.0 - 1e-12: return
		var continuation: Dictionary = Remainder.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, full_delta * (1.0 - fraction), ball.BALL_RADIUS, drift_remaining, _scene_context())
		var restart := false
		for segment in continuation.segments:
			_record_consumed_path(segment.from, segment.to, 0.0)
			var start: float = fraction + float(segment.time_from) / maxf(full_delta, 1e-12)
			var end: float = fraction + float(segment.time_to) / maxf(full_delta, 1e-12)
			var first: Dictionary = _query_range(segment.from, segment.to, start, end, incoming_flight, Vector3(segment.velocity_from) * (float(segment.time_to) - float(segment.time_from)), segment.velocity_from)
			if first.get("ambiguous", false):
				last_evidence["unresolved_query"] = first.duplicate(true)
				ball.global_position = segment.from; ball.linear_velocity = segment.velocity_from; ball.angular_velocity = segment.omega_from
				_hold_unresolved(full_delta * (1.0 - start), "body contact continuation budget"); return
			if first.get("hit", false):
				var local: float = float(first.get("range_fraction", 0.0))
				ball.global_position = first.point; ball.linear_velocity = Vector3(segment.velocity_from).lerp(segment.velocity_to, local)
				ball.angular_velocity = Vector3(segment.omega_from).lerp(segment.omega_to, local)
				_advance_deferred_bounce_age(float(first.fraction))
				ball.observe_receiver_position(ball.global_position)
				last_evidence["remainder_contact"] = first.duplicate(true)
				if first.get("kind", "body") not in ["legal_hand", "legal_paddle"]: _fault(first); return
				# Positive time after an outward-support proof is a new physical
				# contact. No timeout/hand-label exemption erases the recontact.
				if float(first.fraction) > start + 1e-8: _separated = true
				drift_remaining = maxf(0.0, float(segment.kick_end_time) - (float(first.fraction) - fraction) * full_delta)
				fraction = float(first.fraction)
				var resolution: Dictionary = _resolve_hand(first, full_delta)
				if resolution.get("stop", false): return
				if not resolution.get("maintained", false): hand_event += 1
				if resolution.get("unresolved", false): _hold_unresolved(full_delta * (1.0 - fraction), resolution.reason); return
				restart = true; break
			ball.global_position = segment.to; ball.linear_velocity = segment.velocity_to; ball.angular_velocity = segment.omega_to
			_advance_deferred_bounce_age(end)
			ball.observe_receiver_position(segment.to)
			_update_separation_at(segment.to, end, incoming_flight)
			_apply_static_event(segment.event_after)
			if not unresolved_continuation.is_empty(): return
			if reset_epoch != _interval_reset_epoch: return
			if not ball.is_in_play: return
		if restart: continue
		ball.global_position = continuation.position; ball.linear_velocity = continuation.velocity; ball.angular_velocity = continuation.omega
		if not continuation.complete: _hold_unresolved(continuation.remaining_elapsed, "static collision continuation budget")
		return
	_hold_unresolved(full_delta * (1.0 - fraction), "hand impact continuation budget")

func _apply_static_event(event: Dictionary) -> void:
	if event.is_empty(): return
	var ball = game.ball
	ball.linear_velocity = event.outgoing; ball.angular_velocity = event.omega_after
	_ordered_first_floor.clear()
	if event.type == "floor":
		var continuity: Dictionary = _begin_owned_first_floor(event)
		_passive_age_waiting_floor = false
		ball.bounce_count += 1; ball.can_register_floor_bounce = false
		ball.bounced.emit(event.point)
		_finish_owned_first_floor(continuity, event)
	elif event.type == "wall":
		var guard = ball._net_contact_guard
		if not is_instance_valid(guard) or not guard.has_method("apply_authoritative_contact") or not guard.apply_authoritative_contact(event):
			_hold_unresolved(0.0, "ordered wall publisher changed")
	elif event.type in ["post", "net"]:
		var net = game.get_node_or_null("Net")
		var published: bool = net != null and net.apply_authoritative_contact(event)
		if not published:
			if event.type == "post": game.rally_scorer.on_ball_hit_post(event.point)
			elif net != null: net.add_impact(net.to_local(event.point), event.incoming)

func _update_separation_at(point: Vector3, fraction: float, incoming_flight: int) -> void:
	if _separated or _last_contact.is_empty(): return
	var number: int = _evidence_actor(_last_contact)
	if number < 0 or not _frame_current.has(number): return
	var current: Dictionary = _frame_current[number]
	var previous: Dictionary = _snapshots.get(number, current) if _flight == incoming_flight else current
	var geometry_fraction: float = fraction
	if _remainder_geometry_start >= 0.0:
		previous = _contact_pose_snapshots.get(number, current)
		geometry_fraction = clampf((fraction - _remainder_geometry_start) / maxf(1.0 - _remainder_geometry_start, 1e-12), 0.0, 1.0)
	if not History.touching_hitting_surface(previous, current, point, game.ball.BALL_RADIUS, geometry_fraction): _separated = true

func _update_separation() -> void:
	if _separated or _last_contact.is_empty() or not unresolved_continuation.is_empty(): return
	_update_separation_at(game.ball.global_position, 1.0, _flight)

func _hold_unresolved(remaining: float, reason: String) -> void:
	unresolved_continuation = {"remaining_seconds": maxf(0.0, remaining), "position": game.ball.global_position,
		"velocity": game.ball.linear_velocity, "omega": game.ball.angular_velocity, "reason": reason}
	game.ball.set_meta("contact_authority_unresolved", true)
	game.ball.set_time_frozen(true)
	game.ball.set_frozen_state(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity)
	push_warning("Unresolved contact continuation: " + reason)
	# Rare solver failure: replay the point (no score change) instead of stopping the
	# match behind a pause menu whose only way out reset the whole match.
	if not _replay_pending:
		_replay_pending = true
		_replay_point.call_deferred()

var _replay_pending: = false

func _replay_point() -> void:
	_replay_pending = false
	if not is_instance_valid(game) or unresolved_continuation.is_empty(): return
	game._reset_ball()   # cancels the rally without scoring, ball back to the server
	game.scoreboard_ui.show_fault("Replay point", "Contact couldn't be resolved · no point awarded")
	var pause = get_node_or_null("/root/PauseController")   # drop any pause the hold caused
	if pause != null and pause.has_method("_set_pause_state"): pause._set_pause_state()

func _exit_tree() -> void:
	if is_instance_valid(game) and is_instance_valid(game.ball):
		game.ball.set_authoritative_paddles([])
		game.ball.set_scene_interval_owner(null)

func _face_for_contact(evidence: Dictionary) -> Dictionary:
	if evidence.get("kind", "legal_paddle") != "legal_paddle": return {}
	var number: int = _evidence_actor(evidence)
	var id: int = int(evidence.get("mesh_id", -1))
	var current: Dictionary = _frame_current.get(number, {})
	var previous: Dictionary = _snapshots.get(number, current)
	if _remainder_geometry_start >= 0.0: previous = _contact_pose_snapshots.get(number, current)
	if not current.get("parts", {}).has(id) or not previous.get("parts", {}).has(id): return {}
	var face: Dictionary = Manifold.from_parts(previous.parts[id], current.parts[id], int(evidence.get("triangle_offset", -1)), evidence.get("normal", Vector3.ZERO))
	if face.is_empty(): return {}
	if _remainder_geometry_start >= 0.0:
		var start: float = _remainder_geometry_start
		var span: float = maxf(1.0 - start, 1e-12)
		for key in ["a", "b", "c"]:
			face["d" + key] = Vector3(face["d" + key]) / span
			face[key] = Vector3(face[key]) - Vector3(face["d" + key]) * start
		for i in face.polygon.size():
			face.motion[i] /= span; face.polygon[i] -= face.motion[i] * start
	return face

func _advance_manifold(start: float, full_delta: float, incoming_flight: int) -> Dictionary:
	var began: int = Time.get_ticks_usec()
	var queries_before: int = _query_work
	var algebra_before: int = _algebra_units
	var steps_before: int = _manifold_step_count
	var result: Dictionary = _advance_manifold_impl(start, full_delta, incoming_flight)
	_record_performance("maintained_interval", began, queries_before, algebra_before, steps_before)
	return result

func _advance_manifold_impl(start: float, full_delta: float, incoming_flight: int) -> Dictionary:
	var ball = game.ball
	var time: float = start
	var face: Dictionary = _manifold.face
	var candidate_end := 1.0
	var obstacle_refinements := 0
	_maintained_faces = {int(_manifold.mesh_id): face.offsets}; _maintained_player = _evidence_actor(_manifold)
	for step_index in Manifold.MAX_STEPS:
		var next: Dictionary = Manifold.step(face, ball.global_position, ball.linear_velocity, time, candidate_end, full_delta, ball.BALL_RADIUS)
		if not next.complete:
			_maintained_faces = {}; _maintained_player = -1
			_record_manifold(next); _hold_unresolved(full_delta * (1.0 - time), next.reason)
			return {"complete": false}
		if next.released and float(next.time) <= time + 1e-12:
			ball.global_position = next.position; ball.linear_velocity = next.velocity
			_advance_deferred_bounce_age(time)
			ball.observe_receiver_position(ball.global_position)
			_record_manifold(next); _manifold = {}; _face_free = {}
			_maintained_faces = {}; _maintained_player = -1
			return {"complete": true, "fraction": time}
		var error: float = float(next.chord_error_bound) + float(next.integration_position_bound) + float(next.position_projection)
		_record_consumed_path(next.from, next.position, error)
		# Outer CCD proves clearance; inner CCD proves an actual encounter.
		# Neither alone is used as an actual physical contact award/fault.
		_query_radius_adjustment = error - History.CONTACT_EPSILON
		var outer: Dictionary = _query_range(next.from, next.position, time, next.time, incoming_flight)
		_query_radius_adjustment = 0.0
		var scene_outer: Dictionary = Remainder._first_collision(next.from, next.position, next.velocity_from, ball.BALL_RADIUS + error, _scene_context())
		if outer.get("ambiguous", false):
			_maintained_faces = {}; _maintained_player = -1
			last_evidence["unresolved_query"] = outer; _hold_unresolved(full_delta * (1.0 - time), "maintained body query budget")
			return {"complete": false}
		if outer.get("hit", false) or scene_outer.get("hit", false):
			_query_radius_adjustment = -error - History.CONTACT_EPSILON
			var inner: Dictionary = _query_range(next.from, next.position, time, next.time, incoming_flight)
			_query_radius_adjustment = 0.0
			var scene_inner: Dictionary = Remainder._first_collision(next.from, next.position, next.velocity_from, maxf(0.0, ball.BALL_RADIUS - error), _scene_context())
			var local := INF
			if inner.get("hit", false): local = float(inner.range_fraction)
			if scene_inner.get("hit", false): local = minf(local, float(scene_inner.fraction))
			if is_finite(local):
				var contact_time: float = lerpf(time, float(next.time), local)
				var exact: Dictionary = {"complete": true, "time": time, "position": next.from, "velocity": next.velocity_from}
				if contact_time > time + 1e-12: exact = Manifold.step(face, next.from, next.velocity_from, time, contact_time, full_delta, ball.BALL_RADIUS)
				if exact.get("complete", false) and absf(float(exact.time) - contact_time) < 1e-10:
					_query_radius_adjustment = -History.CONTACT_EPSILON
					_confirm_actual_contact = true
					var actual: Dictionary = _query_range(exact.position, exact.position, contact_time, contact_time, incoming_flight)
					_confirm_actual_contact = false
					_query_radius_adjustment = 0.0
					var scene_actual: Dictionary = Remainder.contact_at(exact.position, exact.velocity, ball.BALL_RADIUS, _scene_context())
					var outer_time: float = float(outer.fraction) if outer.get("hit", false) else INF
					if scene_outer.get("hit", false): outer_time = minf(outer_time, lerpf(time, float(next.time), float(scene_outer.fraction)))
					if (actual.get("hit", false) or scene_actual.get("hit", false)) and (contact_time - outer_time) * full_delta <= 0.000001:
						ball.global_position = exact.position; ball.linear_velocity = exact.velocity
						_advance_deferred_bounce_age(contact_time)
						ball.observe_receiver_position(ball.global_position)
						_face_free = {}; _maintained_faces = {}; _maintained_player = -1
						_record_manifold({"event": "ordered_obstacle", "time_from": time, "time_to": contact_time, "time_bracket": Vector2(outer_time, contact_time), "curve_error_bound": error, "actual_body": actual, "actual_scene": scene_actual})
						if actual.get("hit", false):
							_manifold = {}
							return {"complete": true, "fraction": contact_time, "body": actual}
						return {"complete": true, "fraction": contact_time, "scene": scene_actual}
			obstacle_refinements += 1
			if obstacle_refinements >= 24 or (float(next.time) - time) * full_delta < 1e-9:
				_maintained_faces = {}; _maintained_player = -1
				last_evidence["maintained_obstacle"] = {"outer": outer, "inner": inner, "scene_outer": scene_outer, "scene_inner": scene_inner, "curve_error_bound": error}
				_hold_unresolved(full_delta * (1.0 - time), "maintained obstacle numerical budget")
				return {"complete": false}
			candidate_end = (time + float(next.time)) * .5
			continue
		support_observation = SupportEvidence.observe_step(support_observation, face, next, time, full_delta, ball.BALL_RADIUS)
		ball.global_position = next.position; ball.linear_velocity = next.velocity
		_advance_deferred_bounce_age(float(next.time))
		ball.observe_receiver_position(ball.global_position)
		_record_manifold(next)
		time = float(next.time); candidate_end = 1.0; obstacle_refinements = 0
		if next.released:
			_manifold = {}; _face_free = {}; _maintained_faces = {}; _maintained_player = -1
			return {"complete": true, "fraction": time}
		if time >= 1.0 - 1e-12:
			_manifold.normal = Manifold.frame_at(face, time, full_delta).n
			_maintained_faces = {}; _maintained_player = -1
			return {"complete": true, "fraction": 1.0}
	_maintained_faces = {}; _maintained_player = -1
	_hold_unresolved(full_delta * (1.0 - time), "maintained interval budget")
	return {"complete": false}

func _record_manifold(receipt: Dictionary) -> void:
	manifold_receipts.append(receipt)
	if receipt.get("reason", "") in ["maintained_finite_face", "finite_face_exit"]: _manifold_step_count += 1
	if manifold_receipts.size() > 512: manifold_receipts.pop_front()

func _record_performance(kind: String, began: int, query_before: int, algebra_before: int, steps_before: int) -> void:
	var cold := false
	if kind == "surface_query": cold = _first_query; _first_query = false
	if kind == "physical_resolution": cold = _first_resolution; _first_resolution = false
	performance_receipts.append({"kind": kind, "cold": cold, "cost_us": Time.get_ticks_usec() - began,
		"triangle_queries": maxi(0, _query_work - query_before), "algebra_units": maxi(0, _algebra_units - algebra_before),
		"manifold_steps": _manifold_step_count - steps_before, "physics_frame": Engine.get_physics_frames(), "maintained": not _manifold.is_empty()})
	if performance_receipts.size() > 512: performance_receipts.pop_front()

func _players() -> Array:
	return ActorIdentity.players(game, [game.player_left, game.player_right])

func _paddles() -> Array:
	var result: Array = []
	for actor in _players(): result.append(actor.paddle_node)
	return result

func _evidence_actor(evidence: Dictionary) -> int:
	return ActorIdentity.evidence_actor(evidence, game, [game.player_left, game.player_right])

func _observe_receiving_contact(actor, evidence: Dictionary) -> Dictionary:
	if not game.has_method("observe_doubles_first_return"):
		return {"allowed": false, "unresolved": true, "rule": {"reason": "SERVICE_CONTEXT_UNRESOLVED", "detail": "missing first-return observer"}} if game.get("doubles_mode") == true else {"allowed": true}
	# This is reached only for a measured finite hitting surface, after the
	# common rig, earliest-contact and physical-rule gates. No planned feed
	# or approach pose can consume the service ledger's first-return event.
	if not evidence.get("hit", false) or evidence.get("ambiguous", false) or evidence.get("kind", "body") not in ["legal_paddle", "legal_hand"]:
		return {"allowed": false, "unresolved": true, "rule": {"reason": "UNOBSERVED_RECEIVING_CONTACT"}}
	var result: Dictionary = game.observe_doubles_first_return(actor)
	if result.get("valid", false): return {"allowed": true}
	if result.get("unresolved", false): return {"allowed": false, "unresolved": true, "rule": result}
	if result.get("reason", "") != "WRONG_RECEIVER" or int(result.get("winner", -1)) != 1 - ActorIdentity.team_id(actor):
		return {"allowed": false, "unresolved": true, "rule": result}
	game.rally_scorer.on_actor_receiving_contact_fault(ActorIdentity.actor_id(actor), result, evidence)
	return {"allowed": false, "unresolved": false, "rule": result}

# Two-phase publication is deliberately separate from finite contact evidence.
func uses_two_phase_contact(actor) -> bool:
	return owns_live_scene_motion() and game.game_state == game.GameState.PLAYING and ActorIdentity.find_actor(game, ActorIdentity.actor_id(actor)) == actor

func publish_contact_intent(actor, intent: Dictionary) -> Dictionary:
	if not uses_two_phase_contact(actor) or not unresolved_continuation.is_empty() or not IntentQueue.controller_payload(intent): return {"valid": false, "reason": "inactive_or_invalid_intent"}
	var frame: int = Engine.get_physics_frames()
	var id: int = ActorIdentity.actor_id(actor)
	if actor.process_physics_priority >= process_physics_priority: return {"valid": false, "reason": "actor_publication_priority"}
	if _published_intents.has(id) and int(_published_intents[id].frame) == frame: return {"valid": false, "reason": "duplicate_frame_intent"}
	_published_intents[id] = {"frame": frame, "flight": game.ball.flight_id, "epoch": _interval_reset_epoch,
		"instance": actor.get_instance_id(), "team_id": ActorIdentity.team_id(actor), "court_side": ActorIdentity.court_side(actor), "stroke": int(_stroke_state(actor).serial), "intent": intent.duplicate(true)}
	return {"valid": true, "frame": frame, "flight": game.ball.flight_id}

func _controller_for_intent(actor, kind: String):
	if kind == "ai" and actor.is_ai: return actor.ai_brain
	if kind == "human" and not actor.is_ai and actor.posture != null: return actor.posture.human_contact
	return null

func _snapshot_version(snapshot: Dictionary) -> PackedByteArray:
	var values: Array = [snapshot.get("root"), snapshot.get("paddle"), snapshot.get("has_paddle")]
	var ids: Array = snapshot.get("parts", {}).keys(); ids.sort()
	for id in ids:
		var part: Dictionary = snapshot.parts[id]
		values.append([id, part.get("mesh_key"), part.get("transform"), part.get("palette"), part.get("hand")])
	return var_to_bytes(values)

func _seal_contact_intents(pending: Dictionary, seconds: float) -> bool:
	_ordered_initial_bounces = game.ball.bounces_since_last_hit; _ordered_floor_events = 0
	_ordered_first_floor.clear(); _preparing_event_intent.clear()
	var roster: Array = []
	for actor in _players():
		if actor.process_physics_priority >= process_physics_priority: return false
		roster.append({"actor_id": ActorIdentity.actor_id(actor), "team_id": ActorIdentity.team_id(actor), "court_side": ActorIdentity.court_side(actor), "instance_id": actor.get_instance_id()})
	_intent_interval = {"frame": Engine.get_physics_frames(), "reset_epoch": _interval_reset_epoch, "flight": game.ball.flight_id,
		"native_serial": int(pending.native_sample.serial), "seconds": seconds, "control_seconds": _control_delta}
	if not _intents.begin(_intent_interval, roster): return false
	for actor in _players():
		var id: int = ActorIdentity.actor_id(actor)
		var version: PackedByteArray = _snapshot_version(_current_snapshot(actor))
		if not _intents.publish_pose(id, actor.get_instance_id(), _intent_interval, version): return false
		var offer: Dictionary = _published_intents.get(id, {})
		if offer.is_empty() or int(offer.frame) != Engine.get_physics_frames() or int(offer.flight) != game.ball.flight_id or int(offer.epoch) != _interval_reset_epoch or int(offer.instance) != actor.get_instance_id() or int(offer.team_id) != ActorIdentity.team_id(actor) or int(offer.court_side) != ActorIdentity.court_side(actor): continue
		var controller = _controller_for_intent(actor, str(offer.intent.get("kind", "")))
		if controller == null or not controller.contact_intent_is_current(offer.intent): continue
		var result: Dictionary = _intents.offer(id, actor.get_instance_id(), _intent_interval, int(offer.stroke), version, offer.intent)
		if not result.valid: return false
	return _intents.seal(_intent_interval)

func _finish_published_intents() -> void:
	var completed: Dictionary = _published_intents
	_published_intents = {}
	for id in completed:
		if not unresolved_continuation.is_empty(): break
		var offer: Dictionary = completed[id]
		if int(offer.frame) != Engine.get_physics_frames() or int(offer.epoch) != _interval_reset_epoch: continue
		var actor = ActorIdentity.find_actor(game, int(id))
		if actor == null or actor.get_instance_id() != int(offer.instance): continue
		var controller = _controller_for_intent(actor, str(offer.intent.get("kind", "")))
		if controller != null: controller.finish_contact_intent(offer.intent)
	_intents.reset(); _intent_interval.clear(); _settlement_scope.clear(); _ordered_live = false
	_ordered_initial_bounces = -1; _ordered_floor_events = 0; _ordered_first_floor.clear(); _preparing_event_intent.clear()

func _process_ordered_live(pending: Dictionary, control_seconds: float) -> void:
	var ball = game.ball
	var sample: Dictionary = pending.get("native_sample", {})
	var seconds: float = float(sample.get("seconds", -1.0))
	if int(pending.frame) != Engine.get_physics_frames() or int(pending.flight) != ball.flight_id or _flight != ball.flight_id or float(pending.delta) != control_seconds or int(sample.get("frame", -1)) != Engine.get_physics_frames() or int(sample.get("serial", -1)) <= _last_consumed_native_serial or sample.get("frozen", true) or int(sample.get("flight", -1)) != ball.flight_id or not is_finite(seconds) or seconds <= 0.0:
		_hold_unresolved(maxf(seconds, control_seconds), "ordered native interval identity changed"); return
	if ball.time_since_last_bounce != float(pending.bounce_age_before) or ball.receiver_path_state() != pending.receiver_before:
		_hold_unresolved(seconds, "ordered interval rule state changed"); return
	_last_consumed_native_serial = int(sample.serial)
	_delta = seconds
	var force_state: Dictionary = ball.inspect_prepared_aero()
	if not force_state.valid:
		_hold_unresolved(seconds, force_state.reason); return
	var expected_endpoint: Vector3 = _previous_ball + Vector3(force_state.before_velocity) * seconds
	var endpoint_scale: float = maxf(_previous_ball.abs().length(), ball.global_position.abs().length()) + (Vector3(force_state.before_velocity) * seconds).abs().length()
	var drift_reserve: float = minf(History.CONTACT_EPSILON, 8.0 * 1.1920928955078125e-7 * maxf(1.0, endpoint_scale))
	if ball.global_position.distance_to(expected_endpoint) > drift_reserve:
		last_evidence = {"source": "ordered_native_drift", "physical_seconds": seconds, "control_seconds": control_seconds, "residual": ball.global_position - expected_endpoint, "roundoff_bound": drift_reserve}
		_hold_unresolved(seconds, "unowned ordered native drift"); return
	if not _seal_contact_intents(pending, seconds):
		_hold_unresolved(seconds, "incomplete final actor publication"); return
	_ordered_live = true
	var endpoint: Vector3 = ball.global_position
	var first_body: Dictionary = {}
	var scene: Dictionary = completed_scene_boundary(ball._prepared_aero.get("before_velocity", ball.linear_velocity))
	# Clear paths do not rewind/recompute the existing force token.
	if _manifold.is_empty() and not scene.get("hit", false):
		var clear: Dictionary = _query_range(_previous_ball, endpoint, 0.0, 1.0, ball.flight_id)
		if clear.get("ambiguous", false):
			last_evidence = clear; _hold_unresolved(seconds, "ordered body query budget"); return
		if not clear.get("hit", false):
			if not ball.finish_clear_live_interval(pending, seconds): _hold_unresolved(seconds, "clear interval ticket changed"); return
			_update_separation()
			return
		first_body = clear
	var held: Dictionary = ball.take_prepared_aero()
	if held.get("blocked", false) or not held.get("taken", false):
		_hold_unresolved(seconds, str(held.get("reason", "ordered force token missing"))); return
	var expected: Vector3 = _previous_ball + ball.linear_velocity * seconds
	var scale: float = maxf(_previous_ball.abs().length(), endpoint.abs().length()) + (ball.linear_velocity * seconds).abs().length()
	var reserve: float = minf(History.CONTACT_EPSILON, 8.0 * 1.1920928955078125e-7 * maxf(1.0, scale))
	last_evidence = {"source": "ordered_native_interval", "physical_seconds": seconds, "control_seconds": control_seconds,
		"native_serial": sample.serial, "drift_residual": endpoint - expected, "roundoff_bound": reserve}
	if endpoint.distance_to(expected) > reserve:
		_hold_unresolved(seconds, "unowned ordered native drift"); return
	var epoch: int = _interval_reset_epoch
	ball.global_position = _previous_ball
	_deferred_age_fraction = 0.0; _deferred_age_delta = seconds; _passive_age_waiting_floor = false
	if not _manifold.is_empty():
		var fresh: Dictionary = _face_for_contact({"actor_id": _evidence_actor(_manifold), "mesh_id": _manifold.mesh_id, "triangle_offset": _manifold.source, "normal": _manifold.normal})
		if fresh.is_empty(): _hold_unresolved(seconds, "maintained topology changed"); return
		_manifold.face = fresh
	var incoming: int = ball.flight_id
	if not first_body.is_empty():
		ball.global_position = first_body.point
		_advance_deferred_bounce_age(float(first_body.fraction))
		ball.observe_receiver_position(ball.global_position)
		if first_body.get("kind", "body") not in ["legal_hand", "legal_paddle"]:
			_fault(first_body)
		else:
			var resolution: Dictionary = _resolve_hand(first_body, seconds)
			if epoch != _interval_reset_epoch: return
			if resolution.get("unresolved", false): _hold_unresolved(seconds * (1.0 - float(first_body.fraction)), resolution.reason)
			elif not resolution.get("stop", false): _continue_motion(float(first_body.fraction), seconds, incoming)
	else:
		_continue_motion(0.0, seconds, incoming)
	_deferred_age_fraction = -1.0
	if epoch != _interval_reset_epoch: return
	if unresolved_continuation.is_empty(): ball.reapply_prepared_aero(held)
	_update_separation()

# The paddle hand decides whether the planned shot is played. On fast two-handed
# backhands the support wrist bends past its budget; the contact happens and looks the
# same either way, but refusing the plan let the ball deflect off the paddle into the
# net (bench: 38 of 43 unplanned returns of fast balls were netted).
func _paddle_arm_certified(actor, report: Dictionary) -> bool:
	var arms: Array = report.get("arms", [])
	var pose: PostureDefinition = actor.posture.transition_pose_blend if actor.posture != null else null
	if arms.size() < 2 or pose == null: return bool(report.get("valid", false))
	return bool(arms[1 if pose.paddle_hand == 1 else 0].get("valid", false))

func validates_settlement(actor, certificate: Dictionary) -> bool:
	return not _settlement_scope.is_empty() and _settlement_scope == certificate and int(certificate.get("epoch", -1)) == _interval_reset_epoch and int(certificate.get("frame", -1)) == Engine.get_physics_frames() and int(certificate.get("actor_id", -1)) == ActorIdentity.actor_id(actor) and int(certificate.get("instance", -1)) == actor.get_instance_id() and int(certificate.get("flight", -1)) == game.ball.flight_id

func _contact_callback_boundary(authority_epoch: int, ball_epoch: int, event_current: bool) -> Dictionary:
	if authority_epoch != _interval_reset_epoch: return {"stop": true, "reset": true}
	if ball_epoch != game.ball.contact_callback_epoch():
		# An explicit Ball-only reset/feed also invalidates this old force claim.
		reset()
		return {"stop": true, "reset": true}
	if not event_current: return {"unresolved": true, "reason": "contact callback identity changed"}
	return {}

func _settle_intended_paddle(actor, evidence: Dictionary, seconds: float, event_permission: Dictionary) -> Dictionary:
	var id: int = ActorIdentity.actor_id(actor)
	var entry: Dictionary = _intents.eligible(id, actor.get_instance_id(), _intent_interval, int(_stroke_state(actor).serial))
	if entry.is_empty(): return {}
	var controller = _controller_for_intent(actor, str(entry.intent.get("kind", "")))
	if controller == null or not _event_permission_valid(actor, entry, event_permission): return {}
	var previous: Dictionary = _snapshots.get(id, _current_snapshot(actor))
	if not _paddle_arm_certified(actor, previous.get("endpoint_anatomy", {})) or not _paddle_arm_certified(actor, _frame_current[id].get("endpoint_anatomy", {})):
		last_evidence["intended_decline"] = "uncertified_published_endpoint_anatomy"
		return {}
	var actual_frame: Transform3D = History._linear_frame(previous.paddle, _frame_current[id].paddle, float(evidence.fraction))
	if absf(actual_frame.basis.determinant()) < 1e-6: return {"unresolved": true, "reason": "collapsed intended paddle frame"}
	entry = _intents.claim(id, actor.get_instance_id(), _intent_interval, int(_stroke_state(actor).serial))
	if entry.is_empty(): return {}
	_settlement_serial += 1
	_settlement_scope = {"serial": _settlement_serial, "epoch": _interval_reset_epoch, "frame": Engine.get_physics_frames(),
		"actor_id": id, "instance": actor.get_instance_id(), "flight": game.ball.flight_id, "physical_seconds": seconds,
		"control_seconds": _control_delta, "paddle": actual_frame, "evidence": evidence.duplicate(true),
		"intent_payload": entry.intent.duplicate(true), "event_permission": event_permission.duplicate(true)}
	var before_versions: Dictionary = {}
	for other in _frame_current: before_versions[other] = _snapshot_version(_frame_current[other])
	var epoch: int = _interval_reset_epoch
	var ball_epoch: int = game.ball.contact_callback_epoch()
	var samples_before: int = game.shot_physics.accuracy.samples
	var stamina_before: float = actor.stamina.value
	var event_context: Dictionary = game.team_coordination._public_context().duplicate(true) if event_permission.has("advisory_context") else {}
	var result: Dictionary = controller.settle_contact_intent(entry.intent, _settlement_scope.duplicate(true))
	_settlement_scope.clear()
	var boundary: Dictionary = _contact_callback_boundary(epoch, ball_epoch, not result.get("interrupted", false))
	if boundary.get("reset", false): return {"accepted": true, "reset": true}
	if not boundary.is_empty(): return boundary
	_intents.finish_claim(int(entry.token), int(entry.generation))
	for other in _players():
		if before_versions[ActorIdentity.actor_id(other)] != _snapshot_version(Surface.snapshot(other, true)):
			return {"unresolved": true, "reason": "intended settlement changed published geometry"}
	settlement_receipts.append({"frame": Engine.get_physics_frames(), "actor_id": id, "fraction": evidence.fraction,
		"incoming_flight": entry.interval.flight, "outgoing_flight": game.ball.flight_id, "accepted": result.get("accepted", false),
		"physical_seconds": seconds, "control_seconds": _control_delta, "surface": evidence.surface, "normal": evidence.normal,
		"execution_samples": game.shot_physics.accuracy.samples - samples_before, "intended_stamina": stamina_before - actor.stamina.value,
		"event_permission": event_permission.duplicate(true), "event_context": event_context,
		"impact_position": game.ball.global_position, "launch_velocity": game.ball.linear_velocity, "launch_omega": game.ball.angular_velocity,
		"fallback": last_evidence.get("intended_fallback", {}).duplicate(true)})
	if settlement_receipts.size() > 256: settlement_receipts.pop_front()
	return result

static func _note_point(point: Vector3) -> Array:
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01), snappedf(point.z, 0.01)]

func intended_velocity_leaves_surface(actor, certificate: Dictionary, velocity: Vector3, stage: String) -> bool:
	if not validates_settlement(actor, certificate): return false
	var evidence: Dictionary = certificate.evidence
	var seconds: float = certificate.physical_seconds
	var normal: Vector3 = evidence.normal
	var surface_velocity: Vector3 = Vector3(evidence.surface_displacement) / seconds
	var feasible: bool = velocity.is_finite() and normal.is_finite() and surface_velocity.is_finite() and normal.length_squared() > .5 and (velocity - surface_velocity).dot(normal) >= 0.0
	if not feasible:
		# Bench evidence for tools/shot_report.py: the planned shot is dropped here
		# and the ball deflects off the paddle.
		var pose: PostureDefinition = actor.posture.transition_pose_blend if actor.posture != null else null
		PerfMonitor.note("shot_dropped", {"actor": ActorIdentity.actor_id(actor), "stage": stage, "posture": pose.posture_id if pose != null else -1,
			"normal": [snappedf(normal.x, 0.01), snappedf(normal.y, 0.01), snappedf(normal.z, 0.01)],
			"launch_along_normal": snappedf(velocity.dot(normal), 0.01), "surface_along_normal": snappedf(surface_velocity.dot(normal), 0.01),
			"launch": [snappedf(velocity.x, 0.1), snappedf(velocity.y, 0.1), snappedf(velocity.z, 0.1)],
			"ball": [snappedf(game.ball.global_position.x, 0.01), snappedf(game.ball.global_position.y, 0.01), snappedf(game.ball.global_position.z, 0.01)],
			"head": _note_point(PaddleReach.head_world(actor)), "blade_axis": _note_point(actor.paddle_node.global_basis.y.normalized()), "face_axis": _note_point(actor.paddle_node.global_basis.z.normalized()), "planned": _note_point(actor.ai_brain.ai_predicted_contact_position) if actor.is_ai and actor.ai_brain != null else [], "planned_in": snappedf(actor.ai_brain.ai_selected_contact_time, 0.01) if actor.is_ai and actor.ai_brain != null else -1.0,
			"root": [snappedf(actor.global_position.x, 0.01), snappedf(actor.global_position.z, 0.01)], "incoming": [snappedf(game.ball.linear_velocity.x, 0.1), snappedf(game.ball.linear_velocity.y, 0.1), snappedf(game.ball.linear_velocity.z, 0.1)]})
		last_evidence["intended_fallback"] = {"actor_id": ActorIdentity.actor_id(actor), "fraction": evidence.fraction,
			"stage": stage, "velocity": velocity, "normal": normal, "surface_velocity": surface_velocity,
			"relative_normal_velocity": (velocity - surface_velocity).dot(normal)}
	return feasible

func _prepare_event_intent(actor, evidence: Dictionary) -> Dictionary:
	var id: int = ActorIdentity.actor_id(actor)
	var entry: Dictionary = _intents.eligible(id, actor.get_instance_id(), _intent_interval, int(_stroke_state(actor).serial))
	if entry.is_empty(): return {}
	var controller = _controller_for_intent(actor, str(entry.intent.get("kind", "")))
	if controller == null: return {}
	var first_floor: Dictionary = _first_floor_permission(actor, entry, float(evidence.fraction))
	_preparing_event_intent = {"actor_id": id, "entry": entry.duplicate(true), "fraction": evidence.fraction, "first_floor": first_floor.duplicate(true)}
	var current: bool = controller.contact_intent_is_current(entry.intent)
	_preparing_event_intent.clear()
	if not current: return {}
	var receipt: Dictionary = {"actor_id": id, "instance": actor.get_instance_id(), "epoch": _interval_reset_epoch,
		"frame": Engine.get_physics_frames(), "flight": game.ball.flight_id, "token": entry.token,
		"generation": entry.generation, "stroke": entry.stroke_serial, "endpoint_version": entry.endpoint_version.duplicate(),
		"fraction": evidence.fraction}
	if not first_floor.is_empty(): receipt["first_floor"] = first_floor.duplicate(true)
	if entry.intent.kind == "ai" and game.team_coordination != null:
		receipt["advisory_generation"] = game.team_coordination.policy.generation
		receipt["advisory_context"] = game.team_coordination._public_context().duplicate(true)
		receipt["first_return_before"] = int(game.doubles_state.active_rally.get("first_return_actor", -999)) if game.doubles_state != null else -999
	return receipt

func _event_permission_valid(actor, entry: Dictionary, receipt: Dictionary) -> bool:
	if receipt.is_empty() or entry.is_empty(): return false
	if int(receipt.actor_id) != ActorIdentity.actor_id(actor) or int(receipt.instance) != actor.get_instance_id() or int(receipt.epoch) != _interval_reset_epoch or int(receipt.frame) != Engine.get_physics_frames() or int(receipt.flight) != game.ball.flight_id: return false
	if int(receipt.token) != int(entry.token) or int(receipt.generation) != int(entry.generation) or int(receipt.stroke) != int(entry.stroke_serial) or receipt.endpoint_version != entry.endpoint_version: return false
	if receipt.has("first_floor"):
		var sealed: Dictionary = _intents._offers.get(ActorIdentity.actor_id(actor), {})
		var expected_floor: Dictionary = _first_floor_permission(actor, sealed, float(receipt.fraction))
		if expected_floor.is_empty() or receipt.first_floor != expected_floor: return false
	if receipt.has("advisory_context"):
		if game.team_coordination == null or game.team_coordination.policy.generation != int(receipt.advisory_generation): return false
		var current: Dictionary = game.team_coordination._public_context()
		var expected: Dictionary = receipt.advisory_context.duplicate(true)
		if current != expected:
			if int(expected.get("required_receiver", -1)) != ActorIdentity.actor_id(actor) or int(receipt.first_return_before) != -1 or game.doubles_state == null: return false
			var rally: Dictionary = game.doubles_state.active_rally
			if int(rally.get("first_return_actor", -999)) != ActorIdentity.actor_id(actor) or int(rally.get("token", -999)) != int(expected.get("service_token", -1)): return false
			expected.required_receiver = -1
			if current != expected: return false
	return true

func validates_intent_settlement(actor, intent: Dictionary, certificate: Dictionary) -> bool:
	if not validates_settlement(actor, certificate) or intent != certificate.get("intent_payload", {}): return false
	var receipt: Dictionary = certificate.get("event_permission", {})
	var entry: Dictionary = {"token": receipt.get("token", -1), "generation": receipt.get("generation", -1),
		"stroke_serial": int(_stroke_state(actor).serial), "endpoint_version": _snapshot_version(_frame_current.get(ActorIdentity.actor_id(actor), {}))}
	return _event_permission_valid(actor, entry, receipt)

# Only an actual ordered floor may explain the one sealed count transition.
func _begin_owned_first_floor(event: Dictionary) -> Dictionary:
	if not _ordered_live: return {}
	_ordered_floor_events += 1
	var ball = game.ball
	if _ordered_floor_events != 1 or _ordered_initial_bounces != 0 or ball.bounces_since_last_hit != 0 or _intent_interval.is_empty(): return {}
	if int(_intent_interval.frame) != Engine.get_physics_frames() or int(_intent_interval.reset_epoch) != _interval_reset_epoch or int(_intent_interval.flight) != ball.flight_id or int(_intent_interval.native_serial) != _last_consumed_native_serial: return {}
	if not _intents._sealed or not _intents.matches_interval(_intent_interval) or _deferred_age_fraction < 0.0 or _deferred_age_fraction > 1.0: return {}
	return {"interval": _intent_interval.duplicate(true), "fraction": _deferred_age_fraction, "bounce_count_before": ball.bounce_count,
		"last_actor": ball.get_last_hit_actor_id(), "last_team": ball.get_last_hit_team_id(), "point": event.point,
		"outgoing": event.outgoing, "omega_after": event.omega_after}

func _finish_owned_first_floor(candidate: Dictionary, event: Dictionary) -> void:
	if candidate.is_empty(): return
	var ball = game.ball
	var interval: Dictionary = candidate.interval
	# Explicit reset or ordinary finalized point owns its normal abort boundary.
	if int(interval.reset_epoch) != _interval_reset_epoch or not ball.is_in_play: return
	var remaining: float = float(interval.seconds) * (1.0 - float(candidate.fraction))
	if not _ordered_live or _ordered_floor_events != 1 or interval != _intent_interval or int(interval.frame) != Engine.get_physics_frames() or int(interval.flight) != ball.flight_id or int(interval.native_serial) != _last_consumed_native_serial:
		_hold_unresolved(remaining, "ordered floor callback changed interval identity"); return
	if ball.bounces_since_last_hit != 1 or ball.bounce_count != int(candidate.bounce_count_before) + 1 or ball.get_last_hit_actor_id() != int(candidate.last_actor) or ball.get_last_hit_team_id() != int(candidate.last_team) or ball.global_position != Vector3(event.point) or ball.linear_velocity != Vector3(event.outgoing) or ball.angular_velocity != Vector3(event.omega_after):
		_hold_unresolved(remaining, "ordered floor callback changed physical transition"); return
	for actor in _players():
		var id: int = ActorIdentity.actor_id(actor)
		if not _frame_current.has(id) or _snapshot_version(Surface.snapshot(actor, true)) != _snapshot_version(_frame_current[id]):
			_hold_unresolved(remaining, "ordered floor callback changed published endpoint"); return
	_ordered_first_floor = candidate.duplicate(true)
	last_evidence["owned_first_floor"] = _ordered_first_floor.duplicate(true)

func _first_floor_permission(actor, entry: Dictionary, fraction: float) -> Dictionary:
	if not _ordered_live or _ordered_floor_events != 1 or _ordered_first_floor.is_empty() or entry.is_empty() or not unresolved_continuation.is_empty(): return {}
	var ball = game.ball
	var interval: Dictionary = _ordered_first_floor.interval
	var id: int = ActorIdentity.actor_id(actor)
	if not ball.is_in_play or ball.bounces_since_last_hit != 1 or ball.flight_id != int(interval.flight) or ball.get_last_hit_team_id() == ActorIdentity.team_id(actor): return {}
	if interval != _intent_interval or entry.interval != interval or int(interval.frame) != Engine.get_physics_frames() or int(interval.reset_epoch) != _interval_reset_epoch or int(interval.native_serial) != _last_consumed_native_serial: return {}
	if ActorIdentity.find_actor(game, id) != actor or int(entry.actor.actor_id) != id or int(entry.actor.instance_id) != actor.get_instance_id() or int(entry.stroke_serial) != int(_stroke_state(actor).serial): return {}
	if not _intents._sealed or not _intents.matches_interval(interval) or not _frame_current.has(id) or entry.endpoint_version != _snapshot_version(_frame_current[id]): return {}
	if not is_finite(fraction) or fraction < float(_ordered_first_floor.fraction) or fraction > 1.0: return {}
	var intent: Dictionary = entry.intent
	if intent.get("kind", "") != "ai" or int(intent.get("deadline_flight", -1)) != ball.flight_id or float(intent.get("deadline", -1.0)) < 0.0: return {}
	var floor_control_time: float = float(intent.observation_time) - float(interval.control_seconds) * (1.0 - float(_ordered_first_floor.fraction))
	if float(intent.deadline) < floor_control_time: return {}
	return {"floor": _ordered_first_floor.duplicate(true), "actor_id": id, "instance": actor.get_instance_id(),
		"token": entry.token, "generation": entry.generation, "stroke": entry.stroke_serial,
		"endpoint_version": entry.endpoint_version.duplicate(), "floor_control_time": floor_control_time}

func validates_owned_first_floor_intent(actor, intent: Dictionary, certificate: Dictionary = {}) -> bool:
	var id: int = ActorIdentity.actor_id(actor)
	var entry: Dictionary
	var proof: Dictionary
	var fraction: float
	if certificate.is_empty():
		if _preparing_event_intent.is_empty() or int(_preparing_event_intent.actor_id) != id: return false
		entry = _intents.eligible(id, actor.get_instance_id(), _intent_interval, int(_stroke_state(actor).serial))
		if entry.is_empty() or entry != _preparing_event_intent.entry: return false
		proof = _preparing_event_intent.first_floor
		fraction = float(_preparing_event_intent.fraction)
	else:
		if not validates_settlement(actor, certificate): return false
		entry = _intents._offers.get(id, {})
		proof = certificate.get("event_permission", {}).get("first_floor", {})
		fraction = float(certificate.evidence.fraction)
	if entry.is_empty() or entry.intent != intent or proof.is_empty(): return false
	return proof == _first_floor_permission(actor, entry, fraction)
