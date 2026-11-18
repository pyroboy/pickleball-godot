extends SceneTree
const Runtime=preload("res://scripts/elbow_preset_runtime.gd")
const Motion=preload("res://scripts/drive_serve_motion.gd")
const Path=preload("res://scripts/stroke_swing_path.gd")
const Preview=preload("res://scripts/ui/mobile_pose_preview.gd")
const Size=preload("res://scripts/paddle_dimensions.gd")
const Clock=preload("res://scripts/stroke_playback_clock.gd")
const Fixture=preload("res://scripts/auto_elbow_fixture.gd")
const Codec=preload("res://scripts/elbow_preset_bake.gd")
const Visual=preload("res://scripts/player_arm_visual.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func run() -> void:
	var path: String="res://results/mobile-elbow-case16-bake.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bake="):path=arg.trim_prefix("--bake=")
		if arg.begins_with("--case="):path="res://results/mobile-elbow-case%s-bake.json"%arg.trim_prefix("--case=")
	if not FileAccess.file_exists(path):push_error("Real accepted service bake missing: "+path);quit(1);return
	var bake=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Codec.valid(bake),"real payload checksum/schema valid")
	var source: PostureDefinition=PostureLibrary.instance().get_def(int(bake.source_id)).duplicate(true)
	var baseline: PostureDefinition=source.duplicate(true)
	source.elbow_preset_bake=bake
	for ease in range(3):
		var timing: PostureDefinition=source.duplicate(true);timing.ft_ease_curve=ease
		for i in range(101):
			var expected: float=float(i)/100.0
			var total: float=maxf(.01,timing.ft_duration_strike)+maxf(.01,timing.ft_duration_sweep)
			var progress: float=Clock.state(timing,expected*total,Path.endpoint(timing,2),PostureLibrary.instance().get_def(20)).progress
			check(absf(Runtime.clock_coordinate(timing,progress)-expected)<0.00001,"clock roundtrip ease%d at%d"%[ease,i])
	var preview=Preview.new();root.add_child(preview);await process_frame;await process_frame
	var player=preview.player
	var counts: Dictionary={"applied":0,"fallback":0,"fallback_reasons":{},"head_error_max":0.0}
	for index in range(481):
		var coordinate: float=float(index)/480.0
		var progress: float=coordinate
		if str(bake.scope)=="stroke_runtime":
			var elapsed: float=coordinate*float(bake.duration)
			progress=Clock.state(source,elapsed,Path.endpoint(source,2),PostureLibrary.instance().get_def(20)).progress
		preview.show_pose(Motion.sample_drive(baseline,progress,1.0))
		var head: Vector3=player.paddle_node.global_transform*Size.HEAD_OFFSET
		var body: Transform3D=player.body_pivot.global_transform
		var shoulders: Array=[player.right_arm_node.upper_pivot.global_position,player.left_arm_node.upper_pivot.global_position]
		preview.show_pose(Motion.sample_drive(source,progress,1.0))
		var report: Dictionary=player.get_meta("elbow_preset_report",{})
		if report.get("applied",false):counts.applied+=1
		else:
			counts.fallback+=1;counts.fallback_reasons[report.get("status","missing")]=int(counts.fallback_reasons.get(report.get("status","missing"),0))+1
		var head_error: float=(player.paddle_node.global_transform*Size.HEAD_OFFSET).distance_to(head)
		counts.head_error_max=maxf(counts.head_error_max,head_error)
		check(head_error<=0.000002,"actual final head invariant at "+str(index))
		check(player.body_pivot.global_position.distance_to(body.origin)<=0.000002,"body position invariant")
		for side in range(2):
			var arm=player.right_arm_node if side==0 else player.left_arm_node
			check(arm.upper_pivot.global_position.distance_to(shoulders[side])<=0.00002,"shoulder unchanged")
	check(counts.applied==481,"all481/481 dense real samples apply, got "+str(counts))
	var offgrid: Dictionary={"applied":0,"fallback":0,"reasons":{}}
	for index in range(480):
		var coordinate: float=(float(index)+.5)/480.0
		var progress: float=Clock.state(source,coordinate*float(bake.duration),Path.endpoint(source,2),PostureLibrary.instance().get_def(20)).progress
		preview.show_pose(Motion.sample_drive(source,progress,1.0))
		var report: Dictionary=player.get_meta("elbow_preset_report",{})
		if report.get("applied",false):offgrid.applied+=1
		else:offgrid.fallback+=1;offgrid.reasons[report.get("status","missing")]=int(offgrid.reasons.get(report.get("status","missing"),0))+1
	counts.offgrid=offgrid
	check(offgrid.applied==480,"all480/480 off-grid samples apply: "+str(offgrid))
	player.global_position+=Vector3(2,0,4);player.leg_ik.feet_initialized=false
	preview.show_pose(Motion.sample_drive(source,.5,1.0))
	check(bool(player.get_meta("elbow_preset_report",{}).get("applied",false)),"root translation preserves canonical replay")
	player.global_position-=Vector3(2,0,4);player.leg_ik.feet_initialized=false
	var edited: PostureDefinition=source.duplicate(true);edited.right_elbow_pole.x+=0.001
	check(not Motion.sample_drive(edited,.5,1.0).has_meta(Runtime.SAMPLE_META),"manual elbow edit invalidates source")
	edited=source.duplicate(true);edited.main_grip_rotation_deg+=1.0
	check(not Motion.sample_drive(edited,.5,1.0).has_meta(Runtime.SAMPLE_META),"grip edit invalidates source")
	edited=source.duplicate(true);edited.paddle_hand=1-source.paddle_hand
	check(not Motion.sample_drive(edited,.5,1.0).has_meta(Runtime.SAMPLE_META),"handedness invalidates source")
	var previous_grip: float=source.main_grip_rotation_deg
	Motion.sample_drive(source,.5,1.0)
	source.main_grip_rotation_deg+=1.0
	check(not Motion.sample_drive(source,.5,1.0).has_meta(Runtime.SAMPLE_META),"byte-exact cache catches in-place grip edit")
	source.main_grip_rotation_deg=previous_grip
	check(Motion.sample_drive(source,.5,1.0).has_meta(Runtime.SAMPLE_META),"restoring exact authored source restores valid cached fingerprint")
	for corruption in ["finite","truncated","nan"]:
		var corrupt: PostureDefinition=source.duplicate(true)
		corrupt.elbow_preset_bake=source.elbow_preset_bake.duplicate(true)
		if corruption=="finite":corrupt.elbow_preset_bake.routes[source.paddle_hand].knots[0][1]+=.1
		elif corruption=="truncated":corrupt.elbow_preset_bake.samples[0].paddle=[]
		else:corrupt.elbow_preset_bake.routes[source.paddle_hand].knots[0][1]=NAN
		check(not Motion.sample_drive(corrupt,.5,1.0).has_meta(Runtime.SAMPLE_META),"actual "+corruption+" corruption refuses sample")
	var stamped: PostureDefinition=Motion.sample_drive(source,.5,1.0)
	check(not Path.blend_pose(stamped,baseline,.5).has_meta(Runtime.SAMPLE_META),"arbitrary blends do not retain sampled tags")
	preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
	for corruption in ["finite_bake","truncated_bake","nan_progress","outside_progress","scope","non_dictionary"]:
		var injected: PostureDefinition=stamped.duplicate(true)
		var metadata: Dictionary=injected.get_meta(Runtime.SAMPLE_META).duplicate(true)
		if corruption=="finite_bake":metadata.bake.routes[source.paddle_hand].knots[0][1]+=.1
		elif corruption=="truncated_bake":metadata.bake.samples[0].hands=[]
		elif corruption=="nan_progress":metadata.progress=NAN
		elif corruption=="outside_progress":metadata.progress=2.0
		elif corruption=="scope":metadata.scope="wrong"
		injected.set_meta(Runtime.SAMPLE_META,42 if corruption=="non_dictionary" else metadata)
		var paddle_before: Transform3D=player.paddle_node.global_transform
		var arm_before: Transform3D=player.right_arm_node.upper_pivot.transform
		var rejected: Dictionary=Runtime.apply(player,injected)
		check(not rejected.applied,"mutated sample metadata "+corruption+" rejected")
		check(player.paddle_node.global_transform==paddle_before and player.right_arm_node.upper_pivot.transform==arm_before,"invalid metadata leaves scene untouched")
	preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
	player.body_pivot.position.x+=.001
	var untouched: Transform3D=player.paddle_node.global_transform
	var failed: Dictionary=Runtime.apply(player,stamped)
	check(not failed.applied,"live body mismatch fails safely")
	check(player.paddle_node.global_transform==untouched,"mismatch made no partial paddle write")
	preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
	player.paddle_node.position.x+=.001
	untouched=player.paddle_node.global_transform
	failed=Runtime.apply(player,stamped)
	check(not failed.applied,"contact-owned paddle mismatch fails safely")
	check(player.paddle_node.global_transform==untouched,"contact mismatch retains final transform")
	# Post-write numerical gate must restore all state transactionally.
	preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
	var arm=player.right_arm_node if source.paddle_hand==0 else player.left_arm_node
	var mount: Transform3D=arm.hand_mesh.global_transform
	arm.upper_pivot.global_basis=arm.upper_pivot.global_basis.scaled(Vector3(1.002,1.002,1.002))
	arm.articulated_hand.set_mesh_world_transform(mount)
	var saved: Array=[]
	for node in [arm.upper_pivot,arm.forearm_pivot,arm.hand_pivot,arm.upper_mesh,arm.fore_mesh,arm.hand_mesh]:saved.append([node,node.transform])
	untouched=player.paddle_node.global_transform
	failed=Runtime.apply(player,stamped)
	check(not failed.applied,"numerical scale gate rejects")
	check(player.paddle_node.global_transform==untouched,"postwrite failure restores paddle")
	for entry in saved:check(entry[0].transform==entry[1],"postwrite failure restores arm nodes")
	arm.upper_pivot.global_basis=arm.upper_pivot.global_basis.orthonormalized();arm.forearm_pivot.basis=Basis.IDENTITY
	if bool(bake.active_sides[0]) and bool(bake.active_sides[1]):
		preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
		var left=player.left_arm_node;var fixed: Transform3D=left.hand_mesh.global_transform
		left.upper_pivot.global_basis=left.upper_pivot.global_basis.scaled(Vector3(1.002,1.002,1.002))
		left.articulated_hand.set_mesh_world_transform(fixed)
		Visual.update_arm(left);left.articulated_hand.update_wrist_bridge(left.fore_mesh.global_basis)
		var all_before: Array=[]
		for current_arm in [player.right_arm_node,player.left_arm_node]:
			var values: Array=[]
			for node in [current_arm.upper_pivot,current_arm.forearm_pivot,current_arm.hand_pivot,current_arm.upper_mesh,current_arm.fore_mesh,current_arm.hand_mesh]:values.append([node,node.transform])
			var bridge=current_arm.get_meta("arm_elbow_bridge")
			all_before.append({"nodes":values,"arm":current_arm,"wrist":current_arm.anatomical_wrist_world,"stretch":current_arm.visual_stretch,"lag":current_arm.visual_wrist_lag_deg,"elbow_bones":[bridge.skeleton.get_bone_pose(1),bridge.skeleton.get_bone_pose(2)],"wrist_bone":current_arm.articulated_hand.skeleton.get_bone_pose(current_arm.articulated_hand.WRIST_BRIDGE_BONE)})
		untouched=player.paddle_node.global_transform;failed=Runtime.apply(player,stamped)
		check(not failed.applied and str(failed.status).begins_with("Actual invariant"),"second active arm failure rolls back first successful arm")
		check(player.paddle_node.global_transform==untouched,"partial apply rollback restores paddle")
		for state in all_before:
			for entry in state.nodes:check(entry[0].transform==entry[1],"partial apply restores both arms nodes")
			check(state.arm.anatomical_wrist_world==state.wrist and state.arm.visual_stretch==state.stretch and state.arm.visual_wrist_lag_deg==state.lag,"partial apply restores IK caches")
			var bridge=state.arm.get_meta("arm_elbow_bridge")
			for bone in range(2):check(bridge.skeleton.get_bone_pose(bone+1).is_equal_approx(state.elbow_bones[bone]),"partial apply restores elbow bridge geometry")
			check(state.arm.articulated_hand.skeleton.get_bone_pose(state.arm.articulated_hand.WRIST_BRIDGE_BONE).is_equal_approx(state.wrist_bone),"partial apply restores wrist bridge geometry")
		left.upper_pivot.global_basis=left.upper_pivot.global_basis.orthonormalized();left.forearm_pivot.basis=Basis.IDENTITY
	# Independently built far-court rig exercises180-degree stance transport.
	var world:=Node3D.new();root.add_child(world)
	var other=load("res://scripts/player.gd").new();world.add_child(other)
	other.setup(1,{"left":-10.0,"right":10.0,"top":-10.0,"bottom":10.0},Color("3985d9"),Vector3(0,1,0),true)
	other.posture.editor_preview_mode=true;preview._disable_simulation(other)
	# This isolated test rig explicitly exercises diagnostic replay, not gameplay.
	other.set_meta(Runtime.PRIVATE_PREVIEW_META,true)
	await process_frame;await process_frame
	other.leg_ik.feet_initialized=false
	other.posture.force_posture_update(Motion.sample_drive(source,.5,1.0))
	var court: Dictionary=other.get_meta("elbow_preset_report",{})
	counts.opposite_court=court
	# Some rigs are genuinely asymmetric; the safe contract is apply-or-intact-fallback.
	check(court.has("applied"),"opposite court evaluated explicit context gate")
	var skin_error:=0.0
	for progress in [0.0,.25,.5,.75,1.0]:
		var pose: PostureDefinition=Motion.sample_drive(baseline,progress,1.0)
		var near_frames: Array=Fixture.capture(player,pose,progress,true)
		var far_frames: Array=Fixture.capture(other,pose,progress,true)
		var near_inverse:=Runtime.root_for(player).affine_inverse();var far_inverse:=Runtime.root_for(other).affine_inverse()
		var near_rings: Array=near_frames[0].body_geometry.rings;var far_rings: Array=far_frames[0].body_geometry.rings
		for row in range(near_rings.size()):
			for point in range(near_rings[row].size()):skin_error=maxf(skin_error,(near_inverse*near_rings[row][point]).distance_to(far_inverse*far_rings[row][point]))
	counts.court_skin_congruence_error=skin_error
	check(skin_error<=0.00002,"actual displayed skin congruent across court180-degree rotation")
	var repeated:=0;var repeat_fallback:=0
	for cycle in range(20):
		for step in range(121):
			var coordinate: float=float(step if cycle%2==0 else 120-step)/120.0
			var progress: float=Clock.state(source,coordinate*float(bake.duration),Path.endpoint(source,2),PostureLibrary.instance().get_def(20)).progress
			preview.show_pose(Motion.sample_drive(source,progress,1.0))
			if bool(player.get_meta("elbow_preset_report",{}).get("applied",false)):repeated+=1
			else:repeat_fallback+=1
	check(repeat_fallback==0,"20alternating long-lived replays have no drift fallback")
	counts.repeated_applied=repeated;counts.repeated_fallback=repeat_fallback
	var pose: PostureDefinition=Motion.sample_drive(baseline,.5,1.0)
	var start:=Time.get_ticks_usec()
	for iteration in range(500):Runtime.tag(pose,source,.5,"stroke_runtime")
	counts.tag_mean_us=float(Time.get_ticks_usec()-start)/500.0
	preview.show_pose(Motion.sample_drive(baseline,.5,1.0))
	var apply_usec:=0;var applied_count:=0
	for iteration in range(200):
		player.set_meta("elbow_preset_capture",true);player.posture.force_posture_update(pose);player.remove_meta("elbow_preset_capture")
		start=Time.get_ticks_usec();var report:=Runtime.apply(player,pose);apply_usec+=Time.get_ticks_usec()-start
		if report.applied:applied_count+=1
	counts.apply_mean_us=float(apply_usec)/200.0;counts.timed_applied=applied_count
	check(applied_count==200,"timing measured200successful overlays")
	world.queue_free()
	var summary: Dictionary={"checks":checks,"failures":failures,"replay":counts}
	var report_path: String=path.replace("-bake.json","-runtime.json")
	var file=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(summary,"  "));file.close()
	print("ELBOW_RUNTIME ",JSON.stringify(summary))
	preview.queue_free();await process_frame;quit(0 if failures==0 else 1)
