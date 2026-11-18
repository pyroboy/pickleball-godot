extends SceneTree
const R=preload("res://scripts/paddle_rotation.gd")
const Path=preload("res://scripts/stroke_swing_path.gd")
const Key=preload("res://scripts/stroke_body_keyframe.gd")
const Store=preload("res://scripts/mobile_pose_store.gd")
const Serve=preload("res://scripts/mobile_serve_pose_store.gd")
const Sequence=preload("res://scripts/ui/mobile_pose_sequence.gd")
const Motion=preload("res://scripts/drive_serve_motion.gd")
const Preview=preload("res://scripts/ui/mobile_pose_preview.gd")
var checks:=0
var failures:Array[String]=[]
var worst_basis_error:=0.0
var worst_elbow_error:=0.0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func near(a:Basis,b:Basis,label:String)->void:
	var error:float=maxf(a.x.distance_to(b.x),maxf(a.y.distance_to(b.y),a.z.distance_to(b.z)))
	worst_basis_error=maxf(worst_basis_error,error);check(error<.00008,label+" basis error "+str(error))
func fixture()->PostureDefinition:
	var p:=PostureDefinition.new();p.posture_id=0;p.family=2
	p.paddle_forehand_mul=.4;p.paddle_y_offset=.12;p.paddle_forward_mul=.35
	p.paddle_pitch_base_deg=23;p.paddle_yaw_base_deg=41;p.paddle_roll_base_deg=-19
	p.charge_paddle_offset=Vector3(-.06,.02,-.04);p.ft_paddle_offset=Vector3(.04,.08,.06)
	p.charge_paddle_rotation_deg=Vector3(12,-18,28);p.ft_paddle_rotation_deg=Vector3(-26,31,16)
	p.windup_body=Key.new();p.follow_through_body=Key.new()
	p.windup_body.values={"main_grip_rotation_deg":-11.0,"paddle_pitch_signed_deg":8.0,"paddle_pitch_sign_source":2}
	p.follow_through_body.values={"main_grip_rotation_deg":15.0,"paddle_pitch_signed_deg":-7.0,"paddle_pitch_sign_source":1}
	return p
func shifted(p:PostureDefinition)->PostureDefinition:
	var q:PostureDefinition=p.duplicate(true)
	for field in R.BASE+R.SIGNED+R.GRIP:q.set(field,float(q.get(field))+360.0)
	q.charge_paddle_rotation_deg+=Vector3(360,-360,720);q.ft_paddle_rotation_deg+=Vector3(-720,360,-360)
	for body in [q.windup_body,q.follow_through_body]:
		if body!=null:
			for field in R.SIGNED+R.GRIP:
				if body.values.has(field):body.values[field]+=360.0
	return q
func normalization()->void:
	for input in [-1080.0,-720.1,-720.0,-360.0,-180.1,-180.0,0.0,180.0,180.1,360.0,720.0,1080.1]:
		var n:float=R.degrees(input);check(n>=-180 and n<180,"bounded "+str(input));near(R.basis(Vector3(input,0,0)),R.basis(Vector3(n,0,0)),"whole-turn basis")
	var p:=fixture();var q:=shifted(p);var before:PostureDefinition=q.duplicate(true)
	check(R.normalize_pose(q),"normalization detects changes");check(not R.normalize_pose(q),"normalization idempotent")
	for stage in range(3):
		var a:PostureDefinition=Path.endpoint(before,stage);var b:PostureDefinition=Path.endpoint(q,stage)
		check(a.resolve_paddle_offset(Vector3.RIGHT,Vector3.FORWARD)==b.resolve_paddle_offset(Vector3.RIGHT,Vector3.FORWARD),"normalization preserves authored XYZ")
		for ss in [-1.0,0.0,1.0]:
			for fs in [-1.0,0.0,1.0]:near(R.displayed_basis(a,ss,fs),R.displayed_basis(b,ss,fs),"all sign contexts")
	check(q.right_hand_offset==before.right_hand_offset and q.right_elbow_pole==before.right_elbow_pole,"normalization preserves grip seat/elbow")
	var encoded:Dictionary=Store._encode_fields(before);var decoded:=PostureDefinition.new();Store._apply_fields(decoded,encoded)
	check(encoded.paddle_pitch_base_deg==q.paddle_pitch_base_deg,"save/copy serializes canonical angles")
	check(before.paddle_pitch_base_deg>180,"encoding does not mutate original")
	for t in range(41):near(R.displayed_basis(Path.sample(p,t/40.0)),R.displayed_basis(Path.sample(decoded,t/40.0)),"decoded playback")
func fingerprint_checks()->void:
	var pose:=fixture()
	var fields:Dictionary=Store._encode_fields(pose,false)
	var codec=load("res://scripts/elbow_preset_bake.gd")
	var old:Dictionary={"model":codec.MODEL_VERSION,"scope":"stroke_runtime","source_id":pose.posture_id,"handedness":pose.paddle_hand,"fields":fields}
	var old_hash:String=JSON.stringify(codec._checksum_value(old),"",true,true).sha256_text()
	check(old_hash!=Store.authored_fingerprint(pose,"stroke_runtime"),"old interpolation bake fingerprint is stale without deleting it")
	check(Store.authored_fingerprint(pose)==Store.authored_fingerprint(shifted(pose)),"equivalent full turns share normalized source fingerprint")
	for y in [-90.0,-89.9999,-89.95,89.95,89.9999,90.0]:
		var basis:Basis=R.basis(Vector3(33,y,58))
		near(basis,R.basis(R.euler(basis)),"near gimbal endpoint basis preserved")

func interpolation()->void:
	var a:=fixture();var b:=fixture()
	# This XYZ Euler branch has exactly the same orientation, despite each
	# component being different. Axis-wise lerp takes a spurious large excursion.
	b.paddle_pitch_base_deg=a.paddle_pitch_base_deg+180
	b.paddle_yaw_base_deg=180-a.paddle_yaw_base_deg
	b.paddle_roll_base_deg=a.paddle_roll_base_deg+180
	near(R.displayed_basis(a),R.displayed_basis(b),"alternate branch endpoints")
	var legacy:Basis=R.basis(Vector3(lerp_angle(deg_to_rad(a.paddle_pitch_base_deg),deg_to_rad(b.paddle_pitch_base_deg),.5),lerp_angle(deg_to_rad(a.paddle_yaw_base_deg),deg_to_rad(b.paddle_yaw_base_deg),.5),lerp_angle(deg_to_rad(a.paddle_roll_base_deg),deg_to_rad(b.paddle_roll_base_deg),.5))*(180.0/PI))
	check(legacy.x.distance_to(R.displayed_basis(a).x)>.5,"reproduces old per-axis branch excursion")
	for t in range(41):near(R.displayed_basis(a.lerp_with(b,t/40.0)),R.displayed_basis(a),"equivalent branch stays still")
	b=a.duplicate(true);b.paddle_pitch_signed_deg=360;b.paddle_pitch_sign_source=1
	for t in range(41):near(R.displayed_basis(a.lerp_with(b,t/40.0)),R.displayed_basis(a),"signed full turn stays still")
	a.paddle_pitch_base_deg=0;a.paddle_yaw_base_deg=179;a.paddle_roll_base_deg=0;b=a.duplicate(true);b.paddle_yaw_base_deg=-179
	near(R.displayed_basis(a.lerp_with(b,.5)),R.basis(Vector3(0,180,0)),"179 to -179 uses 2-degree path")
	# Equivalent complete paddle bases can also be encoded by a compensating
	# local shaft spin. Slerp must use the complete displayed frame.
	a=fixture();b=a.duplicate(true);b.paddle_in_hand_rotation_deg=93
	R.set_basis(b,R.unspun_basis(a)*Basis(Vector3.UP,deg_to_rad(-93)))
	for t in range(41):near(R.displayed_basis(a.lerp_with(b,t/40.0)),R.displayed_basis(a),"combined spin/base equivalence")
	for hand in range(2):
		var p:=fixture();p.paddle_hand=hand;var q:=shifted(p)
		for t in range(101):
			near(R.displayed_basis(Path.sample(p,t/100.0)),R.displayed_basis(Path.sample(q,t/100.0)),"stroke windup-contact-finish full-turn equivalence")
		var sa:=Sequence.new();var sb:=Sequence.new();sa.configure(p,Sequence.Mode.TO_READY,0,0,false);sb.configure(q,Sequence.Mode.TO_READY,0,0,false)
		for t in range(101):near(R.displayed_basis(sa.sample(sa.duration*t/100.0).pose),R.displayed_basis(sb.sample(sb.duration*t/100.0).pose),"prep recovery equivalent")
func runtime_checks()->void:
	for p in PostureLibrary.instance().all_definitions():
		var q:PostureDefinition=p.duplicate(true);q.paddle_roll_base_deg+=360.0
		for charge in [.0,.35,.7,1.0]:
			for t in [0.0,.25,.5,.75,1.0]:
				near(R.displayed_basis(Motion.sample_drive(p,t,charge)),R.displayed_basis(Motion.sample_drive(q,t,charge)),"runtime full turn %d charge %.2f phase %.2f"%[p.posture_id,charge,t])

func serve_checks()->void:
	for style in range(Serve.STYLE_NAMES.size()):
		var p:PostureDefinition=Serve.get_default(style);var q:=shifted(p)
		for t in range(41):near(R.displayed_basis(Serve.sample(p,t/40.0)),R.displayed_basis(Serve.sample(q,t/40.0)),"serve full turn style "+str(style))
func rig_checks()->void:
	var a:=Preview.new();var b:=Preview.new();root.add_child(a);root.add_child(b)
	await process_frame;await process_frame
	# Compare the same solver context; preview and live use different continuity histories.
	a.player.posture.editor_preview_mode=not "--live-solver" in OS.get_cmdline_user_args();b.player.posture.editor_preview_mode=a.player.posture.editor_preview_mode
	for side in range(2):
		a.player.player_num=side;b.player.player_num=side
		for hand in range(2):
			for id in [0,2,10,11,18,20]:
				var p:PostureDefinition=PostureLibrary.instance().get_def(id).duplicate(true);p.paddle_hand=hand
				var q:=shifted(p)
				for step in range(33):
					var t:float=step/32.0
					a.show_pose(Path.sample(p,t));b.show_pose(Path.sample(q,t))
					near(a.player.paddle_node.global_basis,b.player.paddle_node.global_basis,"actual preview/gameplay orientation")
					check(a.player.paddle_node.global_position.distance_to(b.player.paddle_node.global_position)<.00005,"actual paddle origin preserves equivalent keys")
					for joint in ["right_elbow","left_elbow","right_hand","left_hand"]:
						var error:float=a.joint_world_position(joint).distance_to(b.joint_world_position(joint));worst_elbow_error=maxf(worst_elbow_error,error)
						check(error<.00005,"actual rig equivalence %s pose%d side%d hand%d t%.3f error%.9f"%[joint,id,side,hand,t,error])
	a.queue_free();b.queue_free();await process_frame

func run()->void:
	Store.set_test_path("user://pose_store_tests/angles_%d/poses.json"%OS.get_process_id())
	Serve.set_test_path("user://pose_store_tests/angles_%d/serves.json"%OS.get_process_id())
	normalization();fingerprint_checks();interpolation();serve_checks();runtime_checks();await rig_checks()
	print(JSON.stringify({"suite":"paddle_angle_normalization","checks":checks,"failures":failures,"worst_basis_error":worst_basis_error,"worst_elbow_error_m":worst_elbow_error}))
	quit(0 if failures.is_empty() else 1)
