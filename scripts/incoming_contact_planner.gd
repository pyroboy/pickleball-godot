extends RefCounted
const ActivationZones = preload("res://scripts/contact_activation_zones.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")

const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const IMPACT_DISTANCE: float = 0.1
const CONTACT_MARGIN: float = 0.03
const LIVE_WINDOW: float = 0.14
const MAX_GRIP_DISTANCE: float = 0.705
const FloorGeometry = preload("res://scripts/paddle_floor_geometry.gd")
const ContactGeometry = preload("res://scripts/paddle_clearance.gd")
const FLOOR_RECEIVE_CEILING := 0.30
const MAX_RECEIVE_CROUCH := 0.65
const RECEIVE_WRIST_RESERVE := 0.012

static func _floor_receive(def: PostureDefinition, height: float) -> bool:
	return def.has_zone and def.height_tier == 0 and height <= def.zone_y_max + CONTACT_MARGIN

static func floor_receive_pose(player, def: PostureDefinition, point: Vector3) -> PostureDefinition:
	# The ball touches the low blade, rather than requiring its centre to be
	# the paddle centre. Only a transient receiving pose is changed.
	var height: float = point.y - player.COURT_FLOOR_Y
	if not _floor_receive(def, height) or height < ActivationZones.FLOOR_BALL_HEIGHT - 0.00001: return null
	if "is_jumping" in player and player.is_jumping: return null
	var basis: Basis = Path.paddle_basis(player, def)
	var head := point
	head.y = maxf(head.y, player.COURT_FLOOR_Y + FloorGeometry.head_clearance(basis))
	var raw := Transform3D(basis, head - basis * PaddleDimensions.HEAD_OFFSET)
	if ContactGeometry.distance_to_head_shape(raw.affine_inverse() * point) > ActivationZones.FLOOR_BALL_HEIGHT + ContactGeometry.contact_surface_tolerance(): return null
	var shoulder: Vector3 = Body.shoulder_world(player, def)
	var wrist: Vector3 = WristReach.wrist_from_head(head, basis, def)
	var delta: Vector3 = shoulder - wrist
	var budget: float = WristReach.link_budget(player, def)
	var horizontal_squared: float = Vector2(delta.x, delta.z).length_squared()
	if horizontal_squared >= budget * budget: return null
	var lower: float = maxf(0.0, delta.y - sqrt(budget * budget - horizontal_squared) + RECEIVE_WRIST_RESERVE)
	if lower > maxf(0.0, MAX_RECEIVE_CROUCH - def.crouch_amount): return null
	var pose: PostureDefinition = def.lerp_with(def, 0.0)
	pose.crouch_amount += lower
	pose.paddle_floor_clearance = 0.0
	# In-hand spin can move a custom head around its authored offset grip.
	# Store the inverse transform so the displayed head matches the solution.
	var unspun: Transform3D = Path.remove_in_hand_transform(raw, pose)
	var target: Vector3 = unspun * PaddleDimensions.HEAD_OFFSET - player.global_position
	pose.paddle_forehand_mul = target.dot(player._get_forehand_axis())
	pose.paddle_forward_mul = target.dot(player._get_forward_axis())
	pose.paddle_y_offset = target.y
	var solved: Transform3D = Path.world_transform(player, pose)
	var actual_shoulder: Vector3 = Body.shoulder_world(player, pose)
	if not WristReach.fits(solved, pose, actual_shoulder, budget): return null
	if (solved * PaddleDimensions.HEAD_OFFSET).distance_to(actual_shoulder) > PaddleReach.MAX_HEAD_DISTANCE: return null
	if ContactGeometry.distance_to_head_shape(solved.affine_inverse() * point) > ActivationZones.FLOOR_BALL_HEIGHT + ContactGeometry.contact_surface_tolerance(): return null
	return pose


static func wall_mode(ball) -> bool:
	return ball != null and "wall_practice_active" in ball and ball.wall_practice_active

static func legal_ball(player, ball, future_bounces: int = 0, volley_override: int = -1) -> bool:
	if wall_mode(ball):
		return player.player_num == 0 and ball.is_in_play and ball.wall_return_ready and ball.last_hit_by != 0 and ball.bounces_since_last_hit + future_bounces < 2
	if not ball.is_in_play or ball.last_hit_by == player.player_num: return false
	var total_bounces: int = ball.bounces_since_last_hit + future_bounces
	if total_bounces >= 2: return false
	if not ball.both_bounces_complete and total_bounces == 0: return false

	if total_bounces == 0:
		# Passive queries supply a cloned-foot-state result. Ordinary gameplay
		# keeps the original stateful foot establishment check.
		if volley_override >= 0:
			if volley_override == 0: return false
		elif player.has_method("can_volley_from_feet"):
			if not player.can_volley_from_feet(): return false
		elif absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 1e-05:
			return false
	return true

static func predicted_fault_time(player, ball, flight: Dictionary) -> float:


	var fault: = INF
	if wall_mode(ball):
		var total: int = ball.bounces_since_last_hit
		for event in flight.get("bounce_events", []):
			total += 1
			if total >= 2: return float(event.time)
		return fault
	var scorer = null
	if player is Node:
		var game = player.get_parent()
		if game != null and "rally_scorer" in game: scorer = game.rally_scorer
	var bounces: int = ball.bounces_since_last_hit
	for event in flight.get("bounce_events", []):
		bounces += 1
		var p: Vector3 = event.pos
		var invalid: bool = bounces >= 2 or bounces == 1 and RallyScorer.is_outside_painted_court(p)
		if bounces == 1 and ball.last_hit_by >= 0:
			var last_side: int = int(ball.last_hit_court_side) if "last_hit_court_side" in ball else int(ball.last_hit_by)
			invalid = invalid or (p.z > 0.0) == (last_side == 0)
			if scorer != null and not scorer._serve_was_hit and ball.last_hit_by == scorer._serving_team:
				invalid = invalid or not scorer.check_service_ball_landed(p).get("valid", true)
		if invalid:
			fault = minf(fault, float(event.time))
			break
	return fault

static func point_fits(player, def: PostureDefinition, point: Vector3, margin: float = CONTACT_MARGIN) -> bool:
	var offset: Vector3 = point - player.global_position
	var lateral: float = offset.dot(player._get_forehand_axis())
	var forward: float = offset.dot(player._get_forward_axis())
	var height: float = point.y - player.COURT_FLOOR_Y
	if forward < 0.0 or absf(point.z) < 0.02: return false
	if point.z * player.global_position.z < 0.0: return false
	if not ActivationZones.contains(def, lateral, height, margin): return false
	if _authored_reach_fits(player, def, point): return true
	return _floor_receive(def, height) and floor_receive_pose(player, def, point) != null

static func _authored_reach_fits(player, def: PostureDefinition, point: Vector3) -> bool:
	if point.y < player.COURT_FLOOR_Y + def.paddle_floor_clearance: return false
	# A generated low pose can deliberately contact with the blade tip.
	if def.height_tier == 0 and def.paddle_floor_clearance < FLOOR_RECEIVE_CEILING and point.y < player.COURT_FLOOR_Y + FloorGeometry.head_clearance(Path.paddle_basis(player, def)): return false
	var shoulder: Vector3 = Body.shoulder_world(player, def)
	if point.distance_to(shoulder) > PaddleReach.MAX_HEAD_DISTANCE: return false
	var wrist: Vector3 = WristReach.wrist_from_head(point, Path.paddle_basis(player, def), def)
	return wrist.distance_to(shoulder) <= WristReach.link_budget(player, def) + WristReach.NUMERICAL_EPSILON

static func pose_at(player, def: PostureDefinition, point: Vector3) -> PostureDefinition:
	if _floor_receive(def, point.y - player.COURT_FLOOR_Y) and not _authored_reach_fits(player, def, point):
		var low: PostureDefinition = floor_receive_pose(player, def, point)
		if low != null: return low
	var pose: PostureDefinition = def.lerp_with(def, 0.0)
	var offset: Vector3 = point - player.global_position




	if def.family == 1 and def.left_hand_mode == 1:
		var lower: float = clampf(def.paddle_y_offset - offset.y, 0.0, maxf(0.0, 0.3 - def.crouch_amount))
		pose.crouch_amount += lower
		pose.right_elbow_pole.y -= lower
		pose.left_elbow_pole.y -= lower



		if lower > 1e-06:
			pose.right_elbow_path = def.right_elbow_path.duplicate()
			pose.left_elbow_path = def.left_elbow_path.duplicate()
			for i in range(pose.right_elbow_path.size()): pose.right_elbow_path[i].y -= lower
			for i in range(pose.left_elbow_path.size()): pose.left_elbow_path[i].y -= lower
			for field in ["windup_body", "follow_through_body"]:
				var source: Resource = def.get(field)
				if source == null: continue
				var key: Resource = source.duplicate(true)
				key.values["crouch_amount"] = float(key.values.get("crouch_amount", def.crouch_amount)) + lower
				for elbow in ["right_elbow_pole", "left_elbow_pole"]:
					var pole: Vector3 = key.values.get(elbow, def.get(elbow))
					pole.y -= lower
					key.values[elbow] = pole
				pose.set(field, key)
	pose.paddle_forehand_mul = offset.dot(player._get_forehand_axis())
	pose.paddle_forward_mul = offset.dot(player._get_forward_axis())
	pose.paddle_y_offset = offset.y
	return pose

static func select(player, ball, flight: Dictionary, previous_id: int = -1, volley_override: int = -1) -> Dictionary:
	ActivationZones.refresh(CONTACT_MARGIN)
	var samples: Array = flight.get("samples", [])
	if samples.is_empty() or not ball.is_in_play or ball.last_hit_by == player.player_num: return {}
	if not should_track(player, ball): return {}
	var fault_time: float = predicted_fault_time(player, ball, flight)
	if fault_time <= 0.0: return {}
	var choices: Array[Dictionary] = []
	var fwd: Vector3 = player._get_forward_axis()
	var forward_now: float = (ball.global_position - player.global_position).dot(fwd)
	# Lazily project each reached sample once. Array[float] retains the exact
	# scalar value; a Vector/PackedFloat32 cache would introduce rounding.
	var sample_forward: Array[float] = []
	for def in PostureLibrary.instance().all_definitions():
		if not def.has_zone: continue
		var candidate: Dictionary = {}
		if absf(forward_now - def.zone_forward_offset) <= LIVE_WINDOW and legal_ball(player, ball, 0, volley_override) and point_fits(player, def, ball.global_position):
			candidate = {"point": ball.global_position, "time": 0.0, "bounces": 0}
		else:
			for i in range(samples.size() - 1):
				var a: Dictionary = samples[i]
				var b: Dictionary = samples[i + 1]
				while sample_forward.size() <= i + 1:
					sample_forward.append((samples[sample_forward.size()].pos - player.global_position).dot(fwd))
				var da: float = sample_forward[i] - def.zone_forward_offset
				var db: float = sample_forward[i + 1] - def.zone_forward_offset
				if da < 0 or db > 0 or da - db < 1e-05: continue

				# The predictor stores one post-bounce endpoint per physics tick.
				# Its incoming segment is still legal before that timestamp, with
				# the OLD bounce count. Never connect across a later bounce or
				# count a pre-bounce point as the required first ground contact.
				var segment_bounces: int = int(a.bounces)
				if int(b.bounces) != segment_bounces and int(b.bounces) != segment_bounces + 1: continue
				var fraction: float = clampf(da / (da - db), 0.0, 1.0)
				if a.bounces != b.bounces and fraction >= 1.0: continue
				var point: Vector3 = a.pos.lerp(b.pos, fraction)
				var time: float = lerpf(a.time, b.time, fraction)
				if time >= fault_time: continue
				if not legal_ball(player, ball, segment_bounces, volley_override) or not point_fits(player, def, point): continue
				candidate = {"point": point, "time": time, "bounces": segment_bounces}
				break
		if candidate.is_empty(): continue
		var rest: Vector3 = player.global_position + def.resolve_paddle_offset(player._get_forehand_axis(), fwd)
		candidate["score"] = rest.distance_to(candidate.point) + candidate.time * 0.015
		candidate["posture"] = def.posture_id
		# Ranking only reads point/time/score/posture. Retain the authored
		# definition until hysteresis resolves the one pose that will be used.
		candidate["def"] = def
		choices.append(candidate)
	if choices.is_empty(): return select_extended(player, ball, flight, previous_id, false, volley_override)
	choices.sort_custom(func(a, b): return a.score < b.score if a.score != b.score else int(a.posture) < int(b.posture))
	var best: Dictionary = choices[0]

	for choice in choices:
		if choice.posture == previous_id and choice.score <= best.score + 0.045:
			best = choice
			break
	best["def"] = pose_at(player, best["def"], best.point)
	return best

static func should_track(player, ball) -> bool:
	if ball == null or not ball.is_in_play or ball.last_hit_by == player.player_num: return false
	var relative: Vector3 = ball.global_position - player.global_position
	var flat: = Vector3(relative.x, 0, relative.z)
	var velocity: = Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)
	var forward: float = relative.dot(player._get_forward_axis())
	return ball.linear_velocity.dot( - player._get_forward_axis()) >= 0.1 or velocity.dot( - flat.normalized()) > 0.05 or (forward > 0 and flat.length() < PaddleReach.MAX_HEAD_DISTANCE)

static func balanced_reach_pose(player, base: PostureDefinition, point: Vector3) -> PostureDefinition:


	if point_fits(player, base, point): return pose_at(player, base, point)
	var lean: PostureDefinition = _lean_variant(player, base, point)
	if lean == null or not point_fits(player, lean, point): return null
	var pose: PostureDefinition = pose_at(player, lean, point)
	pose.set_meta("extended_reach", true)
	return pose

static func _lean_variant(player, base: PostureDefinition, point: Vector3) -> PostureDefinition:
	if "is_jumping" in player and player.is_jumping: return null
	if "current_velocity" in player and Vector2(player.current_velocity.x, player.current_velocity.z).length() > 1.3: return null
	var forward: float = (point - player.global_position).dot(player._get_forward_axis())
	var amount: float = clampf((forward - base.zone_forward_offset) / 0.35, 0.0, 1.0)
	if amount < 0.15: return null
	var lean: PostureDefinition = base.lerp_with(base, 0.0)
	lean.body_pitch_deg += 8.0 * amount
	lean.torso_pitch_deg += 4.0 * amount
	lean.weight_shift = minf(1.0, base.weight_shift + 0.45 * amount)
	lean.crouch_amount += 0.02 * amount
	return lean

static func select_extended(player, ball, flight: Dictionary, previous_id: int = -1, require_bounce: bool = false, volley_override: int = -1) -> Dictionary:


	var samples: Array = flight.get("samples", [])
	if samples.is_empty() or not should_track(player, ball): return {}
	var fault_time: float = predicted_fault_time(player, ball, flight)
	var legal_zero: bool = legal_ball(player, ball, 0, volley_override)
	var legal_one: bool = legal_ball(player, ball, 1, volley_override)
	var forehand: Vector3 = player._get_forehand_axis()
	var forward: Vector3 = player._get_forward_axis()
	var best: Dictionary = {}
	var best_score: = INF
	for base in PostureLibrary.instance().all_definitions():
		if not base.has_zone: continue
		var lean_template: PostureDefinition
		var base_shoulder: Vector3 = Body.shoulder_world(player, base)
		var lean_tried: = false
		var sample_count: int = mini(samples.size(), 60)
		for index in range(0, sample_count + 1, 2):


			var sample: Dictionary = samples[mini(index, sample_count - 1)]
			var bounces: int = int(sample.bounces)
			if float(sample.time) >= fault_time: continue
			if require_bounce and bounces + ball.bounces_since_last_hit == 0: continue
			if not (legal_zero if bounces == 0 else legal_one if bounces == 1 else false): continue
			var point: Vector3 = sample.pos
			var local: Vector3 = point - player.global_position
			var lateral: float = local.dot(forehand)
			var front: float = local.dot(forward)
			var height: float = point.y - player.COURT_FLOOR_Y
			if front < 0.08 or front > 1.2 or not ActivationZones.contains(base, lateral, height, CONTACT_MARGIN): continue
			if not _floor_receive(base, height) and point.distance_to(base_shoulder) > PaddleReach.MAX_HEAD_DISTANCE + 0.12: continue
			var chosen: PostureDefinition = base
			if not point_fits(player, base, point):
				if _floor_receive(base, height):
					# A cached far-forward lean cannot be carried back to a low
					# ball beside the feet. Compose knee load only with the lean
					# actually permitted at this candidate's forward distance.
					var low_lean: PostureDefinition = _lean_variant(player, base, point)
					if low_lean == null or not point_fits(player, low_lean, point): continue
					chosen = low_lean
				else:
					if not lean_tried:
						lean_template = _lean_variant(player, base, point)
						lean_tried = true
					if lean_template == null or not point_fits(player, lean_template, point): continue
					chosen = lean_template
			var rest: Vector3 = player.global_position + base.resolve_paddle_offset(forehand, forward)
			var score: float = float(sample.time) + rest.distance_to(point) * 0.08 - (0.025 if base.posture_id == previous_id else 0.0)
			if score < best_score or score == best_score and (best.is_empty() or base.posture_id < int(best.posture)):


				var pose: PostureDefinition = pose_at(player, chosen, point)
				pose.set_meta("extended_reach", true)
				best_score = score
				best = {"point": point, "time": float(sample.time), "bounces": bounces, "posture": base.posture_id, "def": pose, "score": score, "extended": true}
			break
	return best if not best.is_empty() else select_floor_swept(player, ball, flight, previous_id, require_bounce, volley_override)


static func select_floor_swept(player, ball, flight: Dictionary, previous_id: int = -1, require_bounce: bool = false, volley_override: int = -1) -> Dictionary:
	ActivationZones.refresh(CONTACT_MARGIN)
	var samples: Array = flight.get("samples", [])
	var fault_time: float = predicted_fault_time(player, ball, flight)
	var best: Dictionary = {}
	var best_score := INF
	var forehand: Vector3 = player._get_forehand_axis()
	var forward: Vector3 = player._get_forward_axis()
	var floor_bounds: Rect2 = ActivationZones.floor_bounds()
	for index in range(mini(samples.size() - 1, 59)):
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		if minf(a.pos.y, b.pos.y) > player.COURT_FLOOR_Y + floor_bounds.end.y: continue
		if float(a.time) >= fault_time: break
		var count: int = int(a.bounces)
		if int(b.bounces) != count and int(b.bounces) != count + 1: continue
		if not legal_ball(player, ball, count, volley_override) or require_bounce and count + ball.bounces_since_last_hit == 0: continue
		var local: Vector3 = a.pos - player.global_position
		var step: Vector3 = b.pos - a.pos
		var origin := Vector3(local.dot(forehand), a.pos.y - player.COURT_FLOOR_Y, local.dot(forward))
		var delta := Vector3(step.dot(forehand), step.y, step.dot(forward))
		var bounds: Rect2 = ActivationZones.floor_bounds()
		var broad := _clip_axis(origin.x, delta.x, bounds.position.x, bounds.end.x, Vector2(0.0, 1.0))
		broad = _clip_axis(origin.z, delta.z, 0.08, 1.2, broad)
		if broad.x > broad.y: continue
		for base in PostureLibrary.instance().all_definitions():
			if not base.has_zone or base.height_tier != 0: continue
			for rect: Rect2 in ActivationZones.regions_for(base):
				var interval := Vector2(0.0, 1.0)
				var minimum := Vector3(rect.position.x, ActivationZones.FLOOR_BALL_HEIGHT, 0.08)
				var maximum := Vector3(rect.end.x, rect.end.y, 1.2)
				for axis in range(3): interval = _clip_axis(origin[axis], delta[axis], minimum[axis], maximum[axis], interval)
				if interval.x > interval.y: continue
				# Clip the swept wrist against the vertical interval of possible
				# grounded shoulders. Arbitrary start/mid/end probes can miss a
				# narrow diagonal contact between those three positions.
				for reachable: Vector2 in _floor_reach_intervals(player, base, a.pos, b.pos, interval):
					for fraction in [minf(reachable.x + 0.00001, (reachable.x + reachable.y) * 0.5), (reachable.x + reachable.y) * 0.5, maxf(reachable.y - 0.00001, reachable.x)]:
						var time: float = lerpf(a.time, b.time, fraction)
						if time >= fault_time or int(b.bounces) != count and fraction >= 1.0: continue
						var point: Vector3 = a.pos.lerp(b.pos, fraction)
						if not point_fits(player, base, point): continue
						var rest: Vector3 = player.global_position + base.resolve_paddle_offset(forehand, forward)
						var score: float = time + rest.distance_to(point) * 0.08 - (0.025 if base.posture_id == previous_id else 0.0)
						if score > best_score or score == best_score and not best.is_empty() and base.posture_id >= int(best.posture): continue
						var pose := pose_at(player, base, point)
						best_score = score
						best = {"point": point, "time": time, "bounces": count, "posture": base.posture_id, "def": pose, "score": score, "extended": true, "swept_prediction": true}
	return best if not best.is_empty() else select_swept_extended(player, ball, flight, previous_id, require_bounce, volley_override)


static func _floor_reach_intervals(player, def: PostureDefinition, a: Vector3, b: Vector3, interval: Vector2) -> Array[Vector2]:
	var basis: Basis = Path.paddle_basis(player, def)
	var wrist_offset: Vector3 = WristReach.head_to_wrist_offset(basis, def)
	var shoulder: Vector3 = Body.shoulder_world(player, def)
	var lowest: Vector3 = shoulder - Vector3.UP * (maxf(0.0, MAX_RECEIVE_CROUCH - def.crouch_amount) - RECEIVE_WRIST_RESERVE)
	var budget: float = WristReach.link_budget(player, def)
	var floor_head: float = player.COURT_FLOOR_Y + FloorGeometry.head_clearance(basis)
	var step := b - a
	var cuts: Array[float] = [interval.x, interval.y]
	if absf(step.y) > 0.0000001:
		var crossing: float = (floor_head - a.y) / step.y
		if crossing > interval.x and crossing < interval.y: cuts.insert(1, crossing)
	var result: Array[Vector2] = []
	for index in range(cuts.size() - 1):
		var piece := Vector2(cuts[index], cuts[index + 1])
		var wrist := a + wrist_offset
		var motion := step
		if a.y + step.y * (piece.x + piece.y) * 0.5 < floor_head:
			wrist.y = floor_head + wrist_offset.y
			motion.y = 0.0
		# Vertical capsule = two spherical caps and a finite cylinder. This
		# covers every bounded knee-load amount, rather than just max crouch.
		# The lower cap includes the same small vertical load reserve used by
		# the exact pose solver; it does not shorten the nominal arm radius.
		for center in [shoulder, lowest]:
			var cap := _clip_sphere(wrist - center, motion, budget, piece)
			if cap.x <= cap.y: result.append(cap)
		var radial := Vector3(wrist.x - shoulder.x, 0.0, wrist.z - shoulder.z)
		var radial_motion := Vector3(motion.x, 0.0, motion.z)
		var cylinder := _clip_sphere(radial, radial_motion, budget, piece)
		cylinder = _clip_axis(wrist.y, motion.y, minf(lowest.y, shoulder.y), maxf(lowest.y, shoulder.y), cylinder)
		if cylinder.x <= cylinder.y: result.append(cylinder)
		# A valid authored pose keeps the ordinary nominal arm budget and
		# may own the upper part of a derived seam shared with another pose.
		if a.y + step.y * piece.y >= player.COURT_FLOOR_Y + def.paddle_floor_clearance or a.y + step.y * piece.x >= player.COURT_FLOOR_Y + def.paddle_floor_clearance:
			var native := _clip_sphere(a + wrist_offset - shoulder, step, WristReach.link_budget(player, def) + WristReach.NUMERICAL_EPSILON, piece)
			if native.x <= native.y: result.append(native)
	result.sort_custom(func(x, y): return x.x < y.x)
	return result

# Fallback for a lateral/vertical path that traverses the activation region
# between physics samples without crossing a posture's nominal front plane.
# This predicts a contact; actual hits still require the finite paddle sweep.
static func select_swept_extended(player, ball, flight: Dictionary, previous_id: int = -1, require_bounce: bool = false, volley_override: int = -1) -> Dictionary:
	var samples: Array = flight.get("samples", [])
	if samples.size() < 2 or not should_track(player, ball): return {}
	var fault_time: float = predicted_fault_time(player, ball, flight)
	var best: Dictionary = {}
	var best_score := INF
	var flight_bounds := AABB(samples[0].pos, Vector3.ZERO)
	for index in range(1, mini(samples.size(), 60)):
		flight_bounds = flight_bounds.expand(samples[index].pos)
	for base in PostureLibrary.instance().all_definitions():
		if not base.has_zone: continue
		var shoulder: Vector3 = Body.shoulder_world(player, base)
		if shoulder.distance_squared_to(shoulder.clamp(flight_bounds.position, flight_bounds.end)) > PaddleReach.MAX_HEAD_DISTANCE * PaddleReach.MAX_HEAD_DISTANCE: continue
		var wrist_offset: Vector3 = WristReach.head_to_wrist_offset(Path.paddle_basis(player, base), base)
		for index in range(mini(samples.size() - 1, 59)):
			var a: Dictionary = samples[index]
			var b: Dictionary = samples[index + 1]
			if a.bounces != b.bounces or not legal_ball(player, ball, int(b.bounces), volley_override): continue
			if require_bounce and int(b.bounces) + ball.bounces_since_last_hit == 0: continue
			if float(a.time) >= fault_time: break
			var reach_interval: Vector2 = _clip_sphere(a.pos - shoulder, b.pos - a.pos, PaddleReach.MAX_HEAD_DISTANCE, Vector2(0.0, 1.0))
			if reach_interval.x > reach_interval.y: continue
			# Existing sampled extended candidates already handle balanced lean.
			# Keep this fast swept fallback on the authored body, so scanning a
			# distant miss does not allocate a posture clone per physics segment.
			for def: PostureDefinition in [base]:
				var fraction: float = _segment_reach_fraction(player, def, a.pos, b.pos, shoulder, wrist_offset)
				if fraction < 0.0: continue
				var point: Vector3 = a.pos.lerp(b.pos, fraction)
				var time: float = lerpf(a.time, b.time, fraction)
				if time >= fault_time or not point_fits(player, def, point): continue
				var rest: Vector3 = player.global_position + base.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
				var score: float = time + rest.distance_to(point) * 0.08 - (0.025 if base.posture_id == previous_id else 0.0)
				if score > best_score or score == best_score and not best.is_empty() and base.posture_id >= int(best.posture): continue
				var pose: PostureDefinition = pose_at(player, def, point)
				pose.set_meta("extended_reach", true)
				best_score = score
				best = {"point": point, "time": time, "bounces": int(b.bounces), "posture": base.posture_id, "def": pose, "score": score, "extended": true, "swept_prediction": true}
	return best

static func _segment_reach_fraction(player, def: PostureDefinition, a: Vector3, b: Vector3, shoulder: Vector3 = Vector3.INF, wrist_offset: Vector3 = Vector3.ZERO) -> float:
	var origin: Vector3 = a - player.global_position
	var step: Vector3 = b - a
	var forehand: Vector3 = player._get_forehand_axis()
	var forward: Vector3 = player._get_forward_axis()
	var local := Vector3(origin.dot(forehand), a.y - player.COURT_FLOOR_Y, origin.dot(forward))
	var delta := Vector3(step.dot(forehand), step.y, step.dot(forward))
	var best := INF
	for rect: Rect2 in ActivationZones.regions_for(def, CONTACT_MARGIN):
		var interval := Vector2(0.0, 1.0)
		var minimum := Vector3(rect.position.x, maxf(rect.position.y, def.paddle_floor_clearance), 0.08)
		var maximum := Vector3(rect.end.x, rect.end.y, 1.2)
		for axis in range(3):
			interval = _clip_axis(local[axis], delta[axis], minimum[axis], maximum[axis], interval)
			if interval.x > interval.y: break
		if interval.x > interval.y: continue
		if not shoulder.is_finite():
			shoulder = Body.shoulder_world(player, def)
			wrist_offset = WristReach.head_to_wrist_offset(Path.paddle_basis(player, def), def)
		interval = _clip_sphere(a - shoulder, step, PaddleReach.MAX_HEAD_DISTANCE, interval)
		if interval.x > interval.y: continue
		interval = _clip_sphere(a + wrist_offset - shoulder, step, WristReach.link_budget(player, def) + WristReach.NUMERICAL_EPSILON, interval)
		if interval.x > interval.y: continue
		# Nudge inward to avoid a floating-point-only rejection at an exact sphere.
		best = minf(best, minf(interval.x + 0.00001, (interval.x + interval.y) * 0.5))
	return -1.0 if is_inf(best) else best

static func _clip_axis(origin: float, delta: float, minimum: float, maximum: float, interval: Vector2) -> Vector2:
	if absf(delta) < 0.0000001:
		return interval if origin >= minimum - ActivationZones.EDGE_EPSILON and origin <= maximum + ActivationZones.EDGE_EPSILON else Vector2(1.0, -1.0)
	var a: float = (minimum - origin) / delta
	var b: float = (maximum - origin) / delta
	return Vector2(maxf(interval.x, minf(a, b)), minf(interval.y, maxf(a, b)))

static func _clip_sphere(origin: Vector3, delta: Vector3, radius: float, interval: Vector2) -> Vector2:
	var a: float = delta.length_squared()
	var c: float = origin.length_squared() - radius * radius
	if a < 0.000000000001: return interval if c <= 0.0 else Vector2(1.0, -1.0)
	var b: float = 2.0 * origin.dot(delta)
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0: return Vector2(1.0, -1.0)
	var root: float = sqrt(discriminant)
	return Vector2(maxf(interval.x, (-b - root) / (2.0 * a)), minf(interval.y, (-b + root) / (2.0 * a)))

static func legal_contact(player, ball) -> bool:
	if not legal_ball(player, ball): return false
	if wall_mode(ball): return true
	var own_side: float = 1.0 if player.court_side == 0 else -1.0
	if ball.global_position.z * own_side >= ball.BALL_RADIUS - 0.000001: return true
	# A ball which bounced on this player's side may spin/blow back across
	# the plane. That exception requires observed flight and bounce history.
	return "receiver_entire_ball_crossed" in ball and ball.receiver_entire_ball_crossed and ball.receiver_side_bounced and ball.receiver_returned_across_net and ball.bounces_since_last_hit == 1
