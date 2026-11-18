extends RefCounted
const Budget=preload("res://scripts/live_arm_budget.gd")
const Sleeve=preload("res://scripts/live_ready_clearance.gd")
const Path=preload("res://scripts/between_point_arm_path.gd")
const META="carried_cup_continuity"
static func remember(player)->void:
 var arm=player.left_arm_node
 player.set_meta(META,{"basis":arm.hand_mesh.global_basis.orthonormalized(),"elbow":arm.forearm_pivot.global_position,"upper":arm.upper_pivot.global_basis.orthonormalized(),"fore":arm.forearm_pivot.global_basis.orthonormalized(),"body":player.body_pivot.global_transform,"tick":Engine.get_physics_frames()})
static func apply(player,hands) -> Dictionary:
 var _pt := Time.get_ticks_usec()
 var _pr = _perf_apply(player, hands)
 PerfMonitor.record("arm.carried_cup", Time.get_ticks_usec() - _pt)
 return _pr

static func _perf_apply(player,hands) -> Dictionary:
 if not player.has_meta(META):return {}
 var game=player.get_parent()
 if game==null or game.game_state!=game.GameState.WAITING or game.get_server_actor()!=player or game.ball.is_in_play or game.game_serve.is_release_pending():return {}
 if player._between_point_owner()!=null or hands.mode!="SERVE_CUP":return {}
 var arm=player.left_arm_node;var model=arm.articulated_hand
 # Perf: the cup search (rig snapshot, body geometry, up to 5 candidate fits) used
 # to rerun on every arm solve, ~5-6x per tick. Search once per tick and reuse it.
 var cached:Dictionary=player.get_meta(META)
 if int(cached.get("tick",-1))==Engine.get_physics_frames() and cached.has("chosen"):
  var c:Dictionary=cached.chosen
  arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
  arm.solve_ik(c.mount.origin,c.elbow,null,c.wrist)
  model.set_mesh_world_transform(c.mount);model.update_wrist_bridge(arm.fore_mesh.global_basis)
  hands._last_held_mount=c.mount;hands._held_mount_valid=true
  return {"active":true,"feasible":true,"step_deg":0.0,"center":game.game_serve.get_held_ball_position(),"reused":true}
 var state:Dictionary=cached.duplicate(true)
 var last:Basis=state.basis
 var center:Vector3=game.game_serve.get_held_ball_position()
 var goal:Basis=arm.hand_mesh.global_basis.orthonormalized()
 var same_tick:bool=int(state.tick)==Engine.get_physics_frames() and state.has("frame_basis")
 var frame_basis:Basis=state.frame_basis if same_tick else last
 var frame_upper:Basis=state.frame_upper if same_tick else state.get("upper",arm.upper_pivot.global_basis.orthonormalized())
 var frame_fore:Basis=state.frame_fore if same_tick else state.get("fore",arm.forearm_pivot.global_basis.orthonormalized())
 last=frame_basis
 var frame_elbow:Vector3=state.frame_elbow if same_tick else state.elbow
 var frame_body:Transform3D=state.frame_body if same_tick else state.get("body",player.body_pivot.global_transform)
 var path=Path.new(player)
 path.last_basis=frame_basis;path.last_upper=frame_upper;path.last_fore=frame_fore
 path.last_elbow=frame_elbow;path.last_body=frame_body
 var step:float=deg_to_rad(600.0)*player.get_physics_process_delta_time()
 var allowed:float=deg_to_rad(700.0)*player.get_physics_process_delta_time()
 var angle:=last.get_rotation_quaternion().angle_to(goal.get_rotation_quaternion())
 var desired:Basis=last.slerp(goal,minf(1.0,step/maxf(angle,.000001)))
 var transaction=Sleeve.Transaction.new(player);var saved:Dictionary=transaction._snapshot(true)
 path.cup_geometry=Sleeve.body_geometry(player)
 var chosen:Dictionary={}
 # Walk from the previous physical orientation toward the requested cup.
 # Each candidate has the same authoritative ball center. A blocked rotation
 # holds its closest valid orientation; it never stretches or moves the ball.
 for fraction in [1.0,.75,.5,.25,0.0]:
  transaction._restore(saved)
  var basis:Basis=last.slerp(desired,fraction)
  var mount:=Transform3D(basis,center-basis*model.cup_ball_center)
  var normal:Vector3=-(basis*model.palm_contact_basis.z).normalized()
  var fit:Dictionary=path._cup_candidate(arm,mount,center,normal,0.0)
  if fit.is_empty():continue
  chosen={"mount":mount,"elbow":fit.elbow,"wrist":fit.wrist};break
 if chosen.is_empty():
  var fit:Dictionary=path._cup_cone(arm,center,goal)
  if not fit.is_empty():chosen={"mount":Transform3D(fit.basis,center-fit.basis*model.cup_ball_center),"elbow":fit.elbow,"wrist":fit.wrist}
 transaction._restore(saved)
 if chosen.is_empty():return {"active":true,"feasible":false,"reason":"no continuous fixed-center cup at current body"}
 arm.upper_pivot.basis=Basis.IDENTITY;arm.forearm_pivot.basis=Basis.IDENTITY
 arm.solve_ik(chosen.mount.origin,chosen.elbow,null,chosen.wrist)
 model.set_mesh_world_transform(chosen.mount);model.update_wrist_bridge(arm.fore_mesh.global_basis)
 hands._last_held_mount=chosen.mount;hands._held_mount_valid=true
 player.set_meta(META,{"basis":chosen.mount.basis,"elbow":chosen.elbow,"upper":arm.upper_pivot.global_basis.orthonormalized(),"fore":arm.forearm_pivot.global_basis.orthonormalized(),"body":player.body_pivot.global_transform,"frame_elbow":frame_elbow,"frame_body":frame_body,"frame_basis":frame_basis,"frame_upper":frame_upper,"frame_fore":frame_fore,"tick":Engine.get_physics_frames(),"chosen":chosen})
 return {"active":true,"feasible":true,"step_deg":rad_to_deg(last.get_rotation_quaternion().angle_to(chosen.mount.basis.get_rotation_quaternion())),"center":center}
