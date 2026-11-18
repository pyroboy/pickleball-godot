extends SceneTree
## Actual geometry audit: authored shoulder rotations are elbow-direction guides,
## not free joint Euler controls. Use an isolated packaged Backhand, without saves.
## godot --headless --path . --script res://scripts/tests/test_pose_slider_effects.gd
const Store = preload("res://scripts/mobile_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Applier = preload("res://scripts/posture_skeleton_applier.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var output := "user://slider-semantics"
const EPS := 0.00002
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var rows: Array = []
var body_rows: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func xyz(v: Vector3) -> Array: return [v.x, v.y, v.z]

func theoretical_elbow(shoulder: Vector3, wrist: Vector3, pole: Vector3, upper: float, fore: float) -> Vector3:
	var span := wrist - shoulder
	var distance := span.length()
	var axis := span.normalized()
	var stretch := maxf(distance / (upper + fore), 1.0)
	upper *= stretch; fore *= stretch
	if distance >= upper + fore: return shoulder + axis * upper
	var along := (upper * upper - fore * fore + distance * distance) / (2.0 * maxf(distance, 0.000001))
	var radial := pole - shoulder
	radial = (radial - axis * radial.dot(axis)).normalized()
	return shoulder + along * axis + radial * sqrt(maxf(0.0, upper * upper - along * along))

func arm_snapshot(player, pose: PostureDefinition, right: bool) -> Dictionary:
	var arm = player.right_arm_node if right else player.left_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var is_main: bool = right == (pose.paddle_hand == 0)
	var field := "right" if right else "left"
	var pole: Vector3 = pose.get(field + "_elbow_pole")
	var forehand: Vector3 = player._get_forehand_axis()
	var forward: Vector3 = player._get_forward_axis()
	var raw: Vector3 = player.global_position + Applier.stance_offset(pole, forehand, forward)
	if pole.length_squared() < 1e-10:
		raw = player.global_position + forehand * (0.5 if right else -0.5) + Vector3.DOWN - forward * 0.5
	var rotated: Vector3 = player.arm_ik._rotate_shoulder_pole(arm, raw, pose.get(field + "_shoulder_rotation_deg"))
	var stable := Anatomy.stabilized_pole(shoulder, wrist, rotated, forehand * (-1.0 if right else 1.0))
	var hand_distal: Vector3 = arm.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis.x
	var weight: float = 1.0 if is_main else player.arm_ik._hands.support_orientation_grip_weight()
	var conditioned := stable
	if weight > 0.00001:
		conditioned = Anatomy.conditioned_pole(shoulder, wrist, stable, hand_distal, arm.upper_arm_length, arm.forearm_length)
		if weight < 0.99999: conditioned = shoulder + (stable - shoulder).normalized().slerp((conditioned - shoulder).normalized(), weight)
	var raw_elbow := theoretical_elbow(shoulder, wrist, rotated, arm.upper_arm_length, arm.forearm_length)
	var stable_elbow := theoretical_elbow(shoulder, wrist, stable, arm.upper_arm_length, arm.forearm_length)
	var conditioned_elbow := theoretical_elbow(shoulder, wrist, conditioned, arm.upper_arm_length, arm.forearm_length)
	var span_axis := (wrist - shoulder).normalized()
	var hint := (rotated - shoulder).normalized()
	check(shoulder.is_finite() and elbow.is_finite() and wrist.is_finite(), "solved arm stays finite")
	check(wrist.distance_to(arm.anatomical_wrist_world) < EPS, "visible hand stays on anatomical wrist")
	# Actual IK is the source of truth. This reconstruction identifies which
	# conditioning step masked a guide, without changing the rig to bypass it.
	check(conditioned_elbow.distance_to(elbow) < 0.0003, "diagnostic reconstructs actual elbow")
	return {"shoulder": shoulder, "elbow": elbow, "wrist": wrist,
		"rotated_pole": rotated, "stable_pole": stable, "conditioned_pole": conditioned,
		"raw_elbow": raw_elbow, "stable_elbow": stable_elbow, "conditioned_elbow": conditioned_elbow,
		"reach_m": shoulder.distance_to(wrist), "link_budget_m": arm.upper_arm_length + arm.forearm_length,
		"raw_guide_projection_leverage": (hint - span_axis * hint.dot(span_axis)).length(),
		"precondition_wrist_bend_deg": rad_to_deg(hand_distal.angle_to(wrist - stable_elbow)),
		"stabilization_correction_m": raw_elbow.distance_to(stable_elbow),
		"conditioning_correction_m": stable_elbow.distance_to(conditioned_elbow), "grip_weight": weight,
		"main": is_main}

func sample(preview, pose: PostureDefinition) -> Dictionary:
	preview.show_pose(pose)
	return {"right": arm_snapshot(preview.player, pose, true), "left": arm_snapshot(preview.player, pose, false),
		"paddle": preview.player.paddle_node.global_transform}

func body_snapshot(preview, pose: PostureDefinition) -> Dictionary:
	preview.show_pose(pose)
	var p = preview.player
	var result := {"body": p.body_pivot.global_transform, "paddle": p.paddle_node.global_transform,
		"torso": p.body_pivot.get_node("TorsoMesh").global_transform,
		"position_report": Body.position_report(p, pose)}
	for side in ["right", "left"]:
		var leg = p.right_leg_node if side == "right" else p.left_leg_node
		result[side + "_knee"] = leg.shin_pivot.global_transform
		result[side + "_foot"] = leg.foot_pivot.global_transform
		result[side + "_foot_pitch_report"] = p.leg_ik.foot_pitch_report(side == "right")
		var lowest := INF
		for corner in range(8): lowest = minf(lowest, (leg.foot_mesh.global_transform * leg.foot_mesh.mesh.get_aabb().get_endpoint(corner)).y)
		result[side + "_sole_min_y"] = lowest
		check(lowest >= PickleballConstants.FLOOR_Y - 0.0001, "body edit retains sole floor clearance")
	for name in ["body", "torso", "paddle", "left_knee", "right_knee", "left_foot", "right_foot"]:
		check(result[name].is_finite(), "body edit geometry stays finite: " + name)
	return result

func audit_body(preview, pose: PostureDefinition, label: String, player_side: int, hand: int, stage: int) -> void:
	var baseline := body_snapshot(preview, pose)
	for field in ["body_position_offset", "weight_shift", "hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "right_foot_yaw_deg", "left_foot_yaw_deg", "right_foot_pitch_deg", "left_foot_pitch_deg", "right_knee_pole", "left_knee_pole"]:
		var vector: bool = pose.get(field) is Vector3
		var amount := 0.05 if field == "body_position_offset" else (10.0 if field.ends_with("_deg") else 0.1)
		for axis in (range(3) if vector else [-1]):
			var changed: PostureDefinition = pose.duplicate(true)
			if vector:
				var value: Vector3 = changed.get(field); value[axis] += amount; changed.set(field, value)
			else: changed.set(field, float(changed.get(field)) + amount)
			var solved := body_snapshot(preview, changed)
			var effects := {}
			for name in ["body", "torso", "paddle", "left_knee", "right_knee", "left_foot", "right_foot"]:
				var before: Transform3D = baseline[name]
				var after: Transform3D = solved[name]
				effects[name] = {"displacement_m": before.origin.distance_to(after.origin), "world_delta": after.origin - before.origin,
					"rotation_deg": rad_to_deg(before.basis.orthonormalized().get_rotation_quaternion().angle_to(after.basis.orthonormalized().get_rotation_quaternion()))}
			if field == "body_position_offset": check(baseline.paddle.is_equal_approx(solved.paddle), "body position keeps authored paddle fixed")
			if field.ends_with("_knee_pole"):
				for name in ["left_foot", "right_foot"]: check(effects[name].displacement_m < EPS, "knee guide keeps foot target fixed")
			body_rows.append({"case": label, "player_side": player_side, "paddle_hand": hand, "stage": stage,
				"field": field, "axis": axis, "delta": amount, "effects": effects,
				"baseline": baseline, "solved": solved})

func serializable(value):
	if value is Vector3: return xyz(value)
	if value is Transform3D: return {"origin": xyz(value.origin), "basis": [xyz(value.basis.x), xyz(value.basis.y), xyz(value.basis.z)]}
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = serializable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(serializable(item))
		return result
	return value

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var requested := arg.trim_prefix("--output=")
			if not requested.is_absolute_path() or requested.contains("://"):
				push_error("--output requires an absolute filesystem directory"); quit(2); return
			output = requested
	var isolated := "user://pose_store_tests/slider_effects_%d_%d/poses.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(Store.set_test_path(isolated) == OK, "saved poses isolated")
	var preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	var max_response := {}
	for side in [0, 1]:
		preview.player.player_num = side
		for hand in [0, 1]:
			for stage in range(3):
				var pose: PostureDefinition = Path.endpoint(Store._export_packaged_default(2, false), stage)
				pose.paddle_hand = hand
				var baseline := sample(preview, pose)
				var label := "side%d hand%d %s" % [side, hand, Preview.STAGE_NAMES[stage]]
				cases.append({"label": label, "player_side": side, "paddle_hand": hand, "stage": stage,
					"left_hand_mode": pose.left_hand_mode, "baseline": baseline,
					"authored_left_shoulder": pose.left_shoulder_rotation_deg, "authored_right_shoulder": pose.right_shoulder_rotation_deg,
					"authored_left_pole": pose.left_elbow_pole, "authored_right_pole": pose.right_elbow_pole})
				for field in ["left_shoulder_rotation_deg", "right_shoulder_rotation_deg", "left_elbow_pole", "right_elbow_pole"]:
					var arm_name := "left" if field.begins_with("left") else "right"
					var other_name := "right" if arm_name == "left" else "left"
					var degrees: bool = field.ends_with("_deg")
					for axis in range(3):
						for amount in ([-90.0, -30.0, -1.0, 1.0, 30.0, 90.0] if degrees else [-0.5, -0.1, -0.01, 0.01, 0.1, 0.5]):
							var changed: PostureDefinition = pose.duplicate(true)
							var authored: Vector3 = changed.get(field); authored[axis] += amount; changed.set(field, authored)
							var solved := sample(preview, changed)
							var base_arm: Dictionary = baseline[arm_name]
							var actual_arm: Dictionary = solved[arm_name]
							var response: float = base_arm.elbow.distance_to(actual_arm.elbow)
							var raw_response: float = base_arm.raw_elbow.distance_to(actual_arm.raw_elbow)
							var key: String = field + ":" + str(axis)
							max_response[key] = maxf(max_response.get(key, 0.0), response)
							check(baseline.paddle.is_equal_approx(solved.paddle), "guide keeps fixed paddle: " + label)
							check(base_arm.shoulder.distance_to(actual_arm.shoulder) < EPS, "guide keeps fixed shoulder: " + label)
							check(base_arm.wrist.distance_to(actual_arm.wrist) < EPS, "guide keeps fixed wrist: " + label)
							check(baseline[other_name].elbow.distance_to(solved[other_name].elbow) < EPS, "guide changes only named arm: " + label)
							rows.append({"case": label, "player_side": side, "paddle_hand": hand, "stage": stage,
								"field": field, "axis": axis, "delta": amount, "units": "degrees" if degrees else "metres",
								"elbow_effect_m": response, "unconditioned_elbow_effect_m": raw_response,
								"wrist_effect_m": base_arm.wrist.distance_to(actual_arm.wrist),
								"shoulder_effect_m": base_arm.shoulder.distance_to(actual_arm.shoulder),
								"paddle_effect_m": baseline.paddle.origin.distance_to(solved.paddle.origin),
								"rotated_pole_effect_m": base_arm.rotated_pole.distance_to(actual_arm.rotated_pole),
								"conditioned_pole_effect_m": base_arm.conditioned_pole.distance_to(actual_arm.conditioned_pole),
								"solved": actual_arm})
				# Restoring the same values must restore the same actual geometry.
				var restored := sample(preview, pose)
				for name in ["left", "right"]:
					check(restored[name].elbow.distance_to(baseline[name].elbow) < EPS, "restore identical elbow: " + label)
				audit_body(preview, pose, label, side, hand, stage)
	for field_axis in max_response:
		check(max_response[field_axis] > .001, "guide is connected to real geometry: " + field_axis)
		print("SLIDER MAX EFFECT ", field_axis, " = ", max_response[field_axis], "m")
	for index in range(rows.size() / 2):
		check(absf(rows[index].elbow_effect_m - rows[index + rows.size() / 2].elbow_effect_m) < EPS,
			"same authored edit has equal court-side response")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output + "/effects.json", FileAccess.WRITE)
	check(file != null, "diagnostic file opens")
	if file:
		file.store_string(JSON.stringify(serializable({"checks": checks, "failures": failures, "cases": cases, "edits": rows, "body_edits": body_rows, "max_effect_m": max_response}), "\t"))
		file.close()
	print("POSE SLIDER EFFECTS: %d checks, %d failures; %d cases, %d arm edits, %d body edits; output=%s" % [checks, failures.size(), cases.size(), rows.size(), body_rows.size(), ProjectSettings.globalize_path(output)])
	preview.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
