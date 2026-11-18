extends RefCounted


const ArmSurface = preload("res://scripts/player_arm_visual.gd")
const SIDES: = 10
const BRIDGE_META: = &"leg_knee_bridge"
const JOIN_FROM_KNEE: = 0.11
static var _cache: Dictionary = {}
static var mesh_build_count: = 0

static func apply(player, shorts: Color, skin: Color, sock: Color, material: Material) -> void :
	for leg in [player.right_leg_node, player.left_leg_node]:
		for part in [0, 1]:
			var key: = "%d/%.5f/%.5f/%s/%s/%s" % [part, leg.thigh_length, leg.shin_length, shorts.to_html(), skin.to_html(), sock.to_html()]
			if not _cache.has(key):
				_cache[key] = _build(leg.thigh_length, leg.shin_length, part == 0, shorts, skin, sock)
				mesh_build_count += 1
			var node: MeshInstance3D = leg.thigh_mesh if part == 0 else leg.shin_mesh
			node.mesh = _cache[key];node.material_override = material
		if not leg.has_meta(BRIDGE_META):


			var bridge: = ArmSurface.ElbowBridge.new()
			bridge.upper = leg.thigh_mesh;bridge.fore = leg.shin_mesh
			bridge.elbow_local = Vector3(0, leg.thigh_length * 0.5, 0)
			bridge.fore_half = leg.shin_length * 0.5
			bridge.skeleton = Skeleton3D.new();bridge.skeleton.name = "KneeSurfaceSkeleton"
			bridge.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			bridge.upper.add_child(bridge.skeleton)
			var skin_resource: = Skin.new()
			for index in range(3):
				bridge.skeleton.add_bone(["Thigh", "KneeBisector", "Shin"][index])
				var rest: = Transform3D.IDENTITY if index == 0 else Transform3D(Basis.IDENTITY, bridge.elbow_local)
				bridge.skeleton.set_bone_rest(index, rest);bridge.skeleton.set_bone_pose(index, rest)
				skin_resource.add_bind(index, rest.affine_inverse())
			bridge.upper.skin = skin_resource;bridge.upper.skeleton = NodePath("KneeSurfaceSkeleton")
			bridge.upper.custom_aabb = AABB(Vector3( - 0.55, - 0.3, - 0.55), Vector3(1.1, 1.1, 1.1))
			bridge.upper.set_meta(BRIDGE_META, bridge);leg.set_meta(BRIDGE_META, bridge)
		update_leg(leg)

static func update_leg(leg) -> void :
	if leg.has_meta(BRIDGE_META): leg.get_meta(BRIDGE_META).update()

static func _profile(thigh_length: float, shin_length: float) -> Dictionary:
	var half: = thigh_length * 0.5
	var sh: = shin_length * 0.5


	var thigh_at_125: Vector2 = Vector2(0.052, 0.055).lerp(Vector2(0.071, 0.068), 0.125 / (half - half * 0.12))
	var thigh_at_60: Vector2 = Vector2(0.052, 0.055).lerp(Vector2(0.071, 0.068), 0.06 / (half - half * 0.12))
	var shin_at_55: Vector2 = Vector2(0.049, 0.051).lerp(Vector2(0.052, 0.054), 0.055 / (sh * 0.5))
	var shin_at_join: Vector2 = Vector2(0.052, 0.054).lerp(Vector2(0.043, 0.044), (JOIN_FROM_KNEE - sh * 0.5) / (sh * 0.7))
	var rings: Array[Vector3] = [Vector3(0.083, - half, 0.077), Vector3(0.096, - half * 0.72, 0.091), 
		Vector3(0.094, half * 0.1, 0.088), Vector3(0.071, half * 0.12, 0.068), 
		Vector3(thigh_at_125.x, half - 0.125, thigh_at_125.y), Vector3(thigh_at_60.x, half - 0.06, thigh_at_60.y), 
		Vector3(0.052, half, 0.048), Vector3(shin_at_55.x, half + 0.055, shin_at_55.y), 
		Vector3(shin_at_join.x, half + JOIN_FROM_KNEE, shin_at_join.y), 
		Vector3(0.043, half + sh + sh * 0.2, 0.044), Vector3(0.044, half + sh + sh * 0.22, 0.045), Vector3(0.037, half + shin_length, 0.039)]
	var offsets: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.002, 0.005, 0.001, 0.0, 0.0, 0.0, 0.0]
	var weights: Array[Vector3] = [Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, 
		Vector3(0.5, 0.5, 0), Vector3.UP, Vector3(0, 0.5, 0.5), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]
	return {"rings": rings, "offsets": offsets, "weights": weights, "join": 8, "shin_origin": half + sh}

static func _point(profile: Dictionary, row: int, side: int, local_offset: float) -> Vector3:
	var ring: Vector3 = profile.rings[row]; var a: = TAU * side / SIDES
	return Vector3(cos(a) * ring.x, ring.y - local_offset, sin(a) * ring.z + profile.offsets[row])

static func _normal(profile: Dictionary, row: int, side: int) -> Vector3:
	var count: int = profile.rings.size()
	var previous: int = maxi(row - 1, 0); var following: int = mini(row + 1, count - 1)
	var prev: Vector3 = _point(profile, previous, side, 0)
	var next: Vector3 = _point(profile, following, side, 0)
	var ring: Vector3 = profile.rings[row]; var a: = TAU * side / SIDES
	var around: = Vector3( - sin(a) * ring.x, 0, cos(a) * ring.z)
	return (next - prev).cross(around).normalized()

static func _build(thigh_length: float, shin_length: float, upper: bool, shorts: Color, skin: Color, sock: Color) -> ArrayMesh:
	var profile: = _profile(thigh_length, shin_length)
	var first: int = 0 if upper else profile.join
	var last: int = profile.join if upper else profile.rings.size() - 1
	var offset: float = 0.0 if upper else profile.shin_origin
	var surface: = SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(first, last):
		for side in range(SIDES):
			var next: = (side + 1) % SIDES
			for pair in [[row, side], [row + 1, next], [row + 1, side], [row, side], [row, next], [row + 1, next]]:
				var i: int = pair[0]; var s: int = pair[1]
				var color: Color = shorts if i < 3 else (sock if i >= 10 else skin)
				_vertex(surface, profile, i, s, offset, upper, color)
	var end: int = first if upper else last
	for side in range(SIDES):
		var next: = (side + 1) % SIDES
		for point in [Vector3(0, profile.rings[end].y - offset, profile.offsets[end]), _point(profile, end, next if upper else side, offset), _point(profile, end, side if upper else next, offset)]:
			surface.set_normal(Vector3.DOWN if upper else Vector3.UP);surface.set_color(shorts if upper else sock)
			if upper: surface.set_bones(PackedInt32Array([0, 1, 2, 0]));surface.set_weights(PackedFloat32Array([1, 0, 0, 0]))
			surface.add_vertex(point)
	surface.index();return surface.commit()

static func _vertex(surface: SurfaceTool, profile: Dictionary, row: int, side: int, offset: float, upper: bool, color: Color) -> void :
	surface.set_normal(_normal(profile, row, side));surface.set_color(color)
	if upper:
		var w: Vector3 = profile.weights[row]
		surface.set_bones(PackedInt32Array([0, 1, 2, 0]));surface.set_weights(PackedFloat32Array([w.x, w.y, w.z, 0]))
	surface.add_vertex(_point(profile, row, side, offset))
