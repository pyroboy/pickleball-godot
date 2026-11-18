extends SceneTree
const Contacts = preload("res://scripts/pose_foot_contacts.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Split = preload("res://scripts/ui/mobile_pose_split_step_preview.gd")
var count := 0
var unreachable := 0
var feasible_anchor_error := 0.0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	count += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	for original in PostureLibrary.new().definitions:
		for stage in range(3):
			var pose = Path.endpoint(original, stage).duplicate(true)
			preview.show_pose(pose)
			var anchors := [preview.player.leg_ik.right_foot_smooth, preview.player.leg_ik.left_foot_smooth]
			var yaw := [preview.player.leg_ik._right_yaw, preview.player.leg_ik._left_yaw]
			for offset in [Vector3(.08, -.04, -.05), Vector3(-.08, .04, .05), Vector3.ZERO]:
				pose.body_position_offset = offset
				pose.body_yaw_deg += 7; pose.hip_yaw_deg += 9; pose.torso_yaw_deg -= 11
				preview.show_pose(pose)
				check(preview.player.leg_ik.right_foot_smooth.distance_to(anchors[0]) < .00001 and preview.player.leg_ik.left_foot_smooth.distance_to(anchors[1]) < .00001, "pose %s stage %s body edits preserve court anchors" % [original.posture_id, stage])
				check(absf(preview.player.leg_ik._right_yaw-yaw[0]) < .00001 and absf(preview.player.leg_ik._left_yaw-yaw[1]) < .00001, "body edits preserve shoe yaw")
				for leg in [preview.player.right_leg_node, preview.player.left_leg_node]:
					check(absf(leg.shin_pivot.position.length()-leg.thigh_length) < .00001 and absf(leg.foot_pivot.position.length()-leg.shin_length) < .00001, "nominal bones never stretch")
					check(not leg.reach_report.is_empty(), "leg exposes feasibility")
					if not leg.reach_report.feasible: unreachable += 1
					else: feasible_anchor_error = maxf(feasible_anchor_error, leg.foot_pivot.global_position.distance_to(leg.reach_report.anchor))
	var pose = Store._export_packaged_default(20, false).duplicate(true)
	preview.show_pose(pose)
	var base: Vector3 = preview.player.leg_ik.right_foot_smooth
	Split.show(preview, pose, {"active": true, "phase":"split_unweight", "foot_lift":.02,"body_lift":.02,"ankle_pitch_deg":8.0})
	check(not preview.player.leg_ik.right_foot_locked and not preview.player.leg_ik.left_foot_locked, "split flight releases contacts")
	check(preview.player.leg_ik.right_foot_smooth.distance_to(base + Vector3.UP * .02) < .00001,"split explicit lift")
	Split.show(preview, pose, {})
	check(preview.player.leg_ik.right_foot_locked and preview.player.leg_ik.right_foot_smooth.distance_to(base)<.00001,"empty split restores exact anchors")
	pose.right_foot_offset.x += .07; preview.show_pose(pose)
	check(preview.player.leg_ik.right_foot_smooth.distance_to(base) > .06,"explicit foot edit reanchors")
	check(not Contacts.reach_report(Vector3(0,3,0),Vector3.ZERO).feasible,"unreachable anchors reported")
	print("REACH_SAMPLES infeasible=",unreachable," max_feasible_anchor_error=",feasible_anchor_error)
	print("PLANTED_FEET_CHECKS ",count," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
