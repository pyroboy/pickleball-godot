extends SceneTree
const Cue = preload("res://scripts/fx/ball_readability.gd")
var checks: = 0
var errors: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: errors.append(message)
func run() -> void :
	root.get_node("PauseController").set_process_input(false)
	var world: = Node3D.new();root.add_child(world);current_scene = world
	var ball = preload("res://scripts/ball.gd").new();world.add_child(ball)
	ball.freeze = true;ball.position = Vector3(0.8, 1.1, 2.0)
	var before: Transform3D = ball.transform
	var collision_count: = 0
	for child in ball.get_children():
		if child is CollisionShape3D: collision_count += 1
	var cue: = Cue.new();ball.add_child(cue)
	check(cue.position == Vector3.ZERO, "cue is centered on actual ball")
	check(ball.transform == before, "cue does not move ball")
	check(is_equal_approx(ball.mass, 0.024), "ball mass unchanged")
	check( not ball.continuous_cd, "cue does not modify collision integration")
	var after_count: = 0
	for child in ball.get_children():
		if child is CollisionShape3D:
			after_count += 1
			check(is_equal_approx(child.shape.radius, 0.0375), "collision radius unchanged")
	check(after_count == collision_count, "cue does not add collision geometry")
	check(cue.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "halo does not create false ground shadow")
	check( not cue.is_processing() and not cue.is_physics_processing(), "GPU-only cue has no frame processing")
	var camera: = Camera3D.new();world.add_child(camera);camera.position = Vector3(0, 12, 16);camera.look_at(Vector3.ZERO);camera.current = true
	for size in [Vector2i(360, 800), Vector2i(432, 936), Vector2i(521, 828), Vector2i(720, 1560), Vector2i(1280, 800)]:
		root.size = size;root.content_scale_size = size
		await process_frame
		for height in [0.15, 1.1, 3.0]:
			ball.position.y = height
			var center: Vector2 = camera.unproject_position(ball.global_position)
			var edge: Vector2 = camera.unproject_position(ball.global_position + camera.global_basis.x * 0.075)
			var projected: float = center.distance_to(edge)
			var diameter: float = clampf(projected * 1.4, Cue.MINIMUM_PIXELS, Cue.MAXIMUM_PIXELS)
			check(diameter >= 8 and diameter <= 12, "conservative pixel footprint %s height%.2f" % [size, height])
			check(camera.unproject_position(cue.global_position).distance_to(center) < 0.001, "actual-height screen-center agreement")
	check(is_equal_approx(float(cue.material_override.get_shader_parameter("minimum_pixels")), 8.0), "shader uses tested minimum")
	check(is_equal_approx(float(cue.material_override.get_shader_parameter("fade_end_pixels")), 10.0), "large near-camera balls fade cue")
	ball.hide();check( not cue.is_visible_in_tree(), "hidden ball hides cue")
	ball.show();paused = true
	await process_frame
	check(cue.is_visible_in_tree(), "pause retains visible ball cue")
	paused = false;world.queue_free(); await process_frame; await process_frame
	for error in errors: push_error(error)
	print("BALL READABILITY: %d checks, %d failures" % [checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
