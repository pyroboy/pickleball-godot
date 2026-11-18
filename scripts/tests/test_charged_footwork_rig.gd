extends "res://scripts/tests/test_scaled_body_gait.gd"


func run() -> void :
	output = "/tmp/charged-footwork-rig.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
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
		for hz in [30, 60, 120]:
			for side in [0, 1]: _charged_case(p, hz, side)
	check(Torso.mesh_build_count == builds_before, "charged gait does not rebuild meshes")
	var file: = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("CHARGED FOOTWORK RIG: %d checks, %d failures -> %s" % [checks, failures.size(), output])
	game.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)
func _charged_case(p, hz: int, side: int) -> void :
	var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
	if p.posture.human_contact == null:
		p.posture.human_contact = p.posture.HumanContact.new(p, p.posture)
	reset(p, pose)
	var work = p.posture.human_contact.footwork
	check(work != null, "human footwork controller initializes")
	if work == null: return
	work.active = true
	work.state = "crossover";work.load_side = side
	var velocity: Vector3 = p._get_forehand_axis() * (3.5 if side == 0 else -3.5)
	var maximum_stretch: = 1.0; var maximum_drift: = 0.0; var maximum_foot_error: = 0.0
	var minimum_sole: = INF; var minimum_lateral: = INF; var maximum_lateral: = - INF
	var previous: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
	var serials: Array[int] = [p.leg_ik.right_contact_serial, p.leg_ik.left_contact_serial]
	var tag: = "P%d %dHz load%d" % [p.player_num, hz, side]
	for frame in range(hz * 3):
		var elapsed: float = float(frame) / hz
		var current: Vector3
		if elapsed < 1.2:
			work.state = "crossover";current = velocity
		elif elapsed < 1.5:
			work.state = "adjust";current = velocity.normalized() * 0.7
		else:
			work.state = "plant";current = Vector3.ZERO
		pose.set_meta("visual_locomotion_weight", 1.0 - smoothstep(1.2, 1.5, elapsed))
		tick(p, pose, current, 1.0 / hz)
		check(p.right_arm_node.upper_pivot.global_position.distance_to(Body.shoulder_world(p, pose, p.body_pivot.global_transform)) < 1e-05, tag + " fitted shoulder matches displayed chain")
		var feet: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
		var now_serials: Array[int] = [p.leg_ik.right_contact_serial, p.leg_ik.left_contact_serial]
		var locked: Array[bool] = [p.leg_ik.right_foot_locked, p.leg_ik.left_foot_locked]
		for foot_side in [0, 1]:
			var leg = p.right_leg_node if foot_side == 0 else p.left_leg_node
			maximum_stretch = maxf(maximum_stretch, maxf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position) / D.THIGH_LENGTH, leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position) / D.SHIN_LENGTH))
			maximum_foot_error = maxf(maximum_foot_error, leg.foot_pivot.global_position.distance_to(feet[foot_side]))
			minimum_sole = minf(minimum_sole, sole_y(leg.foot_mesh))
			if locked[foot_side] and serials[foot_side] == now_serials[foot_side]: maximum_drift = maxf(maximum_drift, previous[foot_side].distance_to(feet[foot_side]))
		if elapsed > 0.45 and elapsed < 1.2:
			var lateral: float = (feet[0] - feet[1]).dot(p._get_forehand_axis())
			minimum_lateral = minf(minimum_lateral, lateral);maximum_lateral = maxf(maximum_lateral, lateral)
		previous = feet;serials = now_serials
	check(maximum_stretch < 1.001, tag + " real legs retain fixed lengths %.5f" % maximum_stretch)
	check(maximum_drift < 1e-05, tag + " real supports do not slide %.5f" % maximum_drift)
	check(maximum_foot_error < 0.005, tag + " real ankles follow targets %.5f" % maximum_foot_error)
	check(minimum_sole >= p.COURT_FLOOR_Y - 0.015, tag + " soles remain above court %.5f" % minimum_sole)
	check(minimum_lateral < - 0.12 and maximum_lateral > 0.12, tag + " real feet pass laterally")
	check(p.leg_ik.is_support_ready(side), tag + " completed real stance supports load")
	records.append({"case": tag, "maximum_link_scale": maximum_stretch, "maximum_planted_drift_m": maximum_drift, "maximum_ankle_error_m": maximum_foot_error, "minimum_sole_y": minimum_sole, "minimum_court_lateral_gap": minimum_lateral, "maximum_court_lateral_gap": maximum_lateral})
	work.state = "idle";work.active = false
