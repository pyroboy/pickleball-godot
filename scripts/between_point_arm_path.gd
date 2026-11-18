extends RefCounted
const Anatomy=preload("res://scripts/arm_anatomy.gd")
const Sleeve=preload("res://scripts/live_ready_clearance.gd")
const SleeveQuery=preload("res://scripts/between_sleeve_clearance.gd")
const Budget=preload("res://scripts/live_arm_budget.gd")
var actor
var had_cup_request:bool=false
var start_wrist:Vector3
var start_elbow:Vector3
var start_channels:Dictionary
var finger_rotations:Array=[]
var last_basis:Basis
var last_elbow:Vector3
var last_upper:Basis
var last_fore:Basis
var last_center:Vector3
var last_body:Transform3D
var cup_geometry:Dictionary={}
var catch_surface_work_remaining:int=-1
var exit_basis:Basis
var exit_wrist:Vector3
var exit_elbow:Vector3
var exit_fingers:Array=[]
func begin_exit()->void:
 exit_basis=actor.left_arm_node.hand_mesh.global_basis.orthonormalized()
 var arm=actor.left_arm_node
 exit_wrist=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
 exit_elbow=arm.forearm_pivot.global_position
 exit_fingers.clear()
 for bone in arm.articulated_hand.skeleton.get_bone_count():exit_fingers.append(arm.articulated_hand.skeleton.get_bone_pose_rotation(bone))
func _init(player):
 actor=player
 var arm=actor.left_arm_node;var torso:Node3D=actor.body_pivot.get_node("TorsoMesh")
 var wrist:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
 last_center=arm.hand_mesh.global_transform*arm.articulated_hand.cup_ball_center
 last_basis=arm.hand_mesh.global_basis.orthonormalized()
 last_elbow=arm.forearm_pivot.global_position
 last_upper=arm.upper_pivot.global_basis.orthonormalized();last_fore=arm.forearm_pivot.global_basis.orthonormalized();last_body=actor.body_pivot.global_transform
 start_wrist=torso.to_local(wrist);start_elbow=torso.to_local(arm.forearm_pivot.global_position)
 start_channels=Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm,wrist,true),arm.hand_mesh.global_basis*arm.articulated_hand.anatomical_basis,-1.0)
 for bone in arm.articulated_hand.skeleton.get_bone_count():finger_rotations.append(arm.articulated_hand.skeleton.get_bone_pose_rotation(bone))
static func clock_weight(progress:float)->float:
 var u:=clampf(progress,0.0,1.0);var ramp:=.10
 if u<ramp:return (u-ramp/PI*sin(PI*u/ramp))*.5/(1.0-ramp)
 if u>1.0-ramp:return 1.0-clock_weight(1.0-u)
 return (u-.5*ramp)/(1.0-ramp)
func apply(owner,pose)->void:
 if pose==null:return
 var arm=actor.left_arm_node;var model=arm.articulated_hand
 if owner.phase=="SET_SERVE" and owner.index_for_actor(actor)!=owner.server:
  _apply_receiver_exit(owner,pose)
  return
 var request:Dictionary=owner.hand_presentation_for(actor.get_actor_id())
 # Empty free-hand requests need no cup recovery unless this actual arm
 # previously presented a cup during this between-point ownership interval.
 if not request.is_empty() or (had_cup_request and owner._pass_attempts > 0 and not owner.declined_pass_recovery_for(actor.get_actor_id())):
  if not request.is_empty():had_cup_request=true
  _fit_cup(arm,owner)
  last_center=arm.hand_mesh.global_transform*arm.articulated_hand.cup_ball_center
  last_basis=arm.hand_mesh.global_basis.orthonormalized()
  last_elbow=arm.forearm_pivot.global_position
  last_upper=arm.upper_pivot.global_basis.orthonormalized();last_fore=arm.forearm_pivot.global_basis.orthonormalized();last_body=actor.body_pivot.global_transform
  return
 var wrist:Vector3=arm.hand_mesh.global_transform*model.wrist_socket
 var weight:=clock_weight(owner.elapsed/.35)
 if weight<1.0:
  var torso:Node3D=actor.body_pivot.get_node("TorsoMesh")
  var shoulder:Vector3=arm.upper_pivot.global_position
  var start:Vector3=torso.to_global(start_wrist)-shoulder
  var finish:Vector3=owner._carry_wrist(owner.index_for_actor(actor))-shoulder
  wrist=shoulder+start.normalized().slerp(finish.normalized(),weight)*lerpf(start.length(),finish.length(),weight)
  var radial:Vector3=torso.to_global(start_elbow)-shoulder
  radial=(radial-start.normalized()*radial.dot(start.normalized())).normalized()
  var pole:Vector3=actor.global_position+actor._get_forehand_axis()*(-.58)+Vector3.UP*(-.35)+actor._get_forward_axis()*(-.07)
  pole=actor.arm_ik._rotate_shoulder_pole(arm,pole,Vector3(0,8,0))
  pole=Anatomy.stabilized_pole(shoulder,shoulder+finish,pole,actor._get_forehand_axis())
  var goal:Vector3=pole-shoulder
  goal=(goal-finish.normalized()*goal.dot(finish.normalized())).normalized()
  var a:=Basis(start.normalized(),radial,start.normalized().cross(radial)).orthonormalized()
  var b:=Basis(finish.normalized(),goal,finish.normalized().cross(goal)).orthonormalized()
  var frame:=a.slerp(b,weight)
  pole=shoulder+Quaternion(frame.x,(wrist-shoulder).normalized())*frame.y
  arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
  arm.solve_ik(wrist,pole,null,wrist)
 var reference:Basis=Anatomy.forearm_reference_for_arm(arm,wrist,true)
 var anatomical:Basis=reference*Basis(Vector3.RIGHT,deg_to_rad(-float(start_channels.forearm_axial_deg)*(1.0-weight)))*Basis(Vector3.UP,deg_to_rad(float(start_channels.flexion_deg)*(1.0-weight)))*Basis(Vector3.BACK,deg_to_rad(-float(start_channels.radial_deviation_deg)*(1.0-weight)))
 var basis:Basis=anatomical*model.anatomical_basis.inverse()
 model.set_mesh_world_transform(Transform3D(basis,wrist-basis*model.wrist_socket));model.update_wrist_bridge(arm.fore_mesh.global_basis)
 for bone in range(1,model.WRIST_BRIDGE_BONE):model.skeleton.set_bone_pose_rotation(bone,finger_rotations[bone].slerp(model._data.poses.RELAXED[bone],weight))
 last_center=arm.hand_mesh.global_transform*arm.articulated_hand.cup_ball_center
 last_basis=arm.hand_mesh.global_basis.orthonormalized()
 last_elbow=arm.forearm_pivot.global_position
 last_upper=arm.upper_pivot.global_basis.orthonormalized();last_fore=arm.forearm_pivot.global_basis.orthonormalized();last_body=actor.body_pivot.global_transform
func _fixed_hand(arm,left:bool)->void:
 var mount:Transform3D=arm.hand_mesh.global_transform
 var wrist:Vector3=mount*arm.articulated_hand.wrist_socket
 var fit:Dictionary=Budget.solve(arm.upper_pivot.global_position,wrist,arm.forearm_pivot.global_position,mount.basis*arm.articulated_hand.anatomical_basis,arm.upper_arm_length,arm.forearm_length,left)
 if not fit.feasible:return
 arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
 arm.solve_ik(mount.origin,fit.elbow,null,wrist)
 arm.articulated_hand.set_mesh_world_transform(mount);arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)

func _fit_cup(arm,owner)->void:
 var transaction=Sleeve.Transaction.new(actor);var saved:Dictionary=transaction._snapshot(true)
 var model=arm.articulated_hand
 cup_geometry=Sleeve.body_geometry(actor)
 var original:Transform3D=arm.hand_mesh.global_transform
 var center:Vector3=original*model.cup_ball_center
 var request:Dictionary=owner.hand_presentation_for(actor.get_actor_id())
 if actor.get_meta("between_bounded_admission",false) and owner.phase=="PASS" and request.get("mode","")=="CATCH_OPEN" and actor.current_velocity.length_squared()<.000001:
  _fit_open_catch(arm,transaction,saved,original,center)
  return
 var normal:Vector3=-(original.basis*model.palm_contact_basis.z).normalized()
 var preferred:Basis=(actor.body_pivot.global_basis*last_body.basis.inverse())*last_basis
 if owner.phase=="SET_SERVE":
  var target:Transform3D=actor.arm_ik._hands._serve_grasp_mount(arm,center,0.0,center.y-actor.global_position.y)
  preferred=exit_basis.slerp(target.basis,clock_weight(owner.phase_elapsed/.56))
  original=Transform3D(preferred,center-preferred*model.cup_ball_center)
  normal=-(preferred*model.palm_contact_basis.z).normalized()
 var free_return:bool=owner.hand_presentation_for(actor.get_actor_id()).is_empty()
 if free_return:preferred=original.basis
 var relative:Quaternion=preferred.get_rotation_quaternion()*original.basis.orthonormalized().get_rotation_quaternion().inverse()
 var ideal:=2.0*atan2(Vector3(relative.x,relative.y,relative.z).dot(normal),relative.w)
 var chosen:Dictionary=_cup_candidate(arm,original,center,normal,ideal)
 for step in range(1,73):
  for direction in [-1.0,1.0]:
   var ceiling:float=float(chosen.cost) if not chosen.is_empty() and owner.phase!="SET_SERVE" else INF
   var test:Dictionary=_cup_candidate(arm,original,center,normal,ideal+direction*float(step)*TAU/144.0,ceiling)
   if test.is_empty():continue
   var better:bool=chosen.is_empty() or test.cost<chosen.cost
   if owner.phase=="SET_SERVE" and not chosen.is_empty():
    var error:float=test.basis.get_rotation_quaternion().angle_to(preferred.get_rotation_quaternion())
    var old_error:float=chosen.basis.get_rotation_quaternion().angle_to(preferred.get_rotation_quaternion())
    better=error<old_error-.00001 or absf(error-old_error)<=.00001 and test.cost<chosen.cost
   if better:chosen=test
 if chosen.is_empty():
  var aimed:Basis=Basis(normal,ideal)*original.basis
  for fraction in [.75,.5,.25,0.0]:
   var softened:Basis=last_basis.slerp(aimed,fraction)
   var soft_normal:Vector3=-(softened*model.palm_contact_basis.z).normalized()
   var soft_mount:=Transform3D(softened,center-softened*model.cup_ball_center)
   chosen=_cup_candidate(arm,soft_mount,center,soft_normal,0.0)
   if not chosen.is_empty():break
 if chosen.is_empty():chosen=_cup_cone(arm,center,preferred)
 # A desired open/held hand target is a motion request. If its full current
 # frame is infeasible, advance only as far as a continuous physical arm can
 # support; an actual possessed ball follows that displayed cup below.
 if chosen.is_empty():
  for fraction in [.75,.5,.25,0.0]:
   var start_center:Vector3=actor.body_pivot.global_transform*(last_body.affine_inverse()*last_center) if free_return else last_center
   var reachable_center:Vector3=start_center.move_toward(center, 1.2 * actor.get_physics_process_delta_time())
   var trial_center:Vector3=start_center.lerp(reachable_center,fraction)
   var trial:Transform3D=Transform3D(last_basis,trial_center-last_basis*model.cup_ball_center)
   chosen=_cup_candidate(arm,trial,trial_center,-(last_basis*model.palm_contact_basis.z).normalized(),0.0)
   if chosen.is_empty():chosen=_cup_cone(arm,trial_center,preferred)
   if not chosen.is_empty():
    center=trial_center;break
 transaction._restore(saved)
 var best:=last_basis.get_rotation_quaternion().angle_to(chosen.basis.orthonormalized().get_rotation_quaternion()) if not chosen.is_empty() else INF
 if chosen.is_empty():
  actor.set_meta("between_cup_fit",{"feasible":false});return
 var mount:=Transform3D(chosen.basis,center-chosen.basis*model.cup_ball_center)
 arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
 arm.solve_ik(mount.origin,chosen.elbow,null,chosen.wrist)
 model.set_mesh_world_transform(mount);model.update_wrist_bridge(arm.fore_mesh.global_basis)
 actor.set_meta("between_cup_fit",{"feasible":true,"angle":best})
 if owner.phase=="SET_SERVE":load("res://scripts/carried_cup_continuity.gd").remember(actor)

func _fit_open_catch(arm,transaction,saved:Dictionary,request:Transform3D,target:Vector3)->void:
 # The loose ball is never moved by this presentation request. The previous
 # physical arm is transported with the CURRENT torso, then revalidated.
 # Fixed deterministic budget: four frames, at most 68 elbow candidates and
 # twelve actual sleeve queries. No full cone search can run in this branch.
 var model=arm.articulated_hand
 var body_delta:Transform3D=actor.body_pivot.global_transform*last_body.affine_inverse()
 var start_center:Vector3=body_delta*last_center
 var start_basis:Basis=(body_delta.basis*last_basis).orthonormalized()
 var distance:float=1.2*actor.get_physics_process_delta_time()
 var next_center:Vector3=start_center.move_toward(target,distance)
 var allowed:float=deg_to_rad(700.0)*actor.get_physics_process_delta_time()
 var turn:float=start_basis.get_rotation_quaternion().angle_to(request.basis.orthonormalized().get_rotation_quaternion())
 var goal:Basis=start_basis.slerp(request.basis.orthonormalized(),minf(1.0,allowed/maxf(turn,.000001)))
 catch_surface_work_remaining=12
 var retained:Dictionary={};var chosen:Dictionary={};var center:Vector3=start_center
 var frames:Array=[ [start_center,start_basis], [next_center,goal], [next_center,start_basis], [start_center.lerp(next_center,.5),start_basis] ]
 var attempted:int=0
 for index in frames.size():
  if index>1 and not chosen.is_empty():break
  var trial_center:Vector3=frames[index][0];var trial_basis:Basis=frames[index][1]
  var mount:=Transform3D(trial_basis,trial_center-trial_basis*model.cup_ball_center)
  var fit:Dictionary=_cup_candidate(arm,mount,trial_center,-(trial_basis*model.palm_contact_basis.z).normalized(),0.0,INF,true)
  attempted+=1
  if fit.is_empty():continue
  if index==0:retained=fit
  else:chosen=fit;center=trial_center
 if chosen.is_empty():chosen=retained;center=start_center
 var used:int=12-catch_surface_work_remaining
 catch_surface_work_remaining=-1
 transaction._restore(saved)
 if chosen.is_empty():
  actor.set_meta("between_cup_fit",{"feasible":false,"bounded_catch":true,"reason":"current_body_has_no_certified_continuation","candidates":attempted,"surface_queries":used})
  return
 var mount:=Transform3D(chosen.basis,center-chosen.basis*model.cup_ball_center)
 arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
 arm.solve_ik(mount.origin,chosen.elbow,null,chosen.wrist)
 model.set_mesh_world_transform(mount);model.update_wrist_bridge(arm.fore_mesh.global_basis)
 actor.set_meta("between_cup_fit",{"feasible":true,"bounded_catch":true,"progress":center.distance_to(start_center),"target_error":center.distance_to(target),"candidates":attempted,"surface_queries":used,"angle":last_basis.get_rotation_quaternion().angle_to(chosen.basis.get_rotation_quaternion())})

func _cup_candidate(arm,original:Transform3D,center:Vector3,normal:Vector3,angle:float,cost_ceiling:float=INF,first_valid:bool=false)->Dictionary:
 var model=arm.articulated_hand
 var basis:Basis=Basis(normal,angle)*original.basis
 var allowed:float=deg_to_rad(700.0)*actor.get_physics_process_delta_time()
 var hand_turn:float=last_basis.get_rotation_quaternion().angle_to(basis.get_rotation_quaternion())
 if hand_turn>allowed:return {}
 var mount:=Transform3D(basis,center-basis*model.cup_ball_center)
 var wrist:Vector3=mount*model.wrist_socket
 var shoulder:Vector3=arm.upper_pivot.global_position
 var span:Vector3=wrist-shoulder;var length:float=span.length()
 if length>=arm.upper_arm_length+arm.forearm_length-.0001 or length<.0001:return {}
 var axis:Vector3=span/length
 var along:float=(arm.upper_arm_length*arm.upper_arm_length-arm.forearm_length*arm.forearm_length+length*length)/(2.0*length)
 var circle:Vector3=shoulder+axis*along
 var radius:float=sqrt(maxf(0.0,arm.upper_arm_length*arm.upper_arm_length-along*along))
 var preferred:Vector3=actor.body_pivot.global_transform*(last_body.affine_inverse()*last_elbow)
 var radial:Vector3=preferred-circle;radial-=axis*radial.dot(axis)
 if radial.length_squared()<.000001:return {}
 radial=radial.normalized()
 var best:Dictionary={}
 for index in 17:
  var step:float=ceili(float(index)*.5)*(1.0 if index%2 else -1.0)
  var elbow:Vector3=circle+radial.rotated(axis,deg_to_rad(step*2.5))*radius
  var channels:Dictionary=Anatomy.decompose(Anatomy.forearm_reference(shoulder,elbow,wrist,Vector3.UP,true),basis*model.anatomical_basis,-1.0)
  if not channels.within_animation_budget or float(channels.coupled_budget_ratio)>.98:continue
  var channel_cost:float=float(channels.coupled_budget_ratio)+pow(float(channels.forearm_axial_deg)/90.0,2)
  if channel_cost+.04*hand_turn/maxf(allowed,.000001)>=cost_ceiling:continue
  if not best.is_empty() and channel_cost>=float(best.cost):continue
  # Necessary pure kinematic filter only. The displayed solve below remains
  # authoritative; a conservative numerical reserve avoids boundary rejection.
  var direction:Vector3=span/length
  var pole:Vector3=(elbow-shoulder).normalized()
  if (pole-direction*direction.dot(pole)).length_squared()<1e-10:pole=Vector3.UP if absf(direction.dot(Vector3.UP))<.99 else Vector3.RIGHT
  var shoulder_angle:float=acos(clampf((arm.upper_arm_length*arm.upper_arm_length+length*length-arm.forearm_length*arm.forearm_length)/(2.0*arm.upper_arm_length*length),-1.0,1.0))
  var elbow_angle:float=PI-acos(clampf((arm.upper_arm_length*arm.upper_arm_length+arm.forearm_length*arm.forearm_length-length*length)/(2.0*arm.upper_arm_length*arm.forearm_length),-1.0,1.0))
  var preview_upper:Basis=Basis.looking_at(direction,pole)*Basis(Vector3.RIGHT,shoulder_angle)
  var preview_fore:Basis=preview_upper*Basis(Vector3.RIGHT,-elbow_angle)
  if last_upper.get_rotation_quaternion().angle_to(preview_upper.orthonormalized().get_rotation_quaternion())>allowed+.00005:continue
  if last_fore.get_rotation_quaternion().angle_to(preview_fore.orthonormalized().get_rotation_quaternion())>allowed+.00005:continue
  arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
  arm.solve_ik(mount.origin,elbow,null,wrist)
  var upper_turn:float=last_upper.get_rotation_quaternion().angle_to(arm.upper_pivot.global_basis.orthonormalized().get_rotation_quaternion())
  var fore_turn:float=last_fore.get_rotation_quaternion().angle_to(arm.forearm_pivot.global_basis.orthonormalized().get_rotation_quaternion())
  if upper_turn>allowed or fore_turn>allowed:continue
  var cost:float=channel_cost+.04*(upper_turn+fore_turn+hand_turn)/maxf(allowed,.000001)
  if cost>=cost_ceiling:continue
  if not best.is_empty() and cost>=best.cost:continue
  if catch_surface_work_remaining==0:continue
  if catch_surface_work_remaining>0:catch_surface_work_remaining-=1
  if not SleeveQuery.arm_clear(arm,cup_geometry,Sleeve.REQUIRED_GAP):continue
  best={"basis":basis,"wrist":wrist,"elbow":elbow,"cost":cost}
  if first_valid:return best
 return best

func _cup_cone(arm,center:Vector3,goal:Basis)->Dictionary:
 var allowed:float=deg_to_rad(700.0)*actor.get_physics_process_delta_time()
 var best:Dictionary={}
 for turn in range(1,ceili(rad_to_deg(allowed)/2.5)+1):
  var angle:float=minf(deg_to_rad(float(turn)*2.5),allowed)
  for x in [-1.0,0.0,1.0]:
   for y in [-1.0,0.0,1.0]:
    for z in [-1.0,0.0,1.0]:
     var direction:Vector3=actor._get_forehand_axis()*x+Vector3.UP*y-actor._get_forward_axis()*z
     if direction.length_squared()<.5:continue
     var basis:Basis=Basis(direction.normalized(),angle)*last_basis
     var mount:=Transform3D(basis,center-basis*arm.articulated_hand.cup_ball_center)
     var normal:Vector3=-(basis*arm.articulated_hand.palm_contact_basis.z).normalized()
     var goal_cost:float=.1*basis.get_rotation_quaternion().angle_to(goal.get_rotation_quaternion())/PI
     # This known non-negative term belongs to every candidate in this branch.
     # Retain a numerical reserve so equal/near-equal ordering stays unchanged.
     var ceiling:float=INF if best.is_empty() else best.cost-goal_cost+.000000001
     var candidate:Dictionary=_cup_candidate(arm,mount,center,normal,0.0,ceiling)
     if candidate.is_empty():continue
     candidate.cost+=goal_cost
     if best.is_empty() or candidate.cost<best.cost:best=candidate
 return best

func _apply_receiver_exit(owner,pose)->void:
 var arm=actor.left_arm_node;var model=arm.articulated_hand
 var ready=PostureLibrary.instance().get_def(actor.PaddlePosture.READY)
 var paddle:Transform3D=load("res://scripts/stroke_swing_path.gd").world_transform(actor,ready)
 var basis:Basis=actor.arm_ik._hands._grip_basis(arm,paddle.basis,ready.support_grip_rotation_deg-ready.paddle_in_hand_rotation_deg)
 var origin:Vector3=paddle*(load("res://scripts/paddle_dimensions.gd").SUPPORT_GRIP_OFFSET+Vector3.UP*ready.support_grip_slide_m)
 origin+=actor._get_forehand_axis()*ready.left_hand_offset.x+Vector3.UP*ready.left_hand_offset.y+actor._get_forward_axis()*ready.left_hand_offset.z
 var goal_wrist:Vector3=Transform3D(basis,origin)*model.wrist_socket
 var weight:=clock_weight(owner.phase_elapsed/.56)
 var wrist:Vector3=exit_wrist.lerp(goal_wrist,weight)
 basis=exit_basis.slerp(basis,weight)
 var mount:=Transform3D(basis,wrist-basis*model.wrist_socket)
 var fit:Dictionary=Budget.solve(arm.upper_pivot.global_position,wrist,exit_elbow.lerp(arm.forearm_pivot.global_position,weight),basis*model.anatomical_basis,arm.upper_arm_length,arm.forearm_length,true)
 if not fit.feasible:
  actor.set_meta("between_exit_report",{"feasible":false,"weight":weight})
  return
 var geometry:Dictionary=Sleeve.body_geometry(actor)
 var clear:Dictionary=Sleeve._solve_arm(arm,mount,fit.elbow,geometry,true)
 var elbow:Vector3=clear.elbow if not clear.is_empty() else fit.elbow
 arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
 arm.solve_ik(mount.origin,elbow,null,wrist)
 model.set_mesh_world_transform(mount);model.update_wrist_bridge(arm.fore_mesh.global_basis)
 model.set_pose("GRIP",1.0,ready.support_index_closure,ready.support_grip_style)
 var goal_fingers:Array=[]
 for bone in model.skeleton.get_bone_count():goal_fingers.append(model.skeleton.get_bone_pose_rotation(bone))
 for bone in range(1,model.WRIST_BRIDGE_BONE):model.skeleton.set_bone_pose_rotation(bone,exit_fingers[bone].slerp(goal_fingers[bone],weight))
 actor.set_meta("between_exit_report",{"feasible":true,"clear":not clear.is_empty(),"weight":weight})
 if not Sleeve.clearance_report(actor).valid:
  var transaction=Sleeve.Transaction.new(actor)
  var candidate:Dictionary=Sleeve.search(actor,transaction,pose)
  if not candidate.is_empty():Sleeve.apply(actor,candidate)
 if weight>=1.0:Sleeve.apply_presented_ready(actor,pose)
 last_basis=basis

func cup_kinematic_fit(arm,center:Vector3,offset:Vector3)->bool:
 # Necessary body-fit admission for the same finite hand-frame/elbow lattice
 # used by _cup_cone. Presentation still checks actual sleeve surfaces before
 # accepting any candidate. No actor node, ball or foot is changed here.
 var allowed:float=deg_to_rad(700.0)*actor.get_physics_process_delta_time()
 var shoulder:Vector3=arm.upper_pivot.global_position+offset
 var body:Transform3D=actor.body_pivot.global_transform
 body.origin+=offset
 var preferred:Vector3=body*(last_body.affine_inverse()*last_elbow)
 for turn in range(0,ceili(rad_to_deg(allowed)/2.5)+1):
  var angle:float=minf(deg_to_rad(float(turn)*2.5),allowed)
  for x in [-1.0,0.0,1.0]:
   for y in [-1.0,0.0,1.0]:
    for z in [-1.0,0.0,1.0]:
     var direction:Vector3=actor._get_forehand_axis()*x+Vector3.UP*y-actor._get_forward_axis()*z
     if direction.length_squared()<.5:continue
     var basis:Basis=Basis(direction.normalized(),angle)*last_basis
     var wrist:Vector3=center+basis*(arm.articulated_hand.wrist_socket-arm.articulated_hand.cup_ball_center)
     var span:Vector3=wrist-shoulder;var length:float=span.length()
     if length>=arm.upper_arm_length+arm.forearm_length-.0001 or length<.0001:continue
     var axis:Vector3=span/length
     var along:float=(arm.upper_arm_length*arm.upper_arm_length-arm.forearm_length*arm.forearm_length+length*length)/(2.0*length)
     var circle:Vector3=shoulder+axis*along
     var radius:float=sqrt(maxf(0.0,arm.upper_arm_length*arm.upper_arm_length-along*along))
     var radial:Vector3=preferred-circle;radial-=axis*radial.dot(axis)
     if radial.length_squared()<.000001:continue
     radial=radial.normalized()
     for index in 17:
      var step:float=ceili(float(index)*.5)*(1.0 if index%2 else -1.0)
      var elbow:Vector3=circle+radial.rotated(axis,deg_to_rad(step*2.5))*radius
      var channels:Dictionary=Anatomy.decompose(Anatomy.forearm_reference(shoulder,elbow,wrist,Vector3.UP,true),basis*arm.articulated_hand.anatomical_basis,-1.0)
      if not channels.within_animation_budget or float(channels.coupled_budget_ratio)>.98:continue
      var upper:Basis=Basis.looking_at(axis,(elbow-shoulder).normalized())*Basis(Vector3.RIGHT,acos(clampf(along/arm.upper_arm_length,-1.0,1.0)))
      var elbow_angle:float=PI-acos(clampf((arm.upper_arm_length*arm.upper_arm_length+arm.forearm_length*arm.forearm_length-length*length)/(2.0*arm.upper_arm_length*arm.forearm_length),-1.0,1.0))
      var fore:Basis=upper*Basis(Vector3.RIGHT,-elbow_angle)
      if last_upper.get_rotation_quaternion().angle_to(upper.get_rotation_quaternion())>allowed:continue
      if last_fore.get_rotation_quaternion().angle_to(fore.get_rotation_quaternion())>allowed:continue
      return true
 return false
