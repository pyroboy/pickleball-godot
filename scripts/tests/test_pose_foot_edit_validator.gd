extends SceneTree
const Validator = preload("res://scripts/pose_foot_edit_validator.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var actual_rejections := 0
var failures: Array[String] = []
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: failures.append(msg); push_error(msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	for source in PostureLibrary.new().definitions:
		for stage in range(3):
			var pose = Path.endpoint(source,stage).duplicate(true)
			preview.show_pose(pose)
			var baseline := Validator.snapshot(preview.player)
			check(Validator.validate(preview.player,pose,baseline).accepted,"unchanged accepted")
			var synthetic: Dictionary = baseline.duplicate(true)
			synthetic.feet[0].planted = true; baseline.feet[0].planted = true
			synthetic.feet[0].anchor += Vector3(.001,0,0)
			check(not Validator.compare(synthetic,pose,baseline).accepted,"one millimetre target drift rejected")
			synthetic = baseline.duplicate(true)
			synthetic.feet[0].reach_excess += .001
			check(not Validator.compare(synthetic,pose,baseline).accepted,"worsening reach rejected")
			synthetic = baseline.duplicate(true)
			baseline.feet[0].reach_excess = .02; baseline.feet[0].anchor_error = .02
			synthetic.feet[0].reach_excess = .01; synthetic.feet[0].anchor_error = .01
			check(Validator.compare(synthetic,pose,baseline).accepted,"inherited infeasibility may improve")
			preview.show_pose(pose)
			baseline = Validator.snapshot(preview.player)
			var candidate = pose.duplicate(true)
			candidate.body_position_offset += Vector3(.3,.2,.3)
			candidate.hip_yaw_deg += 45
			preview.show_pose(candidate)
			var evaluated := Validator.snapshot(preview.player)
			var report := Validator.validate(preview.player,candidate,baseline)
			for side in range(2):
				if baseline.feet[side].planted and evaluated.feet[side].reach_excess > baseline.feet[side].reach_excess + Validator.POSITION_TOLERANCE_M:
					check(not report.accepted,"actual worsening candidate rejected before commit")
			var impossible = pose.duplicate(true)
			impossible.crouch_amount = 1.1
			impossible.body_roll_deg = 80
			preview.show_pose(impossible)
			var impossible_report := Validator.validate(preview.player,impossible,baseline)
			if not impossible_report.accepted: actual_rejections += 1
			preview.show_pose(pose)
			var restored := Validator.snapshot(preview.player)
			check(restored.feet[0].ankle.distance_to(baseline.feet[0].ankle) < Validator.POSITION_TOLERANCE_M,"rejection restores baseline ankle")
			check(restored.feet[1].ankle.distance_to(baseline.feet[1].ankle) < Validator.POSITION_TOLERANCE_M,"rejection restores other ankle")
	check(actual_rejections > 0,"real impossible geometry rejected")
	print("ACTUAL_REJECTIONS: ",actual_rejections)
	print("FOOT_EDIT_VALIDATOR: ", checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
