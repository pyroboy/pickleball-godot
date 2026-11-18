extends SceneTree



const Hand = preload("res://scripts/articulated_hand.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const OUTPUT_DEFAULT: = "/workspace/shared/pickleball-hands/isolated-hand-models.png"
var _models: Array = []

class MockArm extends Node3D:
	var hand_mesh: MeshInstance3D
	func _init() -> void :
		hand_mesh = MeshInstance3D.new()
		hand_mesh.name = "HandMesh"
		hand_mesh.mesh = BoxMesh.new()
		add_child(hand_mesh)

func _initialize() -> void :
	call_deferred("run")

func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("The hand render fixture requires a display or Xvfb; headless produces no image")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1440, 1000))
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = Vector2i(1440, 1000)
	root.content_scale_factor = 1.0
	var world: = Node3D.new()
	root.add_child(world)
	var environment: = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("19222e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dee7f5")
	environment.ambient_light_energy = 0.72
	var world_environment: = WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var light: = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -28, -12)
	light.light_energy = 1.1
	light.shadow_enabled = false
	world.add_child(light)
	var fill: = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 155, 15)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	world.add_child(fill)
	var camera: = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.79
	camera.near = 0.01
	camera.far = 5.0
	camera.position = Vector3(0, 0.055, 1.5)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.055, 0))
	camera.current = true
	var overlay: = CanvasLayer.new()
	root.add_child(overlay)
	_label(overlay, "ARTICULATED HANDS", Vector2(58, 34), 32, Color("edf3fa"))
	_label(overlay, "702 triangles · 1 surface · 17 bones per hand · actual 40 mm grip / 75 mm ball", Vector2(58, 78), 20, Color("a7b8cb"))
	var modes: = ["GRIP", "OPEN", "CUP"]
	for column in range(3):
		_label(overlay, modes[column], Vector2(210 + 480 * column, 137), 25, Color("d5e5fa"))
	for row in range(2):
		var left: = row == 1
		var title: = "RIGHT HAND · DORSAL / THREE-QUARTER" if not left else "LEFT HAND · PALMAR / THREE-QUARTER"
		_label(overlay, title, Vector2(58, 193 + 365 * row), 17, Color("91a5bb"))
		for column in range(3):
			var arm: = MockArm.new()
			world.add_child(arm)
			var model: = Hand.new()
			model.initialize(arm, left)
			model.set_pose(modes[column])
			_models.append(model)

			var yaw: = - 0.42 if not left else PI + 0.42
			var basis: = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, - 0.3)
			var tx: = Transform3D(basis, Vector3((column - 1) * 0.38, 0.175 - row * 0.284, 0))
			model.set_mesh_world_transform(tx)
			if column == 0:
				_handle(world, tx)
			elif column == 2:
				_ball(world, tx * model.cup_ball_center)
	_label(overlay, "GRIP: pads sit 0.55 mm off the cylinder; index above the opposed thumb", Vector2(58, 914), 19, Color("b5c5d6"))
	_label(overlay, "CUP: the palm is tangent to the ball; this view does not alter gameplay or collision geometry", Vector2(58, 946), 19, Color("8fa3ba"))
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var output: = OUTPUT_DEFAULT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var screenshot: = root.get_texture().get_image()
	var error: = screenshot.save_png(output)
	print("ARTICULATED HAND RENDER: %s (%sx%s), error=%s" % [output, screenshot.get_width(), screenshot.get_height(), error])
	quit(0 if error == OK else 1)

func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color) -> void :
	var label: = Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _handle(parent: Node3D, tx: Transform3D) -> void :
	var grip: = MeshInstance3D.new()
	var cylinder: = CylinderMesh.new()
	cylinder.top_radius = PaddleDimensions.HANDLE_RADIUS
	cylinder.bottom_radius = PaddleDimensions.HANDLE_RADIUS
	cylinder.height = PaddleDimensions.HANDLE_LENGTH
	cylinder.radial_segments = 32
	grip.mesh = cylinder
	var material: = StandardMaterial3D.new()
	material.albedo_color = Color("444d5c")
	material.roughness = 0.95
	grip.material_override = material
	parent.add_child(grip)
	grip.global_transform = tx * Transform3D(Basis.IDENTITY, Vector3(0, PaddleDimensions.HANDLE_CENTER_Y - PaddleDimensions.MAIN_GRIP_Y, 0))
	var cap: = MeshInstance3D.new()
	var cap_mesh: = CylinderMesh.new()
	cap_mesh.top_radius = PaddleDimensions.HANDLE_RADIUS + 0.0015
	cap_mesh.bottom_radius = PaddleDimensions.HANDLE_RADIUS + 0.0015
	cap_mesh.height = 0.008
	cap_mesh.radial_segments = 24
	cap.mesh = cap_mesh
	cap.material_override = material
	grip.add_child(cap)
	cap.position.y = - PaddleDimensions.HANDLE_LENGTH * 0.5

func _ball(parent: Node3D, center: Vector3) -> void :
	var ball: = MeshInstance3D.new()
	var sphere: = SphereMesh.new()
	sphere.radius = 0.0375
	sphere.height = 0.075
	sphere.radial_segments = 24
	sphere.rings = 12
	ball.mesh = sphere
	var material: = StandardMaterial3D.new()
	material.albedo_color = Color("d4ee42")
	material.roughness = 0.75
	ball.material_override = material
	parent.add_child(ball)
	ball.global_position = center
