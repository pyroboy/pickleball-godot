extends SceneTree
## Scene-space layout contract. Isolated saves, no service search or live pose mutation.
const Store=preload("res://scripts/mobile_pose_store.gd")
var game
var editor
var failures:Array[String]=[]
var checks:=0
var report:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for i in range(count):await process_frame
func bounded(tag:String)->void:
	var viewport:Rect2=root.get_visible_rect()
	for control in [editor._preview,editor._play,editor._scrub,editor._phase,editor._timeline._slider,editor._scene_focus,editor._tools_toggle,editor._save,editor._copy_action,editor._copy_action.get_parent().get_child(2),editor._status]:
		check(viewport.encloses(control.get_global_rect()),tag+": pinned control fits "+str(control.text if control is Button else control.get_class()))
	check(not editor._preview.get_global_rect().intersects(editor._scene_focus.get_global_rect()),tag+": scene and drawer do not overlap")
	check(editor._visual_scroll.get_v_scroll_bar().max_value<=editor._visual_scroll.get_v_scroll_bar().page+.1,tag+": scene is never scrolled away")
	for control in [editor._scene_focus,editor._tools_toggle,editor._play,editor._save,editor._fine_button]:
		check(control.size.y>=72*editor._s,tag+": touch height preserved")
	report[tag]={"preview":str(editor._preview.get_global_rect()),"save":str(editor._save.get_global_rect()),"inspector":str(editor._scroll.get_global_rect()),"tools":str(editor._tools_scroll.get_global_rect())}
func run()->void:
	create_timer(120,true).timeout.connect(func():quit(2))
	check(Store.set_test_path("user://pose_store_tests/scene_space_%d/poses.json"%Time.get_ticks_usec())==OK,"save is isolated")
	var pause=root.get_node("PauseController")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await frames();pause.open();game.open_mobile_pose_editor();await frames(8)
	editor=game.mobile_pose_editor;editor._select_pose(0);editor._select_category(2)
	var source:Dictionary=Store._encode_fields(editor._current)
	var initial_nodes:int=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for resolution in [Vector2i(720,1560),Vector2i(720,1280),Vector2i(720,1200),Vector2i(600,960),Vector2i(1080,2340),Vector2i(1280,800)]:
		root.content_scale_size=resolution;root.size=resolution;await frames(8)
		editor._set_scene_expanded(false);editor._show_preview_tools(false);await frames(8)
		var tag:String=str(resolution)
		bounded(tag+" manual")
		var regular:float=editor._preview.size.y
		check(editor._scroll.visible and editor._category.is_visible_in_tree() and editor._fine_button.is_visible_in_tree(),tag+": manual inspector remains available")
		if resolution.y>resolution.x:check(regular>=resolution.y*.30,tag+": scene is at least 30 percent high")
		editor._show_preview_tools(true);await frames(8);bounded(tag+" tools")
		check(editor._tools_scroll.visible and not editor._scroll.visible,tag+": tools replace inspector only")
		editor._elbow_preset_panel.details_button.button_pressed=true;editor._view_toggle.button_pressed=true;await frames(8);bounded(tag+" details")
		check(editor._tools_scroll.get_v_scroll_bar().visible,tag+": long tools scroll above pinned Save")
		check(editor._preview.size.y>=regular-.1,tag+": expanded tools do not shrink scene")
		editor._set_scene_expanded(true);await frames(8);bounded(tag+" focus")
		check(not editor._scroll.visible and not editor._tools_scroll.visible and not editor._picker_row.visible,tag+": focus folds controls")
		if resolution.y>resolution.x:check(editor._preview.size.y>regular*1.5,tag+": focus adds at least 50 percent height")
		editor._show_preview_tools(true);await frames(8)
		check(not editor._expanded_scene and editor._tools_scroll.visible,tag+": tools reopen directly from focus")
		editor._show_preview_tools(false);await frames(8)
		check(editor._scroll.visible and editor._category.selected==2,tag+": selected group is retained")
		check(Store._encode_fields(editor._current)==source and editor._dirty.is_empty(),tag+": view changes never edit pose")
		editor._elbow_preset_panel.details_button.button_pressed=false;editor._view_toggle.button_pressed=false
	root.content_scale_size=Vector2i(720,1200);root.size=Vector2i(600,1000);await frames(8)
	for i in range(4):
		editor._set_scene_expanded(true);await frames();editor._set_scene_expanded(false);await frames()
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)<=initial_nodes+2,"repeated layout modes allocate no extra scene or UI nodes")
	editor._toggle_play();await frames(3)
	var elapsed:float=editor._timeline.elapsed
	editor._set_scene_expanded(true);await frames(3)
	check(editor._playing and editor._timeline.elapsed>=elapsed,"focus preserves active playback")
	editor._toggle_play();editor._set_scene_expanded(false);await frames()
	editor._changed("body_yaw_deg",float(editor._edit.body_yaw_deg)+1);await frames()
	editor._set_scene_expanded(true);await frames();editor.close();await frames()
	check(editor._dialog.visible,"Back in focus protects unsaved changes")
	editor._hide_dialog();await frames();check(editor._expanded_scene,"Cancel returns to expanded scene")
	editor._copy_current_pose();await frames();check(editor._copy_layer.visible,"Copy is available in focus")
	editor._hide_copy();await frames();check(editor._expanded_scene,"Copy dismissal retains scene mode")
	editor._set_scene_expanded(false);editor._revert_current();await frames();editor.close();await frames(5)
	check(game.mobile_pose_editor==null and paused,"closing returns cleanly to Pause")
	game.open_mobile_pose_editor();await frames(8);editor=game.mobile_pose_editor
	check(not editor._expanded_scene and editor._scroll.visible and not editor._tools_scroll.visible,"reopen starts with manual controls visible")
	editor.close();await frames(5);game.queue_free();await frames()
	DirAccess.make_dir_recursive_absolute("res://results")
	var file=FileAccess.open("res://results/mobile_scene_space.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"layouts":report},"  "));file.close()
	print("MOBILE SCENE SPACE: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
