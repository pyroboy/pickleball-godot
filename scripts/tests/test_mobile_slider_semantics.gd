extends "res://scripts/tests/test_mobile_pose_controls.gd"
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")

func run()->void:
	create_timer(180,true).timeout.connect(func():quit(2))
	output=OS.get_environment("SLIDER_CAPTURE_DIR")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output="user://slider-semantics-ui"
	DirAccess.make_dir_recursive_absolute(output)
	check(Store.set_test_path("user://pose_store_tests/slider_semantics_%d/poses.json" % Time.get_ticks_usec())==OK,"isolated store")
	check(ServeStore.set_test_path("user://pose_store_tests/slider_semantics_%d/serves.json" % Time.get_ticks_usec())==OK,"isolated serves")
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	pause=root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited):root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered):root.focus_entered.disconnect(pause._on_window_focus_entered)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await frames(4);pause.open();game.open_mobile_pose_editor();await frames(4);editor=game.mobile_pose_editor
	for side in ["right","left"]:
		var d:Dictionary=Fields.body_descriptor(side+"_shoulder_rotation_deg")
		check(d.label.contains("elbow guide rotation"),"rotation label names actual guide")
		for axis in range(3):
			check(Fields.axis_label(d,axis).contains("°"),"angular axis uses degrees")
			check(not Fields.axis_label(d,axis).contains("forward"),"Euler axes never promise translation")
		check(Fields.body_descriptor(side+"_elbow_pole").label.contains("(m)"),"guide position units")
	check(Fields.axis_label(Fields.body_descriptor("right_hand_offset"),1,true).contains("handle"),"main hand paddle-local label")
	check(Fields.axis_label(Fields.body_descriptor("left_hand_offset"),1,false).contains("Height"),"support target stance-relative label")
	select_id(3) # Backhand
	# Locate by family if definitions ever change ordering/IDs.
	if editor._current.family!=1:
		for i in range(editor._definitions.size()):
			if editor._definitions[i].display_name=="Backhand":editor._select_pose(i);break
	var original:Resource=editor._current.duplicate(true)
	for stage in range(3):
		editor._select_stage(stage);editor._joint_chosen("left_elbow");await frames(2)
		check(is_instance_valid(editor._elbow_guide_status),"visible elbow constraint feedback")
		check(editor._elbow_guide_status.text.contains("not shoulder position"),"no shoulder motion promise")
		if stage==2:check(editor._elbow_guide_status.text.contains("near full reach"),"Finish reports straight-arm limit")
		for axis in range(3):
			var key:String="left_shoulder_rotation_deg:"+str(axis)
			var before:Vector3=editor._preview.player.left_arm_node.forearm_pivot.global_position
			var wrist:Vector3=editor._preview.player.left_arm_node.hand_mesh.global_position
			var paddle:Transform3D=editor._preview.player.paddle_node.global_transform
			var value:float=editor._edit.left_shoulder_rotation_deg[axis]
			editor._sliders[key].value=value+1.0
			var moved:float=before.distance_to(editor._preview.player.left_arm_node.forearm_pivot.global_position)*100.0
			check(editor._status.text.contains("%.2f cm"%moved),"slider reports measured solved motion")
			check(is_equal_approx(editor._edit.left_shoulder_rotation_deg[axis],value+1.0),"slider authors selected angle")
			check(wrist.distance_to(editor._preview.player.left_arm_node.hand_mesh.global_position)<.00002,"guide keeps grip fixed")
			check(paddle.origin.distance_to(editor._preview.player.paddle_node.global_position)<.00002,"guide keeps paddle fixed")
			editor._sliders[key].value=value
		if capture:
			if stage==1:
				editor._scroll.ensure_control_visible(editor._sliders["left_shoulder_rotation_deg:0"])
				await frames(3)
			await snapshot(["windup-guide-limits","contact-guide-controls","finish-reach-limits"][stage])
	editor._select_stage(1);editor._joint_chosen("left_elbow")
	editor._changed("left_shoulder_rotation_deg",Vector3(25,70,-15))
	var player=editor._preview.player
	var arm=player.left_arm_node
	var shoulder:Vector3=arm.upper_pivot.global_position
	var wrist:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
	var axis:Vector3=(wrist-shoulder).normalized()
	var fh:Vector3=player._get_forehand_axis();var fw:Vector3=player._get_forward_axis()
	var raw:Vector3=editor._edit.left_elbow_pole
	var before_pole:Vector3=player.arm_ik._rotate_shoulder_pole(arm,player.global_position+fh*raw.x+Vector3.UP*raw.y+fw*raw.z,editor._edit.left_shoulder_rotation_deg)-shoulder
	before_pole=(before_pole-axis*before_pole.dot(axis)).normalized()
	editor._swivel_elbow_guide(1)
	raw=editor._edit.left_elbow_pole
	var after_pole:Vector3=player.arm_ik._rotate_shoulder_pole(arm,player.global_position+fh*raw.x+Vector3.UP*raw.y+fw*raw.z,editor._edit.left_shoulder_rotation_deg)-shoulder
	after_pole=(after_pole-axis*after_pole.dot(axis)).normalized()
	check(absf(rad_to_deg(before_pole.signed_angle_to(after_pole,axis))-5.0)<.01,"Bend helper respects existing Euler guide rotation")
	check(editor._inactive_control_reason("swing_path_blend",-1).contains("linked"),"linked two-hand path marked inactive")
	check(editor._inactive_control_reason("split_step_hop_height",-1).contains("Inactive"),"unused split height marked inactive")
	check(editor._inactive_control_reason("lunge_distance",-1).contains("Inactive"),"unused lunge marked inactive")
	editor._edit.body_position_offset=Vector3(.01,0,0)
	check(not editor._inactive_control_reason("right_foot_offset",1).is_empty(),"grounded foot height unavailable")
	check(editor._inactive_control_reason("right_foot_offset",0).is_empty(),"foot lateral placement still available")
	check(editor._inactive_control_reason("right_foot_offset",2).is_empty(),"foot forward placement still available")
	editor._edit.body_position_offset=Vector3.ZERO
	check(editor._inactive_control_reason("right_foot_offset",1).is_empty(),"legacy authored foot height preserved")
	# Runtime-only values retain their data but provide no misleading slider.
	editor._select_workspace(1);editor._group.select(5);editor._build_fields()
	check(not editor._sliders.has("split_step_hop_height") and not editor._sliders.has("lunge_distance"),"unused controls cannot be dragged")
	check(editor._current.split_step_hop_height==editor._definitions[0].split_step_hop_height,"inactive data preserved")
	editor._select_workspace(0);select_id(original.posture_id);editor._joint_chosen("left_elbow")
	for geometry in [[Vector2i(432,936),Vector2i(720,1560)],[Vector2i(936,432),Vector2i(1560,720)]]:
		root.size=geometry[0];root.content_scale_size=geometry[1];editor._layout();await frames(4)
		check(editor._elbow_guide_status.size.x<=editor._scroll.size.x,"constraint text wraps in viewport")
	editor._finish_close();await frames(4);paused=false;game.queue_free();await frames(3)
	print("MOBILE SLIDER SEMANTICS: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
