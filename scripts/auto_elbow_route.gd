extends RefCounted
## Isolated, deterministic elbow-circle route prototype. No scene/node mutation.
##
## bake() consumes one arm's fixed-motion frames in strictly increasing seconds.
## Required frame keys: time, shoulder, wrist, hand_basis (world anatomical Basis),
## upper_length, fore_length, baseline_elbow, is_left. Optional: thumb_up,
## body_geometry (body_clearance.volumes result), obstacles (capsules with a, b,
## radius, label), upper_radius, fore_radius, shoulder_exclude_m.
##
## This is SINGLE ARM planning against supplied obstacles. Optimizing both arms
## independently requires a final pair check; original other-arm capsules cannot
## certify two changed arms. The caller owns exact production pose extraction and
## bypassing post-IK pole conditioning when applying the solved elbow.
##
## Options frame_at: Callable(time)->Dictionary can provide exact source frames at
## validation sub-times. Otherwise validation uses explicitly labelled interpolated
## input geometry. extra_evaluator: Callable(frame, elbow)->Dictionary can add hard
## checks. Both must be deterministic and must not mutate fixed motion.
##
## A passing bake is sampled verification, NOT a proof over continuous time.
## Capsule distances are exact; convex-cell margins are conservative plane bounds.
## Shared monotone cubic Hermite angles never overshoot endpoint angles. We validate
## each used edge at bounded time steps, but have no temporal Lipschitz certificate.

const Anatomy = preload("res://scripts/arm_anatomy.gd")
const VERSION = 1
const EPS = 1.0e-8

static func _options(given: Dictionary) -> Dictionary:
	if bool(given.get("_auto_elbow_prepared", false)): return given
	var result: Dictionary = {
		"angular_samples": 72, "baseline_weight": 1.0, "velocity_weight": 0.04,
		"angular_velocity_weight": 0.01, "clearance_m": 0.001,
		"upper_radius": 0.045, "fore_radius": 0.035, "shoulder_exclude_m": 0.07,
		"reach_tolerance_m": 0.000001, "length_tolerance_m": 0.00001,
		"max_validation_step_s": 1.0 / 120.0, "minimum_edge_samples": 3,
		"max_validation_replans": 24, "max_angle_step_deg": 180.0,
		"max_angular_speed_deg_s": INF, "max_elbow_speed_m_s": INF,
		"wrist_budget_ratio": 1.0, "axial_budget_deg": Anatomy.AXIAL_BUDGET_DEG,
		"require_obstacles": false
	}
	result.merge(given, true)
	result.angular_samples = maxi(8, int(result.angular_samples))
	result.minimum_edge_samples = maxi(1, int(result.minimum_edge_samples))
	result.max_validation_step_s = maxf(0.00001, float(result.max_validation_step_s))
	result.clearance_m = maxf(0.0, float(result.clearance_m))
	result.wrist_budget_ratio = clampf(float(result.wrist_budget_ratio), 0.0, 1.0)
	result.axial_budget_deg = clampf(float(result.axial_budget_deg), 0.0, Anatomy.AXIAL_BUDGET_DEG)
	result._auto_elbow_prepared = true
	return result

static func _perpendicular(axis: Vector3, hint: Vector3) -> Vector3:
	var radial: Vector3 = hint - axis * hint.dot(axis)
	if radial.length_squared() < EPS:
		var least: Vector3 = Vector3.RIGHT
		if absf(axis.y) <= absf(axis.x) and absf(axis.y) <= absf(axis.z): least = Vector3.UP
		elif absf(axis.z) <= absf(axis.x): least = Vector3.BACK
		radial = least - axis * least.dot(axis)
	return radial.normalized()

static func _transport(reference: Vector3, before: Vector3, after: Vector3) -> Vector3:
	# Shortest rotation (parallel transport), with a deterministic antipodal chart.
	var cross_axis: Vector3 = before.cross(after)
	var cosine: float = clampf(before.dot(after), -1.0, 1.0)
	var rotated: Vector3 = reference
	if cross_axis.length_squared() > 1.0e-14:
		rotated = reference.rotated(cross_axis.normalized(), atan2(cross_axis.length(), cosine))
	elif cosine < 0.0:
		rotated = reference.rotated(_perpendicular(before, reference), PI)
	return _perpendicular(after, rotated)

static func circle(frame: Dictionary, previous: Dictionary = {}, tolerance: float = 0.000001) -> Dictionary:
	for key in ["shoulder", "wrist", "upper_length", "fore_length", "baseline_elbow", "hand_basis", "time"]:
		if not frame.has(key): return {"valid": false, "reason": "missing_" + key}
	var shoulder: Vector3 = frame.shoulder
	var wrist: Vector3 = frame.wrist
	var baseline: Vector3 = frame.baseline_elbow
	var hand: Basis = frame.hand_basis
	var upper: float = float(frame.upper_length)
	var fore: float = float(frame.fore_length)
	if not shoulder.is_finite() or not wrist.is_finite() or not baseline.is_finite() or not hand.is_finite() or not is_finite(upper) or not is_finite(fore) or not is_finite(float(frame.time)):
		return {"valid": false, "reason": "nonfinite_input"}
	if upper <= 0.0 or fore <= 0.0: return {"valid": false, "reason": "nonpositive_bone_length"}
	if hand.determinant() <= 0.0: return {"valid": false, "reason": "invalid_hand_basis"}
	var distance: float = shoulder.distance_to(wrist)
	if distance > upper + fore + tolerance: return {"valid": false, "reason": "unreachable_far", "reach_excess_m": distance - upper - fore}
	if distance < absf(upper - fore) - tolerance: return {"valid": false, "reason": "unreachable_near", "reach_excess_m": absf(upper - fore) - distance}
	if distance < EPS: return {"valid": false, "reason": "coincident_endpoints_spherical_locus"}
	var axis: Vector3 = (wrist - shoulder) / distance
	var along: float = (upper * upper - fore * fore + distance * distance) / (2.0 * distance)
	var radius_sq: float = upper * upper - along * along
	if radius_sq < -tolerance * maxf(upper, 1.0): return {"valid": false, "reason": "invalid_circle"}
	var center: Vector3 = shoulder + axis * along
	var reference: Vector3
	if bool(previous.get("valid", false)):
		reference = _transport(previous.reference, previous.axis, axis)
	else:
		reference = _perpendicular(axis, baseline - center)
	return {"valid": true, "center": center, "axis": axis, "reference": reference,
		"radius": sqrt(maxf(0.0, radius_sq)), "distance": distance,
		"baseline_angle": reference.signed_angle_to(_perpendicular(axis, baseline - center), axis)}

static func elbow_on_circle(chart: Dictionary, angle: float) -> Vector3:
	return chart.center + chart.reference.rotated(chart.axis, angle) * float(chart.radius)

static func _angle_delta(a: float, b: float) -> float:
	return fposmod(b - a + PI, TAU) - PI

static func _segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	# Closest points of two closed line segments, including zero-length segments.
	var u: Vector3 = b - a
	var v: Vector3 = d - c
	var w: Vector3 = a - c
	var aa: float = u.dot(u)
	var bb: float = u.dot(v)
	var cc: float = v.dot(v)
	var dd: float = u.dot(w)
	var ee: float = v.dot(w)
	var s: float = 0.0
	var t: float = 0.0
	if aa <= EPS and cc <= EPS: return a.distance_to(c)
	if aa <= EPS: t = clampf(ee / cc, 0.0, 1.0)
	elif cc <= EPS: s = clampf(-dd / aa, 0.0, 1.0)
	else:
		var denom: float = aa * cc - bb * bb
		if denom > EPS * aa * cc: s = clampf((bb * ee - cc * dd) / denom, 0.0, 1.0)
		t = (bb * s + ee) / cc
		if t < 0.0:
			t = 0.0
			s = clampf(-dd / aa, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((bb - dd) / aa, 0.0, 1.0)
	return (w + u * s - v * t).length()

static func capsule_margin(a: Vector3, b: Vector3, radius: float, obstacle: Dictionary) -> float:
	return _segment_distance(a, b, obstacle.a, obstacle.b) - radius - float(obstacle.radius)

static func _cell_capsule_bound(a: Vector3, b: Vector3, radius: float, cell: Dictionary, required: float) -> float:
	# Linear-time conservative hard gate. A capsule is contained by the cell's
	# radius-expanded halfspaces. If the entire center segment misses their
	# intersection, the capsule clears the original convex cell. Report only a
	# LOWER BOUND, never invent a precise signed penetration depth.
	if cell.has("bounds"):
		var box: AABB = cell.bounds
		var low: Vector3 = a.min(b)
		var high: Vector3 = a.max(b)
		var separation: Vector3 = (box.position - high).max(low - box.end).max(Vector3.ZERO)
		var box_bound: float = separation.length() - radius
		if box_bound >= required: return box_bound
	var begin: float = 0.0
	var end: float = 1.0
	var lower_bound: float = -INF
	var separated: bool = false
	for plane: Plane in cell.get("planes", []):
		var da: float = plane.distance_to(a)
		var db: float = plane.distance_to(b)
		lower_bound = maxf(lower_bound, minf(da, db) - radius)
		if lower_bound >= required: return lower_bound
		var slope: float = db - da
		var rhs: float = radius + required - da
		if absf(slope) < 1.0e-12:
			if rhs < 0.0: separated = true
		elif slope > 0.0:
			end = minf(end, rhs / slope)
		else:
			begin = maxf(begin, rhs / slope)
		if begin > end: separated = true
	return maxf(lower_bound, required) if separated else lower_bound

static func evaluate(frame: Dictionary, elbow: Vector3, given_options: Dictionary = {}) -> Dictionary:
	var opt: Dictionary = _options(given_options)
	var reasons: Array[String] = []
	var chart: Dictionary = circle(frame, {}, float(opt.reach_tolerance_m))
	if not chart.valid: return {"valid": false, "reasons": [chart.reason], "clearance_m": -INF, "wrist": {}}
	if not elbow.is_finite(): return {"valid": false, "reasons": ["nonfinite_elbow"], "clearance_m": -INF, "wrist": {}}
	var upper_error: float = absf(frame.shoulder.distance_to(elbow) - float(frame.upper_length))
	var fore_error: float = absf(elbow.distance_to(frame.wrist) - float(frame.fore_length))
	if maxf(upper_error, fore_error) > float(opt.length_tolerance_m): reasons.append("bone_length")
	var left: bool = bool(frame.get("is_left", false))
	var thumb: Vector3 = frame.get("thumb_up", frame.hand_basis.y)
	var fore_basis: Basis = Anatomy.forearm_reference(frame.shoulder, elbow, frame.wrist, thumb, left)
	var wrist: Dictionary = Anatomy.decompose(fore_basis, frame.hand_basis, float(frame.get("radial_sign", -1.0 if left else 1.0)))
	if not is_finite(float(wrist.coupled_budget_ratio)) or float(wrist.coupled_budget_ratio) > float(opt.wrist_budget_ratio) + 0.000001: reasons.append("wrist_coupled_budget")
	if absf(float(wrist.forearm_axial_deg)) > float(opt.axial_budget_deg) + 0.000001: reasons.append("forearm_axial_budget")
	if not reasons.is_empty() and not bool(opt.get("compute_all_diagnostics", false)):
		return {"valid": false, "reasons": reasons, "clearance_m": INF, "wrist": wrist,
			"upper_length_error_m": upper_error, "fore_length_error_m": fore_error,
			"collision_checked": false}
	var upper_radius: float = float(frame.get("upper_radius", opt.upper_radius))
	var fore_radius: float = float(frame.get("fore_radius", opt.fore_radius))
	var exclude: float = float(frame.get("shoulder_exclude_m", opt.shoulder_exclude_m))
	if upper_radius < 0.0 or fore_radius < 0.0 or not is_finite(upper_radius) or not is_finite(fore_radius):
		return {"valid": false, "reasons": ["invalid_arm_radius"], "clearance_m": -INF, "wrist": wrist, "collision_checked": false}
	var upper_start: Vector3 = frame.shoulder.lerp(elbow, clampf(exclude / float(frame.upper_length), 0.0, 1.0))
	var minimum: float = INF
	var limiting: String = ""
	var obstacles: Array = frame.get("obstacles", [])
	var cells: Array = frame.get("body_geometry", {}).get("cells", [])
	if bool(opt.require_obstacles) and obstacles.is_empty() and cells.is_empty(): reasons.append("missing_obstacles")
	for obstacle: Dictionary in obstacles:
		if not obstacle.has("a") or not obstacle.has("b") or not obstacle.has("radius"):
			reasons.append("invalid_obstacle")
			continue
		if not (obstacle.a as Vector3).is_finite() or not (obstacle.b as Vector3).is_finite() or not is_finite(float(obstacle.radius)) or float(obstacle.radius) < 0.0:
			reasons.append("invalid_obstacle")
			continue
		var margin: float = minf(capsule_margin(frame.shoulder, elbow, upper_radius, obstacle), capsule_margin(elbow, frame.wrist, fore_radius, obstacle))
		if margin < minimum:
			minimum = margin
			limiting = str(obstacle.get("label", "capsule"))
	for cell: Dictionary in cells:
		var margin: float = minf(_cell_capsule_bound(upper_start, elbow, upper_radius, cell, float(opt.clearance_m)), _cell_capsule_bound(elbow, frame.wrist, fore_radius, cell, float(opt.clearance_m)))
		if margin < minimum:
			minimum = margin
			limiting = "body:" + str(cell.get("region", "cell"))
	if minimum < float(opt.clearance_m): reasons.append("clearance:" + limiting)
	if opt.has("extra_evaluator") and (opt.extra_evaluator as Callable).is_valid():
		var extra: Dictionary = opt.extra_evaluator.call(frame, elbow)
		if not bool(extra.get("valid", false)):
			for reason in extra.get("reasons", ["extra_constraint"]): reasons.append(str(reason))
		minimum = minf(minimum, float(extra.get("clearance_m", INF)))
	return {"valid": reasons.is_empty(), "reasons": reasons, "clearance_m": minimum,
		"limiting_obstacle": limiting, "clearance_is_conservative_lower_bound": true, "wrist": wrist, "upper_length_error_m": upper_error,
		"fore_length_error_m": fore_error, "collision_checked": not obstacles.is_empty() or not cells.is_empty()}

static func _interpolate_frame(a: Dictionary, b: Dictionary, amount: float) -> Dictionary:
	var frame: Dictionary = a.duplicate(false)
	for key in ["time", "upper_length", "fore_length", "upper_radius", "fore_radius", "shoulder_exclude_m"]:
		if a.has(key) and b.has(key): frame[key] = lerpf(float(a[key]), float(b[key]), amount)
	for key in ["shoulder", "wrist", "baseline_elbow", "thumb_up"]:
		if a.has(key) and b.has(key): frame[key] = (a[key] as Vector3).lerp(b[key], amount)
	for key in ["hand_mount", "paddle_transform", "body_transform"]:
		if a.has(key) and b.has(key): frame[key] = (a[key] as Transform3D).interpolate_with(b[key], amount)
	if frame.has("paddle_transform"): frame.paddle_inverse = frame.paddle_transform.affine_inverse()
	frame.hand_basis = (a.hand_basis as Basis).orthonormalized().slerp((b.hand_basis as Basis).orthonormalized(), amount)
	var oa: Array = a.get("obstacles", [])
	var ob: Array = b.get("obstacles", [])
	frame.obstacles = []
	if oa.size() != ob.size():
		frame.interpolation_error = "obstacle_topology_change"
	else:
		for i in range(oa.size()):
			if str(oa[i].get("label", i)) != str(ob[i].get("label", i)):
				frame.interpolation_error = "obstacle_identity_change"
				continue
			frame.obstacles.append({"a": (oa[i].a as Vector3).lerp(ob[i].a, amount), "b": (oa[i].b as Vector3).lerp(ob[i].b, amount), "radius": lerpf(float(oa[i].radius), float(ob[i].radius), amount), "label": str(oa[i].get("label", i))})
	var ca: Array = a.get("body_geometry", {}).get("cells", [])
	var cb: Array = b.get("body_geometry", {}).get("cells", [])
	frame.body_geometry = {"cells": []}
	if ca.size() != cb.size():
		frame.interpolation_error = "body_topology_change"
	else:
		for i in range(ca.size()):
			var pa: Array = ca[i].get("planes", [])
			var pb: Array = cb[i].get("planes", [])
			if pa.size() != pb.size():
				frame.interpolation_error = "body_plane_topology_change"
				continue
			var planes: Array[Plane] = []
			for j in range(pa.size()):
				var normal: Vector3 = pa[j].normal.lerp(pb[j].normal, amount)
				if normal.length_squared() < EPS:
					frame.interpolation_error = "body_plane_orientation_change"
					continue
				planes.append(Plane(normal.normalized(), lerpf(pa[j].d, pb[j].d, amount) / normal.length()))
			frame.body_geometry.cells.append({"planes": planes, "region": str(ca[i].get("region", i))})
	return frame

static func _at_edge(frame_a: Dictionary, frame_b: Dictionary, chart_a: Dictionary, angle_a: float, angle_b: float, amount: float, opt: Dictionary, exact_frame: Dictionary = {}, tangent_a: float = NAN, tangent_b: float = NAN) -> Dictionary:
	var time: float = lerpf(float(frame_a.time), float(frame_b.time), amount)
	var frame: Dictionary = exact_frame
	if frame.is_empty():
		if opt.has("frame_at") and (opt.frame_at as Callable).is_valid():
			var cache: Dictionary = opt.get("_frame_cache", {})
			if cache.has(time): frame = cache[time]
			else:
				frame = opt.frame_at.call(time)
				cache[time] = frame
		else: frame = _interpolate_frame(frame_a, frame_b, amount)
	if frame.has("interpolation_error"): return {"valid": false, "reasons": [frame.interpolation_error], "time": time}
	if not frame.has("time") or absf(float(frame.time) - time) > 0.000001: return {"valid": false, "reasons": ["source_time_mismatch"], "time": time}
	var chart: Dictionary = circle(frame, chart_a, float(opt.reach_tolerance_m))
	if not chart.valid: return {"valid": false, "reasons": [chart.reason], "time": time}
	var duration: float = float(frame_b.time) - float(frame_a.time)
	var secant: float = (angle_b - angle_a) / duration
	if not is_finite(tangent_a): tangent_a = secant
	if not is_finite(tangent_b): tangent_b = secant
	var square: float = amount * amount
	var cube: float = square * amount
	var angle: float = (2.0 * cube - 3.0 * square + 1.0) * angle_a + (cube - 2.0 * square + amount) * duration * tangent_a + (-2.0 * cube + 3.0 * square) * angle_b + (cube - square) * duration * tangent_b
	var elbow: Vector3 = elbow_on_circle(chart, angle)
	var result: Dictionary = evaluate(frame, elbow, opt)
	result.merge({"time": time, "angle": angle, "elbow": elbow, "pole": frame.shoulder + chart.reference.rotated(chart.axis, angle), "frame": frame, "circle": chart}, true)
	return result

static func _edge_key(frame_index: int, from: int, to: int) -> String:
	return "%d:%d:%d" % [frame_index, from, to]

static func _validate_edge(frames: Array, charts: Array, candidates: Array, index: int, from: int, to: int, opt: Dictionary, tangent_a: float, tangent_b: float) -> Dictionary:
	var a: Dictionary = frames[index - 1]
	var b: Dictionary = frames[index]
	var angle_a: float = float(candidates[index - 1][from].angle)
	var angle_b: float = angle_a + _angle_delta(angle_a, float(candidates[index][to].angle))
	var duration: float = float(b.time) - float(a.time)
	var delta: float = angle_b - angle_a
	var qa: float = -6.0 * delta / duration + 3.0 * (tangent_a + tangent_b)
	var qb: float = 6.0 * delta / duration - 4.0 * tangent_a - 2.0 * tangent_b
	var peak: float = maxf(absf(tangent_a), absf(tangent_b))
	if absf(qa) > EPS:
		var critical: float = -qb / (2.0 * qa)
		if critical > 0.0 and critical < 1.0: peak = maxf(peak, absf(qa * critical * critical + qb * critical + tangent_a))
	if minf(float(charts[index - 1].radius), float(charts[index].radius)) > 0.00001 and rad_to_deg(peak) > float(opt.max_angular_speed_deg_s):
		return {"valid": false, "failed_time": a.time, "reasons": ["angular_speed_budget"], "sample_count": 0, "step_s": duration}
	var subdivisions: int = maxi(int(opt.minimum_edge_samples) + 1, int(ceil(duration / float(opt.max_validation_step_s))))
	var minimum: float = minf(float(candidates[index - 1][from].evaluation.clearance_m), float(candidates[index][to].evaluation.clearance_m))
	for step in range(1, subdivisions):
		var sample: Dictionary = _at_edge(a, b, charts[index - 1], angle_a, angle_b, float(step) / subdivisions, opt, {}, tangent_a, tangent_b)
		if not sample.valid:
			return {"valid": false, "failed_time": sample.time, "reasons": sample.reasons, "sample_count": step, "step_s": duration / subdivisions}
		minimum = minf(minimum, float(sample.clearance_m))
	return {"valid": true, "minimum_clearance_m": minimum, "sample_count": subdivisions - 1, "step_s": duration / subdivisions}

static func _solve_run(frames: Array, charts: Array, candidates: Array, start: int, end: int, blocked: Dictionary, opt: Dictionary) -> Dictionary:
	var costs: Array = []
	var parents: Array = []
	for index in range(start, end + 1):
		var row: Array[float] = []
		var links: Array[int] = []
		var duration: float = 1.0 if index == start else float(frames[index].time) - float(frames[index - 1].time)
		for to in range(candidates[index].size()):
			var candidate: Dictionary = candidates[index][to]
			var baseline_distance: float = (candidate.elbow as Vector3).distance_squared_to(frames[index].baseline_elbow)
			var node_cost: float = float(opt.baseline_weight) * baseline_distance * duration
			if frames[index].has("guide_elbow"):
				node_cost += float(opt.get("guide_weight", 100.0)) * (candidate.elbow as Vector3).distance_squared_to(frames[index].guide_elbow) * duration
			var best: float = node_cost if index == start else INF
			var parent: int = -1
			if index != start:
				for from in range(candidates[index - 1].size()):
					var prior_cost: float = float(costs[-1][from])
					if not is_finite(prior_cost) or blocked.has(_edge_key(index, from, to)): continue
					var prior: Dictionary = candidates[index - 1][from]
					var delta: float = absf(_angle_delta(prior.angle, candidate.angle))
					var cartesian: float = prior.elbow.distance_squared_to(candidate.elbow)
					# Angular penalties vanish as the elbow circle collapses.
					var radius: float = minf(float(charts[index - 1].radius), float(charts[index].radius))
					if radius > 0.00001 and (rad_to_deg(delta) > float(opt.max_angle_step_deg) + 0.00001 or rad_to_deg(delta) / duration > float(opt.max_angular_speed_deg_s)): continue
					if sqrt(cartesian) / duration > float(opt.max_elbow_speed_m_s): continue
					var transition: float = (float(opt.velocity_weight) * cartesian + float(opt.angular_velocity_weight) * delta * delta * radius * radius) / duration
					var cost: float = prior_cost + node_cost + transition
					if cost < best - 1.0e-12:
						best = cost
						parent = from
			row.append(best)
			links.append(parent)
		costs.append(row)
		parents.append(links)
		var row_best: float = INF
		for cost in row: row_best = minf(row_best, cost)
		if not is_finite(row_best): return {"valid": false, "disconnected_at": index}
	var selected: Array[int] = []
	selected.resize(end - start + 1)
	var best_index: int = 0
	for index in range(costs[-1].size()):
		if costs[-1][index] < costs[-1][best_index]: best_index = index
	for relative in range(end - start, -1, -1):
		selected[relative] = best_index
		best_index = int(parents[relative][best_index])
	return {"valid": true, "selected": selected, "cost": costs[-1][selected[-1]]}

static func _route_angles(candidates: Array, selected: Array, start: int) -> Array[float]:
	var angles: Array[float] = []
	for relative in range(selected.size()):
		var angle: float = float(candidates[start + relative][int(selected[relative])].angle)
		angles.append(angle if angles.is_empty() else angles[-1] + _angle_delta(angles[-1], angle))
	return angles

static func _route_tangents(frames: Array, angles: Array[float], start: int) -> Array[float]:
	# Shape-preserving PCHIP: shared derivatives, no angular overshoot, and no
	# forced stop at every knot. Harmonic means damp isolated grid noise.
	var count: int = angles.size()
	var tangents: Array[float] = []
	tangents.resize(count)
	tangents.fill(0.0)
	if count < 2: return tangents
	var durations: Array[float] = []
	var secants: Array[float] = []
	for i in range(count - 1):
		var duration: float = float(frames[start + i + 1].time) - float(frames[start + i].time)
		durations.append(duration)
		secants.append((angles[i + 1] - angles[i]) / duration)
	if count == 2:
		tangents[0] = secants[0]
		tangents[1] = secants[0]
		return tangents
	for i in range(1, count - 1):
		var before: float = secants[i - 1]
		var after: float = secants[i]
		if before * after <= 0.0: continue
		var w1: float = 2.0 * durations[i] + durations[i - 1]
		var w2: float = durations[i] + 2.0 * durations[i - 1]
		tangents[i] = (w1 + w2) / (w1 / before + w2 / after)
	tangents[0] = ((2.0 * durations[0] + durations[1]) * secants[0] - durations[0] * secants[1]) / (durations[0] + durations[1])
	if tangents[0] * secants[0] <= 0.0: tangents[0] = 0.0
	elif secants[0] * secants[1] < 0.0: tangents[0] = signf(tangents[0]) * minf(absf(tangents[0]), 3.0 * absf(secants[0]))
	var last: int = count - 2
	tangents[-1] = ((2.0 * durations[last] + durations[last - 1]) * secants[last] - durations[last] * secants[last - 1]) / (durations[last] + durations[last - 1])
	if tangents[-1] * secants[last] <= 0.0: tangents[-1] = 0.0
	elif secants[last] * secants[last - 1] < 0.0: tangents[-1] = signf(tangents[-1]) * minf(absf(tangents[-1]), 3.0 * absf(secants[last]))
	return tangents

static func bake(input_frames: Array, given_options: Dictionary = {}) -> Dictionary:
	var began: int = Time.get_ticks_usec()
	var opt: Dictionary = _options(given_options).duplicate(false)
	opt._frame_cache = {}
	var frames: Array = input_frames.duplicate(true)
	var result: Dictionary = {"version": VERSION, "status": "infeasible", "complete": false, "feasible": false, "elapsed_us": 0,
		"frames": frames, "charts": [], "nodes": [], "segments": [], "infeasible_intervals": [],
		"options": opt, "candidate_counts": [], "edge_validation_count": 0,
		"validation_sample_count": 0, "max_verified_step_s": 0.0,
		"validation_kind": "sampled_exact_source" if opt.has("frame_at") else "sampled_interpolated_input",
		"continuous_time_certified": false, "single_arm_only": true, "clip_loop_closure_enforced": false, "interpolant": "monotone_cubic_hermite_pchip",
		"limits": ["Finite angle grid; failure is not proof of continuous infeasibility.", "Time samples do not certify unsampled times.", "Other-arm input capsules are fixed; jointly changed arms require final pair validation.", "Returned pole requires bypass of production pole conditioning.", "Angular coordinates are periodic; clip end-to-start closure is not optimized."]}
	if frames.is_empty():
		result.infeasible_intervals.append({"start_time": 0.0, "end_time": 0.0, "reason": "empty_input"})
		return result
	var candidates: Array = []
	var previous: Dictionary = {}
	for index in range(frames.size()):
		if _cancelled(opt):
			result.status="cancelled";result.elapsed_us=Time.get_ticks_usec()-began;return result
		var frame: Dictionary = frames[index]
		var chart: Dictionary = circle(frame, previous, float(opt.reach_tolerance_m))
		if index > 0 and chart.valid and frames[0].has("upper_length") and frames[0].has("fore_length"):
			if absf(float(frame.upper_length) - float(frames[0].upper_length)) > float(opt.length_tolerance_m) or absf(float(frame.fore_length) - float(frames[0].fore_length)) > float(opt.length_tolerance_m):
				chart = {"valid": false, "reason": "nominal_bone_lengths_changed"}
		if index > 0 and float(frame.get("time", -INF)) <= float(frames[index - 1].get("time", INF)):
			chart = {"valid": false, "reason": "times_not_strictly_increasing"}
		result.charts.append(chart)
		var row: Array = []
		var rejected: Dictionary = {}
		if chart.valid:
			previous = chart
			var angles: Array[float] = [float(chart.baseline_angle)]
			if frame.has("guide_elbow"):
				var guide_radial: Vector3 = _perpendicular(chart.axis, frame.guide_elbow - chart.center)
				angles.append(chart.reference.signed_angle_to(guide_radial, chart.axis))
			if float(chart.radius) > 0.0000001:
				for angle_index in range(int(opt.angular_samples)):
					var angle: float = TAU * float(angle_index) / int(opt.angular_samples)
					if absf(_angle_delta(angles[0], angle)) > 0.00000001: angles.append(angle)
			for angle in angles:
				if _cancelled(opt):
					result.status="cancelled";result.elapsed_us=Time.get_ticks_usec()-began;return result
				var elbow: Vector3 = elbow_on_circle(chart, angle)
				var evaluation: Dictionary = evaluate(frame, elbow, opt)
				if evaluation.valid: row.append({"angle": angle, "elbow": elbow, "evaluation": evaluation})
				else:
					for reason in evaluation.reasons: rejected[reason] = int(rejected.get(reason, 0)) + 1
			row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.angle) < float(b.angle))
		else:
			rejected[chart.reason] = 1
		candidates.append(row)
		result.candidate_counts.append(row.size())
		result.nodes.append({"time": float(frame.get("time", index)), "valid": false, "rejections": rejected})
		if row.is_empty():
			result.infeasible_intervals.append({"start_time": float(frame.get("time", index)), "end_time": float(frame.get("time", index)), "reason": "no_sampled_feasible_candidate" if chart.valid else chart.reason, "rejections": rejected})
			if bool(opt.get("stop_on_empty_candidates",false)):
				result.elapsed_us=Time.get_ticks_usec()-began
				return result
	for index in range(1, frames.size()):
		if candidates[index - 1].is_empty() or candidates[index].is_empty():
			result.infeasible_intervals.append({"start_time": float(frames[index - 1].get("time", index - 1)), "end_time": float(frames[index].get("time", index)), "reason": "unverified_edge_adjacent_to_infeasible_node"})
	var pending: Array = []
	var start: int = 0
	while start < frames.size():
		if candidates[start].is_empty():
			start += 1
			continue
		var end: int = start
		while end + 1 < frames.size() and not candidates[end + 1].is_empty(): end += 1
		pending.append([start, end])
		start = end + 1
	var blocked: Dictionary = {}
	var verified: Dictionary = {}
	while not pending.is_empty():
		if _cancelled(opt):
			result.status="cancelled";result.elapsed_us=Time.get_ticks_usec()-began;return result
		var run: Array = pending.pop_front()
		start = int(run[0])
		var end: int = int(run[1])
		var solved: Dictionary = {}
		var accepted: bool = false
		var failure_index: int = start + 1
		var route_angles: Array[float] = []
		var tangents: Array[float] = []
		for attempt in range(int(opt.max_validation_replans) + 1):
			if _cancelled(opt):
				result.status="cancelled";result.elapsed_us=Time.get_ticks_usec()-began;return result
			solved = _solve_run(frames, result.charts, candidates, start, end, blocked, opt)
			if not solved.valid:
				failure_index = int(solved.disconnected_at)
				break
			route_angles = _route_angles(candidates, solved.selected, start)
			tangents = _route_tangents(frames, route_angles, start)
			var all_valid: bool = true
			for index in range(start + 1, end + 1):
				if _cancelled(opt):
					result.status="cancelled";result.elapsed_us=Time.get_ticks_usec()-began;return result
				var from: int = int(solved.selected[index - start - 1])
				var to: int = int(solved.selected[index - start])
				var key: String = _edge_key(index, from, to)
				var cache_key: String = key + ":%.12f:%.12f" % [tangents[index - start - 1], tangents[index - start]]
				if verified.has(cache_key): continue
				var checked: Dictionary = _validate_edge(frames, result.charts, candidates, index, from, to, opt, tangents[index - start - 1], tangents[index - start])
				result.edge_validation_count += 1
				result.validation_sample_count += int(checked.sample_count)
				result.max_verified_step_s = maxf(float(result.max_verified_step_s), float(checked.step_s))
				if checked.valid: verified[cache_key] = checked
				else:
					blocked[key] = checked
					failure_index = index
					all_valid = false
			if all_valid:
				accepted = true
				break
		if not accepted:
			var reason: String = "sampled_graph_disconnected" if not bool(solved.get("valid", false)) else "bounded_edge_search_exhausted"
			result.infeasible_intervals.append({"start_time": frames[failure_index - 1].time, "end_time": frames[failure_index].time, "reason": reason})
			if start <= failure_index - 1: pending.append([start, failure_index - 1])
			if failure_index <= end: pending.append([failure_index, end])
			continue
		var angles: Array[float] = []
		for index in range(start, end + 1):
			var candidate: Dictionary = candidates[index][int(solved.selected[index - start])]
			var unwrapped: float = float(candidate.angle) if angles.is_empty() else angles[-1] + _angle_delta(angles[-1], float(candidate.angle))
			angles.append(unwrapped)
			result.nodes[index] = {"time": frames[index].time, "valid": true, "angle": unwrapped, "elbow": candidate.elbow, "evaluation": candidate.evaluation, "tangent": tangents[index - start]}
		result.segments.append({"start_index": start, "end_index": end, "start_time": frames[start].time, "end_time": frames[end].time, "angles": angles, "tangents": tangents, "cost": solved.cost})
	result.segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start_index) < int(b.start_index))
	result.infeasible_intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start_time) < float(b.start_time))
	result.complete = result.infeasible_intervals.is_empty() and result.segments.size() == 1 and int(result.segments[0].start_index) == 0 and int(result.segments[0].end_index) == frames.size() - 1
	result.status = "sampled_feasible" if result.complete else ("partial" if not result.segments.is_empty() else "infeasible")
	result.blocked_edge_count = blocked.size()
	result.elapsed_us = Time.get_ticks_usec() - began
	result.feasible = result.complete
	return result

static func sample(baked: Dictionary, time: float, exact_frame: Dictionary = {}) -> Dictionary:
	# Stateless lookup. Never searches candidates, stretches bones or changes a hand.
	if not is_finite(time): return {"valid": false, "status": "invalid_time"}
	var frames: Array = baked.get("frames", [])
	if frames.is_empty(): return {"valid": false, "status": "empty_bake", "time": time}
	if time < float(frames[0].time) - 1.0e-9 or time > float(frames[-1].time) + 1.0e-9: return {"valid": false, "status": "outside_bake", "time": time}
	var segment: Dictionary = {}
	for item: Dictionary in baked.get("segments", []):
		if time >= float(item.start_time) - 1.0e-9 and time <= float(item.end_time) + 1.0e-9:
			segment = item
			break
	if segment.is_empty(): return {"valid": false, "status": "infeasible_interval", "time": time}
	var low: int = int(segment.start_index)
	var high: int = int(segment.end_index)
	while low < high:
		var middle: int = (low + high) / 2
		if float(frames[middle].time) < time: low = middle + 1
		else: high = middle
	var index: int = low
	var result: Dictionary
	if index == int(segment.start_index) or absf(time - float(frames[index].time)) < 1.0e-9:
		var frame: Dictionary = frames[index] if exact_frame.is_empty() else exact_frame
		if not frame.has("time") or absf(float(frame.time) - time) > 0.000001: return {"valid": false, "status": "runtime_constraint_failed", "reasons": ["source_time_mismatch"], "time": time}
		var chart: Dictionary = circle(frame, baked.charts[index], float(baked.options.reach_tolerance_m))
		if not chart.valid: return {"valid": false, "status": "runtime_constraint_failed", "reasons": [chart.reason], "time": time}
		var angle: float = float(baked.nodes[index].angle)
		var elbow: Vector3 = elbow_on_circle(chart, angle)
		result = evaluate(frame, elbow, baked.options)
		result.merge({"time": time, "angle": angle, "elbow": elbow, "pole": frame.shoulder + chart.reference.rotated(chart.axis, angle), "frame": frame, "circle": chart}, true)
	else:
		var amount: float = (time - float(frames[index - 1].time)) / (float(frames[index].time) - float(frames[index - 1].time))
		result = _at_edge(frames[index - 1], frames[index], baked.charts[index - 1], float(baked.nodes[index - 1].angle), float(baked.nodes[index].angle), amount, baked.options, exact_frame, float(baked.nodes[index - 1].tangent), float(baked.nodes[index].tangent))
	result.status = "sampled_route" if result.valid else "runtime_constraint_failed"
	result.bake_complete = bool(baked.complete)
	result.feasible = bool(result.valid)
	result.runtime_constraints_complete = bool(result.get("collision_checked", false))
	if not exact_frame.is_empty() and not result.runtime_constraints_complete:
		result.status = "sampled_route_cached_collision_only" if result.valid else "runtime_constraint_failed"
	return result

static func _cancelled(options: Dictionary) -> bool:
	var token = options.get("cancellation")
	return token != null and token.is_cancelled()
