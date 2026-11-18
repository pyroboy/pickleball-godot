extends RefCounted
## Force-free finite floor/virtual-ceiling drift, shared by actual continuation
## and prediction. Caller owns the already consumed kick and all event effects.
const BallPhysics=preload("res://scripts/ball.gd")
const CONTACT_EPSILON:=0.00002
const MAX_EVENTS:=8
static func first(from:Vector3,to:Vector3,velocity:Vector3,radius:float)->Dictionary:
 var best:Dictionary={"hit":false,"fraction":2.0}
 var floor_y:float=BallPhysics.FLOOR_Y+radius
 if velocity.y<0.0 and from.y<=floor_y+1e-8:
  best={"hit":true,"fraction":0.0,"normal":Vector3.UP,"type":"floor"}
 elif to.y<floor_y and to.y<from.y:
  best={"hit":true,"fraction":clampf((from.y-floor_y)/(from.y-to.y),0,1),"normal":Vector3.UP,"type":"floor"}
 if from.y>=BallPhysics.FLIGHT_CEILING_Y and (velocity.y>0.0 or to.y>BallPhysics.FLIGHT_CEILING_Y):
  best={"hit":true,"fraction":0.0,"normal":Vector3.DOWN,"type":"ceiling"}
 elif to.y>BallPhysics.FLIGHT_CEILING_Y and to.y>from.y:
  var fraction:float=clampf((BallPhysics.FLIGHT_CEILING_Y-from.y)/(to.y-from.y),0,1)
  if fraction<float(best.fraction):best={"hit":true,"fraction":fraction,"normal":Vector3.DOWN,"type":"ceiling"}
 return best
static func response(kind:String,velocity:Vector3,omega:Vector3)->Array:
 if kind=="floor":
  var bounced:Array=BallPhysics.predict_bounce_spin(velocity,omega)
  return bounced
 var result:Vector3=velocity;result.y=minf(result.y,0.0)
 return [result,omega]
static func drift(position:Vector3,velocity:Vector3,omega:Vector3,seconds:float,radius:float=BallPhysics.BALL_RADIUS)->Dictionary:
 var remaining:float=maxf(seconds,0);var elapsed:=0.0;var events:=0;var segments:Array=[]
 while remaining>1e-10 and events<MAX_EVENTS:
  var endpoint:Vector3=position+velocity*remaining
  var collision:Dictionary=first(position,endpoint,velocity,radius)
  if not collision.hit:
   segments.append({"from":position,"to":endpoint,"time_from":elapsed,"time_to":seconds,"velocity":velocity,"omega":omega,"event":{}})
   position=endpoint;elapsed+=remaining;remaining=0.0;break
  var duration:float=remaining*float(collision.fraction)
  var point:Vector3=position.lerp(endpoint,float(collision.fraction))
  point.y=BallPhysics.FLOOR_Y+radius if collision.type=="floor" else BallPhysics.FLIGHT_CEILING_Y
  var outgoing:Array=response(collision.type,velocity,omega)
  if collision.type=="floor" and Vector3(outgoing[0]).y<.025:outgoing[0].y=0.0
  var event:Dictionary={"type":collision.type,"point":point,"time":elapsed+duration,"normal":collision.normal,"incoming":velocity,"outgoing":outgoing[0],"omega_before":omega,"omega_after":outgoing[1]}
  segments.append({"from":position,"to":point,"time_from":elapsed,"time_to":elapsed+duration,"velocity":velocity,"omega":omega,"event":event})
  elapsed+=duration;remaining=maxf(0.0,seconds-elapsed);events+=1
  position=point+Vector3(collision.normal)*CONTACT_EPSILON;velocity=outgoing[0];omega=outgoing[1]
 return {"position":position,"velocity":velocity,"omega":omega,"elapsed":elapsed,"remaining":remaining,"complete":remaining<=1e-10,"segments":segments}
