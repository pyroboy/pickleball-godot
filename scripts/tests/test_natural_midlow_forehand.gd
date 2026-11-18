extends SceneTree


const D = preload("res://scripts/paddle_dimensions.gd")
const O = preload("res://scripts/stroke_preparation_orientation.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Clearance = preload("res://scripts/body_clearance.gd")
const Drain = preload("res://scripts/tests/hand_scene_teardown.gd")
class Late extends Node:
	signal done
	func _process(_delta: float) -> void : done.emit()
var game
var late: Late
var camera: Camera3D
var caption: Label
var output: = ProjectSettings.globalize_path("user://natural_midlow_forehand")
var failures: Array[String] = []
var checks: = 0
var samples: Array = []
var hits: Array = []
var events: Array = []
var render: = false
var elapsed: = 0.0
var reviewer
var shape_samples: Array = []
var contact_snapshot: Dictionary = {}
var motion_flags: Array[String] = []
var use_authored: = true
func _initialize() -> void : call_deferred("run")
func v(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])
func vd(a: Vector3) -> Array: return [a.x, a.y, a.z]
func txd(t: Transform3D) -> Array: return [vd(t.basis.x), vd(t.basis.y), vd(t.basis.z), vd(t.origin)]
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func fields(pose: PostureDefinition, data: Dictionary) -> void :
	for key in data:
		var value = data[key]
		pose.set(key, v(value) if value is Array and value.size() == 3 else value)
func hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["scripts/player.gd", "scripts/arm_anatomy.gd", "scripts/human_contact_controller.gd", "scripts/incoming_contact_planner.gd", "scripts/drive_serve_motion.gd", "scripts/posture_definition.gd", "scripts/groundstroke_support_motion.gd", "scripts/paddle_dimensions.gd", "scripts/articulated_hand.gd", "data/postures/00_forehand.tres", "data/postures/13_mid_low_forehand.tres"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result
func measure(p, point: Vector3) -> Dictionary:
	var a = p.right_arm_node; var h = a.articulated_hand
	var s: Vector3 = a.upper_pivot.global_position; var e: Vector3 = a.forearm_pivot.global_position
	var w: Vector3 = a.hand_mesh.global_transform * h.wrist_socket
	var paddle: Transform3D = p.paddle_node.global_transform
	var head: Vector3 = paddle * D.HEAD_OFFSET
	var sign_side: float = signf((point - head).dot(paddle.basis.z))
	return {"shoulder": vd(s), "elbow": vd(e), "wrist": vd(w), "head": vd(head), "ball": vd(point), 
		"paddle": txd(paddle), "elbow_drop_m": s.y - e.y, "elbow_outboard_m": e.x - s.x, 
		"upper_length_m": s.distance_to(e), "forearm_length_m": e.distance_to(w), "stretch": a.visual_stretch, 
		"channels": Anatomy.decompose(Anatomy.forearm_reference_for_arm(a, w, false), a.hand_mesh.global_basis * h.anatomical_basis, h.radial_sign), 
		"dorsal_dot_ball_side": (a.hand_mesh.global_basis * h.anatomical_basis.z).dot(paddle.basis.z * sign_side), 
		"head_surface_gap_m": Geometry.distance_to_head_shape(paddle.affine_inverse() * point) - Ball.BALL_RADIUS, 
		"body_root": vd(p.global_position), "feet_locked": [p.leg_ik.right_foot_locked, p.leg_ik.left_foot_locked]}
func clear_move() -> void :
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
func shape_measure(p, label: String) -> Dictionary:
	reviewer.sample_time_seconds = elapsed
	var result: Dictionary = reviewer._measure_body(p)
	var pose: PostureDefinition = p.posture._presented_body_pose
	if pose == null: pose = p.posture.transition_pose_blend
	var skin = p.body_pivot.get_meta("articulated_torso", null)
	var frames: Array[Transform3D] = [skin._last_pelvis, skin._last_abdomen, skin._last_chest]
	var body: Dictionary = Clearance.volumes(p, pose, p.body_pivot.global_transform, frames)
	var arm_body: Array = []
	for arm in [p.right_arm_node, p.left_arm_node]:
		arm_body.append({"upper": Clearance.mesh_surface_margins(arm.upper_mesh, body, arm.upper_pivot.global_position, arm.forearm_pivot.global_position, 0.08), "forearm": Clearance.mesh_surface_margins(arm.fore_mesh, body)})
	result["arm_body_margins"] = arm_body;result["label"] = label
	shape_samples.append(result)
	return result
func save_snapshot(p) -> Dictionary:
	var nodes: Array = []; var bones: Array = []
	var all_nodes: Array = [p];all_nodes.append_array(p.find_children("*", "Node3D", true, false))
	for node in all_nodes:
		nodes.append([node, node.transform])
		if node is Skeleton3D:
			var poses: Array = []
			for index in node.get_bone_count(): poses.append(node.get_bone_pose(index))
			bones.append([node, poses])
	return {"nodes": nodes, "bones": bones, "ball": game.ball.global_position, "paddle": p.paddle_node.global_transform}
func replay_contact(p) -> void :
	for item in contact_snapshot.nodes: item[0].transform = item[1]
	for item in contact_snapshot.bones:
		for index in item[1].size(): item[0].set_bone_pose(index, item[1][index])
	game.ball.global_position = contact_snapshot.ball
func steer(delta: Vector3, dt: float, speed: float) -> void :
	clear_move()
	var flat: = Vector2(delta.x, delta.z)
	if flat.length() < 0.001: return
	var deadzone: float = (InputMap.action_get_deadzone("move_left") + InputMap.action_get_deadzone("move_right") + InputMap.action_get_deadzone("move_up") + InputMap.action_get_deadzone("move_down")) * 0.25
	var magnitude: float = deadzone + (1.0 - deadzone) * minf(1.0, flat.length() / maxf(0.0001, speed * dt))
	var raw: Vector2 = flat.normalized() * magnitude
	Input.action_press("move_right" if raw.x >= 0 else "move_left", absf(raw.x))
	Input.action_press("move_down" if raw.y >= 0 else "move_up", absf(raw.y))
func run() -> void :
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(output)
	var before: = hashes()
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	late = Late.new();late.process_priority = 100000;root.add_child(late)
	for frame in range(8): await late.done
	reviewer = preload("res://scripts/debug/pose_simulation_review.gd").new()
	reviewer.game = game;reviewer.surface = Geometry.sample_head_surface()
	game.game_serve.cleanup();game.game_serve.set_process(false);game.game_serve.set_physics_process(false)
	game.pvp_mode = true;game.aim_focus._sync_realtime_mode()
	game.reaction_button.auto_fire_on_perfect = false
	game._set_game_state(game.GameState.PLAYING);game.rally_scorer._serve_was_hit = true
	game.player_right.set_ai_movement_enabled(false);game.player_right.set_process(false);game.player_right.set_physics_process(false)
	var p = game.player_left
	p.global_position = Vector3(0, p.ground_y, 3.2);p.velocity = Vector3.ZERO;p.current_velocity = Vector3.ZERO
	p.hitting.clear_charge_visual();p.hitting.serving_visual_active = false
	game.ball.freeze = true;game.ball.is_in_play = false
	var lib = PostureLibrary.instance(); var original: PostureDefinition = lib.get_def(13)
	var pose: PostureDefinition = original.duplicate(true)

	p.posture.editor_preview_mode = true;p.posture.transition_pose_blend = pose
	p.posture.force_posture_update(pose);p.leg_ik.feet_initialized = false;p._process(0.0)
	p.paddle_node.global_transform = Path.world_transform(p, pose);p.arm_ik.update_arm_ik(0.0, pose)
	var actual_s: Vector3 = p.right_arm_node.upper_pivot.global_position
	var expected_s: Vector3 = actual_s
	var fit_delta: Vector3 = actual_s - expected_s

	pose.paddle_forehand_mul += fit_delta.x;pose.paddle_y_offset += fit_delta.y;pose.paddle_forward_mul -= fit_delta.z
	pose.right_elbow_pole += Vector3(fit_delta.x, fit_delta.y, - fit_delta.z)
	pose.zone_forward_offset -= fit_delta.z
	p.posture.force_posture_update(pose);p._process(0.0)
	p.paddle_node.global_transform = Path.world_transform(p, pose);p.arm_ik.update_arm_ik(0.0, pose)
	var ball_offset: Vector3 = (p.paddle_node.global_transform * D.HEAD_OFFSET + p.paddle_node.global_basis.z * (D.HEAD_HALF_THICKNESS + Ball.BALL_RADIUS) - p.global_position)
	var static_measure: = measure(p, p.global_position + ball_offset)
	shape_measure(p, "static_candidate")
	check(static_measure.channels.within_animation_budget, "static fitted candidate wrist budget")
	check(static_measure.elbow_drop_m > 0.12, "static fitted candidate low elbow")
	check(static_measure.dorsal_dot_ball_side < - 0.5, "static candidate uses palmar striking side")
	check(absf(static_measure.head_surface_gap_m) < 0.0001, "static candidate finite sphere tangency")
	check(absf(static_measure.upper_length_m - 0.35) < 0.0001 and absf(static_measure.forearm_length_m - 0.35) < 0.0001, "static exact two-link lengths")
	check(p.ground_y + ball_offset.y >= pose.zone_y_min and p.ground_y + ball_offset.y <= pose.zone_y_max, "candidate retains existing mid-low height band")
	check(ball_offset.x >= pose.zone_x_min and ball_offset.x <= pose.zone_x_max, "candidate retains existing mid-low lateral band")
	lib._by_id[13] = pose
	for index in lib.definitions.size():
		if lib.definitions[index].posture_id == 13: lib.definitions[index] = pose
	p.posture.editor_preview_mode = false
	p.posture.transition_pose_blend = null;p.posture.human_contact.visual_pose = null
	p.leg_ik.feet_initialized = false
	for frame in range(24): await late.done

	var original_target: = Vector3(0.42, 1.08, 2.74)
	var duration: = 0.65
	var origin: = Vector3(original_target.x, original_target.y + 0.25, original_target.z - 4.0 * duration)
	var velocity: Vector3 = (original_target - origin) / duration
	velocity.y += 0.5 * Ball.get_effective_gravity() * duration
	for iteration in range(12): velocity += (original_target - game.shot_physics._spin_position_after(origin, velocity, Vector3.ZERO, duration)) / duration * 0.86
	var flight: Dictionary = Flight.trace(origin, velocity, Vector3.ZERO)
	var station: Dictionary = {}
	var station_y: float = p.ground_y + ball_offset.y
	for index in range(flight.samples.size() - 1):
		var a: Dictionary = flight.samples[index]; var b: Dictionary = flight.samples[index + 1]
		if a.bounces != 0 or b.bounces != 0 or a.pos.y < station_y or b.pos.y > station_y or a.vel.y >= 0: continue
		var fraction: float = (a.pos.y - station_y) / (a.pos.y - b.pos.y)
		station = {"point": a.pos.lerp(b.pos, fraction), "time": lerpf(a.time, b.time, fraction)};break
	check( not station.is_empty(), "untouched incoming flight reaches derived height before bounce")
	if station.is_empty(): await finish(before, {"static": static_measure});return
	var root_target: Vector3 = station.point - ball_offset;root_target.y = p.ground_y
	var starting_root: Vector3 = p.global_position
	var required: float = Vector2(root_target.x - starting_root.x, root_target.z - starting_root.z).length()
	check(required / p.move_speed + 0.3 < float(station.time), "enough flight time for ordinary movement and compact hold")
	check(p._clamp_to_court(root_target).distance_to(root_target) < 0.0001, "derived player station stays inside existing court bounds")
	game.ball.reset_rally_state();game.ball.both_bounces_complete = true;game.ball.bounces_since_last_hit = 0
	game.ball.global_position = origin;game.ball.linear_velocity = velocity;game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_hit_by = 1;game.ball.is_in_play = true;game.ball.freeze = false;game.ball.flight_id += 1
	game.ball.hit_by_paddle.connect( func(team):
		if int(team) != 0: return
		var hit: Dictionary = measure(p, game.ball.global_position)
		hit["time"] = elapsed;hit["outgoing"] = vd(game.ball.linear_velocity)
		var normal: Vector3 = p.paddle_node.global_basis.z
		if (game.ball.global_position - p.paddle_node.global_transform * D.HEAD_OFFSET).dot(normal) < 0: normal = - normal
		hit["normal_dot_outgoing"] = normal.dot(game.ball.linear_velocity.normalized())
		hit["selected_pose"] = p.posture.human_contact.swing_def.posture_id
		hit["legal_feet"] = p.can_volley_from_feet()
		hit["raw_evidence"] = p.posture.human_contact.last_contact_evidence.duplicate()
		hit["shape"] = shape_measure(p, "actual_contact")
		hits.append(hit))
	if render: setup_camera(p)
	game.input_handler.set_process(true)
	var arrived_at: = -1.0; var pressed_at: = -1.0; var released: = false; var max_root_step: = 0.0
	var previous_root: Vector3 = p.global_position
	var prior_phase: = -100
	var full_hold: bool = "--full-hold" in OS.get_cmdline_user_args()
	for frame in range(180):
		if arrived_at < 0:
			if Vector2(root_target.x - p.global_position.x, root_target.z - p.global_position.z).length() < 0.002:
				clear_move();arrived_at = elapsed;events.append({"event": "arrived via Input", "time": elapsed, "root": vd(p.global_position)})
			else: steer(root_target - p.global_position, 1.0 / 60.0, p.move_speed)
		elif pressed_at < 0 and elapsed - arrived_at >= (0.04 if full_hold else 0.22):
			Input.action_press("ui_accept");pressed_at = elapsed;events.append({"event": "press Hit", "time": elapsed})
		elif pressed_at >= 0 and not released and elapsed - pressed_at >= (0.46 if full_hold else 0.1):
			Input.action_release("ui_accept");released = true;events.append({"event": "release Hit", "time": elapsed, "charge": game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME})
		await late.done
		elapsed += 1.0 / 60.0
		max_root_step = maxf(max_root_step, p.global_position.distance_to(previous_root));previous_root = p.global_position
		var human = p.posture.human_contact
		if render and not hits.is_empty() and contact_snapshot.is_empty(): contact_snapshot = save_snapshot(p)
		if human.phase != prior_phase:
			shape_measure(p, "phase_%d" % human.phase);prior_phase = human.phase
		var row: Dictionary = measure(p, game.ball.global_position)
		row.merge({"frame": frame, "time": elapsed, "physics_tick": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(), "phase": human.phase, "displayed_pose": p.posture.transition_pose_blend.posture_id if p.posture.transition_pose_blend != null else -1, "selected_pose": human.contact.get("posture", -1), "ttc": human.contact.get("time", -1), "charge_active": p.hitting.charge_visual_active})
		samples.append(row)
		if render and frame % 2 == 0:
			caption.text = "Same incoming ball | ordinary movement + held/released Hit\nAuthored mid-low forehand; frame%d phase%d" % [frame, human.phase]
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("frame%04d.png" % (frame / 2)))
		if hits.size() > 0 and human.phase < 0 and frame > 75: break
	check(arrived_at >= 0, "ordinary Input movement reached requested station")
	check(max_root_step <= p.move_speed / 60.0 + 0.001, "no instant root teleport during live flight")
	check(released, "actual held input released")
	check(hits.size() == 1, "exactly one actual paddle return")
	for hit in hits:
		check(hit.selected_pose == 13, "real return uses the candidate mid-low forehand")
		check(hit.dorsal_dot_ball_side < - 0.5, "actual contact presents the palmar face")
		check(hit.elbow_drop_m > 0.12, "actual contact keeps the elbow below shoulder")
		check(hit.channels.within_animation_budget, "actual contact wrist stays within animation budget")
		check(hit.stretch <= 1.001 and absf(hit.upper_length_m - 0.35) < 0.0001 and absf(hit.forearm_length_m - 0.35) < 0.0001, "actual contact preserves link lengths")
		check(absf(hit.head_surface_gap_m) < 0.002, "actual finite head surface contact")
		check(hit.legal_feet, "actual volley feet remain legal")
		check(hit.normal_dot_outgoing > 0.7, "outgoing ball leaves the presented striking side")
		for region in hit.shape.body_surface_clearance_m: check(hit.shape.body_surface_clearance_m[region] >= - 3e-05, "contact paddle clears actual " + region)
		for region in hit.shape.arm_body_margins[0].upper: check(hit.shape.arm_body_margins[0].upper[region] >= - 3e-05, "contact main upper arm clears " + region)
		for region in hit.shape.arm_body_margins[0].forearm: check(hit.shape.arm_body_margins[0].forearm[region] >= - 3e-05, "contact main forearm clears " + region)
	var maximum_budget: = 0.0
	for sample in samples: maximum_budget = maxf(maximum_budget, sample.channels.coupled_budget_ratio)
	if maximum_budget > 1.001: motion_flags.append("Full-motion main wrist exceeds the combined animation budget: max ratio %.6f" % maximum_budget)
	for sample in shape_samples:
		for side in [0, 1]:
			for region in sample.arm_body_margins[side].upper:
				if sample.arm_body_margins[side].upper[region] < - 3e-05: motion_flags.append("%s arm%d upper/%s conservative body margin %.6fm" % [sample.label, side, region, sample.arm_body_margins[side].upper[region]])
	if use_authored:
		for sample in samples:
			if sample.phase >= 0 and sample.displayed_pose == 13:
				check(sample.channels.within_animation_budget, "authored mid-low frame%d wrist budget" % sample.frame)
				check(sample.stretch <= 1.001 and absf(sample.upper_length_m - 0.35) < 0.0001 and absf(sample.forearm_length_m - 0.35) < 0.0001, "authored mid-low frame%d exact links" % sample.frame)
		for sample in shape_samples:
			if sample.pose != 13: continue
			for side in [0, 1]:
				for part in ["upper", "forearm"]:
					for region in sample.arm_body_margins[side][part]: check(sample.arm_body_margins[side][part][region] >= - 3e-05, "authored mid-low %s arm%d %s/%s" % [sample.label, side, part, region])
	if render and not contact_snapshot.is_empty():
		game.process_mode = Node.PROCESS_MODE_DISABLED
		var all_nodes: Array = [game];all_nodes.append_array(game.find_children("*", "", true, false))
		for node in all_nodes: node.set_process(false);node.set_physics_process(false)
		for tween in get_processed_tweens(): tween.kill()
		replay_contact(p)
		var center: Vector3 = p.global_position + Vector3(0.12, 0.0, - 0.12)
		for view in ["front", "hitting_side", "threequarter"]:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 1.95
			var direction: Vector3 = Vector3.FORWARD if view == "front" else Vector3.RIGHT if view == "hitting_side" else Vector3(1, 0, -1).normalized()
			camera.global_position = center + direction * 2.5 + Vector3.UP * 0.12;camera.look_at(center)
			caption.text = "Actual input contact | %s | authored mid-low forehand\nActual controller contact; inherited high forehand remains separate" % view
			await late.done; await RenderingServer.frame_post_draw
			check(p.paddle_node.global_transform.is_equal_approx(contact_snapshot.paddle), "contact replay preserves actual paddle")
			root.get_texture().get_image().save_png(output.path_join("actual_contact_%s.png" % view))
	await finish(before, {"static": static_measure, "fit_delta": vd(fit_delta), "feed": {"origin": vd(origin), "velocity": vd(velocity)}, "station": {"point": vd(station.point), "time": station.time}, "starting_root": vd(starting_root), "root_target": vd(root_target), "required_movement_m": required, "maximum_root_step_m": max_root_step})
func setup_camera(p) -> void :
	root.size = Vector2i(1000, 1000);root.content_scale_size = Vector2i(1000, 1000)
	camera = Camera3D.new();game.add_child(camera);camera.near = 0.01;camera.fov = 42
	var focus: Vector3 = p.global_position + Vector3(0.15, 0.0, 0.1)
	camera.global_position = focus + Vector3(1.7, 0.35, -2.8);camera.look_at(focus);camera.make_current()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()
	var layer: = CanvasLayer.new();root.add_child(layer);caption = Label.new();layer.add_child(caption)
	caption.position = Vector2(20, 20);caption.add_theme_font_size_override("font_size", 20);caption.add_theme_constant_override("outline_size", 4)
func finish(before: Dictionary, summary: Dictionary) -> void :
	clear_move();Input.action_release("ui_accept")
	var after: = hashes();check(before == after, "production source hashes unchanged")
	summary.merge({"checks": checks, "failures": failures, "motion_flags": motion_flags, "hits": hits, "events": events, "samples": samples, "shape_samples": shape_samples, "source_before": before, "source_after": after, "scope": "Saved authored pose13", "control_path": "Original feed, actual Input movement/charge/release; no contact-gate edit"})
	var file: = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE);file.store_string(JSON.stringify(summary, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("NATURAL FOREHAND STATION ", checks, " checks; ", failures.size(), " failures; ", hits.size(), " real hits")
	if reviewer: reviewer.free()
	await Drain.finish(self, game, late);quit(0 if failures.is_empty() else 1)
