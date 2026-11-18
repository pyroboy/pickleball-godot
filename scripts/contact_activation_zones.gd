extends RefCounted

## Derived contact coverage. Authored pose resources remain untouched.
## Fill only holes bounded by authored zones on opposite sides; never expand
## the silhouette into unbounded/out-of-reach space. Physical reach is separate.
const EDGE_EPSILON := 0.00001
const DEFAULT_MARGIN := 0.03
const LIVE_HALF_DEPTH := 0.14
const FLOOR_BALL_HEIGHT := 0.0375

static func minimum_height(def: PostureDefinition, margin: float = DEFAULT_MARGIN) -> float:
	# Low receiving coverage reaches the legal ball-center floor. Wrist, blade
	# clearance, crouch and bounce legality are still checked by the planner.
	return FLOOR_BALL_HEIGHT if def.height_tier == 0 else def.zone_y_min - margin
static var _margin := -1.0
static var _signatures: Dictionary = {}
static var _forwards: Dictionary = {}
static var _tiers: Dictionary = {}
static var _regions: Dictionary = {}
static var _display: Array[Dictionary] = []
static var _patches: Array[Dictionary] = []
static var _floor_bounds := Rect2()
# Exact semantic dependencies in the library's current order. Entries retain only
# booleans, integers, a Vector4 signature and floats; no pose/resource payloads.
# Vector4 intentionally preserves the OLD _signature's float32 comparison.
static var _dependency_rows: Array = []

static func _dependencies_unchanged(definitions: Array) -> bool:
	if definitions.size() != _dependency_rows.size(): return false
	for index in definitions.size():
		var def: PostureDefinition = definitions[index]
		var row: Array = _dependency_rows[index]
		if def.has_zone != bool(row[0]): return false
		if not def.has_zone: continue
		if def.posture_id != int(row[1]) or _signature(def) != row[2] or def.zone_forward_offset != float(row[3]) or def.height_tier != int(row[4]): return false
	return true

static func _remember_dependencies(definitions: Array) -> void:
	_dependency_rows.clear()
	for def: PostureDefinition in definitions:
		_dependency_rows.append([true, def.posture_id, _signature(def), def.zone_forward_offset, def.height_tier] if def.has_zone else [false])

static func _signature(def: PostureDefinition) -> Vector4:
	return Vector4(def.zone_x_min, def.zone_x_max, def.zone_y_min, def.zone_y_max)

static func refresh(margin: float = DEFAULT_MARGIN) -> void:
	var live_definitions: Array = PostureLibrary.instance().all_definitions()
	# No frame/revision gate: in-place edits are observed on the very next call.
	# Keep the existing sort/map-equality path for every dependency change,
	# including reorder/replacement and duplicate posture IDs.
	if _margin == margin and _dependencies_unchanged(live_definitions): return
	var definitions: Array = live_definitions.duplicate()
	definitions.sort_custom(func(a, b): return a.posture_id < b.posture_id)
	var signatures: Dictionary = {}
	var forwards: Dictionary = {}
	var tiers: Dictionary = {}
	for def in definitions:
		if def.has_zone:
			signatures[def.posture_id] = _signature(def)
			forwards[def.posture_id] = def.zone_forward_offset
			tiers[def.posture_id] = def.height_tier
	_remember_dependencies(live_definitions)
	if _margin == margin and signatures == _signatures and forwards == _forwards and tiers == _tiers: return
	_margin = margin
	_signatures = signatures
	_forwards = forwards
	_tiers = tiers
	_regions = {}
	_display = []
	_patches = []
	_floor_bounds = Rect2()
	var authored: Array[Dictionary] = []
	var xs: Array[float] = []
	var ys: Array[float] = []
	for def in definitions:
		if not def.has_zone: continue
		var bottom := minimum_height(def, margin)
		var rect := Rect2(def.zone_x_min - margin, bottom,
			def.zone_x_max - def.zone_x_min + margin * 2.0, def.zone_y_max + margin - bottom)
		var item := {"rect": rect, "owners": [int(def.posture_id)], "forward_min": def.zone_forward_offset - LIVE_HALF_DEPTH, "forward_max": def.zone_forward_offset + LIVE_HALF_DEPTH, "bridge": false}
		authored.append(item)
		if def.height_tier == 0:
			_floor_bounds = rect if _floor_bounds.size == Vector2.ZERO else _floor_bounds.merge(rect)
		_regions[def.posture_id] = [rect]
		_display.append(item)
		for x in [rect.position.x, rect.end.x]:
			if not xs.has(x): xs.append(x)
		for y in [rect.position.y, rect.end.y]:
			if not ys.has(y): ys.append(y)
	xs.sort(); ys.sort()
	# A horizontal/vertical visibility bridge has existing coverage on both
	# sides. This handles face seams and their edge/corner intersections without
	# treating the enclosing bounding box as reachable.
	_bridges(authored, ys, false)
	_bridges(authored, xs, true)
	for patch in _patches:
		_display.append(patch)
		for id in patch.owners: _regions[id].append(patch.rect)

static func _bridges(authored: Array[Dictionary], edges: Array[float], vertical: bool) -> void:
	for index in range(edges.size() - 1):
		var lo: float = edges[index]
		var hi: float = edges[index + 1]
		if hi - lo <= EDGE_EPSILON: continue
		var middle := (lo + hi) * 0.5
		var intervals: Array[Dictionary] = []
		for item in authored:
			var rect: Rect2 = item.rect
			var across_min: float = rect.position.x if vertical else rect.position.y
			var across_max: float = rect.end.x if vertical else rect.end.y
			if middle <= across_min or middle >= across_max: continue
			intervals.append({"start": rect.position.y if vertical else rect.position.x,
				"end": rect.end.y if vertical else rect.end.x, "item": item})
		intervals.sort_custom(func(a, b): return a.start < b.start if a.start != b.start else a.end < b.end)
		if intervals.is_empty(): continue
		var end: float = intervals[0].end
		var previous: Dictionary = intervals[0].item
		for next in intervals.slice(1):
			if float(next.start) > end + EDGE_EPSILON:
				var owners: Array = previous.owners.duplicate()
				for id in next.item.owners:
					if not owners.has(id): owners.append(id)
				owners.sort()
				var rect := Rect2(lo, end, hi - lo, next.start - end) if vertical else Rect2(end, lo, next.start - end, hi - lo)
				_append_patch({"rect": rect, "owners": owners, "forward_min": minf(previous.forward_min, next.item.forward_min), "forward_max": maxf(previous.forward_max, next.item.forward_max), "bridge": true})
			if float(next.end) > end:
				end = next.end
				previous = next.item

static func _append_patch(patch: Dictionary) -> void:
	for existing in _patches:
		if existing.owners != patch.owners or existing.forward_min != patch.forward_min or existing.forward_max != patch.forward_max: continue
		var a: Rect2 = existing.rect
		var b: Rect2 = patch.rect
		if is_equal_approx(a.position.x, b.position.x) and is_equal_approx(a.size.x, b.size.x) and (is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y)):
			existing.rect = a.merge(b); return
		if is_equal_approx(a.position.y, b.position.y) and is_equal_approx(a.size.y, b.size.y) and (is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x)):
			existing.rect = a.merge(b); return
	_patches.append(patch)

static func regions_for(def: PostureDefinition, margin: float = DEFAULT_MARGIN) -> Array:
	if _margin != margin or _signatures.get(def.posture_id, Vector4.INF) != _signature(def) or _tiers.get(def.posture_id, -1) != def.height_tier: refresh(margin)
	# Standalone/editor test definitions retain their own explicit authored area.
	if _signatures.get(def.posture_id, Vector4.INF) != _signature(def) or _tiers.get(def.posture_id, -1) != def.height_tier:
		return [Rect2(def.zone_x_min - margin, minimum_height(def, margin), def.zone_x_max - def.zone_x_min + margin * 2.0, def.zone_y_max + margin - minimum_height(def, margin))]
	return _regions.get(def.posture_id, [])

static func contains(def: PostureDefinition, lateral: float, height: float, margin: float = DEFAULT_MARGIN) -> bool:
	for rect: Rect2 in regions_for(def, margin):
		if lateral >= rect.position.x - EDGE_EPSILON and lateral <= rect.end.x + EDGE_EPSILON and height >= rect.position.y - EDGE_EPSILON and height <= rect.end.y + EDGE_EPSILON: return true
	return false

static func display_regions() -> Array[Dictionary]:
	refresh()
	return _display

static func floor_bounds() -> Rect2:
	return _floor_bounds
