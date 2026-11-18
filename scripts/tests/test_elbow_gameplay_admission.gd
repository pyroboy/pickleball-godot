extends SceneTree
## Historical core-only certificates remain readable, but their source hashes
## predate resolved-display quaternion interpolation. This gate verifies stale
## retention/refusal without resealing them. Newly certified positive diagnostic
## replay and accepted Apply/Undo lifecycle need a new certified fixture.
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Runtime = preload("res://scripts/elbow_preset_runtime.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
const Fixture = preload("res://scripts/auto_elbow_fixture.gd")
const Human = preload("res://scripts/human_contact_controller.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Codec = preload("res://scripts/elbow_preset_bake.gd")
const Grip = preload("res://scripts/mobile_paddle_grip_store.gd")
class BallStub extends RigidBody3D:
	var is_in_play := true
	var bounces_since_last_hit := 1
	var last_hit_by := 1
	var flight_id := -912
var failures:Array[String]=[]
var checks:=0
var max_json_roundtrip_error:=0.0
func check(value:bool,label:String):
	checks+=1
	if not value:failures.append(label)
func _initialize():call_deferred("run")
func vec(v:Vector3) -> Array:return [v.x,v.y,v.z]
func snap(player,label:String) -> Dictionary:
	var pose=player.posture.transition_pose_blend
	var report:Dictionary=player.get_meta("elbow_preset_report",{})
	return {"label":label,"tag":pose.has_meta(Runtime.SAMPLE_META),"applied":bool(report.get("applied",false)),"status":report.get("status","original"),"elbows":[vec(player.right_arm_node.forearm_pivot.global_position),vec(player.left_arm_node.forearm_pivot.global_position)],"pose_id":pose.posture_id}
func disable_simulation(node:Node):
	node.set_process(false);node.set_physics_process(false)
	node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false)
	if node is CollisionObject3D:node.collision_layer=0;node.collision_mask=0
	if node is Area3D:node.monitoring=false;node.monitorable=false
	for child in node.get_children():disable_simulation(child)
func same_json_value(a,b) -> bool:
	if a is Dictionary:
		if not b is Dictionary or a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_json_value(a[key],b[key]):return false
		return true
	if a is Array:
		if not b is Array or a.size()!=b.size():return false
		for index in range(a.size()):
			if not same_json_value(a[index],b[index]):return false
		return true
	if a is float or a is int:
		if not (b is float or b is int):return false
		var error:float=absf(float(a)-float(b))
		max_json_roundtrip_error=maxf(max_json_roundtrip_error,error)
		# Godot's full-precision JSON may differ by one binary64 rounding step.
		# This is 100,000 times stricter than the existing checksum quantum.
		return is_finite(error) and error<=0.00000000000001
	return typeof(a)==typeof(b) and a==b
func same_bake(a:Dictionary,b:Dictionary) -> bool:
	return Codec.valid(a) and Codec.valid(b) and same_json_value(a,b)
func run():
	var test_id:="%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	check(Store.set_test_path("user://pose_store_tests/admission_"+test_id+".json")==OK,"isolated admission pose store")
	check(Grip.set_test_path("user://pose_store_tests/admission_grip_"+test_id+".json")==OK,"isolated admission grip store")
	var world=Node3D.new();root.add_child(world)
	var p=load("res://scripts/player.gd").new();world.add_child(p)
	p.setup(0,{"left":-10.0,"right":10.0,"top":-10.0,"bottom":10.0},Color("3985d9"),Vector3(0,1,5),true)
	disable_simulation(p)
	await process_frame;await process_frame
	disable_simulation(p)
	var expect_off := true
	if p.posture.editor_preview_mode:failures.append("ordinary gameplay rig unexpectedly in preview mode")
	var b=BallStub.new();b.freeze=true;b.collision_layer=0;b.collision_mask=0;root.add_child(b);p.ball_ref=b
	var output:Dictionary={"expect_gameplay_off":expect_off,"scope":"Ordinary Player rig, no Preview designation; actual Player.animate_serve_release -> PlayerHitting._animate_authored_swing -> actual Tween and real rig; is_ai true; editor_preview_mode false; physics/input disabled; frozen fake ball only supplies context; frozen ball supplies context only; no contact or launch side effects.","cases":[],"coverage":{"historical_stale_bake_refusal":true,"newly_certified_positive_diagnostic_replay":"UNVERIFIED: no new-model certified fixture", "accepted_apply_undo_lifecycle":"UNVERIFIED: no new-model certified fixture"}}
	for name in ["mobile-elbow-case16-bake.json","mobile-elbow-case18-rotated-bake.json"]:
		for variant in ["baseline","canonical_saved_bake","retargeted_5mm"]:
			var bake:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://results/"+name))
			var source:PostureDefinition=PostureLibrary.instance().get_def(int(bake.source_id)).duplicate(true)
			source.elbow_preset_bake=bake if variant != "baseline" else {}
			if variant == "retargeted_5mm":source.paddle_forehand_mul+=.005
			var row:Dictionary={"bake":name,"variant":variant,"valid":Codec.valid(bake),"fingerprint_match":Store.authored_fingerprint(source,"stroke_runtime")==bake.source_sha256,"samples":[]}
			p.ai_desired_posture=source.posture_id
			p.posture.transition_pose_blend=source
			p.leg_ik.feet_initialized=false
			p.posture.force_posture_update(source)
			row.samples.append(snap(p,"accepted_contact_before_swing"))
			p.animate_serve_release(1.0)
			row.samples.append(snap(p,"actual_controller_initial_contact"))
			var tw:Tween=p.hitting.paddle_swing_tween;tw.pause()
			var elapsed:=0.0
			for point in [float(source.ft_duration_sweep)*.5,float(source.ft_duration_sweep),float(source.ft_duration_sweep)+float(source.ft_duration_hold)-.00001,float(source.ft_duration_sweep)+float(source.ft_duration_hold)+.00001,float(source.ft_duration_sweep)+float(source.ft_duration_hold)+float(source.ft_duration_settle)+1.0]:
				p.leg_ik.feet_initialized=false
				tw.custom_step(point-elapsed);elapsed=point
				row.samples.append(snap(p,"t="+str(point)))
			output.cases.append(row)
	for row in output.cases:
		check(row.valid,"historical bake remains structurally valid: "+row.bake)
		check(not row.fingerprint_match,"historical source remains stale under quaternion model: "+row.bake)
		for index in range(row.samples.size()):
			var applied:bool=row.samples[index].applied
			check(not row.samples[index].tag,"actual AI historical source receives no runtime tag")
			var expected:bool=not expect_off and row.variant=="canonical_saved_bake" and index in [1,2,3,4]
			if applied!=expected:failures.append("activation mismatch %s %s sample%d"%[row.bake,row.variant,index])
		if expect_off:
			var baseline:Dictionary={}
			for possible in output.cases:
				if possible.bake==row.bake and possible.variant=="baseline":baseline=possible
			if row.variant=="canonical_saved_bake":
				for index in range(row.samples.size()):
					for side in range(2):
						var av:Array=row.samples[index].elbows[side];var bv:Array=baseline.samples[index].elbows[side]
						if Vector3(av[0],av[1],av[2]).distance_to(Vector3(bv[0],bv[1],bv[2]))>0.00002:failures.append("baseline mismatch %s sample%d side%d"%[row.bake,index,side])
	await test_admission(p,b,output)
	var report_path:="user://elbow-gameplay-admission.json"
	var file=FileAccess.open(report_path,FileAccess.WRITE)
	check(file!=null,"admission report can be written in source and exported runtime")
	output.max_json_roundtrip_error=max_json_roundtrip_error
	output.checks=checks
	output.failures=failures
	if file!=null:file.store_string(JSON.stringify(output,"  "));file.close()
	print("ELBOW_GAMEPLAY_ADMISSION ",JSON.stringify({"checks":checks,"failures":failures,"coverage":output.coverage,"max_json_roundtrip_error":max_json_roundtrip_error,"report":ProjectSettings.globalize_path(report_path)}))
	world.queue_free();b.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func rig_state(p) -> PackedByteArray:
	var values:Array=[p.body_pivot.global_transform,p.paddle_node.global_transform]
	for arm in [p.right_arm_node,p.left_arm_node]:
		for n in [arm.upper_pivot,arm.forearm_pivot,arm.hand_pivot,arm.upper_mesh,arm.fore_mesh,arm.hand_mesh]:values.append(n.transform)
		values.append_array([arm.anatomical_wrist_world,arm.visual_stretch,arm.visual_wrist_lag_deg])
	return var_to_bytes(values)
func test_admission(p,b,output:Dictionary):
	var view=Preview.new();root.add_child(view);await process_frame;await process_frame
	output.admission=[];output.human=[];output.diagnostic=[]
	for name in ["mobile-elbow-case16-bake.json","mobile-elbow-case18-rotated-bake.json"]:
		var bake:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://results/"+name))
		var baseline:PostureDefinition=PostureLibrary.instance().get_def(int(bake.source_id)).duplicate(true)
		var source:PostureDefinition=baseline.duplicate(true);source.elbow_preset_bake=bake
		var original:Dictionary=bake.duplicate(true)
		var source_matches:bool=Store.authored_fingerprint(source,"stroke_runtime")==bake.source_sha256
		check(Codec.valid(bake),"historical certificate checksum and structure remain valid")
		check(not source_matches,"historical fixture is stale; it must not be resealed to gain admission")
		check(Store.save(source)==OK,"stale historical certificate remains savable")
		var reloaded:PostureDefinition=PostureLibrary.new().get_def(source.posture_id)
		check(same_bake(reloaded.elbow_preset_bake,original),"save/load preserves historical certificate unchanged")
		check(not Motion.sample_drive(reloaded,.5,1.0).has_meta(Runtime.SAMPLE_META),"reloaded stale certificate cannot regain a runtime tag")
		var exported:Dictionary=JSON.parse_string(Store.export_pose_json(source))
		check(not exported.is_empty() and same_bake(exported.fields.elbow_preset_bake,original),"Copy JSON preserves historical certificate unchanged")
		var copied_source:PostureDefinition=baseline.duplicate(true)
		check(Store.copy_values(source,copied_source)==OK and same_bake(copied_source.elbow_preset_bake,original),"pose copy preserves historical certificate unchanged")
		check(not Motion.sample_drive(copied_source,.5,1.0).has_meta(Runtime.SAMPLE_META),"copied stale source cannot regain a runtime tag")
		var stamped:PostureDefinition=Motion.sample_drive(source,.5,1.0)
		check(not stamped.has_meta(Runtime.SAMPLE_META),"stale source refuses diagnostic sample tag")
		var copied:PostureDefinition=stamped.duplicate(true)
		# Test only: model retained/copied historical metadata independently of
		# today's tag producer. Do not reseal the bake or activate this metadata
		# on a private diagnostic rig. Permission must still belong to the rig.
		if not copied.has_meta(Runtime.SAMPLE_META):
			copied.set_meta(Runtime.SAMPLE_META,{"bake":bake,"progress":Runtime.clock_coordinate(source,.5),"scope":"stroke_runtime"})
		check(copied.has_meta(Runtime.SAMPLE_META),"admission probes include retained historical sample metadata")
		for ai in [true,false]:
			p.is_ai=ai
			for mode in [false,true]:
				p.posture.editor_preview_mode=mode
				p.leg_ik.feet_initialized=false;p.posture.force_posture_update(Motion.sample_drive(baseline,.5,1.0))
				var before:PackedByteArray=rig_state(p)
				var result:Dictionary=Runtime.apply(p,copied)
				check(not result.applied,"ordinary AI/Human rig refuses copied historical tag")
				check(result.status=="Core-only preset requires a private diagnostic preview; original retained","ordinary AI/Human refusal reaches the explicit rig permission gate")
				check(rig_state(p)==before,"admission refusal occurs before any rig mutation")
				output.admission.append({"case":source.posture_id,"is_ai":ai,"editor_preview_mode":mode,"private":false,"result":result})
		p.posture.editor_preview_mode=false;p.is_ai=false
		var reference:Array=[]
		for use_bake in [false,true]:
			var human=Human.new(p,p.posture)
			human.swing_def=source if use_bake else baseline;human.charge_ratio=1.0;human.swing_flight_id=99;human.strike_time=source.ft_duration_strike
			human._swing_is_volley=false;human._swing_near_kitchen=false;human._swing_spin_mode=0;human._swing_shot_intent="AUTO"
			var index:=0
			for phase in [1,2]:
				for factor in [0.0,.5,1.0]:
					human.phase=phase;human.hit=false;human._sweep_valid=false;human.contact={}
					human.elapsed=factor*(human.strike_time if phase==1 else source.ft_duration_sweep)
					human._strike_start_pose=Motion.sample_drive(baseline,0.0,1.0);human._finish_start_pose=Motion.sample_drive(baseline,.5,1.0)
					p.leg_ik.feet_initialized=false;human._advance_swing(0.0,b)
					var actual:Dictionary=snap(p,"human phase%d factor%.1f"%[phase,factor])
					check(not actual.applied and not actual.tag,"actual Human retains post-blend original path")
					if use_bake:
						for side in range(2):
							var a:Array=actual.elbows[side];var r:Array=reference[index].elbows[side]
							check(Vector3(a[0],a[1],a[2]).distance_to(Vector3(r[0],r[1],r[2]))<=0.00002,"Human baked source preserves baseline")
					else:reference.append(actual)
					index+=1;output.human.append(actual)
		var private=view.player
		check(bool(private.get_meta(Runtime.PRIVATE_PREVIEW_META,false)),"private preview carries explicit designation")
		view.show_pose(Motion.sample_drive(baseline,.5,1.0))
		private.posture.editor_preview_mode=false
		var before:PackedByteArray=rig_state(private);var denied:Dictionary=Runtime.apply(private,copied)
		check(not denied.applied and rig_state(private)==before,"private rig converted to gameplay refuses copied historical tag without mutation")
		check(denied.status=="Core-only preset requires a private diagnostic preview; original retained","converted private rig refusal reaches the explicit permission gate")
		private.posture.editor_preview_mode=true
		var sequence=Sequence.new();sequence.configure(source,Sequence.Mode.STROKE_ONLY)
		var count:=0
		for index in range(961):
			var seconds:float=float(bake.duration)*float(index)/960.0
			var pose:PostureDefinition=sequence.sample(seconds).pose
			Fixture.capture(private,pose,seconds,false)
			var result:Dictionary=private.get_meta("elbow_preset_report",{})
			check(not pose.has_meta(Runtime.SAMPLE_META),"stale diagnostic sequence receives no runtime tag")
			check(not bool(result.get("applied",false)),"private diagnostic playback refuses stale certificate")
			var unchanged:PackedByteArray=rig_state(private)
			var refused:Dictionary=Runtime.apply(private,pose)
			check(not refused.applied and rig_state(private)==unchanged,"stale diagnostic refusal occurs without rig mutation")
			if result.get("applied",false):count+=1
		output.diagnostic.append({"case":source.posture_id,"source_matches":source_matches,"historical_replay_samples":961,"applied":count,"newly_certified_positive_replay":"UNVERIFIED"})
		check(same_bake(source.elbow_preset_bake,original),"runtime refusal preserves original certificate payload")
		for mode in [Sequence.Mode.STROKE,Sequence.Mode.TO_READY,Sequence.Mode.RECEIVE_STROKE,Sequence.Mode.SERVE_RECEIVE]:
			sequence.configure(source,mode)
			for index in range(33):
				var pose:PostureDefinition=sequence.sample(sequence.duration*float(index)/32.0).pose
				view.show_pose(pose)
				check(not pose.has_meta(Runtime.SAMPLE_META) and not bool(private.get_meta("elbow_preset_report",{}).get("applied",false)),"private rig cannot activate core overlay in full actions")
		for context in [[0,1,true],[0,2,true],[1,0,true],[2,0,true],[0,0,false]]:
			sequence.configure(source,Sequence.Mode.STROKE_ONLY,context[0],context[1],context[2],private)
			for progress in [0.0,.5,1.0]:check(not sequence._stroke_pose(progress).has_meta(Runtime.SAMPLE_META),"unsupported private diagnostic context refuses")
	view.queue_free();await process_frame
