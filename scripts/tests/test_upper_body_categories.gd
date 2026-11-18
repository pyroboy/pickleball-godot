extends "res://scripts/tests/test_mobile_pose_controls.gd"
const Fields=preload("res://scripts/ui/mobile_pose_fields.gd")
var geometry_rows:Array=[]
func same_transform(a:Transform3D,b:Transform3D)->bool:
	return a.origin.distance_to(b.origin)<.00002 and a.basis.orthonormalized().is_equal_approx(b.basis.orthonormalized()) and a.basis.get_scale().distance_to(b.basis.get_scale())<.00005

func all_sliders(node:Node,found:Dictionary)->void:
	if node is HSlider and node.has_meta("pose_field_key"):
		var key:String=node.get_meta("pose_field_key")
		check(not found.has(key),"no duplicate active field "+key);found[key]=true
	for child in node.get_children():all_sliders(child,found)

func rig()->Dictionary:
	var p=editor._preview.player
	return {"root":p.body_pivot.global_transform,"hips":p.body_pivot.get_node("HipsMesh").global_transform,"chest":p.body_pivot.get_node("TorsoMesh").global_transform,"paddle":p.paddle_node.global_transform,"rf":p.right_leg_node.foot_pivot.global_transform,"lf":p.left_leg_node.foot_pivot.global_transform,"rs":p.right_arm_node.upper_pivot.global_position,"ls":p.left_arm_node.upper_pivot.global_position,"rw":p.right_arm_node.hand_mesh.global_transform,"lw":p.left_arm_node.hand_mesh.global_transform}
func run()->void:
	create_timer(180,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://categories/poses.json");ServeStore.set_test_path("user://categories/serves.json")
	output="/tmp/upper-body-qa/captures";DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	pause=root.get_node("PauseController")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await frames(4);pause.open();game.open_mobile_pose_editor();await frames(4);editor=game.mobile_pose_editor
	for workspace in [1,0,1,2,1,0]:
		editor._select_workspace(workspace);check(editor._has_motion()==(not editor._base and editor._current is PostureDefinition and (editor._serve or editor._current.posture_id!=20)),"workspace transition matches actual definition type")
	for base in [false,true]:
		var owned:Dictionary={}
		for cat in range(9):
			for d in Fields.category_fields(cat,base):
				check(not owned.has(d.field),"single owner "+d.field);owned[d.field]=cat
		for group in range(6):
			for d in Fields.fields(group,base):check(owned.has(d.field),"existing field retained "+d.field)
	for joint in Fields.JOINT_IDS:
		editor._joint_chosen(joint);check(editor._category.selected==Fields.category_for_joint(joint),"joint routes "+joint)
		if joint.ends_with("hand"):check(editor._paddle_view==2,"hand selection opens hand controls")
	for workspace in range(3):
		editor._select_workspace(workspace)
		for cat in range(9):
			if workspace==2 and cat==8:continue
			editor._select_category(cat)
			for view in (range(3) if cat==7 and workspace!=1 else [0]):
				editor._paddle_view=view;editor._build_fields();all_sliders(editor._fields,{})
				for d in Fields.category_fields(cat,workspace==1):
					if d.type=="option" or editor._edit.get(d.field)==null:continue
					if workspace==2 and not ServeStore.is_field_editable(editor._stage,d.field):continue
					if cat==7 and workspace!=1:
						var kind:int=0 if d.field in editor.ROT or d.field.contains("signed") or d.field.contains("sign_source") else 1 if d.field in editor.POS or d.field=="paddle_floor_clearance" else 2
						if view!=kind:continue
					for axis in (range(3) if d.type=="vector" else [-1]):
						if not editor._inactive_control_reason(d.field,axis).is_empty():continue
						var key:String=d.field+(":"+str(axis) if axis>=0 else "")
						check(editor._sliders.has(key),"accessible "+str(workspace)+" "+str(cat)+" "+key)
				await frames(1)
	editor._select_workspace(0)
	for side in [0,1]:
		editor._preview.player.player_num=side
		for hand in [0,1]:
			for pose_index in [0,2,3]:
				editor._select_pose(pose_index);editor._current.paddle_hand=hand
				for phase in range(3):
					editor._select_stage(phase);editor._select_category(0);editor._refresh_preview()
					var before:=rig();var value:float=editor._edit.torso_yaw_deg
					editor._sliders.torso_yaw_deg.value=value+5.0
					var after:=rig()
					var tag:String="side%d hand%d pose%d phase%d"%[side,hand,pose_index,phase]
					for fixed in ["root","hips","rf","lf","paddle"]:check(same_transform(before[fixed],after[fixed]),tag+" fixed "+fixed)
					check((before.rs.distance_to(after.rs)>.0001 and before.ls.distance_to(after.ls)>.0001) or (is_equal_approx(float(editor._edit.torso_yaw_deg),value) and editor._status.text.contains("Reach limit")),tag+" both shoulders turn or explicit fixed-hips guard")
					check(after.rw.is_finite() and after.lw.is_finite(),tag+" wrists finite")
					geometry_rows.append({"case":tag,"paddle_drift":before.paddle.origin.distance_to(after.paddle.origin),"hips_drift":before.hips.origin.distance_to(after.hips.origin),"right_grip_drift":before.rw.origin.distance_to(after.rw.origin),"left_grip_drift":before.lw.origin.distance_to(after.lw.origin)})
					editor._sliders.torso_yaw_deg.value=value
					check(rig().paddle.is_equal_approx(before.paddle),tag+" restore")
					await frames(1)
	editor._select_workspace(2)
	for pose_index in range(editor._definitions.size()):
		editor._select_pose(pose_index)
		for phase in range(3):
			editor._select_stage(phase);editor._select_category(0);editor._refresh_preview()
			var before:=rig();var value:float=editor._edit.torso_yaw_deg
			editor._sliders.torso_yaw_deg.value=value+2.0
			var after:=rig()
			for fixed in ["root","hips","rf","lf","paddle"]:
				check(same_transform(before[fixed],after[fixed]),"serve%d phase%d fixed %s"%[pose_index,phase,fixed])
			editor._sliders.torso_yaw_deg.value=value
			await frames(1)
	editor._select_workspace(0);editor._select_pose(3);editor._select_category(0)
	for size in [[Vector2i(432,936),Vector2i(720,1560)],[Vector2i(936,432),Vector2i(1560,720)]]:
		root.size=size[0];root.content_scale_size=size[1];editor._layout();editor._select_category(0);await frames(3)
		await snapshot("upper-body-"+str(size[0]))
		editor._view_toggle.button_pressed=true;await frames(3);await snapshot("view-open-"+str(size[0]))
		editor._timeline._settings_button.button_pressed=true;await frames(3);await snapshot("timeline-open-"+str(size[0]))
		check(not editor._view_options.visible,"expanded options are exclusive")
		editor._timeline.close_options()
	var file=FileAccess.open("/tmp/upper-body-qa/categories.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry":geometry_rows,"layout":report},"  "))
	print("UPPER BODY CATEGORIES: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
