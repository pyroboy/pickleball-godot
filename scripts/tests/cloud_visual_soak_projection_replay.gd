extends RefCounted
## Immutable captured-frame loader for native display/reprojection diagnostics.
## It does not apply snapshots to gameplay or claim a natural rerun.
static func read_frame(path: String, offset: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(offset)
	var length := file.get_32()
	var value = bytes_to_var(file.get_buffer(length))
	file.close()
	return value if value is Dictionary else {}
