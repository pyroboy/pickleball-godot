extends RefCounted
## Presentation-only admission for an unpossessed stationary catch request.
## The real ball/phase clock is never captured, rewound, moved or awarded here.
const Clear=preload("res://scripts/live_ready_clearance.gd")
const Budget=preload("res://scripts/live_arm_budget.gd")
const Surface=preload("res://scripts/player_surface_contacts.gd")
const Paddle=preload("res://scripts/paddle_dimensions.gd")
const FOOT_TOLERANCE:=.00002
const HAND_GAP:=.0002
const POSE_FIELDS=["paddle_posture","transition_pose_blend","_presented_body_pose","_posture_lerp_pos","_posture_lerp_rot","_posture_lerp_basis","_posture_lerp_initialized"]
const PATH_FIELDS=["had_cup_request","last_basis","last_elbow","last_upper","last_fore","last_center","last_body"]
var actor
var surfaces
var last_report:Dictionary={}
func _init(player):
 actor=player
 surfaces=preload("res://scripts/between_surface_certificate.gd").new(actor)
func _support_key()->Array:
 var ik=actor.leg_ik
 return [actor.get_instance_id(),actor.body_pivot.get_instance_id(),actor.right_arm_node.get_instance_id(),actor.left_arm_node.get_instance_id(),actor.right_arm_node.upper_arm_length,actor.right_arm_node.forearm_length,actor.left_arm_node.upper_arm_length,actor.left_arm_node.forearm_length,actor.global_transform,ik.right_foot_locked,ik.left_foot_locked,ik.right_foot_lock_pos,ik.left_foot_lock_pos,ik.right_contact_serial,ik.left_contact_serial,ik._active_side,ik._run_active,ik._airborne]
func _eligible(owner)->bool:
 if owner.phase!="PASS" or owner.index_for_actor(actor)!=owner.catcher or owner._carry_team>=0:return false
 if owner.hand_presentation_for(actor.get_actor_id()).get("mode","")!="CATCH_OPEN":return false
 var ik=actor.leg_ik
 return actor.current_velocity.length_squared()<.000001 and ik.feet_initialized and ik.right_foot_locked and ik.left_foot_locked and ik._active_side<0 and not ik._run_active and not ik._airborne
static func _geometry(points:PackedVector3Array)->Dictionary:
 var boxes:Array[AABB]=[];var indices:Array[int]=[]
 for index in range(0,points.size()-2,3):boxes.append(AABB(points[index],Vector3.ZERO).expand(points[index+1]).expand(points[index+2]));indices.append(index/3)
 return {"points":points,"bounds":boxes,"tree":Clear._tree(indices,boxes)}
static func _surfaces_clear(points:PackedVector3Array,other:Dictionary)->bool:
 if points.is_empty() or other.points.is_empty():return false
 for index in range(0,points.size()-2,3):
  var a:Vector3=points[index];var b:Vector3=points[index+1];var c:Vector3=points[index+2]
  if not Clear._clear_triangle(a,b,c,AABB(a,Vector3.ZERO).expand(b).expand(c).grow(HAND_GAP),other,other.tree,HAND_GAP):return false
 return true
func displayed_report()->Dictionary:
 var arms:Dictionary=Budget.displayed_report(actor)
 var sleeve:Dictionary=Clear.clearance_report(actor)
 var feet:Array=[];var supported:bool=true;var planted_count:int=0
 for pair in [[actor.right_leg_node,actor.leg_ik.right_foot_lock_pos,actor.leg_ik.right_foot_locked,0],[actor.left_leg_node,actor.leg_ik.left_foot_lock_pos,actor.leg_ik.left_foot_locked,1]]:
  var leg=pair[0];var ankle:Vector3=leg.foot_pivot.global_position
  var a:float=absf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)-leg.thigh_length)
  var b:float=absf(leg.shin_pivot.global_position.distance_to(ankle)-leg.shin_length)
  var sole:float=INF;var bounds:AABB=leg.foot_mesh.mesh.get_aabb()
  for corner in 8:sole=minf(sole,(leg.foot_mesh.global_transform*bounds.get_endpoint(corner)).y)
  var planted:bool=pair[2]
  if planted:planted_count+=1
  var contact_valid:bool=ankle.distance_to(pair[1])<=FOOT_TOLERANCE if planted else actor.leg_ik._active_side==int(pair[3])
  var okay:bool=a<=FOOT_TOLERANCE and b<=FOOT_TOLERANCE and contact_valid and sole>=Ball.FLOOR_Y-FOOT_TOLERANCE and Clear.Foot.reach_report(leg.thigh_pivot.global_position,ankle,leg.thigh_length,leg.shin_length).feasible
  supported=supported and okay;feet.append({"valid":okay,"planted":planted,"upper_error":a,"lower_error":b,"anchor_error":ankle.distance_to(pair[1]),"sole":sole})
 supported=supported and planted_count>0
 var surface_report:Dictionary=surfaces.report()
 var hand_pair:bool=surface_report.hand_pair_clear
 var paddle_clear:bool=surface_report.hand_paddle_clear
 var hands_clear:bool=surface_report.hand_torso_clear
 var pose=actor.posture._presented_body_pose
 var mounted:bool=false
 if pose!=null:
  var target:Vector3=actor.paddle_node.to_global(Paddle.MAIN_GRIP_OFFSET+pose.right_hand_offset)
  var basis:Basis=actor.arm_ik._hands._grip_basis(actor.right_arm_node,actor.paddle_node.global_basis,pose.main_grip_rotation_deg-pose.paddle_in_hand_rotation_deg)
  var actual:Transform3D=actor.right_arm_node.hand_mesh.global_transform
  mounted=actual.origin.distance_to(target)<=FOOT_TOLERANCE and maxf((actual.basis.x-basis.x).length(),maxf((actual.basis.y-basis.y).length(),(actual.basis.z-basis.z).length()))<=FOOT_TOLERANCE
 return {"valid":arms.valid and sleeve.valid and supported and hand_pair and paddle_clear and hands_clear and mounted,"arms":arms,"sleeves":sleeve,"feet":feet,"hand_pair_clear":hand_pair,"hand_paddle_clear":paddle_clear,"hand_torso_clear":hands_clear,"main_seated":mounted}
func begin(owner)->Dictionary:
 if actor.has_meta("between_bounded_admission"):actor.remove_meta("between_bounded_admission")
 if not _eligible(owner):
  last_report={"admitted":false,"reason":"outside stationary planted unpossessed catch scope"};actor.set_meta("between_admission",last_report)
  return {}
 var before:Dictionary=displayed_report()
 if not before.valid:
  last_report={"admitted":false,"reason":"current supported presentation has no whole-rig certificate","before":before}
  actor.set_meta("between_admission",last_report)
  return {}
 var transaction=Clear.Transaction.new(actor)
 var saved:Dictionary=transaction._snapshot()
 var posture:Dictionary={}
 for key in POSE_FIELDS:posture[key]=actor.posture.get(key)
 var path=owner._arm_paths[owner.index_for_actor(actor)];var path_fields:Dictionary={}
 for key in PATH_FIELDS:path_fields[key]=path.get(key)
 var hand_fields:Dictionary={}
 for key in ["_last_held_mount","_held_mount_valid","_between_mode","_between_entry_local","_between_last_elapsed","_support_grip_weight","_support_grip_rotation_deg","_grasp_key","_grasp_basis","mode"]:hand_fields[key]=actor.arm_ik._hands.get(key)
 var metadata:Dictionary={}
 for key in ["live_transition_arm_reach","pose_body_position_applied","live_ready_clearance","_ready_clearance_exact_cache"]:
  metadata[key]={"present":actor.body_pivot.has_meta(key),"value":actor.body_pivot.get_meta(key) if actor.body_pivot.has_meta(key) else null}
 actor.set_meta("between_bounded_admission",true)
 return {"transaction":transaction,"snapshot":saved,"support":_support_key(),"posture":posture,"hand_fields":hand_fields,"path":path,"path_fields":path_fields,"metadata":metadata,"before":before,"generation":owner._generation,"run":owner._run_id,"actor_id":actor.get_actor_id(),"heading":float(actor.posture._presented_body_pose.get_meta("ready_facing_yaw_deg",actor.posture._presented_body_pose.body_yaw_deg))}
func finish(owner,token:Dictionary)->void:
 if actor.has_meta("between_bounded_admission"):actor.remove_meta("between_bounded_admission")
 if token.is_empty():return
 var unchanged:bool=owner._generation==token.generation and owner._run_id==token.run and actor.get_actor_id()==token.actor_id and owner.phase=="PASS" and owner._carry_team<0 and _support_key()==token.support
 var fit:Dictionary=actor.get_meta("between_cup_fit",{})
 var after:Dictionary=displayed_report()
 if fit.get("feasible",false) and after.valid:
  last_report={"admitted":true,"retained":false,"valid":true,"after":after};actor.set_meta("between_admission",last_report);return
 if not unchanged:
  last_report={"admitted":true,"retained":false,"valid":after.valid,"reason":"ownership/root/support changed; stale fallback forbidden","after":after};actor.set_meta("between_admission",last_report);return
 token.transaction._restore(token.snapshot)
 for key in token.posture:actor.posture.set(key,token.posture[key])
 for key in token.hand_fields:actor.arm_ik._hands.set(key,token.hand_fields[key])
 for key in token.path_fields:token.path.set(key,token.path_fields[key])
 for key in token.metadata:
  if token.metadata[key].present:actor.body_pivot.set_meta(key,token.metadata[key].value)
  else:actor.body_pivot.remove_meta(key)
 # Keep the next requested turn anchored to the actual presentation. The
 # phase deadline and elapsed support/ball clocks continue normally.
 owner._carry_heading[owner.index_for_actor(actor)]=token.heading
 var restored:Dictionary=displayed_report()
 last_report={"admitted":true,"retained":true,"valid":restored.valid,"reason":"catch request declined; supported presentation retained","rejected":after,"after":restored}
 actor.set_meta("between_admission",last_report)
