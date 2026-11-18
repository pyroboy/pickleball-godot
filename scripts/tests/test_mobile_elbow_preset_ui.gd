extends SceneTree
## Actual mobile controls with deterministic service replies. This checks UI
## transactions/lifecycle only; solver and geometry validity have separate tests.
const Store=preload("res://scripts/mobile_pose_store.gd")
const Bake=preload("res://scripts/elbow_preset_bake.gd")
var checks:=0
var failures:Array[String]=[]
var game
var editor
var panel
var mock
class FakeService extends Node:
	signal completed(result:Dictionary)
	signal progress_changed(message:String)
	var busy:=false
	var calls:=0
	var cancelled:=0
	var held_cancel:=false
	var source:PostureDefinition
	var requested_side:=-1
	var requested_value:=Vector3.ZERO
	func start(value:PostureDefinition,_angle:bool)->void:
		calls+=1;source=value.duplicate(true);busy=true
	func request_offset(side:int,value:Vector3)->void:
		calls+=1;requested_side=side;requested_value=value;busy=true
	func reset_offsets()->void:
		calls+=1;requested_side=-1;requested_value=Vector3.ZERO;busy=true
	func cancel()->void:
		cancelled+=1
		if not held_cancel:busy=false
	func finish(result:Dictionary)->void:
		busy=false;completed.emit(result)
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func frames(count:int=2)->void:
	for i in range(count):await process_frame;await physics_frame
func fake_bake(value:PostureDefinition)->Dictionary:
	var transform:Array=[1,0,0,0,1,0,0,0,1,0,0,0]
	var sample:Dictionary={"p":0.0,"body":transform.duplicate(),"paddle":transform.duplicate(),"shoulders":[[0,0,0],[0,0,0]],"hands":[transform.duplicate(),transform.duplicate()],"elbows":[[0,0,0],[0,0,0]],"skin":[transform.duplicate(),transform.duplicate(),transform.duplicate()],"modes":["GRIP","FREE"],"weight":0.0}
	var end:=sample.duplicate(true);end.p=1.0
	return Bake.seal({"version":1,"model":Bake.MODEL_VERSION,"scope":"stroke_runtime","source_id":value.posture_id,"source_sha256":Store.authored_fingerprint(value,"stroke_runtime"),"handedness":value.paddle_hand,"active_sides":[true,false],"rotation_deg":[0,0,0],"offsets":[[0,0,0],[0,0,0]],"duration":maxf(.01,value.ft_duration_strike)+maxf(.01,value.ft_duration_sweep),"rig":{"links":[[.3,.3],[.3,.3]],"sockets":[[0,0,0],[0,0,0]],"anatomy":[[1,0,0,0,1,0,0,0,1],[1,0,0,0,1,0,0,0,1]]},"routes":[{"knots":[[0,0,0,0,1,0,1,0,0],[1,0,0,0,1,0,1,0,0]]},{}],"samples":[sample,end]})
func success(value:PostureDefinition,offset:Vector3=Vector3.ZERO)->Dictionary:
	var pose:PostureDefinition=value.duplicate(true);pose.elbow_preset_bake=fake_bake(value)
	pose.elbow_preset_bake.offsets[0]=[offset.x,offset.y,offset.z]
	pose.elbow_preset_bake=Bake.seal(pose.elbow_preset_bake)
	return {"valid":true,"status":"deterministic UI fixture","pose":pose,"active_sides":[true,false],"angle_deg":0.0,"offsets":[offset,Vector3.ZERO],"inherited_issues":["UI inherited support fixture"],"scope":"Runtime stroke only"}
func install_mock()->void:
	panel=editor._elbow_preset_panel
	panel.service.queue_free();mock=FakeService.new();panel.add_child(mock);panel.service=mock
	panel.source_selected()
func generate()->void:
	panel.smooth_button.pressed.emit()
	mock.finish(success(mock.source))
	await frames()
func review_mock()->void:
	# Explicitly mock only the geometry outcome for this UI-transaction suite.
	# Real application geometry and gates are tested by the separate rig suite.
	panel.preview_button.set_pressed_no_signal(true)
	editor._timeline._mode.select(4);editor._timeline._motion.select(0);editor._timeline._stance.select(0);editor._variant_mode=0
	editor._timeline._options_changed(4)
	editor._preview.player.set_meta("elbow_preset_report",{"applied":true,"status":"UI fixture only"})
	panel.refresh_controls()
func run()->void:
	create_timer(80,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://pose_store_tests/elbow_ui_%d_%d/poses.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(3)
	root.get_node("PauseController").open();game.open_mobile_pose_editor();await frames(3)
	editor=game.mobile_pose_editor;install_mock()
	var original:Dictionary=Store._encode_fields(editor._current)
	panel.smooth_button.pressed.emit()
	check(mock.calls==1 and mock.busy and not panel.cancel_button.disabled,"one click starts cancellable search")
	check(Store._encode_fields(editor._current)==original and editor._dirty.is_empty(),"search leaves editable source and dirty state untouched")
	check(mock.source!=editor._current,"service receives a deep clone")
	check(Bake.valid(fake_bake(mock.source)),"mock fixture meets persistence schema")
	mock.finish(success(mock.source));await frames()
	check(panel.candidate!=null and panel.pending and panel.apply_button.disabled,"validated reply stays unapplied until explicit diagnostic review")
	check(Store._encode_fields(editor._current)==original,"Preview remains a clone")
	check(editor._timeline.active and editor._timeline._mode.selected==0,"accepted result preserves selected full-action mode")
	check(panel.scope_hint.text.contains("full-animation rebake") and panel.scope_hint.text.contains("authored keys"),"full-action fallback and authored guide scopes are explicit")
	check(panel.status.text.contains("main: active") and panel.status.text.contains("support: inherited"),"active main and unchanged support are disclosed")
	panel.apply_preview();check(editor._current.elbow_preset_bake.is_empty(),"full-action Apply is refused without diagnostic review")
	check(not editor._preview.pose.has_meta("elbow_preset_sample"),"unapplied candidate cannot activate inside full Play")
	editor._timeline._mode.select(4);editor._timeline._options_changed(4)
	check(editor._preview.pose.has_meta("elbow_preset_sample") and panel.scope_hint.text.contains("diagnostic"),"explicit stroke-only diagnostic permits matching pending tag")
	check(panel.apply_button.disabled,"diagnostic fallback frame still cannot Apply an unseen correction")
	editor._timeline._mode.select(0);editor._timeline._options_changed(0)
	editor._timeline._seek(0);check(not editor._preview.pose.has_meta("elbow_preset_sample") and panel.scope_hint.text.contains("fallback"),"full-action selection clears candidate tag and reports fallback")
	panel.arm.select(1);panel.arm.item_selected.emit(1)
	check(not panel.axes[0].editable and panel.update_button.disabled,"inactive arm offsets disabled")
	panel.arm.select(0);panel.arm.item_selected.emit(0)
	panel.axes[0].value=3.0
	check(panel.apply_button.disabled,"unsubmitted guide request cannot silently Apply old candidate")
	panel.update_button.pressed.emit()
	check(mock.requested_side==0 and mock.requested_value==Vector3(.03,0,0),"XYZ centimeters passed as body-local meters")
	mock.finish(success(mock.source,Vector3(.03,0,0)));await frames()
	review_mock();panel.apply_button.pressed.emit()
	check(not editor._current.elbow_preset_bake.is_empty() and editor._dirty.has(editor._key) and not panel.pending,"Apply sets bake only on private editable pose")
	var baked:=Store._encode_fields(editor._current);var stripped:=baked.duplicate(true);stripped.elbow_preset_bake={}
	check(stripped==original,"Apply preserves every authored channel")
	panel.undo_button.pressed.emit()
	check(editor._current.elbow_preset_bake.is_empty() and panel.pending and not panel.preview_button.button_pressed,"Undo restores previous bake and shows restored source")
	review_mock();panel.apply_button.pressed.emit();editor._save_current()
	check(not editor._dirty.has(editor._key) and not editor._definitions[editor._pose_picker.selected].elbow_preset_bake.is_empty(),"normal Save persists applied bake")
	panel.undo_button.pressed.emit()
	check(editor._dirty.has(editor._key),"Undo after Save is an unsaved change")
	await generate()
	var retained:Dictionary=panel.candidate.elbow_preset_bake.duplicate(true)
	panel.smooth_button.pressed.emit();mock.finish({"valid":false,"status":"no route"})
	check(panel.candidate.elbow_preset_bake==retained and panel.status.text.contains("Manual adjustment needed"),"failed search retains candidate and explicit manual-needed status")
	panel.smooth_button.pressed.emit();var stale:int=panel.generation
	editor._changed("crouch_amount",float(editor._edit.crouch_amount)+.01)
	panel._completed(success(mock.source),stale)
	check(panel.candidate==null and editor._current.elbow_preset_bake.is_empty() and panel.undo_history.is_empty(),"manual edit cancels stale result, bake and old Undo")
	panel.smooth_button.pressed.emit();stale=panel.generation;panel.cancel_button.pressed.emit();panel._completed(success(mock.source),stale)
	check(panel.candidate==null and not mock.busy,"Cancel prevents stale result acceptance")
	panel.smooth_button.pressed.emit();stale=panel.generation;editor._select_pose(1);panel._completed(success(mock.source),stale)
	check(panel.candidate==null and not panel.pending,"pose switch discards stale candidate")
	panel.smooth_button.pressed.emit();stale=panel.generation;editor._select_stage(0);panel._completed(success(mock.source),stale)
	check(panel.candidate==null and editor._stage==0 and not editor._timeline.active,"new key selection cannot be reset by stale completion")
	panel.smooth_button.pressed.emit();stale=panel.generation;editor._play_variant(1);panel._completed(success(mock.source),stale)
	check(panel.candidate==null and editor._variant_mode==1,"new variant cannot be reset by stale completion")
	editor._clear_variant();editor._stop()
	panel.smooth_button.pressed.emit();stale=panel.generation;editor._timeline._stance.select(1);editor._timeline._options_changed(1);panel._completed(success(mock.source),stale)
	check(panel.candidate==null and editor._timeline._stance.selected==1,"new timeline options cannot be reset by stale completion")
	panel.smooth_button.pressed.emit();stale=panel.generation;editor._timeline._seek(.35);var seeked:float=editor._timeline.elapsed;panel._completed(success(mock.source),stale)
	check(panel.candidate==null and is_equal_approx(editor._timeline.elapsed,seeked),"new timeline seek cannot be reset by stale completion")
	await generate()
	var old_calls:int=mock.calls;editor._current.crouch_amount+=.01
	check(panel.preview_source(editor._current)==editor._current,"unhooked source edit cannot display old authored candidate")
	panel.update_offset();check(mock.calls==old_calls and panel.candidate==null,"offset rejects candidate from an unhooked changed source")
	await generate();old_calls=mock.calls;editor._current.crouch_amount+=.01
	panel.reset_offsets();check(mock.calls==old_calls and panel.candidate==null,"reset rejects candidate from an unhooked changed source")
	panel.smooth_button.pressed.emit();var wrong_source:PostureDefinition=mock.source.duplicate(true);wrong_source.crouch_amount+=.02;mock.finish(success(wrong_source))
	check(panel.candidate==null and panel.status.text.contains("Stale smoothing result rejected"),"result bake source fingerprint is validated before acceptance")
	await generate();editor._current.crouch_amount+=.01;review_mock();panel.apply_preview()
	check(editor._current.elbow_preset_bake.is_empty(),"Apply rejects direct unhooked source mutation")
	panel.source_selected();await generate();review_mock();panel.apply_preview()
	var saved_bake:Dictionary=editor._current.elbow_preset_bake.duplicate(true)
	editor._current.crouch_amount+=.01;panel.source_selected()
	check(panel.status.text.contains("stale / inactive") and editor._current.elbow_preset_bake==saved_bake,"opening stale smoothing discloses fallback without mutating saved bake")
	for workspace in range(3):
		editor._select_workspace(workspace)
		for index in range(editor._definitions.size()):
			editor._select_pose(index)
			check(editor._current!=null,"all selectable poses retained %d/%d"%[workspace,index])
			if workspace!=0 or editor._current.posture_id==20:check(panel.smooth_button.disabled and not panel.status.text.is_empty(),"unsupported contexts explicitly unavailable %d/%d"%[workspace,index])
	editor._select_workspace(0);await generate()
	root.size=Vector2i(432,768);root.content_scale_size=Vector2i(720,1280);editor._layout();await frames(4)
	check(root.get_visible_rect().encloses(editor._save.get_global_rect()) and editor._scroll.size.y>=120,"expanded smoothing keeps short-portrait Save and inspector reachable")
	mock.held_cancel=true;panel.smooth_button.pressed.emit();editor._finish_close();await frames()
	check(is_instance_valid(game.mobile_pose_editor) and editor._closing,"close waits while cancelled worker is still busy")
	mock.busy=false;await frames(3)
	check(game.mobile_pose_editor==null,"close completes after worker settles")
	game.queue_free();await frames()
	print("MOBILE ELBOW PRESET UI: %d checks, %d failures (mock service; no solver-quality claim)"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
