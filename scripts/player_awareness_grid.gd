extends Node




var _player: CharacterBody3D


const GRID_LATERAL: = 2.3
const GRID_FORWARD: = 6.0
const GRID_BEHIND: = 1.0
const GRID_HEIGHT_MAX: = 2.1


const DENSE_RADIUS: = 0.8
const MEDIUM_RADIUS: = 1.5
const DENSE_SPACING: = 0.25
const MEDIUM_SPACING: = 0.35
const SPARSE_SPACING: = 0.5

const COURT_FLOOR_Y: = PickleballConstants.FLOOR_Y
const HEIGHT_FULL: Array[float] = [COURT_FLOOR_Y, 0.2, 0.35, 0.5, 0.9, 1.3, 1.8]
const HEIGHT_MEDIUM: Array[float] = [COURT_FLOOR_Y, 0.22, 0.4, 0.55, 0.9, 1.3]
const HEIGHT_SPARSE: Array[float] = [COURT_FLOOR_Y, 0.3, 0.9, 1.8]


const FLOOR_FORWARD_SPACING: = 0.2
const FLOOR_FORWARD_Z_MAX: = 3.5
const HEIGHT_FLOOR: Array[float] = [COURT_FLOOR_Y, 0.18, 0.32, 0.48]


const ACTIVATION_RADIUS: = 0.4
const STEP_TIME: = 0.04
const FADE_HALFLIFE: = 0.15


const TIME_RED: = 0.3
const TIME_ORANGE: = 0.6
const TIME_YELLOW: = 1.0

const COLOR_RED: = Color(1.0, 0.1, 0.0, 1.0)
const COLOR_ORANGE: = Color(1.0, 0.45, 0.0, 1.0)
const COLOR_YELLOW: = Color(1.0, 0.95, 0.0, 0.95)
const COLOR_GREEN: = Color(0.0, 1.0, 0.3, 0.9)
const COLOR_INACTIVE: = Color(0.5, 0.5, 0.6, 0.35)
const EMISSION_IDLE: = 0.3


const VERTEX_RADIUS: = 0.06
const EMISSION_MAX: = 3.5
const COLOR_UPDATE_INTERVAL: = 2


const ZONE_SCORE_WEIGHT: = 0.08

enum ZoneID{
	FOREHAND_HIGH, 
	FOREHAND_MID, 
	FOREHAND_LOW, 
	FOREHAND_WIDE, 
	BACKHAND_HIGH, 
	BACKHAND_MID, 
	BACKHAND_LOW, 
	BACKHAND_WIDE, 
	CENTER_HIGH, 
	CENTER_MID, 
	CENTER_LOW, 
	OVERHEAD, 
	BEHIND, 
}


var _zone_to_postures: Dictionary = {}


var _local_positions: PackedVector3Array = PackedVector3Array()
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _activation: PackedFloat32Array = PackedFloat32Array()
var _time_to_arrival: PackedFloat32Array = PackedFloat32Array()
var _zone_ids: PackedInt32Array = PackedInt32Array()


var _grid_root: Node3D = null
var _shared_mesh: SphereMesh = null
var _zone_scores: Dictionary = {}
var _posture_scores: Dictionary = {}
var _is_locked: bool = false
var _player_base_y: float = 0.0

func _ready() -> void :
	_player = get_parent() as CharacterBody3D
	_init_zone_mapping()
	_build_grid()



func _init_zone_mapping() -> void :
	var PP = _player.PaddlePosture
	_zone_to_postures = {
		ZoneID.FOREHAND_HIGH: [PP.FOREHAND], 
		ZoneID.FOREHAND_MID: [PP.FOREHAND, PP.MID_LOW_FOREHAND], 
		ZoneID.FOREHAND_LOW: [PP.LOW_FOREHAND], 
		ZoneID.FOREHAND_WIDE: [PP.WIDE_FOREHAND, PP.MID_LOW_WIDE_FOREHAND, PP.LOW_WIDE_FOREHAND], 
		ZoneID.BACKHAND_HIGH: [PP.BACKHAND], 
		ZoneID.BACKHAND_MID: [PP.BACKHAND, PP.MID_LOW_BACKHAND], 
		ZoneID.BACKHAND_LOW: [PP.LOW_BACKHAND], 
		ZoneID.BACKHAND_WIDE: [PP.WIDE_BACKHAND, PP.MID_LOW_WIDE_BACKHAND, PP.LOW_WIDE_BACKHAND], 
		ZoneID.CENTER_HIGH: [PP.FORWARD, PP.VOLLEY_READY], 
		ZoneID.CENTER_MID: [PP.FORWARD, PP.MID_LOW_FORWARD, PP.VOLLEY_READY], 
		ZoneID.CENTER_LOW: [PP.LOW_FORWARD], 
		ZoneID.OVERHEAD: [PP.MEDIUM_OVERHEAD, PP.HIGH_OVERHEAD], 
		ZoneID.BEHIND: [], 
	}



func _build_grid() -> void :
	_player_base_y = _player.global_position.y
	_grid_root = Node3D.new()
	_grid_root.name = "AwarenessGridRoot"
	_grid_root.visible = false
	_player.add_child(_grid_root)

	_shared_mesh = SphereMesh.new()
	_shared_mesh.radius = VERTEX_RADIUS
	_shared_mesh.height = VERTEX_RADIUS * 2.0
	_shared_mesh.radial_segments = 3
	_shared_mesh.rings = 1


	var positions: Array[Vector3] = []
	var max_extent: float = sqrt(GRID_LATERAL * GRID_LATERAL + GRID_FORWARD * GRID_FORWARD) + 1.0
	_generate_zone(positions, SPARSE_SPACING, MEDIUM_RADIUS, max_extent, - GRID_BEHIND, GRID_FORWARD, HEIGHT_SPARSE)
	_generate_zone(positions, MEDIUM_SPACING, DENSE_RADIUS, MEDIUM_RADIUS, - GRID_BEHIND, GRID_FORWARD, HEIGHT_MEDIUM)
	_generate_zone(positions, DENSE_SPACING, 0.0, DENSE_RADIUS, - GRID_BEHIND, GRID_FORWARD, HEIGHT_FULL)

	_generate_floor_forward(positions)


	for pos in positions:
		_local_positions.append(pos)
		_activation.append(0.0)
		_time_to_arrival.append(INF)
		_zone_ids.append(_assign_zone(pos))

		var mat: = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.emission_enabled = true
		mat.albedo_color = COLOR_INACTIVE
		mat.emission = Color(COLOR_INACTIVE.r, COLOR_INACTIVE.g, COLOR_INACTIVE.b, 1.0)
		mat.emission_energy_multiplier = EMISSION_IDLE
		_materials.append(mat)

		var mi: = MeshInstance3D.new()
		mi.mesh = _shared_mesh
		mi.material_override = mat
		mi.visible = true

		mi.position = _local_to_node_pos(pos)
		_grid_root.add_child(mi)
		_meshes.append(mi)

func _generate_zone(out: Array[Vector3], spacing: float, min_dist: float, max_dist: float, 
		z_min: float, z_max: float, heights: Array[float]) -> void :
	var x: = - GRID_LATERAL
	while x <= GRID_LATERAL:
		var z: = z_min
		while z <= z_max:
			var xz_dist: = sqrt(x * x + z * z)
			if xz_dist >= min_dist and xz_dist < max_dist:
				for y in heights:
					if y <= GRID_HEIGHT_MAX:
						out.append(Vector3(x, y, z))
			z += spacing
		x += spacing

func _generate_floor_forward(out: Array[Vector3]) -> void :


	var sp: = FLOOR_FORWARD_SPACING
	var x: = - GRID_LATERAL
	while x <= GRID_LATERAL:
		var z: = 0.0
		while z <= FLOOR_FORWARD_Z_MAX:
			for y in HEIGHT_FLOOR:
				out.append(Vector3(x, y, z))
			z += sp
		x += sp

func _assign_zone(local_pos: Vector3) -> int:
	var x: = local_pos.x
	var y: = local_pos.y - _player_base_y
	var z: = local_pos.z

	if z < 0.0:
		return ZoneID.BEHIND
	if y > 0.9:
		return ZoneID.OVERHEAD

	var is_wide: bool = abs(x) > 0.65
	if is_wide:
		if x > 0.0:
			return ZoneID.FOREHAND_WIDE
		return ZoneID.BACKHAND_WIDE


	if x > 0.3:
		if y > 0.55:
			return ZoneID.FOREHAND_HIGH
		if y > 0.2:
			return ZoneID.FOREHAND_MID
		return ZoneID.FOREHAND_LOW
	elif x < -0.3:
		if y > 0.55:
			return ZoneID.BACKHAND_HIGH
		if y > 0.2:
			return ZoneID.BACKHAND_MID
		return ZoneID.BACKHAND_LOW
	else:
		if y > 0.55:
			return ZoneID.CENTER_HIGH
		if y > 0.2:
			return ZoneID.CENTER_MID
		return ZoneID.CENTER_LOW



func _world_to_local(world_pt: Vector3) -> Vector3:


	var offset: = world_pt - _player.global_position
	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	return Vector3(offset.dot(fh), world_pt.y, offset.dot(fwd))

func _local_to_node_pos(local_pos: Vector3) -> Vector3:


	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	return fh * local_pos.x + Vector3.UP * (local_pos.y - _player_base_y) + fwd * local_pos.z



func set_trajectory_points(points: Array[Vector3]) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_set_trajectory_points(points)
	PerfMonitor.record("debug.awareness_grid", Time.get_ticks_usec() - _pt)

func _perf_set_trajectory_points(points: Array[Vector3]) -> void:
	if _is_locked:
		return
	if points.is_empty():
		return


	var local_pts: Array[Vector3] = []
	var local_times: Array[float] = []
	for i in range(points.size()):
		local_pts.append(_world_to_local(points[i]))
		local_times.append(i * STEP_TIME)


	var interp_pts: Array[Vector3] = []
	var interp_times: Array[float] = []
	for i in range(local_pts.size()):
		interp_pts.append(local_pts[i])
		interp_times.append(local_times[i])
		if i < local_pts.size() - 1:
			var d: = local_pts[i].distance_to(local_pts[i + 1])
			if d > ACTIVATION_RADIUS:
				var n_sub: = ceili(d / ACTIVATION_RADIUS)
				for s in range(1, n_sub):
					var t: = float(s) / float(n_sub)
					interp_pts.append(local_pts[i].lerp(local_pts[i + 1], t))
					interp_times.append(lerpf(local_times[i], local_times[i + 1], t))

	_activate_vertices(interp_pts, interp_times)
	_compute_zone_scores()
	_compute_posture_scores()

func _activate_vertices(pts: Array[Vector3], times: Array[float]) -> void :

	_activation.fill(0.0)
	_time_to_arrival.fill(INF)

	# Only vertices within ACTIVATION_RADIUS of a point can change, so look them up
	# in ACTIVATION_RADIUS-sized cells (27 neighbours) instead of scanning all
	# ~2,600 vertices per point. Point order is unchanged, so results are identical
	# to the brute-force scan (verified by scripts/debug/test_awareness_grid_buckets.gd).
	if _buckets.is_empty(): _build_buckets()
	for pt_idx in range(pts.size()):
		var pt: Vector3 = pts[pt_idx]
		var time: float = times[pt_idx]
		var cell := _cell_of(pt)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var bucket = _buckets.get(cell + Vector3i(dx, dy, dz))
					if bucket == null: continue
					for v_idx in bucket:
						var d: float = _local_positions[v_idx].distance_to(pt)
						if d < ACTIVATION_RADIUS:
							var strength: float = 1.0 - (d / ACTIVATION_RADIUS)
							if strength > _activation[v_idx]:
								_activation[v_idx] = strength
								_time_to_arrival[v_idx] = time

var _buckets: Dictionary = {}   # Vector3i cell -> PackedInt32Array of vertex indices

func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / ACTIVATION_RADIUS), floori(p.y / ACTIVATION_RADIUS), floori(p.z / ACTIVATION_RADIUS))

func _build_buckets() -> void:
	_buckets.clear()
	for v_idx in range(_local_positions.size()):
		var c := _cell_of(_local_positions[v_idx])
		var b: PackedInt32Array = _buckets.get(c, PackedInt32Array())
		b.append(v_idx)
		_buckets[c] = b



func _compute_zone_scores() -> void :
	_zone_scores.clear()
	for v_idx in range(_local_positions.size()):
		if _activation[v_idx] < 0.05:
			continue
		var zone: int = _zone_ids[v_idx]
		var time: float = _time_to_arrival[v_idx]
		var urgency: float = clampf(1.0 - time / 1.5, 0.0, 1.0)
		var weight: float = _activation[v_idx] * (0.3 + 0.7 * urgency)
		_zone_scores[zone] = _zone_scores.get(zone, 0.0) + weight

func _compute_posture_scores() -> void :
	_posture_scores.clear()
	for zone in _zone_scores:
		var score: float = _zone_scores[zone]
		var postures: Array = _zone_to_postures.get(zone, [])
		for p in postures:
			_posture_scores[p] = _posture_scores.get(p, 0.0) + score

func get_posture_zone_scores() -> Dictionary:
	return _posture_scores






func get_ttc_at_world_point(world_pt: Vector3, radius: float = 0.4) -> float:
	var local_pt: Vector3 = _world_to_local(world_pt)
	var min_ttc: float = INF
	var r2: float = radius * radius
	for v_idx in range(_local_positions.size()):
		if _activation[v_idx] < 0.05:
			continue
		var d2: float = _local_positions[v_idx].distance_squared_to(local_pt)
		if d2 < r2:
			var t: float = _time_to_arrival[v_idx]
			if t < min_ttc:
				min_ttc = t
	return min_ttc




func get_approach_info() -> Dictionary:





	var total_weight: float = 0.0
	var weighted_height: float = 0.0
	var weighted_lateral: float = 0.0
	var max_urgency: float = 0.0
	var active_count: int = 0
	for v_idx in range(_local_positions.size()):
		if _activation[v_idx] < 0.1:
			continue
		var time: float = _time_to_arrival[v_idx]
		var urgency: float = clampf(1.0 - time / 1.5, 0.0, 1.0)
		var pos: Vector3 = _local_positions[v_idx]

		var xz_dist: float = sqrt(pos.x * pos.x + pos.z * pos.z)


		var proximity: float = 1.0 / (1.0 + xz_dist * 1.5)
		var w: float = _activation[v_idx] * (0.1 + 0.3 * urgency + 0.6 * proximity)
		weighted_height += pos.y * w
		weighted_lateral += pos.x * w
		total_weight += w
		active_count += 1
		if urgency > max_urgency:
			max_urgency = urgency
	if total_weight < 0.01:
		return {"height": 1.0, "lateral": 0.0, "urgency": 0.0, "confidence": 0}


	return {
		"height": (weighted_height / total_weight) - COURT_FLOOR_Y, 
		"lateral": weighted_lateral / total_weight, 
		"urgency": max_urgency, 
		"confidence": active_count
	}




func set_locked(locked: bool) -> void :
	_is_locked = locked

func reset() -> void :
	_is_locked = false
	_activation.fill(0.0)
	_time_to_arrival.fill(INF)
	_zone_scores.clear()
	_posture_scores.clear()
	if not _grid_root.visible: return
	for i in range(_meshes.size()):
		_materials[i].albedo_color = COLOR_INACTIVE
		_materials[i].emission = Color(COLOR_INACTIVE.r, COLOR_INACTIVE.g, COLOR_INACTIVE.b, 1.0)
		_materials[i].emission_energy_multiplier = EMISSION_IDLE



func update_grid(_delta: float) -> void :
	if not _grid_root.visible:
		return

	var has_active: bool = false
	for v_idx in range(_local_positions.size()):
		var act: float = _activation[v_idx]
		if act >= 0.02:
			has_active = true
			var time: float = _time_to_arrival[v_idx]
			var col: Color = _get_time_color(time)
			col.a *= act
			_materials[v_idx].albedo_color = col
			_materials[v_idx].emission = Color(col.r, col.g, col.b, 1.0)
			_materials[v_idx].emission_energy_multiplier = act * EMISSION_MAX
		else:
			_meshes[v_idx].visible = false
			continue
		_meshes[v_idx].visible = true


	if not has_active:
		_is_locked = false



func _get_time_color(time: float) -> Color:
	if time < TIME_RED:
		return COLOR_RED.lerp(COLOR_ORANGE, time / TIME_RED)
	elif time < TIME_ORANGE:
		return COLOR_ORANGE.lerp(COLOR_YELLOW, (time - TIME_RED) / (TIME_ORANGE - TIME_RED))
	elif time < TIME_YELLOW:
		return COLOR_YELLOW.lerp(COLOR_GREEN, (time - TIME_ORANGE) / (TIME_YELLOW - TIME_ORANGE))
	return COLOR_GREEN



func set_visible(v: bool) -> void :
	if _grid_root:
		_grid_root.visible = v



	if v:
		_is_locked = false
