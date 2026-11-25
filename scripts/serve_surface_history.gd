extends RefCounted
## A release is an observed owner event, never permission for later body hits.
## Only actual cup-hand triangles already touching at release can depart, and
## each skipped triangle must prove outward separation for the whole interval.
const ActorIdentity=preload("res://scripts/contact_actor_identity.gd")
const Surface=preload("res://scripts/player_surface_contacts.gd")
const History=preload("res://scripts/player_surface_history.gd")
const Geometry=preload("res://scripts/contact_surface_geometry.gd")
var active:=false
var server_num:=-1 # legacy team alias
var server_actor_id:=-1
var previous:Dictionary={}
var current:Dictionary={}
var ball_from:=Vector3.ZERO
var departures:Dictionary={}
## Simple hand shape (articulated_hand.gd, one palm box): the server's hand that holds the ball
## at release. The box has no cupped fingers to tell "leaving the hand" from "hitting it"
## triangle by triangle, so that hand cannot fault the serve; every other part still can.
var held_parts:Dictionary={}
var fault:Dictionary={}
var latest:Dictionary={}
func clear()->void:
 active=false;previous.clear();current.clear();departures.clear();held_parts.clear();fault={};latest={}
func prime(players:Array,server,point:Vector3,radius:float)->void:
 clear();active=true;server_num=ActorIdentity.team_id(server);server_actor_id=ActorIdentity.actor_id(server);ball_from=point
 for p in players:previous[ActorIdentity.actor_id(p)]=Surface.snapshot(p,true)
 var snapshot:Dictionary=previous[server_actor_id]
 for id in snapshot.parts:
  var part:Dictionary=snapshot.parts[id]
  if not part.hand.is_empty():
   if part.hand.has("grip"):
    if AABB(part.bounds).grow(radius+HELD_REACH_M).has_point(point):held_parts[int(id)]=true
    continue
   var triangles:Dictionary=touching_triangles(part,point,radius)
   if not triangles.is_empty():departures[int(id)]=triangles
 current=previous.duplicate(true)
func sample(players:Array,point:Vector3,radius:float)->Dictionary:
 if not active:return {"blocked":true,"reason":"serve_release_not_observed"}
 if not fault.is_empty():return fault
 current.clear()
 var first:Dictionary={"hit":false,"blocked":false,"ambiguous":false,"fraction":2.0}
 var total_queries:=0;var total_algebra_units:=0
 for p in players:
  var now:=Surface.snapshot(p,true);current[ActorIdentity.actor_id(p)]=now
  var before:Dictionary=previous.get(ActorIdentity.actor_id(p),now)
  if ActorIdentity.actor_id(p)==server_actor_id and not held_parts.is_empty():
   before=_without_held(before);now=_without_held(now)
  var allowed:Dictionary=departures if ActorIdentity.actor_id(p)==server_actor_id else {}
  var remaining_units:int=maxi(0,576-total_algebra_units)
  var found:=History.query(before,now,ball_from,point,radius,1.0,true,0.0,1.0,-1,maxi(0,4096-total_queries),allowed,12,{},Vector3.INF,remaining_units)
  total_queries+=int(found.get("queries",0));total_algebra_units+=int(found.get("algebra_work_units",0))
  ActorIdentity.annotate(found,p)
  first=ActorIdentity.earliest(first,found)
 latest=first
 if first.get("ambiguous",false):
  fault=first.duplicate(true);fault["reason"]="unresolved_serve_delivery";return fault
 if first.get("hit",false) and (first.get("kind","")!="legal_paddle" or int(first.actor_id)!=server_actor_id or first.get("simultaneous_partner_contact",false)):
  fault=first.duplicate(true);fault["reason"]="serve_body_contact";return fault
 var snapshot:Dictionary=current[server_actor_id]
 for id in departures.keys():
  if not snapshot.parts.has(id):departures.erase(id);continue
  var touching_now:Dictionary=touching_triangles(snapshot.parts[id],point,radius)
  for offset in departures[id].keys():
   if not touching_now.has(offset):departures[id].erase(offset)
  if departures[id].is_empty():departures.erase(id)
 previous=current.duplicate(true);ball_from=point
 return first
const HELD_REACH_M:=0.02 # a hand whose box is this close to the ball's surface at release holds it
func _without_held(snapshot:Dictionary)->Dictionary:
 if not snapshot.has("parts"):return snapshot
 var kept:Dictionary={}
 for id in snapshot.parts:
  if not held_parts.has(int(id)):kept[id]=snapshot.parts[id]
 var copy:Dictionary=snapshot.duplicate()
 copy.erase("lean_without_legs");copy.erase("lean_without_paddle")
 copy["parts"]=kept
 return copy
static func touching(part:Dictionary,point:Vector3,radius:float)->bool:
 if not AABB(part.bounds).grow(radius+History.CONTACT_EPSILON).has_point(point):return false
 var triangles:=Surface.snapshot_triangles(part)
 for i in range(0,triangles.size()-2,3):
  if point.distance_to(Geometry.closest_triangle(point,triangles[i],triangles[i+1],triangles[i+2]))<=radius+History.CONTACT_EPSILON:return true
 return false

static func touching_triangles(part:Dictionary,point:Vector3,radius:float)->Dictionary:
 var result:Dictionary={}
 if not AABB(part.bounds).grow(radius+History.CONTACT_EPSILON).has_point(point):return result
 var triangles:=Surface.snapshot_triangles(part)
 for i in range(0,triangles.size()-2,3):
  var distance:float=point.distance_to(Geometry.closest_triangle(point,triangles[i],triangles[i+1],triangles[i+2]))
  if distance<=radius+History.CONTACT_EPSILON:result[i]=maxf(0.0,radius-distance)
 return result
