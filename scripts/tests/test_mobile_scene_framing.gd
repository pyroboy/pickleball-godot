extends SceneTree
const Store=preload("res://scripts/mobile_pose_store.gd")
const Serve=preload("res://scripts/mobile_serve_pose_store.gd")
const Fit=preload("res://scripts/ui/mobile_pose_camera_framing.gd")
var game
var editor
var checks:=0
var failures:Array[String]=[]
var report:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func frames(n:int=8)->void:
	for i in range(n):await process_frame
func bounded(tag:String)->void:
	var preview=editor._preview
	var points:PackedVector3Array=Fit.points(preview)
	check(points.size()>50,tag+": visible geometry bounds collected")
	var safe:=Rect2(Vector2.ZERO,preview.size).grow(-2)
	var outside:=0
	for point in points:
		if not safe.has_point(preview._world_screen_position(point)):outside+=1
	check(outside==0,tag+": full model, paddle, contact box and selected gizmo fit (%d outside)"%outside)
	check(preview._fitted_distance<=7.0,tag+": bounded useful distance")
	report.append({"tag":tag,"distance":preview._fitted_distance,"points":points.size(),"outside":outside,"scene_size":str(preview.size)})
func run()->void:
	create_timer(120,true).timeout.connect(func():quit(2))
	check(Store.set_test_path("user://pose_store_tests/scene_framing_%d/poses.json"%Time.get_ticks_usec())==OK,"stroke save isolated")
	check(Serve.set_test_path("user://pose_store_tests/scene_framing_serve_%d/poses.json"%Time.get_ticks_usec())==OK,"serve save isolated")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames()
	root.get_node("PauseController").open();game.open_mobile_pose_editor();await frames();editor=game.mobile_pose_editor
	editor._gizmo_show.set_pressed_no_signal(true);editor._gizmo_mode.select(0);editor._select_gizmo_mode(0)
	for resolution in [Vector2i(720,1560),Vector2i(720,1200)]:
		root.content_scale_size=resolution;root.size=Vector2i(432,936) if resolution.y==1560 else Vector2i(600,1000);await frames()
		for expanded in [false,true]:
			editor._set_scene_expanded(expanded);await frames()
			editor._select_workspace(0)
			for id in [10,11,18,19]:
				for i in range(editor._definitions.size()):
					if editor._definitions[i].posture_id==id:editor._select_pose(i);break
				editor._joint_chosen("paddle")
				for stage in range(3):
					editor._select_stage(stage);await frames();bounded("%s expanded=%s stroke=%d stage=%d"%[resolution,expanded,id,stage])
			editor._select_workspace(2)
			for i in range(editor._definitions.size()):
				editor._select_pose(i);editor._joint_chosen("paddle")
				for stage in range(3):
					editor._select_stage(stage);await frames();bounded("%s expanded=%s serve=%d stage=%d"%[resolution,expanded,i,stage])
	var preview=editor._preview
	preview._orbit(Vector2(12,-8));var yaw:float=preview.yaw;var pitch:float=preview.pitch
	editor._set_scene_expanded(false);await frames()
	check(is_equal_approx(preview.yaw,yaw) and is_equal_approx(preview.pitch,pitch),"layout fit preserves orbit orientation")
	preview.zoom(-.1);var distance:float=preview.distance;var camera:Transform3D=preview.camera.transform
	editor._set_scene_expanded(true);await frames()
	check(preview._manual_zoom and is_equal_approx(preview.distance,distance) and preview.camera.transform.is_equal_approx(camera),"deliberate zoom is not overridden by a resize")
	preview.view("reset");await frames();bounded("Reset view restores safe fitting")
	check(not preview._manual_zoom,"Reset view re-enables default fit")
	editor.close();await frames();game.queue_free();await frames()
	var file=FileAccess.open("res://results/mobile_scene_framing.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":report},"  "));file.close()
	print("MOBILE SCENE FRAMING: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
