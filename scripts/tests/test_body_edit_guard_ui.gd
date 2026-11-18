extends "res://scripts/tests/test_mobile_pose_controls.gd"
const Fields=preload("res://scripts/ui/mobile_pose_fields.gd")
const Validator=preload("res://scripts/pose_foot_edit_validator.gd")
var rejected:=0
func run()->void:
	create_timer(180,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://guard-ui/poses.json");ServeStore.set_test_path("user://guard-ui/serves.json")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await frames(3);pause=root.get_node("PauseController");pause.open();game.open_mobile_pose_editor();await frames(3);editor=game.mobile_pose_editor
	for index in range(editor._definitions.size()):
		for phase in range(3):
			for field in ["crouch_amount","body_roll_deg","hip_yaw_deg"]:
				editor._copies.clear();editor._select_pose(index);editor._select_stage(phase);editor._select_category(1)
				var before:String=Store.export_pose_json(editor._current)
				var baseline:Dictionary=Validator.snapshot(editor._preview.player)
				var value:float=editor._edit.get(field)
				var desired:float=.7 if field=="crouch_amount" else 60.0 if field=="body_roll_deg" else 90.0
				editor._set_body_value(Fields.body_descriptor(field),-1,desired)
				var unchanged:bool=is_equal_approx(float(editor._edit.get(field)),value) and not is_equal_approx(value,desired)
				if unchanged:
					rejected+=1
					check(editor._status.text.contains("Requested") and editor._status.text.contains("kept") and editor._status.text.contains("Reach limit"),"rejection explains requested/applied")
					check(Store.export_pose_json(editor._current)==before,"rejection preserves all authored fields")
					var restored:Dictionary=Validator.validate(editor._preview.player,editor._preview.pose,baseline)
					check(restored.accepted,"rejection restores baseline solved anchors")
				else:
					check(is_equal_approx(float(editor._edit.get(field)),desired),"valid request reaches original field binding")
					check(Validator.validate(editor._preview.player,editor._preview.pose,baseline).accepted,"accepted edit preserves planted feet and reach")
				await frames(1)
	check(rejected>0,"real infeasible UI requests rejected")
	print("BODY EDIT GUARD UI: %d checks, %d rejections, %d failures"%[checks,rejected,failures.size()]);quit(0 if failures.is_empty() else 1)
