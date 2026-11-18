extends SceneTree
const Replay = preload("res://scripts/tests/cloud_visual_soak_projection_replay.gd")
func _initialize() -> void:
	var folder := OS.get_environment("VISUAL_SOAK_SNAPSHOT_FOLDER")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("index.json")))
	var count := 0
	for row in data.frames:
		var frame: Dictionary = Replay.read_frame(folder.path_join("snapshots.bin"), int(row.snapshot_offset))
		if frame.is_empty() or not frame.player_transform is Transform3D or not frame.camera_projection is Projection or not frame.diagnostic is Dictionary:
			push_error("Lossless snapshot decode failed at " + str(row.snapshot_offset)); quit(1); return
		if absf(float(frame.elapsed) - float(row.elapsed)) > 0.000001:
			push_error("Snapshot timestamp/index mismatch"); quit(1); return
		count += 1
	print("VISUAL_SOAK_SNAPSHOT_CHECK ", count, " frames decoded losslessly")
	quit(0)
