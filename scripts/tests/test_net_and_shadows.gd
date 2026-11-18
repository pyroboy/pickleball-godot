extends SceneTree

const Profile = preload("res://scripts/net_profile.gd")
const Factory = preload("res://scripts/net.gd")
const Shadows = preload("res://scripts/fx/ground_shadows.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var failures: Array[String] = []
var checks: = 0
var world: Node3D
var net
var ball
var shadows
var left: Node3D
var right: Node3D
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	root.get_node("PauseController").set_process_input(false)
	world = Node3D.new();root.add_child(world);current_scene = world
	var helper: = Factory.new()
	net = helper.create_net(world);helper.free()
	ball = preload("res://scripts/ball.gd").new();world.add_child(ball)
	ball.set_physics_process(false);ball.gravity_scale = 0.0;ball.linear_damp = 0.0
	ball.freeze = true;ball.is_in_play = true
	net.bind_ball(ball)
	left = Node3D.new();right = Node3D.new();world.add_child(left);world.add_child(right)
	left.position = Vector3(-1.0, 1.0, 2.0);right.position = Vector3(1.0, 1.0, -2.0)
	shadows = Shadows.new();world.add_child(shadows);shadows.setup(ball, left, right)
	await physics_frame; await physics_frame
	check(is_equal_approx(Profile.height_at(0), 0.8636), "center height is 34 inches above playing surface")
	check(is_equal_approx(Profile.height_at(3.05), 0.9144), "sideline height is 36 inches above playing surface")
	check(is_equal_approx(Profile.top_y_at(0), 0.9386), "world floor offset included")
	check( not ball.continuous_cd, "net sweep preserves existing ball/floor CCD mode")
	check(net.get_node("WovenFabric").mesh.get_surface_count() == 1, "one bounded fabric surface")
	check(net.get_node("TopTape").material_override.get_shader_parameter("tape"), "top tape explicit")
	var space = world.get_world_3d().direct_space_state
	for i in range(101):
		var x: float = lerpf(-3.3, 3.3, float(i) / 100.0)
		var top: float = Profile.top_y_at(x)
		var low = PhysicsRayQueryParameters3D.create(Vector3(x, top - 0.003, 0.3), Vector3(x, top - 0.003, -0.3), 4)
		var high = PhysicsRayQueryParameters3D.create(Vector3(x, top + 0.003, 0.3), Vector3(x, top + 0.003, -0.3), 4)
		check( not space.intersect_ray(low).is_empty(), "no gap below sag profile x=%.3f" % x)
		check(space.intersect_ray(high).is_empty(), "no invisible wall above sag x=%.3f" % x)
		check(absf(Flight.net_clear_y_at(x) - Profile.clear_y_at(x)) < 1e-05, "predictor shares collision profile")
	for x in [0.0, 1.2573, -2.0955, 3.05]:
		for direction in [-1.0, 1.0]:
			await launch(x, 0.55, direction, true)
			await launch(x, Profile.clear_y_at(x) - 0.012, direction, true)
			await launch(x, Profile.clear_y_at(x) + 0.02, direction, false)

	var original_ticks: int = Engine.physics_ticks_per_second
	for ticks in [30, 120]:
		Engine.physics_ticks_per_second = ticks
		for direction in [-1.0, 1.0]:
			await launch(0.0, 0.55, direction, true)
			await launch(1.2573, Profile.clear_y_at(1.2573) - 0.012, direction, true)
			await launch(1.2573, Profile.clear_y_at(1.2573) + 0.02, direction, false)
	Engine.physics_ticks_per_second = original_ticks
	ball.freeze = true;ball.position = Vector3(1, 2, 2)
	net.clear_impacts()
	net.add_impact(Vector3(0, 0.5, 0), Vector3(0, 0, 20));net.advance_impacts(0.05)
	var nearby: float = absf(net.displacement_at(Vector3(0, 0.5, 0)))
	check(nearby > 0.01, "impact creates visible local displacement")
	check(absf(net.displacement_at(Vector3(2.5, 0.5, 0))) < nearby * 0.02, "ripple localized, not entire net wobble")
	check(absf(net.displacement_at(Vector3(0, Profile.top_y_at(0), 0))) < 1e-05, "top cable anchored to collision profile")
	for i in range(20): net.add_impact(Vector3(float(i % 3) * 0.2, 0.5, 0), Vector3(0, 0, 20))
	check(net._impacts.size() == 4, "repeated impacts bounded to four")
	net.advance_impacts(0.05)
	check(absf(net.displacement_at(Vector3(0, 0.5, 0))) <= 0.045, "repeated-hit deformation capped")
	var before = net._impacts.duplicate()
	shadows.update_shadows(); var before_shadow: Vector3 = shadows._shadows[0].global_position
	paused = true;ball.position.x += 1
	for i in range(5): await process_frame
	check(net._impacts == before, "pause freezes ripple clock")
	check(shadows._shadows[0].global_position == before_shadow, "pause freezes shadow positions")
	paused = false
	await process_frame
	check(shadows._shadows[0].global_position.x == ball.global_position.x, "resume refreshes shadow position")
	ball.reset(); await physics_frame; await physics_frame
	check(net._impacts.is_empty(), "ball reset clears old ripples")
	net.add_impact(Vector3(0, 0.5, 0), Vector3(0, 0, 20));net.advance_impacts(2.01)
	check(net._impacts.is_empty(), "damped impacts settle and stop uploads")
	for h in [-1.0, 0.0, 0.5, 3.5, 100.0]:
		var cue: Vector3 = Shadows.cue_for_height(h, true)
		check(cue.x >= Shadows.BALL_MIN_DIAMETER - 0.000001 and cue.x <= Shadows.BALL_MAX_DIAMETER + 0.000001 and cue.z >= Shadows.BALL_MIN_OPACITY - 0.000001 and cue.z <= Shadows.BALL_MAX_OPACITY + 0.000001, "ball shadow bounds at height %.1f" % h)
		var player: Vector3 = Shadows.cue_for_height(h, false)
		check(player.x <= 0.88 and player.z <= 0.25, "player shadow restrained")
	check(Shadows.cue_for_height(3.0, true).z < Shadows.cue_for_height(0.0, true).z, "higher ball shadow softer/lighter")
	ball.position = Vector3(0, 2, 1);shadows.update_shadows()
	check(shadows._shadows[0].visible, "shadow exists without any sun light")
	ball.hide();shadows.update_shadows();check( not shadows._shadows[0].visible, "hidden ball hides shadow")
	ball.show();ball.position.x = 9.0;shadows.update_shadows();check( not shadows._shadows[0].visible, "shadow hidden beyond court apron")
	shadows.setup(ball, left, right);check(shadows.get_child_count() == 3, "repeated setup leaves exactly three shadow draws")
	left.free();shadows.update_shadows();check( not shadows._shadows[1].visible, "freed target safely hides shadow")
	world.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("NET AND SHADOWS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func launch(x: float, y: float, direction: float, expect_hit: bool) -> void :
	ball.freeze = true;ball.global_position = Vector3(x, y, - direction * 0.65)
	ball.linear_velocity = Vector3.ZERO;ball.angular_velocity = Vector3.ZERO
	ball.flight_id += 1
	await physics_frame; await physics_frame
	net.clear_impacts(); var count: int = net.impact_count
	ball.freeze = false;ball.sleeping = false;ball.linear_velocity = Vector3(0, 0, direction * 20.0)
	for i in range(12): await physics_frame
	var hit: bool = net.impact_count > count
	check(net.impact_count - count <= 1, "one net impact event per contact, no sweep/solver double response")
	check(hit == expect_hit, "20m/s contact x%.4f y%.4f dir%+.0f expected%s actual%s pos%s" % [x, y, direction, expect_hit, hit, ball.position])
	if expect_hit: check((ball.linear_velocity.z * direction < 0.0 or (ball.linear_velocity.y > 0.1 and ball.linear_velocity.length() < 19.0)), "no tunneling %dHz at seam/top x%.4f y%.4f dir%+.0f vel%s" % [Engine.physics_ticks_per_second, x, y, direction, ball.linear_velocity])
