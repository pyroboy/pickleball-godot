extends RefCounted
const BodyTurn = preload("res://scripts/rally_body_turn.gd")
const Swing = preload("res://scripts/human_swing_playback.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
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
## Seconds between this release and the ideal one (+ early, - late; NAN: not known). The swing
## times itself to the ball, so this is the player's timing (docs/SHOT_QUALITY_PLAN.md).
var release_error: float = NAN
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
## PerfToggles.human_plan_once (docs/PERFORMANCE_PLAN.md step 1): the contact is planned once per
## flight and kept, its clock counted down, until something it was planned from changes: a new
## flight (hit, serve, reset), a bounce, a sudden velocity change (net cord, wall, any outside
## push) or the swing moving to a new phase, at once; the player standing somewhere else (the
## planner measures the contact from the body) at most every PLAN_INTERVAL_SECONDS. With no
## plan found it retries at PLAN_EMPTY_RETRY. The old way re-planned at PLAN_INTERVAL_SECONDS
## always, and every tick in the last PLAN_EVERY_TICK_TIME and through the swing.
const PLAN_MOVE_M := 0.08            # body moved this far since the plan: plan again
const PLAN_VELOCITY_JUMP := 1.2      # m/s change in one tick beyond gravity: the flight was disturbed
const PLAN_EMPTY_RETRY := 0.2        # s between retries while nothing is planned
var _plan_bounces: int = -1
var _plan_root: Vector3 = Vector3.INF
var _plan_phase: int = -2
var _plan_ball_velocity: Vector3 = Vector3.ZERO
var _plan_velocity_tick: int = -1
var _plan_gravity_step: float = NAN   # m/s gravity adds per tick, read once

func _plan_stale(ball, now: int) -> bool:
	var velocity: Vector3 = ball.linear_velocity
	var disturbed: bool = false
	if _plan_velocity_tick == now - 1:
		if is_nan(_plan_gravity_step): _plan_gravity_step = float(ball.get_effective_gravity()) / float(Engine.physics_ticks_per_second)
		disturbed = (velocity - _plan_ball_velocity + Vector3(0.0, _plan_gravity_step, 0.0)).length() > PLAN_VELOCITY_JUMP
	_plan_ball_velocity = velocity
	_plan_velocity_tick = now
	if disturbed or _plan_flight != ball.flight_id or _plan_bounces != ball.bounces_since_last_hit or _plan_phase != phase: return true
	# Moving: never more often than the old interval (a running player moved past PLAN_MOVE_M every tick).
	var since: float = float(now - _plan_tick) / float(Engine.physics_ticks_per_second)
	if since < PLAN_INTERVAL_SECONDS: return false
	if player.global_position.distance_squared_to(_plan_root) > PLAN_MOVE_M * PLAN_MOVE_M: return true
	return contact.is_empty() and since >= PLAN_EMPTY_RETRY


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
	_physics_update_usec = Time.get_ticks_usec()
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
		var replan: bool
		if PerfToggles.human_plan_once:
			replan = _plan_stale(ball, now)
		else:
			var near_contact: bool = not contact.is_empty() and float(contact.time) <= PLAN_EVERY_TICK_TIME
			replan = near_contact or phase >= 1 or _plan_flight != ball.flight_id or float(now - _plan_tick) / float(Engine.physics_ticks_per_second) >= PLAN_INTERVAL_SECONDS
		if replan:
			var _pp: int = Time.get_ticks_usec()
			_plan_tick = now; _plan_flight = ball.flight_id
			_plan_bounces = ball.bounces_since_last_hit
			_plan_root = player.global_position
			_plan_phase = phase
			contact = Planner.select(player, ball, flight, old_id)
			if not contact.is_empty():
				if phase < 1:
					contact.def = _fit_planned_contact_grip(contact, ball, previous_contact_pose)
				elif swing_def != null and contact.posture == swing_def.posture_id:
					# The real released stroke owns its grip. A refreshed trajectory
					# can move the contact point, never regrip at the impact frame.
					contact.def.main_grip_rotation_deg = swing_def.main_grip_rotation_deg
			PerfMonitor.record("human.plan", Time.get_ticks_usec() - _pp)
		elif not contact.is_empty():
			contact.time = maxf(0.0, float(contact.time) - delta)   # keep the reused plan's clock honest
		var _ps: int = Time.get_ticks_usec()
		_update_superblocks(delta, ball, flight)
		var _pa: int = Time.get_ticks_usec()
		PerfMonitor.record("human.superblocks", _pa - _ps)
		_update_anticipation(delta, ball, flight)
		PerfMonitor.record("human.anticipation", Time.get_ticks_usec() - _pa)
	else:
		# Not tracking: runs every tick between balls, so an empty plan is not reallocated.
		_distant_load_active = false
		if not contact.is_empty(): contact = {}
		if not anticipated_contact.is_empty(): anticipated_contact = {}
		if not smash_spot.is_empty(): smash_spot = {}
		if not superblock_hint.is_empty(): superblock_hint = {}
		_superblock_clock = 0.0
		anticipation_path.clear()
		if footwork.active and phase <= 0:
			if phase == 0: cancel()
			else: footwork.cancel("flight no longer incoming")
	if _held_pose_pending: _flush_held_pose()
	var preparation: Dictionary = preparation_contact()
	posture._ball_incoming = not preparation.is_empty()
	posture._committed_incoming_posture = preparation.get("posture", -1)
	var _pw: int = Time.get_ticks_usec()
	if phase >= 0:
		var callback_epoch: int = ball.contact_callback_epoch()
		_advance_swing(delta, ball)
		PerfMonitor.record("human.swing", Time.get_ticks_usec() - _pw)
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
			var volley: bool = _contact_is_volley(ball)
			var near_kitchen: bool = _near_kitchen_context()
			var spin: int = _visual_spin_mode()
			var intent: String = _visual_shot_intent()
			var prepared: PostureDefinition = BodyTurn.sample(DriveMotion.drive_definition_shared(def, 0.0, volley, spin, near_kitchen, intent))   # only read below
			var target: PostureDefinition = ReadyMotion.prepare(prepared, ready, preparation.time, volley, near_kitchen)
			if float(preparation.time) > ReadyMotion.PREP_START_TIME:
				var early: PostureDefinition = BodyTurn.sample(DriveMotion.held_drive_pose(def, 0.18, volley, spin, near_kitchen, intent))
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
	var _pi: int = Time.get_ticks_usec()
	if phase < 0: PerfMonitor.record("human.pose", _pi - _pw)
	_update_indicators(ball)
	_remember_sweep(ball)
	PerfMonitor.record("human.indicators", Time.get_ticks_usec() - _pi)

## Perf (PerfToggles.held_curve_prewarm): the held-HIT curve of a stroke was built the first
## time that stroke was prepared, mid-rally: 129 pose samples, 13 ms on the Mac and over 20 ms
## on the phone in one tick, once per stroke per match. They are now built ahead, one stroke
## every other tick, while no rally is on (before the first serve and between points; called
## from player.gd every tick). A stroke prepared before its turn still builds on demand.
var _prewarm_ids: Array = []
var _prewarm_listed := false
func prewarm_held_curves() -> void:
	if not PerfToggles.held_curve_prewarm or Engine.get_physics_frames() % 2 != 0: return
	if _prewarm_listed and _prewarm_ids.is_empty(): return
	var game = player.get_parent()
	if game == null or not "game_state" in game or game.game_state == game.GameState.PLAYING: return
	if not _prewarm_listed:
		_prewarm_listed = true
		for def in PostureLibrary.instance().all_definitions():
			if def is PostureDefinition and def.has_zone and def.posture_id != 20: _prewarm_ids.append(def.posture_id)
	if _prewarm_ids.is_empty(): return
	var def: PostureDefinition = PostureLibrary.instance().get_def(int(_prewarm_ids.pop_back()))
	if def != null: held_hit_motion.prewarm(def)

func preparation_contact() -> Dictionary:
	var ball = player._get_ball_ref()
	if ball == null or ball.flight_id != _flight_id or phase >= 2 or ball.bounces_since_last_hit >= 2 or not Planner.should_track(player, ball): return {}
	if not contact.is_empty(): return contact
	if footwork.active and not footwork.plan.is_empty(): return footwork.plan
	if phase < 0 and Input.is_action_pressed("ui_accept") and not _preparation_hold_suppressed and not superblock_hint.is_empty(): return superblock_hint
	return anticipated_contact

## Risk of the hold in progress (0..1): a hard hit on a ball that will be met below the tape,
## close to the net. The same number the mishit score uses at contact (game.gd "low_drive"), so
## the ring colour is the rule (docs/SHOT_QUALITY_PLAN.md).
func hold_risk(hold_seconds: float) -> float:
	var Tuning = preload("res://scripts/gameplay_tuning.gd")
	if hold_seconds < preload("res://scripts/human_shot_choice.gd").TAP_SECONDS: return 0.0   # a tap is a touch shot
	var preparation: Dictionary = preparation_contact()
	var ball = player._get_ball_ref()
	if preparation.is_empty() or ball == null or not ball.both_bounces_complete or not preparation.has("point"): return 0.0
	var point: Vector3 = preparation.point
	var below: float = clampf(((PickleballConstants.FLOOR_Y + PickleballConstants.NET_HEIGHT) - point.y) / 0.4, 0.0, 1.0)
	var near_net: float = clampf((Tuning.LOW_DRIVE_FAR - absf(point.z)) / 1.5, 0.0, 1.0)
	var charge: float = minf(clampf(hold_seconds / PickleballConstants.RALLY_FULL_HOLD, 0.0, 1.0), 1.0 - Tuning.TIRED_CHARGE_CAP * player.stamina.tiredness())
	return below * charge * near_net

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
		if not superblock_hint.is_empty(): superblock_hint = {}
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
		# A ball beside you (side band) starts footwork too, when the sideways step fits in time.
		if anticipated_contact.is_empty() and player.hitting.charge_visual_active:
			var band: Dictionary = Footwork.band_plan(player, ball, flight)
			if bool(band.get("reachable", false)): anticipated_contact = band
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

## ---- One hold target at a time (user, 2026-11-25) ----
## While HIT is held the body aims at a planned contact (a pose and a point). The plan can come
## from four places (in-reach contact, footwork plan, side band, anticipation) and is refreshed
## ten times a second, and it sometimes jumped between two ways to take the same ball (about one
## refresh in ten moved the point some 2 m), with the pose chasing each jump. The held pose now
## commits to one choice:
##  - small refinements of the same choice are followed as before;
##  - a different choice must stay the candidate for HOLD_SWITCH_CONFIRM seconds, and not sooner
##    than HOLD_SWITCH_LOCK after the last switch;
##  - a choice that was left is not gone back to on this ball (no back and forth);
##  - the in-reach contact (the swing that will really happen) always wins, and a committed
##    choice whose moment has passed is dropped at once.
## Only the held (wind-up) pose reads this. The release timing, footwork and the swing itself
## still read preparation_contact(), so what the shot does is unchanged.
const HOLD_SAME_POINT_M := 0.35
const HOLD_SWITCH_CONFIRM := 0.2
const HOLD_SWITCH_LOCK := 0.5
const HOLD_GAP_GRACE := 0.5               # s the choice is kept while the planner offers nothing
var _held_gap_s: float = 0.0
const HOLD_SWITCH_BLEND_S := 0.4          # the blend is slower for this long after a switch ...
const HOLD_SWITCH_HALFLIFE := 0.14        # ... starting from this half-life (0.055 otherwise)
const HOLD_TARGET_HALFLIFE := 0.07        # s: easing of the target pose itself
var _held_target_pose: PostureDefinition = null
## ---- One writer for the rig (2026-11-25) ----
## The held pose is advanced on the input clock every rendered frame (so the wind-up keeps real
## time through slow motion), and it used to be written to the rig there too. The physics tick
## writes the rig as well, 30 times a second, and its version carries what the input-clock
## write left out (the footwork stance, the legs' own body drop, the support refit). So the body
## flipped between two slightly different poses on alternate frames: about 5 mm at the torso and
## head, more at the elbows. In a rally that hides in the motion; in the aim slow motion, with
## everything else nearly still, it was a visible shake, and the first-person view shook with it.
## Now the input clock only advances the pose; the tick writes it. Ticks keep their real-time
## rate in slow motion (the engine scales the step, not the rate), so the pose is at most one
## tick (33 ms) behind the hold. If no tick has run for a moment (a paused tool), the input
## clock writes as before.
const RIG_TICK_STALE_USEC := 120000
var _physics_update_usec: int = 0

func _tick_writes_rig() -> bool:
	return Time.get_ticks_usec() - _physics_update_usec < RIG_TICK_STALE_USEC

var held_target: Dictionary = {}          # the committed choice (tests read it)
var held_target_switches: int = 0
var _held_flight: int = -1
var _held_candidate: Dictionary = {}
var _held_candidate_s: float = 0.0
var _held_lock_s: float = 0.0
var _held_since_switch_s: float = 99.0
var _held_left: Array = []                # [posture id, point] of choices already left on this ball

static func _held_same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	if int(a.get("posture", -1)) != int(b.get("posture", -2)): return false
	if not a.has("point") or not b.has("point"): return true
	return Vector3(a.point).distance_to(Vector3(b.point)) <= HOLD_SAME_POINT_M

func _reset_held_target() -> void:
	_held_gap_s = 0.0
	_held_target_pose = null
	held_target = {}
	_held_candidate = {}
	_held_candidate_s = 0.0
	_held_lock_s = 0.0
	_held_since_switch_s = 99.0
	_held_left = []

func _commit_held(choice: Dictionary, counted: bool) -> void:
	if counted and not held_target.is_empty():
		_held_left.append({"posture": held_target.get("posture", -1), "point": held_target.get("point", Vector3.INF)})
		held_target_switches += 1
		_held_lock_s = HOLD_SWITCH_LOCK
		_held_since_switch_s = 0.0
	held_target = choice.duplicate()   # a copy: the sources keep changing their own dictionaries
	_held_candidate = {}
	_held_candidate_s = 0.0

## The choice the held pose aims at. `fresh` is preparation_contact(); `delta` advances the clocks
## (0 when this interval was already counted).
func _held_preparation(fresh: Dictionary, delta: float) -> Dictionary:
	var ball = player._get_ball_ref()
	var flight: int = ball.flight_id if ball != null else -1
	if phase >= 0 or flight != _held_flight:
		_reset_held_target()
		_held_flight = flight
		if fresh.is_empty() or phase >= 0: return fresh
	# The plan drops out for a moment on the same ball (often for two frames, while one planner
	# hands over to another): the committed choice is kept through the gap, so the pose does
	# not stop and start again. A longer gap ends it; choices already left stay left.
	if fresh.is_empty():
		_held_gap_s += delta
		if held_target.has("time"): held_target["time"] = float(held_target.time) - delta
		if held_target.is_empty() or _held_gap_s > HOLD_GAP_GRACE or float(held_target.get("time", 1.0)) < 0.0:
			held_target = {}
			_held_candidate = {}
			_held_candidate_s = 0.0
			return fresh
		return held_target
	_held_gap_s = 0.0
	_held_lock_s = maxf(0.0, _held_lock_s - delta)
	_held_since_switch_s += delta
	if held_target.is_empty() or _held_same(fresh, held_target):
		_commit_held(fresh, false)                       # first choice, or the same one refined
		return held_target
	if held_target.has("time"): held_target["time"] = float(held_target.time) - delta
	# The swing that will really happen, or a committed moment that has passed: switch now.
	if not contact.is_empty() and _held_same(fresh, contact) or float(held_target.get("time", 1.0)) < 0.0:
		_commit_held(fresh, true)
		return held_target
	# A choice already left on this ball is not gone back to.
	for left in _held_left:
		if _held_same(fresh, left): return held_target
	# A different choice has to hold as the candidate for a moment, one switch at a time.
	if _held_same(fresh, _held_candidate): _held_candidate_s += delta
	else: _held_candidate_s = 0.0
	_held_candidate = fresh
	if _held_candidate_s >= HOLD_SWITCH_CONFIRM and _held_lock_s <= 0.0: _commit_held(fresh, true)
	return held_target

func _held_blend_halflife() -> float:
	return lerpf(HOLD_SWITCH_HALFLIFE, 0.055, clampf(_held_since_switch_s / HOLD_SWITCH_BLEND_S, 0.0, 1.0))

func begin_held_hit() -> void:
	if phase >= 0: return
	_reset_held_target()
	held_hit_seconds = 0.0
	_charge_control_clock = false
	_charge_cancel_recovering = false
	_charge_recovery_seconds = 0.0
	_pending_held_delta = 0.0
	_held_pose_pending = false
	held_hit_motion.reset(false)
	var preparation: Dictionary = preparation_contact()
	if not preparation.is_empty(): held_hit_motion.prewarm(preparation.def, Callable(), "", true)

func set_charge(ratio: float, control_delta: float = -1.0) -> void :
	var _pt: int = Time.get_ticks_usec()
	_set_charge(ratio, control_delta)
	PerfMonitor.record("human.set_charge", Time.get_ticks_usec() - _pt)

func _set_charge(ratio: float, control_delta: float) -> void:
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
	if phase < 0 and control_delta >= 0.0:
		if PerfToggles.touch_on_change and _tick_writes_rig():
			# The tick writes the rig, so the held pose is advanced there, once per tick, with the
			# input time gathered since (at 60 fps one pose instead of two; the clock above, which
			# the charge meter reads, still runs every frame).
			_pending_held_delta += control_delta
			_held_pose_pending = true
			return
		control_delta += _pending_held_delta
		_pending_held_delta = 0.0
		_held_pose_pending = false
	_advance_held_pose(control_delta)

## Input time gathered for the held pose until the next tick (PerfToggles.touch_on_change).
var _pending_held_delta: float = 0.0
var _held_pose_pending: bool = false

func _flush_held_pose() -> void:
	var gathered: float = _pending_held_delta
	_pending_held_delta = 0.0
	_held_pose_pending = false
	if phase < 0 and _charge_control_clock: _advance_held_pose(gathered)

func _advance_held_pose(control_delta: float) -> void:
	var _pt: int = Time.get_ticks_usec()
	_advance_held_pose_inner(control_delta)
	PerfMonitor.record("human.held_pose", Time.get_ticks_usec() - _pt)

func _advance_held_pose_inner(control_delta: float) -> void:
	var preparation: Dictionary = _held_preparation(preparation_contact(), maxf(control_delta, 0.0))
	if preparation.is_empty():
		if visual_pose == null: visual_pose = _ready_pose(0.0)
		if not _tick_writes_rig(): _apply_visual()
		return
	_charge_target_pose = _held_preparation_pose(preparation)
	if visual_pose == null: visual_pose = _ready_pose(0.0)
	if control_delta >= 0.0 and phase < 0:
		_update_charge_pose(control_delta, true, _charge_target_pose)
	posture.transition_pose_blend = visual_pose
	if not _tick_writes_rig(): posture.force_posture_update(visual_pose)

func _update_charge_pose(delta: float, from_control_clock: bool = false, prepared_pose: PostureDefinition = null) -> void :
	# Only the control-clock call consumes a target during a live held input.
	# Sampling one on a world tick was discarded here and overwritten by the
	# next control update, including its latest moving contact/root/body state.
	if phase < 0 and _charge_control_clock and not from_control_clock: return
	# The control clock already advanced the commitment in set_charge for this interval.
	var preparation: Dictionary = _held_preparation(preparation_contact(), 0.0 if from_control_clock else delta)
	if preparation.is_empty(): return
	# The input path has already sampled this exact held interval and contact.
	_charge_target_pose = BodyTurn.sample(prepared_pose if prepared_pose != null else _held_preparation_pose(preparation))
	var previous_preparation: PostureDefinition = visual_pose
	# The target is re-aimed in steps (the ball prediction refreshes ten times a second); easing the
	# target first, then the pose toward it, turns each step into a smooth move instead of a pulse.
	_held_target_pose = ReadyMotion.blend_pose(_held_target_pose if _held_target_pose != null else _charge_target_pose, _charge_target_pose, delta, HOLD_TARGET_HALFLIFE)
	visual_pose = ReadyMotion.blend_pose(visual_pose if visual_pose != null else _ready_pose(0.0), _held_target_pose, delta, _held_blend_halflife())
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
	# The Erne marker (special_moments.gd) means "an Erne is on here": HIT takes it.
	# If the jump no longer fits, the ordinary swing goes ahead (only an explicit
	# ERNE pick refuses the swing, as before).
	var auto_erne: bool = action_game.selected_movement_intent == "AUTO" and bool(action_game.get("erne_chance_live"))
	if action_game.selected_movement_intent == "ERNE" or auto_erne:
		var opportunity: Dictionary = player.erne_action.choose_plan(ball)
		if player.erne_action.begin(opportunity, ball):
			_released_joint_path = true
			footwork.cancel("Erne owns lateral jump", false)
			contact = {}
			anticipated_contact = opportunity
			action_game.selected_movement_intent = "AUTO"
		elif not auto_erne: return false
	if contact.is_empty() and not footwork.active and not player.erne_action.active and not anticipated_contact.is_empty():
		footwork.activate_plan(anticipated_contact, player._get_ball_ref())
	var preparation: Dictionary = preparation_contact()
	if contact.is_empty() and not footwork.active and preparation.is_empty():
		cancel()
		return false
	_released_joint_path = true
	charge_ratio = clampf(ratio, 0, 1)
	_swing_near_kitchen = _near_kitchen_context()
	var timed: Dictionary = contact if not contact.is_empty() else preparation
	release_error = NAN
	if not timed.is_empty() and timed.get("def") != null and is_finite(float(timed.get("time", NAN))):
		release_error = float(timed.time) - float(timed.def.ft_duration_strike) - preload("res://scripts/gameplay_tuning.gd").TIMING_CENTRE


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
	_pending_held_delta = 0.0
	_held_pose_pending = false
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
		# The swing shape lives in human_swing_playback.gd: Pose Studio's Hold / Play call the same.
		visual_pose = Swing.strike_pose(swing_def, factor, charge_ratio, _swing_is_volley, _swing_spin_mode, _swing_near_kitchen, _swing_shot_intent, motion_context, _strike_start_pose)
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
		visual_pose = Swing.finish_pose(swing_def, elapsed / maxf(0.01, swing_def.ft_duration_sweep), charge_ratio, _swing_is_volley, _swing_spin_mode, _swing_near_kitchen, _swing_shot_intent, motion_context, _finish_start_pose)
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
	_sweep_valid = (phase == 0 or phase == 1) and visual_pose != null and ball.flight_id == swing_flight_id
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
	var ready: PostureDefinition = ReadyMotion.ready_pose(preload("res://scripts/hunt_ready.gd").ready_for(player, player._get_ball_ref()))
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
	# Simple hands (PerfToggles.simple_hands): the stroke keeps its posed grip.
	if PerfToggles.simple_hands: return BodyTurn.sample(base).duplicate(false)
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
