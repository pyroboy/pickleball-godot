extends RefCounted
## Headless tests for posture zone classification and scoring.
##
## Tests cover:
##   1. Zone boundary — every defined zone contains its authored (center) point
##   2. Height-tier threshold — LOW / MID_LOW / NORMAL / OVERHEAD boundaries
##   3. Green-pool scoring — only green postures score; non-greens are ignored
##   4. Scoring rubric — PERFECT/GREAT/GOOD/OK/MISS grade boundaries
##   5. Posture family — forehand/backhand/center/overhead classification
##
## Run:
##   godot --headless --path . --script res://scripts/tests/test_posture_zones.gd

# ── Helpers ────────────────────────────────────────────────────────────────────

class ZoneFakePlayer extends RefCounted:
	var player_num := 0
	var global_position := Vector3.ZERO
	var current_velocity := Vector3.ZERO
	var paddle_posture: int = 0
	var paddle_world_pos := Vector3.ZERO

	enum PaddlePosture {
		FOREHAND = 0, FORWARD = 1, BACKHAND = 2,
		MEDIUM_OVERHEAD = 3, HIGH_OVERHEAD = 4,
		LOW_FOREHAND = 5, LOW_FORWARD = 6, LOW_BACKHAND = 7,
		CHARGE_FOREHAND = 8, CHARGE_BACKHAND = 9,
		WIDE_FOREHAND = 10, WIDE_BACKHAND = 11,
		VOLLEY_READY = 12,
		MID_LOW_FOREHAND = 13, MID_LOW_BACKHAND = 14, MID_LOW_FORWARD = 15,
		MID_LOW_WIDE_FOREHAND = 16, MID_LOW_WIDE_BACKHAND = 17,
		LOW_WIDE_FOREHAND = 18, LOW_WIDE_BACKHAND = 19,
		READY = 20,
	}

	const FOREHAND_FAMILY := 0
	const BACKHAND_FAMILY := 1
	const CENTER_FAMILY := 2
	const OVERHEAD_FAMILY := 3

	func _get_forehand_axis() -> Vector3:
		return Vector3.RIGHT if player_num == 0 else Vector3.LEFT

	func _get_forward_axis() -> Vector3:
		return Vector3.FORWARD

	func to_local(world_pos: Vector3) -> Vector3:
		# Simplified: assumes player at origin facing forward
		return world_pos - global_position

	func get_paddle_position() -> Vector3:
		return paddle_world_pos


## ── Zone data (mirrors player_paddle_posture.gd:_init_posture_zones) ──────────

const NORMAL_ZONES := {
	ZoneFakePlayer.PaddlePosture.FOREHAND:        {"x_min": 0.2,  "x_max": 0.55, "y_min": 0.5,  "y_max": 1.0},
	ZoneFakePlayer.PaddlePosture.BACKHAND:        {"x_min": -0.55, "x_max": -0.2, "y_min": 0.5,  "y_max": 1.0},
	ZoneFakePlayer.PaddlePosture.WIDE_FOREHAND:   {"x_min": 0.5,   "x_max": 1.1,  "y_min": 0.48, "y_max": 1.0},
	ZoneFakePlayer.PaddlePosture.WIDE_BACKHAND:   {"x_min": -1.1,  "x_max": -0.5, "y_min": 0.48, "y_max": 1.0},
	ZoneFakePlayer.PaddlePosture.FORWARD:          {"x_min": -0.15, "x_max": 0.15, "y_min": 0.5,  "y_max": 1.0},
	ZoneFakePlayer.PaddlePosture.VOLLEY_READY:    {"x_min": -0.2,  "x_max": 0.2,  "y_min": 0.55, "y_max": 0.9},
	ZoneFakePlayer.PaddlePosture.MEDIUM_OVERHEAD: {"x_min": -0.35, "x_max": 0.35, "y_min": 0.8,  "y_max": 1.3},
	ZoneFakePlayer.PaddlePosture.HIGH_OVERHEAD:   {"x_min": -0.35, "x_max": 0.35, "y_min": 1.1,  "y_max": 1.8},
}

const MID_LOW_ZONES := {
	ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND:      {"x_min": 0.2,  "x_max": 0.55, "y_min": 0.15, "y_max": 0.52},
	ZoneFakePlayer.PaddlePosture.MID_LOW_BACKHAND:      {"x_min": -0.55,"x_max": -0.2, "y_min": 0.15, "y_max": 0.52},
	ZoneFakePlayer.PaddlePosture.MID_LOW_FORWARD:       {"x_min": -0.15,"x_max": 0.15, "y_min": 0.15, "y_max": 0.52},
	ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_FOREHAND: {"x_min": 0.5,  "x_max": 1.1,  "y_min": 0.1,  "y_max": 0.50},
	ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_BACKHAND: {"x_min": -1.1, "x_max": -0.5, "y_min": 0.1,  "y_max": 0.50},
}

const LOW_ZONES := {
	ZoneFakePlayer.PaddlePosture.LOW_FOREHAND:      {"x_min": 0.2,  "x_max": 0.55, "y_min": -0.2, "y_max": 0.2},
	ZoneFakePlayer.PaddlePosture.LOW_BACKHAND:      {"x_min": -0.55,"x_max": -0.2, "y_min": -0.2, "y_max": 0.2},
	ZoneFakePlayer.PaddlePosture.LOW_FORWARD:       {"x_min": -0.15,"x_max": 0.15, "y_min": -0.2, "y_max": 0.2},
	ZoneFakePlayer.PaddlePosture.LOW_WIDE_FOREHAND: {"x_min": 0.5,  "x_max": 1.1,  "y_min": -0.2, "y_max": 0.15},
	ZoneFakePlayer.PaddlePosture.LOW_WIDE_BACKHAND: {"x_min": -1.1, "x_max": -0.5, "y_min": -0.2, "y_max": 0.15},
}

var ALL_ZONES := {}


func _init() -> void:
	for d in [NORMAL_ZONES, MID_LOW_ZONES, LOW_ZONES]:
		for k in d:
			ALL_ZONES[k] = d[k]


# ── Core scoring logic (copied from player_paddle_posture.gd) ──────────────────

## Returns miss penalty (0 = inside zone) for lateral axis.
func _zone_lat_miss(local_lat: float, zone: Dictionary) -> float:
	if local_lat < zone.x_min:
		return zone.x_min - local_lat
	if local_lat > zone.x_max:
		return local_lat - zone.x_max
	return 0.0


## Returns miss penalty (0 = inside zone) for height axis.
func _zone_ht_miss(local_ht: float, zone: Dictionary) -> float:
	if local_ht < zone.y_min:
		return zone.y_min - local_ht
	if local_ht > zone.y_max:
		return local_ht - zone.y_max
	return 0.0


## Score a posture: lower is better.  Inf = completely outside zone.
func _score_posture(local_lat: float, local_ht: float, posture: int) -> float:
	var zone: Dictionary = ALL_ZONES.get(posture, {})
	if zone.is_empty():
		return INF
	var lat_miss := _zone_lat_miss(local_lat, zone)
	var ht_miss := _zone_ht_miss(local_ht, zone)
	return lat_miss + ht_miss


## Grade from ball2ghost distance.
func _grade_ball2ghost(d: float) -> String:
	if d < 0.25:  return "PERFECT"
	if d < 0.40:  return "GREAT"
	if d < 0.60:  return "GOOD"
	if d < 0.80:  return "OK"
	return "MISS"


## Classify posture family.
func _posture_family(p: int) -> int:
	match p:
		ZoneFakePlayer.PaddlePosture.FOREHAND, \
		ZoneFakePlayer.PaddlePosture.LOW_FOREHAND, \
		ZoneFakePlayer.PaddlePosture.WIDE_FOREHAND, \
		ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND, \
		ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_FOREHAND, \
		ZoneFakePlayer.PaddlePosture.LOW_WIDE_FOREHAND, \
		ZoneFakePlayer.PaddlePosture.CHARGE_FOREHAND:
			return ZoneFakePlayer.FOREHAND_FAMILY
		ZoneFakePlayer.PaddlePosture.BACKHAND, \
		ZoneFakePlayer.PaddlePosture.LOW_BACKHAND, \
		ZoneFakePlayer.PaddlePosture.WIDE_BACKHAND, \
		ZoneFakePlayer.PaddlePosture.MID_LOW_BACKHAND, \
		ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_BACKHAND, \
		ZoneFakePlayer.PaddlePosture.LOW_WIDE_BACKHAND, \
		ZoneFakePlayer.PaddlePosture.CHARGE_BACKHAND:
			return ZoneFakePlayer.BACKHAND_FAMILY
		ZoneFakePlayer.PaddlePosture.MEDIUM_OVERHEAD, \
		ZoneFakePlayer.PaddlePosture.HIGH_OVERHEAD:
			return ZoneFakePlayer.OVERHEAD_FAMILY
		_:
			return ZoneFakePlayer.CENTER_FAMILY


## Height tier from ball Y (world space, relative to COURT_FLOOR_Y=0.075).
func _height_tier(ball_y: float) -> int:
	# Constants mirror player_paddle_posture.gd thresholds
	if ball_y < 0.22:  return 0  # LOW
	if ball_y < 0.55:  return 1  # MID_LOW
	if ball_y < 1.0:  return 2  # NORMAL
	return 3  # OVERHEAD


## Score-only-green-postures: like the green-pool scorer, but with a mock green set.
func _score_green_pool(local_lat: float, local_ht: float, green_set: Array[int]) -> Dictionary:
	var best: int = -1
	var best_score: float = INF
	for posture in green_set:
		var s: float = _score_posture(local_lat, local_ht, posture)
		if s < best_score:
			best_score = s
			best = posture
	return {"posture": best, "score": best_score}


## Fallback scoring: scores ALL postures and picks closest to zone center.
func _score_fallback(local_lat: float, local_ht: float) -> Dictionary:
	var best: int = -1
	var best_d: float = INF
	for posture in ALL_ZONES:
		var zone: Dictionary = ALL_ZONES[posture]
		var cx: float = (zone.x_min + zone.x_max) / 2.0
		var cy: float = (zone.y_min + zone.y_max) / 2.0
		var dx: float = local_lat - cx
		var dy: float = local_ht - cy
		var d: float = sqrt(dx * dx + dy * dy)
		if d < best_d:
			best_d = d
			best = posture
	return {"posture": best, "dist": best_d}


# ── Assertion helper ───────────────────────────────────────────────────────────

func _assert(condition: bool, label: String, totals: Dictionary) -> void:
	if condition:
		totals.pass += 1
	else:
		totals.fail += 1
		totals.errors.append(label)


func _assert_eq_int(a: int, b: int, label: String, totals: Dictionary) -> void:
	_assert(a == b, "%s (got %d, expected %d)" % [label, a, b], totals)


func _assert_eq_float(a: float, b: float, eps: float, label: String, totals: Dictionary) -> void:
	_assert(absf(a - b) <= eps, "%s (got %.4f, expected %.4f)" % [label, a, b], totals)


func _assert_eq_str(a: String, b: String, label: String, totals: Dictionary) -> void:
	_assert(a == b, "%s (got '%s', expected '%s')" % [label, a, b], totals)


# ── Test: run_all ─────────────────────────────────────────────────────────────

func run_all(totals: Dictionary) -> void:
	print("\n━━━ Posture Zone Tests ━━━")
	_test_zone_centers_contained(totals)
	_test_height_tier_boundaries(totals)
	_test_height_tier_classification_examples(totals)
	_test_green_pool_only_scores_greens(totals)
	_test_green_pool_ignores_non_greens(totals)
	_test_green_pool_tie_break_by_lat(totals)
	_test_scoring_rubric_boundaries(totals)
	_test_scoring_rubric_golden_cases(totals)
	_test_posture_family_forehand(totals)
	_test_posture_family_backhand(totals)
	_test_posture_family_center(totals)
	_test_posture_family_overhead(totals)
	_test_fallback_scores_all_zones(totals)
	_test_fallback_picks_closest_center(totals)
	_test_zone_edge_misses(totals)
	_test_low_zone_ball_at_ground(totals)
	_test_mid_low_zone_bridges_normal_and_low(totals)


# ── Test 1: every zone contains its authored center point ──────────────────────

func _test_zone_centers_contained(totals: Dictionary) -> void:
	var failures := 0
	for posture in ALL_ZONES:
		var zone: Dictionary = ALL_ZONES[posture]
		var cx: float = (zone.x_min + zone.x_max) / 2.0
		var cy: float = (zone.y_min + zone.y_max) / 2.0
		var lat_miss := _zone_lat_miss(cx, zone)
		var ht_miss := _zone_ht_miss(cy, zone)
		if lat_miss > 0.0 or ht_miss > 0.0:
			failures += 1
			print("  FAIL: posture %d center (%.3f, %.3f) outside zone" % [posture, cx, cy])
	_assert(failures == 0, "all zone centers self-contained", totals)


# ── Test 2: height tier thresholds ─────────────────────────────────────────────

func _test_height_tier_boundaries(totals: Dictionary) -> void:
	_assert_eq_int(_height_tier(0.0),  0, "y=0.0  → LOW",      totals)
	_assert_eq_int(_height_tier(0.21), 0, "y=0.21 → LOW",      totals)
	_assert_eq_int(_height_tier(0.22), 1, "y=0.22 → MID_LOW",  totals)
	_assert_eq_int(_height_tier(0.30), 1, "y=0.30 → MID_LOW",  totals)
	_assert_eq_int(_height_tier(0.54), 1, "y=0.54 → MID_LOW",  totals)
	_assert_eq_int(_height_tier(0.55), 2, "y=0.55 → NORMAL",   totals)
	_assert_eq_int(_height_tier(0.70), 2, "y=0.70 → NORMAL",   totals)
	_assert_eq_int(_height_tier(0.99), 2, "y=0.99 → NORMAL",   totals)
	_assert_eq_int(_height_tier(1.00), 3, "y=1.00 → OVERHEAD", totals)
	_assert_eq_int(_height_tier(1.50), 3, "y=1.50 → OVERHEAD", totals)


# ── Test 3: height tier classification examples ─────────────────────────────────

func _test_height_tier_classification_examples(totals: Dictionary) -> void:
	# LOW-tier postures should be returned for very low balls
	var score_low := _score_posture(0.3, 0.05, ZoneFakePlayer.PaddlePosture.LOW_FOREHAND)
	var score_norm := _score_posture(0.3, 0.05, ZoneFakePlayer.PaddlePosture.FOREHAND)
	_assert(score_low < score_norm,
		"LOW posture scores better than NORMAL for low ball", totals)

	# MID_LOW tier
	var score_ml := _score_posture(0.3, 0.35, ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND)
	var score_n := _score_posture(0.3, 0.35, ZoneFakePlayer.PaddlePosture.FOREHAND)
	_assert(score_ml < score_n,
		"MID_LOW posture scores better than NORMAL for mid-low ball", totals)

	# NORMAL tier
	var score_nor := _score_posture(0.3, 0.70, ZoneFakePlayer.PaddlePosture.FOREHAND)
	var score_mid := _score_posture(0.3, 0.70, ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND)
	_assert(score_nor < score_mid,
		"NORMAL posture scores better than MID_LOW for normal-height ball", totals)


# ── Test 4: green pool only scores postures in the green set ──────────────────

func _test_green_pool_only_scores_greens(totals: Dictionary) -> void:
	# Only LOW_FOREHAND is green
	var result := _score_green_pool(0.3, 0.05, [ZoneFakePlayer.PaddlePosture.LOW_FOREHAND])
	_assert_eq_int(result.posture, ZoneFakePlayer.PaddlePosture.LOW_FOREHAND,
		"green pool returns LOW_FOREHAND when it's the only green", totals)
	_assert(result.score < INF, "score is finite", totals)


# ── Test 5: non-greens return INF / best posture stays -1 ────────────────────

func _test_green_pool_ignores_non_greens(totals: Dictionary) -> void:
	# Only NORMAL posture green, but ball is at low height — normal zone
	# should give a high miss score
	var result := _score_green_pool(0.3, 0.05, [ZoneFakePlayer.PaddlePosture.FOREHAND])
	_assert_eq_int(result.posture, ZoneFakePlayer.PaddlePosture.FOREHAND,
		"green pool still returns the green even if score is high", totals)
	_assert(result.score > 0.3,
		"LOW ball in NORMAL zone produces non-zero miss penalty", totals)


# ── Test 6: green pool tie-break by lateral position ─────────────────────────

func _test_green_pool_tie_break_by_lat(totals: Dictionary) -> void:
	# Forehand side (positive lat) → should pick FH over BH
	var result := _score_green_pool(0.35, 0.7,
		[ZoneFakePlayer.PaddlePosture.FOREHAND, ZoneFakePlayer.PaddlePosture.BACKHAND])
	_assert_eq_int(result.posture, ZoneFakePlayer.PaddlePosture.FOREHAND,
		"forehand lateral picks forehand posture", totals)

	# Backhand side (negative lat)
	var result2 := _score_green_pool(-0.35, 0.7,
		[ZoneFakePlayer.PaddlePosture.FOREHAND, ZoneFakePlayer.PaddlePosture.BACKHAND])
	_assert_eq_int(result2.posture, ZoneFakePlayer.PaddlePosture.BACKHAND,
		"backhand lateral picks backhand posture", totals)


# ── Test 7: scoring rubric boundary crossings ──────────────────────────────────

func _test_scoring_rubric_boundaries(totals: Dictionary) -> void:
	_assert_eq_str(_grade_ball2ghost(0.00),  "PERFECT", "d=0.00 → PERFECT", totals)
	_assert_eq_str(_grade_ball2ghost(0.24),  "PERFECT", "d=0.24 → PERFECT", totals)
	_assert_eq_str(_grade_ball2ghost(0.25),  "GREAT",   "d=0.25 → GREAT",   totals)
	_assert_eq_str(_grade_ball2ghost(0.39),  "GREAT",   "d=0.39 → GREAT",   totals)
	_assert_eq_str(_grade_ball2ghost(0.40),  "GOOD",    "d=0.40 → GOOD",    totals)
	_assert_eq_str(_grade_ball2ghost(0.59),  "GOOD",    "d=0.59 → GOOD",    totals)
	_assert_eq_str(_grade_ball2ghost(0.60),  "OK",      "d=0.60 → OK",      totals)
	_assert_eq_str(_grade_ball2ghost(0.79),  "OK",      "d=0.79 → OK",      totals)
	_assert_eq_str(_grade_ball2ghost(0.80),  "MISS",    "d=0.80 → MISS",    totals)
	_assert_eq_str(_grade_ball2ghost(1.50),  "MISS",    "d=1.50 → MISS",    totals)


# ── Test 8: golden cases for rubric ────────────────────────────────────────────

func _test_scoring_rubric_golden_cases(totals: Dictionary) -> void:
	# PERFECT: ball went through the paddle
	_assert_eq_str(_grade_ball2ghost(0.10), "PERFECT",
		"ball through paddle → PERFECT", totals)
	# GREAT: within paddle reach
	_assert_eq_str(_grade_ball2ghost(0.34), "GREAT",
		"within paddle reach → GREAT", totals)
	# GOOD: close, slight adjustment
	_assert_eq_str(_grade_ball2ghost(0.50), "GOOD",
		"slight adjustment needed → GOOD", totals)
	# OK: reachable with stretch
	_assert_eq_str(_grade_ball2ghost(0.70), "OK",
		"reachable with stretch → OK", totals)
	# MISS: wrong posture
	_assert_eq_str(_grade_ball2ghost(0.90), "MISS",
		"wrong posture → MISS", totals)


# ── Test 9-12: posture family ─────────────────────────────────────────────────

func _test_posture_family_forehand(totals: Dictionary) -> void:
	for p in [
		ZoneFakePlayer.PaddlePosture.FOREHAND,
		ZoneFakePlayer.PaddlePosture.LOW_FOREHAND,
		ZoneFakePlayer.PaddlePosture.WIDE_FOREHAND,
		ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND,
		ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_FOREHAND,
		ZoneFakePlayer.PaddlePosture.LOW_WIDE_FOREHAND,
		ZoneFakePlayer.PaddlePosture.CHARGE_FOREHAND,
	]:
		_assert_eq_int(_posture_family(p), ZoneFakePlayer.FOREHAND_FAMILY,
			"posture %d is forehand family" % p, totals)


func _test_posture_family_backhand(totals: Dictionary) -> void:
	for p in [
		ZoneFakePlayer.PaddlePosture.BACKHAND,
		ZoneFakePlayer.PaddlePosture.LOW_BACKHAND,
		ZoneFakePlayer.PaddlePosture.WIDE_BACKHAND,
		ZoneFakePlayer.PaddlePosture.MID_LOW_BACKHAND,
		ZoneFakePlayer.PaddlePosture.MID_LOW_WIDE_BACKHAND,
		ZoneFakePlayer.PaddlePosture.LOW_WIDE_BACKHAND,
		ZoneFakePlayer.PaddlePosture.CHARGE_BACKHAND,
	]:
		_assert_eq_int(_posture_family(p), ZoneFakePlayer.BACKHAND_FAMILY,
			"posture %d is backhand family" % p, totals)


func _test_posture_family_center(totals: Dictionary) -> void:
	for p in [
		ZoneFakePlayer.PaddlePosture.FORWARD,
		ZoneFakePlayer.PaddlePosture.LOW_FORWARD,
		ZoneFakePlayer.PaddlePosture.MID_LOW_FORWARD,
		ZoneFakePlayer.PaddlePosture.VOLLEY_READY,
		ZoneFakePlayer.PaddlePosture.READY,
	]:
		_assert_eq_int(_posture_family(p), ZoneFakePlayer.CENTER_FAMILY,
			"posture %d is center family" % p, totals)


func _test_posture_family_overhead(totals: Dictionary) -> void:
	_assert_eq_int(_posture_family(ZoneFakePlayer.PaddlePosture.MEDIUM_OVERHEAD),
		ZoneFakePlayer.OVERHEAD_FAMILY, "MEDIUM_OVERHEAD is overhead family", totals)
	_assert_eq_int(_posture_family(ZoneFakePlayer.PaddlePosture.HIGH_OVERHEAD),
		ZoneFakePlayer.OVERHEAD_FAMILY, "HIGH_OVERHEAD is overhead family", totals)


# ── Test 13: fallback scores all zones (not just greens) ───────────────────────

func _test_fallback_scores_all_zones(totals: Dictionary) -> void:
	var result := _score_fallback(0.3, 0.7)
	_assert(result.posture >= 0, "fallback returns a valid posture", totals)
	_assert(result.dist >= 0.0, "fallback distance is non-negative", totals)
	_assert(result.dist < INF, "fallback distance is finite", totals)


# ── Test 14: fallback picks closest zone center ─────────────────────────────────

func _test_fallback_picks_closest_center(totals: Dictionary) -> void:
	# Dead center of FOREHAND zone (x=0.375, y=0.75)
	var result := _score_fallback(0.375, 0.75)
	_assert_eq_int(result.posture, ZoneFakePlayer.PaddlePosture.FOREHAND,
		"center of FOREHAND zone picks FOREHAND", totals)
	_assert(result.dist < 0.01,
		"at zone center, distance is near zero", totals)


# ── Test 15: zone edge miss distances ─────────────────────────────────────────

func _test_zone_edge_misses(totals: Dictionary) -> void:
	var zone: Dictionary = ALL_ZONES[ZoneFakePlayer.PaddlePosture.FOREHAND]
	# x below zone
	_assert_eq_float(_zone_lat_miss(0.0, zone), 0.2, 0.001, "x=0.0 (below x_min=0.2) miss=0.2", totals)
	# x inside zone
	_assert_eq_float(_zone_lat_miss(0.35, zone), 0.0, 0.001, "x=0.35 (inside zone) miss=0.0", totals)
	# x above zone
	_assert_eq_float(_zone_lat_miss(0.8, zone), 0.25, 0.001, "x=0.8 (above x_max=0.55) miss=0.25", totals)
	# y below zone
	_assert_eq_float(_zone_ht_miss(0.3, zone), 0.2, 0.001, "y=0.3 (below y_min=0.5) miss=0.2", totals)
	# y inside zone
	_assert_eq_float(_zone_ht_miss(0.75, zone), 0.0, 0.001, "y=0.75 (inside zone) miss=0.0", totals)
	# y above zone
	_assert_eq_float(_zone_ht_miss(1.2, zone), 0.2, 0.001, "y=1.2 (above y_max=1.0) miss=0.2", totals)


# ── Test 16: low zone handles ball at ground level ────────────────────────────

func _test_low_zone_ball_at_ground(totals: Dictionary) -> void:
	# y=-0.1 is well inside LOW zone (y_min=-0.2, y_max=0.2)
	var zone: Dictionary = ALL_ZONES[ZoneFakePlayer.PaddlePosture.LOW_FOREHAND]
	var ht_miss := _zone_ht_miss(-0.1, zone)
	_assert_eq_float(ht_miss, 0.0, 0.001, "y=-0.1 is inside LOW_FOREHAND zone", totals)

	# Same ball is way outside NORMAL zone
	var norm_zone: Dictionary = ALL_ZONES[ZoneFakePlayer.PaddlePosture.FOREHAND]
	var norm_ht_miss := _zone_ht_miss(-0.1, norm_zone)
	_assert(norm_ht_miss > 0.5,
		"y=-0.1 produces large miss in NORMAL zone (%.2f)" % norm_ht_miss, totals)


# ── Test 17: mid-low bridges normal and low ─────────────────────────────────────

func _test_mid_low_zone_bridges_normal_and_low(totals: Dictionary) -> void:
	# y=0.35 is inside MID_LOW_FOREHAND zone (y_min=0.15, y_max=0.52)
	var ml_zone: Dictionary = ALL_ZONES[ZoneFakePlayer.PaddlePosture.MID_LOW_FOREHAND]
	var ml_miss := _zone_ht_miss(0.35, ml_zone)
	_assert_eq_float(ml_miss, 0.0, 0.001, "y=0.35 is inside MID_LOW_FOREHAND zone", totals)

	# But outside LOW_FOREHAND (y_max=0.2)
	var lo_zone: Dictionary = ALL_ZONES[ZoneFakePlayer.PaddlePosture.LOW_FOREHAND]
	var lo_miss := _zone_ht_miss(0.35, lo_zone)
	_assert(lo_miss > 0.1,
		"y=0.35 is outside LOW_FOREHAND zone (miss=%.2f)" % lo_miss, totals)

	# And outside normal FOREHAND (y_min=0.5)
	var norm_zone: Dictionary = ALL_ZONES[FakePlayer.PaddlePosture.FOREHAND]
	var norm_miss := _zone_ht_miss(0.35, norm_zone)
	_assert(norm_miss > 0.1,
		"y=0.35 is outside FOREHAND zone (miss=%.2f)" % norm_miss, totals)
