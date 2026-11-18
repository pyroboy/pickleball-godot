extends SceneTree
## Default: exact parity only. --bench adds the opt-in serial microbenchmark;
## --bench-only skips parity. No timers are sampled inside the parity pass.
const Current = preload("res://scripts/ready_ball_tracking.gd")
const Reference = preload("res://scripts/tests/fixtures/ready_ball_tracking_code27_reference.gd")
const CurrentTrace = preload("res://scripts/tests/fixtures/ready_tracking_candidate_trace.gd")
const ReferenceTrace = preload("res://scripts/tests/fixtures/ready_tracking_reference_trace.gd")
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const EXPECTED_REFERENCE_SHA256 = "a6a6f72bca1dc19a3af2f56fb86336805d1b39cb5c6e1dc61ebbd9cf6549cc2b"
var game
var checks: int = 0
var cases: int = 0
var limited_calls: int = 0
var unbounded_calls: int = 0
var early_calls: int = 0
var reference_samples: int = 0
var candidate_resources: int = 0
var failures: Array[String] = []
var report: Dictionary = {}
var output: String = ""
var benchmark: bool = false
var benchmark_only: bool = false
var bench_samples: int = 120
var bench_rounds: int = 5

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 100: failures.append(label)

func _definitions() -> Array[PostureDefinition]:
	var result: Array[PostureDefinition] = []
	var files: PackedStringArray = DirAccess.get_files_at("res://data/postures")
	files.sort()
	for name in files:
		if name.ends_with(".tres"):
			result.append(load("res://data/postures/" + name).duplicate(true))
	return result

func _configure_player(player, profile: int) -> void:
	player.hitting.serving_visual_active = false
	player.hitting.charge_visual_active = false
	player.hitting.is_in_follow_through = false
	player.posture.editor_preview_mode = false
	player.posture._committed_incoming_posture = -1
	player.current_velocity = Vector3.ZERO
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 3.5 if player.player_num == 0 else -3.5))
	player.leg_ik.locomotion_body_weight = 0.0
	player.leg_ik.drive_preparation.body_alignment_active = false
	player.right_arm_node.upper_arm_length = 0.35
	player.right_arm_node.forearm_length = 0.35
	player.left_arm_node.upper_arm_length = 0.35
	player.left_arm_node.forearm_length = 0.35
	if profile > 0:
		player.global_transform = Transform3D(Basis.from_euler(Vector3(0.025, 0.43, -0.035)), Vector3(1.25, 1.08, 4.1 if player.player_num == 0 else -4.1))
		player.right_arm_node.upper_arm_length = 0.34
		player.right_arm_node.forearm_length = 0.36
		player.left_arm_node.upper_arm_length = 0.33
		player.left_arm_node.forearm_length = 0.37
	if profile == 2:
		player.leg_ik.locomotion_body_weight = 0.47
		player.leg_ik.locomotion_hip_yaw_deg = 31.0
		player.leg_ik._body_turn_reference_deg = 24.0

func _source(def: PostureDefinition, stage: int, hand: int, profile: int) -> PostureDefinition:
	var result: PostureDefinition = Path.endpoint(def, stage)
	result.paddle_hand = hand
	result.set_meta("parity_scalar", 12.75)
	result.set_meta("parity_payload", {"values": [1, "untouched", Vector3(0.2, -0.4, 0.8)], "flag": true})
	result.set_meta("support_grip_weight", 0.63)
	if profile > 0:
		result.main_grip_rotation_deg = 47.0
		result.support_grip_rotation_deg = -38.0
		result.paddle_in_hand_rotation_deg = 93.0
		result.support_grip_slide_m = 0.024
		result.support_index_closure = 0.41
		result.support_grip_style = 0.72
		result.right_hand_offset += Vector3(0.014, -0.012, 0.008)
		result.left_hand_offset += Vector3(-0.008, 0.018, -0.011)
		result.right_shoulder_rotation_deg = Vector3(7, -12, 3)
		result.left_shoulder_rotation_deg = Vector3(-4, 11, -6)
		result.left_hand_mode = 1 if profile == 1 else 4
		result.torso_yaw_deg += 9.0
		result.body_yaw_deg += 13.0
		result.body_pitch_deg += 4.0
		result.body_roll_deg -= 3.0
	if profile == 2:
		result.body_position_offset = Vector3(0.075, 0.025, -0.045)
		result.set_meta("visual_locomotion_weight", 0.66)
		result.set_meta("travel_locomotion_weight", 0.22)
		result.set_meta("travel_paddle_follow", true)
		result.set_meta("charged_load_lateral", 0.018)
	return result

func _compare_call(old, fresh, source: PostureDefinition, player, target: Vector3, delta: float, amount: float, label: String) -> Array:
	old.samples.clear(); old.sample_ids.clear()
	fresh.samples.clear(); fresh.sample_ids.clear()
	var source_before: Dictionary = Snapshot.pose(source)
	var expected: PostureDefinition = old.apply(source, player, target, delta, amount)
	var actual: PostureDefinition = fresh.apply(source, player, target, delta, amount)
	check(Snapshot.pose(actual) == Snapshot.pose(expected), label + " all authored fields/encoded fields/metadata exact")
	check(Snapshot.pose(source) == source_before, label + " source unchanged")
	check(old._tip == fresh._tip and old._torso == fresh._torso, label + " filter state exact")
	check(absf(fresh._tip.length_squared() - 1.0) < 0.00001, label + " quaternion remains normalized")
	check(old.samples == fresh.samples, label + " every trial weight and complete pose exact")
	check(old.samples.size() == fresh.samples.size(), label + " same sample count")
	if not old.samples.is_empty():
		check(old.samples.size() == 1 or old.samples.size() == 11, label + " bounded search remains exactly nine candidates")
		var unique_old: Dictionary = {}; var unique_new: Dictionary = {}
		for id in old.sample_ids: unique_old[id] = true
		for id in fresh.sample_ids: unique_new[id] = true
		check(unique_old.size() == old.samples.size(), label + " reference allocates one resource per sample")
		check(unique_new.size() == 1 and fresh.sample_ids[0] == actual.get_instance_id(), label + " one fresh invocation-local candidate")
		check(actual != source and actual != expected, label + " result ownership is independent")
		check(actual.get_meta(Current.BASE_META) == Current.untracked(source), label + " base metadata retains original identity")
		check(Path.world_transform(player, actual) == Path.world_transform(player, expected), label + " world paddle exact including floor branch")
		reference_samples += old.samples.size(); candidate_resources += 1
		if old.samples.size() == 11: limited_calls += 1
		else: unbounded_calls += 1
	else:
		early_calls += 1
		check(actual == expected, label + " early return identity exact")
	return [expected, actual]

func _parity(defs: Array[PostureDefinition]) -> void:
	check(defs.size() == 21, "all 21 authored posture definitions included")
	for player in [game.player_left, game.player_right]:
		for hand in range(2):
			for profile in range(3):
				_configure_player(player, profile)
				for def in defs:
					for stage in range(3):
						cases += 1
						var source: PostureDefinition = _source(def, stage, hand, profile)
						var old = ReferenceTrace.new(); var fresh = CurrentTrace.new()
						var label: String = "side%d hand%d profile%d pose%d stage%d" % [player.player_num, hand, profile, def.posture_id, stage]
						var target: Vector3 = player.global_position + player._get_forehand_axis() * (3.1 if stage != 1 else -3.7) + player._get_forward_axis() * (2.4 if profile != 2 else -1.2) + Vector3.UP * (0.35 if stage != 2 else 7.0)
						var first: Array = _compare_call(old, fresh, source, player, target, 1.0 / 30.0, 1.0, label + " first")
						var retained_old: Dictionary = Snapshot.pose(first[0]); var retained_new: Dictionary = Snapshot.pose(first[1])
						_compare_call(old, fresh, source, player, target + Vector3(-5, -1.2, 4), 1.0 / 120.0, 0.37, label + " next")
						check(Snapshot.pose(first[0]) == retained_old and Snapshot.pose(first[1]) == retained_new, label + " prior returned objects remain unchanged")
						# Returning a previously tracked pose must still unwrap its base.
						var tracked: PostureDefinition = first[1]
						_compare_call(old, fresh, tracked, player, target, 0.0, 0.83, label + " unwrap")
						check(Snapshot.pose(first[1]) == retained_new, label + " tracked input remains unchanged")
						_compare_call(old, fresh, source, player, target, 0.1, 0.0, label + " zero weight")
						_compare_call(old, fresh, source, player, Vector3.INF, 0.1, 1.0, label + " invalid target")
						# Same resource identity, different authored data and metadata.
						source.torso_yaw_deg -= 2.3
						source.right_foot_yaw_deg += 4.0
						source.set_meta("parity_scalar", 91.5)
						_compare_call(old, fresh, source, player, target, -0.01, 1.3, label + " source mutation")
	check(limited_calls > 0, "limited nine-candidate search was exercised")
	check(unbounded_calls > 0, "unlimited single-sample path was exercised")
	var old = ReferenceTrace.new(); var fresh = CurrentTrace.new()
	_compare_call(old, fresh, null, game.player_left, Vector3.ZERO, 0.1, 1.0, "null source")

func _statistics(values: Array) -> Dictionary:
	var sorted: Array = values.duplicate(); sorted.sort()
	var total: float = 0.0
	for value in sorted: total += float(value)
	return {"n": sorted.size(), "mean_us": total / sorted.size(), "p50_us": sorted[int(sorted.size() * 0.5)], "p95_us": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max_us": sorted.back()}

func _batch(script: Script, source: PostureDefinition, player, target: Vector3) -> Dictionary:
	var tracker = script.new()
	for tick in range(12): tracker.apply(source, player, target, 1.0 / 60.0)
	var checksum: float = 0.0
	var start: int = Time.get_ticks_usec()
	for tick in range(bench_samples):
		var pose: PostureDefinition = tracker.apply(source, player, target + player._get_forehand_axis() * (0.2 if tick % 2 == 0 else -0.2), 1.0 / 60.0)
		checksum += pose.paddle_y_offset + pose.torso_yaw_deg
	return {"us_per_call": float(Time.get_ticks_usec() - start) / bench_samples, "checksum": checksum}

func _benchmark(defs: Array[PostureDefinition]) -> void:
	var player = game.player_left
	var rows: Array = []
	for profile in range(3):
		_configure_player(player, profile)
		for wanted_id in [20, 2]:
			var source: PostureDefinition
			for def in defs:
				if def.posture_id == wanted_id: source = _source(def, 1, 0, profile)
			var target: Vector3 = player.global_position + player._get_forehand_axis() * 4.0 + player._get_forward_axis() * 2.0 + Vector3.UP * 0.3
			var before: Array = []; var after: Array = []
			for round_index in range(bench_rounds):
				# Alternate serial order to reduce warm-up/order bias.
				var a: Dictionary; var b: Dictionary
				if round_index % 2 == 0:
					a = _batch(Reference, source, player, target); b = _batch(Current, source, player, target)
				else:
					b = _batch(Current, source, player, target); a = _batch(Reference, source, player, target)
				check(a.checksum == b.checksum, "microbenchmark exact output checksum")
				before.append(a.us_per_call); after.append(b.us_per_call)
			rows.append({"pose": wanted_id, "profile": profile, "baseline": _statistics(before), "candidate": _statistics(after), "samples_per_batch": bench_samples})
	report["microbenchmark"] = rows

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--bench": benchmark = true
		if arg == "--bench-only": benchmark = true; benchmark_only = true
		if arg.begins_with("--bench-samples="): bench_samples = maxi(1, int(arg.trim_prefix("--bench-samples=")))
		if arg.begins_with("--bench-rounds="): bench_rounds = maxi(1, int(arg.trim_prefix("--bench-rounds=")))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	check(FileAccess.get_sha256("res://scripts/tests/fixtures/ready_ball_tracking_code27_reference.gd") == EXPECTED_REFERENCE_SHA256, "frozen unmodified code27 reference hash")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.between_point_controller.cancel(); game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	await process_frame
	var defs: Array[PostureDefinition] = _definitions()
	for player in [game.player_left, game.player_right]:
		if player.right_arm_node.articulated_hand == null: player.arm_ik.update_arm_ik(0.0, defs.back())
	if not benchmark_only: _parity(defs)
	if benchmark: _benchmark(defs)
	report.merge({"checks": checks, "cases": cases, "failures": failures, "limited_calls": limited_calls, "unlimited_calls": unbounded_calls, "early_calls": early_calls, "reference_candidate_resources": reference_samples, "optimized_candidate_resources": candidate_resources, "saved_candidate_resources": reference_samples - candidate_resources, "parity_ran": not benchmark_only, "benchmark_ran": benchmark})
	if output != "":
		var file = FileAccess.open(output, FileAccess.WRITE)
		if file == null: push_error("Cannot write parity report: " + output); quit(2); return
		file.store_string(JSON.stringify(report, "\t")); file.close()
	print("READY_TRACKING_ALLOCATION_PARITY ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
