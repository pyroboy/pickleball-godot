extends RefCounted
## Integration adapter. All tactical ball data comes from the caller's already
## delayed ordinary AIBrain offer/predictor, never from a fresh ball prediction.
const Policy=preload("team_shot_coordinator.gd")
const Avoidance=preload("team_avoidance.gd")
const Cancel=preload("ai_pending_contact_cancellation.gd")
const RuntimePolicy=preload("runtime_policy.gd")
var cancellations:Array=[]
var game
var policy=Policy.new()
var last_decision_by_actor:Dictionary={}
var last_steering_by_actor:Dictionary={}
var _roster_key:Array=[]
var _tendencies:Dictionary={}
var _history:Dictionary={}
var _world_history:Array=[]
var _last_frame:=-1
var _last_advanced_frame:=-1
var _clock:=0.0
var _seen_generation:=-1
var _style_preferences_frame:=-1

func setup(owner) -> bool:
 game=owner
 return _configure_roster()

func _configure_roster() -> bool:
 if game==null or not game.has_method("get_players"):return false
 var records:Array=[];var key:Array=[int(game._point_reset_generation)]
 for actor in game.get_players():
  key.append([actor.get_actor_id(),actor.get_team_id(),actor.get_court_side()])
  var home:Vector3=actor.global_position
  if absf(home.x)<.3:home.x=1.35 if actor.get_actor_id() in [0,3] else -1.35
  records.append({"actor_id":actor.get_actor_id(),"team_id":actor.get_team_id(),"court_side":actor.get_court_side(),"human":not actor.is_ai or actor.get_actor_id()==RuntimePolicy.bench_human,
   "home":home,"min_x":actor.min_x,"max_x":actor.max_x,"min_z":actor.min_z,"max_z":actor.max_z})
 if key==_roster_key:return true
 if not policy.configure(records):return false
 _roster_key=key;_history.clear();_world_history.clear();last_decision_by_actor.clear();_style_preferences_frame=-1
 for id in _tendencies:policy.set_tendencies(int(id),_tendencies[id])
 return true

func set_actor_tendencies(actor_id:int, values:Dictionary) -> bool:
 if not policy.set_tendencies(actor_id,values):return false
 _tendencies[actor_id]={"cover_depth_offset":policy.roster[actor_id].cover_depth_offset,"poach_tendency":policy.roster[actor_id].poach_tendency}
 return true

func cancel(reason:String="explicit lifecycle reset") -> void:
 policy.reset(reason);_history.clear();_world_history.clear();last_decision_by_actor.clear();last_steering_by_actor.clear();_last_frame=-1;_style_preferences_frame=-1

func _public_context() -> Dictionary:
 var ball=game.ball
 var receiver:=-1;var service_token:=-1
 if "doubles_state" in game and game.doubles_state!=null:
  var rally:Dictionary=game.doubles_state.active_rally
  if not rally.is_empty():
   service_token=int(rally.get("token",-1))
   if int(rally.get("first_return_actor",-1))<0:
    var actor=game.get_receiver_actor()
    if actor!=null:receiver=actor.get_actor_id()
 var incoming:int=1-int(ball.last_hit_by) if int(ball.last_hit_by) in [0,1] else -1
 return {"flight_id":int(ball.flight_id),"reset_generation":int(game._point_reset_generation),"service_token":service_token,
  "required_receiver":receiver,"incoming_team":incoming,"in_play":bool(ball.is_in_play),
  "eligible_play":game.game_state==game.GameState.PLAYING and not game.match_over and not game._tool_state_active(),
  "both_bounces_complete":bool(ball.both_bounces_complete)}

func _begin(delta:float) -> bool:
 if game==null or not is_instance_valid(game) or not _configure_roster():return false
 var frame:int=Engine.get_physics_frames()
 if frame!=_last_advanced_frame:
  _clock+=delta if delta>0.0 else maxf(game.get_physics_process_delta_time(),0.0)
  _last_advanced_frame=frame
 _last_frame=frame
 policy.begin_frame(frame,_clock,_public_context())
 if _seen_generation!=policy.generation:
  _seen_generation=policy.generation;_history.clear();_world_history.clear();last_decision_by_actor.clear()
 # A team decision caches both teammates' targets. Publish one coherent style
 # batch before any actor may resolve it, never while that frame is in progress.
 if not _publish_frame_style_preferences(frame):return false
 return true

func _publish_frame_style_preferences(frame:int) -> bool:
 if frame==_style_preferences_frame:return true
 var pending:Dictionary={}
 for actor in game.get_players():
  var id:int=actor.get_actor_id()
  if not policy.roster.has(id):return false
  var values:Dictionary={}
  if actor.is_ai and actor.ai_brain.has_method("style_position_preferences"):
   # This existing getter preserves the style latched in a current flight plan.
   values=actor.ai_brain.style_position_preferences()
  var depth:float=float(values.get("cover_depth",0.0))
  var poach:float=float(values.get("poach_tendency",0.0))
  if not is_finite(depth) or not is_finite(poach):return false
  pending[id]={"cover_depth_offset":depth,"poach_tendency":poach}
 # Validate the complete roster before writing any preference. No decisions,
 # offers, actor poses, plans, execution latches, or random streams change here.
 if pending.size()!=policy.roster.size():return false
 var ids:Array=pending.keys();ids.sort()
 for id in ids:
  if not set_actor_tendencies(int(id),pending[id]):return false
 _style_preferences_frame=frame
 return true

func _visible(actor) -> Dictionary:
 var human=actor.posture.human_contact if actor.posture!=null else null
 var committed:bool=human!=null and human.phase in [0,1] and human.visual_pose!=null if not actor.is_ai else actor.ai_brain.ai_is_charging
 var head_node=actor.paddle_node.get_node_or_null("Head")
 var head:Vector3=head_node.global_position if head_node!=null else actor.paddle_node.global_position
 var arm=actor.right_arm_node
 var wrist:Vector3=arm.forearm_pivot.to_global(Vector3(0,0,-arm.forearm_length))
 return {"actor_id":actor.get_actor_id(),"team_id":actor.get_team_id(),"court_side":actor.get_court_side(),
  "root":actor.global_position,"velocity":actor.current_velocity,"shoulder":arm.upper_pivot.global_position,"head":head,
  "head_reach":float(arm.upper_arm_length+arm.forearm_length)+wrist.distance_to(head),"committed_visible":committed,
  "radius":Avoidance.DEFAULT_RADIUS,"speed":float(actor.move_speed)}

func begin_physics_frame(delta:float) -> void:
 # Game runs before its actor children: every teammate snapshot is from the
 # same completed prior interval, independent of subsequent AI node order.
 if not _begin(delta):return
 if not _world_history.is_empty() and int(_world_history[-1].frame)==_last_frame:return
 var visible:Dictionary={};var instances:Dictionary={}
 for actor in game.get_players():
  visible[actor.get_actor_id()]=_visible(actor)
  instances[actor.get_actor_id()]=actor.get_instance_id()
 var ball=game.ball
 var ball_state:PackedByteArray=var_to_bytes([ball.global_position,ball.linear_velocity,ball.angular_velocity,int(ball.flight_id),int(ball.bounces_since_last_hit)])
 _world_history.append({"frame":_last_frame,"time":_clock,"visible":visible,"instances":instances,"bounces":int(ball.bounces_since_last_hit),
  "policy_generation":policy.generation,"reset_generation":int(game._point_reset_generation),"flight_id":int(ball.flight_id),"ball_state":ball_state})
 while _world_history.size()>1 and _clock-float(_world_history[1].time)>2.0:_world_history.pop_front()

func opponent_centroid_for_frame(actor) -> Dictionary:
 # Pure lookup of the one existing beginning-of-physics snapshot. Never refresh
 # from current actor poses here, and never advance the coordinator clock.
 if game==null or not is_instance_valid(game) or actor==null or not is_instance_valid(actor):return {"valid":false,"reason":"missing game or actor"}
 if _world_history.is_empty():return {"valid":false,"reason":"opponent snapshot unavailable"}
 var sample:Dictionary=_world_history[-1]
 var frame:int=Engine.get_physics_frames()
 if int(sample.get("frame",-1))!=frame:return {"valid":false,"reason":"opponent snapshot frame stale"}
 if int(sample.get("policy_generation",-1))!=policy.generation or int(sample.get("reset_generation",-1))!=int(game._point_reset_generation):return {"valid":false,"reason":"opponent snapshot generation stale"}
 var ball=game.ball
 if ball==null or int(sample.get("flight_id",-1))!=int(ball.flight_id):return {"valid":false,"reason":"opponent snapshot flight stale"}
 var ball_state:PackedByteArray=var_to_bytes([ball.global_position,ball.linear_velocity,ball.angular_velocity,int(ball.flight_id),int(ball.bounces_since_last_hit)])
 if sample.get("ball_state",PackedByteArray())!=ball_state:return {"valid":false,"reason":"ball changed after opponent snapshot"}
 var visible:Dictionary=sample.get("visible",{});var instances:Dictionary=sample.get("instances",{})
 var players:Array=game.get_players()
 if players.size()!=visible.size() or players.size()!=instances.size():return {"valid":false,"reason":"opponent snapshot roster changed"}
 for current in players:
  var id:int=current.get_actor_id()
  if not visible.has(id) or int(instances.get(id,-1))!=current.get_instance_id():return {"valid":false,"reason":"opponent snapshot actor replaced"}
  if int(visible[id].team_id)!=current.get_team_id() or int(visible[id].court_side)!=current.get_court_side():return {"valid":false,"reason":"opponent snapshot identity changed"}
 var own_id:int=actor.get_actor_id()
 if int(instances.get(own_id,-1))!=actor.get_instance_id():return {"valid":false,"reason":"query actor not in snapshot"}
 var ids:Array=visible.keys();ids.sort();var total:=Vector3.ZERO;var count:=0
 for id in ids:
  var record:Dictionary=visible[id]
  if int(record.team_id)==actor.get_team_id():continue
  var point:Vector3=record.root
  if not point.is_finite():return {"valid":false,"reason":"opponent snapshot point nonfinite"}
  total+=point;count+=1
 if count==0:return {"valid":false,"reason":"opponent snapshot has no opponent"}
 if not total.is_finite():return {"valid":false,"reason":"opponent snapshot centroid overflow"}
 return {"valid":true,"position":total/float(count),"frame":frame,"world_time":float(sample.time),"policy_generation":int(sample.policy_generation),"reset_generation":int(sample.reset_generation),"flight_id":int(sample.flight_id)}

func _observe(brain,_delta:float) -> Dictionary:
 var latency:float=brain._get_latency_frames()/float(Engine.physics_ticks_per_second)
 if _world_history.is_empty():return {"ready":false,"age":0.0,"latency":latency,"visible":{},"bounces":0}
 var old:Dictionary=_world_history.front()
 for sample:Dictionary in _world_history:
  if _clock-float(sample.time)>=latency-.000001:old=sample
  else:break
 var age:float=_clock-float(old.time)
 var team_visible:Dictionary={}
 for id in old.visible:
  if int(old.visible[id].team_id)==brain._player.get_team_id():team_visible[id]=old.visible[id]
 return {"ready":age>=latency-.000001,"age":age,"latency":latency,"visible":team_visible,"bounces":int(old.bounces)}

func _human_offer(brain,observed:Dictionary,age:float,latency:float,ready:bool,flight_id:int,observed_bounces:int) -> Dictionary:
 var root:Vector3=Vector3(observed.root)+Vector3(observed.velocity)*age
 var velocity:Vector3=observed.velocity
 var result:Dictionary={"flight_id":flight_id,"root":root,"velocity":velocity,"target":root,"contact":observed.head,"time":-1.0,
  "reachable":false,"committed_visible":observed.committed_visible,"ready":ready and brain._perception_ready,"sample_age":age,"latency":latency}
 if not result.ready:return result
 # Extrapolate the observed movement, rather than invent future human input.
 # This is a visible geometric reach bound, not finite contact certification.
 var shoulder_offset:Vector3=Vector3(observed.shoulder)-Vector3(observed.root)
 var flight:Dictionary=brain._get_predicted_flight(game.ball)
 for sample:Dictionary in flight.get("samples",[]):
  var time:float=float(sample.get("time",-1.0));var point:Vector3=sample.get("pos",Vector3.INF)
  if time<0.0 or not point.is_finite() or point.y<.15:continue
  if (point.z>0.0)!=(int(observed.court_side)==0):continue
  var predicted_root:Vector3=root+velocity*time
  var actor:Dictionary=policy.roster[int(observed.actor_id)]
  predicted_root.x=clampf(predicted_root.x,actor.min_x,actor.max_x);predicted_root.z=clampf(predicted_root.z,actor.min_z,actor.max_z)
  if point.distance_to(predicted_root+shoulder_offset)>float(observed.head_reach):continue
  var bounces:int=observed_bounces+int(brain._perceived_state.get("bounces",0))+int(sample.get("bounces",0))
  if bounces>=2:continue
  if not policy._context.get("both_bounces_complete",false) and bounces<=0:continue
  result.target=predicted_root;result.contact=point;result.time=time;result.reachable=true;break
 return result

func advise(brain,ordinary_offer:Dictionary,delta:float) -> Dictionary:
 if not _begin(delta):return {"pursue":false,"reason":"coordination not configured"}
 var actor=brain._player;var id:int=actor.get_actor_id()
 # Bench stand-in for a human: plays every ball itself, never coordinated;
 # its partner models it from sight like a real human (_human_offer below).
 if id==RuntimePolicy.bench_human:return {"pursue":true,"owner":id,"reason":"bench human"}
 var observed:Dictionary=_observe(brain,delta)
 var flight:int=int(policy._context.flight_id)
 var age:float=0.0
 if not brain._ball_history.is_empty():age=brain._observation_time-float(brain._ball_history.front().time)
 var latency:float=brain._get_latency_frames()/float(Engine.physics_ticks_per_second)
 var reported:Dictionary=ordinary_offer
 if brain.ai_is_charging and brain._charge_contact_flight==flight:
  reported={"target":brain._charge_target_position,"contact":brain._charge_contact_position,"time":maxf(0.0,brain._charge_contact_deadline-brain._observation_time),"reachable":true}
 var own:Dictionary={"flight_id":flight,"root":actor.global_position,"velocity":actor.current_velocity,
  "target":reported.get("target",actor.global_position),"contact":reported.get("contact",actor.global_position),
  "time":float(reported.get("time",-1.0)),"reachable":bool(reported.get("reachable",false)),
  "stroke_started":brain.ai_is_charging and brain.coordination_forward_progress>0.0 and brain._pose_alignment_tick==Engine.get_physics_frames()-1,
  "stroke_progress":brain.coordination_forward_progress if brain.ai_is_charging else 0.0,
  "committed_visible":bool(brain.ai_is_charging),"ready":bool(brain._perception_ready),"sample_age":age,"latency":latency}
 policy.publish(id,own)
 for teammate_id in observed.visible:
  var teammate=game.get_player_by_actor_id(int(teammate_id))
  if teammate!=null and (not teammate.is_ai or int(teammate_id)==RuntimePolicy.bench_human):
   policy.publish(int(teammate_id),_human_offer(brain,observed.visible[teammate_id],observed.age,observed.latency,observed.ready,flight,int(observed.bounces)))
 var decision:Dictionary=policy.decision(id)
 last_decision_by_actor[id]=decision.duplicate(true)
 return decision

func may_begin_stroke(actor) -> bool:
 if not _begin(0.0):return false
 if actor.get_actor_id()==RuntimePolicy.bench_human:return true
 return bool(policy.decision(actor.get_actor_id()).pursue)

func cover_input(brain,decision:Dictionary) -> Vector3:
 var actor=brain._player
 if brain.ai_is_charging or brain._execution_commit_active:
  var result:Dictionary=Cancel.cancel_pending(brain,"fresh shared advisory pursuit revoked")
  result["actor_id"]=actor.get_actor_id();result["frame"]=Engine.get_physics_frames()
  cancellations.append(result)
 var target:Vector3=decision.get("target",actor.global_position)
 brain.ai_target_position=target
 brain.ai_committed_target_position=target
 var offset:Vector3=target-actor.global_position;offset.y=0
 return offset.normalized() if offset.length()>.12 else Vector3.ZERO

func filter_ground_velocity(brain,desired:Vector3,delta:float) -> Vector3:
 if not _begin(0.0):return desired
 var actor=brain._player;var id:int=actor.get_actor_id()
 if _world_history.is_empty():return desired
 var observed:Dictionary=_observe(brain,delta);var partners:Array=[]
 if not observed.ready:return desired
 for other_id in observed.visible:
  if int(other_id)==id:continue
  var item:Dictionary=observed.visible[other_id].duplicate()
  item.root=Vector3(item.root)+Vector3(item.velocity)*float(observed.age)
  partners.append(item)
 var result:Dictionary=Avoidance.steer(actor.global_position,actor.current_velocity,desired,partners,delta,float(actor.move_speed),16.0)
 last_steering_by_actor[id]=result
 return result.velocity
