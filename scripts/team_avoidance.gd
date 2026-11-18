extends RefCounted
## Bounded ground steering from visible teammate estimates. Never moves a node.
const HORIZON := 0.45
const DEFAULT_RADIUS := 0.68
const ANGLES := 24
static func closest_distance(relative_position: Vector3, relative_velocity: Vector3, seconds: float) -> float:
 relative_position.y=0.0;relative_velocity.y=0.0
 var time:float=clampf(-relative_position.dot(relative_velocity)/relative_velocity.length_squared(),0.0,seconds) if relative_velocity.length_squared()>.000001 else 0.0
 return (relative_position+relative_velocity*time).length()
static func steer(position: Vector3, current: Vector3, desired: Vector3, partners: Array, delta: float, max_speed: float=5.8, acceleration: float=16.0, radius: float=DEFAULT_RADIUS) -> Dictionary:
 if not position.is_finite() or not current.is_finite() or not desired.is_finite() or not is_finite(delta) or delta<=0.0:return {"velocity":Vector3.ZERO,"safe":false,"reason":"invalid steering input"}
 current.y=0.0;desired.y=0.0;desired=desired.limit_length(max_speed)
 var step:float=maxf(acceleration,0.0)*delta
 var candidates:Array[Vector3]=[current.move_toward(desired,step),current.move_toward(Vector3.ZERO,step)]
 for i in ANGLES:
  var direction:=Vector3(cos(TAU*float(i)/ANGLES),0,sin(TAU*float(i)/ANGLES))
  for ratio in [.35,.7,1.0]:candidates.append(current.move_toward(direction*max_speed*ratio,step).limit_length(max_speed))
 var best:=Vector3.ZERO;var best_cost:=INF;var best_margin:=-INF;var any_safe:=false
 for candidate in candidates:
  var margin:=INF
  for partner:Dictionary in partners:
   var other_position:Vector3=partner.get("root",Vector3.INF);var other_velocity:Vector3=partner.get("velocity",Vector3.ZERO)
   if not other_position.is_finite() or not other_velocity.is_finite():return {"velocity":current.move_toward(Vector3.ZERO,step),"safe":false,"reason":"invalid teammate observation"}
   var combined:float=radius+float(partner.get("radius",DEFAULT_RADIUS))
   margin=minf(margin,closest_distance(position-other_position,candidate-other_velocity,maxf(HORIZON,delta))-combined)
  var safe:bool=margin>=-.000001
  var cost:float=candidate.distance_squared_to(desired)+candidate.length_squared()*.002
  if safe and (not any_safe or cost<best_cost) or not safe and not any_safe and (margin>best_margin+.000001 or absf(margin-best_margin)<=.000001 and cost<best_cost):
   best=candidate;best_cost=cost;best_margin=margin;any_safe=safe
 return {"velocity":best,"safe":any_safe,"reason":"separated predicted ground path" if any_safe else "no acceleration-bounded separated step","margin":best_margin,"candidates":candidates.size(),"horizon":maxf(HORIZON,delta)}
