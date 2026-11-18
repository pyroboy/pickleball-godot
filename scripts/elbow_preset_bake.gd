extends RefCounted
## Versioned, data-only persistence boundary for the optional smoothing overlay.
## Structural validity is intentionally separate from runtime source/rig validity:
## stale but well-formed work can be inspected, copied and explicitly replaced.
const VERSION := 1
const MODEL_VERSION := "head-locked-circle-hermite-elapsed-v1"
const MAX_SAMPLES := 481
const MAX_KNOTS := 481
const MAX_BYTES := 2097152
## Fingerprint-only quantum absorbs Godot JSON parser decimal rounding. Stored
## authored geometry and playback gates keep their original numeric precision.
const CHECKSUM_QUANTUM := 0.000000001
const SCOPES := ["stroke_authored", "stroke_runtime"]
const TOP_KEYS := ["version", "model", "scope", "source_id", "source_sha256", "payload_sha256", "handedness", "active_sides", "rotation_deg", "offsets", "duration", "rig", "routes", "samples"]
const SAMPLE_KEYS := ["p", "body", "paddle", "shoulders", "hands", "elbows", "skin", "modes", "weight"]
const MAX_ADMITTED := 16
static var _admitted: Array = []

static func clone(value: Dictionary) -> Dictionary:
	return value.duplicate(true)

## One-time runtime admission validates unknown dictionaries before playback can
## index them. Deep freezing makes the identity-cache hit safe without rehashing
## hundreds of samples each frame. Replacement/deep copies must revalidate.
static func admit(value) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	for admitted in _admitted:
		if is_same(admitted, value) and value.is_read_only(): return true
	if not valid(value): return false
	_freeze(value)
	if _admitted.size() >= MAX_ADMITTED: _admitted.pop_front()
	_admitted.append(value)
	return true

static func _freeze(value) -> void:
	if value is Dictionary:
		for item in value.values(): _freeze(item)
		value.make_read_only()
	elif value is Array:
		for item in value: _freeze(item)
		value.make_read_only()

## Accidental-corruption checksum, not a signature or an authenticity guarantee.
## Only editor-side validated results call this; playback never reseals payloads.
static func seal(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var result := value.duplicate(true)
	result.payload_sha256 = "0".repeat(64)
	if not _valid_shape(result): return {}
	result.payload_sha256 = payload_fingerprint(result)
	return result

static func payload_fingerprint(value: Dictionary) -> String:
	var source := value.duplicate(true)
	source.erase("payload_sha256")
	return JSON.stringify(_checksum_value(source), "", true, true).sha256_text()

static func _checksum_value(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _checksum_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_checksum_value(item))
		return result
	if value is int or value is float: return roundi(float(value) * 1000000000.0)
	return value

static func fingerprint_fields(fields: Dictionary, scope: String, source_id: int, handedness: int) -> String:
	if scope not in SCOPES or source_id < 0 or source_id > 20 or handedness not in [0, 1]: return ""
	var source := fields.duplicate(true)
	source.erase("elbow_preset_bake")
	# Orientation interpolation is part of the baked motion, even when authored
	# fields are byte-identical. Old bakes remain valid data but no longer match.
	var document := {"model": MODEL_VERSION, "paddle_rotation_model": "resolved-display-quaternion-v1", "scope": scope, "source_id": source_id, "handedness": handedness, "fields": source}
	return JSON.stringify(_checksum_value(document), "", true, true).sha256_text()

static func _canonical(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_canonical(item))
		return result
	if value is float and is_finite(value) and value == floor(value): return int(value)
	return value

static func valid(value) -> bool:
	if not _valid_shape(value): return false
	return value.is_empty() or value.payload_sha256 == payload_fingerprint(value)

static func _valid_shape(value) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not _keys(value, TOP_KEYS): return false
	if not _integer(value.version, VERSION, VERSION) or value.model != MODEL_VERSION: return false
	if not value.scope is String or value.scope not in SCOPES: return false
	if not _integer(value.source_id, 0, 20) or not _integer(value.handedness, 0, 1): return false
	if not _sha256(value.source_sha256) or not _sha256(value.payload_sha256): return false
	if not value.active_sides is Array or value.active_sides.size() != 2: return false
	for active in value.active_sides:
		if not active is bool: return false
	if not value.active_sides[0] and not value.active_sides[1]: return false
	# Vector3/Basis use float32 channels: their exact +/-0.20m or 15-degree
	# endpoint can round a few ulps above the decimal user-facing limit.
	if not _numbers(value.rotation_deg, 3, 15.00001) or not _rows(value.offsets, 2, 3, 0.20000001): return false
	if not _number(value.duration, 120.0) or value.duration <= 0.0: return false
	if not _keys(value.rig, ["links", "sockets", "anatomy"]): return false
	if not _rows(value.rig.links, 2, 2, 5.0) or not _rows(value.rig.sockets, 2, 3, 5.0) or not _rows(value.rig.anatomy, 2, 9, 8.0): return false
	for arm in value.rig.links:
		for length in arm:
			if length <= 0.0: return false
	if not value.routes is Array or value.routes.size() != 2: return false
	for side in range(2):
		if not value.routes[side] is Dictionary: return false
		if not value.active_sides[side]:
			if not value.routes[side].is_empty(): return false
		elif not _route(value.routes[side]): return false
	if not value.samples is Array or value.samples.size() < 2 or value.samples.size() > MAX_SAMPLES: return false
	var previous := -1.0
	for sample in value.samples:
		if not _keys(sample, SAMPLE_KEYS) or not _progress(sample.p) or float(sample.p) <= previous: return false
		previous = float(sample.p)
		if not _transform(sample.body) or not _transform(sample.paddle): return false
		if not _rows(sample.shoulders, 2, 3, 20.0) or not _rows(sample.elbows, 2, 3, 20.0): return false
		if not _transforms(sample.hands, 2) or not _transforms(sample.skin, 3): return false
		if not sample.modes is Array or sample.modes.size() != 2: return false
		for mode in sample.modes:
			if not _mode(mode): return false
		if not _progress(sample.weight): return false
	if not _endpoints(value.samples[0].p, value.samples[-1].p): return false
	return JSON.stringify(value, "", true, true).to_utf8_buffer().size() <= MAX_BYTES

static func _route(route) -> bool:
	if not _keys(route, ["knots"]): return false
	if not route.knots is Array or route.knots.size() < 2 or route.knots.size() > MAX_KNOTS: return false
	var previous := -1.0
	for knot in route.knots:
		if not _numbers(knot, 9, 10000.0) or not _progress(knot[0]) or float(knot[0]) <= previous: return false
		previous = float(knot[0])
		if absf(float(knot[1])) > 128.0 * PI: return false
		var axis := Vector3(knot[3], knot[4], knot[5])
		var reference := Vector3(knot[6], knot[7], knot[8])
		if absf(axis.length_squared() - 1.0) > 0.002 or absf(reference.length_squared() - 1.0) > 0.002 or absf(axis.dot(reference)) > 0.002: return false
	return _endpoints(route.knots[0][0], route.knots[-1][0])

static func _keys(value, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)

static func _integer(value, minimum: int, maximum: int) -> bool:
	return _number(value, float(maxi(absi(minimum), absi(maximum)))) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _number(value, bound: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= bound

static func _numbers(value, count: int, bound: float) -> bool:
	if not value is Array or value.size() != count: return false
	for component in value:
		if not _number(component, bound): return false
	return true

static func _rows(value, count: int, width: int, bound: float) -> bool:
	if not value is Array or value.size() != count: return false
	for row in value:
		if not _numbers(row, width, bound): return false
	return true

static func _transform(value) -> bool:
	if not _numbers(value, 12, 20.0): return false
	for index in range(9):
		if absf(float(value[index])) > 8.0: return false
	return true

static func _transforms(value, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for transform in value:
		if not _transform(transform): return false
	return true

static func _progress(value) -> bool:
	return _number(value, 1.0) and value >= 0.0

static func _endpoints(first, last) -> bool:
	return float(first) == 0.0 and float(last) == 1.0

static func _sha256(value) -> bool:
	if not value is String or value.length() != 64: return false
	for letter in value:
		if not letter in "0123456789abcdef": return false
	return true

static func _mode(value) -> bool:
	if not value is String or value.is_empty() or value.length() > 32: return false
	for letter in value:
		if not letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ_": return false
	return true
