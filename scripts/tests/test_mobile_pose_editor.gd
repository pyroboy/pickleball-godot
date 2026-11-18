extends SceneTree
const Navigation = preload("res://scripts/tests/mobile_pose_test_navigation.gd")
const Store=preload("res://scripts/mobile_pose_store.gd")
var checks:=0
var failures:Array[String]=[]
var game
var pause
var editor
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func frames(n:int=2)->void:
	for i in range(n):await process_frame;await physics_frame
func back()->void:
	pause._last_back_msec=-1000;root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
func click(point:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=point;e.pressed=down;root.push_input(e,true)
func check_field_value(desc:Dictionary,axis:int,authored:Resource)->void:
	var field:String=desc.field
	Navigation.select_field(editor,field)
	var key:String=field if axis<0 else field+":"+str(axis)
	var value:float=float(editor._edit.get(field)) if axis<0 else float(editor._edit.get(field)[axis])
	var original:float=float(authored.get(field)) if axis<0 else float(authored.get(field)[axis])
	if editor._sliders.has(key):
		check(absf(editor._sliders[key].value-value)<=float(desc.step)*.51,"slider preserves authored value: "+key)
		return
	var reason:String=editor._inactive_control_reason(field,axis)
	var allowed:bool=(axis==1 and field in ["right_foot_offset","left_foot_offset"] and reason=="Height locked to the court floor.") or (axis<0 and field=="swing_path_blend" and reason=="Two-hand Backhand uses a linked body-frame path.")
	if axis<0 and field in ["split_step_hop_height","lunge_distance"]:
		allowed=reason=="Inactive in the current motion system."
	if axis<0 and editor._base:
		var states:Dictionary={"recovery_time":editor._preview.player.BasePoseState.RECOVERY_READY,"landing_lockout_time":editor._preview.player.BasePoseState.LANDING_RECOVERY,"jump_window":editor._preview.player.BasePoseState.JUMP_TAKEOFF}
		if states.has(field):allowed=editor._current.base_pose_id!=states[field] and reason=="Used only by the corresponding recovery / landing / takeoff stance."
	check(allowed,"only intentionally constrained fields omit sliders: "+key)
	var explanation_visible:bool=false
	for label in editor._fields.find_children("*","Label",true,false):
		if not reason.is_empty() and label.text.contains(reason):explanation_visible=true
	check(explanation_visible,"inactive field has visible explanation: "+key)
	check(is_equal_approx(value,original),"inactive field retains exact authored value: "+key)
func run()->void:
	create_timer(40,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://pose_store_tests/editor_%d/poses.json"%OS.get_process_id())
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	pause=root.get_node("PauseController")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await frames(3)
	check(game.mobile_pose_editor==null and game.posture_editor_v2==null,"no mobile or desktop editor allocated while off")
	var baseline:int=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	pause.open();await frames();check(paused,"pause entered")
	var pose_button:Button=pause._menu._pose_button
	click(pose_button.get_global_rect().get_center());await frames()
	editor=game.mobile_pose_editor
	check(is_instance_valid(editor),"Pause → Pose Editor button opens editor")
	if not is_instance_valid(editor):quit(1);return
	check(root.get_visible_rect().encloses(editor._save.get_global_rect()) and root.get_visible_rect().encloses(editor._status.get_global_rect()),"save and status fit portrait viewport")
	var initial_paddle:Transform3D=editor._preview.player.paddle_node.global_transform
	editor._preview.show_pose(editor._preview.pose)
	check(editor._preview.player.paddle_node.global_transform.is_equal_approx(initial_paddle),"deferred body setup preserves initial preview paddle pose")
	check(editor._preview.player!=game.player_left,"preview uses isolated player")
	check(editor._preview.viewport.find_world_3d()!=root.find_world_3d(),"preview has isolated world")
	check(editor._preview.player.posture.editor_preview_mode,"preview uses actual pose/IK pipeline")
	check(not editor._preview.player.is_physics_processing(),"preview player physics disabled")
	check(root.get_node("McpBridge").udp_server==null,"editor does not start developer bridge")
	check(editor._preview.player.awareness_grid==null and editor._preview.player.posture.posture_ghost_root==null,"editor does not create developer geometry")
	for workspace_index in range(2):
		editor._select_workspace(workspace_index)
		for def_index in range(editor._definitions.size()):
			editor._select_pose(def_index)
			for group in range(6):
				var authored:Resource=editor._edit.duplicate(true)
				for desc in editor.Fields.fields(group,workspace_index==1):
					if editor._edit.get(desc.field)==null:continue
					check((editor._edit.get(desc.field) is Vector3)==(desc.type=="vector"),"correct inspector scalar/vector schema: "+desc.field)
					if desc.type=="float":check_field_value(desc,-1,authored)
					elif desc.type=="vector":
						for axis in range(3):check_field_value(desc,axis,authored)
			await process_frame
	editor._select_workspace(0);Navigation.select_field(editor,"body_yaw_deg");await frames()
	for picker in [editor._workspace,editor._pose_picker,editor._category]:
		picker.show_popup();await process_frame;back();await process_frame
		check(is_instance_valid(game.mobile_pose_editor) and not picker.get_popup().visible,"Android Back dismisses dropdown before editor")
	editor._play.pressed.emit();editor._last_tick-=100000;editor._process(0.0)
	check(editor._playing and editor._timeline.elapsed>0 and editor._timeline.sample.phase.begins_with("Charging") and paused,"Play advances private motion while match stays paused")
	editor._select_stage(1)
	var root_pos:Vector3=game.player_left.global_position
	var paddle:Transform3D=game.player_left.paddle_node.global_transform
	var ball:Transform3D=game.ball.global_transform
	var time:float=Engine.time_scale
	var live:Resource=PostureLibrary.instance().get_def(0)
	var original:float=live.body_yaw_deg
	# A body category now selects its gizmo; hide it before testing camera-only drag.
	if editor._gizmo_show.button_pressed:
		editor._gizmo_show.button_pressed=false;editor._toggle_gizmo()
	var camera_before:Transform3D=editor._preview.camera.transform
	var drag:=InputEventScreenDrag.new();drag.index=5;drag.relative=Vector2(50,10);drag.position=editor._preview.get_global_rect().get_center()
	var touch:=InputEventScreenTouch.new();touch.index=5;touch.position=drag.position;touch.pressed=true
	root.push_input(touch,true);root.push_input(drag,true);touch.pressed=false;root.push_input(touch,true);await frames()
	check(editor._preview.camera.transform!=camera_before,"touch drag orbits preview")
	check(game.player_left.global_position==root_pos and game.player_left.paddle_node.global_transform==paddle and game.ball.global_transform==ball,"camera touch leaves live match geometry unchanged")
	editor._sliders.body_yaw_deg.value=original+5;await frames()
	check(editor._dirty.has(editor._key) and editor._preview.pose.body_yaw_deg==original+5,"joint slider changes actual preview pose")
	check(live.body_yaw_deg==original,"unsaved slider leaves live definition unchanged")
	back();await frames();check(root.get_visible_rect().encloses(editor._dialog_box.get_global_rect()),"dirty confirmation fits portrait viewport");check(is_instance_valid(game.mobile_pose_editor) and editor._dialog.visible,"Android Back asks about dirty edits")
	back();await frames();check(not editor._dialog.visible and paused,"second Back keeps editing")
	editor._save_current();await frames()
	check(live.body_yaw_deg==original+5 and editor._dirty.is_empty(),"save publishes live values after persistence")
	check(PostureLibrary.new().get_def(0).body_yaw_deg==original+5,"saved editor values reload")
	editor._select_stage(0);editor._sliders.body_yaw_deg.value=original+12
	check(editor._current.windup_body!=null and editor._current.windup_body.values.body_yaw_deg==original+12,"wind-up body keyframe editable")
	check(editor._preview.pose.body_yaw_deg==original+12,"wind-up sampler previews keyframe")
	editor._select_stage(2);editor._sliders.body_yaw_deg.value=original-8
	check(editor._preview.pose.body_yaw_deg==original-8,"finish sampler previews keyframe")
	editor._scrub.value=.5;check(editor._preview.pose.body_yaw_deg==original+5,"scrub passes exact contact")
	editor._select_workspace(1);Navigation.select_field(editor,"crouch_amount");editor._sliders.crouch_amount.value=.2
	check(editor._preview.pose.crouch_amount==.2,"base stance joint preview works")
	editor._request_revert();check(editor._dialog.visible,"revert requires confirmation");editor._revert_current()
	check(not editor._dirty.has(editor._key),"revert discards selected unsaved copy")
	editor._select_workspace(0);editor._request_default();check(editor._dialog.visible,"default requires confirmation");editor._reset_default()
	check(live.body_yaw_deg==original and PostureLibrary.new().get_def(0).body_yaw_deg==original,"default restores packaged pose and persists reset")
	# Saved body stances must reach the controllers' separate runtime libraries.
	var controller=game.player_left.pose_controller
	var old_cached=controller.compose_runtime_posture()
	editor._select_workspace(1);Navigation.select_field(editor,"crouch_amount");editor._sliders.crouch_amount.value=.23;editor._save_current()
	back();await frames(3)
	check(controller._library.get_def(0).crouch_amount==.23,"saved base stance reaches player runtime library")
	check(controller._composed_pose_cache==null,"successful close invalidates composed runtime pose cache")
	check(game.mobile_pose_editor==null and paused and pause._menu.visible,"clean Back frees editor and returns to Pause")
	check(game.player_left.paddle_node.global_transform==paddle and Engine.time_scale==time,"editor exit preserves live grip and pause time scale")
	for repetition in range(3):
		pause._menu._on_pose_editor();await frames();game.open_mobile_pose_editor()
		check(game.find_children("MobilePoseEditor","",false,false).size()==1,"repeat open creates one editor")
		back();await frames(3)
	root.content_scale_size=Vector2i(720,1280);root.size=Vector2i(432,768)
	pause._menu._on_pose_editor();await frames(4)
	check(root.get_visible_rect().encloses(game.mobile_pose_editor._save.get_global_rect()) and root.get_visible_rect().encloses(game.mobile_pose_editor._status.get_global_rect()),"short portrait retains save and status")
	check(game.mobile_pose_editor._scroll.size.y>=120,"short portrait retains scrollable touch inspector")
	back();await frames(3)
	pause.close();await frames(3)
	var after:int=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	check(after<=baseline+2,"closing editor returns to baseline node count (%d vs %d)"%[after,baseline])
	check(not paused and not Input.is_action_pressed("ui_accept"),"resume leaves no ghost hit input")
	# Committed serve survives editing without reinitializing the live charge/swing owner.
	game._perform_serve(.6);await frames(1);pause.open();await frames()
	var serve_state:int=game.game_state;var serve_position:Vector3=game.ball.global_position
	var charge:float=game.game_serve.get_charge_ratio()
	pause._menu._on_pose_editor();await frames(4)
	check(game.game_state==serve_state and game.ball.global_position==serve_position and game.game_serve.get_charge_ratio()==charge,"committed serve is frozen during editor")
	pause._notification(Node.NOTIFICATION_APPLICATION_PAUSED);pause._notification(Node.NOTIFICATION_APPLICATION_RESUMED);await frames()
	check(paused and is_instance_valid(game.mobile_pose_editor),"background/resume preserves editor and manual pause")
	back();await frames();pause.close();await frames()
	check(not paused,"committed serve can resume")
	game.queue_free();await frames()
	print("MOBILE POSE EDITOR: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
