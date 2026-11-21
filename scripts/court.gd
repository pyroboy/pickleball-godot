extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")



const COURT_LENGTH: = 13.4
const COURT_WIDTH: = 6.1
const NET_HEIGHT: = 0.91
const LINE_WIDTH: = 0.05
const NON_VOLLEY_ZONE: = PickleballConstants.NON_VOLLEY_ZONE


const SHOW_DEBUG_ZONES: = true

func create_court(parent: Node3D) -> StaticBody3D:
	var court: StaticBody3D = StaticBody3D.new()
	court.name = "Court"
	parent.add_child(court)




	var apron_mesh: BoxMesh = BoxMesh.new()



	apron_mesh.size = Vector3(16.0, 0.15, 40.0)
	var apron_inst: MeshInstance3D = MeshInstance3D.new()
	apron_inst.mesh = apron_mesh
	apron_inst.name = "CourtApron"
	apron_inst.position = Vector3(0, -0.006, 0)
	var apron_mat: StandardMaterial3D = StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.12, 0.16, 0.22)
	apron_mat.roughness = 0.9
	apron_mat.metallic = 0.0
	apron_inst.material_override = apron_mat
	court.add_child(apron_inst)



	var surface_mesh: BoxMesh = BoxMesh.new()
	surface_mesh.size = Vector3(COURT_WIDTH + 0.6, 0.006, COURT_LENGTH + 0.6)
	var surface_inst: MeshInstance3D = MeshInstance3D.new()
	surface_inst.mesh = surface_mesh
	surface_inst.name = "CourtSurface"
	surface_inst.position = Vector3(0, 0.072, 0)
	var surface_mat: StandardMaterial3D = StandardMaterial3D.new()
	surface_mat.albedo_color = Color(0.16, 0.32, 0.52)
	surface_mat.roughness = 0.75
	surface_mat.metallic = 0.0
	surface_inst.material_override = surface_mat
	court.add_child(surface_inst)


	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(COURT_WIDTH, 0.15, COURT_LENGTH)
	col.shape = shape
	court.add_child(col)


	court.physics_material_override = PhysicsMaterial.new()
	court.physics_material_override.bounce = 0.64
	court.physics_material_override.friction = 0.4

	_create_stadium_backdrop(parent)
	return court

func _create_stadium_backdrop(parent: Node3D) -> void :

	var backdrop: MeshInstance3D = MeshInstance3D.new()
	backdrop.name = "StadiumBackdrop"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 30.0
	cyl.bottom_radius = 30.0
	cyl.height = 14.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_bottom = false   # under the floor, never seen
	backdrop.mesh = cyl
	backdrop.position = Vector3(0, 5.5, 0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.07, 0.09, 0.14)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.disable_receive_shadows = true
	backdrop.material_override = mat
	parent.add_child(backdrop)

func create_lines(parent: Node3D) -> void :
	var half_length: float = COURT_LENGTH / 2.0
	var half_width: float = COURT_WIDTH / 2.0
	var nz: float = NON_VOLLEY_ZONE

	var line_y: float = 0.077
	# All 8 lines in one unshaded mesh (one draw; was 8 lit quads). Still named
	# CourtLines: wall practice hides it by name.
	var segments: Array = [
		[Vector3(-half_width, line_y, -half_length), Vector3(half_width, line_y, -half_length)],
		[Vector3(-half_width, line_y, half_length), Vector3(half_width, line_y, half_length)],
		[Vector3(-half_width, line_y, -half_length), Vector3(-half_width, line_y, half_length)],
		[Vector3(half_width, line_y, -half_length), Vector3(half_width, line_y, half_length)],
		[Vector3(-half_width, line_y, -nz), Vector3(half_width, line_y, -nz)],
		[Vector3(-half_width, line_y, nz), Vector3(half_width, line_y, nz)],
		[Vector3(0, line_y, -nz), Vector3(0, line_y, -half_length)],
		[Vector3(0, line_y, nz), Vector3(0, line_y, half_length)]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in segments:
		var a: Vector3 = seg[0]; var b: Vector3 = seg[1]
		var along: Vector3 = (b - a).normalized()
		var side: Vector3 = along.cross(Vector3.UP).normalized() * LINE_WIDTH * 0.5
		var lo: Vector3 = a - along * LINE_WIDTH * 0.5; var hi: Vector3 = b + along * LINE_WIDTH * 0.5
		for v in [lo - side, hi - side, hi + side, lo - side, hi + side, lo + side]:
			st.set_normal(Vector3.UP); st.add_vertex(v)
	var lines := MeshInstance3D.new()
	lines.name = "CourtLines"
	lines.mesh = st.commit()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.94, 0.95, 0.97)
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lines.material_override = line_mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lines)

	if RuntimePolicy.developer_tools: print("[COURT] SHOW_DEBUG_ZONES=", SHOW_DEBUG_ZONES)
	if SHOW_DEBUG_ZONES and RuntimePolicy.developer_tools:
		_create_debug_zones(parent)
		if RuntimePolicy.developer_tools: print("[COURT] Debug zones created!")

func _create_debug_zones(parent: Node3D) -> void :
	var half_length: float = COURT_LENGTH / 2.0
	var half_width: float = COURT_WIDTH / 2.0
	var nz: float = NON_VOLLEY_ZONE

	var debug_root: Node3D = Node3D.new()
	debug_root.name = "DebugZones"
	debug_root.visible = false
	parent.add_child(debug_root)
	if RuntimePolicy.developer_tools: print("[DEBUG_ZONES] half_length=", half_length, " half_width=", half_width, " nz=", nz)



	var service_depth: float = half_length - nz

	var service_box_center_z: float = nz + service_depth / 2

	if RuntimePolicy.developer_tools: print("[DEBUG_ZONES] service_depth=", service_depth, " service_box_center_z=", service_box_center_z)






	_create_zone(debug_root, Vector3(half_width / 2, 0.01, - service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(1, 0, 1, 0.6), "Red Right")


	_create_zone(debug_root, Vector3( - half_width / 2, 0.01, - service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0.5, 0, 0.8, 0.6), "Red Left")


	_create_zone(debug_root, Vector3(0, 0.01, - nz / 2), 
		Vector3(half_width * 2, 0.02, nz), 
		Color(1, 0, 0, 0.4), "Red Kitchen (NVZ)")






	_create_zone(debug_root, Vector3(half_width / 2, 0.01, service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0, 1, 1, 0.6), "Blue Right")


	_create_zone(debug_root, Vector3( - half_width / 2, 0.01, service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0, 1, 0, 0.6), "Blue Left")


	_create_zone(debug_root, Vector3(0, 0.01, nz / 2), 
		Vector3(half_width * 2, 0.02, nz), 
		Color(1, 0, 0, 0.4), "Blue Kitchen (NVZ)")























func _create_zone(parent: Node3D, center: Vector3, size: Vector3, color: Color, _label: String) -> void :
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()

	mesh.size = Vector3(size.x, 0.01, size.z)
	mesh_inst.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mesh_inst.material_override = mat


	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(center.x, 0.078, center.z)

func _create_line(parent: Node3D, start: Vector3, end: Vector3, material: StandardMaterial3D) -> void :
	var length: float = start.distance_to(end)
	var center: Vector3 = (start + end) / 2.0

	var line_mesh: QuadMesh = QuadMesh.new()

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = line_mesh
	mesh_inst.material_override = material
	mesh_inst.rotation_degrees = Vector3(-90, 0, 0)

	var dx: float = abs(start.x - end.x)
	var dz: float = abs(start.z - end.z)
	if dx > dz:
		line_mesh.size = Vector2(length, LINE_WIDTH)
	else:
		line_mesh.size = Vector2(LINE_WIDTH, length)

	parent.add_child(mesh_inst)
	mesh_inst.global_position = center

func get_court_bounds() -> Dictionary:
	var half_len: float = COURT_LENGTH / 2.0
	var half_wid: float = COURT_WIDTH / 2.0
	return {
		"left": - half_wid, 
		"right": half_wid, 
		"top": - half_len, 
		"bottom": half_len, 
		"net_z": 0.0
	}
