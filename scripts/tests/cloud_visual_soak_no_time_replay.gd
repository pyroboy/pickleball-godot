extends RefCounted
## Captured status replay only, never an invented legal root/contact fixture.
## Callers may feed each observed_status into their presentation-only gate.
static func sequence(path: String = "res://tools/cloud_qa/visual_soak_no_time_episode.json") -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Array = []
	var samples: Array = data.samples
	var first: int = int(samples[0].usec)
	for row in samples:
		result.append({"offset_usec": int(row.usec) - first, "observed_status": row.guide_status,
			"visible": row.guide_visible, "flight_id": int(row.flight), "bounce": int(row.bounce),
			"advisor_solve": int(row.advisor_solves), "held": row.held, "aim_mode": row.aim_mode,
			"player_position": row.player_position, "ball_position": row.ball_position})
	return result
