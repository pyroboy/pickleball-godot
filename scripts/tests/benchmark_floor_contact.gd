extends SceneTree
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
class IncomingBall extends RefCounted:
 var is_in_play=true
 var last_hit_by=1
 var bounces_since_last_hit=1
 var both_bounces_complete=true
 var global_position=Vector3.ZERO
 var linear_velocity=Vector3.ZERO
func _initialize():call_deferred("run")
func run():
 var p=Side.new(0);p.global_position=Vector3(0,1,3.2);p.global_transform.origin=p.global_position
 var ball=IncomingBall.new()
 var output={}
 for kind in ["normal","distant","low","low_miss"]:
  var corpus=[]
  for lane in [-.65,-.42,0,.42,.82]:
   var y=1.05 if kind=="normal" else .65 if kind=="distant" else .17
   var z=1.5 if kind in ["normal","distant"] else 2.0
   var x=lane+(3.5 if kind in ["distant","low_miss"] else 0.0)
   var pos=Vector3(x,y,z);var vel=Vector3(0,.4,5)
   corpus.append({"pos":pos,"vel":vel,"flight":Flight.trace(pos,vel,Vector3.ZERO)})
  var times=[];var plans=0
  for rep in range(90):
   var start=Time.get_ticks_usec()
   for item in corpus:
    ball.global_position=item.pos;ball.linear_velocity=item.vel
    var result=Planner.select(p,ball,item.flight)
    if not result.is_empty():plans+=1
   if rep>=10:times.append(float(Time.get_ticks_usec()-start)/corpus.size())
  times.sort()
  output[kind]={"p50_us":times[40],"p95_us":times[76],"worst_us":times[-1],"plans":plans}
 print("FLOOR PLANNER BENCH ",JSON.stringify(output))
 quit()
