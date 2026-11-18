extends SceneTree
## Deterministic geometry/temporal fixture; does not alter production state.
const Arc = preload("res://scripts/ui/aim_arc_style.gd")
var checks := 0
var failures: Array[String] = []
var rate := 60
var output := "/tmp/cloud_arc_style.json"
var camera: Camera3D
var viewport := Rect2(0, 0, 720, 1280)
var records: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=" )
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: ", label)

func make_path(t: float = 0.0, mode: String = "static", count: int = 48) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in count:
		var u := float(i) / maxf(1.0, float(count - 1))
		var point := Vector3(0.2 + 0.6 * u, 1.0 + 2.2 * sin(PI * u) - 0.95 * u, 2.5 - 8.0 * u)
		if mode == "aim": point.x += 0.7 * sin(t * TAU / 3.0) * u
		if mode == "player": point.x += 0.3 * sin(t * TAU / 3.0) * (1.0 - u)
		if mode == "high_curvature": point.x += 1.1 * sin(u * TAU * 3.0)
		if mode == "short": point = Vector3(0, 1, 0).lerp(Vector3(0.02, 1.01, -0.02), u)
		if mode == "long": point.z = 8.0 - 50.0 * u
		result.append(point)
	return result

func old_mask(count: int, seconds: float) -> Array[bool]:
	var bits: Array[bool] = []
	var phase: float = fmod(seconds * 1.7, 1.0)
	for index in range(count - 1): bits.append(fmod(float(index) * 0.43 - phase, 1.0) < 0.56)
	return bits

func is_covered(lines: PackedVector2Array, p: Vector2) -> bool:
	for i in range(0, lines.size(), 2):
		if Geometry2D.get_closest_point_to_segment(p, lines[i], lines[i + 1]).distance_to(p) < 0.0005: return true
	return false

func unit_cases() -> void:
	for path in [PackedVector2Array(), PackedVector2Array([Vector2(8, 9)]), PackedVector2Array([Vector2(8, 9), Vector2(8, 9)]), PackedVector2Array([Vector2(NAN, 4), Vector2(5, INF)]), PackedVector2Array([Vector2(1e30, 1e30), Vector2(-1e30, -1e30)])]:
		var g: Dictionary = Arc.geometry(path, viewport)
		check(g.lines.is_empty(), "empty/degenerate/nonfinite/extreme path has no connecting line")
		for point in g.endpoints: check(point.is_finite(), "finite degenerate cap")
	var straight := PackedVector2Array([Vector2(10, 50), Vector2(310, 50)])
	var split := PackedVector2Array()
	for i in 101: split.append(Vector2(10 + 3 * i, 50))
	var a: Dictionary = Arc.geometry(straight, viewport)
	var b: Dictionary = Arc.geometry(split, viewport)
	for i in 601:
		var p := Vector2(10.13 + float(i) * 0.49, 50)
		check(is_covered(a.lines, p) == is_covered(b.lines, p), "dash phase independent of collinear cache resampling")
	check(a.endpoints[0] == straight[0] and a.endpoints[-1] == straight[-1], "exact source and end even when last dash ends in a gap")
	var clipped := Arc.geometry(PackedVector2Array([Vector2(-400, 50), Vector2(310, 50)]), viewport)
	var translated := Arc.geometry(PackedVector2Array([Vector2(0, 50), Vector2(710, 50)]), Rect2(-400, 0, 1120, 1280))
	for i in 300:
		var p := Vector2(float(i) + 0.13, 50)
		check(is_covered(clipped.lines, p) == is_covered(translated.lines, p + Vector2(400, 0)), "off-screen clipping does not reset dash phase")
	var separated := Arc.geometry(PackedVector2Array([Vector2(0, 20), Vector2(20, 20), Vector2.INF, Vector2(100, 20), Vector2(120, 20)]), viewport)
	check(not is_covered(separated.lines, Vector2(60, 20)), "invalid vertex never creates a connector")
	var solid := Arc.geometry(straight, viewport, 1.0, Arc.SOLID)
	check(solid.lines == straight, "solid exact endpoints and continuous geometry")
	var bad_style := Arc.geometry(straight, viewport, 1.0, 100)
	check(bad_style.lines == a.lines, "unknown style uses steady dashed")
	for scale in [NAN, INF, -1.0, 0.0, 0.25, 1.0, 4.0, 10000.0]:
		var sanitized := Arc.geometry(straight, viewport, scale)
		check(not sanitized.overflow and not sanitized.lines.is_empty(), "invalid/extreme scale remains bounded and drawable")
		for point in sanitized.lines: check(point.is_finite(), "sanitized scale keeps finite geometry")
	var huge := PackedVector2Array()
	for i in 1537: huge.append(Vector2(i, 100))
	var bounded := Arc.geometry(huge, viewport)
	check(bounded.overflow and bounded.lines.is_empty(), "oversized input fails closed")
	var zigzag := PackedVector2Array()
	for i in 512: zigzag.append(Vector2(0 if i % 2 == 0 else 719, 10 + i))
	bounded = Arc.geometry(zigzag, viewport)
	check(bounded.overflow and bounded.lines.is_empty() and bounded.endpoints.is_empty(), "visible stroke budget fails closed without a misleading landing")
	var bad_rect := Arc.geometry(straight, Rect2(Vector2.ZERO, Vector2(INF, 10)))
	check(bad_rect.lines.is_empty(), "invalid viewport fails closed")
	var shifted := PackedVector2Array([straight[0] + Vector2(13.25, 21.75), straight[1] + Vector2(13.25, 21.75)])
	var moved := Arc.geometry(shifted, viewport)
	check(moved.lines.size() == a.lines.size(), "translation preserves dash count")
	for i in moved.lines.size(): check(moved.lines[i].distance_to(a.lines[i] + Vector2(13.25, 21.75)) < 0.001, "translation changes geometry immediately without phase drift")

func projection_cases() -> void:
	camera.global_transform = Transform3D.IDENTITY
	camera.near = 0.1; camera.far = 100.0
	for path in [PackedVector3Array([Vector3(0,0,1),Vector3(1,0,2)]),PackedVector3Array([Vector3.INF,Vector3.ZERO]),PackedVector3Array([Vector3(0,0,-101),Vector3(1,0,-102)])]:
		var p: PackedVector2Array = Arc.project_path(path, camera)
		var g: Dictionary = Arc.geometry(p, viewport)
		check(g.lines.is_empty() and g.endpoints.is_empty(), "invalid/behind/beyond-far depth draws nothing")
	var crossing := PackedVector3Array([Vector3(-0.05,0,-1),Vector3(0.05,0,1),Vector3(0.2,0,-1)])
	var screen: PackedVector2Array = Arc.project_path(crossing, camera)
	var breaks := 0
	for p in screen:
		if not p.is_finite(): breaks += 1
	check(breaks > 0, "near-plane crossing has an explicit break")
	var strokes: Dictionary = Arc.geometry(screen, viewport)
	for p in strokes.lines: check(p.is_finite() and viewport.grow(3.01).has_point(p), "near-plane lines finite and clipped to viewport")
	var enter: PackedVector2Array = Arc.project_path(PackedVector3Array([Vector3(0,0,1),Vector3(0.1,0,-1)]), camera)
	check(not enter[0].is_finite() and enter[-1].is_finite(), "hidden source cannot create fake endpoint cap")
	var invalid: PackedVector2Array = Arc.project_path(PackedVector3Array([Vector3(0,0,-1),Vector3.INF,Vector3(0.2,0,-1)]), camera)
	check(Arc.geometry(invalid, viewport).lines.is_empty(), "invalid sample cannot bridge separated world geometry")
	camera.global_position = Vector3(0, 7, 10)
	camera.look_at(Vector3(0, 0.8, -1), Vector3.UP)

func temporal_case(mode: String) -> void:
	var origin: Transform3D = camera.global_transform
	var prior_mask: Array[bool] = []
	var prior_lines := PackedVector2Array()
	var prior_path := PackedVector2Array()
	var before_toggles := 0
	var static_after_changes := 0
	var cache_refresh_drift := 0.0
	var endpoint_error := 0.0
	var max_path_step := 0.0
	var observed_motion_frames := 0
	var common_samples: Dictionary = {}
	for frame in range(3 * rate + 1):
		var t := float(frame) / float(rate)
		camera.global_transform = origin
		if mode == "camera": camera.global_position += camera.global_basis.x * 0.25 * sin(t * TAU / 3.0)
		var world := make_path(t, mode)
		var original := world.duplicate()
		var path := Arc.project_path(world, camera)
		var g := Arc.geometry(path, viewport)
		var rebuilt := Arc.geometry(Arc.project_path(world.duplicate(), camera), viewport)
		check(g.lines == rebuilt.lines and g.endpoints == rebuilt.endpoints, mode + " deterministic duplicate/cache refresh")
		check(world == original, mode + " leaves authoritative world points unchanged")
		if not g.endpoints.is_empty() and Arc.is_projectable(world[-1], camera) and viewport.has_point(camera.unproject_position(world[-1])):
			endpoint_error = maxf(endpoint_error, g.endpoints[-1].distance_to(camera.unproject_position(world[-1])))
		if Arc.is_projectable(world[-1], camera) and viewport.has_point(camera.unproject_position(world[-1])):
			check(not g.endpoints.is_empty() and g.endpoints[-1] == camera.unproject_position(world[-1]), mode + " visible exact landing cannot disappear in a gap")
		var mask := old_mask(world.size(), 100.0 + t)
		if frame > 0:
			for i in mask.size():
				if mask[i] != prior_mask[i]: before_toggles += 1
			if mode == "static" and g.lines != prior_lines: static_after_changes += 1
			if path.size() == prior_path.size():
				var step := 0.0
				for i in path.size():
					if path[i].is_finite() and prior_path[i].is_finite(): step = maxf(step, path[i].distance_to(prior_path[i]))
				max_path_step = maxf(max_path_step, step)
				if step > 0.0001: observed_motion_frames += 1
		if frame % (rate / 30) == 0: common_samples[str(roundi(t * 1000000.0))] = hash(g.lines)
		prior_mask = mask; prior_lines = g.lines; prior_path = path
	check(before_toggles > 0, mode + " detects prior clock-driven whole-segment toggles")
	check(static_after_changes == 0, mode + " no new static phase changes")
	check(endpoint_error < 0.001, mode + " exact immediate input path endpoint")
	records.append({"scenario":mode,"frames":3*rate+1,"before_clock_segment_full_toggles":before_toggles,"after_static_geometry_changes":static_after_changes if mode == "static" else null,"cache_refresh_max_drift_px":cache_refresh_drift,"max_endpoint_error_px":endpoint_error,"max_required_path_motion_px_per_frame":max_path_step,"observed_path_motion_frames":observed_motion_frames,"common_time_geometry_hashes":common_samples})
	camera.global_transform = origin

func benchmark() -> Dictionary:
	var path := make_path()
	var screen := Arc.project_path(path, camera)
	var result: Dictionary = {}
	for mode in ["before_phase_mask", "before_projection_and_phase_mask", "after_dashed_geometry", "after_solid_geometry", "after_projection_and_dashes"]:
		var values: Array[float] = []
		for pass_index in 5:
			var start := Time.get_ticks_usec()
			for i in 1500:
				match mode:
					"before_phase_mask": old_mask(screen.size(), float(i)/rate)
					"before_projection_and_phase_mask":
						var old_screen := PackedVector2Array(); old_screen.resize(path.size())
						for point_index in path.size(): old_screen[point_index] = camera.unproject_position(path[point_index])
						old_mask(old_screen.size(), float(i)/rate)
					"after_dashed_geometry": Arc.geometry(screen, viewport)
					"after_solid_geometry": Arc.geometry(screen, viewport, 1.0, Arc.SOLID)
					_: Arc.geometry(Arc.project_path(path, camera), viewport)
			values.append(float(Time.get_ticks_usec() - start) / 1500.0)
		values.sort()
		result[mode] = {"median_usec":values[2],"pass_mean_usec":values}
	result["note"] = "Cloud CPU microbenchmark; baseline mask excludes draw calls; candidate uses one multiline call. Not device or GPU performance acceptance."
	return result

func run() -> void:
	root.size = Vector2i(720,1280)
	camera = Camera3D.new(); root.add_child(camera); camera.make_current()
	await process_frame
	unit_cases(); projection_cases()
	for mode in ["static", "aim", "player", "camera", "short", "long", "high_curvature"]: temporal_case(mode)
	var result := {"scope":"Archived build28/cloud candidate helper only. No current Mac build30/31 or universal flicker acceptance.","rate":rate,"checks":checks,"failures":failures,"records":records,"cpu":benchmark()}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ARC STYLE: %d Hz, %d checks, %d failures" % [rate, checks, failures.size()])
	camera.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
