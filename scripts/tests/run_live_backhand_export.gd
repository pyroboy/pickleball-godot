extends SceneTree


const Review = preload("res://scripts/tests/export_live_backhand_geometry.gd")
func _initialize() -> void : call_deferred("run")
func run() -> void :
	if "--all-receiving" in OS.get_cmdline_user_args():
		var completed: Dictionary = {}
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--skip-exported="):
				var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--skip-exported=")))
				for snapshot in saved.snapshots:
					if snapshot.capture_phase == "presented_hit_frame": completed[snapshot.case] = true
		var cases: = PackedStringArray()
		var total_receiving: int = 0
		for pose in PostureLibrary.instance().all_definitions():
			if not pose.has_zone: continue
			total_receiving += 1
			var case_id: String = "pose_%02d" % pose.posture_id
			if not completed.has(case_id): cases.append(case_id)
		assert (total_receiving == 18, "Expected all18 real receiving postures")
		assert ( not cases.is_empty(), "No unexported receiving cases remain")
		OS.set_environment("POSE_REVIEW_ONLY", ",".join(cases))
		print("LIVE CONTACT EXPORT: selected ", cases.size(), " of18 receiving cases; skipped ", completed.size(), " completed snapshots")
	var review = Review.new()
	root.add_child(review)
	current_scene = review
