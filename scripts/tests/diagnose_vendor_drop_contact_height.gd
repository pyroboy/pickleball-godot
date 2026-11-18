extends "res://scripts/tests/diagnose_vendor_natural_fk.gd"


func prepare_candidates(candidates: Array, original: Dictionary) -> Array:
	result_file = "/workspace/shared/pickleball-hands/vendor-drop-contact-height-actual.json"
	var selected: Array = []
	for source in candidates:
		if int(source.style) != 4: continue
		var candidate: Dictionary = source.duplicate(true)
		candidate["reference_pose_fields"] = source.pose_fields.duplicate(true)
		candidate["reference_body_transform"] = source.body_transform.duplicate(true)
		var player_origin: = Vector3.ZERO
		for row in original.records:
			if int(row.team) == int(candidate.team) and int(row.style) == 4: player_origin = v(row.player_origin);break
		var release: Vector3 = v(candidate.ball_target_world)
		release.y = 1.45
		var plan: Dictionary = Styles.release_plan(player_origin, int(candidate.team) == 1, 4, release)
		var down: float = float(candidate.ball_target_world[1]) - plan.contact_position.y
		candidate.case += "_real_drop_height"
		candidate.pose_fields.crouch_amount += down
		candidate.body_transform[3][1] -= down
		for key in ["paddle_origin", "elbow", "wrist", "expected_shoulder", "head_world"]: candidate[key][1] -= down
		candidate.ball_target_world = vd(plan.contact_position)
		candidate["derived_delivery"] = {"release": vd(release), "contact": vd(plan.contact_position), "contact_time": plan.contact_time, "bounce_time": plan.bounce_time, "vertical_translation_m": - down}
		selected.append(candidate)
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-drop-contact-height-candidates.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(selected, "\t"));file.close()
	return selected
