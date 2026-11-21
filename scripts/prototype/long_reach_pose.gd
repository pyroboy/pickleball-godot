extends RefCounted
## Isolated, deterministic long-reach presentation. No authored resource writes.
## Body travel follows a planted lead foot; the trailing foot gathers afterwards.
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const DURATION := 1.80
const CONTACT_TIME := 0.43
const MAX_TRAVEL := 0.58
const KEY_TIMES: Array = [0.0,0.10,0.29,0.43,0.70,1.10,1.45,1.80]
const ROOT: Array = [0.0,0.0,0.42,1.0,1.0,1.0,1.0,1.0]
const DROP: Array = [0.0,-0.09,-0.23,-0.39,-0.39,-0.39,-0.09,0.0]
const LEAN: Array = [0.0,0.0,0.05,0.15,0.13,0.06,0.0,0.0]
# Preserve the approved low/mid lunge exactly. Taller contacts progressively
# trade lateral travel for a supported, much shallower stance. The actual rig
# still has to pass its planted-leg and finite-paddle admission checks.
const HIGH_START_HEIGHT := 1.05
const HIGH_FULL_HEIGHT := 1.25
const HIGH_MAX_TRAVEL := 0.28
const HIGH_DROP: Array = [0.0,-0.035,-0.07,-0.07,-0.07,-0.045,0.0,0.0]
const HIGH_LEAN: Array = [0.0,0.0,0.015,0.035,0.03,0.015,0.0,0.0]

static func height_weight(contact_height:float)->float:
	return smoothstep(HIGH_START_HEIGHT,HIGH_FULL_HEIGHT,contact_height) if is_finite(contact_height) else 0.0

static func maximum_travel(contact_height:float)->float:
	return lerpf(MAX_TRAVEL,HIGH_MAX_TRAVEL,height_weight(contact_height))

static func sample(time_seconds:float,direction:Vector3=Vector3.RIGHT,travel:float=MAX_TRAVEL,backhand:bool=false,contact_height:float=.5)->Dictionary:
	var t:float=clampf(time_seconds,0.0,DURATION) if is_finite(time_seconds) else 0.0
	var toward:=Vector3(direction.x,0,direction.z)
	if not toward.is_finite() or toward.length_squared()<0.000001:toward=Vector3.LEFT if backhand else Vector3.RIGHT
	toward=toward.normalized()
	var high:float=height_weight(contact_height)
	var distance:float=clampf(travel,0.0,maximum_travel(contact_height)) if is_finite(travel) else 0.0
	var lead:float=smoothstep(.10,.29,t)
	var trail:float=smoothstep(.78,1.10,t)
	var lead_lift:float=_lift(t,.10,.29,.055)
	var trail_lift:float=_lift(t,.78,1.10,.055)
	var turn:float=smoothstep(.04,.34,t)*(1.0-smoothstep(1.02,1.65,t))
	var counter:float=smoothstep(.08,.38,t)*(1.0-smoothstep(.80,1.55,t))
	var contact:float=smoothstep(.20,.40,t)*(1.0-smoothstep(.58,.90,t))
	var motion:Dictionary={"phase":_phase(t),"progress":t/DURATION,"finished":t>=DURATION,"backhand":backhand,
		"root_offset":toward*_curve(t,ROOT)*distance,"body_offset":Vector3.UP*_curve(t,DROP),
		"body_rotation":Vector3.UP.cross(toward)*_curve(t,LEAN),"body_yaw":deg_to_rad(25.0 if backhand else -8.0)*turn,
		"torso_yaw":deg_to_rad(63.0 if backhand else -7.0)*turn,"counterbalance_weight":counter,
		"pole_weight":smoothstep(0.,.12,t)*(1.-smoothstep(1.55,1.80,t)),
		"paddle_offset":toward*.10*contact+Vector3.DOWN*.13*contact,"paddle_rotation":Vector3.ZERO,"contact_weight":contact,
		"lead_travel":distance*lead,"trail_travel":distance*trail,"lead_lift":lead_lift,"trail_lift":trail_lift,
		"lead_planted":lead_lift<=.000001,"trail_planted":trail_lift<=.000001,
		"lead_yaw_weight":lead,"trail_yaw_weight":trail,"airborne":false}
	if high<=0.0:return motion
	motion["height_weight"]=high
	motion["body_offset"]=Vector3.UP*lerpf(_curve(t,DROP),_curve(t,HIGH_DROP),high)
	motion["body_rotation"]=Vector3.UP.cross(toward)*lerpf(_curve(t,LEAN),_curve(t,HIGH_LEAN),high)
	motion["body_yaw"]=deg_to_rad(lerpf(25.0,20.0,high) if backhand else -8.0)*turn
	# Extension is about the same real waist as the chest turn; the head and
	# both shoulder sockets follow it. It is not an arm-length or body-scale edit.
	motion["torso_extension"]=deg_to_rad(16.0)*turn*high
	motion["paddle_offset"]=toward*.10*contact+Vector3.UP*lerpf(-.13,.15,high)*contact
	motion["lead_lift"]=lead_lift*lerpf(1.0,.64,high)
	motion["trail_lift"]=trail_lift*lerpf(1.0,.64,high)
	motion["lead_planted"]=float(motion.lead_lift)<=.000001
	motion["trail_planted"]=float(motion.trail_lift)<=.000001
	# A lateral adjustment keeps the READY shoe heading. It never swivels a
	# planted foot, and gathers into the translated READY stance exactly.
	motion["lead_yaw_weight"]=lead*(1.0-high)
	motion["trail_yaw_weight"]=trail*(1.0-high)
	return motion

static func capture_base(actor)->Dictionary:
	var torso:Node3D=actor.body_pivot.get_node("TorsoMesh")
	var hips:Node3D=actor.body_pivot.get_node("HipsMesh")
	var skin=actor.body_pivot.get_meta("articulated_torso")
	var base:Dictionary={"body":actor.body_pivot.transform,"torso":torso.transform,"hips":hips.transform,
		"pelvis":skin._last_pelvis,"abdomen":skin._last_abdomen,"chest":skin._last_chest,
		"right_arm":actor.right_arm_node.transform,"left_arm":actor.left_arm_node.transform}
	base["support_wrist"]=torso.to_local(actor.left_arm_node.anatomical_wrist_world)
	base["support_elbow"]=torso.to_local(actor.left_arm_node.forearm_pivot.global_position)
	base["main_elbow"]=torso.to_local(actor.right_arm_node.forearm_pivot.global_position)
	base["support_mount"]=torso.global_transform.affine_inverse()*actor.left_arm_node.hand_mesh.global_transform
	var model=actor.left_arm_node.articulated_hand
	base["support_channels"]=Anatomy.decompose(Anatomy.forearm_reference_for_arm(actor.left_arm_node,actor.left_arm_node.anatomical_wrist_world,true),actor.left_arm_node.hand_mesh.global_basis*model.anatomical_basis,model.radial_sign)
	base["support_hand_pose"]={"mode":model._mode,"closure":model._closure,"index":model._index_closure/maxf(model._closure,.00001),"style":model._support_style_weight}
	return base

static func apply_body(actor,base:Dictionary,motion:Dictionary)->void:
	# Rotate around the ready pose's waist, not the player origin. The visible
	# skin, hidden TorsoMesh/head, and both actual shoulder sockets share frames.
	var chest:Transform3D=base.chest
	var waist:Vector3=chest.origin-chest.basis*Vector3.UP*Dimensions.WAIST_TO_CHEST
	var chest_basis:=Basis(Vector3.UP,float(motion.torso_yaw))
	if float(motion.get("height_weight",0.0))>0.0:
		chest_basis=chest_basis*Basis(Vector3.RIGHT,float(motion.get("torso_extension",0.0)))
	var turn:=Transform3D(chest_basis,Vector3.ZERO)
	turn.origin=waist-turn.basis*waist
	chest=turn*chest
	var torso:Node3D=actor.body_pivot.get_node("TorsoMesh")
	torso.transform=turn*base.torso
	actor.body_pivot.get_node("HipsMesh").transform=base.hips
	actor.body_pivot.get_meta("articulated_torso").update_frames(base.pelvis,base.abdomen,chest)
	actor.right_arm_node.transform=turn*base.right_arm
	actor.left_arm_node.transform=turn*base.left_arm
	actor.body_pivot.transform=base.body
	actor.body_pivot.position+=motion.body_offset
	actor.body_pivot.rotation+=motion.body_rotation+Vector3.UP*float(motion.body_yaw)

static func main_pole(actor,_wrist:Vector3,_mount:Transform3D,motion:Dictionary,base:Dictionary={})->Vector3:
	# An outboard elbow remains clear while the one-handed backhand turns.
	# A wrist-only conditioned pole can rotate the elbow through the ribcage.
	var torso:Node3D=actor.body_pivot.get_node("TorsoMesh")
	var outboard:Vector3=actor.right_arm_node.upper_pivot.global_position+torso.global_basis.x
	if base.is_empty():return outboard
	return torso.to_global(base.main_elbow).lerp(outboard,float(motion.pole_weight))

static func _lift(t:float,start:float,end:float,height:float)->float:
	if t<=start or t>=end:return 0.0
	var u:float=(t-start)/(end-start)
	return height*16*u*u*(1-u)*(1-u)
static func _curve(t:float,values:Array)->float:
	for i in range(KEY_TIMES.size()-1):
		if t<=float(KEY_TIMES[i+1]):return lerpf(float(values[i]),float(values[i+1]),smoothstep(float(KEY_TIMES[i]),float(KEY_TIMES[i+1]),t))
	return float(values[-1])
static func _phase(t:float)->StringName:
	if t<.10:return &"load_and_turn"
	if t<.29:return &"long_lead_step"
	if t<.40:return &"plant_and_load"
	if t<.57:return &"long_reach_contact"
	if t<.78:return &"supported_extension"
	if t<1.10:return &"gather_trailing_foot"
	if t<DURATION:return &"rise_and_recover"
	return &"complete"
