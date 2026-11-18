extends RefCounted
## Runtime coordinate rebase only. This must pass a complete world-geometry gate
## at a supported half turn before the logical ledger side may commit.
static func _half_turn_mesh(mesh: Mesh) -> ArrayMesh:
 var result:=ArrayMesh.new()
 var turn:=Basis(Vector3.UP,PI)
 for surface in mesh.get_surface_count():
  var arrays:Array=mesh.surface_get_arrays(surface).duplicate(true)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for index in vertices.size():vertices[index]=turn*vertices[index]
  arrays[Mesh.ARRAY_VERTEX]=vertices
  if arrays[Mesh.ARRAY_NORMAL] != null:
   var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
   for index in normals.size():normals[index]=turn*normals[index]
   arrays[Mesh.ARRAY_NORMAL]=normals
  if arrays[Mesh.ARRAY_TANGENT] != null:
   var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
   for index in range(0,tangents.size(),4):
    var tangent:Vector3=turn*Vector3(tangents[index],tangents[index+1],tangents[index+2])
    tangents[index]=tangent.x;tangents[index+1]=tangent.y;tangents[index+2]=tangent.z
   arrays[Mesh.ARRAY_TANGENT]=tangents
  result.add_surface_from_arrays(mesh.surface_get_primitive_type(surface),arrays)
  result.surface_set_material(surface,mesh.surface_get_material(surface))
 return result

static func rebase_runtime_visuals(actor) -> Array:
 return set_visual_court_side(actor, 1-actor.court_side)

static func set_visual_court_side(actor, target_side:int) -> Array:
 var changed:Array=[]
 if actor.body_pivot==null or not actor.body_pivot.has_meta("articulated_torso"):return changed
 var skin=actor.body_pivot.get_meta("articulated_torso")
 var head:MeshInstance3D=actor.body_pivot.get_node("TorsoMesh/HeadMesh")
 for mesh_node in [skin.body_mesh,head,actor.body_pivot.get_node("HipsMesh"),actor.body_pivot.get_node("TorsoMesh")]:
  if not mesh_node.has_meta("court_rest_frame"):
   mesh_node.set_meta("court_rest_frame",{"side":actor.court_side,"original":mesh_node.mesh,"opposite":_half_turn_mesh(mesh_node.mesh)})
  var rest:Dictionary=mesh_node.get_meta("court_rest_frame")
  var selected:Mesh=rest.original if target_side==rest.side else rest.opposite
  if mesh_node.mesh==selected:continue
  changed.append({"node":mesh_node,"mesh":mesh_node.mesh})
  mesh_node.mesh=selected
 var turn:=Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
 for child in head.get_children():
  if child is Node3D:
   if not child.has_meta("court_rest_frame"):child.set_meta("court_rest_frame",{"side":actor.court_side,"original":child.transform})
   var rest:Dictionary=child.get_meta("court_rest_frame")
   var selected:Transform3D=rest.original if target_side==rest.side else turn*rest.original
   changed.append({"node":child,"transform":child.transform})
   child.transform=selected
 return changed

static func restore_runtime_visuals(changed:Array)->void:
 for record in changed:
  if record.has("mesh"):record.node.mesh=record.mesh
  else:record.node.transform=record.transform

static func _capture_subtree(root) -> Dictionary:
 var nodes:Array=[];var bones:Array=[];var meshes:Array=[]
 var stack:Array=[root]
 while not stack.is_empty():
  var node=stack.pop_back();stack.append_array(node.get_children())
  if node is Node3D:nodes.append({"node":node,"world":node.global_transform,"local":node.transform})
  if node is MeshInstance3D:meshes.append({"node":node,"mesh":node.mesh})
  if node is Skeleton3D:
   var channels:Array=[]
   for index in node.get_bone_count():channels.append([node.get_bone_pose_position(index),node.get_bone_pose_rotation(index),node.get_bone_pose_scale(index)])
   bones.append({"node":node,"channels":channels})
 return {"nodes":nodes,"bones":bones,"meshes":meshes}

static func _restore_subtree(saved:Dictionary, restore_meshes:bool=false)->void:
 for record in saved.nodes:
  if restore_meshes:record.node.transform=record.local
  else:record.node.global_transform=record.world
 for record in saved.bones:
  for index in record.channels.size():
   record.node.set_bone_pose_position(index,record.channels[index][0]);record.node.set_bone_pose_rotation(index,record.channels[index][1]);record.node.set_bone_pose_scale(index,record.channels[index][2])
 if restore_meshes:
  for record in saved.meshes:record.node.mesh=record.mesh

static func _copy_value(value:Variant)->Variant:
 return value.duplicate(true) if value is Array or value is Dictionary else value

static func _capture_fields(object)->Dictionary:
 var fields:Dictionary={}
 for property in object.get_property_list():
  if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:fields[property.name]=_copy_value(object.get(property.name))
 return fields

static func _restore_fields(object,fields:Dictionary)->void:
 for key in fields:object.set(key,_copy_value(fields[key]))

static func _capture_owner_fields(actor)->Dictionary:
 var items:Array=[]
 for object in [actor.leg_ik,actor.arm_ik._hands]:items.append({"object":object,"fields":_capture_fields(object)})
 var posture:Dictionary={}
 for key in ["paddle_posture","_posture_lerp_pos","_posture_lerp_rot","_posture_lerp_basis","_posture_lerp_initialized","transition_pose_blend","_presented_body_pose"]:posture[key]=actor.posture.get(key)
 items.append({"object":actor.posture,"fields":posture})
 var player:Dictionary={}
 for key in ["_support_sim_time","_support_consumed_time","_support_last_refresh_tick","_between_last_pose","paddle_rest_position","paddle_rest_rotation"]:player[key]=actor.get(key)
 var metadata:Dictionary={}
 for key in actor.body_pivot.get_meta_list():metadata[key]=_copy_value(actor.body_pivot.get_meta(key))
 return {"items":items,"player":player,"body_metadata":metadata}

static func _restore_owner_fields(actor,saved:Dictionary)->void:
 for item in saved.items:_restore_fields(item.object,item.fields)
 for key in saved.player:actor.set(key,saved.player[key])
 for key in actor.body_pivot.get_meta_list():
  if not saved.body_metadata.has(key):actor.body_pivot.remove_meta(key)
 for key in saved.body_metadata:actor.body_pivot.set_meta(key,_copy_value(saved.body_metadata[key]))

static func _world_geometry(actor)->Dictionary:
 var surface:Script=load("res://scripts/player_surface_contacts.gd")
 var result:Dictionary={}
 for node in actor.body_pivot.find_children("*","MeshInstance3D",true,false):
  if node.mesh!=null:result[str(actor.get_path_to(node))]=surface.world_triangles(node)
 return result

static func _geometry_delta(first:Dictionary,second:Dictionary)->Dictionary:
 var maximum:float=0.0;var differences:Array=[];var vertices:int=0
 if first.keys()!=second.keys():return {"valid":false,"reason":"mesh roster changed"}
 for key in first:
  var previous:PackedVector3Array=first[key];var current:PackedVector3Array=second[key]
  if previous.size()!=current.size():return {"valid":false,"reason":"mesh topology changed","mesh":key}
  var worst:float=0.0
  for index in current.size():worst=maxf(worst,previous[index].distance_to(current[index]))
  vertices+=current.size();maximum=maxf(maximum,worst)
  if worst>.00001:differences.append({"mesh":key,"maximum_m":worst})
 return {"valid":differences.is_empty(),"maximum_m":maximum,"differences":differences,"triangle_vertices":vertices,"scope":"all actual body-pivot meshes, including hidden rig reference meshes; editor ghosts outside the rig excluded"}

static func _geometry_frames(actor)->Dictionary:
 # Every deformed vertex is an affine blend of these actual skin frames.
 # Checking the original local AABB corners bounds every possible vertex,
 # without rebuilding or sampling the triangle soup during gameplay.
 var surface:Script=load("res://scripts/player_surface_contacts.gd")
 var result:Dictionary={}
 for node in actor.body_pivot.find_children("*","MeshInstance3D",true,false):
  if node.mesh==null:continue
  var palette:Array=surface._skin_palette(node)
  if palette.is_empty():palette.append(node.global_transform)
  result[str(actor.get_path_to(node))]={"node":node,"mesh":node.mesh,"frames":palette,"bounds":node.mesh.get_aabb(),"skin":node.skin}
 return result

static func _frame_delta(first:Dictionary,second:Dictionary)->Dictionary:
 var maximum:float=0.0;var count:int=0;var differences:Array=[]
 if first.keys()!=second.keys():return {"valid":false,"reason":"mesh roster changed"}
 for key in first:
  var before:Dictionary=first[key];var after:Dictionary=second[key]
  if before.skin!=after.skin or before.frames.size()!=after.frames.size():return {"valid":false,"reason":"skin bindings changed","mesh":key}
  var local_map:=Transform3D.IDENTITY
  if before.mesh!=after.mesh:
   var rest:Dictionary=after.node.get_meta("court_rest_frame",{})
   if rest.is_empty() or before.mesh not in [rest.original,rest.opposite] or after.mesh not in [rest.original,rest.opposite]:return {"valid":false,"reason":"uncertified mesh replacement","mesh":key}
   local_map=Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
   if before.mesh==rest.opposite:local_map=local_map.affine_inverse()
  var worst:float=0.0
  for index in before.frames.size():
   for corner in 8:
    var point:Vector3=before.bounds.get_endpoint(corner)
    worst=maxf(worst,(before.frames[index]*point).distance_to(after.frames[index]*local_map*point))
    count+=1
  maximum=maxf(maximum,worst)
  if worst>.00001:differences.append({"mesh":key,"maximum_m":worst})
 return {"valid":differences.is_empty(),"maximum_m":maximum,"differences":differences,"affine_corner_checks":count,"scope":"all actual static and skin frames over local mesh bounds; certified runtime half-turn mesh map"}

static func commit_supported_roster(game,owner)->Dictionary:
 var started:int=Time.get_ticks_usec()
 var result:Dictionary={"committed":false,"actors":[],"reason":""}
 if not game.doubles_mode or not game.doubles_state.end_change_pending:return result
 if owner.phase!="END_TURN" or not owner._all_support_ready():
  result.reason="end-change turn is not fully supported"
  return result
 for heading in owner._carry_heading:
  if absf(wrapf(float(heading)-180.0,-180.0,180.0))>.0001:
   result.reason="end-change facing is not ready"
   return result
 var server_id:int=game.get_server_actor().get_actor_id()
 var verify_triangles:bool=game.get_tree().has_meta("verify_end_rebase_triangles")
 var external_proof_usec:int=0
 var snapshots:Array=[]
 for index in owner._players.size():
  var actor=owner._players[index]
  var frame=load("res://scripts/live_ready_clearance.gd").Transaction.new(actor)
  var proof_started:int=Time.get_ticks_usec()
  var geometry:Dictionary=_world_geometry(actor) if verify_triangles else {}
  external_proof_usec+=Time.get_ticks_usec()-proof_started
  snapshots.append({"actor":actor,"owners":_capture_owner_fields(actor),"carry_tick":owner._carry_heading_tick[index],"side":actor.court_side,"head":actor.body_pivot.get_node("TorsoMesh/HeadMesh").global_transform,"all":_capture_subtree(actor.body_pivot),"left":_capture_subtree(actor.left_arm_node),"right":_capture_subtree(actor.right_arm_node),"geometry":geometry,"frames":_geometry_frames(actor),"transaction":frame,"saved":frame._snapshot(true),"heading":actor.leg_ik._heading_angle,"ready":actor.leg_ik._ready_facing_deg,"hip":actor.leg_ik.locomotion_hip_yaw_deg,"carry":owner._carry_heading[index],"pose":owner._poses[index],"wrist":owner._wrists[index]})
 var capture_done:int=Time.get_ticks_usec()
 var proof_usec:int=0
 var old_phase:String=owner.phase
 owner.phase="END_REBASE"
 var accepted:bool=true
 for index in owner._players.size():
  var actor=owner._players[index];var saved:Dictionary=snapshots[index]
  rebase_runtime_visuals(actor)
  actor.configure_identity(actor.actor_id,actor.team_id,1-actor.court_side)
  actor.leg_ik._heading_angle=wrapf(actor.leg_ik._heading_angle+PI,-PI,PI)
  actor.leg_ik._ready_facing_deg=0.0
  actor.leg_ik.locomotion_hip_yaw_deg=wrapf(actor.leg_ik.locomotion_hip_yaw_deg-180.0,-180.0,180.0)
  owner._carry_heading[index]=wrapf(float(owner._carry_heading[index])-180.0,-180.0,180.0)
  owner._carry_heading_tick[index]=Engine.get_physics_frames()
  var pose=owner._make_pose(index,0.0)
  owner._poses[index]=pose;owner._wrists[index]=owner._carry_wrist(index)
  actor.posture.transition_pose_blend=pose;actor.posture.force_posture_update(pose)
  _restore_subtree(saved.left);_restore_subtree(saved.right)
  for record in saved.saved.arms:
   record.arm.anatomical_wrist_world=record.wrist;record.arm.visual_stretch=record.stretch;record.arm.visual_wrist_lag_deg=record.lag
   for key in record.fields:record.arm.articulated_hand.set(key,record.fields[key])
   if record.support_frame_present:record.arm.set_meta("live_support_frame",record.support_frame.duplicate(true))
   elif record.arm.has_meta("live_support_frame"):record.arm.remove_meta("live_support_frame")
  for record in saved.saved.bridges:
   for key in record.fields:record.bridge.set(key,record.fields[key].duplicate() if record.fields[key] is Array else record.fields[key])
  actor.body_pivot.get_node("TorsoMesh/HeadMesh").global_transform=saved.head*Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
  var proof_started:int=Time.get_ticks_usec()
  var proof:Dictionary=_frame_delta(saved.frames,_geometry_frames(actor))
  proof_usec+=Time.get_ticks_usec()-proof_started
  if verify_triangles:
   var external_started:int=Time.get_ticks_usec()
   proof["triangle_verification"]=_geometry_delta(saved.geometry,_world_geometry(actor))
   external_proof_usec+=Time.get_ticks_usec()-external_started
   if not proof.triangle_verification.valid:proof.valid=false
  proof["actor_id"]=actor.get_actor_id();result.actors.append(proof)
  if not proof.valid:accepted=false
 if accepted and game.get_server_actor().get_actor_id()==server_id:
  accepted=game.doubles_state.confirm_end_change()
 if not accepted:
  for index in snapshots.size():
   var saved:Dictionary=snapshots[index];var actor=saved.actor
   actor.configure_identity(actor.actor_id,actor.team_id,saved.side)
   saved.transaction._restore(saved.saved);_restore_subtree(saved.all,true);_restore_owner_fields(actor,saved.owners)
   actor.leg_ik._heading_angle=saved.heading;actor.leg_ik._ready_facing_deg=saved.ready;actor.leg_ik.locomotion_hip_yaw_deg=saved.hip
   owner._carry_heading[index]=saved.carry;owner._carry_heading_tick[index]=saved.carry_tick;owner._poses[index]=saved.pose;owner._wrists[index]=saved.wrist
  owner.phase=old_phase
  result.reason="rest-frame world geometry admission rejected"
  return result
 for index in owner._players.size():
  var actor=owner._players[index];var arm=actor.left_arm_node;var path=owner._arm_paths[index]
  path.last_basis=arm.hand_mesh.global_basis.orthonormalized();path.last_elbow=arm.forearm_pivot.global_position
  path.last_upper=arm.upper_pivot.global_basis.orthonormalized();path.last_fore=arm.forearm_pivot.global_basis.orthonormalized();path.last_body=actor.body_pivot.global_transform
  path.last_center=arm.hand_mesh.global_transform*arm.articulated_hand.cup_ball_center
  actor._between_last_pose=actor.posture.capture_displayed_pose()
 result.committed=true;result.server_actor_id=server_id;result.microseconds=Time.get_ticks_usec()-started
 result.timing={"capture_usec":capture_done-started,"affine_proof_usec":proof_usec,"external_triangle_proof_usec":external_proof_usec,"runtime_total_usec":Time.get_ticks_usec()-started-external_proof_usec,"apply_and_bookkeeping_usec":Time.get_ticks_usec()-capture_done-proof_usec}
 return result
