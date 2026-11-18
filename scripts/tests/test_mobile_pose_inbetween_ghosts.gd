extends SceneTree
## Regression: in-between bodies reuse the one solved motion pass, including skin poses.
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const ViewSettings = preload("res://scripts/mobile_pose_view_settings.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
const Variants = preload("res://scripts/ui/mobile_pose_windup_variants.gd")
var test_id := "%d_%d" % [OS.get_process_id(), int(Time.get_unix_time_from_system() * 1000000.0)]
var checks := 0
var failures: Array[String] = []
var sampled := 0
var max_transform_drift := 0.0
var max_basis_drift := 0.0
var rigid_readback_checks := 0
var performance: Dictionary = {}
var output := "/workspace/scratch/6b6e64f75bd2/verification/inbetween-ghosts"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count: int = 2) -> void:
	for i in range(count): await process_frame
func counted_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	sampled += 1
	return Path.sample(definition, progress)
func expected_indices(count: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	for gap in range(2):
		for slot in range(count): values.append(gap * 32 + roundi(float(slot + 1) * 32.0 / (count + 1)))
	return values
func equal_transform(a: Transform3D, b: Transform3D, label: String, basis_tolerance: float = .00002) -> void:
	max_transform_drift = maxf(max_transform_drift, a.origin.distance_to(b.origin))
	var basis_drift: float = maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z)))
	max_basis_drift = maxf(max_basis_drift, basis_drift)
	check(a.is_finite() and a.origin.distance_to(b.origin) < .00002 and basis_drift < basis_tolerance, label + " (origin %.9f, basis %.9f)" % [a.origin.distance_to(b.origin), basis_drift])
func source_skeleton(source: MeshInstance3D) -> Skeleton3D:
	return source.get_node_or_null(source.skeleton) as Skeleton3D if source.skin != null else null
func verify_cache(preview, definition: PostureDefinition, sampler: Callable, label: String) -> void:
	var ghosts = preview._inbetween_root
	check(ghosts != null and ghosts.samples.size() == 65, label + ": cached all 65 solved body snapshots")
	if ghosts == null or ghosts.samples.size() != 65: return
	check(not ghosts.sources.is_empty(), label + ": real body sources exist")
	var has_skin := false
	var has_paddle := false
	var has_arms := false
	var has_legs := false
	for source in ghosts.sources:
		var path: String = str(preview.player.get_path_to(source)).to_lower()
		has_paddle = has_paddle or path.contains("paddle")
		has_arms = has_arms or path.contains("arm") or path.contains("elbow") or path.contains("hand")
		has_legs = has_legs or path.contains("leg") or path.contains("knee") or path.contains("foot")
		has_skin = has_skin or source_skeleton(source) != null
	check(has_paddle and has_arms and has_legs and has_skin, label + ": body, paddle, arms, legs and articulated skin are included")
	for index in range(65):
		preview.show_pose(sampler.call(definition, float(index) / 64.0))
		check(ghosts.samples[index].size() == ghosts.sources.size(), label + ": every source sampled at %d" % index)
		for mesh_index in range(ghosts.sources.size()):
			var source: MeshInstance3D = ghosts.sources[mesh_index]
			var sample: Dictionary = ghosts.samples[index][mesh_index]
			equal_transform(sample.transform, source.global_transform, label + ": cached actual mesh %d sample %d" % [mesh_index, index])
			check(sample.visible == source.is_visible_in_tree(), label + ": cached source visibility")
			var skeleton := source_skeleton(source)
			if skeleton != null:
				check(sample.bones.size() == skeleton.get_bone_count(), label + ": all skin bones captured")
				for bone in range(skeleton.get_bone_count()):
					equal_transform(sample.bones[bone], skeleton.get_bone_pose(bone), label + ": actual skin bone %d at %d" % [bone, index])
				equal_transform(sample.skeleton_transform, skeleton.global_transform, label + ": actual skeleton frame")
func verify_display(preview, definition: PostureDefinition, sampler: Callable, label: String) -> void:
	var ghosts = preview._inbetween_root
	check(ghosts.is_visible_in_tree(), label + ": in-between geometry visible")
	var indices: PackedInt32Array = preview.inbetween_sample_indices
	for slot in range(indices.size()):
		preview.show_pose(sampler.call(definition, float(indices[slot]) / 64.0))
		for source_index in range(ghosts.batches.size()):
			var entry: Dictionary = ghosts.batches[source_index]
			var source: MeshInstance3D = entry.source
			if entry.has("rigid"):
				var per_gap: int = indices.size() / 2
				var gap: int = slot / per_gap
				var batch: MultiMeshInstance3D = entry.rigid[gap]
				check(batch.multimesh.mesh == source.mesh, label + ": rigid mesh shared with actual rig")
				check(batch.multimesh.instance_count <= 6, label + ": rigid instances bounded to six per gap")
				check(batch.get_meta("source_path") == preview.player.get_path_to(source), label + ": rigid source mapping preserved")
				var visible_count := 0
				var drawn_index := 0
				for previous in range(gap * per_gap, (gap + 1) * per_gap):
					if ghosts.samples[indices[previous]][source_index].visible:
						visible_count += 1
						if previous < slot: drawn_index += 1
				check(batch.multimesh.visible_instance_count == visible_count, label + ": rigid source visibility respected")
				if source.is_visible_in_tree() and DisplayServer.get_name() != "headless":
					rigid_readback_checks += 1
					equal_transform(batch.global_transform * batch.multimesh.get_instance_transform(drawn_index), source.global_transform, label + ": rigid ghost matches actual solved mesh " + str(source.name))
			else:
				check(entry.copies.size() <= 12, label + ": skinned copies bounded to 12")
				var copy: MeshInstance3D = entry.copies[slot].mesh
				var copy_skeleton: Skeleton3D = entry.copies[slot].skeleton
				check(copy.get_meta("source_path") == preview.player.get_path_to(source), label + ": skin source mapping preserved")
				var skeleton := source_skeleton(source)
				check(copy.mesh == source.mesh and copy.skin == source.skin, label + ": original mesh and skin retained")
				check(copy.is_visible_in_tree() == source.is_visible_in_tree(), label + ": skinned source visibility respected")
				equal_transform(copy.global_transform, source.global_transform, label + ": skinned ghost matches actual solved mesh")
				# Skeleton3D decomposes and reconstructs stored TRS. The wrist cuff
				# round-trip differs by < 1e-4 in basis; position tolerance stays 20 um.
				for bone in range(skeleton.get_bone_count()):
					equal_transform(copy_skeleton.get_bone_pose(bone), skeleton.get_bone_pose(bone), label + ": skinned ghost follows actual bones " + str(source.name) + "/" + skeleton.get_bone_name(bone), .0001)
				equal_transform(copy_skeleton.global_transform, skeleton.global_transform, label + ": ghost skeleton follows actual frame")
	for descendant in ghosts.find_children("*", "", true, false):
		check(not descendant is CollisionObject3D and not descendant is CollisionShape3D and not descendant is CharacterBody3D,
			label + ": no player or collision replicas")
		check(descendant.get_script() == null, label + ": child geometry carries no gameplay scripts")
func file_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func settings_checks() -> void:
	var path := "user://pose_store_tests/inbetween_%s/view.json" % test_id
	check(ViewSettings.set_test_path(path) == OK, "view settings use isolated test path")
	check(ViewSettings.DEFAULT_INBETWEEN_COUNT == 2 and ViewSettings.MAX_INBETWEEN_COUNT == 6, "bounded user default is two per gap")
	check(ViewSettings.load_inbetween_count() == 2, "new settings default to two per gap")
	for count in [0, 1, 6, 2]:
		check(ViewSettings.save_inbetween_count(count) == OK, "persist valid count %d" % count)
		check(ViewSettings.set_test_path(path) == OK, "reset settings in-memory state")
		check(ViewSettings.load_inbetween_count() == count, "count survives settings reload %d" % count)
	for rejected in ["user://production.json", "user://pose_store_tests/../production.json", "res://view.json", "user://pose_store_tests/view.txt"]:
		check(ViewSettings.set_test_path(rejected) == ERR_INVALID_PARAMETER, "unsafe test path rejected")
	check(ViewSettings.load_inbetween_count() == 2, "rejected override preserves preceding settings path")
	for payload in ["broken json", "{}", '{"version":2,"inbetween_per_gap":4}', '{"version":1,"inbetween_per_gap":"4"}', '{"version":1,"inbetween_per_gap":1.5}', " ".repeat(4097)]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(payload); file.close()
		check(ViewSettings.load_inbetween_count() == 2, "invalid or oversized setting falls back safely")
	check(ViewSettings.save_inbetween_count(2) == OK, "restore valid isolated view setting")

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	var isolate := "user://pose_store_tests/inbetween_%s/" % test_id
	check(Store.set_test_path(isolate + "poses.json") == OK, "isolated pose state")
	check(ServeStore.set_test_path(isolate + "serves.json") == OK, "isolated serve state")
	check(GripStore.set_test_path(isolate + "grips.json") == OK, "isolated grip state")
	settings_checks()
	var preview = Preview.new(); preview.size = Vector2(640, 480); root.add_child(preview)
	await frames()
	check(preview.inbetween_count == 0, "direct preview preserves opt-in zero default")
	var definition: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	var original: String = Store.export_pose_json(definition)
	var displayed: PostureDefinition = Path.sample(definition, .27)
	preview.show_pose(displayed)
	var displayed_transform: Transform3D = preview.player.paddle_node.global_transform
	preview.set_motion_sampler(counted_sample)
	var build_start := Time.get_ticks_usec()
	preview.set_motion(definition)
	performance.initial_65_sample_build_usec = Time.get_ticks_usec() - build_start
	check(sampled == 65, "body ghosts reuse exactly one 65-sample solve pass")
	check(preview.pose == displayed, "cache build restores displayed resource")
	equal_transform(preview.player.paddle_node.global_transform, displayed_transform, "cache build restores displayed paddle")
	check(preview.inbetween_sample_indices.is_empty(), "zero count has no selected samples")
	var rebuilds: int = preview.motion_rebuild_count
	var state: PackedByteArray = var_to_bytes(preview._inbetween_root.samples)
	for count in [0, 1, 6, 2, 0, 6]:
		preview.set_inbetween_count(count)
		check(preview.inbetween_count == count and preview.inbetween_sample_indices == expected_indices(count), "even interior samples, excluding all three authored keys, count %d" % count)
		check(sampled == 65 and preview.motion_rebuild_count == rebuilds, "slider count never resamples or rebuilds")
		check(var_to_bytes(preview._inbetween_root.samples) == state, "slider count preserves actual solved cache")
		check(preview._inbetween_root.is_visible_in_tree() == (count > 0), "zero count hides geometry")
		check(preview._ghosts.size() == 3 and preview.ghost_transforms.size() == 3, "three authored paddle keys remain separate")
		if count in [1, 6]: verify_display(preview, definition, Path.sample, "count %d" % count)
	check(Store.export_pose_json(definition) == original, "display count does not author saved keys")
	var nodes: int = preview._inbetween_root.find_children("*", "", true, false).size()
	performance.pooled_nodes = nodes
	performance.source_meshes = preview._inbetween_root.sources.size()
	performance.serialized_cache_bytes = state.size()
	var pool_update_times: Array[int] = []
	for iteration in range(36):
		var started := Time.get_ticks_usec()
		preview.set_inbetween_count(iteration % 7)
		pool_update_times.append(Time.get_ticks_usec() - started)
	pool_update_times.sort()
	performance.warm_count_update_median_usec = pool_update_times[pool_update_times.size() / 2]
	performance.warm_count_update_max_usec = pool_update_times[-1]
	preview.set_inbetween_count(6)
	check(preview._inbetween_root.find_children("*", "", true, false).size() == nodes, "warm pool remains bounded after repeated slider changes")
	preview.set_inbetween_count(-10); check(preview.inbetween_count == 0, "count lower bound clamps")
	preview.set_inbetween_count(100); check(preview.inbetween_count == 6, "count upper bound clamps")
	verify_cache(preview, definition, Path.sample, "stroke")
	state = var_to_bytes(preview._inbetween_root.samples)
	for index in range(65):
		preview.show_pose(Path.sample(definition, float(index) / 64)); preview.set_preview_progress(float(index) / 64); preview.set_motion(definition)
	preview.view("side"); preview.zoom(.1); preview._orbit(Vector2(20, 10))
	check(sampled == 65 and preview.motion_rebuild_count == rebuilds, "scrub, playback and camera retain single cached solve pass")
	check(var_to_bytes(preview._inbetween_root.samples) == state, "scrub, playback and camera retain all body and skin transforms")
	# Changing a display preference while a static pose is shown must not make
	# reactivation of the same unchanged stroke reveal old instance counts.
	preview.set_motion(PostureLibrary.instance().get_def(20))
	preview.set_inbetween_count(1)
	preview.set_motion(definition)
	check(sampled == 65 and preview.motion_rebuild_count == rebuilds, "static return does not need a new solve pass")
	verify_display(preview, definition, Path.sample, "same stroke after static count change")
	preview.set_inbetween_count(6)
	definition.windup_body = Keyframe.new(); definition.windup_body.values.body_yaw_deg = 33.0
	preview.set_motion(definition)
	check(sampled == 130 and preview.motion_rebuild_count == rebuilds + 1, "pose edit refreshes exactly one solve pass")
	check(var_to_bytes(preview._inbetween_root.samples) != state, "pose edit replaces stale body snapshots")
	verify_display(preview, definition, Path.sample, "edited stroke")
	for mode in [Variants.STRONG, Variants.WEAK]:
		var variant = Variants.new(); variant.configure(definition, mode, Callable(), preview.player)
		preview.set_motion_sampler(variant.sample); preview.set_motion(definition)
		verify_display(preview, definition, variant.sample, "generated variant %d" % mode)
	preview.set_motion_sampler(ServeStore.sample)
	for style in range(7):
		var serve: PostureDefinition = ServeStore.get_default(style)
		preview.show_pose(ServeStore.sample(serve, .37)); preview.set_motion(serve)
		verify_display(preview, serve, ServeStore.sample, "serve %d" % style)
		check(preview._inbetween_root.samples.size() == 65, "serve cache has 65 whole-body samples")
	preview.set_motion(PostureLibrary.instance().get_def(20))
	check(not preview._inbetween_root.is_visible_in_tree(), "Ready has no invented in-between poses")
	preview.set_inbetween_count(1)
	check(not preview._inbetween_root.is_visible_in_tree(), "count change cannot reveal stale Ready ghosts")
	preview.set_motion(null, false)
	check(not preview._inbetween_root.is_visible_in_tree(), "static body stance hides preceding stroke ghosts")
	preview.set_inbetween_count(6)
	check(not preview._inbetween_root.is_visible_in_tree(), "count change cannot reveal stale body stance ghosts")
	preview.set_motion_sampler(counted_sample); preview.set_motion(definition)
	check(preview._inbetween_root.is_visible_in_tree() and preview.inbetween_sample_indices.size() == 12, "returning to stroke restores preferred ghost count")
	var weak_root: WeakRef = weakref(preview._inbetween_root)
	var weak_pool: Array[WeakRef] = []
	for node in preview._inbetween_root.find_children("*", "", true, false): weak_pool.append(weakref(node))
	preview.queue_free(); await frames(3)
	check(weak_root.get_ref() == null, "destroying preview releases ghost root")
	for node in weak_pool: check(node.get_ref() == null, "destroying preview releases every pooled geometry node")
	var report := {"suite": "inbetween-preview", "checks": checks, "failures": failures, "max_transform_drift_m": max_transform_drift, "max_basis_drift": max_basis_drift, "rigid_render_readback_checks": rigid_readback_checks, "performance": performance}
	var report_file := FileAccess.open(output + ("/preview-results.json" if DisplayServer.get_name() == "headless" else "/preview-render-results.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t")); report_file.close()
	print("[MOBILE INBETWEEN GHOSTS] %d checks, %d failures; max transform drift %.9f m" % [checks, failures.size(), max_transform_drift])
	quit(0 if failures.is_empty() else 1)
