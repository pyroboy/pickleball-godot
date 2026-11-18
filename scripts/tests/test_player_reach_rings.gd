extends SceneTree

const Policy = preload("res://scripts/runtime_policy.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
var checks: = 0
var failures: Array[String] = []
var game
var player
var ball
var rings
var settings
var old_setting
var human
var extended_contact: Dictionary
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func incoming(point: Vector3) -> Dictionary:
	ball.is_in_play = true
	ball.last_hit_by = 1
	ball.both_bounces_complete = true
	ball.bounces_since_last_hit = 0
	ball.global_position = point + player._get_forward_axis() * 0.08
	ball.linear_velocity = - player._get_forward_axis() * 0.3
	ball.flight_id += 1
	return {"samples": [{"pos": point + player._get_forward_axis() * 0.02, "time": 0.1, "bounces": 0}, {"pos": point, "time": 0.14, "bounces": 0}]}
func apply_plan(plan: Dictionary) -> void :
	human.contact = plan
	human._flight_id = ball.flight_id
	human.phase = -1
	rings.refresh()
func run() -> void :
	settings = root.get_node("Settings")
	old_setting = settings.get_value("beta_debug.reach_rings")
	settings.set_value("beta_debug.reach_rings", false)
	check(Policy.mobile_runtime and not Policy.developer_tools, "run with --mobile-runtime")
	check(settings.DEFAULTS["beta_debug.reach_rings"] == false, "rings must default off")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.set_physics_process(false);game.input_handler.set_process(false)
	player = game.player_left;ball = game.ball
	player.set_physics_process(false);game.player_right.set_physics_process(false)
	ball.freeze = true;ball.set_physics_process(false)
	player.global_position = Vector3(0, player.ground_y, 3.3)
	player.current_velocity = Vector3.ZERO
	player.leg_ik.feet_initialized = false;player._process(0.0);player.can_volley_from_feet()
	human = player.posture.human_contact
	rings = player.get_node("ReachRings")
	check( not rings.visible and not rings.is_processing() and rings._mesh == null, "off setting allocated/rendered geometry or processed")
	check(game.player_right.get_node_or_null("ReachRings") == null, "AI should not get blue player's guide")
	var pause = root.get_node("PauseController")
	pause.open();pause._menu._on_settings()
	await process_frame
	var panel = pause._menu._settings_overlay
	var toggle = panel.find_child("beta_debug_reach_rings", true, false)
	check(toggle != null, "settings beta toggle missing")
	var setup_start: = Time.get_ticks_usec()
	toggle.button_pressed = true
	var setup_us: = Time.get_ticks_usec() - setup_start
	check(settings.get_value("beta_debug.reach_rings") and rings.visible, "toggle not wired to live scene")
	settings._do_save()
	var saved: = ConfigFile.new()
	check(saved.load(settings.CONFIG_PATH) == OK and saved.get_value("beta_debug", "reach_rings", false), "toggle did not persist")
	panel._on_close(); await process_frame;pause.close(); await process_frame
	check( not paused and is_instance_valid(rings._mesh), "back/resume lost rings")
	check(rings.inner_radius > 0.6 and rings.outer_radius > rings.inner_radius + 0.25, "concentric radii not distinct")
	check(Planner.point_fits(player, rings.envelope_pose, rings.envelope_witness), "outer envelope witness is not anatomically reachable")
	check(rings._mesh.mesh is PlaneMesh and rings.get_child_count() == 3, "guide must use exactly the ring, cached path and contact marker meshes")
	check(rings._flight_path.mesh is ImmediateMesh and rings._contact_tip.mesh is SphereMesh, "incoming path/marker uses unexpected geometry")
	check(rings._contact_tip.mesh.radial_segments == 8 and rings._contact_tip.mesh.rings == 4, "contact marker exceeded low-poly budget")
	check(rings._mesh.mesh.get_faces().size() == 6, "ring geometry isn't two triangles")
	check(rings.find_children("*", "CollisionObject3D", true, false).is_empty(), "helper introduced collision")
	check(game.game_debug_ui == null and player.awareness_grid == null and player.debug_visual.incoming_traj_mesh == null, "beta toggle enabled heavy debug tools")
	var normal: Dictionary = {}
	for base in PostureLibrary.instance().all_definitions():
		if base.posture_id not in [0, 1, 2]: continue
		var p: Vector3 = player.global_position + base.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
		var trace: = incoming(p)
		var plan: = Planner.select(player, ball, trace)
		if not plan.is_empty() and not plan.get("extended", false) and Vector2(plan.point.x - player.position.x, plan.point.z - player.position.z).length() <= rings.inner_radius + 0.03:
			normal = plan;break
	check( not normal.is_empty(), "normal fixture lacks genuine contact")
	human.anticipation_path = PackedVector3Array([ball.global_position, normal.get("point", ball.global_position)])
	human.prediction_revision += 1
	apply_plan(normal)
	check(rings._flight_mesh.get_surface_count() == 1, "cached incoming path did not build one line surface")
	check(rings._flight_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 2, "single path segment exceeded two endpoints")
	check(rings.active_band == 1, "normal accepted plan did not light inner ring")
	for base in PostureLibrary.instance().all_definitions():
		if not base.has_zone: continue
		for extra in [0.22, 0.32, 0.42]:
			var p: Vector3 = player.global_position + player._get_forehand_axis() * ((base.zone_x_min + base.zone_x_max) * 0.5) + player._get_forward_axis() * (base.zone_forward_offset + extra)
			p.y = player.COURT_FLOOR_Y + (base.zone_y_min + base.zone_y_max) * 0.5
			var trace: = incoming(p)
			var plan: = Planner.select(player, ball, trace)
			if not plan.is_empty() and plan.get("extended", false): extended_contact = plan;break
		if not extended_contact.is_empty(): break
	check( not extended_contact.is_empty(), "extended fixture lacks genuine contact")
	apply_plan(extended_contact)
	check(rings.active_band == 2, "genuine extended plan did not light outer ring")
	var before: = {"ball_pos": ball.global_position, "ball_vel": ball.linear_velocity, "bounces": ball.bounces_since_last_hit, "flight": ball.flight_id, "plan": human.contact.duplicate(), "phase": human.phase, "pose": human.visual_pose, "paddle": player.paddle_node.global_transform}
	var cached_mesh = rings._flight_mesh
	var cached_revision: int = rings._path_revision
	var cached_vertices: PackedVector3Array = rings._flight_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var start: = Time.get_ticks_usec()
	for i in range(1000): rings.refresh()
	check(rings._flight_mesh == cached_mesh and rings._path_revision == cached_revision and rings._flight_mesh.get_surface_count() == 1 and rings._flight_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == cached_vertices, "unchanged prediction reallocated/rebuilt path geometry")
	var refresh_us: = Time.get_ticks_usec() - start
	check(before.ball_pos == ball.global_position and before.ball_vel == ball.linear_velocity and before.bounces == ball.bounces_since_last_hit and before.flight == ball.flight_id and before.plan == human.contact and before.phase == human.phase and before.pose == human.visual_pose and before.paddle == player.paddle_node.global_transform, "visual refresh mutated gameplay")
	ball.last_hit_by = 0;rings.refresh();check(rings.active_band == 0, "outgoing ball kept valid glow")
	ball.last_hit_by = 1;ball.flight_id += 1;rings.refresh();check(rings.active_band == 0, "stale flight kept valid glow")
	human._flight_id = ball.flight_id;ball.bounces_since_last_hit = 2;rings.refresh();check(rings.active_band == 0, "double bounce kept glow")
	ball.bounces_since_last_hit = 0;ball.is_in_play = false;rings.refresh();check(rings.active_band == 0, "dead ball kept glow")
	for offset in [Vector3(0, 5, - 0.6), Vector3(0, 1, 0.6), Vector3(3, 1, - 0.6)]:
		var point: Vector3 = player.global_position + offset
		var trace: = incoming(point)
		var rejected: = Planner.select(player, ball, trace)
		check(rejected.is_empty(), "invalid height/direction/distance unexpectedly accepted")
		apply_plan(rejected);check(rings.active_band == 0, "invalid plan enabled glow")
	var trace: = incoming(player.global_position + Vector3(0.42, 0.1, - 0.46))
	ball.both_bounces_complete = false
	apply_plan(Planner.select(player, ball, trace))
	check(rings.active_band == 0, "mandatory bounce incorrectly glowed")
	player.position += Vector3(0.4, 0.5, 1);rings.refresh()
	check(is_equal_approx(rings.global_position.y, player.COURT_FLOOR_Y + 0.008), "jump lifted rings off court")
	check(is_equal_approx(rings.global_position.x, player.global_position.x) and is_equal_approx(rings.global_position.z, player.global_position.z), "rings did not follow player")
	game.game_state = game.GameState.POINT_SCORED;rings.refresh();check( not rings.visible, "between-point guide visible")
	game.game_state = game.GameState.PLAYING;game.match_over = true;rings.refresh();check( not rings.visible, "match-over guide visible")
	game.match_over = false;rings.refresh();check(rings.visible, "guide did not restore for next rally")
	var mesh = rings._mesh
	var flight_path = rings._flight_path
	var contact_tip = rings._contact_tip
	for iteration in range(4):
		settings.set_value("beta_debug.reach_rings", false)
		check( not rings.visible and not rings.is_processing(), "off did not stop visuals/work")
		settings.set_value("beta_debug.reach_rings", true)
		check(rings._mesh == mesh and rings._flight_path == flight_path and rings._contact_tip == contact_tip, "repeated toggle reallocated geometry")
	settings.set_value("beta_debug.reach_rings", old_setting)
	settings._do_save()
	print("RING PROFILE: setup_us=%d refresh_mean_us=%.2f inner=%.3f outer=%.3f" % [setup_us, refresh_us / 1000.0, rings.inner_radius, rings.outer_radius])
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER REACH RINGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
