extends RefCounted
const BodyTurn = preload("res://scripts/rally_body_turn.gd")
const JointPreview = preload("res://scripts/live_joint_preparation_path.gd")
const PlannedGrip = preload("res://scripts/held_preparation_reach.gd")
const MotionContext = preload("res://scripts/rally_motion_context.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")

const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Colors = preload("res://scripts/posture_colors.gd")
const ReadyMotion = preload("res://scripts/incoming_ready_motion.gd")
const DriveMotion = preload("res://scripts/drive_serve_motion.gd")
const ReadyTracking = preload("res://scripts/ready_ball_tracking.gd")
const FiniteContact = preload("res://scripts/finite_paddle_contact.gd")
const BallModel = preload("res://scripts/ball.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const ContactGeometry = preload("res://scripts/paddle_clearance.gd")
const Footwork = preload("res://scripts/charged_footwork.gd")
const HeldMotion = preload("res://scripts/held_hit_motion.gd")
const Superblocks = preload("res://scripts/preparation_superblocks.gd")
var footwork
const HIT_DISTANCE: float = Planner.IMPACT_DISTANCE
var player
var posture
var contact: Dictionary = {}


var anticipated_contact: Dictionary = {}
var superblock_hint: Dictionary = {}
# Where this ball can be smashed from (Footwork.select_smash_spot), refreshed at
# 10 Hz with the anticipation. Drives the court marker and the SMASH button label.
var smash_spot: Dictionary = {}
var _preparation_hold_suppressed: = false
var _superblock_clock: = 0.0
var _superblock_root: = Vector3.INF
var _superblock_held_last: = false
var anticipation_path: = PackedVector3Array()
var prediction_revision: = 0
var prediction_flight_id: = -1
var _prediction_clock: = 0.0
var visual_pose: PostureDefinition
var charge_ratio: float = 0.0
var phase: int = -1
var stroke_serial: int = 0
var elapsed: float = 0.0
var strike_time: float = 0.12
var swing_def: PostureDefinition
var swing_flight_id: int = -1
var motion_context: Dictionary = {}
var preparation_motion_context: Dictionary = {}
var queued_movement_allowed: = false
var hit: bool = false
var _flight_id: int = -1
# Perf: contact planning (Planner.select, with its heavy select_extended fallback)
# ran every physics tick while a ball was incoming, up to ~170 ms in one frame.
# Re-plan at ~15 Hz while the ball is far, and every tick in the final window
# (at a 30 Hz physics tick this re-plans every other tick).
const PLAN_INTERVAL_SECONDS := 0.066
const PLAN_EVERY_TICK_TIME := 0.25
var _plan_tick: int = -1000
var _plan_flight: int = -1
var _swing_is_volley: bool = false
var _released_joint_path := false


var _distant_load_active: = false
var _charge_target_pose: PostureDefinition
var held_hit_motion = HeldMotion.new()
var held_hit_seconds: float = 0.0
var _charge_control_clock: bool = false
var _charge_cancel_recovering: bool = false
var _charge_recovery_seconds: float = 0.0
var _strike_start_pose: PostureDefinition
var _finish_start_pose: PostureDefinition
var _swing_spin_mode: int = 0
var _swing_near_kitchen: bool = false
var _swing_shot_intent: String = "AUTO"
var _swing_shot_type: String = "GROUNDSTROKE"
var _swing_arc: float = 0.0
var _swing_aim_target: Vector3 = Vector3.INF
var _queued_bounces: int = 0
var _bounce_plan_grace: float = 0.0
var _anticipates_bounce: bool = false
var _floor_grace_used: bool = false
var _sweep_valid: bool = false
var _previous_ball: = Vector3.ZERO
var _previous_paddle_transform: = Transform3D.IDENTITY

var last_contact_evidence: Dictionary = {}
var _previous_pose: PostureDefinition
var _previous_bounces: int = 0
var _previous_flight_id: int = -1
var swept_hits: int = 0

func _init(owner, module) -> void :
	player = owner
	posture = module
	footwork = Footwork.new(owner, self)

func update(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_update(delta)
	PerfMonitor.record("human.update", Time.get_ticks_usec() - _pt)

func _perf_update(delta: float) -> void:
	if "special_reach_driver" in player and player.special_reach_driver != null and player.special_reach_driver.owns_presentation(): return
	if not Input.is_action_pressed("ui_accept"): _preparation_hold_suppressed = false
	var ball = player._get_ball_ref()
	if ball == null: return
	if ball.flight_id != _flight_id:
		_flight_id = ball.flight_id
		_distant_load_active = false
		contact = {}
		anticipated_contact = {}
		smash_spot = {}
		superblock_hint = {}
		_superblock_clock = 0.0
		anticipation_path.clear()
		_prediction_clock = 0.0
		posture._blue_latched = false
		posture._scored_this_ball = false
		if ball.is_in_play and ball.last_hit_by != player.player_num:




			if phase >= 2 and hit:
				var previous_visual: PostureDefinition = visual_pose


				cancel(false)
				visual_pose = previous_visual
				posture.transition_pose_blend = previous_visual
	var previous_contact_pose: PostureDefinition = contact.get("def", visual_pose)
	var old_id: int = contact.get("posture", -1)
	if Planner.should_track(player, ball):
		var flight: Dictionary = player.debug_visual._last_flight if player.debug_visual else {}
		if flight.is_empty(): flight = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity)
		var now: int = Engine.get_physics_frames()
		var near_contact: bool = not contact.is_empty() and float(contact.time) <= PLAN_EVERY_TICK_TIME
		if near_contact or phase >= 1 or _plan_flight != ball.flight_id or float(now - _plan_tick) / float(Engine.physics_ticks_per_second) >= PLAN_INTERVAL_SECONDS:
			_plan_tick = now; _plan_flight = ball.flight_id
			contact = Planner.select(player, ball, flight, old_id)
			if not contact.is_empty():
				if phase < 1:
					contact.def = _fit_planned_contact_grip(contact, ball, previous_contact_pose)
				elif swing_def != null and contact.posture == swing_def.posture_id:
					# The real released stroke owns its grip. A refreshed trajectory
					# can move the contact point, never regrip at the impact frame.
					contact.def.main_grip_rotation_deg = swing_def.main_grip_rotation_deg
		elif not contact.is_empty():
			contact.time = maxf(0.0, float(contact.time) - delta)   # keep the reused plan's clock honest
		_update_superblocks(delta, ball, flight)
		_update_anticipation(delta, ball, flight)
	else:
		_distant_load_active = false
		contact = {}
		anticipated_contact = {}
		smash_spot = {}
		superblock_hint = {}
		_superblock_clock = 0.0
		anticipation_path.clear()
		if footwork.active and phase <= 0:
			if phase == 0: cancel()
			else: footwork.cancel("flight no longer incoming")
	var preparation: Dictionary = preparation_contact()
	posture._ball_incoming = not preparation.is_empty()
	posture._committed_incoming_posture = preparation.get("posture", -1)
	if phase >= 0:
		var callback_epoch: int = ball.contact_callback_epoch()
		_advance_swing(delta, ball)
		if callback_epoch != ball.contact_callback_epoch(): return
	elif _charge_cancel_recovering:
		var preceding_recovery: PostureDefinition = visual_pose
		var ready: PostureDefinition = _ready_pose(delta)
		visual_pose = ReadyMotion.blend_pose(ReadyTracking.untracked(visual_pose), ready, delta, ReadyMotion.RECOVER_HALFLIFE)
		visual_pose = player._ready_tracking.apply(visual_pose, player, ball.global_position, delta)
		if _released_joint_path: visual_pose = JointPreview.sample(player, visual_pose, preceding_recovery, delta)
		_charge_recovery_seconds += maxf(delta, 0.0)
		if _charge_recovery_seconds >= 0.6 and not _preparation_hold_suppressed and not ReadyMotion.grip_transition_active(visual_pose): _charge_cancel_recovering = false
		_apply_visual()
	elif not preparation.is_empty():
		var def: PostureDefinition = preparation.def
		held_hit_motion.prewarm(def)
		if player.hitting.charge_visual_active:
			_update_charge_pose(delta)
		else:
			var ready: PostureDefinition = _ready_pose(delta)
			var prepared: PostureDefinition = BodyTurn.sample(DriveMotion.drive_definition(def, 0.0, _contact_is_volley(ball), _visual_spin_mode(), _near_kitchen_context(), _visual_shot_intent()))
			var target: PostureDefinition = ReadyMotion.prepare(prepared, ready, preparation.time, _contact_is_volley(ball), _near_kitchen_context())
			if float(preparation.time) > ReadyMotion.PREP_START_TIME:
				var early: PostureDefinition = BodyTurn.sample(DriveMotion.held_drive_pose(def, 0.18, _contact_is_volley(ball), _visual_spin_mode(), _near_kitchen_context(), _visual_shot_intent()))
				target = Path.blend_pose(early, ready, 0.7)
				if ReadyMotion.GripTransition.supports_both_joined(ready, early): target = early
			visual_pose = ReadyMotion.blend_pose(ReadyTracking.untracked(visual_pose) if visual_pose != null else ready, target, delta)
			var tracking_weight: float = 1.0 - smoothstep(ReadyMotion.PREP_START_TIME, ReadyMotion.PREP_FULL_TIME, maxf(float(preparation.time), 0.0))
			visual_pose = player._ready_tracking.apply(visual_pose, player, ball.global_position, delta, tracking_weight)
		visual_pose = footwork.apply_stance(visual_pose)
		posture.force_posture_update(visual_pose)
		posture.transition_pose_blend = visual_pose
	else:
		if not player.hitting.is_in_follow_through and not player.hitting.serving_visual_active:
			var ready: PostureDefinition = _ready_pose(delta)
			visual_pose = ReadyMotion.blend_pose(ReadyTracking.untracked(visual_pose), ready, delta, ReadyMotion.RECOVER_HALFLIFE)
			visual_pose = player._ready_tracking.apply(visual_pose, player, ball.global_position, delta)
			_apply_visual()
		else:
			visual_pose = null
	_update_indicators(ball)
	_remember_sweep(ball)

func preparation_contact() -> Dictionary:
	var ball = player._get_ball_ref()
	if ball == null or ball.flight_id != _flight_id or phase >= 2 or ball.bounces_since_last_hit >= 2 or not Planner.should_track(player, ball): return {}
	if not contact.is_empty(): return contact
	if phase < 0 and Input.is_action_pressed("ui_accept") and not _preparation_hold_suppressed and not superblock_hint.is_empty(): return superblock_hint
	if footwork.active and not footwork.plan.is_empty(): return footwork.plan
	return anticipated_contact

func release_timing_state() -> Dictionary:


	var preparation: Dictionary = preparation_contact()
	var ball = player._get_ball_ref()
	var reachable: bool = not preparation.is_empty() and not contact.is_empty() and ball != null
	if reachable:
		var total_bounces: int = ball.bounces_since_last_hit + int(contact.get("bounces", 0))


		reachable = total_bounces < 2 and (Planner.wall_mode(ball) and ball.wall_return_ready or total_bounces > 0 or ball.both_bounces_complete and player._nvz_state.established_outside)
	var moving: bool = Vector2(player.current_velocity.x, player.current_velocity.z).length() > 0.35
	var stable: bool = not moving and not player.is_jumping and footwork.ready_to_strike()
	var ready: bool = phase < 0 and player.hitting.charge_visual_active and reachable and stable
	var release_lead: float = float(preparation.def.ft_duration_strike) + 0.06 if not preparation.is_empty() else 0.0
	if ready: ready = float(contact.time) <= release_lead
	return {"flight_id": ball.flight_id if ball != null else -1, 
		"time": float(preparation.get("time", -1.0)), 
		"time_until_release": maxf(0.0, float(preparation.time) - release_lead) if not preparation.is_empty() else -1.0, 
		"release_lead": release_lead, "current_reachable": reachable, 
		"release_ready": ready, "preparation_only": not preparation.is_empty() and not reachable, 
		"queued": phase == 0}

func _update_superblocks(delta: float, ball, flight: Dictionary) -> void :
	var held: bool = Input.is_action_pressed("ui_accept") and player.hitting.charge_visual_active and phase < 0 and not _preparation_hold_suppressed and footwork._eligible(ball)
	if not held:
		superblock_hint = {}
		_superblock_clock = 0.0
		_superblock_held_last = false
		return
	_superblock_clock -= delta

	var urgent: bool = not superblock_hint.is_empty() and float(superblock_hint.time) < Superblocks.URGENT_TIME
	if _superblock_held_last and _superblock_clock > 0.0 and not urgent and player.global_position.distance_to(_superblock_root) < 0.025:
		if not superblock_hint.is_empty(): superblock_hint.time = maxf(0.0, float(superblock_hint.time) - delta)
		return
	_superblock_held_last = true
	_superblock_clock = 0.1
	_superblock_root = player.global_position
	superblock_hint = Superblocks.select(player, ball, flight, true, superblock_hint)

func _update_anticipation(delta: float, ball, flight: Dictionary) -> void :
	if player.erne_action != null and player.erne_action.active:
		anticipated_contact = player.erne_action.contact_opportunity(ball)
		return
	_prediction_clock -= delta
	if not anticipated_contact.is_empty(): anticipated_contact.time = maxf(0.0, float(anticipated_contact.time) - delta)
	if _prediction_clock > 0.0: return
	_prediction_clock = 0.1
	prediction_revision += 1
	prediction_flight_id = ball.flight_id
	var previous_id: int = anticipated_contact.get("posture", -1)
	smash_spot = Footwork.select_smash_spot(player, ball, flight, smash_spot) if phase < 1 and footwork._eligible(ball) else {}
	if footwork.active: footwork.refresh_prediction(ball, flight)
	if footwork.active:
		anticipated_contact = footwork.plan.duplicate()


	elif footwork._eligible(ball) and (contact.is_empty() or phase == 0):
		anticipated_contact = Footwork.select_plan(player, ball, flight)
		if anticipated_contact.is_empty() and (player.hitting.charge_visual_active or phase == 0):
			anticipated_contact = Footwork.select_preparation(player, ball, flight, previous_id)
	elif phase < 0 and not smash_spot.is_empty() and not Footwork.is_smash_contact(player, contact) and footwork._eligible(ball):
		# The ball is already in reach, but it could be smashed from a better
		# spot: offer the step under it (taken only while HIT is held).
		anticipated_contact = Footwork.select_plan(player, ball, flight, true)
	else:
		anticipated_contact = {}
	# When the footwork itself plans a smash, the guide marks that same spot.
	if bool(anticipated_contact.get("smash", false)) and phase < 1:
		smash_spot = anticipated_contact.duplicate()
		smash_spot["path"] = Footwork.path_to(flight, smash_spot)
	anticipation_path.clear()
	var preparation: Dictionary = preparation_contact()
	if preparation.is_empty(): return
	var samples: Array = flight.get("samples", [])

	for index in range(0, samples.size(), 4):
		if float(samples[index].time) >= float(preparation.time): break
		anticipation_path.append(samples[index].pos)
	anticipation_path.append(preparation.point)

func begin_held_hit() -> void:
	if phase >= 0: return
	held_hit_seconds = 0.0
	_charge_control_clock = false
	_charge_cancel_recovering = false
	_charge_recovery_seconds = 0.0
	held_hit_motion.reset(false)
	var preparation: Dictionary = preparation_contact()
	if not preparation.is_empty(): held_hit_motion.prewarm(preparation.def, Callable(), "", true)

func set_charge(ratio: float, control_delta: float = -1.0) -> void :
	if phase >= 1: return
	charge_ratio = clampf(ratio, 0, 1)
	_charge_cancel_recovering = false
	if phase < 0:
		if control_delta >= 0.0:
			_charge_control_clock = true
			held_hit_seconds = minf(held_hit_seconds + control_delta, HeldMotion.STRONG_SECONDS)
		elif not _charge_control_clock:
			# Direct simulation callers have no input clock; never count world ticks too.
			held_hit_seconds = charge_ratio * HeldMotion.STRONG_SECONDS
	player.hitting.charge_visual_active = true
	if phase < 0 and Input.is_action_pressed("ui_accept") and not _preparation_hold_suppressed and not _superblock_held_last:
		var ball = player._get_ball_ref()
		if ball != null and Planner.should_track(player, ball) and footwork._eligible(ball):
			var flight: Dictionary = player.debug_visual._last_flight if player.debug_visual else {}
			if flight.is_empty(): flight = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity)
			_update_superblocks(0.0, ball, flight)


			_prediction_clock = 0.0
			_update_anticipation(0.0, ball, flight)
	var preparation: Dictionary = preparation_contact()
	if preparation.is_empty():
		if visual_pose == null: visual_pose = _ready_pose(0.0)
		_apply_visual()
		return
	_charge_target_pose = _held_preparation_pose(preparation)
	if visual_pose == null: visual_pose = _ready_pose(0.0)
	if control_delta >= 0.0 and phase < 0:
		_update_charge_pose(control_delta, true, _charge_target_pose)
	posture.transition_pose_blend = visual_pose
	posture.force_posture_update(visual_pose)

func _update_charge_pose(delta: float, from_control_clock: bool = false, prepared_pose: PostureDefinition = null) -> void :
	# Only the control-clock call consumes a target during a live held input.
	# Sampling one on a world tick was discarded here and overwritten by the
	# next control update, including its latest moving contact/root/body state.
	if phase < 0 and _charge_control_clock and not from_control_clock: return
	var preparation: Dictionary = preparation_contact()
	if preparation.is_empty(): return
	# The input path has already sampled this exact held interval and contact.
	_charge_target_pose = BodyTurn.sample(prepared_pose if prepared_pose != null else _held_preparation_pose(preparation))
	var previous_preparation: PostureDefinition = visual_pose
	visual_pose = ReadyMotion.blend_pose(visual_pose if visual_pose != null else _ready_pose(0.0), _charge_target_pose, delta, 0.055)
	if phase < 0: visual_pose = held_hit_motion.fit_live_preparation(visual_pose, player, previous_preparation, delta)

func _held_preparation_pose(preparation: Dictionary) -> PostureDefinition:
	if phase < 0:
		return held_hit_motion.sample(preparation.def, _ready_pose(0.0), held_hit_seconds, player, bool(preparation.get("directional_only", false)))
	# Released early: existing queued preparation can meet the contact deadline;
	# visual hold duration is never an additional gate on the actual shot.



	if contact.is_empty() and float(preparation.time) > 0.45 and not _near_kitchen_context():
		_distant_load_active = true
	var visual_load: float = maxf(charge_ratio, 0.9) if _distant_load_active else charge_ratio
	if bool(preparation.get("directional_only", false)): visual_load = minf(visual_load, 0.25)
	return DriveMotion.held_drive_pose(preparation.def, visual_load, 
		_contact_is_volley(player._get_ball_ref()) and not _distant_load_active, 
		_visual_spin_mode(), _near_kitchen_context(), _visual_shot_intent(), preparation_motion_context)

## 0: no smash on this ball, 1: a smash spot is reachable (move or hold HIT),
## 2: the planned contact is a smash from where the player stands.
func smash_state() -> int:
	if phase >= 2: return 0
	var ball = player._get_ball_ref()
	if ball == null or ball.flight_id != _flight_id or not ball.is_in_play: return 0
	if Footwork.is_smash_contact(player, preparation_contact()): return 2
	return 1 if phase < 1 and not smash_spot.is_empty() else 0

func preparation_label() -> String:
	var preparation: Dictionary = preparation_contact()
	if preparation.is_empty(): return ""
	if preparation.has("label"): return str(preparation.label)
	var def: PostureDefinition = preparation.def
	if def.family == 3: return "Smash" if Footwork.is_smash_contact(player, preparation) else "Overhead"
	if def.family == 2: return "Low block" if def.height_tier <= 1 else "Block"
	var side: String = "Backhand" if def.family == 1 else "Forehand"
	if def.height_tier <= 1: return "Low " + side.to_lower()
	if _near_kitchen_context(): return side + " block"
	return side

func preparation_status_text() -> String:
	if phase >= 1: return ""
	var label: String = preparation_label()
	if label.is_empty(): return ""
	return ("Queued · " if phase == 0 else "Prepare · ") + label

func request_swing(ratio: float) -> bool:
	superblock_hint = {}
	_superblock_held_last = false
	if phase >= 0: return false
	var ball = player._get_ball_ref()
	if ball == null or ball.flight_id != _flight_id: return false
	var action_game = player.get_parent()
	_released_joint_path = false
	if action_game.selected_movement_intent == "ERNE":
		var opportunity: Dictionary = player.erne_action.choose_plan(ball)
		if not player.erne_action.begin(opportunity, ball): return false
		_released_joint_path = true
		footwork.cancel("Erne owns lateral jump", false)
		contact = {}
		anticipated_contact = opportunity
		action_game.selected_movement_intent = "AUTO"
	if contact.is_empty() and not footwork.active and not player.erne_action.active and not anticipated_contact.is_empty():
		footwork.activate_plan(anticipated_contact, player._get_ball_ref())
	var preparation: Dictionary = preparation_contact()
	if contact.is_empty() and not footwork.active and preparation.is_empty():
		cancel()
		return false
	_released_joint_path = true
	charge_ratio = clampf(ratio, 0, 1)
	_swing_near_kitchen = _near_kitchen_context()


	queued_movement_allowed = contact.is_empty() or footwork.active and not footwork.ready_to_strike() or Vector2(player.current_velocity.x, player.current_velocity.z).length() > 0.35
	phase = 0
	stroke_serial += 1
	elapsed = 0
	hit = false
	last_contact_evidence = {}
	swing_flight_id = _flight_id
	_queued_bounces = int(player._get_ball_ref().bounces_since_last_hit)
	_bounce_plan_grace = 0.0
	_anticipates_bounce = int(preparation.get("bounces", contact.get("bounces", 0))) > 0
	_floor_grace_used = false
	var game = player.get_parent()
	_swing_spin_mode = int(game.selected_spin_mode)
	_swing_shot_intent = str(game.selected_shot_intent)
	_swing_shot_type = str(game._pending_shot_type)
	_swing_arc = float(game.trajectory_arc_offset)
	_swing_aim_target = game.capture_aim_target()
	game.freeze_spin_selection(_swing_spin_mode, _swing_shot_intent)
	motion_context = {}
	preparation_motion_context = _capture_motion_context(preparation, ball)
	MotionContext.apply_feet(player, preparation_motion_context)
	player.hitting.charge_visual_active = true
	if not player.erne_action.active and _swing_shot_intent != "DROP" and player.has_method("request_contextual_jump"):
		if not footwork.active: player.request_contextual_jump(contact, charge_ratio)
	_remember_sweep(player._get_ball_ref())
	return true

func cancel(suppress_hold: bool = true) -> void :
	superblock_hint = {}
	_superblock_held_last = false
	_preparation_hold_suppressed = suppress_hold and Input.is_action_pressed("ui_accept")
	motion_context = {}
	preparation_motion_context = {}
	MotionContext.clear_feet(player)
	if player.erne_action != null and player.erne_action.active and not hit: player.erne_action.cancel("stroke cancelled")
	player.set_meta("legal_net_followthrough_flight", -1)
	player.set_meta("legal_return_over_net_flight", -1)
	_distant_load_active = false
	footwork.cancel("controller cancelled", suppress_hold or footwork.suppressed)
	var ball = player._get_ball_ref()
	var preserve_visual: bool = visual_pose != null and ball != null and ball.is_in_play and not posture.editor_preview_mode
	player.get_parent().release_aim_target()
	if player.has_method("cancel_contextual_jump"):
		player.cancel_contextual_jump()
	if phase >= 0:
		player.get_parent().clear_frozen_spin_selection()
	if phase >= 0:
		phase = -1
		player.hitting.is_in_follow_through = false
		player.hitting.charge_visual_active = false
	player.hitting.charge_visual_active = false
	_charge_cancel_recovering = preserve_visual and suppress_hold
	_charge_recovery_seconds = 0.0
	held_hit_seconds = 0.0
	_charge_control_clock = false
	held_hit_motion.reset(false)
	if not preserve_visual: visual_pose = null
	else: posture.transition_pose_blend = visual_pose
	charge_ratio = 0
	queued_movement_allowed = false
	_charge_target_pose = null
	_strike_start_pose = null
	_finish_start_pose = null
	_bounce_plan_grace = 0.0
	_sweep_valid = false

func _advance_swing(delta: float, ball) -> void :
	var preceding_pose: PostureDefinition = visual_pose
	if phase == 0:
		if not contact.is_empty() and int(contact.get("bounces", 0)) > 0:
			_anticipates_bounce = true
		if _anticipates_bounce and not _floor_grace_used and ball.global_position.y <= Flight.FLOOR_REST_Y + 0.08 and ball.linear_velocity.y < 0.0:
			_bounce_plan_grace = 0.08
			_floor_grace_used = true
		if ball.bounces_since_last_hit > _queued_bounces:
			_queued_bounces = ball.bounces_since_last_hit
			_bounce_plan_grace = 0.08
		else:
			_bounce_plan_grace = maxf(0.0, _bounce_plan_grace - delta)
		var same_flight: bool = ball.flight_id == swing_flight_id and ball.is_in_play and ball.last_hit_by != player.player_num and ball.bounces_since_last_hit < 2



		if contact.is_empty() and same_flight and (_bounce_plan_grace > 0.0 or footwork.active or not anticipated_contact.is_empty()):
			_update_charge_pose(delta)
			if _released_joint_path: visual_pose = JointPreview.sample(player, visual_pose, preceding_pose, delta)
			_apply_visual()
			return
		if contact.is_empty() or not same_flight:
			cancel()
			posture.transition_pose_blend = visual_pose
			return
		set_charge(charge_ratio)
		_update_charge_pose(delta)
		if _released_joint_path: visual_pose = JointPreview.sample(player, visual_pose, preceding_pose, delta)
		_apply_visual()
		if player.erne_action.active and not player.erne_action._taken_off: return
		if contact.time > contact.def.ft_duration_strike or not footwork.ready_to_strike(): return
		swing_def = contact.def
		_swing_is_volley = _contact_is_volley(ball)
		motion_context = _capture_motion_context(contact, ball)
		contact["motion_context"] = motion_context
		MotionContext.apply_feet(player, motion_context)
		_strike_start_pose = visual_pose
		# An immediate legal contact must reach its strike pose within the next
		# physics tick. The old25ms floor spans two60Hz ticks and loses a
		# fast ball before the finite paddle sweep can reach it.
		strike_time = maxf(minf(0.025, 1.0 / float(Engine.physics_ticks_per_second)), contact.time)
		phase = 1
		elapsed = 0.0
		player.hitting.charge_visual_active = false
		player.hitting.is_in_follow_through = true


		_advance_swing(0.0, ball)
		if phase == 1: _advance_swing(delta, ball)
		return
	elif phase == 1:
		elapsed += delta

		if not contact.is_empty() and contact.posture == swing_def.posture_id:
			swing_def = contact.def
		var factor: float = clampf(elapsed / strike_time, 0, 1)
		visual_pose = BodyTurn.sample(DriveMotion.sample_drive(swing_def, factor * 0.5, charge_ratio, _swing_is_volley, _swing_spin_mode, _swing_near_kitchen, _swing_shot_intent, motion_context))
		if _strike_start_pose:
			visual_pose = Path.blend_pose(visual_pose, _strike_start_pose, pow(1.0 - factor, 2.0))
		if _released_joint_path: visual_pose = JointPreview.sample(player, visual_pose, preceding_pose, -1.0)
		_apply_visual()
		var owner = player.get_parent().contact_authority
		if owner != null and owner.uses_two_phase_contact(player):
			_publish_two_phase_intent(ball, delta)
		else:
			# An endpoint overlap is later than its incoming swept intersection.
			# Resolve that first TOI, including earlier body contact, before any
			# aimed response. A rejected swept interval cannot retry as a static hit.
			var has_interval: bool = delta > 0.0 and _sweep_valid and _previous_pose != null and ball.flight_id == _previous_flight_id and ball.flight_id == swing_flight_id and ball.bounces_since_last_hit == _previous_bounces
			var callback_epoch: int = ball.contact_callback_epoch()
			if has_interval:
				var accepted: bool = _try_swept_contact(ball, delta)
				if callback_epoch != ball.contact_callback_epoch(): return
				hit = accepted
			elif owns_contact_window(ball) and Planner.legal_ball(player, ball) and FiniteContact.touches(player.paddle_node.global_transform, ball.global_position, ball.BALL_RADIUS):
				last_contact_evidence = {"swept": false, "fraction": 1.0}
				if _align_contact_surface(ball):
					var game = player.get_parent()
					var accepted: bool = game._apply_player_contact_hit(charge_ratio, swing_def.posture_id, _swing_spin_mode, _swing_shot_intent, _swing_aim_target)
					if callback_epoch != ball.contact_callback_epoch(): return
					hit = accepted
					if hit: game.clear_frozen_spin_selection()
			if callback_epoch != ball.contact_callback_epoch(): return
			if hit or elapsed >= strike_time + 0.1:
				player.get_parent().release_aim_target()
				_finish_start_pose = visual_pose
				phase = 2
				elapsed = 0
	elif phase == 2:
		elapsed += delta
		var factor: float = Path.release_progress(swing_def, 1, clampf(elapsed / maxf(0.01, swing_def.ft_duration_sweep), 0, 1))
		visual_pose = BodyTurn.sample(DriveMotion.sample_drive(swing_def, factor, charge_ratio, _swing_is_volley, _swing_spin_mode, _swing_near_kitchen, _swing_shot_intent, motion_context))
		if _finish_start_pose:
			visual_pose = Path.blend_pose(visual_pose, _finish_start_pose, pow(clampf((1.0 - factor) * 2.0, 0.0, 1.0), 2.0))
		if elapsed >= swing_def.ft_duration_sweep:
			phase = 3
			elapsed = 0
	elif phase == 3:
		elapsed += delta
		if elapsed >= swing_def.ft_duration_hold:
			phase = 4
			elapsed = 0
	elif phase == 4:
		elapsed += delta
		var finish: PostureDefinition = DriveMotion.sample_drive(swing_def, 1.0, charge_ratio, _swing_is_volley, _swing_spin_mode, _swing_near_kitchen, _swing_shot_intent, motion_context)
		var ready: PostureDefinition = _ready_pose(delta)
		var factor: float = clampf(elapsed / maxf(0.01, swing_def.ft_duration_settle), 0, 1)
		factor = smoothstep(0, 1, factor)
		if _released_joint_path:
			ready = JointPreview.sample(player, ready, preceding_pose, -1.0)
			visual_pose = ReadyMotion.blend_pose(visual_pose, ready, delta, ReadyMotion.RECOVER_HALFLIFE)
			visual_pose = JointPreview.sample(player, visual_pose, preceding_pose, delta)
		elif ReadyMotion.grip_transition_active(visual_pose) or ReadyMotion.GripTransition.supports_both_joined(finish, ready):
			visual_pose = ReadyMotion.blend_pose(visual_pose, ready, delta, ReadyMotion.RECOVER_HALFLIFE)
		else: visual_pose = Path.blend_pose(finish, ready, factor)
		var recovery_seated: bool = true
		if _released_joint_path:
			var presented: Transform3D = Path.world_transform(player, visual_pose)
			var target: Transform3D = Path.world_transform(player, ready)
			recovery_seated = presented.origin.distance_to(target.origin) < .001 and presented.basis.orthonormalized().get_rotation_quaternion().angle_to(target.basis.orthonormalized().get_rotation_quaternion()) < deg_to_rad(.1)
			player.set_meta("erne_recovery_gap", {"distance":presented.origin.distance_to(target.origin),"degrees":rad_to_deg(presented.basis.orthonormalized().get_rotation_quaternion().angle_to(target.basis.orthonormalized().get_rotation_quaternion())),"elapsed":elapsed})
		if elapsed >= swing_def.ft_duration_settle and not ReadyMotion.grip_transition_active(visual_pose) and (_released_joint_path or recovery_seated):
			if _released_joint_path:
				var recovery_pose: PostureDefinition = visual_pose
				cancel(false)
				visual_pose = recovery_pose
				_charge_cancel_recovering = true
				_charge_recovery_seconds = 0.0
				_apply_visual()
				return
			if visual_pose.has_meta("joined_grip_transition_finished"): ready = visual_pose


			cancel(false)



			visual_pose = ready
			posture.transition_pose_blend = ready
			posture.force_posture_update(ready)
			return
	if _released_joint_path and phase != 4: visual_pose = JointPreview.sample(player, visual_pose, preceding_pose, delta if phase >= 2 else -1.0)
	_apply_visual()

func _remember_sweep(ball) -> void :
	_sweep_valid = phase in [0, 1] and visual_pose != null and ball.flight_id == swing_flight_id
	if not _sweep_valid: return
	_previous_ball = ball.global_position
	_previous_paddle_transform = player.paddle_node.global_transform
	_previous_pose = visual_pose
	_previous_bounces = ball.bounces_since_last_hit
	_previous_flight_id = ball.flight_id

func owns_contact_window(ball) -> bool:
	return phase == 1 and not hit and elapsed >= 0.0 and elapsed <= strike_time + 0.1 and ball.flight_id == swing_flight_id

func _try_swept_contact(ball, delta: float) -> bool:
	if phase != 1 or delta <= 0.0 or not _sweep_valid or _previous_pose == null or visual_pose == null: return false
	if ball.flight_id != _previous_flight_id or ball.flight_id != swing_flight_id or ball.bounces_since_last_hit != _previous_bounces: return false
	if not Planner.legal_ball(player, ball): return false
	var start_elapsed: float = elapsed - delta
	var available: float = strike_time + 0.1 - start_elapsed
	if available < 0.0: return false
	var current_ball: Vector3 = ball.global_position
	var current_paddle: Transform3D = player.paddle_node.global_transform
	var fraction: float = FiniteContact.physical_sweep_fraction(_previous_ball, current_ball, _previous_paddle_transform, current_paddle, ball.BALL_RADIUS, minf(1.0, available / delta))
	if fraction < 0.0: return false
	var impact: Vector3 = _previous_ball.lerp(current_ball, fraction)
	var swept_transform: Transform3D = FiniteContact.interpolate_head_transform(_previous_paddle_transform, current_paddle, fraction)
	var pose: PostureDefinition = Path.blend_pose(_previous_pose, visual_pose, fraction)
	pose = preload("res://scripts/paddle_pose_encoding.gd").encode(player, pose, swept_transform)
	var transform: Transform3D = Path.world_transform(player, pose)
	if not WristReach.fits(transform, pose, Body.shoulder_world(player, pose), WristReach.link_budget(player, pose)): return false
	var saved_pose: PostureDefinition = visual_pose
	visual_pose = pose
	_apply_visual()
	ball.global_position = impact
	last_contact_evidence = {"swept": true, "fraction": fraction, 
		"paddle_from": _previous_paddle_transform, "paddle_to": current_paddle, 
		"ball_from": _previous_ball, "ball_to": current_ball, 
		"swept_paddle": swept_transform, "window_fraction": minf(1.0, available / delta)}


	var actual: Transform3D = player.paddle_node.global_transform
	var reproduced: bool = actual.origin.distance_to(swept_transform.origin) <= 0.0001 and actual.basis.x.distance_to(swept_transform.basis.x) <= 0.0001 and actual.basis.y.distance_to(swept_transform.basis.y) <= 0.0001 and actual.basis.z.distance_to(swept_transform.basis.z) <= 0.0001
	var saved_elapsed: float = elapsed
	elapsed = maxf(0.0, start_elapsed + delta * fraction)
	var aligned: bool = reproduced and _align_contact_surface(ball)
	var callback_epoch: int = ball.contact_callback_epoch()
	var accepted: bool = aligned and player.get_parent()._apply_player_contact_hit(charge_ratio, swing_def.posture_id, _swing_spin_mode, _swing_shot_intent, _swing_aim_target)
	if callback_epoch != ball.contact_callback_epoch(): return false
	elapsed = saved_elapsed
	if not accepted:
		ball.global_position = current_ball
		visual_pose = saved_pose
		_apply_visual()
		return false

	# The strike continues through the unconsumed portion of this frame.
	# Restore its actual admitted endpoint, then resolve outgoing body/net/
	# post/floor events in time order rather than aero-only advancement.
	visual_pose = saved_pose
	_apply_visual()
	var authority = player.get_parent().contact_authority
	if authority != null:
		authority.capture_remainder_endpoint()
		last_contact_evidence["remainder"] = authority.continue_paddle_remainder(player, delta, fraction)
	swept_hits += 1
	return true

func _contact_is_volley(ball) -> bool:
	var preparation: Dictionary = preparation_contact()
	return ball != null and not preparation.is_empty() and ball.bounces_since_last_hit + preparation.get("bounces", 0) == 0

func _visual_spin_mode() -> int:
	return _swing_spin_mode if phase >= 0 else int(player.get_parent().selected_spin_mode)

func _visual_shot_intent() -> String:
	return _swing_shot_intent if phase >= 0 else str(player.get_parent().selected_shot_intent)

func _near_kitchen_context() -> bool:
	return _swing_near_kitchen if phase >= 0 else absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.65

func _ready_pose(_delta: float = 1.0 / 60.0) -> PostureDefinition:
	var ready: PostureDefinition = ReadyMotion.ready_pose(PostureLibrary.instance().get_def(player.PaddlePosture.READY))
	if absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.65:
		ready = DriveMotion.kitchen_ready(ready)
	# Tracking is applied after ReadyMotion blending so its fast tip is not filtered twice.
	return ready

func _apply_visual() -> void :

	if phase < 0 and contact.is_empty() and (player.hitting.serving_visual_active or player.hitting.is_in_follow_through):
		return
	if visual_pose:
		visual_pose = footwork.apply_stance(visual_pose)
		posture.transition_pose_blend = visual_pose
		posture.force_posture_update(visual_pose)

func _update_indicators(ball) -> void :
	var preparation: Dictionary = preparation_contact()
	posture._ball_incoming = not preparation.is_empty()
	posture._committed_incoming_posture = preparation.get("posture", -1)
	if preparation.is_empty():
		posture._last_commit_stage = -1
		posture._contact_point_local = Vector3.ZERO
		posture._emit_stage_cleared()
	else:
		var distance: float = ball.global_position.distance_to(preparation.point)
		var stage: int = 2 if preparation.time < posture.TTC_BLUE else (1 if preparation.time < posture.TTC_PURPLE else 0)
		posture._last_commit_stage = stage
		posture._contact_point_local = preparation.point - player.global_position
		posture.incoming_stage_changed.emit(stage, preparation.posture, ball.global_position.distance_to(player.global_position), distance, preparation.time)
	if player.debug_visual:
		player.debug_visual.human_committed_contact_position = preparation.get("point", Vector3.ZERO)
		var marker = player.debug_visual.human_intercept_indicator
		if marker:
			marker.visible = not preparation.is_empty() and (player.debug_visual._intercept_visible or not player.debug_visual._intent_hidden)
			if not preparation.is_empty(): marker.global_position = preparation.point

func draw_ghosts() -> void :
	for id in posture.posture_ghosts:
		var ghost: Node3D = posture.posture_ghosts[id]
		var selected: bool = not contact.is_empty() and id == contact.posture
		var def: PostureDefinition = contact.def if selected else PostureLibrary.instance().get_def(id)
		if def == null: continue
		if selected and (player.hitting.charge_visual_active or phase >= 0):
			def = DriveMotion.drive_definition(def, charge_ratio, _contact_is_volley(player._get_ball_ref()), _visual_spin_mode(), _near_kitchen_context(), _visual_shot_intent())
		var transform: Transform3D = Path.world_transform(player, def)
		var head: Vector3 = transform.origin + transform.basis.y * PaddleDimensions.HEAD_CENTER_Y
		ghost.global_transform = Transform3D(transform.basis.scaled(posture.POSTURE_GHOST_SCALE), head - transform.basis.y * PaddleDimensions.HEAD_CENTER_Y * posture.POSTURE_GHOST_SCALE.y)
		ghost.visible = selected or posture._posture_ghosts_visible or (posture._charge_ghosts_visible and id in [8, 9])
		var material = posture._get_ghost_material(ghost)
		if material:
			var color: Dictionary = Colors.stage_colors(posture._last_commit_stage) if selected else Colors.proximity_color(0, false, posture._ghost_base_color)
			material.albedo_color = Color(color.albedo, color.get("alpha", color.albedo.a))
			material.emission_energy_multiplier = color.em_mult
			if selected: material.emission = color.emission
			posture._apply_ghost_material(ghost, material)
	for id in posture._posture_zone_bounds:
		posture._set_zone_visibility(posture._posture_zone_bounds[id], false)
	posture._update_ft_ghosts()

func _align_contact_surface(ball) -> bool:


	var raw: Transform3D = player.paddle_node.global_transform
	if not FiniteContact.touches(raw, ball.global_position, ball.BALL_RADIUS): return false
	last_contact_evidence["raw_paddle"] = raw
	last_contact_evidence["raw_ball"] = ball.global_position
	last_contact_evidence["raw_gap"] = ContactGeometry.distance_to_head_shape(raw.affine_inverse() * ball.global_position) - ball.BALL_RADIUS
	last_contact_evidence["elapsed"] = elapsed
	last_contact_evidence["flight"] = ball.flight_id
	last_contact_evidence["phase"] = phase
	var candidate: PostureDefinition = ContactGeometry.contact_surface_pose(player, visual_pose, ball.global_position, ball.linear_velocity, WristReach.live_shoulder(player, visual_pose))
	if candidate == null: return false
	var previous: PostureDefinition = visual_pose
	visual_pose = candidate
	_apply_visual()
	if not WristReach.fits(player.paddle_node.global_transform, candidate, WristReach.live_shoulder(player, candidate), WristReach.link_budget(player, candidate)) or not FiniteContact.touches(player.paddle_node.global_transform, ball.global_position, ball.BALL_RADIUS):
		visual_pose = previous
		_apply_visual()
		return false
	return true

func _capture_motion_context(selected: Dictionary, ball) -> Dictionary:
	if selected.is_empty() or not selected.get("def") is PostureDefinition: return {}
	var game = player.get_parent()
	return MotionContext.capture(player, ball, selected.def, selected.get("point", ball.global_position), float(selected.get("time", 0.0)), {
		"charge": charge_ratio, "spin_mode": _swing_spin_mode, "shot_intent": _swing_shot_intent,
		"shot_type": _swing_shot_type,
		"target": _swing_aim_target, "arc": _swing_arc,
		"bounces": ball.bounces_since_last_hit + int(selected.get("bounces", 0))})

func _fit_planned_contact_grip(selected: Dictionary, ball, previous: PostureDefinition) -> PostureDefinition:
	# Fit the actual contextual Contact endpoint, then carry only its seated
	# grip back into the source stroke. Wind-up and strike blend toward that
	# grip before impact; the phase-one latch below remains immutable.
	var base: PostureDefinition = selected.def
	var game = player.get_parent()
	var context: Dictionary = _capture_motion_context(selected, ball)
	if phase < 0:
		context = MotionContext.capture(player, ball, base, selected.get("point", ball.global_position), float(selected.get("time", 0.0)), {
			"charge": charge_ratio, "spin_mode": int(game.selected_spin_mode), "shot_intent": str(game.selected_shot_intent),
			"shot_type": str(game._pending_shot_type), "target": game.aim_controller.get_target() if game.aim_controller else Vector3.INF, "arc": float(game.trajectory_arc_offset),
			"bounces": ball.bounces_since_last_hit + int(selected.get("bounces", 0))})
	var endpoint: PostureDefinition = DriveMotion.sample_drive(base, .5, charge_ratio, bool(context.is_volley), int(context.spin_mode), bool(context.near_kitchen), str(context.shot_intent), context)
	endpoint = BodyTurn.sample(endpoint)
	var fitted: PostureDefinition = PlannedGrip.fit_planned_contact_grip(player, endpoint, previous)
	var result: PostureDefinition = BodyTurn.sample(base).duplicate(false)
	result.main_grip_rotation_deg = fitted.main_grip_rotation_deg
	for key in fitted.get_meta_list():
		if str(key).begins_with("planned_live_grip"): result.set_meta(key, fitted.get_meta(key))
	return result

func notify_physical_hand_contact(evidence: Dictionary) -> void:
	# The permitted paddle-holding hand is a real physical hitting surface.
	# This callback only hands the existing motion into recovery after the
	# authority already verified and applied its un-aimed normal impulse.
	if phase not in [1, 2]: return
	hit = true
	last_contact_evidence = evidence.duplicate(true)
	_finish_start_pose = visual_pose
	phase = 2
	elapsed = 0.0
	player.get_parent().release_aim_target()
	player.get_parent().clear_frozen_spin_selection()

func _publish_two_phase_intent(ball, delta: float) -> void:
	if delta <= 0.0 or not Engine.is_in_physics_frame(): return
	if phase != 1 or hit or ball.flight_id != swing_flight_id or elapsed - delta > strike_time + .1: return
	player.get_parent().contact_authority.publish_contact_intent(player, {"kind": "human", "flight": swing_flight_id,
		"stroke_serial": stroke_serial, "elapsed": elapsed, "strike_time": strike_time, "control_seconds": delta,
		"charge_ratio": charge_ratio, "spin_mode": _swing_spin_mode, "shot_intent": _swing_shot_intent,
		"target": _swing_aim_target, "motion_context": motion_context.duplicate(true)})

func contact_intent_is_current(intent: Dictionary) -> bool:
	var ball = player._get_ball_ref()
	return ball != null and ball.is_in_play and phase == 1 and not hit and int(intent.get("flight", -1)) == swing_flight_id and ball.flight_id == swing_flight_id and int(intent.get("stroke_serial", -1)) == stroke_serial and float(intent.get("elapsed", -1.0)) == elapsed

func settle_contact_intent(intent: Dictionary, certificate: Dictionary) -> Dictionary:
	if not contact_intent_is_current(intent): return {}
	var game = player.get_parent()
	if not game.contact_authority.validates_settlement(player, certificate): return {}
	var callback_epoch: int = game.ball.contact_callback_epoch()
	var accepted: bool = game.settle_human_contact_intent(player, intent, certificate)
	if callback_epoch != game.ball.contact_callback_epoch() or int(certificate.epoch) != game.contact_authority._interval_reset_epoch: return {"accepted": true, "interrupted": true}
	if not accepted and game.ball.flight_id != int(certificate.flight): return {"accepted": true, "interrupted": true}
	var event: Dictionary = game.ball.paddle_contact_context()
	if accepted:
		last_contact_evidence = certificate.evidence.duplicate(true)
		last_contact_evidence["physical_seconds"] = certificate.physical_seconds
		last_contact_evidence["control_seconds"] = certificate.control_seconds
		notify_physical_hand_contact(last_contact_evidence)
		if not game.ball.paddle_contact_is_current(event) or int(certificate.epoch) != game.contact_authority._interval_reset_epoch: return {"accepted": true, "interrupted": true}
		swept_hits += 1
	return {"accepted": accepted}

func finish_contact_intent(intent: Dictionary) -> void:
	if not contact_intent_is_current(intent): return
	if elapsed >= strike_time + .1:
		player.get_parent().release_aim_target()
		_finish_start_pose = visual_pose
		phase = 2; elapsed = 0.0
