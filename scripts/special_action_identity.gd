extends RefCounted
## Match-only action ownership: a TEAM alias never identifies one partner.
const Actors=preload("res://scripts/contact_actor_identity.gd")
static func describe(actor)->Dictionary:
 if not is_instance_valid(actor) or not Actors.valid(actor):return {}
 if "actor_id" in actor and int(actor.actor_id)<0:return {}
 var registry=actor.get_parent()
 if registry==null or not registry.has_method("get_player_by_actor_id") or registry.get_player_by_actor_id(Actors.actor_id(actor))!=actor:return {}
 return {"actor_id":Actors.actor_id(actor),"team_id":Actors.team_id(actor),"court_side":Actors.court_side(actor),"player_num":Actors.team_id(actor)}
static func matches(actor,state:Dictionary)->bool:
 var identity:=describe(actor)
 if identity.is_empty():return false
 for key in ["actor_id","team_id","court_side"]:
  if int(state.get(key,-1))!=int(identity[key]):return false
 return not state.has("player_num") or int(state.player_num)==int(identity.team_id)
static func annotate(actor,state:Dictionary)->Dictionary:
 var identity:=describe(actor)
 if identity.is_empty():return {}
 var result:=state.duplicate(true);result.merge(identity,true);return result
static func incoming(actor,ball)->bool:
 var identity:=describe(actor)
 if identity.is_empty() or ball==null or not ball.is_in_play:return false
 var last:int=ball.get_last_hit_actor_id();var team:int=ball.get_last_hit_team_id();var side:int=ball.get_last_hit_court_side()
 var hitter=actor.get_parent().get_player_by_actor_id(last)
 return hitter!=null and Actors.team_id(hitter)==team and Actors.court_side(hitter)==side and team==1-int(identity.team_id)
static func ball_identity(ball)->Dictionary:
 return {"last_hit_actor_id":ball.get_last_hit_actor_id(),"last_hit_team_id":ball.get_last_hit_team_id(),"last_hit_court_side":ball.get_last_hit_court_side()}
static func flight_matches(ball,state:Dictionary)->bool:
 if ball==null or int(state.get("flight_id",-1))!=ball.flight_id:return false
 var current:=ball_identity(ball)
 for key in current:
  if int(state.get(key,-1))!=int(current[key]):return false
 return not state.has("last_hit_by") or int(state.last_hit_by)==ball.get_last_hit_team_id()
static func forecast_ball(ball,base_bounces:int)->Dictionary:
 ## Prediction-only public state view. Never mutate the live Ball or add its
 ## current bounce count to a forecast rooted in an older observation.
 return {"bounces_since_last_hit":base_bounces,"last_hit_by":ball.get_last_hit_team_id(),"last_hit_court_side":ball.get_last_hit_court_side(),"wall_practice_active":ball.wall_practice_active if "wall_practice_active" in ball else false}
