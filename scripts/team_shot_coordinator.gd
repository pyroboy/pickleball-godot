extends RefCounted
## Advisory ownership only. This object cannot touch ball physics or scoring.
const SWITCH_ADVANTAGE_SECONDS := 0.16
const MIN_CLAIM_SECONDS := 0.14
const LATE_SWITCH_SECONDS := 0.45
const COVER_TARGET_SPEED := 2.5
const MIDDLE_DEADBAND := 0.55
const CHASE_MIN_RUN := 0.05        # m: an offer with no run target is not a chase
const CHASE_KEEP_ADVANTAGE := 0.5  # m the current chaser is favoured by, so partners don't swap
const HUMAN_SIDE_MARGIN := 0.2     # m past the partners' midpoint, toward the human, that makes a ball the human's
# Who takes the ball: the partner for whom it is the easier ball, not simply whoever could touch it
# first. A metre of running weighs like RUN_COST seconds of waiting, and a run that needs more
# than STRAIN_SPEED m/s all the way weighs extra. (Before: 0.06 s per metre, so the partner who
# could lunge across and reach a drive a moment earlier took it from the one it was going to.)
const RUN_COST := 0.30
const STRAIN_SPEED := 2.5
const STRAIN_COST := 0.08
# A partner whose brain has not planned this ball yet (the AIs plan one per tick) is waited for
# this long (from when it was first seen planning) before the other one is given it. Before, the
# first to plan claimed it and kept it.
const PLAN_WAIT_SECONDS := 0.12
var roster: Dictionary = {}
var teams: Dictionary = {0: [], 1: []}
var _context_key: Array = []
var _context: Dictionary = {}
var _offers: Dictionary = {}
var _claims: Dictionary = {}
var _decisions: Dictionary = {}
var _cover: Dictionary = {}
var _frame := -1
var _time := 0.0
var _plan_wait: Dictionary = {}   # team -> time a partner was first seen still planning this ball
var generation := 0
var last_reset_reason := "unconfigured"

func configure(actors: Array) -> bool:
 var next: Dictionary = {}; var grouped: Dictionary = {0: [], 1: []}
 for actor: Dictionary in actors:
  if typeof(actor.get("actor_id"))!=TYPE_INT or typeof(actor.get("team_id"))!=TYPE_INT or typeof(actor.get("court_side"))!=TYPE_INT:return false
  var id=int(actor.get("actor_id",-1)); var team=int(actor.get("team_id",-1)); var side=int(actor.get("court_side",-1))
  if id<0 or next.has(id) or team not in [0,1] or side not in [0,1]:return false
  var home:Vector3=actor.get("home",Vector3.INF)
  if not home.is_finite():return false
  next[id]={"actor_id":id,"team_id":team,"court_side":side,"human":bool(actor.get("human",false)),"home":home,"cover_depth_offset":0.0,"poach_tendency":0.0,
   "min_x":float(actor.get("min_x",-3.1)),"max_x":float(actor.get("max_x",3.1)),"min_z":float(actor.get("min_z",.3 if side==0 else -8.0)),"max_z":float(actor.get("max_z",8.0 if side==0 else -.3))}
  grouped[team].append(id)
 if grouped[0].size()!=2 or grouped[1].size()!=2:return false
 for team in [0,1]:
  grouped[team].sort()
  if next[grouped[team][0]].court_side!=next[grouped[team][1]].court_side:return false
 if next[grouped[0][0]].court_side==next[grouped[1][0]].court_side:return false
 roster=next;teams=grouped;reset("configured");return true

func set_tendencies(actor_id:int, values:Dictionary) -> bool:
 # Public numeric positioning preferences, never profile names or shot intent.
 # These cannot create eligibility, displace a required receiver, or defeat a
 # committed reachable human. Default values preserve the neutral policy.
 if not roster.has(actor_id):return false
 var depth:float=float(values.get("cover_depth_offset",0.0))
 var poach:float=float(values.get("poach_tendency",0.0))
 if not is_finite(depth) or not is_finite(poach):return false
 roster[actor_id].cover_depth_offset=clampf(depth,-.45,.45)
 roster[actor_id].poach_tendency=clampf(poach,-1.0,1.0)
 return true

func reset(reason: String) -> void:
 generation+=1;last_reset_reason=reason
 _offers.clear();_claims.clear();_decisions.clear();_cover.clear();_plan_wait.clear();_context_key=[];_context={};_frame=-1

func begin_frame(frame: int, simulation_time: float, public_context: Dictionary) -> void:
 if frame<0 or not is_finite(simulation_time):reset("invalid public clock");return
 var key:Array=[int(public_context.get("flight_id",-1)),int(public_context.get("reset_generation",-1)),
  int(public_context.get("service_token",-1)),int(public_context.get("required_receiver",-1)),
  int(public_context.get("incoming_team",-1)),bool(public_context.get("in_play",false)),bool(public_context.get("eligible_play",false))]
 if key!=_context_key or frame<_frame:
  _offers.clear();_claims.clear();_decisions.clear();_cover.clear();generation+=1;_plan_wait.clear()
  last_reset_reason="public flight, lifecycle or service eligibility changed"
 _context_key=key;_context=public_context.duplicate(true);_frame=frame;_time=simulation_time
 for old_frame in _offers.keys():
  if int(old_frame)<frame-1:_offers.erase(old_frame)
 for team in _decisions.keys():
  if int(_decisions[team].frame)!=frame:_decisions.erase(team)

func publish(actor_id: int, observation: Dictionary) -> bool:
 if not roster.has(actor_id) or _frame<0:return false
 if int(observation.get("flight_id",-1))!=int(_context.get("flight_id",-2)):return false
 var root:Vector3=observation.get("root",Vector3.INF);var velocity:Vector3=observation.get("velocity",Vector3.INF)
 var target:Vector3=observation.get("target",root);var contact:Vector3=observation.get("contact",root)
 var age:float=float(observation.get("sample_age",-1.0));var latency:float=float(observation.get("latency",0.0))
 var time:float=float(observation.get("time",-1.0))
 if not root.is_finite() or not velocity.is_finite() or not target.is_finite() or not contact.is_finite():return false
 if not is_finite(age) or not is_finite(latency) or not is_finite(time) or age<0.0 or latency<0.0:return false
 var ready:bool=bool(observation.get("ready",false)) and age+.000001>=latency
 var offer:Dictionary={"actor_id":actor_id,"frame":_frame,"at":_time,"flight_id":int(observation.flight_id),
  "root":root,"velocity":velocity,"target":target,"contact":contact,"deadline":_time+maxf(time,0.0),
  "reachable":bool(observation.get("reachable",false)) and time>=0.0 and ready,
  "committed":bool(observation.get("committed_visible",false)) and ready,"ready":ready,
  "stroke_started":bool(observation.get("stroke_started",false)) and ready,"stroke_progress":float(observation.get("stroke_progress",0.0)),
  "sample_age":age,"latency":latency,"pending":bool(observation.get("pending",false))}
 offer.make_read_only()
 if not _offers.has(_frame):_offers[_frame]={}
 if _offers[_frame].has(actor_id):return false
 _offers[_frame][actor_id]=offer;return true

func decision(actor_id: int) -> Dictionary:
 if not roster.has(actor_id):return {"owner":-1,"pursue":false,"reason":"unregistered actor"}
 var team:int=roster[actor_id].team_id
 if not _decisions.has(team):_decisions[team]=_resolve_team(team)
 var result:Dictionary=_decisions[team].duplicate(true)
 result["pursue"]=int(result.owner)==actor_id
 result["target"]=result.targets.get(actor_id,roster[actor_id].home)
 return result

func _eligible(offer: Dictionary, team: int) -> bool:
 if not bool(_context.get("in_play",false)) or not bool(_context.get("eligible_play",false)):return false
 if int(_context.get("incoming_team",-1))!=team:return false
 var receiver:int=int(_context.get("required_receiver",-1))
 # Only the immediately preceding completed frame is consumed by _resolve_team.
 # ETA is a prediction used for ranking, not a physical contact expiry. A
 # reachable offer at ETA zero still describes the interval now being consumed.
 # New flight/service/dead state invalidates immediately; absent/false next-frame
 # offers withdraw the advisory claim. Actual contact authority remains final.
 return (receiver<0 or receiver==int(offer.actor_id)) and bool(offer.reachable)

func _may_chase(offer: Dictionary, team: int) -> bool:
 if not bool(_context.get("in_play",false)) or not bool(_context.get("eligible_play",false)):return false
 if int(_context.get("incoming_team",-1))!=team:return false
 var receiver:int=int(_context.get("required_receiver",-1))
 return (receiver<0 or receiver==int(offer.actor_id)) and bool(offer.ready)

func _yields_to_human(id: int, team: int, prior: Dictionary) -> bool:
 # An AI never takes a ball headed to its human partner's side of the court.
 # "Side" is split at the midpoint between the two partners (so it follows
 # them when they move); only balls in the middle strip stay contestable.
 if roster[id].human or not prior.has(id):return false
 for other in teams[team]:
  if other==id or not roster[other].human or not prior.has(other):continue
  var human_x:float=Vector3(prior[other].root).x;var ai_x:float=Vector3(prior[id].root).x
  var side:float=signf(human_x-ai_x) if absf(human_x-ai_x)>.3 else signf(Vector3(roster[other].home).x-Vector3(roster[id].home).x)
  if side==0.0:return false
  var mid:float=(human_x+ai_x)*.5
  return (Vector3(prior[id].contact).x-mid)*side>HUMAN_SIDE_MARGIN
 return false

func _cost(offer: Dictionary) -> float:
 var travel:Vector3=Vector3(offer.target)-Vector3(offer.root);travel.y=0.0
 var reversal:float=.12 if Vector3(offer.velocity).dot(travel)<-.1 else 0.0
 var actor:Dictionary=roster[int(offer.actor_id)]
 var crossing:bool=absf(Vector3(offer.target).x)<MIDDLE_DEADBAND or Vector3(offer.target).x*Vector3(actor.home).x<0.0
 var poach:float=float(actor.poach_tendency)*.06 if crossing else 0.0
 var eta:float=maxf(0.0,float(offer.deadline)-_time)
 var strain:float=maxf(0.0,travel.length()/maxf(eta,.05)-STRAIN_SPEED)*STRAIN_COST if travel.length()>.3 else 0.0
 return eta+travel.length()*RUN_COST+strain+reversal-poach

func _resolve_team(team: int) -> Dictionary:
 var prior:Dictionary=_offers.get(_frame-1,{})
 var ids:Array=teams[team]
 var complete:bool=prior.has(ids[0]) and prior.has(ids[1])
 var selected:=-1;var best:=INF;var reason:="waiting for prior completed observation frame"
 # Nobody has the ball yet and a partner is still to plan it: wait a moment for both plans.
 var planning:bool=false
 if complete and not _claims.has(team):
  for id in ids:
   if bool(prior[id].get("pending",false)) and _may_chase(prior[id],team):planning=true
  if planning:
   if not _plan_wait.has(team):_plan_wait[team]=_time
   planning=_time-float(_plan_wait[team])<PLAN_WAIT_SECONDS
 if planning:reason="waiting for both partners' plans"
 if complete and not planning:
  reason="no legal reachable offer"
  for id in ids:
   var offer:Dictionary=prior[id]
   if not _eligible(offer,team) or _yields_to_human(id,team,prior):continue
   var value:float=_cost(offer)
   if roster[id].human and offer.committed:
    selected=id;best=value;reason="observed reachable human commitment";break
   if value<best-.000001 or absf(value-best)<=.000001 and (selected<0 or roster[id].human and not roster[selected].human or roster[id].human==roster[selected].human and id<selected):
    best=value;selected=id;reason="earliest natural reachable offer"
  var old:Dictionary=_claims.get(team,{})
  var old_id:int=int(old.get("actor_id",-1))
  # The previous owner has already physically sampled its forward stroke.
  # A late human queue cannot require an unsafe withdrawal through the ball.
  # Fresh flight, service, reach or dead-ball invalidation still wins immediately.
  if reason=="observed reachable human commitment" and old_id!=selected and prior.has(old_id) and _eligible(prior[old_id],team) and bool(prior[old_id].get("stroke_started",false)):
   selected=old_id;reason="existing physical forward stroke retains reachable owner"
  if selected>=0 and reason!="observed reachable human commitment" and prior.has(old_id) and _eligible(prior[old_id],team) and not _yields_to_human(old_id,team,prior):
   var old_cost:float=_cost(prior[old_id])
   # No hand-off in the last moments: a partner given the ball under LATE_SWITCH_SECONDS before
   # its contact cannot set up (bench: owner changed 0.2-0.4 s before contact, nobody hit it).
   var late:bool=selected!=old_id and maxf(0.0,float(prior[selected].deadline)-_time)<LATE_SWITCH_SECONDS
   if late or bool(prior[old_id].committed) or _time-float(old.get("since",_time))<MIN_CLAIM_SECONDS or old_cost-best<SWITCH_ADVANTAGE_SECONDS:
    selected=old_id
    if reason!="existing physical forward stroke retains reachable owner":reason="stable reachable claim"
  if selected<0:
   # Nobody is certain to reach it: the partner with the shorter run still goes
   # for the ball (and may lunge) instead of both holding their cover spots.
   # Before, a ball through the middle or wide of both was left to bounce twice.
   var shortest:=INF
   for id in ids:
    var offer:Dictionary=prior[id]
    if not _may_chase(offer,team) or _yields_to_human(id,team,prior):continue
    var run:Vector3=Vector3(offer.target)-Vector3(offer.root);run.y=0.0
    if run.length()<CHASE_MIN_RUN:continue
    var value:float=run.length()-(CHASE_KEEP_ADVANTAGE if id==old_id else 0.0)
    if value<shortest:shortest=value;selected=id;reason="best-effort chase"
  if selected>=0:
   if int(old.get("actor_id",-1))!=selected:_claims[team]={"actor_id":selected,"since":_time}
  else:_claims.erase(team)
 var targets:Dictionary={}
 for id in ids:
  targets[id]=prior[id].target if selected==id else _cover_target(id,selected,prior)
 # What each partner offered (bench note "team_claim": who took the ball and what the other could have done).
 var offers:Dictionary={}
 if complete:
  for id in ids:
   var run:Vector3=Vector3(prior[id].target)-Vector3(prior[id].root);run.y=0.0
   offers[id]={"run":run.length(),"eta":maxf(0.0,float(prior[id].deadline)-_time),"reachable":_eligible(prior[id],team),"x":Vector3(prior[id].root).x,"z":Vector3(prior[id].root).z,"contact_x":Vector3(prior[id].contact).x,"contact_z":Vector3(prior[id].contact).z,"contact_y":Vector3(prior[id].contact).y,"offered":bool(prior[id].reachable),"ready":bool(prior[id].ready),"cost":_cost(prior[id])}
 return {"frame":_frame,"generation":generation,"owner":selected,"reason":reason,"targets":targets,"offers":offers,
  "source_frame":_frame-1,"complete_observations":complete,"required_receiver":int(_context.get("required_receiver",-1))}

func _cover_target(id: int, owner: int, offers: Dictionary) -> Vector3:
 var actor:Dictionary=roster[id];var target:Vector3=actor.home
 if bool(_context.get("both_bounces_complete",false)):target.z=3.05*(1.0 if actor.court_side==0 else -1.0)
 if owner>=0 and offers.has(owner):
  var owner_target:Vector3=offers[owner].target
  var owner_contact:Vector3=offers[owner].contact
  var lane:float=signf(actor.home.x) if absf(actor.home.x)>.05 else (-1.0 if id==teams[actor.team_id][0] else 1.0)
  if absf(owner_target.x)>MIDDLE_DEADBAND:lane=-signf(owner_target.x)
  target.x=lane*1.35
  var depth:float=3.05 if bool(_context.get("both_bounces_complete",false)) else 5.9
  if absf(owner_contact.z)>5.0:depth=maxf(depth,absf(owner_contact.z)-.7)
  target.z=depth*(1.0 if actor.court_side==0 else -1.0)
 target.z+=float(actor.cover_depth_offset)*(1.0 if actor.court_side==0 else -1.0)
 target.x=clampf(target.x,actor.min_x,actor.max_x);target.z=clampf(target.z,actor.min_z,actor.max_z)
 var previous:Dictionary=_cover.get(id,{})
 if not previous.is_empty():target=Vector3(previous.target).move_toward(target,COVER_TARGET_SPEED*maxf(0.0,_time-float(previous.time)))
 _cover[id]={"target":target,"time":_time}
 return target
