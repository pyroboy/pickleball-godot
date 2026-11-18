extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const Approved = preload("res://scripts/approved_backhand_import.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func run() -> void:
	var corrected: Resource = Store._export_packaged_default(2, false)
	var original: Resource = corrected.duplicate(true)
	Store._apply_fields(original, JSON.parse_string(Approved.JSON_TEXT).fields)
	var before: Dictionary = Store._encode_fields(original)
	var after: Dictionary = Store._encode_fields(corrected)
	for key in before:
		if key not in ["left_elbow_path", "right_elbow_path", "left_elbow_pole", "paddle_roll_signed_deg"]:
			check(same_value(before[key], after[key]), "only authorized elbow channels change: " + key)
	check(corrected.left_elbow_path.size() == 63 and corrected.right_elbow_path.size() == 63, "dense bounded authored routes")
	for route in ["left_elbow_path", "right_elbow_path"]:
		check(corrected.get(route)[0] == original.get(route)[0] and corrected.get(route)[62] == original.get(route)[8], "Wind-up and Finish poles preserved " + route)
	var maxima: Dictionary = {}
	for count in [240, 480]:
		for court in range(2):
			for source in [["original", original], ["corrected", corrected]]:
				var preview = Preview.new(); root.add_child(preview)
				for tick in range(3): await process_frame
				preview.player.player_num = court
				var previous: Array[Vector3] = []
				var maximum := 0.0
				var positions: Array = []
				for index in range(count + 1):
					var t: float = float(index) / float(count)
					var pose = Path.sample(source[1], t)
					preview.show_pose(pose)
					var elbows: Array[Vector3] = [preview.player.right_arm_node.forearm_pivot.global_position, preview.player.left_arm_node.forearm_pivot.global_position]
					for arm in range(2):
						check(elbows[arm].is_finite(), "finite actual elbow")
						if not previous.is_empty(): maximum = maxf(maximum, elbows[arm].distance_to(previous[arm]))
					positions.append(elbows); previous = elbows
					if source[0] == "corrected":
						var raw: Resource = Path.sample(original, t)
						var a: Transform3D = Path.world_transform(preview.player, raw)
						var b: Transform3D = Path.world_transform(preview.player, pose)
						check((a * Vector3(0, 0.2794, 0)).is_equal_approx(b * Vector3(0, 0.2794, 0)), "intended paddle head trajectory unchanged")
						if index == count / 2: check(a.basis.z.is_equal_approx(b.basis.z), "Contact face normal preserved by in-plane shaft correction")
				for index in [count, count / 2, 0, count / 4, count * 3 / 4]:
					preview.show_pose(Path.sample(source[1], float(index) / count))
					check(preview.player.right_arm_node.forearm_pivot.global_position.is_equal_approx(positions[index][0]) and preview.player.left_arm_node.forearm_pivot.global_position.is_equal_approx(positions[index][1]), "reverse/random sampling deterministic")
				maxima[str(count)+":"+str(court)+":"+source[0]] = maximum
				check(maximum < (0.065 if count == 240 else 0.04) if source[0] == "corrected" else maximum > 0.3, "corrected route eliminates old discontinuity")
				preview.queue_free(); await process_frame
	print("BACKHAND ELBOW METRICS: ", JSON.stringify(maxima))
	print("[BACKHAND ELBOW SMOOTHING] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func same_value(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_value(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not same_value(a[i], b[i]): return false
		return true
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	return a == b
