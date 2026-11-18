extends SceneTree
const Navigation = preload("res://scripts/tests/mobile_pose_test_navigation.gd")
## Copy-only UI: private unsaved data, context, modal Back, no persistence changes.
const Store=preload("res://scripts/mobile_pose_store.gd")
var checks:=0
var failures:Array[String]=[]
var game
var pause
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
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=down;root.push_input(event,true)
func payload(editor)->Dictionary:
	return JSON.parse_string(editor._copy_payload.substr(editor._copy_payload.find("{")))
func run()->void:
	create_timer(40,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://pose_store_tests/copy_ui_%d_%d/poses.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	pause=root.get_node("PauseController")
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(3)
	var baseline:int=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	check(game.mobile_pose_editor==null,"copy feature remains lazy while editor is off")
	pause.open();game.open_mobile_pose_editor();await frames(3)
	var e=game.mobile_pose_editor
	check(e._copy_layer==null,"copy text view allocated only on Copy")
	check(root.get_visible_rect().encloses(e._copy_action.get_global_rect()),"Copy button fits portrait header")
	var live:Resource=PostureLibrary.instance().get_def(0)
	var before:float=live.body_yaw_deg
	check(Store.save(live)==OK,"existing save fixture created")
	var saved_bytes:String=FileAccess.get_file_as_string(Store.storage_path())
	var paddle:Transform3D=game.player_left.paddle_node.global_transform
	var ball:Transform3D=game.ball.global_transform
	Navigation.select_field(e,"body_yaw_deg");e._select_stage(0);e._sliders.body_yaw_deg.value=before+7
	e._select_stage(2);e._sliders.weight_shift.value=.25
	e._select_stage(0);await frames()
	click(e._copy_action.get_global_rect().get_center());await frames(3)
	check(e._copy_layer.visible,"Copy button opens reviewable text fallback")
	check(e._copy_payload.begins_with("Pose: Forehand\nKind: Stroke pose\nSelected phase: Wind-up (context only)"),"copy header identifies exact pose and selected phase")
	check(e._copy_payload.contains("Whole selected pose, including Wind-up, Contact and Finish"),"whole selected pose scope is explicit")
	check(e._copy_payload.contains("This is the data of this pose. Update this pose and apply it to the app."),"copy includes user-requested chat instruction")
	var data:Dictionary=payload(e)
	check(data.schema=="pickleball.pose" and data.version==1 and data.scope=="whole_pose","portable schema and whole-pose version present")
	check(data.kind=="stroke" and int(data.id)==0 and int(data.selected_stage)==0,"portable identity and context correct")
	check(is_equal_approx(float(data.fields.windup_body.body_yaw_deg),before+7),"copy contains unsaved wind-up edit")
	check(is_equal_approx(float(data.fields.follow_through_body.weight_shift),.25),"copy includes unsaved finish keyframe too")
	check(live.body_yaw_deg==before and game.player_left.paddle_node.global_transform==paddle and game.ball.global_transform==ball,"Copy does not publish or mutate match geometry")
	check(FileAccess.get_file_as_string(Store.storage_path())==saved_bytes,"Copy leaves saved bytes unchanged")
	check(e._dirty.has(e._key),"Copy does not mark unsaved work saved")
	check(not e._copy_text.editable and not e._copy_text.virtual_keyboard_enabled,"copy text is selectable read-only data")
	e._copy_text.select_all();check(e._copy_text.get_selected_text()==e._copy_payload,"manual Select all includes complete chat payload")
	check(root.get_visible_rect().encloses(e._copy_box.get_global_rect()),"copy fallback fits tall portrait")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		# Verification reads only the synthetic data just copied by this test;
		# the production editor contains no clipboard-read call.
		check(DisplayServer.clipboard_get()==e._copy_payload,"system clipboard receives exact selected pose payload")
	else:check(e._copy_status.text.contains("Clipboard access is unavailable"),"unsupported clipboard gets visible fallback")
	back();await frames();check(is_instance_valid(game.mobile_pose_editor) and not e._copy_layer.visible,"native Back closes copy view before dirty editor")
	back();await frames();check(e._dialog.visible,"next Back still protects unsaved edits");back();await frames()
	e._select_workspace(1);Navigation.select_field(e,"crouch_amount");e._sliders.crouch_amount.value=.23;e._copy_current_pose();await frames()
	data=payload(e)
	check(data.kind=="base" and int(data.id)==0,"body stance copy exports only selected stance")
	check(e._copy_payload.contains("Kind: Body stance") and e._copy_payload.contains("Whole selected body stance"),"body stance header avoids stroke ambiguity")
	check(is_equal_approx(float(data.fields.crouch_amount),.23),"body stance unsaved edit copied")
	check(FileAccess.get_file_as_string(Store.storage_path())==saved_bytes,"body copy also leaves saved bytes unchanged")
	back();await frames()
	root.content_scale_size=Vector2i(720,1280);root.size=Vector2i(432,768);await frames(3)
	e._copy_current_pose();await frames(3)
	check(root.get_visible_rect().encloses(e._copy_box.get_global_rect()),"copy view fits short portrait")
	back();await frames()
	var previous:String=e._copy_payload
	e._current.crouch_amount=NAN;e._copy_current_pose()
	check(not e._copy_layer.visible and e._copy_payload==previous,"invalid export rejects without replacing prior copied data")
	check(e._status.text.begins_with("Could not copy pose:"),"invalid export gives visible error")
	check(FileAccess.get_file_as_string(Store.storage_path())==saved_bytes,"failed Copy does not touch disk")
	var source:String=FileAccess.get_file_as_string("res://scripts/ui/mobile_pose_editor.gd")
	check(not source.contains("clipboard_get") and not source.contains("clipboard_has("),"production UI never reads clipboard")
	check(not FileAccess.get_file_as_string("res://scripts/mobile_pose_store.gd").contains("func parse_pose_json"),"copy-only request adds no import API")
	e._finish_close();await frames(3);pause.close();await frames(3)
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)<=baseline+2,"copy text view frees with editor")
	game.queue_free();await frames()
	print("MOBILE POSE COPY UI: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
