extends RefCounted


const ArmVisual = preload("res://scripts/player_arm_visual.gd")
const TorsoSkin = preload("res://scripts/articulated_torso_mesh.gd")
const SKIN: = Color("dbb18b")
const SOCK: = Color("e7edf4")
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/athlete_kit.gdshader")
	return _material

static func apply(player) -> void :
	var jersey: = Color("168be4") if player.player_num == 0 else Color("d84d60")
	var shorts: = Color("1650ae") if player.player_num == 0 else Color("942e46")
	var trim: = Color("62c6ff") if player.player_num == 0 else Color("ff9a99")
	var torso: MeshInstance3D = player.body_pivot.get_node("TorsoMesh")



	var shirt: = _rings([
		Vector3(0.132, - 0.17, 0.083), Vector3(0.136, - 0.135, 0.086), 
		Vector3(0.167, 0.02, 0.098), Vector3(0.18, 0.082, 0.1), 
		Vector3(0.112, 0.115, 0.077), Vector3(0.066, 0.125, 0.061)], 
		[shorts, jersey, jersey, jersey, jersey, trim], 8, true)
	var neck: = _rings([
		Vector3(0.047, 0.119, 0.043), Vector3(0.044, 0.174, 0.041), Vector3(0.051, 0.21, 0.047)], 
		[SKIN, SKIN, SKIN], 10)
	var joined: = SurfaceTool.new()
	joined.begin(Mesh.PRIMITIVE_TRIANGLES)
	joined.append_from(shirt, 0, Transform3D.IDENTITY)
	joined.append_from(neck, 0, Transform3D.IDENTITY)
	joined.index()
	_replace(torso, joined.commit())
	var hips: MeshInstance3D = player.body_pivot.get_node("HipsMesh")
	_replace(hips, _rings([Vector3(0.139, - 0.07, 0.083), Vector3(0.15, 0.045, 0.09), Vector3(0.142, 0.07, 0.087)], 
		[shorts, shorts, shorts.lightened(0.1)], 8, true))


	torso.layers = 0
	hips.layers = 0
	var body_skin: = TorsoSkin.new()
	body_skin.initialize(player, material(), jersey, shorts, trim)
	var head: MeshInstance3D = torso.get_node("HeadMesh")

	preload("res://scripts/player_face_visual.gd").apply(head, SKIN, player._get_forward_axis(), material())
	ArmVisual.apply(player, jersey, SKIN, material())
	preload("res://scripts/player_leg_visual.gd").apply(player, shorts, SKIN, SOCK, material())
	for leg in [player.right_leg_node, player.left_leg_node]:

		preload("res://scripts/player_shoe_visual.gd").apply(leg.foot_mesh, jersey, shorts, material())

static func _replace(node: MeshInstance3D, mesh: ArrayMesh) -> void :
	node.mesh = mesh
	node.material_override = material()

static func _rings(profile: Array, colors: Array, sides: int, squared: bool = false) -> ArrayMesh:
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var square: = [Vector2( - 0.75, -1), Vector2(0.75, -1), Vector2(1, - 0.65), Vector2(1, 0.65), Vector2(0.75, 1), Vector2( - 0.75, 1), Vector2(-1, 0.65), Vector2(-1, - 0.65)]
	for section in profile:
		var points: = PackedVector3Array()
		for i in range(sides):
			var circle: Vector2 = square[i] if squared else Vector2(cos(TAU * i / sides), sin(TAU * i / sides))
			points.append(Vector3(circle.x * section.x, section.y, circle.y * section.z))
		rings.append(points)
	for row in range(rings.size() - 1):
		for i in range(sides):
			var next: = (i + 1) % sides
			_triangle(surface, rings[row][i], rings[row + 1][i], rings[row + 1][next], colors[row], colors[row + 1], colors[row + 1])
			_triangle(surface, rings[row][i], rings[row + 1][next], rings[row][next], colors[row], colors[row + 1], colors[row])
	for i in range(sides):
		var next: = (i + 1) % sides
		_triangle(surface, Vector3(0, profile[0].y, 0), rings[0][i], rings[0][next], colors[0], colors[0], colors[0])
		_triangle(surface, Vector3(0, profile[-1].y, 0), rings[-1][next], rings[-1][i], colors[-1], colors[-1], colors[-1])
	surface.generate_normals()
	surface.index()
	return surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void :


	surface.set_smooth_group(-1)
	surface.set_color(ca);surface.add_vertex(a)
	surface.set_color(cc);surface.add_vertex(c)
	surface.set_color(cb);surface.add_vertex(b)
