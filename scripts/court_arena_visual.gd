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
	_build_park(game)
	# Small wall slogans dropped: unreadable at the pixel look's half resolution.
	for side in ([] if true else [-1.0, 1.0]):
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
	# Drop faces the camera (always inside the arena, above the floor) never sees: bottoms,
	# faces pointing out of the arena, and the sides of floor-flat strips. Halves the triangles.
	var kept: = PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var n: Vector3 = normals[indices[t]]
		if n.y < -0.5: continue
		if size.y < 0.02 and n.y < 0.5: continue
		if absf(n.y) < 0.5 and Vector2(n.x, n.z).dot(Vector2(center.x, center.z)) > 0.0: continue
		kept.append_array([indices[t], indices[t + 1], indices[t + 2]])
	for index in kept:

		var brightness: = 0.82 + 0.18 * maxf(0.0, normals[index].dot(Vector3( - 0.3, 0.8, 0.5).normalized()))
		surface.set_color(color * Color(brightness, brightness, brightness, 1))
		surface.add_vertex(center + vertices[index])


# --- Park world (VISUAL_PASS_PLAN step 2/7): grass surround, dirt apron, pastel trees. ---
# Presentation only: unshaded, nearest-filtered, baked colour, no shadow casting, no collision.
const PARK_SEED := 20261119

func _build_park(game: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PARK_SEED
	var park := Node3D.new()
	park.name = "ParkWorld"
	add_child(park)
	# Dirt apron: recolour the court's existing apron mesh (same node, same size, so no z-fight).
	var apron := game.find_child("CourtApron", true, false)
	if apron is MeshInstance3D:
		var dirt := StandardMaterial3D.new()
		dirt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dirt.albedo_texture = _dirt_texture(rng)
		dirt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		dirt.uv1_scale = Vector3(4.0, 10.0, 1.0)
		dirt.uv1_triplanar = false
		apron.material_override = dirt
		apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The old stadium backdrop (a near-black 30 m cylinder, visual only, no collision)
	# walls the park in and reads as a black sky above the trees. Its top cap also
	# shades the whole court from the sun, and the current lighting was tuned under
	# that shade, so keep it as a shadow-only caster: unseen, same light.
	var backdrop := game.find_child("StadiumBackdrop", true, false)
	if backdrop is GeometryInstance3D:
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Grass surround under and beyond the apron.
	var grass := MeshInstance3D.new()
	grass.name = "ParkGrass"
	var plane := PlaneMesh.new()
	# Wide enough to reach the horizon from the high camera; past its edge the
	# procedural sky's near-black ground colour shows above the trees.
	plane.size = Vector2(600.0, 600.0)
	grass.mesh = plane
	grass.position = Vector3(0.0, 0.02, 0.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _grass_texture(rng)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.uv1_scale = Vector3(300.0, 300.0, 1.0)   # same 2 m tile as before
	gm.disable_fog = true
	grass.material_override = gm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	park.add_child(grass)
	# Trees: behind the far wall and out to the sides, away from the camera side.
	var trunks := SurfaceTool.new()
	trunks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spots: Array[Vector3] = [
		Vector3(-12.5, 0, -13.0), Vector3(-6.5, 0, -15.5), Vector3(1.0, 0, -14.0), Vector3(7.5, 0, -16.0),
		Vector3(13.0, 0, -12.5), Vector3(-15.5, 0, -5.0), Vector3(16.0, 0, -4.5), Vector3(-17.0, 0, 5.0),
		Vector3(15.5, 0, 6.0), Vector3(-10.0, 0, -20.0), Vector3(10.5, 0, -20.5)]
	var canopies: Array[Color] = [Color("9fd8a2"), Color("b6e0a0"), Color("8cc9a8"), Color("c9e4a4"), Color("f2c4cf")]
	var blobs := Node3D.new()
	blobs.name = "TreeBlobShadows"
	park.add_child(blobs)
	var blob_tex := _blob_texture()
	for spot in spots:
		var scale_f := rng.randf_range(0.85, 1.35)
		var canopy: Color = canopies[rng.randi() % canopies.size()]
		_tree(trunks, spot, scale_f, canopy)
		var blob := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 3.4 * scale_f
		quad.orientation = PlaneMesh.FACE_Y
		blob.mesh = quad
		blob.position = spot + Vector3(0.5 * scale_f, 0.035, 0.4 * scale_f)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_texture = blob_tex
		bm.albedo_color = Color(0.1, 0.25, 0.15, 0.45)
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		blob.material_override = bm
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blobs.add_child(blob)
	trunks.generate_normals()
	var tree_mesh := MeshInstance3D.new()
	tree_mesh.name = "ParkTrees"
	tree_mesh.mesh = trunks.commit()
	tree_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.vertex_color_is_srgb = true
	tm.disable_fog = true
	tree_mesh.material_override = tm
	park.add_child(tree_mesh)

func _tree(surface: SurfaceTool, at: Vector3, scale_f: float, canopy: Color) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * scale_f
	trunk.bottom_radius = 0.22 * scale_f
	trunk.height = 1.8 * scale_f
	trunk.radial_segments = 5
	trunk.rings = 1
	_add_mesh(surface, trunk, at + Vector3(0, 0.9 * scale_f, 0), Color("a98466"))
	var low := SphereMesh.new()
	low.radius = 1.35 * scale_f
	low.height = 2.4 * scale_f
	low.radial_segments = 7
	low.rings = 3
	_add_mesh(surface, low, at + Vector3(0, 2.5 * scale_f, 0), canopy)
	var top := SphereMesh.new()
	top.radius = 0.95 * scale_f
	top.height = 1.7 * scale_f
	top.radial_segments = 6
	top.rings = 3
	_add_mesh(surface, top, at + Vector3(0.15 * scale_f, 3.5 * scale_f, 0.1 * scale_f), canopy.lightened(0.12))

static func _add_mesh(surface: SurfaceTool, mesh: Mesh, center: Vector3, color: Color) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var b := 0.78 + 0.22 * clampf(normals[index].dot(Vector3(-0.3, 0.8, 0.5).normalized()) * 0.5 + 0.5, 0.0, 1.0)
		surface.set_color(color * Color(b, b, b, 1.0))
		surface.add_vertex(center + vertices[index])

static func _grass_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color("8fcf7e"))
	for i in 90:
		img.set_pixel(rng.randi() % 64, rng.randi() % 64, Color("7cbf6e") if i % 2 == 0 else Color("9fdc8a"))
	for i in 26:   # tufts: short dark vertical blades
		var x := rng.randi() % 63
		var y := 1 + rng.randi() % 62
		img.set_pixel(x, y, Color("5fa35a"))
		img.set_pixel(x, y - 1, Color("6eb465"))
		if i % 3 == 0: img.set_pixel(x + 1, y, Color("5fa35a"))
	var flowers: Array[Color] = [Color("fff1a8"), Color("ffffff"), Color("f7b6c8"), Color("c9b8f5")]
	for i in 9:
		img.set_pixel(rng.randi() % 64, rng.randi() % 64, flowers[i % flowers.size()])
	return ImageTexture.create_from_image(img)

static func _dirt_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color("c8a47e"))
	for i in 70:
		img.set_pixel(rng.randi() % 32, rng.randi() % 32, Color("b9946e") if i % 2 == 0 else Color("d5b48e"))
	return ImageTexture.create_from_image(img)

static func _blob_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 24
	tex.height = 24
	return tex
