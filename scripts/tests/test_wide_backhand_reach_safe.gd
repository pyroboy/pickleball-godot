extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const Approved = preload("res://scripts/approved_wide_backhand_import.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Variants = preload("res://scripts/stroke_windup_variants.gd")
const Held = preload("res://scripts/held_hit_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Profile = preload("res://scripts/wide_backhand_reach_profile.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
var failures: Array[String] = []
var checks := 0
var rows: Array = []
var output := ""
var maxima := {"body_shift_m": 0.0, "paddle_origin_delta_m": 0.0, "paddle_basis_delta": 0.0,
	"grip_error_m": 0.0, "upper_ratio": 0.0, "forearm_ratio": 0.0, "visual_stretch": 0.0,
	"baseline_visual_stretch": 0.0, "leg_ratio": 0.0, "feet_target_delta_m": 0.0,
	"actual_ankle_delta_m": 0.0, "consecutive_body_delta_m": 0.0, "iterations": 0}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		if failures.size() < 30: push_error(message)
		failures.append(message)
func vector(v: Vector3) -> Array: return [v.x, v.y, v.z]
func transform_difference(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z)))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Store.set_test_path("user://pose_store_tests/wide_backhand_safe_" + str(OS.get_process_id()) + "/poses.json")
	GripStore.set_test_path("user://pose_store_tests/wide_backhand_safe_" + str(OS.get_process_id()) + "/grips.json")
	var provenance := "res://docs/pose-imports/wide-backhand-2026-10-02.json"
	var original: String = Approved.JSON_TEXT
	check(original.sha256_text() == Approved.SOURCE_SHA256, "embedded original import hash unchanged")
	if FileAccess.file_exists(provenance): check(FileAccess.get_file_as_string(provenance) == original, "retained source matches embedded original import")
	else: check(get_script().resource_path.ends_with(".gdc"), "source JSON is required outside compiled APK")
	var def: PostureDefinition = Store._export_packaged_default(11, false)
	var encoded_before: Dictionary = Store._encode_fields(def)
	var preview = Preview.new(); root.add_child(preview)
	var reference = Preview.new(); root.add_child(reference)
	for tick in range(3): await process_frame
	# ID is the only reference difference: explicit supplied fields and two-hand
	# mode are retained. ID10 bypasses this ID11-specific presentation profile.
	for court in range(2):
		preview.player.player_num = court; reference.player.player_num = court
		var previous := Vector3.ZERO
		for index in range(1025):
			var t := index / 1024.0
			var pose: PostureDefinition = Path.sample(def, t)
			var raw := pose.duplicate(true); raw.posture_id = 10
			reference.show_pose(raw)
			preview.show_pose(pose)
			var result := measure(preview.player, reference.player, pose, court, t, "authored")
			var position: Vector3 = preview.player.body_pivot.global_position
			if index > 0: maxima.consecutive_body_delta_m = maxf(maxima.consecutive_body_delta_m, position.distance_to(previous))
			previous = position
			if index in [0, 512]:
				check(result.body_shift_m <= .000001, "Wind-up/Contact body unchanged")
				check(preview.player.body_pivot.global_transform.is_equal_approx(reference.player.body_pivot.global_transform), "Wind-up/Contact full body transform unchanged")
			if index % 64 == 0:
				var repeat: Transform3D = preview.player.body_pivot.global_transform
				var paddle: Transform3D = preview.player.paddle_node.global_transform
				preview.player.leg_ik._solve_legs(0.0, pose, true)
				preview.player.arm_ik.update_arm_ik(0.0, pose)
				check(preview.player.body_pivot.global_transform.is_equal_approx(repeat), "repeated solve never accumulates body offset")
				check(preview.player.paddle_node.global_transform.is_equal_approx(paddle), "repeated solve preserves paddle")
		for mode in [Variants.STRONG, Variants.WEAK]:
			var variant = Variants.new(); variant.configure(def, mode, Callable(), preview.player)
			for index in range(513):
				var t := index / 512.0
				var pose: PostureDefinition = variant.sample(def, t)
				var raw := pose.duplicate(true); raw.posture_id = 10
				reference.show_pose(raw); preview.show_pose(pose)
				measure(preview.player, reference.player, pose, court, t, "strong" if mode == Variants.STRONG else "weak")
				if index == 256: check(preview.player.body_pivot.global_transform.is_equal_approx(reference.player.body_pivot.global_transform), "Strong/Weak Contact unchanged")
		var held = Held.new()
		var ready: PostureDefinition = Store._export_packaged_default(20, false)
		for index in range(257):
			var seconds := index / 256.0 * Held.STRONG_SECONDS
			var pose: PostureDefinition = held.sample(def, ready, seconds, preview.player)
			var raw := pose.duplicate(true); raw.posture_id = 10
			reference.show_pose(raw); preview.show_pose(pose)
			measure(preview.player, reference.player, pose, court, seconds, "held_generation")
		# Runtime path uses a real fixed Wind-up plant through the entire swing.
		# Both rigs use those same actual plants, ordinary floor fit and leg IK.
		var windup: PostureDefinition = Path.sample(def, 0.0)
		preview.show_pose(windup)
		var planted: Array = [preview.player.leg_ik.right_foot_smooth, preview.player.leg_ik.left_foot_smooth]
		for index in range(257):
			var t := index / 256.0
			var pose: PostureDefinition = Path.sample(def, t)
			var raw := pose.duplicate(true); raw.posture_id = 10
			for pair in [[reference.player, raw], [preview.player, pose]]:
				var player = pair[0]; var value: PostureDefinition = pair[1]
				player.posture.force_posture_update(value, false)
				player.leg_ik.right_foot_smooth = planted[0]
				player.leg_ik.left_foot_smooth = planted[1]
				player.leg_ik._solve_legs(0.0, value)
				player.arm_ik.update_arm_ik(0.0, value)
			measure(preview.player, reference.player, pose, court, t, "planted_runtime")
			check(preview.player.leg_ik.right_foot_smooth == planted[0] and preview.player.leg_ik.left_foot_smooth == planted[1], "runtime feet remain exactly planted")
	# Random/reverse scrubbing must be deterministic, including affected samples.
	for t in [1.0, .91, .74, .5, .0, .91, .1, .74, 1.0]:
		var pose: PostureDefinition = Path.sample(def, t)
		preview.show_pose(pose)
		var transform: Transform3D = preview.player.body_pivot.global_transform
		preview.show_pose(Path.sample(def, .3))
		preview.show_pose(pose)
		check(preview.player.body_pivot.global_transform.is_equal_approx(transform), "random scrubbing is deterministic")
	check(Store._encode_fields(def) == encoded_before, "all authored body/paddle fields unchanged")
	if FileAccess.file_exists(provenance): check(FileAccess.get_file_as_string(provenance) == original, "source bytes unchanged after sweeps")
	else: check(Approved.JSON_TEXT.sha256_text() == Approved.SOURCE_SHA256, "embedded source bytes unchanged after sweeps")
	check(maxima.baseline_visual_stretch > 1.05, "reference reproduces original reach defect")
	check(maxima.body_shift_m < .041, "minimal imported correction remains below 4.1 cm")
	check(maxima.consecutive_body_delta_m < .003, "dense playback body position has no correction jumps")
	var outside: PostureDefinition = def.duplicate(true); outside.posture_id = 10
	check(not Profile.enabled(outside), "other strokes are unaffected")
	outside = def.duplicate(true); outside.left_hand_mode = 4
	check(not Profile.enabled(outside), "free-support recovery is unaffected")
	var impossible := Profile.minimum_translation([Vector3(-2,0,0),Vector3(2,0,0)],[.7,.7])
	check(not impossible.feasible, "infeasible reach is reported instead of silently bypassed")
	print("[WIDE BACKHAND REACH SAFE] %d checks, %d failures" % [checks, failures.size()])
	print(JSON.stringify(maxima))
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"maxima":maxima,"rows":rows}, "\t",true,true)); file.close()
	quit(0 if failures.is_empty() else 1)

func measure(player, reference, pose, court: int, t: float, mode: String) -> Dictionary:
	var report: Dictionary = player.body_pivot.get_meta("wide_backhand_reach_report", {})
	check(not report.is_empty() and bool(report.get("feasible", false)), "reach correction feasible %s/%d/%.6f" % [mode,court,t])
	var body_shift: float = player.body_pivot.global_position.distance_to(reference.body_pivot.global_position)
	var paddle_delta: float = player.paddle_node.global_position.distance_to(reference.paddle_node.global_position)
	var basis_delta: float = transform_difference(player.paddle_node.global_transform, reference.paddle_node.global_transform)
	check(paddle_delta <= .000002 and basis_delta <= .000002, "entire world paddle transform unchanged")
	maxima.body_shift_m = maxf(maxima.body_shift_m, body_shift)
	maxima.paddle_origin_delta_m = maxf(maxima.paddle_origin_delta_m, paddle_delta)
	maxima.paddle_basis_delta = maxf(maxima.paddle_basis_delta, basis_delta)
	maxima.iterations = maxi(maxima.iterations, int(report.get("iterations", 0)))
	var row := {"court":court,"t":t,"mode":mode,"body_shift_m":body_shift,
		"delta":vector(player.body_pivot.global_position-reference.body_pivot.global_position),"arms":[]}
	for side in range(2):
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var old_arm = reference.right_arm_node if side == 0 else reference.left_arm_node
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
		var upper: float = shoulder.distance_to(elbow) / arm.upper_arm_length
		var fore: float = elbow.distance_to(wrist) / arm.forearm_length
		var anchor: Vector3 = player.paddle_node.to_global(D.MAIN_GRIP_OFFSET + pose.right_hand_offset if side == 0 else D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m)
		var error: float = arm.hand_mesh.global_position.distance_to(anchor)
		check(upper <= 1.000003 and fore <= 1.000003 and arm.visual_stretch <= 1.000003, "actual upper and forearm remain nominal")
		check(error <= .000002 and wrist.distance_to(arm.anatomical_wrist_world) <= .000002, "both grips and wrist sockets seated")
		maxima.upper_ratio = maxf(maxima.upper_ratio, upper); maxima.forearm_ratio = maxf(maxima.forearm_ratio, fore)
		maxima.grip_error_m = maxf(maxima.grip_error_m, error)
		maxima.visual_stretch = maxf(maxima.visual_stretch, arm.visual_stretch)
		maxima.baseline_visual_stretch = maxf(maxima.baseline_visual_stretch, old_arm.visual_stretch)
		row.arms.append({"upper_ratio":upper,"fore_ratio":fore,"visual_stretch":arm.visual_stretch,"grip_error_m":error})
		var leg = player.right_leg_node if side == 0 else player.left_leg_node
		var old_leg = reference.right_leg_node if side == 0 else reference.left_leg_node
		var target: Vector3 = player.leg_ik.right_foot_smooth if side == 0 else player.leg_ik.left_foot_smooth
		var old_target: Vector3 = reference.leg_ik.right_foot_smooth if side == 0 else reference.leg_ik.left_foot_smooth
		var target_delta: float = target.distance_to(old_target)
		var leg_ratio: float = maxf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)/leg.thigh_length,leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position)/leg.shin_length)
		check(target_delta <= .000001, "authored/live planted-foot target unchanged")
		check(leg_ratio <= 1.000003, "leg links remain nominal")
		var bounds: AABB = leg.foot_mesh.mesh.get_aabb()
		for corner in range(8): check((leg.foot_mesh.global_transform * bounds.get_endpoint(corner)).y >= PickleballConstants.FLOOR_Y-.000002, "sole remains above court")
		maxima.leg_ratio = maxf(maxima.leg_ratio,leg_ratio)
		maxima.feet_target_delta_m = maxf(maxima.feet_target_delta_m,target_delta)
		maxima.actual_ankle_delta_m = maxf(maxima.actual_ankle_delta_m,leg.foot_pivot.global_position.distance_to(old_leg.foot_pivot.global_position))
	rows.append(row)
	return row
