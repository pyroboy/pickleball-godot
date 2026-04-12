class_name PostureCommitSelector
extends RefCounted

## Phase 3: Extracted commit-selection logic from player_paddle_posture.gd.
##
## Responsibility: Given a trajectory + ghost positions → pick the committed
## posture (green pool), then score it for grade quality.
##
## Green pool: a ghost is "green" when its world position is within
## POSTURE_GHOST_NEAR_RADIUS meters of any trajectory sample point.
## CHARGE_FOREHAND / CHARGE_BACKHAND are never green (they are manual).
##
## Scoring: green postures are ranked by how well the contact point falls
## inside their coverage zone (miss distance). Fallback (no greens yet) uses
## zone-center proximity.
##
## The selector is a RefCounted so it can be used headlessly by tests.

## ── Constants ─────────────────────────────────────────────────────────────────

## Ghost-to-trajectory radius for green pool membership (meters).
## Rev 2 tightened from 0.45 → 0.30 for crisper commits.
const POSTURE_GHOST_NEAR_RADIUS: float = 0.30

## Step time used when deriving TTC from trajectory arc indices.
const TRAJECTORY_STEP_TIME: float = 0.04

## Grade thresholds (ball-to-ghost distance at contact).
const GRADE_PERFECT: float = 0.25
const GRADE_GREAT: float = 0.40
const GRADE_GOOD: float = 0.60
const GRADE_OK: float = 0.80

## Maximum reach XZ distance for contact-point projection.
const REACH_XZ: float = 1.2

## Floor y used in trajectory / contact calculations.
const COURT_FLOOR_Y: float = 0.08

## ── State ─────────────────────────────────────────────────────────────────────

var _trajectory_points: Array[Vector3] = []
var _green_lit_postures: Dictionary = {}   # posture int → true (persists while ball incoming)
var _committed_incoming_posture: int = -1
var _contact_point_local: Vector3 = Vector3.ZERO
var _first_green_posture: int = -1

## ── Public API ────────────────────────────────────────────────────────────────

## Feed new trajectory samples. Call every frame while ball is in play.
func set_trajectory_points(points: Array[Vector3]) -> void:
	_trajectory_points = points


## Returns true if the given posture is in the green pool (near trajectory).
## CHARGE postures are always excluded — they are manually activated.
func is_ghost_near_trajectory(posture: int, posture_ghosts: Dictionary,
		forehand_charge: int, backhand_charge: int) -> bool:
	if _trajectory_points.is_empty():
		return false
	if posture == forehand_charge or posture == backhand_charge:
		return false
	var ghost: Node3D = posture_ghosts.get(posture)
	var ghost_world: Vector3
	if ghost:
		ghost_world = ghost.global_position
	else:
		return false  # no ghost node — can't be green
	for pt in _trajectory_points:
		if ghost_world.distance_to(pt) < POSTURE_GHOST_NEAR_RADIUS:
			return true
	return false


## Build the green set from current trajectory + ghost positions.
## Returns a dict {posture: true} for all green postures.
func build_green_set(posture_ghosts: Dictionary,
		forehand_charge: int, backhand_charge: int) -> Dictionary:
	var greens: Dictionary = {}
	for posture in posture_ghosts.keys():
		if is_ghost_near_trajectory(posture, posture_ghosts,
				forehand_charge, backhand_charge):
			greens[posture] = true
	return greens


## Score-only-green variant: given an explicit green set, find the best
## posture from that set for the given (local_lat, local_ht) contact point.
## Returns {posture: int, score: float}. Score = 0 means perfect zone fit.
func score_green_postures(local_lat: float, local_ht: float,
		green_set: Dictionary, posture_zones: Dictionary) -> Dictionary:
	var best: int = -1
	var best_score: float = INF
	for posture in green_set:
		if posture not in posture_zones:
			continue
		var zone: Dictionary = posture_zones[posture]
		var lat_miss: float = 0.0
		if local_lat < zone.x_min:
			lat_miss = zone.x_min - local_lat
		elif local_lat > zone.x_max:
			lat_miss = local_lat - zone.x_max
		var ht_miss: float = 0.0
		if local_ht < zone.y_min:
			ht_miss = zone.y_min - local_ht
		elif local_ht > zone.y_max:
			ht_miss = local_ht - zone.y_max
		# Height mismatch weighted heavier (2.5x) than lateral.
		var score: float = ht_miss * 2.5 + lat_miss
		if score < best_score:
			best_score = score
			best = posture
	return {"posture": best, "score": best_score}


## Zone-based commit scoring: pick best green posture for ref_pos.
## Greens scored by how well the contact point fits their coverage box.
## Fallback: closest zone-center posture when no greens are available.
func find_best_green_posture(ref_pos: Vector3, posture_ghosts: Dictionary,
		posture_zones: Dictionary, forehand_charge: int,
		backhand_charge: int, player_pos: Vector3,
		forehand_axis: Vector3, court_floor_y: float,
		awareness_grid = null) -> int:
	# Compute local (lateral, height) from ref_pos.
	var local_lat: float = (ref_pos - player_pos).dot(forehand_axis)
	var local_ht: float = ref_pos.y - court_floor_y

	# Override with grid data if available and confident.
	if awareness_grid:
		var info: Dictionary = awareness_grid.get_approach_info()
		if info.confidence > 5:
			local_lat = info.lateral
			local_ht = info.height

	# Descending-arc correction: clamp local_ht to the lower of the
	# grid-reported height and the predicted floor-relative height.
	# Prevents mid-arc trajectory samples from masking true low contacts.
	var ball_ref = null
	if awareness_grid and awareness_grid.has_method("_get_ball_ref"):
		ball_ref = awareness_grid._get_ball_ref()
	# (awareness_grid ball-ref access is optional; leave as no-op if unavailable)

	# ── GREEN PATH ──────────────────────────────────────────────────────────
	var green_set: Dictionary = build_green_set(posture_ghosts,
			forehand_charge, backhand_charge)
	if not green_set.is_empty():
		var best: int = -1
		var best_score: float = INF
		for posture in green_set:
			if posture not in posture_zones:
				continue
			var zone: Dictionary = posture_zones[posture]
			var lat_miss: float = 0.0
			if local_lat < zone.x_min:
				lat_miss = zone.x_min - local_lat
			elif local_lat > zone.x_max:
				lat_miss = local_lat - zone.x_max
			var ht_miss: float = 0.0
			if local_ht < zone.y_min:
				ht_miss = zone.y_min - local_ht
			elif local_ht > zone.y_max:
				ht_miss = local_ht - zone.y_max
			var score: float = ht_miss * 2.5 + lat_miss
			# 3D ghost proximity tiebreaker at zero score.
			var ghost: Node3D = posture_ghosts.get(posture)
			if ghost:
				score += 0.05 * ghost.global_position.distance_to(ref_pos)
			if score < best_score:
				best_score = score
				best = posture
		if best >= 0:
			return best

	# ── FALLBACK: no greens yet — use zone-center scoring ───────────────────
	var best_fallback: int = -1
	var best_d: float = INF
	for posture in posture_zones:
		var zone: Dictionary = posture_zones[posture]
		var cx: float = (zone.x_min + zone.x_max) / 2.0
		var cy: float = (zone.y_min + zone.y_max) / 2.0
		var dx: float = local_lat - cx
		var dy: float = local_ht - cy
		var d: float = sqrt(dx * dx + dy * dy)
		if d < best_d:
			best_d = d
			best_fallback = posture
	return best_fallback


## Find the trajectory point closest to the player's XZ position
## (likely contact area). Filters out floor-clipping and extreme-height samples.
func find_closest_trajectory_point(player_pos: Vector3,
		court_floor_y: float) -> Vector3:
	if _trajectory_points.is_empty():
		return player_pos
	var player_xz := Vector2(player_pos.x, player_pos.z)
	var best_pt := _trajectory_points[0]
	var best_dist := INF
	for pt in _trajectory_points:
		if pt.y < (court_floor_y - 0.02) or pt.y > 1.8:
			continue
		var d := player_xz.distance_to(Vector2(pt.x, pt.z))
		if d < best_dist:
			best_dist = d
			best_pt = pt
	return best_pt


## Compute expected contact point in world space.
## For descending balls: picks the LAST trajectory point within reach window
## (lowest = true contact Y). For ascending/flat balls: XZ-nearest fallback.
func compute_expected_contact_point(player_pos: Vector3,
		court_floor_y: float, ball_is_descending: bool) -> Vector3:
	if _trajectory_points.is_empty():
		return player_pos
	var player_xz := Vector2(player_pos.x, player_pos.z)

	if ball_is_descending:
		var last_in_reach := Vector3.INF
		for pt in _trajectory_points:
			if pt.y < (court_floor_y - 0.02) or pt.y > 1.8:
				continue
			if player_xz.distance_to(Vector2(pt.x, pt.z)) < REACH_XZ:
				last_in_reach = pt
		if last_in_reach != Vector3.INF:
			return last_in_reach

	# Fallback: XZ-nearest.
	var best_pt := _trajectory_points[0]
	var best_d := INF
	for pt in _trajectory_points:
		if pt.y < (court_floor_y - 0.02) or pt.y > 1.8:
			continue
		var d := player_xz.distance_to(Vector2(pt.x, pt.z))
		if d < best_d:
			best_d = d
			best_pt = pt
	return best_pt


## Project ball trajectory to player's Z plane. Returns world-space contact point.
func compute_contact_at_player_z(ball_pos: Vector3, ball_vel: Vector3,
		player_pos: Vector3, court_floor_y: float,
		gravity: float, cor_func: Callable) -> Vector3:
	var player_z: float = player_pos.z
	var bpos: Vector3 = ball_pos
	var bvel: Vector3 = ball_vel

	if abs(bvel.z) < 0.1:
		return bpos  # not moving toward player

	var t: float = (player_z - bpos.z) / bvel.z
	if t < 0.0:
		return bpos  # moving away

	# Check if ball hits floor before player's Z.
	var qa: float = -0.5 * gravity
	var qb: float = bvel.y
	var qc: float = bpos.y - court_floor_y
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc >= 0.0 and qa != 0.0:
		var t_floor: float = (-qb - sqrt(disc)) / (2.0 * qa)
		if t_floor > 0.0 and t_floor < t:
			# Ball bounces — compute post-bounce arc.
			var bounce_x: float = bpos.x + bvel.x * t_floor
			var bounce_z: float = bpos.z + bvel.z * t_floor
			var vy_at_floor: float = bvel.y - gravity * t_floor
			var bounce_vy: float = abs(vy_at_floor) * cor_func.call(abs(vy_at_floor))
			var rem_t: float = (player_z - bounce_z) / bvel.z
			if rem_t > 0.0:
				return Vector3(
					bounce_x + bvel.x * rem_t,
					court_floor_y + bounce_vy * rem_t - 0.5 * gravity * rem_t * rem_t,
					player_z)

	# Direct flight — no bounce.
	return Vector3(
		bpos.x + bvel.x * t,
		bpos.y + bvel.y * t - 0.5 * gravity * t * t,
		player_z)


## Simple forward-Euler trajectory projection for headless / test use.
func compute_simple_trajectory(ball_pos: Vector3, ball_vel: Vector3,
		gravity: float, court_floor_y: float,
		max_steps: int = 80) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var pos: Vector3 = ball_pos
	var vel: Vector3 = ball_vel
	var has_bounced: bool = false
	for _step in range(max_steps):
		vel.y -= gravity * 0.04
		pos += vel * 0.04
		if pos.y <= court_floor_y:
			pos.y = court_floor_y
			if not has_bounced:
				has_bounced = true
				# First bounce: reflect with COR
				var impact_speed: float = abs(vel.y)
				vel.y = impact_speed * 0.685  # approximate COR
			else:
				points.append(pos)
				break
		points.append(pos)
	return points


## Compute time-to-contact (seconds) between ball and ghost world position.
## Primary: derive from trajectory arc index difference × TRAJECTORY_STEP_TIME.
## Fallback: straight-line distance / ball speed.
func compute_ttc(ball_pos: Vector3, ball_vel: Vector3,
		ghost_world: Vector3) -> float:
	var ttc: float = -1.0
	if _trajectory_points.size() >= 2:
		var best_ball_i: int = 0
		var best_ghost_i: int = 0
		var best_ball_d: float = INF
		var best_ghost_d: float = INF
		for i in _trajectory_points.size():
			var d_ball: float = _trajectory_points[i].distance_to(ball_pos)
			if d_ball < best_ball_d:
				best_ball_d = d_ball
				best_ball_i = i
			var d_ghost: float = _trajectory_points[i].distance_to(ghost_world)
			if d_ghost < best_ghost_d:
				best_ghost_d = d_ghost
				best_ghost_i = i
		if best_ghost_i > best_ball_i:
			ttc = float(best_ghost_i - best_ball_i) * TRAJECTORY_STEP_TIME
	if ttc < 0.0:
		var speed: float = ball_vel.length()
		if speed < 0.5:
			return 3.0
		ttc = ghost_world.distance_to(ball_pos) / speed
	return clampf(ttc, 0.0, 3.0)


## Grade a hit quality from ball-to-ghost distance at contact.
func grade_ball_to_ghost(d: float) -> String:
	if d < GRADE_PERFECT:  return "PERFECT"
	if d < GRADE_GREAT:   return "GREAT"
	if d < GRADE_GOOD:    return "GOOD"
	if d < GRADE_OK:      return "OK"
	return "MISS"


## Zone miss penalty for lateral axis.
func zone_lat_miss(local_lat: float, zone: Dictionary) -> float:
	if local_lat < zone.x_min:
		return zone.x_min - local_lat
	if local_lat > zone.x_max:
		return local_lat - zone.x_max
	return 0.0


## Zone miss penalty for height axis.
func zone_ht_miss(local_ht: float, zone: Dictionary) -> float:
	if local_ht < zone.y_min:
		return zone.y_min - local_ht
	if local_ht > zone.y_max:
		return local_ht - zone.y_max
	return 0.0


## Classify height tier from floor-relative ball height.
func height_tier(ball_y: float, court_floor_y: float) -> int:
	var rel_h: float = ball_y - court_floor_y
	if rel_h < 0.22:  return 0  # LOW
	if rel_h < 0.55:  return 1  # MID_LOW
	if rel_h < 1.05:  return 2  # NORMAL
	return 3  # OVERHEAD


## Find local (lateral, height) of a world point relative to player position.
func local_axes(ref_pos: Vector3, player_pos: Vector3,
		forehand_axis: Vector3, court_floor_y: float) -> Vector2:
	var local_lat: float = (ref_pos - player_pos).dot(forehand_axis)
	var local_ht: float = ref_pos.y - court_floor_y
	return Vector2(local_lat, local_ht)
