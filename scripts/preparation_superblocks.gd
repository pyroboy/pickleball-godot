extends RefCounted


const Planner = preload("res://scripts/incoming_contact_planner.gd")
const WIDTH: = 2.0
const EDGE_EPSILON: = 1e-05
const MAX_HORIZON: = 3.0
const SEAM_HYSTERESIS: = 0.025
const URGENT_TIME: = 0.25


const HIGH_PREPARATION_Y: = 1.3
const BAND_NAMES: = ["Low", "Mid", "High", "Overhead"]
const COLORS: = [Color("5bdef3"), Color("8ee58a"), Color("ffc976"), Color("f292d5")]

static func layout() -> Dictionary:
	var library: = PostureLibrary.instance()
	var left: = 0.0
	var right: = 0.0
	var low_top: = 0.0
	var mid_bottom: = INF
	var mid_top: = 0.0
	var high_bottom: = INF
	var top: = 0.0
	for def in library.all_definitions():
		if not def.has_zone: continue
		left = minf(left, def.zone_x_min)
		right = maxf(right, def.zone_x_max)
		top = maxf(top, def.zone_y_max)
		if def.family not in [0, 1]: continue
		if def.height_tier == 0: low_top = maxf(low_top, def.zone_y_max)
		elif def.height_tier == 1:
			mid_bottom = minf(mid_bottom, def.zone_y_min)
			mid_top = maxf(mid_top, def.zone_y_max)
		elif def.height_tier == 2: high_bottom = minf(high_bottom, def.zone_y_min)





	var overhead: PostureDefinition = library.get_def(4)
	var low_pose_seam: float = (low_top + mid_bottom) * 0.5
	var edges: = PackedFloat32Array([0.0, (mid_top + high_bottom) * 0.5, 
		HIGH_PREPARATION_Y, overhead.zone_y_min, top])
	var front: float = (library.get_def(0).zone_forward_offset + library.get_def(2).zone_forward_offset) * 0.5
	var blocks: Array[Dictionary] = []
	for side in [-1, 1]:
		for band in range(4):
			blocks.append({"id": (0 if side < 0 else 4) + band, "side": side, "band": band, 
				"name": ("BH " if side < 0 else "FH ") + BAND_NAMES[band], 
				"x_min": left - WIDTH if side < 0 else right, 
				"x_max": left if side < 0 else right + WIDTH, 
				"y_min": edges[band], "y_max": edges[band + 1], "forward": front})
	return {"left": left, "right": right, "edges": edges, "front": front, "low_pose_seam": low_pose_seam, "blocks": blocks}

static func local_point(owner, point: Vector3) -> Vector3:
	var offset: Vector3 = point - owner.global_position
	return Vector3(offset.dot(owner._get_forehand_axis()), point.y - owner.COURT_FLOOR_Y, 
		offset.dot(owner._get_forward_axis()))

static func world_point(owner, lateral: float, height: float, forward: float) -> Vector3:
	var point: Vector3 = owner.global_position + owner._get_forehand_axis() * lateral + owner._get_forward_axis() * forward
	point.y = owner.COURT_FLOOR_Y + height
	return point

static func classify(local: Vector3, geometry: Dictionary, previous: Dictionary = {}, time: float = INF) -> Dictionary:
	if local.y < - EDGE_EPSILON: return {}
	var side: int = -1 if local.x < 0.0 else 1
	var inner: float = - float(geometry.left) if side < 0 else float(geometry.right)
	var lateral: float = absf(local.x)
	if lateral < inner - EDGE_EPSILON: return {}
	var edges: PackedFloat32Array = geometry.edges
	var band: = 3
	for index in range(3):
		if local.y < edges[index + 1]: band = index;break

	if time > URGENT_TIME and not previous.is_empty() and int(previous.get("side", 0)) == side:
		var old: int = int(previous.get("band", band))
		if old in range(4) and local.y >= edges[old] - SEAM_HYSTERESIS and local.y < edges[old + 1] + SEAM_HYSTERESIS:
			band = old
	var inside: bool = lateral <= inner + WIDTH + EDGE_EPSILON and local.y <= edges[4] + EDGE_EPSILON
	return {"side": side, "band": band, "block_id": (0 if side < 0 else 4) + band if inside else -1, 
		"directional_only": not inside, "family": 3 if band == 3 else (1 if side < 0 else 0)}

static func crossing(owner, ball, flight: Dictionary, geometry: Dictionary) -> Dictionary:
	if not Planner.should_track(owner, ball): return {}
	var fault_time: float = Planner.predicted_fault_time(owner, ball, flight)
	var samples: Array = flight.get("samples", [])
	for index in range(samples.size() - 1):
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		var da: float = local_point(owner, a.pos).z - float(geometry.front)
		var db: float = local_point(owner, b.pos).z - float(geometry.front)
		if da < 0.0 or db > 0.0 or da - db < 1e-05 or a.bounces != b.bounces: continue
		var fraction: float = clampf(da / (da - db), 0.0, 1.0)
		var time: float = lerpf(a.time, b.time, fraction)
		if time < 0.0 or time > MAX_HORIZON or time >= fault_time: continue
		var point: Vector3 = a.pos.lerp(b.pos, fraction)
		if point.z * owner.global_position.z <= 0.0: continue

		if not Planner.legal_ball(owner, ball, int(b.bounces)): continue
		return {"point": point, "time": time, "bounces": int(b.bounces)}
	return {}

static func select(owner, ball, flight: Dictionary, held: bool, previous: Dictionary = {}) -> Dictionary:
	if not held: return {}
	var geometry: = layout()
	var prediction: = crossing(owner, ball, flight, geometry)
	if prediction.is_empty(): return {}
	var local: = local_point(owner, prediction.point)
	var selected: = classify(local, geometry, previous, float(prediction.time))
	if selected.is_empty(): return {}
	var side: int = selected.side
	var ids: Array = [7, 2, 2, 4] if side < 0 else [5, 0, 0, 4]
	var id: int = ids[int(selected.band)]
	if int(selected.band) == 0 and local.y >= float(geometry.low_pose_seam): id = 14 if side < 0 else 13
	var base: PostureDefinition = PostureLibrary.instance().get_def(id)


	var pose: PostureDefinition = base.lerp_with(base, 0.0)
	var target: Vector3 = prediction.point - owner._get_forehand_axis() * base.paddle_forehand_mul - owner._get_forward_axis() * base.zone_forward_offset
	target.y = owner.ground_y
	if absf(target.x) > PickleballConstants.COURT_WIDTH * 0.5 or absf(target.z) > PickleballConstants.BASELINE_Z: return {}
	if owner.bounds_ready and (target.x < owner.min_x or target.x > owner.max_x or target.z < owner.min_z or target.z > owner.max_z): return {}
	prediction.merge(selected)
	prediction.merge({"flight_id": ball.flight_id, "posture": base.posture_id, "def": pose, 
		"target_root": target, "distance": target.distance_to(owner.global_position), "neutral": false, 
		"lunge": false, "preparation_only": true, "superblock_advisory": true, 
		"label": ("Beyond · " if selected.directional_only else "") + ("Overhead" if selected.band == 3 else BAND_NAMES[selected.band] + (" backhand" if side < 0 else " forehand"))})
	return prediction
