extends SceneTree
## Exact baseline-reference parity; timing is opt-in and uses untraced classes.
const Current = preload("res://scripts/held_hit_motion.gd")
const Reference = preload("res://scripts/tests/fixtures/held_motion_pass11_reference.gd")
const CurrentTrace = preload("res://scripts/tests/fixtures/held_motion_pass11_candidate_trace.gd")
const ReferenceTrace = preload("res://scripts/tests/fixtures/held_motion_pass11_reference_trace.gd")
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const EXPECTED_REFERENCE_SHA256 = "808899f9e2c4cd5883480a9f487dd763e8b0392fa27a7554f2e0cd8b0a2e010b"
var game
var checks: int = 0
var contexts: int = 0
var calls: int = 0
var constrained: int = 0
var unconstrained: int = 0
var original_resources: int = 0
var optimized_resources: int = 0
var failures: Array[String] = []
var output: String = ""
var benchmark: bool = false
var benchmark_only: bool = false
var bench_samples: int = 120
var report: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 80: failures.append(label)

func _definitions() -> Array[PostureDefinition]:
	var result: Array[PostureDefinition] = []
	var files: PackedStringArray = DirAccess.get_files_at("res://data/postures"); files.sort()
	for name in files:
		if name.ends_with(".tres"): result.append(load("res://data/postures/" + name).duplicate(true))
	return result

func _configure(player, translated: bool) -> void:
	player.posture.editor_preview_mode = false
	player.posture._committed_incoming_posture = -1
	player.hitting.serving_visual_active = false
	player.hitting.charge_visual_active = false
	player.hitting.is_in_follow_through = false
	player.current_velocity = Vector3.ZERO
	player.leg_ik.locomotion_body_weight = 0.0
	player.leg_ik.drive_preparation.body_alignment_active = false
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 3.8 if player.player_num == 0 else -3.8))
	if translated: player.global_transform = Transform3D(Basis.from_euler(Vector3(.03, .27, -.02)), Vector3(.8, 1.07, 4.3 if player.player_num == 0 else -4.3))

func _cache(helper) -> Dictionary:
	var result: Dictionary = {}
	for key in helper._curves:
		var data: Dictionary = helper._curves[key]
		result[key] = {"fingerprint": data.fingerprint, "source": Snapshot.pose(data.source), "normal": Snapshot.pose(data.normal), "extensions": data.extensions.duplicate(true), "extension_order": data.extensions.keys(), "curve_report": data.curve.report.duplicate(true)}
	return result

func _compare(old, fresh, source: PostureDefinition, windup: PostureDefinition, amount: float, player, sampler: Callable, key: String, label: String) -> Array:
	calls += 1
	old.samples.clear(); old.sample_ids.clear(); old.fits.clear()
	fresh.samples.clear(); fresh.sample_ids.clear(); fresh.fits.clear()
	var before: Dictionary = Snapshot.pose(source)
	var before_windup: Dictionary = Snapshot.pose(windup)
	var expected: PostureDefinition = old.extend_windup(source, windup, amount, player, sampler, key)
	var actual: PostureDefinition = fresh.extend_windup(source, windup, amount, player, sampler, key)
	check(Snapshot.pose(actual) == Snapshot.pose(expected), label + " all raw/encoded fields and metadata exact")
	check(old.samples == fresh.samples, label + " every candidate and exact bisection amount unchanged")
	check(old.fits == fresh.fits, label + " every limit and constraint outcome unchanged")
	check(old.report == fresh.report, label + " applied weight/limit/report exact")
	check(_cache(old) == _cache(fresh), label + " source fingerprint, scalar/Basis amount cache and FIFO order exact")
	check(Snapshot.pose(source) == before and Snapshot.pose(windup) == before_windup, label + " authored source and live windup unchanged")
	check(actual != windup and actual != source and actual != expected, label + " independently owned return resource")
	check(old.samples.size() == 1 or old.samples.size() == 12, label + " initial plus ten constrained trials plus final unchanged")
	var old_ids: Dictionary = {}; var new_ids: Dictionary = {}
	for id in old.sample_ids: old_ids[id] = true
	for id in fresh.sample_ids: new_ids[id] = true
	check(old_ids.size() == old.samples.size(), label + " frozen baseline allocates each candidate")
	check(new_ids.size() == 1 and fresh.sample_ids[0] == actual.get_instance_id(), label + " one invocation-local allocation")
	check(Orientation.canonical_basis(actual) == Orientation.canonical_basis(expected), label + " final canonical orientation exact")
	if player != null: check(Path.world_transform(player, actual) == Path.world_transform(player, expected), label + " world/floor transform exact")
	if old.samples.size() == 12: constrained += 1
	else: unconstrained += 1
	original_resources += old_ids.size(); optimized_resources += new_ids.size()
	return [expected, actual]

func _direct_helper(old, fresh, source: PostureDefinition, windup: PostureDefinition, sampler: Callable, key: String, label: String) -> void:
	var old_data: Dictionary = old._curve(source, sampler, key)
	var new_data: Dictionary = fresh._curve(source, sampler, key)
	var previous: PostureDefinition
	var previous_snapshot: Dictionary = {}
	for amount in [0.0, .31, 1.0]:
		var a: PostureDefinition = old._candidate(source, windup, old_data, amount)
		var b: PostureDefinition = fresh._candidate(source, windup, new_data, amount)
		check(Snapshot.pose(a) == Snapshot.pose(b), label + " direct helper output exact")
		check(b != windup and b != previous, label + " direct helper still creates fresh deep-copy result")
		if previous != null: check(Snapshot.pose(previous) == previous_snapshot, label + " direct helper preserves previous result")
		previous = b; previous_snapshot = Snapshot.pose(b)

func _context(source: PostureDefinition, sampler: Callable, key: String, hand: int, profile: int) -> void:
	contexts += 1
	if contexts % 20 == 0: print("HELD_PASS11 context ", contexts, "/112")
	source = source.duplicate(true)
	source.paddle_hand = hand
	if profile == 1:
		source.main_grip_rotation_deg = 37.0
		source.support_grip_rotation_deg = -23.0
		source.paddle_in_hand_rotation_deg = 81.0
		source.support_grip_slide_m = .023
		source.body_position_offset = Vector3(.035, .015, -.025)
		source.torso_yaw_deg += 7.0
		source.right_hand_offset += Vector3(.01, -.015, .006)
	var windup: PostureDefinition = sampler.call(source, 0.0)
	windup.set_meta("parity_scalar", 8.125)
	windup.set_meta("parity_payload", {"array": [1, 2, Vector3(.1, .2, .3)], "label": "held"})
	if profile == 1:
		# Deliberately constrained live contact-relative windup; this must not
		# contaminate the canonical curve cache or escape the existing cap.
		windup.paddle_forehand_mul += .45
		windup.paddle_y_offset -= .22
	var old = ReferenceTrace.new(); var fresh = CurrentTrace.new()
	old.prewarm(source, sampler, key); fresh.prewarm(source, sampler, key)
	check(_cache(old) == _cache(fresh), key + " prewarm exact")
	_direct_helper(old, fresh, source, windup, sampler, key, key)
	for player in [game.player_left, game.player_right]:
		_configure(player, profile == 1)
		var label: String = "%s side%d hand%d profile%d" % [key, player.player_num, hand, profile]
		var first: Array = _compare(old, fresh, source, windup, 1.0, player, sampler, key, label + " first")
		var before_old: Dictionary = Snapshot.pose(first[0]); var before_new: Dictionary = Snapshot.pose(first[1])
		_compare(old, fresh, source, windup, .41, player, sampler, key, label + " next amount")
		check(Snapshot.pose(first[0]) == before_old and Snapshot.pose(first[1]) == before_new, label + " prior returned resources remain isolated")
		player.global_position += Vector3(.6, .04, -.35)
		player.global_basis = Basis.from_euler(Vector3(.015, -.31, .02))
		_compare(old, fresh, source, windup, .78, player, sampler, key, label + " moving root")
		windup.paddle_forward_mul += .008
		windup.paddle_roll_base_deg += 3.0
		windup.set_meta("parity_scalar", 19.75)
		_compare(old, fresh, source, windup, .78, player, sampler, key, label + " same amount edited windup")
	_compare(old, fresh, source, windup, .0, null, sampler, key, key + " null player zero amount")
	var old_fingerprint: String = old._curves[key].fingerprint
	source.paddle_y_offset += .023
	source.main_grip_rotation_deg -= 5.0
	old.prewarm(source, sampler, key, true); fresh.prewarm(source, sampler, key, true)
	check(old._curves[key].fingerprint != old_fingerprint and fresh._curves[key].fingerprint == old._curves[key].fingerprint, key + " source edits invalidate fingerprint exactly")
	check(old._curves[key].extensions.is_empty() and fresh._curves[key].extensions.is_empty(), key + " refresh clears amount cache")
	windup = sampler.call(source, 0.0)
	_compare(old, fresh, source, windup, 1.0, game.player_left, sampler, key, key + " refreshed source")
	old.reset(false); fresh.reset(false)
	check(old.report.is_empty() and fresh.report.is_empty() and _cache(old) == _cache(fresh), key + " report-only reset preserves curves")
	old.reset(); fresh.reset()
	check(old._curves.is_empty() and fresh._curves.is_empty(), key + " full reset clears curves")

func _eviction(source: PostureDefinition) -> void:
	var sampler: Callable = Path.sample
	var old = ReferenceTrace.new(); var fresh = CurrentTrace.new()
	var windup: PostureDefinition = sampler.call(source, 0.0)
	for index in range(Current.EXTENSION_CACHE_LIMIT + 5):
		_compare(old, fresh, source, windup, float(index) / 73.0, null, sampler, "eviction", "eviction%d" % index)
	check(old._curves.eviction.extensions.size() == Current.EXTENSION_CACHE_LIMIT and fresh._curves.eviction.extensions.size() == Current.EXTENSION_CACHE_LIMIT, "bounded exact cache still evicts to 64 entries")

func _benchmark(defs: Array[PostureDefinition]) -> void:
	var rows: Array = []
	var player = game.player_left; _configure(player, false)
	for id in [0, 2, 10]:
		var source: PostureDefinition
		for def in defs:
			if def.posture_id == id: source = def
		var windup: PostureDefinition = Path.sample(source, 0.0)
		windup.paddle_forehand_mul += .35
		var old = Reference.new(); var fresh = Current.new()
		old.prewarm(source, Path.sample, "bench"); fresh.prewarm(source, Path.sample, "bench")
		for index in range(12):
			old.extend_windup(source, windup, 1.0, player, Path.sample, "bench")
			fresh.extend_windup(source, windup, 1.0, player, Path.sample, "bench")
		var before: Array = []; var after: Array = []
		for round_index in range(5):
			var sums: Array = []
			for entry in ([old, fresh] if round_index % 2 == 0 else [fresh, old]):
				var checksum: float = 0.0; var start: int = Time.get_ticks_usec()
				for index in range(bench_samples):
					var pose: PostureDefinition = entry.extend_windup(source, windup, 1.0, player, Path.sample, "bench")
					checksum += pose.paddle_y_offset + pose.paddle_forehand_mul
				var per_call: float = float(Time.get_ticks_usec() - start) / bench_samples
				if entry == old: before.append(per_call)
				else: after.append(per_call)
				sums.append(checksum)
			check(sums[0] == sums[1], "microbenchmark exact checksum")
		rows.append({"pose": id, "reference_us_per_call": before, "candidate_us_per_call": after, "samples_per_batch": bench_samples})
	report["microbenchmark"] = rows

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--bench": benchmark = true
		if arg == "--bench-only": benchmark = true; benchmark_only = true
		if arg.begins_with("--bench-samples="): bench_samples = maxi(1, int(arg.trim_prefix("--bench-samples=")))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	check(FileAccess.get_sha256("res://scripts/tests/fixtures/held_motion_pass11_reference.gd") == EXPECTED_REFERENCE_SHA256, "frozen held-motion reference exact")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	print("HELD_PASS11 scene instantiated")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.between_point_controller.cancel(); game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	await process_frame
	var defs: Array[PostureDefinition] = _definitions()
	if not benchmark_only:
		check(defs.size() == 21, "all 21 stroke/static definitions covered")
		for def in defs:
			for hand in range(2):
				for profile in range(2): _context(def, Path.sample, "stroke_%d" % def.posture_id, hand, profile)
		for style in range(7):
			var source: PostureDefinition = Serve.packaged_default(style)
			for hand in range(2):
				for profile in range(2): _context(source, Serve.sample, "serve_%d" % style, hand, profile)
		_eviction(defs[0])
		check(constrained > 0 and unconstrained > 0, "both constrained and unconstrained paths exercised")
		check(original_resources > optimized_resources, "actual candidate Resource allocation reduction observed")
	if benchmark:
		print("HELD_PASS11 starting untraced serial benchmark")
		_benchmark(defs)
	report.merge({"checks": checks, "contexts": contexts, "calls": calls, "constrained_calls": constrained, "unconstrained_calls": unconstrained, "reference_resources": original_resources, "candidate_resources": optimized_resources, "saved_resources": original_resources - optimized_resources, "failures": failures, "benchmark_ran": benchmark, "parity_ran": not benchmark_only})
	if output != "":
		var file = FileAccess.open(output, FileAccess.WRITE)
		if file == null: push_error("Cannot open report " + output); quit(2); return
		file.store_string(JSON.stringify(report, "\t")); file.close()
	print("HELD_CANDIDATE_ALLOCATION_PARITY ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
