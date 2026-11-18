extends SceneTree
const Store=preload("res://scripts/mobile_pose_store.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	Store.set_test_path("user://pose_store_tests/review_ready_%d/poses.json"%OS.get_process_id())
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await process_frame;await physics_frame
	root.get_node("PauseController").open()
	var p=game.player_left
	var before=PostureLibrary.instance().get_def(20).body_yaw_deg
	p.hitting._animate_authored_swing(0,.6)
	var tween=p.hitting.paddle_swing_tween
	game.open_mobile_pose_editor();await process_frame;await process_frame
	var e=game.mobile_pose_editor
	for i in range(e._definitions.size()):
		if e._definitions[i].posture_id==20:e._select_pose(i);break
	e._changed("body_yaw_deg",before+40.0);e._save_current()
	print("READY BEFORE=",before," saved=",PostureLibrary.instance().get_def(20).body_yaw_deg)
	tween.custom_step(5.0)
	print("COMMITTED RECOVERY yaw=",p.posture.transition_pose_blend.body_yaw_deg," expected original=",before)
	var preserved:bool=is_equal_approx(p.posture.transition_pose_blend.body_yaw_deg,before)
	game.queue_free();await process_frame;quit(0 if preserved else 1)
