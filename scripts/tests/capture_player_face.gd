extends SceneTree


const Face = preload("res://scripts/player_face_visual.gd")
var output: = "/tmp/player-face"

func _initialize() -> void : call_deferred("run")

func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("Face capture requires a rendered display")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i(720, 840)
	root.size = Vector2i(720, 840)
	var world: = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment: = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("263746")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce9fa")
	environment.environment.ambient_light_energy = 0.75
	world.add_child(environment)
	var light: = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -35, 0)
	light.light_energy = 1.35
	world.add_child(light)
	var material: = ShaderMaterial.new()
	material.shader = preload("res://shaders/athlete_kit.gdshader")
	var head: = MeshInstance3D.new()
	head.name = "HeadMesh"
	world.add_child(head)
	Face.apply(head, Color("dbb18b"), Vector3.FORWARD, material)
	var camera: = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.31
	world.add_child(camera)
	camera.make_current()
	for view in [{"name": "front", "position": Vector3(0, 0.006, - 0.6)}, 
		{"name": "three_quarter", "position": Vector3(0.42, 0.015, - 0.42)}, 
		{"name": "side", "position": Vector3(0.6, 0.006, 0)}]:
		camera.position = view.position
		camera.look_at(Vector3.ZERO, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = output.path_join("player_head_" + view.name + ".png")
		root.get_texture().get_image().save_png(path)
		print("FACE CAPTURE ", path)
	quit()
