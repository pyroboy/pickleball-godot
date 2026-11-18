extends SceneTree
const Grip = preload("res://scripts/paddle_grip_frame.gd")
class MockAxes extends RefCounted:
	var global_transform := Transform3D.IDENTITY
	var side := 0
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if side == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if side == 0 else Vector3.BACK
	func _get_swing_sign() -> float: return -1.0 if side == 0 else 1.0
const Axes = preload("res://scripts/ui/mobile_pose_gizmo_axes.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const Contact = preload("res://scripts/serve_contact_orientation.gd")
const ROT = ["paddle_pitch_base_deg","paddle_yaw_base_deg","paddle_roll_base_deg"]
var failures: Array[String] = []
var count := 0
var preview
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error(label)
func observed_axis(before:Basis,after:Basis)->Vector3:
	return (before.x.cross(after.x)+before.y.cross(after.y)+before.z.cross(after.z)).normalized()
func check_basis(before:Basis,after:Basis,axis:Vector3,label:String)->void:
	check(observed_axis(before,after).dot(axis)>.99999,label)
func run()->void:
	_check_algebra()
	create_timer(90).timeout.connect(func():quit(2))
	preview=Preview.new();root.add_child(preview)
	await process_frame;await process_frame
	var p=preview.player
	for side in [0,1]:
		p.player_num=side
		var pose:PostureDefinition=PostureLibrary.instance().get_def(0).duplicate(true)
		pose.body_pitch_deg=21;pose.body_yaw_deg=34;pose.body_roll_deg=-17
		pose.hip_yaw_deg=19;pose.spine_curve_deg=13
		pose.torso_pitch_deg=-11;pose.torso_yaw_deg=-37;pose.torso_roll_deg=24
		pose.head_pitch_deg=23;pose.head_yaw_deg=-18
		pose.right_shoulder_rotation_deg=Vector3(23,-34,47);pose.left_shoulder_rotation_deg=Vector3(-17,29,37)
		pose.paddle_pitch_base_deg=29;pose.paddle_yaw_base_deg=-41;pose.paddle_roll_base_deg=53
		pose.paddle_pitch_signed_deg=7;pose.paddle_pitch_sign_source=1;pose.paddle_in_hand_rotation_deg=16
		pose.right_foot_offset.y=.35;pose.left_foot_offset.y=.35
		pose.right_foot_pitch_deg=5;pose.left_foot_pitch_deg=5
		pose.right_foot_yaw_deg=24;pose.left_foot_yaw_deg=-34;pose.left_hand_mode=1
		for entry in [
			["hips",0,"body_pitch_deg",func():return p.body_pivot.global_basis],
			["hips",1,"hip_yaw_deg",func():return p.body_pivot.get_node("HipsMesh").global_basis],
			["hips",2,"body_roll_deg",func():return p.body_pivot.global_basis],
			["torso",0,"torso_pitch_deg",func():return p.body_pivot.get_node("TorsoMesh").global_basis],
			["torso",1,"torso_yaw_deg",func():return p.body_pivot.get_node("TorsoMesh").global_basis],
			["torso",2,"torso_roll_deg",func():return p.body_pivot.get_node("TorsoMesh").global_basis],
			["head",0,"head_pitch_deg",func():return p.body_pivot.get_node("TorsoMesh/HeadMesh").global_basis],
			["head",1,"head_yaw_deg",func():return p.body_pivot.get_node("TorsoMesh/HeadMesh").global_basis],
			["right_foot",0,"right_foot_pitch_deg",func():return p.right_leg_node.foot_pivot.global_basis],
			["right_foot",1,"right_foot_yaw_deg",func():return p.right_leg_node.foot_pivot.global_basis],
			["left_foot",0,"left_foot_pitch_deg",func():return p.left_leg_node.foot_pivot.global_basis],
			["left_foot",1,"left_foot_yaw_deg",func():return p.left_leg_node.foot_pivot.global_basis],
			["right_hand",1,"main_grip_rotation_deg",func():return p.right_arm_node.hand_mesh.global_basis],
			["left_hand",1,"support_grip_rotation_deg",func():return p.left_arm_node.hand_mesh.global_basis],
		]:
			preview.show_pose(pose)
			var axes=Axes.for_selection(p,pose,entry[0],true)
			var before:Basis=entry[3].call()
			var after=pose.duplicate(true);after.set(entry[2],float(after.get(entry[2]))+.05)
			preview.show_pose(after)
			check_basis(before,entry[3].call(),axes[entry[1]],"side %d actual %s"%[side,entry[2]])
		preview.show_pose(pose)
		for id in ["right_elbow","left_elbow"]:
			var arm=p.right_arm_node if id.begins_with("right") else p.left_arm_node
			var angles:Vector3=pose.get(id.replace("elbow","shoulder_rotation_deg"))
			var pole:Vector3=p.global_position+Vector3(.4,-.7,.2)
			var before:Vector3=p.arm_ik._rotate_shoulder_pole(arm,pole,angles)
			var move=Axes.for_selection(p,pose,id,false)
			var stance=[p._get_forehand_axis(),Vector3.UP,p._get_forward_axis()]
			for axis in range(3):
				var after:Vector3=p.arm_ik._rotate_shoulder_pole(arm,pole+stance[axis]*.01,angles)
				check((after-before).normalized().dot(move[axis])>.99999,"side %d %s move %d"%[side,id,axis])
		for id in ["right_hand","left_hand"]:
			check(Axes.for_selection(p,pose,id,false)[1].dot(p.paddle_node.global_basis.y)>.99999,"grip slide actual shaft")
		for style in range(7):
			var def=Serve.get_default(style)
			def.paddle_pitch_base_deg+=13;def.paddle_yaw_base_deg-=17;def.paddle_roll_base_deg+=21
			def.paddle_in_hand_rotation_deg=19
			var sample=Serve.sample(def,.5)
			preview.show_pose(sample)
			var axes=Axes.for_selection(p,sample,"paddle",true)
			var before:Transform3D=p.paddle_node.global_transform
			var face:Vector3=before*(Size.HEAD_OFFSET+Vector3.BACK*Contact.CONTACT_DISTANCE)
			for axis in range(3):
				var changed=def.duplicate(true);changed.set(ROT[axis],float(changed.get(ROT[axis]))+.05)
				var after_sample=Serve.sample(changed,.5)
				preview.show_pose(after_sample)
				var after:Transform3D=p.paddle_node.global_transform
				check_basis(before.basis,after.basis,axes[axis],"side %d serve %d axis %d"%[side,style,axis])
				check(face.distance_to(after*(Size.HEAD_OFFSET+Vector3.BACK*Contact.CONTACT_DISTANCE))<.00001,"serve Contact fixed ball point")
	print("Gizmo axis regression: %d checked, %d failed"%[count,failures.size()])
	preview.queue_free();await process_frame
	quit(1 if not failures.is_empty() else 0)

func _check_algebra() -> void:
	for side in [0,1]:
		var p := MockAxes.new(); p.side=side
		p.global_transform.basis=Basis.from_euler(Vector3(.1,.2,.3))
		var pose=load("res://scripts/posture_definition.gd").new()
		pose.body_pitch_deg=21; pose.body_yaw_deg=34; pose.body_roll_deg=-17
		pose.hip_yaw_deg=19; pose.spine_curve_deg=13
		pose.torso_pitch_deg=-11; pose.torso_yaw_deg=-37; pose.torso_roll_deg=24
		pose.head_pitch_deg=23; pose.head_yaw_deg=-18
		pose.paddle_pitch_base_deg=29; pose.paddle_yaw_base_deg=-41; pose.paddle_roll_base_deg=53
		pose.paddle_pitch_signed_deg=7; pose.paddle_pitch_sign_source=1
		pose.paddle_in_hand_rotation_deg=16
		var s=Basis(p._get_forehand_axis(),Vector3.UP,-p._get_forward_axis())
		var g=p.global_transform.basis
		var b=g*Body.untranslated_pivot_transform(p,pose).basis
		var t=b*Body.waist_transform(p,pose,false).basis*s
		var h=b*Body.torso_transform(p,pose,false).basis
		var rotation=pose.resolve_paddle_rotation_deg(-1,-1)*PI/180.0
		for pair in [
			["body_pitch_deg",-(g*s*ry(-pose.body_yaw_deg)*Vector3.RIGHT),func(v):return g*Body.untranslated_pivot_transform(p,v).basis],
			["body_yaw_deg",-(g*s*Vector3.UP),func(v):return g*Body.untranslated_pivot_transform(p,v).basis],
			["body_roll_deg",g*s*ry(-pose.body_yaw_deg)*rx(-pose.body_pitch_deg)*Vector3.BACK,func(v):return g*Body.untranslated_pivot_transform(p,v).basis],
			["hip_yaw_deg",-(b*Vector3.UP),func(v):return b*Body.pelvis_transform(p,v,false).basis],
			["torso_pitch_deg",-(t*ry(-pose.torso_yaw_deg)*Vector3.RIGHT),func(v):return b*Body.torso_transform(p,v,false).basis],
			["torso_yaw_deg",-(t*Vector3.UP),func(v):return b*Body.torso_transform(p,v,false).basis],
			["torso_roll_deg",t*ry(-pose.torso_yaw_deg)*rx(-(28+pose.torso_pitch_deg))*Vector3.BACK,func(v):return b*Body.torso_transform(p,v,false).basis],
			["head_pitch_deg",(h*ry(-pose.head_yaw_deg)*Vector3.RIGHT)*p._get_swing_sign(),func(v):return h*Basis.from_euler(Vector3(v.head_pitch_deg*p._get_swing_sign(),-v.head_yaw_deg,0)*PI/180.0)],
			["head_yaw_deg",-(h*Vector3.UP),func(v):return h*Basis.from_euler(Vector3(v.head_pitch_deg*p._get_swing_sign(),-v.head_yaw_deg,0)*PI/180.0)],
			["paddle_pitch_base_deg",s*Vector3.RIGHT,func(v):return Path.paddle_basis(p,v)],
			["paddle_yaw_base_deg",s*Basis(Vector3.RIGHT,rotation.x)*Vector3.UP,func(v):return Path.paddle_basis(p,v)],
			["paddle_roll_base_deg",s*Basis(Vector3.RIGHT,rotation.x)*Basis(Vector3.UP,rotation.y)*Vector3.FORWARD,func(v):return Path.paddle_basis(p,v)],
		]:
			_verify_algebra("%d/%s"%[side,pair[0]],pose,pair[0],pair[1],pair[2])
		var angles=Vector3(23,-34,47)*PI/180.0
		for axis in range(3):
			var before=s*Basis.from_euler(angles)*s.inverse()
			var after_angles=angles;after_angles[axis]+=deg_to_rad(.02)
			var after=s*Basis.from_euler(after_angles)*s.inverse()
			var expected=[s*Basis(Vector3.UP,angles.y)*Vector3.RIGHT,s*Vector3.UP,s*Basis(Vector3.UP,angles.y)*Basis(Vector3.RIGHT,angles.x)*Vector3.BACK][axis]
			_check_algebra_basis("%d/shoulder_%d"%[side,axis],before,after,expected)
		var pb=Path.paddle_basis(p,pose)
		_check_algebra_basis("%d/grip"%side,Grip.basis(pb,false,19),Grip.basis(pb,false,19.02),pb.y)
func rx(deg:float)->Basis:return Basis(Vector3.RIGHT,deg_to_rad(deg))
func ry(deg:float)->Basis:return Basis(Vector3.UP,deg_to_rad(deg))
func _verify_algebra(label:String,pose,field:String,axis:Vector3,basis_for:Callable)->void:
	var changed=pose.duplicate(true);changed.set(field,float(pose.get(field))+.02)
	_check_algebra_basis(label,basis_for.call(pose),basis_for.call(changed),axis)
func _check_algebra_basis(label:String,before:Basis,after:Basis,expected:Vector3)->void:
	var observed=(before.x.cross(after.x)+before.y.cross(after.y)+before.z.cross(after.z)).normalized()
	check(observed.dot(expected.normalized())>.99999,"algebra "+label)
