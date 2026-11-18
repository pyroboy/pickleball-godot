extends RefCounted


const D = preload("res://scripts/player_body_dimensions.gd")
const SIDES: = 16
static var _bind_ring_cache: Dictionary = {}

static func rings() -> Array[Vector3]:
	var p: float = D.PELVIS_CENTER_Y
	var a: float = p + D.PELVIS_HALF_HEIGHT
	var c: float = D.CHEST_CENTER_Y
	return [Vector3(0.15, p - 0.1, 0.098), Vector3(0.165, p - 0.06, 0.105), Vector3(0.165, p + 0.06, 0.108), Vector3(0.153, a, 0.101), 
		Vector3(0.15, a + 0.005, 0.099), Vector3(0.145, a + 0.03, 0.096), Vector3(0.135, a + 0.06, 0.091), Vector3(0.14, a + 0.1, 0.097), 
		Vector3(0.144, c - 0.17, 0.091), Vector3(0.154, c - 0.135, 0.095), Vector3(0.167, c + 0.02, 0.098), Vector3(0.18, c + 0.082, 0.1), 
		Vector3(0.112, c + 0.115, 0.077), Vector3(0.066, c + 0.125, 0.061), Vector3(0.048, c + 0.13, 0.043), Vector3(0.044, c + 0.174, 0.041), Vector3(0.051, c + 0.21, 0.047)]

static func weights() -> Array[Vector3]:
	return [Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0.85, 0.15, 0), Vector3(0.75, 0.25, 0), 
		Vector3(0.3, 0.7, 0), Vector3(0, 0.9, 0.1), Vector3(0, 0.55, 0.45), Vector3(0, 0.15, 0.85), 
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]

static func cross_section() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in SIDES:
		var angle: float = - PI * 0.5 + TAU * index / SIDES
		result.append(Vector2(sin(angle), - cos(angle)))
	return result

static func surface_rings(back_facing: bool = false) -> Array[PackedVector3Array]:
	if _bind_ring_cache.has(back_facing): return _bind_ring_cache[back_facing]
	var result: Array[PackedVector3Array] = []
	var profile: Array[Vector3] = rings()
	var cross: Array[Vector2] = cross_section()
	for section in profile:
		var ring: = PackedVector3Array()
		var chest: float = exp( - pow((section.y - D.CHEST_CENTER_Y - 0.006) / 0.07, 2.0))
		var scapula: float = exp( - pow((section.y - D.CHEST_CENTER_Y - 0.055) / 0.055, 2.0))
		for corner in cross:
			var point: = Vector3(corner.x * section.x, section.y, corner.y * section.z)


			if section.y > D.CHEST_CENTER_Y + 0.04 and section.y < D.CHEST_CENTER_Y + 0.12:
				point.y += 0.02 * exp( - pow((section.y - D.CHEST_CENTER_Y - 0.082) / 0.022, 2.0)) * pow(absf(corner.x), 4.0)

			var lobe: float = exp( - pow((absf(corner.x) - 0.43) / 0.24, 2.0))
			var sternum: float = exp( - pow(corner.x / 0.18, 2.0))
			var front: float = pow(maxf( - corner.y, 0.0), 4.0)
			var back: float = pow(maxf(corner.y, 0.0), 4.0)
			point.z -= chest * front * (0.011 * lobe - 0.003 * sternum)
			point.z += scapula * back * (0.008 * lobe - 0.002 * sternum)
			if back_facing: point = Vector3( - point.x, point.y, - point.z)
			ring.append(point)
		result.append(ring)
	_bind_ring_cache[back_facing] = result
	return result

static func region(section: int) -> String:
	if section < 4: return "pelvis"
	if section < 8: return "abdomen"
	if section < 13: return "ribcage"
	return "neck"
