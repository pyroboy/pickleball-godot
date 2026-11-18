extends RefCounted
## Presentation only. Never feeds the shot solver, reach, input or ball physics.
const SETTLE_USEC := 160000
const BLEND_USEC := 100000
const POINTS := 48
const MOTION_EPSILON := 0.004
const QUIET_EPSILON := MOTION_EPSILON * 0.5
const MOTION_BUCKET_USEC := 8000
const MAX_MOTION_SAMPLES := 64
var _motion_samples: Array = []
var _target_moving := false
var _start_moving := false
var _context_settle_until := 0
var _context_confidence_pending := false
var _target_motion_until := 0
var _start_motion_until := 0
var _target_noise_since := -1
var _start_noise_since := -1
var _observed := false
var _target := Vector3.INF
var _start := Vector3.INF
var _context := ""
var _contact_valid := false
var _aim_locked := false
var _settle_until := 0
var _path_from := PackedVector3Array()
var _path_to := PackedVector3Array()
var _path_current := PackedVector3Array()
var _path_revision := -1
var _path_risk := ""
var _blend_started := 0
var _blending := false

func reset() -> void:
	_observed = false
	_motion_samples.clear()
	_target_moving = false
	_start_moving = false
	_context_settle_until = 0
	_context_confidence_pending = false
	_target_motion_until = 0
	_start_motion_until = 0
	_target_noise_since = -1
	_start_noise_since = -1
	_settle_until = 0
	_path_from.clear(); _path_to.clear(); _path_current.clear()
	_path_revision = -1
	_path_risk = ""
	_blending = false

func _observe_motion(now_usec: int, target: Vector3, start: Vector3) -> bool:
	var target_jump := false
	var start_jump := false
	if not _motion_samples.is_empty():
		var previous: Array = _motion_samples.back()
		target_jump = now_usec - int(previous[0]) > SETTLE_USEC and target.distance_to(previous[1]) > MOTION_EPSILON
		start_jump = now_usec - int(previous[0]) > SETTLE_USEC and start.is_finite() and Vector3(previous[2]).is_finite() and start.distance_to(previous[2]) > MOTION_EPSILON
	# Keep the first and latest observation per fixed clock bucket. The first
	# anchor must survive repeated identical timestamps and tiny increments.
	var bucket := int(now_usec / MOTION_BUCKET_USEC)
	if _motion_samples.size() > 1 and int(_motion_samples[-2][0] / MOTION_BUCKET_USEC) == bucket:
		_motion_samples[-1] = [now_usec, target, start]
	else:
		_motion_samples.append([now_usec, target, start])
	var cutoff := now_usec - SETTLE_USEC
	while _motion_samples.size() > 1 and int(_motion_samples[1][0]) <= cutoff:
		_motion_samples.pop_front()
	while _motion_samples.size() > MAX_MOTION_SAMPLES:
		_motion_samples.pop_front()
	var target_radius := 0.0
	var target_speed := 0.0
	var start_speed := 0.0
	var previous_usec := now_usec
	var start_radius := 0.0
	var target_travel := 0.0
	var start_travel := 0.0
	var target_min := target
	var target_max := target
	var start_min := start
	var start_max := start
	var first_target := target
	var first_start := start
	var previous_target := Vector3.INF
	var previous_start := Vector3.INF
	for index in _motion_samples.size():
		var sample: Array = _motion_samples[index]
		var a: Vector3 = sample[1]
		var b: Vector3 = sample[2]
		if index == 0 and int(sample[0]) < cutoff and _motion_samples.size() > 1:
			var next: Array = _motion_samples[1]
			var weight := clampf(float(cutoff - int(sample[0])) / maxf(1.0, float(int(next[0]) - int(sample[0]))), 0.0, 1.0)
			a = a.lerp(next[1], weight)
			if b.is_finite() and Vector3(next[2]).is_finite(): b = b.lerp(next[2], weight)
		if index == 0: first_target = a; first_start = b
		var sample_usec: int = maxi(int(sample[0]), cutoff) if index == 0 else int(sample[0])
		var elapsed: float = maxf(1.0, float(sample_usec - previous_usec)) / 1000000.0
		if previous_target.is_finite():
			target_speed = maxf(target_speed, previous_target.distance_to(a) / elapsed)
			target_travel += previous_target.distance_to(a)
		if previous_start.is_finite() and b.is_finite():
			start_speed = maxf(start_speed, previous_start.distance_to(b) / elapsed)
			start_travel += previous_start.distance_to(b)
		previous_usec = sample_usec
		previous_target = a; previous_start = b
		target_min = target_min.min(a); target_max = target_max.max(a)
		if start.is_finite() and b.is_finite():
			start_min = start_min.min(b); start_max = start_max.max(b)
		target_radius = maxf(target_radius, target.distance_to(a))
		if start.is_finite() and b.is_finite(): start_radius = maxf(start_radius, start.distance_to(b))
	var target_noise := target_min.distance_to(target_max) <= MOTION_EPSILON * 2.0 and target.distance_to(first_target) <= target_travel * 0.5
	if target_noise:
		if _target_noise_since < 0: _target_noise_since = now_usec
	else: _target_noise_since = -1
	var target_quiet := target_radius <= QUIET_EPSILON or (_target_noise_since >= 0 and now_usec - _target_noise_since >= SETTLE_USEC)
	var start_noise := start.is_finite() and first_start.is_finite() and start_min.distance_to(start_max) <= MOTION_EPSILON * 2.0 and start.distance_to(first_start) <= start_travel * 0.5
	if start_noise:
		if _start_noise_since < 0: _start_noise_since = now_usec
	else: _start_noise_since = -1
	var start_quiet := start_radius <= QUIET_EPSILON or (_start_noise_since >= 0 and now_usec - _start_noise_since >= SETTLE_USEC)
	if target_jump or (target_radius > MOTION_EPSILON and not target_noise):
		if not _target_moving or target_jump: _target_motion_until = now_usec + SETTLE_USEC
		_target_moving = true
	elif target_quiet and now_usec >= _target_motion_until:
		_target_moving = false
	if start_jump or (start_radius > MOTION_EPSILON and not start_noise):
		if not _start_moving or start_jump: _start_motion_until = now_usec + SETTLE_USEC
		_start_moving = true
	elif start_quiet and now_usec >= _start_motion_until:
		_start_moving = false
	# A pending context cannot admit confidence from the first few millimetres
	# of a newly started motion. Use the existing quiet distance/window as
	# the rate bound; already-admitted confidence keeps ordinary hysteresis.
	var quiet_speed: float = QUIET_EPSILON * 1000000.0 / SETTLE_USEC
	var target_admission: bool = target_speed <= quiet_speed or (_target_noise_since >= 0 and now_usec - _target_noise_since >= SETTLE_USEC)
	var start_admission: bool = start_speed <= quiet_speed or (_start_noise_since >= 0 and now_usec - _start_noise_since >= SETTLE_USEC)
	return target_quiet and start_quiet and target_admission and start_admission

func observe(now_usec: int, target: Vector3, start: Vector3, context: String, contact_valid: bool, aim_locked: bool, confidence: bool = true) -> bool:
	var motion_quiet := _observe_motion(now_usec, target, start)
	var context_changed: bool = _observed and (context != _context or contact_valid != _contact_valid or aim_locked != _aim_locked)
	if not _observed or context_changed:
		_context_settle_until = now_usec + SETTLE_USEC
		_context_confidence_pending = true
	var changed: bool = _observed and (target.distance_to(_target) > MOTION_EPSILON or context != _context or contact_valid != _contact_valid or aim_locked != _aim_locked)
	if _observed and start.is_finite() and _start.is_finite(): changed = changed or start.distance_to(_start) > MOTION_EPSILON
	if not _observed or changed:
		_target = target
		if start.is_finite(): _start = start
		_context = context
		_contact_valid = contact_valid
		_aim_locked = aim_locked
		if _observed: _settle_until = now_usec + SETTLE_USEC
	_observed = true
	# Keep specific warnings on the original timing path. The motion window
	# only qualifies the positive ESTIMATED ARC confidence label.
	if _context_confidence_pending and now_usec >= _context_settle_until and motion_quiet:
		_context_confidence_pending = false
	if not confidence: return now_usec < _settle_until
	return now_usec < _context_settle_until or _context_confidence_pending or _target_moving or _start_moving

func present(points: PackedVector3Array, revision: int, risk: String, now_usec: int) -> PackedVector3Array:
	if revision != _path_revision:
		var incoming: PackedVector3Array = resample(points)
		# Do not interpolate across a changed safety classification: a new net
		# warning must not retain a visually clear path through the net.
		if _path_current.size() == incoming.size() and not incoming.is_empty() and risk == _path_risk:
			_path_from = _path_current.duplicate()
			_blending = true
		else:
			_path_from = incoming.duplicate()
			_blending = false
		_path_to = incoming
		_path_revision = revision
		_path_risk = risk
		_blend_started = now_usec
	var blend: float = clampf(float(now_usec - _blend_started) / BLEND_USEC, 0.0, 1.0)
	# Completed and deliberately snapped paths are already cached. Avoid
	# re-interpolating every vertex on every static presentation frame.
	if not _blending or blend >= 1.0:
		_path_current = _path_to
		_blending = false
		return _path_current
	_path_current.resize(_path_to.size())
	for index in _path_to.size(): _path_current[index] = _path_from[index].lerp(_path_to[index], blend)
	return _path_current

static func resample(points: PackedVector3Array) -> PackedVector3Array:
	if points.is_empty(): return PackedVector3Array()
	var distances: Array[float] = [0.0]
	for index in range(1, points.size()): distances.append(distances.back() + points[index - 1].distance_to(points[index]))
	var total: float = distances.back()
	var result := PackedVector3Array()
	result.resize(POINTS)
	var segment := 0
	for index in POINTS:
		var distance: float = total * float(index) / float(POINTS - 1)
		while segment + 1 < distances.size() and distances[segment + 1] < distance: segment += 1
		var next: int = mini(segment + 1, points.size() - 1)
		var length: float = distances[next] - distances[segment]
		result[index] = points[segment].lerp(points[next], (distance - distances[segment]) / length if length > 0.000001 else 0.0)
	return result
