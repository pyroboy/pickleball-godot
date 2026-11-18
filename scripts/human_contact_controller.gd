extends RefCounted
## Human contact prediction, held-charge pose and physics-timed swing share one target.
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Colors = preload("res://scripts/posture_colors.gd")
const HIT_DISTANCE: float = Planner.IMPACT_DISTANCE
var player
var posture
var contact: Dictionary = {}
var visual_pose: PostureDefinition
var charge_ratio: float = 0.0
var phase: int = -1 # -1 tracking, 0 queued, 1 strike, 2 finish, 3 hold, 4 recovery
var elapsed: float = 0.0
var strike_time: float = 0.12
var swing_def: PostureDefinition
var swing_flight_id: int = -1
var hit: bool = false
var _flight_id: int = -1

func _init(owner, module) -> void:
	player = owner
	posture = module

func update(delta: float) -> void:
	var ball = player._get_ball_ref()
	if ball == null: return
	if ball.flight_id != _flight_id:
		_flight_id = ball.flight_id
		contact = {}
		posture._blue_latched = false
		posture._scored_this_ball = false
	var old_id: int = contact.get("posture", -1)
	if ball.is_in_play and ball.last_hit_by != player.player_num and ball.linear_velocity.dot(-player._get_forward_axis()) >= 0.1:
		var flight: Dictionary = player.debug_visual._last_flight if player.debug_visual else {}
		if flight.is_empty(): flight = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity)
		contact = Planner.select(player, ball, flight, old_id)
	else:
		contact = {}
	posture._ball_incoming = not contact.is_empty()
	posture._committed_incoming_posture = contact.get("posture", -1)
	if phase >= 0:
		_advance_swing(delta, ball)
	elif not contact.is_empty():
		var def: PostureDefinition = contact.def
		visual_pose = def.lerp_with(Path.endpoint(def, 0), charge_ratio) if player.hitting.charge_visual_active else def
		posture.force_posture_update(visual_pose)
		posture.transition_pose_blend = visual_pose
	else:
		var had_pose: bool = visual_pose != null
		visual_pose = null
		if not player.hitting.is_in_follow_through and not player.hitting.charge_visual_active:
			posture.transition_pose_blend = null
			if had_pose or posture.paddle_posture != player.PaddlePosture.READY:
				posture.force_posture_update(PostureLibrary.instance().get_def(player.PaddlePosture.READY))
	_update_indicators(ball)

func set_charge(ratio: float) -> void:
	if phase >= 1: return
	charge_ratio = clampf(ratio, 0, 1)
	if contact.is_empty(): return
	player.hitting.charge_visual_active = true
	visual_pose = contact.def.lerp_with(Path.endpoint(contact.def, 0), charge_ratio)
	posture.transition_pose_blend = visual_pose
	posture.force_posture_update(visual_pose)

func request_swing(ratio: float) -> bool:
	if phase >= 0: return false
	if contact.is_empty():
		cancel()
		return false
	charge_ratio = clampf(ratio, 0, 1)
	phase = 0
	elapsed = 0
	hit = false
	swing_flight_id = _flight_id
	player.hitting.charge_visual_active = true
	return true

func cancel() -> void:
	if phase >= 0:
		phase = -1
		player.hitting.is_in_follow_through = false
		player.hitting.charge_visual_active = false
	visual_pose = null
	charge_ratio = 0

func _advance_swing(delta: float, ball) -> void:
	if phase == 0:
		if contact.is_empty() or ball.flight_id != swing_flight_id:
			cancel()
			posture.transition_pose_blend = null
			return
		set_charge(charge_ratio)
		if contact.time > contact.def.ft_duration_strike: return
		swing_def = contact.def
		strike_time = maxf(0.025, contact.time)
		phase = 1
		elapsed = 0.0
		player.hitting.charge_visual_active = false
		player.hitting.is_in_follow_through = true
	elif phase == 1:
		elapsed += delta
		# Refresh the contact position up to impact, without switching swing families mid-strike.
		if not contact.is_empty() and contact.posture == swing_def.posture_id:
			swing_def = contact.def
		var factor: float = clampf(elapsed / strike_time, 0, 1)
		visual_pose = swing_def.lerp_with(Path.sample(swing_def, factor * 0.5), charge_ratio)
		_apply_visual()
		if Planner.legal_ball(player, ball) and ball.flight_id == swing_flight_id and PaddleReach.head_world(player).distance_to(ball.global_position) <= HIT_DISTANCE:
			var game = player.get_parent()
			hit = game._apply_player_contact_hit(charge_ratio, swing_def.posture_id)
		if hit or elapsed >= strike_time + 0.10:
			phase = 2
			elapsed = 0
	elif phase == 2:
		elapsed += delta
		var factor: float = Path.release_progress(swing_def, 1, clampf(elapsed / maxf(0.01, swing_def.ft_duration_sweep), 0, 1))
		visual_pose = swing_def.lerp_with(Path.sample(swing_def, factor), charge_ratio)
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
		var finish: PostureDefinition = swing_def.lerp_with(Path.endpoint(swing_def, 2), charge_ratio)
		var ready: PostureDefinition = PostureLibrary.instance().get_def(player.PaddlePosture.READY)
		var factor: float = clampf(elapsed / maxf(0.01, swing_def.ft_duration_settle), 0, 1)
		factor = smoothstep(0, 1, factor)
		visual_pose = finish.lerp_with(ready, factor)
		if elapsed >= swing_def.ft_duration_settle:
			cancel()
			posture.transition_pose_blend = null
			posture.force_posture_update(ready)
			return
	_apply_visual()

func _apply_visual() -> void:
	if visual_pose:
		posture.transition_pose_blend = visual_pose
		posture.force_posture_update(visual_pose)

func _update_indicators(ball) -> void:
	if contact.is_empty():
		posture._last_commit_stage = -1
		posture._emit_stage_cleared()
	else:
		var distance: float = ball.global_position.distance_to(contact.point)
		var stage: int = 2 if contact.time < posture.TTC_BLUE else (1 if contact.time < posture.TTC_PURPLE else 0)
		posture._last_commit_stage = stage
		posture._contact_point_local = contact.point - player.global_position
		posture.incoming_stage_changed.emit(stage, contact.posture, ball.global_position.distance_to(player.global_position), distance, contact.time)
	if player.debug_visual:
		player.debug_visual.human_committed_contact_position = contact.get("point", Vector3.ZERO)
		var marker = player.debug_visual.human_intercept_indicator
		if marker:
			marker.visible = not contact.is_empty() and (player.debug_visual._intercept_visible or not player.debug_visual._intent_hidden)
			if not contact.is_empty(): marker.global_position = contact.point

func draw_ghosts() -> void:
	for id in posture.posture_ghosts:
		var ghost: Node3D = posture.posture_ghosts[id]
		var selected: bool = not contact.is_empty() and id == contact.posture
		var def: PostureDefinition = contact.def if selected else PostureLibrary.instance().get_def(id)
		if def == null: continue
		var transform: Transform3D = Path.world_transform(player, def)
		var head: Vector3 = transform.origin + transform.basis.y * 0.4
		ghost.global_transform = Transform3D(transform.basis.scaled(posture.POSTURE_GHOST_SCALE), head - transform.basis.y * 0.4 * posture.POSTURE_GHOST_SCALE.y)
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
