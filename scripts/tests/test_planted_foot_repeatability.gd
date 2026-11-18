extends SceneTree
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
var max_error := 0.0
var max_scale_error := 0.0
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(msg)
func run() -> void:
	var preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	var pose = Path.endpoint(Store._export_packaged_default(0,false),0).duplicate(true)
	preview.show_pose(pose)
	var player = preview.player
	var anchors := [player.right_leg_node.foot_pivot.global_position,player.left_leg_node.foot_pivot.global_position]
	# Fixed initial markers, never reset between phases or cycles. Thousands of
	# actual solves include candidate/restore pairs like editor validation.
	for cycle in range(40):
		for field in ["torso_yaw_deg","hip_yaw_deg","body_position_offset"]:
			for sample_index in range(25):
				var candidate = pose.duplicate(true)
				var amount := sin(float(sample_index)/24.0*PI)
				if field == "body_position_offset": candidate.body_position_offset.x += .08*amount
				else: candidate.set(field,float(candidate.get(field))+10.0*amount)
				for displayed in [candidate,pose,candidate]:
					preview.show_pose(displayed)
					for side in range(2):
						var leg = player.right_leg_node if side == 0 else player.left_leg_node
						var error: float = leg.foot_pivot.global_position.distance_to(anchors[side])
						max_error = maxf(max_error,error)
						check(error < .00002,"fixed initial court marker invariant")
						for pivot in [leg.thigh_pivot,leg.shin_pivot,leg.foot_pivot]:
							max_scale_error=maxf(max_scale_error,pivot.scale.distance_to(Vector3.ONE))
						check(absf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)-leg.thigh_length)<.00002,"nominal thigh")
						check(absf(leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position)-leg.shin_length)<.00002,"nominal shin")
	print("REPEATED_PLANT: ",checks," checks, ",failures," failures, 9000 solves, max initial-marker drift=",max_error," max scale error=",max_scale_error)
	quit(0 if failures==0 else 1)
