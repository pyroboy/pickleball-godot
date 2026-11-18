extends RefCounted



static var _cache: Dictionary = {}
static var mesh_build_count: = 0
const SIDES: = 12

static func apply(player, jersey: Color, skin: Color, material: Material) -> void :
	for arm in [player.right_arm_node, player.left_arm_node]:
		for part in [0, 1]:
			var length: float = arm.upper_arm_length if part == 0 else arm.forearm_length
			var key: = "%d/%.5f/%s/%s" % [part, length, jersey.to_html() if part == 0 else "skin", skin.to_html()]
			if not _cache.has(key):
				_cache[key] = _build(length, part == 0, jersey, skin)
				mesh_build_count += 1
			var node: MeshInstance3D = arm.upper_mesh if part == 0 else arm.fore_mesh
			node.mesh = _cache[key]
			node.material_override = material
			node.set_meta("rounded_arm_surface", true)

static func _build(length: float, upper: bool, jersey: Color, skin: Color) -> ArrayMesh:
	var half: = length * 0.5

	var rings: Array[Vector3]
	var colors: Array[Color]
	if upper:
		rings = [Vector3(0.006, - half - 0.028, 0.006), Vector3(0.04, - half - 0.01, 0.038), 
			Vector3(0.058, - half + 0.024, 0.056), Vector3(0.056, - half + 0.075, 0.054), 
			Vector3(0.049, - 0.012, 0.047), Vector3(0.04, 0.001, 0.04), 
			Vector3(0.038, half - 0.042, 0.038), Vector3(0.029, half + 0.01, 0.029), 
			Vector3(0.006, half + 0.03, 0.006)]
		colors = [jersey, jersey, jersey, jersey, jersey, skin, skin, skin, skin]
	else:
		rings = [Vector3(0.005, - half - 0.03, 0.005), Vector3(0.028, - half - 0.012, 0.028), 
			Vector3(0.035, - half + 0.025, 0.036), Vector3(0.037, - half + 0.075, 0.037), 
			Vector3(0.031, 0.018, 0.032), Vector3(0.023, half - 0.035, 0.024), 


			Vector3(0.013, half - 0.005, 0.014), Vector3(0.004, half + 0.006, 0.004)]
		colors = [skin, skin, skin, skin, skin, skin, skin, skin]
	var surface: = SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size() - 1):
		for side in range(SIDES):
			var next: = (side + 1) % SIDES
			var a: = _point(rings[row], side); var b: = _point(rings[row + 1], side)
			var c: = _point(rings[row + 1], next); var d: = _point(rings[row], next)
			_triangle(surface, a, c, b, colors[row], colors[row + 1], colors[row + 1])
			_triangle(surface, a, d, c, colors[row], colors[row], colors[row + 1])
	for side in range(SIDES):
		var next: = (side + 1) % SIDES
		_triangle(surface, Vector3(0, rings[0].y, 0), _point(rings[0], next), _point(rings[0], side), colors[0], colors[0], colors[0])
		_triangle(surface, Vector3(0, rings[-1].y, 0), _point(rings[-1], side), _point(rings[-1], next), colors[-1], colors[-1], colors[-1])
	surface.generate_normals();surface.index()
	return surface.commit()

static func _point(ring: Vector3, side: int) -> Vector3:
	var angle: = TAU * side / SIDES
	return Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.z)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void :
	surface.set_smooth_group(0)
	surface.set_color(ca);surface.add_vertex(a)
	surface.set_color(cb);surface.add_vertex(b)
	surface.set_color(cc);surface.add_vertex(c)
