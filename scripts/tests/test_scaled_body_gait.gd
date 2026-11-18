extends SceneTree


const D = preload("res://scripts/player_body_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Torso = preload("res://scripts/articulated_torso_mesh.gd")
const Ready = preload("res://scripts/incoming_ready_motion.gd")
var checks: = 0
var failures: Array[String] = []
var records: Array = []
var output: = "/workspace/shared/pickleball-hands/scaled-body-gait.json"
var simulation_hz: = 60
var game
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and failures.size() < 100: failures.append(label)
func sole_y(mesh: MeshInstance3D) -> float:
	var box: AABB = mesh.mesh.get_aabb(); var lowest: = INF
	for x in [0, 1]:
		for y in [0, 1]:
			for z in [0, 1]: lowest = minf(lowest, (mesh.global_transform * (box.position + box.size * Vector3(x, y, z))).y)
	return lowest
func reset(p, pose: PostureDefinition) -> void :
	p.global_position = Vector3(float(p.player_num) * 2, p.ground_y, 0)
	p.current_velocity = Vector3.ZERO;p.is_jumping = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
	p.posture.editor_preview_mode = false;p.posture.transition_pose_blend = pose
	p.leg_ik.feet_initialized = false
	p.posture.force_posture_update(pose, false)
	p.leg_ik.update_leg_ik(0.0, pose)
func tick(p, pose: PostureDefinition, velocity: Vector3, delta: float) -> void :
	p.current_velocity = velocity
	p.global_position += velocity * delta
	p.posture.transition_pose_blend = pose
	p.posture.force_posture_update(pose, false)
	p.leg_ik.update_leg_ik(delta, pose)
	p.arm_ik.update_arm_ik(delta, pose)

func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--hz="): simulation_hz = int(arg.trim_prefix("--hz="))
	if simulation_hz not in [30, 60, 120]:
		push_error("Use --hz=30,60,120 for the actual-scene delta-rate gate")
		quit(2);return
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var builds_before: int = Torso.mesh_build_count
	for p in [game.player_left, game.player_right]:
		var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
		_test_model(p, pose)
		var directions: Array[Vector3] = [p._get_forward_axis(), p._get_forehand_axis(), (p._get_forward_axis() + p._get_forehand_axis()).normalized(), ( - p._get_forward_axis() + p._get_forehand_axis() * 0.65).normalized()]
		for fraction in [0.25, 0.5, 1.0]:
			for index in range(directions.size()):
				_run_case(p, pose, "speed%.2f_dir%d" % [fraction, index], directions[index] * p.move_speed * fraction, false, false)
		_run_case(p, pose, "wide_recovery", p._get_forehand_axis() * p.move_speed * 0.5, true, false)
		_run_case(p, pose, "split_step", Vector3.ZERO, false, false, true)
		_run_case(p, pose, "jump_landing", p._get_forward_axis() * p.move_speed * 0.25, false, true)
	check(Torso.mesh_build_count == builds_before, "gait/body updates never regenerate a mesh")
	var file: = FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records, "simulation_hz": simulation_hz, 
			"notes": "Production scene, real leg IK/planner, deterministic root trajectories. Jump trajectory exercises airborne/landing leg modes; full gameplay jump/contact suites are additional gates."}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("SCALED BODY/GAIT: %dHz; %d checks, %d failures -> %s" % [simulation_hz, checks, failures.size(), output])
	game.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)

func _test_model(p, pose: PostureDefinition) -> void :
	reset(p, pose)
	var model = p.body_pivot.get_meta("articulated_torso", null)
	check(model != null, "skinned abdomen/body initialized")
	if model == null: return
	check(model.skeleton.get_bone_count() == 3, "body has exactly three GPU bones")
	check(model.body_mesh.mesh.get_surface_count() == 1, "body uses one draw surface")
	check(model.body_mesh.mesh.surface_get_array_index_len(0) / 3 <= 560, "rounded body geometry budget <=560 triangles")
	check(p.body_pivot.get_node("TorsoMesh").layers == 0 and p.body_pivot.get_node("HipsMesh").layers == 0, "compatibility proxies do not draw")
	check(p.body_pivot.get_node("TorsoMesh/HeadMesh").is_visible_in_tree(), "head remains visible under torso proxy")
	var arrays: Array = model.body_mesh.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	for vertex in range(weights.size() / 4):
		var sum: = 0.0
		for influence in range(4):
			sum += weights[vertex * 4 + influence]
			check(bones[vertex * 4 + influence] >= 0 and bones[vertex * 4 + influence] < 3, "valid body bone index")


		check(absf(sum - 1.0) < 0.0001, "normalized packed body skin weights %.7f" % sum)
	for leg in [p.right_leg_node, p.left_leg_node]:
		check(is_equal_approx(leg.thigh_length, D.THIGH_LENGTH) and is_equal_approx(leg.shin_length, D.SHIN_LENGTH), "central leg dimensions agree with actual instances")
		check(leg.foot_mesh.mesh.get_aabb().size.is_equal_approx(Vector3(0.1, 0.05, 0.16)), "shoe envelope unchanged")
	for bend in [-18.0, 0.0, 18.0]:
		var def: PostureDefinition = pose.duplicate(true)
		def.spine_curve_deg = bend;def.torso_yaw_deg = bend;def.torso_roll_deg = bend * 0.5
		Body.apply(p, def)
		check(model.skeleton.get_bone_global_pose(0).is_equal_approx(Body.pelvis_transform(p, def)), "pelvis skin follows shared chain")
		check(model.skeleton.get_bone_global_pose(1).is_equal_approx(Body.abdomen_transform(p, def)), "abdomen skin follows shared chain")
		check(model.skeleton.get_bone_global_pose(2).is_equal_approx(Body.torso_transform(p, def)), "ribcage skin follows shared chain")
		var writes: int = model.bone_pose_write_count
		Body.apply(p, def)
		check(model.bone_pose_write_count == writes, "unchanged body pose does zero bone writes")

func _run_case(p, source: PostureDefinition, name: String, velocity: Vector3, reverse: bool, jumping: bool, split: bool = false) -> void :
	var pose: PostureDefinition = source.duplicate(true)
	reset(p, pose)
	var maximum_stretch: = 1.0
	var maximum_drift: = 0.0
	var minimum_sole: = INF
	var maximum_foot_error: = 0.0
	var previous: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
	var previous_t: Array[float] = [p.leg_ik.right_step_t, p.leg_ik.left_step_t]
	var tag: = "P%d %dHz %s" % [p.player_num, simulation_hz, name]
	for frame in range(simulation_hz * 2):
		var elapsed: float = float(frame) / simulation_hz
		var current: Vector3 = velocity if elapsed < 1.5 else Vector3.ZERO
		if reverse:
			if elapsed >= 2.0 / 3.0 and elapsed < 1.5: current = - velocity
			pose.stance_width = lerpf(0.72, source.stance_width, smoothstep(0.65, 1.4, elapsed))
		if split: pose.crouch_amount = source.crouch_amount + Ready.split_load(maxf(0.0, Ready.SPLIT_DURATION - elapsed))
		if jumping:
			var phase: float = clampf((elapsed - 0.2) / 0.72, 0, 1)
			p.is_jumping = phase > 0 and phase < 1
			p.global_position.y = p.ground_y + sin(PI * phase) * 0.24
		tick(p, pose, current, 1.0 / simulation_hz)
		check(p.right_arm_node.upper_pivot.global_position.distance_to(Body.shoulder_world(p, pose, p.body_pivot.global_transform)) < 1e-05, tag + " fitted shoulder query matches drawing")
		var feet: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
		var steps: Array[float] = [p.leg_ik.right_step_t, p.leg_ik.left_step_t]
		for side in range(2):
			var leg = p.right_leg_node if side == 0 else p.left_leg_node
			var thigh: float = leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)
			var shin: float = leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position)
			maximum_stretch = maxf(maximum_stretch, maxf(thigh / D.THIGH_LENGTH, shin / D.SHIN_LENGTH))
			maximum_foot_error = maxf(maximum_foot_error, leg.foot_pivot.global_position.distance_to(feet[side]))
			minimum_sole = minf(minimum_sole, sole_y(leg.foot_mesh))
			if frame > 0 and previous_t[side] >= 1 and steps[side] >= 1 and not p.is_jumping and not jumping:
				maximum_drift = maxf(maximum_drift, feet[side].distance_to(previous[side]))
		previous = feet;previous_t = steps
	check(maximum_stretch < 1.001, tag + " bounded actual leg extension %.4f" % maximum_stretch)
	check(maximum_drift < 0.001, tag + " planted feet do not skate %.5f" % maximum_drift)
	check(maximum_foot_error < 0.005, tag + " solved ankles follow actual targets %.5f" % maximum_foot_error)
	check(minimum_sole >= p.COURT_FLOOR_Y - 0.015, tag + " soles stay above floor %.5f" % minimum_sole)
	records.append({"case": tag, "speed": velocity.length(), "maximum_link_scale": maximum_stretch, "maximum_planted_drift_m": maximum_drift, "maximum_ankle_error_m": maximum_foot_error, "minimum_sole_y": minimum_sole})
