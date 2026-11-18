extends RefCounted
## Geometric evidence only. Rule12.C catch/carry is NOT classified by duration,
## by this numerical contact model, or by Rule10.D stroke permission.
const Face=preload("res://scripts/finite_face_manifold.gd")
const Geometry=preload("res://scripts/contact_surface_geometry.gd")
static func initial()->Dictionary:
 return {"rule_12c":"UNCLASSIFIED", "intervals":0,"supported_seconds":0.0,"ball_path_metres":0.0,"material_slip_metres":0.0,"surface_transport_metres":0.0,"max_gap_metres":0.0,"release_reason":"","unproven_intervals":0}
static func observe(state:Dictionary,face:Dictionary,from:Vector3,to:Vector3,start:float,end:float,seconds:float,radius:float,release_reason:String="")->Dictionary:
 var result:Dictionary=state.duplicate(true) if not state.is_empty() else initial()
 var proof:Dictionary=Face.qualify_interval(face,from,to,start,end,radius)
 if not proof.qualified:
  result.unproven_intervals+=1;return result
 return _measure(result,face,from,to,start,end,seconds,radius,release_reason)
static var verify_reuse:=false
static var reuse_count:=0
static var fallback_count:=0
static var reuse_comparison_failures:Array=[]
static func observe_step(state:Dictionary,face:Dictionary,step:Dictionary,start:float,seconds:float,radius:float)->Dictionary:
 var release_reason:String=step.reason if step.released else ""
 var certificate:Dictionary=Face.accepted_support_certificate(int(step.get("support_certificate_id",-1)),face,step.from,step.position,start,step.time,seconds,radius)
 if certificate.is_empty():
  fallback_count+=1
  return observe(state,face,step.from,step.position,start,step.time,seconds,radius,release_reason)
 reuse_count+=1
 var result:Dictionary=state.duplicate(true) if not state.is_empty() else initial()
 result=_measure(result,face,step.from,step.position,start,step.time,seconds,radius,release_reason)
 if verify_reuse:
  var original:Dictionary=observe(state,face,step.from,step.position,start,step.time,seconds,radius,release_reason)
  if original!=result:
   reuse_comparison_failures.append({"expected":original,"actual":result,"certificate_id":step.support_certificate_id})
   push_error("Accepted support certificate differs from full recomputation")
 return result
static func _measure(result:Dictionary,face:Dictionary,from:Vector3,to:Vector3,start:float,end:float,seconds:float,radius:float,release_reason:String)->Dictionary:
 var f0:Dictionary=Face.frame_at(face,start,seconds);var f1:Dictionary=Face.frame_at(face,end,seconds)
 if not f0.valid or not f1.valid:result.unproven_intervals+=1;return result
 var surface0:Vector3=from-Vector3(f0.n)*radius;var surface1:Vector3=to-Vector3(f1.n)*radius
 var b0:Vector3=face.b+face.db*start;var c0:Vector3=face.c+face.dc*start
 var b1:Vector3=face.b+face.db*end;var c1:Vector3=face.c+face.dc*end
 var w0:Vector3=Geometry.barycentric(surface0,f0.a,b0,c0)
 var w1:Vector3=Geometry.barycentric(surface1,f1.a,b1,c1)
 var transported:Vector3=Vector3(f1.a)*w0.x+b1*w0.y+c1*w0.z
 result.intervals+=1
 result.supported_seconds+=(end-start)*seconds
 result.ball_path_metres+=from.distance_to(to)
 result.material_slip_metres+=transported.distance_to(surface1)
 result.surface_transport_metres+=surface0.distance_to(transported)
 result.max_gap_metres=maxf(float(result.max_gap_metres),maxf(absf((from-Vector3(f0.a)).dot(f0.n)-radius),absf((to-Vector3(f1.a)).dot(f1.n)-radius)))
 if release_reason!="":result.release_reason=release_reason
 # Keep raw physical quantities. No invented duration/slip threshold is a
 # legal catch/carry test, and no successful constraint step certifies a shot.
 return result
