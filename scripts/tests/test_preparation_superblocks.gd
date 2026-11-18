extends SceneTree
const Regions = preload("res://scripts/preparation_superblocks.gd")
const Fixture = preload("res://scripts/tests/fixtures/distant_preparation_fixture.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const AudioTeardown = preload("res://scripts/tests/audio_teardown.gd")
var checks: = 0
var failures: Array[String] = []
var records: Array = []
var game
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func scene(data: Dictionary = {}):
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	Fixture.prepare(game, data)
	await physics_frame; await physics_frame
func end_scene():
	Fixture.release(game)
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	game.queue_free(); await process_frame; await process_frame
func run():
	create_timer(160).timeout.connect( func(): quit(2))
	await scene()
	var geometry: = Regions.layout()
	check(geometry.blocks.size() == 8, "exactly eight blocks")
	check(is_equal_approx(geometry.left, -0.8461) and is_equal_approx(geometry.right, 1.068), "outer edges from authored widest zones")
	check(is_equal_approx(geometry.edges[0], 0.0) and is_equal_approx(geometry.edges[3], 1.777) and is_equal_approx(geometry.edges[4], 2.1124), "floor / true overhead / high overhead bounds")
	check(game.player_left.get_node("ReachRings").preparation_visual == null, "disabled DEBUG must not construct geometry")
	for player in [game.player_left, game.player_right]:
		player.global_position = Vector3(0, player.ground_y, 3.8 if player.player_num == 0 else -3.8)
		for rotation in [-1.7, 0.0, 1.3]:
			player.rotation.y = rotation
			for block in geometry.blocks:
				check(is_equal_approx(block.x_max - block.x_min, 2.0), "width is exactly 2 m")
				for x in [block.x_min, block.x_max]:
					for y in [block.y_min, block.y_max]:
						var world: Vector3 = Regions.world_point(player, x, y, block.forward)
						var local: Vector3 = Regions.local_point(player, world)
						check(local.distance_to(Vector3(x, y, block.forward)) < 1e-05, "vertex frame drift after body/root rotation")
						var vertex_choice: = Regions.classify(local, geometry, {}, 0.0)
						check( not vertex_choice.is_empty() and not bool(vertex_choice.get("directional_only", true)), "shared or outer block vertex must classify without a hole")
				var middle: = Vector3((block.x_min + block.x_max) * 0.5, (block.y_min + block.y_max) * 0.5, block.forward)
				var selected: = Regions.classify(middle, geometry)
				check(selected.block_id == block.id, "all eight block centers classify")
			player.global_position.x += 0.3
		player.rotation.y = 0.0
	for side in [-1, 1]:
		var x: float = geometry.left - 1.0 if side < 0 else geometry.right + 1.0
		for seam in range(1, 4):
			var before: = Regions.classify(Vector3(x, geometry.edges[seam] - 0.0001, geometry.front), geometry)
			var after: = Regions.classify(Vector3(x, geometry.edges[seam] + 0.0001, geometry.front), geometry)
			check(before.band == seam - 1 and after.band == seam, "band seam continuous / deterministic")
			var stable: = Regions.classify(Vector3(x, geometry.edges[seam] + 0.01, geometry.front), geometry, before, 1.0)
			var urgent: = Regions.classify(Vector3(x, geometry.edges[seam] + 0.01, geometry.front), geometry, before, 0.1)
			check(stable.band == seam - 1 and urgent.band == seam, "spatial seam hysteresis releases immediately for close contact")
		check(Regions.classify(Vector3(x, - 0.001, geometry.front), geometry).is_empty(), "below-floor advice rejected")
		var outside: = Regions.classify(Vector3(x + side * 2.0, 1.0, geometry.front), geometry)
		check(outside.directional_only and outside.block_id == -1, "beyond strip is guidance only")
	game.player_left.get_node("ReachRings")._set_preparation_enabled(true)
	check(game.player_left.get_node("ReachRings").preparation_visual.blocks.size() == 8, "enabled debug constructs eight boxes")
	game.player_left.get_node("ReachRings")._set_preparation_enabled(false)
	check( not game.player_left.get_node("ReachRings").preparation_visual.visible, "debug hides on toggle off")
	await end_scene()
	for side in [-1, 1]:
		for band in range(4):
			await held_case(side, band, geometry)
	await mirrored_cases(geometry)
	await invalid_cases()
	await AudioTeardown.drain(self)
	var file = FileAccess.open("/tmp/preparation-superblocks-evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "layout": geometry, "cases": records}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("PREPARATION SUPERBLOCKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func held_case(side: int, band: int, geometry: Dictionary):
	var height: float = (geometry.edges[band] + geometry.edges[band + 1]) * 0.5 + PickleballConstants.FLOOR_Y
	var lateral: float = (geometry.left - 1.0) if side < 0 else (geometry.right + 1.0)
	await scene({"lateral": lateral, "height": height, "forward": geometry.front, "duration": 1.6})
	var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
	check(h.superblock_hint.is_empty(), "no automatic superblock activation side=%d band=%d" % [side, band])
	var start: Vector3 = p.global_position
	Fixture.press(game)
	var hint: Dictionary = h.superblock_hint.duplicate()
	check( not hint.is_empty(), "held crossing activates side=%d band=%d" % [side, band])
	if not hint.is_empty():
		check(hint.band == band and hint.side == side and not hint.directional_only, "all eight live predicted crossing choices")
		check(hint.def.family == (3 if band == 3 else (1 if side < 0 else 0)), "band selects expected advisory family")
		check(bool(hint.preparation_only), "advisory cannot be movement/hit permission")
		check( not h.footwork.activate_plan(hint, b), "advisory refused by movement planner")
	check(h.contact.is_empty(), "distant block cannot enlarge actual reach")
	check( not h.release_timing_state().release_ready, "advisory cannot enable release-ready cue")
	check(p.global_position.distance_to(start) < 0.001 and b.last_hit_by == 1, "press cannot teleport or hit")
	game.input_handler.cancel_charge_input()
	for frame in range(3): Fixture.tick(game); await physics_frame
	check(h.superblock_hint.is_empty(), "cancel suppresses same held advisory")
	Fixture.release(game); await physics_frame
	Fixture.press(game); await physics_frame
	check( not h.superblock_hint.is_empty(), "new press re-arms advisory")
	Fixture.release(game)
	check(h.superblock_hint.is_empty(), "release clears superblock activation immediately")
	records.append({"side": side, "band": band, "height": height, "hint": hint.get("label", ""), "crossing": hint.get("point", Vector3.ZERO), "time": hint.get("time", -1)})
	await end_scene()
func invalid_cases():
	for mode in ["fault", "dead", "outgoing", "away", "second_bounce"]:
		await scene({"lateral": 2.3})
		Fixture.press(game)
		var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
		match mode:
			"dead": b.is_in_play = false
			"outgoing": b.last_hit_by = 0
			"away": b.linear_velocity = Vector3(0, 0, -7)
			"second_bounce": b.bounces_since_last_hit = 2
			"fault": game._set_game_state(game.GameState.POINT_SCORED)
		for frame in range(3): await physics_frame
		check(h.superblock_hint.is_empty(), mode + " clears advisory")
		check(b.last_hit_by != 0 or mode == "outgoing", mode + " manufactured contact")
		await end_scene()

func mirrored_cases(geometry: Dictionary):
	for side in [-1, 1]:
		for band in range(4):
			var height: float = (geometry.edges[band] + geometry.edges[band + 1]) * 0.5 + PickleballConstants.FLOOR_Y
			var lateral: float = geometry.left - 1.0 if side < 0 else geometry.right + 1.0
			await scene({"lateral": lateral, "height": height, "forward": geometry.front, "duration": 1.6})
			var left = game.player_left; var right = game.player_right; var ball = game.ball
			var original: = Regions.select(left, ball, Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity), true)
			right.global_position = Vector3( - left.global_position.x, right.ground_y, - left.global_position.z)
			right.current_velocity = Vector3.ZERO
			right.leg_ik.feet_initialized = false;right._process(0.0);right.can_volley_from_feet()
			ball.global_position = Vector3( - ball.global_position.x, ball.global_position.y, - ball.global_position.z)
			ball.linear_velocity = Vector3( - ball.linear_velocity.x, ball.linear_velocity.y, - ball.linear_velocity.z)
			ball.angular_velocity = Vector3( - ball.angular_velocity.x, ball.angular_velocity.y, - ball.angular_velocity.z)
			ball.last_hit_by = 0
			var mirrored: = Regions.select(right, ball, Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity), true)
			check( not original.is_empty() and not mirrored.is_empty(), "mirrored front-plane crossing exists for all eight bands")
			if not original.is_empty() and not mirrored.is_empty():
				check(original.block_id == mirrored.block_id and original.posture == mirrored.posture and absf(original.time - mirrored.time) < 0.001, "mirror preserves block, family and crossing time")
				check(original.point.distance_to(Vector3( - mirrored.point.x, mirrored.point.y, - mirrored.point.z)) < 0.001, "crossing point is court-direction symmetric")
				check(original.target_root.distance_to(Vector3( - mirrored.target_root.x, mirrored.target_root.y, - mirrored.target_root.z)) < 0.001, "directional guidance mirrors around actual player")
			await end_scene()
