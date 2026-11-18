extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Styles = preload("res://scripts/paddle_grip_styles.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
var checks:=0
var failures:Array[String]=[]
var game
var editor
var pause
var capture:=false
var output:="/workspace/scratch/6b6e64f75bd2/verification/paddle-gimbal"
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(n:int=3)->void:
	for i in range(n):await process_frame
func select_id(id:int)->void:
	for i in range(editor._definitions.size()):
		if editor._definitions[i].posture_id==id:editor._select_pose(i);return
	check(false,"pose exists")
func snap(name:String)->void:
	await frames(5)
	var bounds:=root.get_visible_rect()
	check(bounds.encloses(editor._preview.get_global_rect()),name+": preview fits")
	check(bounds.encloses(editor._scroll.get_global_rect()),name+": controls fit")
	check(bounds.encloses(editor._save.get_global_rect()),name+": save fits")
	if capture:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,name+": screenshot")
func run()->void:
	create_timer(120,true).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	check(Store.set_test_path("user://pose_store_tests/gimbal_%d/poses.json"%OS.get_process_id())==OK,"isolated pose save")
	check(GripStore.set_test_path("user://pose_store_tests/gimbal_%d/grips.json"%OS.get_process_id())==OK,"isolated global grip save")
	check(ServeStore.set_test_path("user://pose_store_tests/gimbal_%d/serves.json"%OS.get_process_id())==OK,"isolated serve save")
	root.size=Vector2i(432,936);root.content_scale_size=Vector2i(720,1560)
	pause=root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited):root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered):root.focus_entered.disconnect(pause._on_window_focus_entered)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(4)
	pause.open();game.open_mobile_pose_editor();await frames(4);editor=game.mobile_pose_editor
	select_id(0);editor._group.select(4);editor._build_fields();await frames()
	check(is_instance_valid(editor._gimbal),"gimbal available for stroke")
	check(editor._gimbal.size.y>=280*editor._s,"large on-panel gimbal")
	check(editor._angle_inputs.size()==3,"three editable angle inputs")
	var before_other:Resource=PostureLibrary.instance().get_def(1).duplicate(true)
	for stage in range(3):
		editor._select_stage(stage)
		var other_endpoints:Array=[]
		for i in range(3):other_endpoints.append(Path.endpoint(editor._current,i))
		for axis in range(3):
			for value in [721.2,-1081.5,10080.2,-10080.7,179.9,180.1]:
				editor._angle_inputs[editor.ROT[axis]].value=value
				await frames(2)
				var expected:=wrapf(value,-180,180)
				check(is_equal_approx(float(editor._edit.get(editor.ROT[axis])),expected),"unrestricted numeric wraps axis%d stage%d value%f"%[axis,stage,value])
				check(is_equal_approx(editor._sliders[editor.ROT[axis]].value,expected),"slider synchronized")
				check(is_equal_approx(editor._gimbal.angles[axis],expected),"gimbal synchronized")
				check(editor._preview.player.paddle_node.global_transform.is_finite(),"actual paddle finite")
		for other in range(3):
			if other==stage:continue
			var now:Resource=Path.endpoint(editor._current,other)
			for field in editor.POS+editor.ROT:check(is_equal_approx(float(now.get(field)),float(other_endpoints[other].get(field))),"other key transform preserved "+field)
		# Cross seam by actual ring gesture rather than invoking mutation callback.
		var dial=editor._gimbal;var a:=float(editor._edit.paddle_pitch_base_deg)
		dial._begin(dial.ring_point(0,179));dial._move(dial.ring_point(0,181));dial.cancel_gesture();await frames(2)
		check(absf(wrapf(editor._edit.paddle_pitch_base_deg-a-2,-180,180))<.001,"ring crossing has continuous 2deg delta")
	check(Store.export_pose_json(before_other)==Store.export_pose_json(PostureLibrary.instance().get_def(1)),"other live pose unchanged")
	for side in range(2):
		editor._preview.player.player_num=side
		for hand in range(2):
			for stage in range(3):
				editor._select_stage(stage);editor._changed("paddle_hand",hand)
				editor._changed("body_yaw_deg",60.0 if side==0 else -60.0)
				for direction in range(2):
					editor._lag_direction=direction
					var target:Vector3=editor._wrist_lag_direction()
					var frame:Transform3D=Path.world_transform(editor._preview.player,editor._edit)
					var wrist:Vector3=Wrist.wrist_world(frame,editor._edit)
					var grip:float=editor._edit.paddle_in_hand_rotation_deg
					editor._apply_wrist_lag();await frames()
					var after:Transform3D=Path.world_transform(editor._preview.player,editor._edit)
					check(after.basis.y.dot(target)>.9999,"Wrist Lag aims top backward both court sides/hands/stages")
					check(Wrist.wrist_world(after,editor._edit).distance_to(wrist)<.00002,"Wrist Lag retains seated wrist")
					check(is_equal_approx(editor._edit.paddle_in_hand_rotation_deg,grip),"Wrist Lag leaves in-hand grip untouched")
	editor._preview.player.player_num=0
	editor._save_current();check(not editor._dirty.has(editor._key),"save succeeds")
	var live:Resource=PostureLibrary.new().get_def(0)
	check(Store.export_pose_json(live)==Store.export_pose_json(editor._current),"gimbal transform reloads exactly")
	editor._set_paddle_angle(0,9876);await frames();editor._reset_field(editor.ROT[0],-1);await frames()
	check(is_equal_approx(editor._edit.paddle_pitch_base_deg,Path.endpoint(live,editor._stage).paddle_pitch_base_deg),"per-angle saved reset")
	editor._reset_default();editor._select_stage(1);editor._joint_chosen("paddle")
	check(editor._sliders.has("contact_curve"),"Contact curve control is visible in paddle panel")
	var curve_keys:Array=[]
	for key_t in [0.0,.5,1.0]:curve_keys.append(Path.sample(editor._current,key_t).resolve_paddle_offset(Vector3.RIGHT,Vector3.FORWARD))
	for curve in [0.0,1.0,.5]:
		editor._sliders.contact_curve.value=curve;await frames()
		check(is_equal_approx(editor._current.contact_curve,curve),"Contact curve slider changes actual motion setting")
		for key_index in range(3):check(Path.sample(editor._current,float(key_index)*.5).resolve_paddle_offset(Vector3.RIGHT,Vector3.FORWARD).is_equal_approx(curve_keys[key_index]),"Contact curve UI keeps authored anchor fixed")
	editor._set_paddle_angle(0,20);await frames();await snap("portrait-paddle-gimbal")
	editor._joint_chosen("right_elbow")
	var elbow_before:Vector3=editor._preview.joint_world_position("right_elbow")
	var paddle_before:Transform3D=editor._preview.player.paddle_node.global_transform
	var arm=editor._preview.player.right_arm_node
	var wrist_before:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
	editor._fine=false;editor._swivel_elbow_guide(1);await frames()
	check(editor._preview.joint_world_position("right_elbow").distance_to(elbow_before)>.0001,"bend guide visibly steers elbow")
	check(editor._preview.player.paddle_node.global_transform.is_equal_approx(paddle_before),"bend guide preserves paddle target")
	check((arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket).distance_to(wrist_before)<.00001,"bend guide preserves held wrist")
	check(editor._preview.selected_joint_samples.size()==65,"selected elbow has solved movement curve")
	editor._fine=true;await snap("portrait-elbow-curve")
	editor._joint_chosen("paddle");editor._paddle_view=2;editor._build_fields();await frames()
	check(editor._sliders.has("body_position_offset:0") and editor._sliders.has("body_position_offset:2"),"whole body XYZ controls are exposed")
	var fixed_paddle:Transform3D=editor._preview.player.paddle_node.global_transform
	var other_body:Array=[Path.endpoint(editor._current,0).body_position_offset,Path.endpoint(editor._current,2).body_position_offset]
	for axis in range(3):editor._sliders["body_position_offset:"+str(axis)].value=[.08,.03,-.07][axis]
	await frames()
	check(editor._edit.body_position_offset.is_equal_approx(Vector3(.08,.03,-.07)),"body XYZ authors selected key")
	check(editor._preview.player.paddle_node.global_transform.is_equal_approx(fixed_paddle),"body position keeps actual paddle Contact fixed")
	check(Path.endpoint(editor._current,0).body_position_offset==other_body[0] and Path.endpoint(editor._current,2).body_position_offset==other_body[1],"body position preserves other two keys")
	await snap("portrait-body-position")
	editor._set_left_support_hold(true);await frames()
	for stage in range(3):
		var key_pose:Resource=Path.endpoint(editor._current,stage)
		check(key_pose.left_hand_mode==1 and key_pose.left_hand_offset==Vector3.ZERO,"left hold joins all phases with seated anchor")
	check(editor._current.paddle_hand==0,"left hold never changes main handedness")
	var support:Vector3=editor._preview.player.arm_ik.get_support_hand_target(editor._preview.pose)
	check(editor._preview.player.left_arm_node.hand_mesh.global_position.distance_to(support)<.00001,"left support hand is actually seated on handle")
	editor._paddle_view=1;editor._build_fields();await snap("portrait-two-hand-grip")
	editor._paddle_view=2;editor._build_fields()
	editor._set_left_support_hold(false);await frames()
	for stage in range(3):check(Path.endpoint(editor._current,stage).left_hand_mode==4,"release applies to every phase")
	var fixed_upper:Dictionary={}
	for field in editor.POS+editor.ROT+["body_pitch_deg","body_yaw_deg","torso_yaw_deg"]:fixed_upper[field]=editor._edit.get(field)
	for preset in range(3):
		editor._stance_preset=preset;editor._apply_stance_preset();await frames()
		for field in fixed_upper:check(editor._edit.get(field)==fixed_upper[field],"stance preset keeps paddle/upper body field "+field)
		var legs=editor._preview.player.leg_ik
		var foot_delta:Vector3=legs.left_foot_smooth-legs.right_foot_smooth
		var depth:float=foot_delta.dot(editor._preview.player._get_forward_axis())
		check(depth>.1 if preset==0 else depth<-.1 if preset==1 else absf(depth)<.02,"stance preset has explicit correct lead foot")
	editor._save_current();var body_reloaded:Resource=PostureLibrary.new().get_def(0)
	check(body_reloaded.body_position_offset.is_equal_approx(editor._current.body_position_offset),"body position survives Save/reload")
	editor._paddle_view=0;editor._build_fields()
	var authored_variant:String=Store.export_pose_json(editor._current)
	var contact_frame:Transform3D=Path.world_transform(editor._preview.player,Path.sample(editor._current,.5))
	for mode in [1,2]:
		editor._play_variant(mode);await frames()
		check(editor._variant_mode==mode and editor._playing,"generated preview starts")
		check(editor._motion_hint.text.contains("preview"),"generated mode clearly labelled")
		check(editor._preview.ghost_transforms[1].is_equal_approx(contact_frame),"generated Contact ghost stays fixed")
		check(Store.export_pose_json(editor._current)==authored_variant,"generated play never authors source")
		editor._last_tick-=50000;editor._process(0)
		var paused_at:float=editor._progress
		editor._play_variant(mode);check(not editor._playing and is_equal_approx(editor._progress,paused_at),"same variant pauses at current position")
		editor._play_variant(mode);check(editor._playing and is_equal_approx(editor._progress,paused_at),"same variant resumes current position")
		editor._scrubbed(.5);check(editor._preview.player.paddle_node.global_transform.is_equal_approx(contact_frame),"generated actual Contact stays fixed")
	editor._toggle_play();check(editor._variant_mode==0 and editor._playing,"Play returns to normal authored motion")
	editor._select_stage(1);check(editor._variant_mode==0 and not editor._playing,"selecting key ends generated preview")
	select_id(20);editor._group.select(4);editor._paddle_view=1;editor._build_fields();await frames()
	for preset in range(4):
		editor._choose_grip_style(preset);await frames()
		check(editor._grip_picker.selected==preset,"preset selection synchronized")
		check(is_equal_approx(Styles.relative_rotation(editor._edit),Styles.PRESET_ANGLES[preset]),"preset actual relative angle")
	editor._grip_input.value=1123.2;await frames();check(editor._grip_picker.selected==4,"manual tuning selects Custom")
	check(absf(Styles.relative_rotation(editor._edit)-43.2)<.01,"in-hand numeric wraps")
	await snap("portrait-ready-grip")
	editor._save_current()
	var ready_before:Resource=editor._current.duplicate(true)
	editor._choose_grip_style(1);editor._request_global_grip();await frames()
	check(editor._dialog.visible and not GripStore.has_global(),"global button asks scope before applying")
	editor._set_global_grip();await frames()
	check(GripStore.has_global(),"global button persists explicitly")
	for def in PostureLibrary.instance().all_definitions():
		for stage in range(3):check(absf(Styles.relative_rotation(Path.endpoint(def,stage))-45)<.01,"global applies every stroke stage")
	for def in ServeStore.all_definitions():
		for stage in range(3):check(absf(Styles.relative_rotation(Path.endpoint(def,stage))-45)<.01,"global applies every serve stage")
	for field in editor.POS+editor.ROT:check(is_equal_approx(float(ready_before.get(field)),float(editor._current.get(field))),"global keeps Ready transform authored field "+field)
	editor._undo_global_grip();await frames()
	check(not GripStore.has_global(),"undo returns prior no-global state")
	editor._choose_grip_style(0);editor._set_global_grip();await frames()
	select_id(0);editor._select_stage(0);editor._choose_grip_style(3);editor._save_current();await frames()
	check(absf(Styles.relative_rotation(Path.endpoint(PostureLibrary.instance().get_def(0),0))+45)<.01,"individual selected-stage override after global")
	check(absf(Styles.relative_rotation(Path.endpoint(PostureLibrary.instance().get_def(0),1)))<.01,"individual override keeps other stage global")
	editor._undo_global_grip();await frames()
	select_id(20)
	root.size=Vector2i(432,768);root.content_scale_size=Vector2i(720,1280);editor._paddle_view=0;editor._build_fields();await snap("short-portrait-gimbal")
	root.size=Vector2i(936,432);root.content_scale_size=Vector2i(1560,720);await snap("landscape-gimbal")
	editor._select_workspace(2);editor._group.select(4);editor._select_stage(1);await frames();check(is_instance_valid(editor._gimbal),"serve Contact rotation is available")
	var serve_before:PostureDefinition=editor._current.duplicate(true)
	var serve_contact_before:Transform3D=editor._preview.player.paddle_node.global_transform
	editor._set_paddle_angle(0,editor._edit.paddle_pitch_base_deg+8);await frames()
	check(is_equal_approx(editor._current.paddle_pitch_base_deg,serve_before.paddle_pitch_base_deg+8),"serve Contact pitch changes authored value")
	for field in editor.POS:check(is_equal_approx(editor._current.get(field),serve_before.get(field)),"serve Contact rotation keeps solver-owned stored position")
	check(not editor._preview.player.paddle_node.global_transform.basis.is_equal_approx(serve_contact_before.basis),"serve Contact displayed rotation changes")
	editor._save_current();check(not editor._dirty.has(editor._key),"serve Contact rotation saves")
	check(editor._sliders.has("contact_curve"),"serve Contact keeps whole-motion curve editable")
	editor._sliders.contact_curve.value=.75;check(is_equal_approx(editor._current.contact_curve,.75),"serve Contact curve slider applies")
	editor._stance_preset=0;editor._apply_stance_preset();check(editor._stage==1 and ServeStore.endpoint(editor._current,0).lead_foot==1,"serve stance preset edits Wind-up and returns to Contact")
	editor._select_stage(0);await frames();check(is_instance_valid(editor._gimbal),"serve Wind-up rotation available")
	editor._paddle_view=1;editor._build_fields();editor._choose_grip_style(2);await frames();editor._save_current();check(not editor._dirty.has(editor._key),"serve grip saves")
	for i in range(3):
		editor._finish_close();await frames(4);check(game.mobile_pose_editor==null,"close frees editor")
		await process_frame;pause.close();await frames(3);pause.open();game.open_mobile_pose_editor();await frames(3);editor=game.mobile_pose_editor
		check(is_instance_valid(editor),"reopen editor")
	editor._finish_close();await frames(4);await process_frame;pause.close();await frames(3)
	game.queue_free();await frames(4);OS.delay_msec(100)
	print("[MOBILE PADDLE GIMBAL] %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
