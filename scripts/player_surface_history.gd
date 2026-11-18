extends RefCounted
## Bounded continuous ball/contact query between two actual displayed rig
## snapshots. Surface vertices interpolate linearly between physics samples.
## Captures transforms/palettes cheaply; only overlapping parts are skinned.
const Surface = preload("res://scripts/player_surface_contacts.gd")
const Geometry = preload("res://scripts/contact_surface_geometry.gd")
const Reentry = preload("res://scripts/moving_triangle_reentry.gd")
const MAX_ADVANCES := 48
const MAX_TOTAL_QUERIES := 2048
const MAX_ALGEBRA_QUERIES := 12
const ALGEBRA_UNITS_PER_QUERY := 24 # 3 quadratics, 3 quartics, 1 sextic
const CONTACT_EPSILON := 0.00002
const TELEPORT_DISTANCE := 1.5
var _previous: Dictionary = {}
var _flight := -1

func reset() -> void:
	_previous.clear()
	_flight = -1

func prime(player, flight_id: int) -> void:
	_previous = Surface.snapshot(player)
	_flight = flight_id

func advance(player, ball_from: Vector3, ball_to: Vector3, flight_id: int,
		radius: float = 0.0375, max_fraction: float = 1.0, teleported: bool = false, include_legal_hand: bool = false) -> Dictionary:
	var current: Dictionary = Surface.snapshot(player)
	var reset_reason := ""
	if teleported: reset_reason = "explicit_teleport"
	elif _previous.is_empty(): reset_reason = "initial"
	elif _flight != flight_id: reset_reason = "flight_changed"
	elif Vector3(current.root).distance_to(_previous.root) > TELEPORT_DISTANCE: reset_reason = "root_teleport"
	var result: Dictionary
	if reset_reason != "":
		result = Surface.ball_contact(player, ball_from, ball_to, radius, max_fraction, include_legal_hand)
		result.ambiguous = false
		result.blocked = result.hit
		result.history_reset = reset_reason
	else:
		result = query(_previous, current, ball_from, ball_to, radius, max_fraction, include_legal_hand)
	_previous = current
	_flight = flight_id
	return result

static func query(previous: Dictionary, current: Dictionary, ball_from: Vector3, ball_to: Vector3,
		radius: float = 0.0375, max_fraction: float = 1.0, include_legal_hand: bool = false,
		_range_start: float = 0.0, _range_end: float = 1.0, departing_mesh_id: int = -1, query_budget: int = MAX_TOTAL_QUERIES, release_departures: Dictionary = {}, algebra_budget: int = MAX_ALGEBRA_QUERIES, maintained_faces: Dictionary = {}, ball_displacement: Vector3 = Vector3.INF, exact_algebra_units: int = -1, physical_velocity: Vector3 = Vector3.INF, sample_seconds: float = 0.0) -> Dictionary:
	var algebra_cache: Dictionary = {}
	var algebra_units_limit: int = ALGEBRA_UNITS_PER_QUERY * mini(MAX_ALGEBRA_QUERIES, maxi(0, algebra_budget))
	if exact_algebra_units >= 0: algebra_units_limit = mini(algebra_units_limit, exact_algebra_units)
	var range_start: float = clampf(_range_start, 0.0, 1.0)
	var range_end: float = clampf(_range_end, range_start, 1.0)
	var range_span: float = range_end - range_start
	var limit: float = clampf(max_fraction, 0.0, 1.0)
	var result := {"hit": false, "blocked": false, "ambiguous": false, "fraction": -1.0,
		"source": "interpolated_posed_mesh", "queries": 0, "algebra_queries": 0, "algebra_work_units": 0, "max_advances": MAX_ADVANCES, "uncertain_fraction": INF}
	for id in current.parts:
		var now: Dictionary = current.parts[id]
		var before: Dictionary = previous.parts.get(id, now)
		var bounds: AABB = now.bounds.merge(before.bounds).grow(radius)
		var endpoint: Vector3 = ball_from.lerp(ball_to, limit)
		if not bounds.has_point(ball_from) and not bounds.has_point(endpoint) and not bounds.intersects_segment(ball_from, endpoint): continue
		var end_triangles: PackedVector3Array = Surface.snapshot_triangles(now)
		var start_triangles: PackedVector3Array = Surface.snapshot_triangles(before)
		if now.mesh != before.mesh or start_triangles.size() != end_triangles.size() or now.get("mesh_key", []) != before.get("mesh_key", []):
			return {"hit": false, "blocked": true, "ambiguous": true, "fraction": 0.0, "part": now.part,
				"source": "interpolated_posed_mesh", "reason": "overlapping_topology_changed"}
		var full_displacements := PackedVector3Array()
		for vertex in start_triangles.size(): full_displacements.append(end_triangles[vertex] - start_triangles[vertex])
		if range_start > 0.0 or range_end < 1.0:
			start_triangles = start_triangles.duplicate(); end_triangles = end_triangles.duplicate()
			for vertex in start_triangles.size():
				var original_start: Vector3 = start_triangles[vertex]
				var original_end: Vector3 = end_triangles[vertex]
				start_triangles[vertex] = original_start.lerp(original_end, range_start)
				end_triangles[vertex] = original_start.lerp(original_end, range_end)
		var plane_sources := PackedInt32Array()
		if now.get("equipment", false) and now.palette.is_empty() and before.palette.is_empty() and now.get("mesh_key", Surface.mesh_geometry_key(now.mesh)) == Surface.mesh_geometry_key(now.mesh): plane_sources = Surface.rigid_planar_face_sources(now.mesh)
		for offset in range(0, end_triangles.size() - 2, 3):
			if maintained_faces.has(int(id)) and offset in maintained_faces[int(id)]: continue
			var a: Vector3 = start_triangles[offset]; var b: Vector3 = start_triangles[offset + 1]; var c: Vector3 = start_triangles[offset + 2]
			var da: Vector3 = full_displacements[offset] * range_span; var db: Vector3 = full_displacements[offset + 1] * range_span; var dc: Vector3 = full_displacements[offset + 2] * range_span
			var triangle_bounds := AABB(a, Vector3.ZERO).expand(b).expand(c).expand(a + da).expand(b + db).expand(c + dc).grow(radius)
			if not triangle_bounds.has_point(ball_from) and not triangle_bounds.has_point(endpoint) and not triangle_bounds.intersects_segment(ball_from, endpoint): continue
			var motion: Vector3 = ball_displacement if ball_displacement.is_finite() else ball_to - ball_from
			# Work in the ball-relative frame: the triangle's Hausdorff
			# speed is bounded by its fastest relative vertex, not the sum
			# of unrelated ball and surface speeds. This stays conservative
			# while avoiding false exhaustion on co-moving hands.
			var speed_bound: float = maxf((motion - da).length(), maxf((motion - db).length(), (motion - dc).length()))
			var time: float = _triangle_entry(ball_from, motion, a, b, c, da, db, dc, radius + CONTACT_EPSILON, limit)
			if time < 0.0: continue
			var shared_plane: Array = []
			if not plane_sources.is_empty() and plane_sources[offset / 3] >= 0:
				var source: int = plane_sources[offset / 3]
				shared_plane = [start_triangles[source], start_triangles[source + 1], start_triangles[source + 2],
					full_displacements[source] * range_span, full_displacements[source + 1] * range_span, full_displacements[source + 2] * range_span]
			var exhausted := true
			for step in MAX_ADVANCES:
				if int(result.queries) >= mini(MAX_TOTAL_QUERIES, maxi(0, query_budget)):
					result.ambiguous = true; result.blocked = true
					result.reason = "total_continuous_contact_budget"
					return result
				result.queries += 1
				var ball: Vector3 = ball_from + motion * time
				var nearest: Vector3 = Geometry.closest_triangle(ball, a + da * time, b + db * time, c + dc * time)
				var gap: float = ball.distance_to(nearest) - radius
				if gap <= CONTACT_EPSILON:
					var global_fraction: float = range_start + range_span * time
					var kind := "legal_paddle" if now.get("equipment", false) else "body"
					if not now.hand.is_empty() and not before.hand.is_empty() and current.get("has_paddle", false) and previous.get("has_paddle", false):
						var hand := {"wrist": Vector3(before.hand.wrist).lerp(now.hand.wrist, global_fraction),
							"distal": Vector3(before.hand.distal).lerp(now.hand.distal, global_fraction).normalized()}
						var at_time := PackedVector3Array()
						for vertex in start_triangles.size(): at_time.append(start_triangles[vertex].lerp(end_triangles[vertex], time))
						var paddle: Transform3D = _linear_frame(previous.paddle, current.paddle, global_fraction)
						if absf(paddle.basis.determinant()) < 1e-6:
							result.ambiguous = true; result.blocked = true; result.reason = "collapsed_paddle_interpolation"
							return result
						kind = Surface.hand_contact_kind(hand, at_time, nearest, paddle)
					# Only omit a previously contacted hand triangle when a supporting
					# plane proves separation for the ENTIRE remaining interval.
					# No other hand, body surface, or returning triangle is waived.
					var normal: Vector3 = (ball - nearest).normalized()
					if time == 0.0 and kind in ["legal_hand", "legal_paddle"] and int(id) == departing_mesh_id and _proven_departing(ball, normal, radius,
						[a + da * time, b + db * time, c + dc * time], [da, db, dc], motion):
						exhausted = false
						break
					if time == 0.0 and release_departures.has(int(id)) and release_departures[int(id)].has(offset):
						var initial_depth: float = release_departures[int(id)][offset]
						if _proven_release_outward(ball, nearest, radius, [a, b, c], [da, db, dc], motion, initial_depth):
							var exit_path: Dictionary = Reentry.first_entry(ball_from, motion, a, b, c, da, db, dc, radius, limit, algebra_cache, algebra_units_limit - int(result.algebra_work_units), shared_plane)
							result.algebra_work_units += int(exit_path.get("work_units", 0))
							result.algebra_queries = ceili(float(result.algebra_work_units) / ALGEBRA_UNITS_PER_QUERY)
							if not exit_path.resolved:
								result.ambiguous = true; result.blocked = true; result.reason = "release_manifold_algebra_budget"
								result.fraction = range_start; return result
							if exit_path.resolved:
								if not exit_path.hit:
									exhausted = false; break
								time = float(exit_path.time); continue
					if kind in ["legal_hand", "legal_paddle"] and time == 0.0 and int(id) == departing_mesh_id:
						var weights_now: Vector3 = Geometry.barycentric(nearest, a, b, c)
						var relative: Vector3 = motion - (da * weights_now.x + db * weights_now.y + dc * weights_now.z)
						if physical_velocity.is_finite() and sample_seconds > 0.0:
							relative = physical_velocity - (full_displacements[offset] * weights_now.x + full_displacements[offset + 1] * weights_now.y + full_displacements[offset + 2] * weights_now.z) / sample_seconds
						if relative.dot(normal) >= -1e-10:
							var reentry: Dictionary = Reentry.first_entry(ball_from, motion, a, b, c, da, db, dc, radius, limit, algebra_cache, algebra_units_limit - int(result.algebra_work_units), shared_plane)
							result.algebra_work_units += int(reentry.get("work_units", 0))
							result.algebra_queries = ceili(float(result.algebra_work_units) / ALGEBRA_UNITS_PER_QUERY)
							if not reentry.resolved:
								result.ambiguous = true; result.blocked = true; result.reason = "rotating_manifold_algebra_budget"
								result.fraction = range_start; return result
							if reentry.resolved:
								if not reentry.hit:
									exhausted = false; break
								time = float(reentry.time)
								continue
					if kind == "legal_hand" and not include_legal_hand:
						exhausted = false
						break
					limit = time
					endpoint = ball_from.lerp(ball_to, limit)
					result.hit = true; result.blocked = true; result.hit_fraction = global_fraction
					result.ambiguous = float(result.uncertain_fraction) <= global_fraction
					result.fraction = minf(global_fraction, float(result.uncertain_fraction))
					result.range_fraction = time
					result.triangle_offset = offset
					result.part = now.part; result.mesh_id = int(id); result.point = ball; result.surface = nearest; result.kind = kind
					result.normal = (ball - nearest).normalized()
					var weights: Vector3 = Geometry.barycentric(nearest, a + da * time, b + db * time, c + dc * time)
					result.surface_displacement = full_displacements[offset] * weights.x + full_displacements[offset + 1] * weights.y + full_displacements[offset + 2] * weights.z
					result.surface_motion_units = "meters_per_sample_interval"
					exhausted = false
					break
				# Distance cannot close faster than this Lipschitz bound. A
				# step beyond limit proves this triangle cannot touch in range.
				var safe_step: float = INF if speed_bound < 1e-12 else gap / speed_bound
				if speed_bound >= 1e-12:
					# The closest-point plane supports the entire triangle. Keep
					# that plane fixed while vertices move: none can reach the
					# ball-radius slab before this exact linear halfspace bound.
					# This is much tighter than total speed for glancing motion.
					safe_step = maxf(safe_step, _support_step(ball, nearest, radius,
						[a + da * time, b + db * time, c + dc * time], [da, db, dc], motion))
				if time + safe_step > limit:
					exhausted = false
					break
				if step == MAX_ADVANCES - 2 and not maintained_faces.is_empty():
					var grazing: Dictionary = Reentry.first_entry(ball_from, motion, a, b, c, da, db, dc, radius + CONTACT_EPSILON, limit, algebra_cache, algebra_units_limit - int(result.algebra_work_units), shared_plane)
					result.algebra_work_units += int(grazing.get("work_units", 0))
					result.algebra_queries = ceili(float(result.algebra_work_units) / ALGEBRA_UNITS_PER_QUERY)
					if grazing.resolved:
						if not grazing.hit: exhausted = false; break
						time = float(grazing.time); continue
				time += safe_step * 0.95
			if exhausted:
				# Never turn a computationally unresolved body path into a
				# successful paddle save. Caller must reject/retry the strike.
				var uncertain_fraction: float = range_start + range_span * time
				result.uncertain_fraction = minf(float(result.uncertain_fraction), uncertain_fraction)
				result.ambiguous = not result.hit or float(result.uncertain_fraction) <= float(result.get("hit_fraction", INF))
				result.blocked = result.hit or result.ambiguous
				if result.ambiguous:
					result.reason = "continuous_contact_budget"
					result.uncertain_part = now.part
					result.fraction = minf(float(result.get("hit_fraction", INF)), float(result.uncertain_fraction))
	return result

static func query_range(previous: Dictionary, current: Dictionary, ball_from: Vector3, ball_to: Vector3,
		radius: float, start_fraction: float, end_fraction: float, include_legal_hand: bool = false, departing_mesh_id: int = -1, query_budget: int = MAX_TOTAL_QUERIES, release_departures: Dictionary = {}, algebra_budget: int = MAX_ALGEBRA_QUERIES, maintained_faces: Dictionary = {}, ball_displacement: Vector3 = Vector3.INF, exact_algebra_units: int = -1, physical_velocity: Vector3 = Vector3.INF, sample_seconds: float = 0.0) -> Dictionary:
	## ball_from/to bound the re-integrated path over this frame subinterval.
	## Body/hand vertices remain the SAME global linear interpolation as the
	## original query. Returned fraction is global; range_fraction is local.
	## Surface displacement still spans the FULL sample interval for impulses.
	return query(previous, current, ball_from, ball_to, radius, 1.0, include_legal_hand, start_fraction, end_fraction, departing_mesh_id, query_budget, release_departures, algebra_budget, maintained_faces, ball_displacement, exact_algebra_units, physical_velocity, sample_seconds)

static func _proven_release_outward(ball: Vector3, nearest: Vector3, radius: float,
		vertices: Array, displacements: Array, motion: Vector3, initial_depth: float) -> bool:
	var distance: float = ball.distance_to(nearest)
	if radius - distance > initial_depth + 1e-7: return false
	var normal: Vector3 = (ball - nearest).normalized()
	if normal.length_squared() < 0.5: return false
	for i in 3:
		if (ball - Vector3(vertices[i])).dot(normal) < distance - 1e-7: return false
		if (motion - Vector3(displacements[i])).dot(normal) <= 1e-10: return false
	return true

static func _support_step(ball: Vector3, nearest: Vector3, radius: float,
		vertices: Array, displacements: Array, ball_motion: Vector3) -> float:
	var normal: Vector3 = (ball - nearest).normalized()
	if normal.length_squared() < 0.5: return 0.0
	var step := INF
	for i in 3:
		var gap: float = (ball - Vector3(vertices[i])).dot(normal) - radius
		# If floating-point triangle degeneracy loses the supporting plane,
		# retain the independent Hausdorff-speed advancement bound instead.
		if gap < -1e-7: return 0.0
		var closing: float = (Vector3(displacements[i]) - ball_motion).dot(normal)
		if closing > 1e-12: step = minf(step, maxf(0.0, gap) / closing)
	return step

static func _triangle_entry(ball: Vector3, motion: Vector3, a: Vector3, b: Vector3, c: Vector3,
		da: Vector3, db: Vector3, dc: Vector3, radius: float, limit: float) -> float:
	## Conservative moving AABB in the ball-relative frame. Every triangle
	## vertex stays inside min(initial)+min(velocity)*t .. max(initial)+
	## max(velocity)*t for t>=0. Intersect those six linear inequalities
	## before invoking distance iteration. A known earlier hit clips limit.
	var entry := 0.0
	var exit_time: float = limit
	for axis in 3:
		var low: float = minf(a[axis], minf(b[axis], c[axis])) - ball[axis]
		var high: float = maxf(a[axis], maxf(b[axis], c[axis])) - ball[axis]
		var slow: float = minf(da[axis], minf(db[axis], dc[axis])) - motion[axis]
		var fast: float = maxf(da[axis], maxf(db[axis], dc[axis])) - motion[axis]
		# low + slow*t <= radius
		if absf(slow) < 1e-12:
			if low > radius: return -1.0
		elif slow > 0.0: exit_time = minf(exit_time, (radius - low) / slow)
		else: entry = maxf(entry, (radius - low) / slow)
		# high + fast*t >= -radius
		if absf(fast) < 1e-12:
			if high < -radius: return -1.0
		elif fast < 0.0: exit_time = minf(exit_time, (-radius - high) / fast)
		else: entry = maxf(entry, (-radius - high) / fast)
		if entry > exit_time + 1e-9: return -1.0
	return maxf(0.0, entry - 1e-8)

static func _proven_departing(ball: Vector3, normal: Vector3, radius: float,
		vertices: Array, displacements: Array, ball_motion: Vector3) -> bool:
	if normal.length_squared() < 0.5: return false
	for i in 3:
		if (ball - Vector3(vertices[i])).dot(normal) < radius - CONTACT_EPSILON * 1.05: return false
		if (ball_motion - Vector3(displacements[i])).dot(normal) < -1e-10: return false
	return true

static func touching_hitting_surface(previous: Dictionary, current: Dictionary, center: Vector3,
		radius: float, fraction: float) -> bool:
	## Manifold release at a global frame time, not a wall-clock cooldown.
	if not previous.get("has_paddle", false) or not current.get("has_paddle", false): return false
	var paddle: Transform3D = _linear_frame(previous.paddle, current.paddle, clampf(fraction, 0.0, 1.0))
	if absf(paddle.basis.determinant()) < 1e-6: return true
	var has_equipment := false
	for part in current.parts.values():
		if part.get("equipment", false): has_equipment = true; break
	if not has_equipment and Surface.PaddleShape.distance_to_paddle_shape(paddle.affine_inverse() * center) <= radius + CONTACT_EPSILON: return true
	for id in current.parts:
		var now: Dictionary = current.parts[id]
		var before: Dictionary = previous.parts.get(id, now)
		var equipment: bool = now.get("equipment", false)
		if not equipment and (now.hand.is_empty() or before.hand.is_empty()): continue
		if not now.bounds.merge(before.bounds).grow(radius + CONTACT_EPSILON).has_point(center): continue
		var old: PackedVector3Array = Surface.snapshot_triangles(before)
		var posed: PackedVector3Array = Surface.snapshot_triangles(now).duplicate()
		if old.size() != posed.size(): return true # cannot prove release
		for i in posed.size(): posed[i] = old[i].lerp(posed[i], fraction)
		var hand: Dictionary = {} if equipment else {"wrist": Vector3(before.hand.wrist).lerp(now.hand.wrist, fraction),
			"distal": Vector3(before.hand.distal).lerp(now.hand.distal, fraction).normalized()}
		for i in range(0, posed.size() - 2, 3):
			var point: Vector3 = Geometry.closest_triangle(center, posed[i], posed[i + 1], posed[i + 2])
			if point.distance_to(center) <= radius + CONTACT_EPSILON and (equipment or Surface.hand_contact_kind(hand, posed, point, paddle) == "legal_hand"): return true
	return false

static func _linear_frame(before: Transform3D, after: Transform3D, fraction: float) -> Transform3D:
	## The same globally LINEAR surface interpolation used for body vertices.
	## Slerping only the paddle would invent hand/paddle separation mid-frame.
	return Transform3D(Basis(before.basis.x.lerp(after.basis.x, fraction),
		before.basis.y.lerp(after.basis.y, fraction), before.basis.z.lerp(after.basis.z, fraction)),
		before.origin.lerp(after.origin, fraction))
