extends RefCounted



const D = preload("res://scripts/player_body_dimensions.gd")
const Profile = preload("res://scripts/body_surface_profile.gd")
const SIDES: = Profile.SIDES
static var _mesh_cache: Dictionary = {}
const SKIN: = Color("dbb18b")
static var mesh_build_count: = 0
var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var bone_pose_write_count: = 0
var _last_pelvis: = Transform3D.IDENTITY
var _last_abdomen: = Transform3D.IDENTITY
var _last_chest: = Transform3D.IDENTITY
var _initialized: = false

func initialize(player, material: Material, jersey: Color, shorts: Color, trim: Color) -> void :
	skeleton = Skeleton3D.new()
	skeleton.name = "VisualBodySkeleton"
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	player.body_pivot.add_child(skeleton)
	var rest: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, D.PELVIS_CENTER_Y, 0)), 
		Transform3D(Basis.IDENTITY, Vector3(0, D.PELVIS_CENTER_Y + D.PELVIS_HALF_HEIGHT, 0)), 
		Transform3D(Basis.IDENTITY, Vector3(0, D.CHEST_CENTER_Y, 0))]
	var skin: = Skin.new()
	for index in range(3):
		skeleton.add_bone(["Pelvis", "Abdomen", "Ribcage"][index])
		skeleton.set_bone_parent(index, index - 1)
		var local: Transform3D = rest[index] if index == 0 else rest[index - 1].affine_inverse() * rest[index]
		skeleton.set_bone_rest(index, local)
		skeleton.set_bone_pose(index, local)
		skin.add_bind(index, rest[index].affine_inverse())
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	skeleton.add_child(body_mesh)
	body_mesh.mesh = _build(jersey, shorts, trim, player._get_forward_axis().z > 0.0)
	body_mesh.skin = skin
	body_mesh.skeleton = NodePath("..")
	body_mesh.material_override = material
	body_mesh.custom_aabb = AABB(Vector3( - 0.4, - 0.62, - 0.42), Vector3(0.8, 1.1, 0.84))
	player.body_pivot.set_meta("articulated_torso", self)
	update_frames(rest[0], rest[1], rest[2])

func update_frames(pelvis: Transform3D, abdomen: Transform3D, chest: Transform3D) -> void :
	if _initialized and pelvis.is_equal_approx(_last_pelvis) and abdomen.is_equal_approx(_last_abdomen) and chest.is_equal_approx(_last_chest): return
	skeleton.set_bone_pose(0, pelvis)
	skeleton.set_bone_pose(1, pelvis.affine_inverse() * abdomen)
	skeleton.set_bone_pose(2, abdomen.affine_inverse() * chest)
	_last_pelvis = pelvis;_last_abdomen = abdomen;_last_chest = chest
	_initialized = true
	bone_pose_write_count += 3

static func _build(jersey: Color, shorts: Color, trim: Color, back_facing: bool = false) -> ArrayMesh:
	var cache_key: String = "%s/%s/%s/%s" % [jersey.to_html(), shorts.to_html(), trim.to_html(), back_facing]
	if _mesh_cache.has(cache_key): return _mesh_cache[cache_key]



	var profile: Array[Vector3] = Profile.rings()
	var weights: Array[Vector3] = Profile.weights()
	var colors: Array[Color] = [shorts, shorts, shorts, shorts.lightened(0.08), trim.darkened(0.25), 
		jersey.darkened(0.08), jersey.darkened(0.06), jersey, jersey, jersey, jersey, jersey, jersey, trim, SKIN, SKIN, SKIN]
	var rings: Array[PackedVector3Array] = Profile.surface_rings(back_facing)
	var surface: = SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size() - 1):
		for side in range(SIDES):
			var next: int = (side + 1) % SIDES
			_triangle(surface, rings[row][side], rings[row + 1][next], rings[row + 1][side], colors[row], colors[row + 1], colors[row + 1], weights[row], weights[row + 1], weights[row + 1])
			_triangle(surface, rings[row][side], rings[row][next], rings[row + 1][next], colors[row], colors[row], colors[row + 1], weights[row], weights[row], weights[row + 1])
	for side in range(SIDES):
		var next: int = (side + 1) % SIDES
		_triangle(surface, Vector3(0, profile[0].y, 0), rings[0][next], rings[0][side], colors[0], colors[0], colors[0], weights[0], weights[0], weights[0])
		_triangle(surface, Vector3(0, profile[-1].y, 0), rings[-1][side], rings[-1][next], colors[-1], colors[-1], colors[-1], weights[-1], weights[-1], weights[-1])
	surface.generate_normals();surface.index()
	mesh_build_count += 1
	var mesh: ArrayMesh = surface.commit()
	_mesh_cache[cache_key] = mesh
	return mesh

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, wa: Vector3, wb: Vector3, wc: Vector3) -> void :
	surface.set_smooth_group(0)
	_vertex(surface, a, ca, wa);_vertex(surface, b, cb, wb);_vertex(surface, c, cc, wc)

static func _vertex(surface: SurfaceTool, point: Vector3, color: Color, weights: Vector3) -> void :
	surface.set_bones(PackedInt32Array([0, 1, 2, 0]))
	surface.set_weights(PackedFloat32Array([weights.x, weights.y, weights.z, 0]))
	surface.set_color(color);surface.add_vertex(point)
