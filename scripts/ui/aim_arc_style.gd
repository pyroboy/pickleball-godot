extends RefCounted
## Presentation-only, stateless trajectory strokes. There is deliberately no clock,
## revision, smoothing, solver, input or gameplay state in this helper.
const DASHED := 0
const SOLID := 1
const DASH_PIXELS := 14.0
const GAP_PIXELS := 9.0
const MAX_INPUT_POINTS := 512
const MAX_STROKES := 4096
const MAX_SCREEN_COORDINATE := 10000000.0
const EPSILON := 0.00001

static func is_projectable(point: Vector3, camera: Camera3D) -> bool:
	if camera == null or not point.is_finite(): return false
	var depth: float = -(camera.global_transform.affine_inverse() * point).z
	return depth >= maxf(camera.near, 0.0001) and depth <= camera.far

static func project_path(world: PackedVector3Array, camera: Camera3D) -> PackedVector2Array:
	# Clip each world edge to the camera depth slab before projecting. INF marks
	# discontinuities, so invalid/behind-camera samples can never be bridged.
	var result := PackedVector2Array()
	if camera == null or world.is_empty() or world.size() > MAX_INPUT_POINTS: return result
	var inverse: Transform3D = camera.global_transform.affine_inverse()
	var near_depth: float = maxf(camera.near, 0.0001)
	var far_depth: float = camera.far
	if not inverse.is_finite() or not is_finite(near_depth) or not is_finite(far_depth) or far_depth <= near_depth: return result
	if not is_projectable(world[0], camera): result.append(Vector2.INF)
	if world.size() == 1:
		if result.is_empty(): result.append(camera.unproject_position(world[0]))
		return result
	for index in range(1, world.size()):
		var a: Vector3 = world[index - 1]
		var b: Vector3 = world[index]
		if not a.is_finite() or not b.is_finite():
			_break_run(result)
			continue
		var depth_a: float = -(inverse * a).z
		var depth_b: float = -(inverse * b).z
		var depth_delta: float = depth_b - depth_a
		var from_t := 0.0
		var to_t := 1.0
		if absf(depth_delta) <= EPSILON:
			if depth_a < near_depth or depth_a > far_depth:
				_break_run(result)
				continue
		else:
			var first: float = (near_depth - depth_a) / depth_delta
			var second: float = (far_depth - depth_a) / depth_delta
			from_t = maxf(0.0, minf(first, second))
			to_t = minf(1.0, maxf(first, second))
			if from_t > to_t:
				_break_run(result)
				continue
		if from_t > 0.0: _break_run(result)
		var screen_a: Vector2 = camera.unproject_position(a if from_t == 0.0 else a.lerp(b, from_t))
		var screen_b: Vector2 = camera.unproject_position(b if to_t == 1.0 else a.lerp(b, to_t))
		if not screen_a.is_finite() or not screen_b.is_finite():
			_break_run(result)
			continue
		if result.is_empty() or not result[-1].is_finite(): result.append(screen_a)
		elif not result[-1].is_equal_approx(screen_a):
			_break_run(result)
			result.append(screen_a)
		result.append(screen_b)
		if to_t < 1.0: _break_run(result)
	return result

static func _break_run(points: PackedVector2Array) -> void:
	if points.is_empty() or points[-1].is_finite(): points.append(Vector2.INF)

static func geometry(path: PackedVector2Array, viewport: Rect2, scale: float = 1.0, style: int = DASHED) -> Dictionary:
	var lines := PackedVector2Array()
	var endpoints := PackedVector2Array()
	var overflow := false
	# Projection can add two clipping boundaries per original edge.
	if path.size() > MAX_INPUT_POINTS * 3 or not viewport.position.is_finite() or not viewport.size.is_finite() or viewport.size.x <= 0.0 or viewport.size.y <= 0.0:
		return {"lines": lines, "endpoints": endpoints, "overflow": path.size() > MAX_INPUT_POINTS * 3}
	scale = clampf(scale, 0.25, 4.0) if is_finite(scale) else 1.0
	var bounds: Rect2 = viewport.grow(3.0 * scale)
	var dash: float = DASH_PIXELS * scale
	var period: float = (DASH_PIXELS + GAP_PIXELS) * scale
	var distance := 0.0
	for index in range(1, path.size()):
		var a: Vector2 = path[index - 1]
		var b: Vector2 = path[index]
		if not a.is_finite() or not b.is_finite():
			distance = 0.0
			continue
		if maxf(maxf(absf(a.x), absf(a.y)), maxf(absf(b.x), absf(b.y))) > MAX_SCREEN_COORDINATE:
			distance = 0.0
			continue
		var length: float = a.distance_to(b)
		if not is_finite(length):
			distance = 0.0
			continue
		if length <= EPSILON: continue
		var clip: Vector2 = _clip_edge(a, b, bounds)
		if clip.is_finite():
			if style == SOLID:
				lines.append(a.lerp(b, clip.x)); lines.append(a.lerp(b, clip.y))
			else:
				# Advance phase analytically over off-screen distance. We only loop
				# over visible dashes, never over huge near-plane projections.
				var from_distance: float = distance + length * clip.x
				var to_distance: float = distance + length * clip.y
				var cycle: float = floor(from_distance / period)
				while cycle * period < to_distance:
					var from_dash: float = maxf(from_distance, cycle * period)
					var to_dash: float = minf(to_distance, cycle * period + dash)
					if to_dash - from_dash > EPSILON:
						lines.append(a.lerp(b, clampf((from_dash - distance) / length, 0.0, 1.0)))
						lines.append(a.lerp(b, clampf((to_dash - distance) / length, 0.0, 1.0)))
					if lines.size() >= MAX_STROKES * 2:
						overflow = true
						break
					cycle += 1.0
			distance += length
		else:
			distance += length
		if lines.size() >= MAX_STROKES * 2:
			overflow = true
			break
	# The tiny constant endpoint caps preserve the exact source/terminal point even
	# when the last dash would fall in a gap. Never move an endpoint to a dash.
	if not path.is_empty():
		if path[0].is_finite() and bounds.has_point(path[0]): endpoints.append(path[0])
		if path.size() > 1 and path[-1].is_finite() and bounds.has_point(path[-1]) and (endpoints.is_empty() or path[-1] != endpoints[0]): endpoints.append(path[-1])
	# Fail closed on deliberately pathological input rather than display a
	# silently truncated trajectory with misleading detached endpoint caps.
	if overflow: lines.clear(); endpoints.clear()
	return {"lines": lines, "endpoints": endpoints, "overflow": overflow}

static func _clip_edge(a: Vector2, b: Vector2, bounds: Rect2) -> Vector2:
	var delta: Vector2 = b - a
	var from_t := 0.0
	var to_t := 1.0
	for axis in 2:
		if absf(delta[axis]) <= EPSILON:
			if a[axis] < bounds.position[axis] or a[axis] > bounds.end[axis]: return Vector2.INF
		else:
			var first: float = (bounds.position[axis] - a[axis]) / delta[axis]
			var second: float = (bounds.end[axis] - a[axis]) / delta[axis]
			from_t = maxf(from_t, minf(first, second))
			to_t = minf(to_t, maxf(first, second))
			if from_t > to_t: return Vector2.INF
	return Vector2(from_t, to_t)

static func draw(canvas: CanvasItem, path: PackedVector2Array, viewport: Rect2, color: Color, scale: float = 1.0, style: int = DASHED) -> void:
	scale = clampf(scale, 0.25, 4.0) if is_finite(scale) else 1.0
	var strokes: Dictionary = geometry(path, viewport, scale, style)
	if not strokes.lines.is_empty(): canvas.draw_multiline(strokes.lines, color, 2.2 * scale, true)
	for endpoint in strokes.endpoints: canvas.draw_circle(endpoint, 1.1 * scale, color, true, -1.0, true)
