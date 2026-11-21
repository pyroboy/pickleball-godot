extends RefCounted
## Bounded algebraic CCD for the difficult, already-touching rotating manifold.
## Ball/triangle vertices follow the SAME linear sampled paths as History.
## Sphere contact lies on a vertex (quadratic), edge (quartic), or face
## (sextic). Isolate polynomial roots through derivative-monotone intervals.
## Only entry/tangent roots after the original contact remain candidates.
const Bounds=preload("res://scripts/contact_polynomial_bounds.gd")
const ROOT_EPS:=1e-9
const DISTANCE_EPS:=0.00002
static func first_entry(ball:Vector3,motion:Vector3,a:Vector3,b:Vector3,c:Vector3,
 da:Vector3,db:Vector3,dc:Vector3,radius:float,limit:float,feature_cache:Dictionary={},work_budget:int=2147483647,plane:Array=[])->Dictionary:
 if not is_finite(radius) or radius<0 or not is_finite(limit) or limit<0 or limit>1:return {"resolved":false,"hit":false,"reason":"nonfinite_or_invalid_interval"}
 for vector in [ball,motion,a,b,c,da,db,dc]:
  if not Vector3(vector).is_finite():return {"resolved":false,"hit":false,"reason":"nonfinite_triangle_path"}
 if limit<=ROOT_EPS:return {"resolved":true,"hit":false,"time":INF,"work_units":0}
 var triangle_proof:Dictionary=Bounds.triangle_departure(ball,motion,a,b,c,da,db,dc,limit)
 if triangle_proof.departing:return {"resolved":true,"hit":false,"time":INF,"work_units":0,"bound_controls":triangle_proof.controls,"triangle_departure":true}
 var bounded_polynomials:Array=Bounds.features(ball,motion,a,b,c,da,db,dc,radius)
 var polynomials:Array=[]
 for bounded in bounded_polynomials:polynomials.append(bounded.value)
 var earliest:=INF
 var work_units:=0
 var bound_controls:=0
 for feature_index in polynomials.size():
  var p:Array=polynomials[feature_index]
  for coefficient in p:
   if not is_finite(float(coefficient)):return {"resolved":false,"hit":false,"reason":"nonfinite_feature_polynomial"}
  var sign_proof:Dictionary=Bounds.strict_sign(bounded_polynomials[feature_index],limit)
  bound_controls+=int(sign_proof.controls)
  if int(sign_proof.sign)!=0:
   if feature_index==0 and int(sign_proof.sign)>0:return {"resolved":true,"hit":false,"time":INF,"work_units":work_units,"bound_controls":bound_controls,"plane_proof":true}
   continue
  # A strictly increasing feature polynomial has only EXIT roots. This
  # whole-interval proof is separate from finite-domain contact: every
  # other face/edge/vertex remains checked. Tangency and uncertain signs
  # always retain the original bounded root isolation below.
  var departure_proof:Dictionary=Bounds.strict_sign(Bounds.derivative(bounded_polynomials[feature_index]),limit)
  bound_controls+=int(departure_proof.controls)
  if int(departure_proof.sign)>0:continue
  var derivative:Array=_derivative(p)
  var scale:float=_scale(p)
  var key:=PackedFloat64Array(p);key.append(limit)
  var roots:Array
  if feature_cache.has(key):roots=feature_cache[key]
  else:
   var cost:int=p.size()-1
   if work_units+cost>work_budget:return {"resolved":false,"hit":false,"reason":"algebra_feature_budget","work_units":work_units,"bound_controls":bound_controls}
   roots=_roots(p,0.0,limit);feature_cache[key]=roots;work_units+=cost
  for root_value in roots:
   var t:float=root_value
   if t<=ROOT_EPS or t>=earliest:continue
   # Positive slope leaves the surface. A later zero/negative slope is
   # tangent/entering and must not inherit the old manifold's exemption.
   if _value(derivative,t)>scale*1e-8:continue
   var finite:Dictionary=Bounds.finite_root(feature_index,ball,motion,a,b,c,da,db,dc,radius,t)
   if not finite.resolved:return {"resolved":false,"hit":false,"reason":finite.reason,"work_units":work_units,"bound_controls":bound_controls}
   if not finite.valid:continue
   earliest=t
 return {"resolved":true,"hit":is_finite(earliest),"time":earliest,"work_units":work_units,"bound_controls":bound_controls}
static func _dot_poly(a:Array,b:Array)->Array:
 var result:Array=[];result.resize(a.size()+b.size()-1);result.fill(0.0)
 for i in a.size():
  for j in b.size():
   var x:Vector3=a[i];var y:Vector3=b[j]
   result[i+j]+=float(x.x)*float(y.x)+float(x.y)*float(y.y)+float(x.z)*float(y.z)
 return result
static func _mul(a:Array,b:Array)->Array:
 var result:Array=[];result.resize(a.size()+b.size()-1);result.fill(0.0)
 for i in a.size():
  for j in b.size():result[i+j]+=float(a[i])*float(b[j])
 return result
static func _add(a:Array,b:Array,factor:float=1.0)->Array:
 var result:Array=a.duplicate();result.resize(maxi(a.size(),b.size()))
 for i in result.size():
  if i>=a.size():result[i]=0.0
  if i<b.size():result[i]+=float(b[i])*factor
 return result
static func _derivative(p:Array)->Array:
 var result:Array=[]
 for i in range(1,p.size()):result.append(float(p[i])*i)
 return result
static func _value(p:Array,t:float)->float:
 var result:=0.0
 for i in range(p.size()-1,-1,-1):result=result*t+float(p[i])
 return result
static func _scale(p:Array)->float:
 var scale:=0.0
 for coefficient in p:scale=maxf(scale,absf(float(coefficient)))
 return maxf(scale,1e-20)
static func _roots(coefficients:Array,low:float,high:float)->Array:
 var p:Array=coefficients.duplicate()
 var tolerance:float=_scale(p)*1e-12
 while p.size()>1 and absf(float(p[-1]))<=tolerance:p.pop_back()
 if p.size()<=1:return []
 if p.size()==2:
  var t:float=-float(p[0])/float(p[1])
  return [clampf(t,low,high)] if t>=low-ROOT_EPS and t<=high+ROOT_EPS else []
 var critical:Array=_roots(_derivative(p),low,high)
 var bounds:Array=[low];bounds.append_array(critical);bounds.append(high);bounds.sort()
 var roots:Array=[]
 for t in bounds:
  if absf(_value(p,float(t)))<=tolerance:roots.append(float(t))
 for i in range(bounds.size()-1):
  var left:float=bounds[i];var right:float=bounds[i+1]
  var value_left:float=_value(p,left);var value_right:float=_value(p,right)
  if value_left*value_right>=0.0:continue
  for iteration in 40:
   var middle:float=(left+right)*.5;var value_middle:float=_value(p,middle)
   if value_left*value_middle<=0.0:right=middle
   else:left=middle;value_left=value_middle
  roots.append((left+right)*.5)
 roots.sort()
 var distinct:Array=[]
 for t in roots:
  if distinct.is_empty() or absf(float(t)-float(distinct[-1]))>ROOT_EPS:distinct.append(float(t))
 return distinct
