extends Node3D


const Logo = preload("res://assets/branding/arjostyle-pickleball.png")

func setup(game: Node3D) -> void :
	name = "CourtArenaVisual"
	game.add_child(self)
	var panels: = SurfaceTool.new()
	panels.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accents: = SurfaceTool.new()
	accents.begin(Mesh.PRIMITIVE_TRIANGLES)

	_box(panels, Vector3(0, 1.05, -9.55), Vector3(12.6, 1.96, 0.2), Color("172b46"))
	_box(panels, Vector3(0, 2.06, -9.55), Vector3(12.8, 0.1, 0.3), Color("345675"))
	for side in [-1.0, 1.0]:
		_box(panels, Vector3(side * 5.6, 0.78, -3.8), Vector3(0.18, 1.42, 11.5), Color("1d3552"))
		_box(panels, Vector3(side * 5.6, 1.53, -3.8), Vector3(0.28, 0.08, 11.65), Color("416487"))
		_box(panels, Vector3(side * 6.12, 1.26, -8.48), Vector3(1.0, 2.32, 1.85), Color("203a57"))
		_box(panels, Vector3(side * 7.2, 1.42, -10.9), Vector3(1.2, 2.68, 2.4), Color("20344c"))
		_box(accents, Vector3(side * 5.492, 1.4, -4.0), Vector3(0.009, 0.035, 10.65), Color("478bc1"))
		for z in [-8.3, -3.5, 1.25]:
			_box(accents, Vector3(side * 5.6, 1.588, z), Vector3(0.24, 0.025, 0.32), Color("f4d2a0"))
		_box(accents, Vector3(side * 4.8, 0.083, 8.35), Vector3(0.65, 0.005, 0.045), Color("438dcc"))
	for x in [-4.1, 0.0, 4.1]:
		_box(accents, Vector3(x, 2.123, -9.5), Vector3(0.38, 0.026, 0.2), Color("f6d7a0"))
	_combined("ArenaBoards", panels)
	_combined("ArenaAccents", accents)
	var mark: = MeshInstance3D.new()
	mark.name = "ArenaWordmark"
	var plane: = QuadMesh.new()
	plane.size = Vector2(4.4, 1.15)
	mark.mesh = plane
	mark.position = Vector3(0, 1.06, -9.439)
	var material: = ShaderMaterial.new()
	material.shader = preload("res://shaders/court_brand.gdshader")
	material.set_shader_parameter("logo_texture", Logo)
	material.set_shader_parameter("ink", Color(0.6, 0.76, 0.92, 0.8))
	mark.material_override = material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	for side in [-1.0, 1.0]:
		var sign: = Label3D.new()
		sign.name = "ArenaMessage" + str(int(side))
		sign.text = "PLAY\nPRACTICE\nIMPROVE" if side < 0 else "SMALL COURT\nBIG HABITS"
		sign.font_size = 42
		sign.pixel_size = 0.005
		sign.outline_size = 0
		sign.modulate = Color("9cbddc")
		sign.position = Vector3(side * 4.62, 1.08, -9.435)
		sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sign)

func _combined(label: String, surface: SurfaceTool) -> void :
	surface.generate_normals()
	surface.index()
	var mesh: = MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = surface.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.disable_receive_shadows = true
	material.disable_fog = true
	mesh.material_override = material
	add_child(mesh)

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void :
	var box: = BoxMesh.new()
	box.size = size
	var arrays: = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:

		var brightness: = 0.82 + 0.18 * maxf(0.0, normals[index].dot(Vector3( - 0.3, 0.8, 0.5).normalized()))
		surface.set_color(color * Color(brightness, brightness, brightness, 1))
		surface.add_vertex(center + vertices[index])
