extends SceneTree
## The selected-joint curve must use the displayed stroke context, not the
## independent editable-key ghosts. Drive both through the actual UI transport.
const Store=preload("res://scripts/mobile_pose_store.gd")
const Path=preload("res://scripts/stroke_swing_path.gd")
var game
var editor
var checks:=0
var failures:Array[String]=[]
var max_error:=0.0
var guide_rebuild_us:Array[int]=[]
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func same_points(a:PackedVector3Array,b:PackedVector3Array)->bool:
	if a.size()!=b.size():return false
	for i in range(a.size()):
		if a[i].distance_to(b[i])>.00002:return false
	return true
func same_curves(a:Dictionary,b:Dictionary)->bool:
	if a.size()!=b.size():return false
	for id in a:
		if not b.has(id) or not same_points(a[id],b[id]):return false
	return true
func frames(n:=2):
	for i in range(n):await process_frame
func select_id(id:int):
	for i in range(editor._definitions.size()):
		if editor._definitions[i].posture_id==id:editor._select_pose(i);return
	check(false,"pose exists %d"%id)
func phase_elapsed(progress:float)->float:
	var seq=editor._timeline.sequence
	if progress<=0:return seq.prefix_seconds
	if progress>=1:return seq.prefix_seconds+seq.stroke_seconds
	var a:float=seq.prefix_seconds
	var b:float=seq.prefix_seconds+seq.stroke_seconds
	for i in range(27):
		var m:float=(a+b)*.5
		if float(seq.sample(m).progress)<progress:a=m
		else:b=m
	return (a+b)*.5
func parity(label:String,dense:=false):
	var preview=editor._preview
	var cache:Dictionary=preview.context_joint_samples.duplicate(true)
	check(cache.size()==12,label+": all joint curves sampled")
	var rebuilds:int=preview.joint_context_rebuild_count
	var indices:Array=range(65) if dense else [0,1,8,16,24,32,40,48,56,63,64]
	for index in indices:
		var t:float=float(index)/64.0
		editor._timeline.elapsed=phase_elapsed(t)
		editor._timeline.active=true;editor._timeline._sample();editor._refresh_preview()
		for id in preview.JOINT_NAMES:
			var error:float=preview.joint_world_position(id).distance_to(cache[id][index])
			max_error=maxf(max_error,error)
			check(error<.00002,label+": %s sample %d parity %.9f"%[id,index,error])
	check(preview.joint_context_rebuild_count==rebuilds,label+": elapsed scrub reuses cache")
	var state:Transform3D=preview.player.paddle_node.global_transform
	var wrist:Transform3D=preview.player.right_arm_node.hand_mesh.global_transform
	var displayed:PostureDefinition=preview.pose
	preview._joint_context_motion_revision=-1
	var rebuild_start:=Time.get_ticks_usec()
	editor._timeline.refresh_joint_guide()
	guide_rebuild_us.append(Time.get_ticks_usec()-rebuild_start)
	check(preview.pose==displayed,label+": guide restores displayed pose identity")
	check(preview.player.paddle_node.global_transform.is_equal_approx(state),label+": guide leaves paddle XYZ/orientation intact")
	check(preview.player.right_arm_node.hand_mesh.global_transform.is_equal_approx(wrist),label+": guide leaves seated grip intact")
func configure(variant:int,motion:int,stance:int,mode:int=0):
	editor._stop();editor._variant_mode=variant;editor._variant=null;editor._motion_dirty=true
	editor._timeline._mode.select(mode);editor._timeline._motion.select(motion);editor._timeline._stance.select(stance);editor._timeline._signature=""
	editor._timeline._seek(1.0)
func run():
	create_timer(240,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://pose_store_tests/joint_runtime_%d.json"%OS.get_process_id())
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(4)
	root.get_node("PauseController").open();game.open_mobile_pose_editor();await frames(4);editor=game.mobile_pose_editor
	select_id(0);editor._joint_chosen("right_elbow")
	var original:Dictionary=Store._encode_fields(editor._current)
	var authored:Dictionary=editor._preview.joint_samples.duplicate(true)
	var heads:PackedVector3Array=editor._preview.sample_heads.duplicate()
	for variant in range(3):
		for motion in range(2):
			for stance in range(3):
				configure(variant,motion,stance)
				parity("forehand variant%d motion%d stance%d"%[variant,motion,stance],variant==0 and motion==0 and stance==0)
				check(Store._encode_fields(editor._current)==original,"guide never edits authored pose")
	configure(0,0,0)
	check(same_curves(editor._preview.joint_samples,authored) and same_points(editor._preview.sample_heads,heads),"runtime overlay preserves authored ghosts and paddle arc")
	var runtime_cache:Dictionary=editor._preview.context_joint_samples.duplicate(true)
	var rebuilds:int=editor._preview.joint_context_rebuild_count
	for id in ["left_elbow","head","paddle","right_elbow"]:editor._preview.select_joint(id)
	editor._preview.yaw+=.2;editor._preview.update_camera()
	check(editor._preview.joint_context_rebuild_count==rebuilds,"selection/camera reuse runtime joint cache")
	editor._scrubbed(.25)
	check(editor._preview.context_joint_samples.is_empty() and same_points(editor._preview.selected_joint_samples,authored.right_elbow),"authored scrub restores original guide")
	for stage in range(3):
		editor._select_stage(stage)
		check(not editor._timeline.active and same_points(editor._preview.selected_joint_samples,authored.right_elbow),"editable stage uses authored curve")
		check(editor._preview.joint_world_position("right_elbow").distance_to(authored.right_elbow[stage*32])<.00002,"editable stage ring remains authored key")
	configure(0,0,0,1)
	editor._timeline._seek(0.0)
	check(same_curves(editor._preview.context_joint_samples,runtime_cache),"charging preserves stroke-only phase cache")
	editor._timeline._seek(1.0)
	check(same_curves(editor._preview.context_joint_samples,runtime_cache),"recovery preserves stroke-only phase cache")
	var panel=editor._elbow_preset_panel
	panel.smooth();await frames(3)
	check(panel.busy() and panel.candidate==null and panel.smooth_button.disabled and not panel.cancel_button.disabled,"busy search status has no unaccepted candidate")
	check(same_curves(editor._preview.context_joint_samples,runtime_cache),"busy search preserves displayed stroke curve")
	panel.cancel()
	while panel.busy():await process_frame
	check(panel.candidate==null and same_curves(editor._preview.context_joint_samples,runtime_cache),"cancel preserves original stroke curve")
	# A real persisted accepted fixture verifies candidate admission, applied and
	# undone routes. Forehand itself remains manual-needed; no invented bake.
	select_id(18);editor._joint_chosen("right_elbow");configure(0,0,0)
	var original18:Dictionary=Store._encode_fields(editor._current)
	var source_curve:Dictionary=editor._preview.context_joint_samples.duplicate(true)
	var baked:PostureDefinition=editor._current.duplicate(true)
	baked.elbow_preset_bake=JSON.parse_string(FileAccess.get_file_as_string("res://results/mobile-elbow-case18-bake.json"))
	panel._begin()
	panel._completed({"valid":true,"pose":baked,"active_sides":baked.elbow_preset_bake.active_sides,"angle_deg":0.0,"scope":"Runtime stroke only"},panel.generation)
	if str(baked.elbow_preset_bake.source_sha256)!=Store.authored_fingerprint(baked,"stroke_runtime"):
		# A fixture certified for an earlier orientation sampler is retained as
		# valid historical data, but must never be relabelled as newly certified.
		check(panel.candidate==null and not panel.pending,"earlier orientation-model fixture is rejected as stale")
		check(editor._current.elbow_preset_bake.is_empty(),"stale candidate leaves authored pose intact")
		parity("stale bake preserves original guide",true)
		check(not bool(editor._preview.player.get_meta("elbow_preset_report",{}).get("applied",false)),"stale bake does not reach actual rig")
	else:
		check(panel.candidate!=null and panel.pending,"real validated fixture admitted")
		check(Store._encode_fields(editor._current)==original18,"accepted Preview retains source")
		check(editor._timeline._mode.selected==0 and not editor._preview.pose.has_meta("elbow_preset_sample"),"candidate acceptance keeps full Play original")
		check(same_curves(editor._preview.context_joint_samples,source_curve),"full Play guide remains original with accepted candidate")
		configure(0,0,0,4)
		parity("accepted stroke-only diagnostic bake",true)
		check(bool(editor._preview.player.get_meta("elbow_preset_report",{}).get("applied",false)),"accepted bake actually applied to live rig")
		check(not same_curves(editor._preview.context_joint_samples,source_curve),"accepted guide reflects actual smoothed elbow")
		var accepted_curve:Dictionary=editor._preview.context_joint_samples.duplicate(true)
		panel._begin();panel._completed({"valid":false,"status":"test: no new feasible route"},panel.generation)
		check(panel.candidate!=null and same_curves(editor._preview.context_joint_samples,accepted_curve),"failed replacement retains accepted curve")
		check(panel.status.text.contains("Manual adjustment needed"),"failed search remains explicitly manual-needed")
		panel.preview_button.set_pressed_no_signal(false);panel._toggle_preview()
		check(same_curves(editor._preview.context_joint_samples,source_curve),"Preview off returns original guide")
		panel.preview_button.set_pressed_no_signal(true);panel._toggle_preview();panel.apply_preview()
		parity("applied bake",true)
		panel.undo_apply();parity("undo original")
		check(same_curves(editor._preview.context_joint_samples,source_curve),"Undo returns original guide")
		check(editor._current.elbow_preset_bake.is_empty(),"Undo returns original bake")
		panel.preview_button.set_pressed_no_signal(true);panel._toggle_preview();panel.apply_preview();panel.source_selected();configure(0,0,0,4)
		check(panel.candidate==null and not editor._current.elbow_preset_bake.is_empty(),"saved source reopening has no pending candidate")
		parity("saved bake reopening")
		check(bool(editor._preview.player.get_meta("elbow_preset_report",{}).get("applied",false)),"saved source bake actually applied in explicit diagnostic")
		configure(0,0,0,1);parity("saved core bake refused throughout full Play")
		check(not editor._preview.pose.has_meta("elbow_preset_sample") and same_curves(editor._preview.context_joint_samples,source_curve),"saved full Play and guide remain original")
	editor._changed("crouch_amount",float(editor._edit.crouch_amount)+.01)
	check(editor._current.elbow_preset_bake.is_empty() and panel.candidate==null,"manual edit clears stale saved route")
	configure(0,0,0);parity("manual source edit")
	editor._select_workspace(2)
	for index in range(editor._definitions.size()):
		editor._select_pose(index);editor._joint_chosen("right_elbow")
		configure(0,0,0);parity("serve style%d"%index)
	for variant in [1,2]:
		configure(variant,0,0);parity("serve variant%d"%variant)
	print("MOBILE RUNTIME JOINT GUIDE: %d checks, %d failures, max error %.9f m"%[checks,failures.size(),max_error])
	var file=FileAccess.open("res://results/runtime-joint-guide.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"max_error_m":max_error,"guide_rebuild_us":guide_rebuild_us},"  "));file.close()
	game.queue_free();await frames();quit(0 if failures.is_empty() else 1)
