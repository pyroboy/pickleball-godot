extends RefCounted
## Degree <=6 feature polynomials in double components, with absolute-term
## majorants. Strict Bernstein signs certify no zero over the whole interval.
## Gamma512 exceeds the arithmetic dependency depth (under 128 operations).
static var _binomial:Dictionary={}
const GAMMA := 5.684341886081125e-14
const CONVERSION_GAMMA := 1.4210854715202206e-14
static func vector(v:Vector3)->Array:return [float(v.x),float(v.y),float(v.z)]
static func subtract(a:Array,b:Array)->Array:return [float(a[0])-float(b[0]),float(a[1])-float(b[1]),float(a[2])-float(b[2])]
static func absolute(a:Array)->Array:return [absf(a[0]),absf(a[1]),absf(a[2])]
static func cross(a:Array,b:Array)->Array:return [float(a[1])*float(b[2])-float(a[2])*float(b[1]),float(a[2])*float(b[0])-float(a[0])*float(b[2]),float(a[0])*float(b[1])-float(a[1])*float(b[0])]
static func cross_magnitude(a:Array,b:Array)->Array:return [absf(a[1]*b[2])+absf(a[2]*b[1]),absf(a[2]*b[0])+absf(a[0]*b[2]),absf(a[0]*b[1])+absf(a[1]*b[0])]
static func plus_vector(a:Array,b:Array)->Array:return [a[0]+b[0],a[1]+b[1],a[2]+b[2]]
static func dot_polynomial(a:Array,b:Array,am:Array=[],bm:Array=[])->Dictionary:
 var v:Array=[];var m:Array=[];v.resize(a.size()+b.size()-1);m.resize(v.size());v.fill(0.0);m.fill(0.0)
 for i in a.size():
  for j in b.size():
   for axis in 3:
    v[i+j]+=float(a[i][axis])*float(b[j][axis])
    m[i+j]+=(absf(a[i][axis]) if am.is_empty() else float(am[i][axis]))*(absf(b[j][axis]) if bm.is_empty() else float(bm[j][axis]))
 return {"value":v,"magnitude":m}
static func multiply(a:Dictionary,b:Dictionary)->Dictionary:
 var v:Array=[];var m:Array=[];v.resize(a.value.size()+b.value.size()-1);m.resize(v.size());v.fill(0.0);m.fill(0.0)
 for i in a.value.size():
  for j in b.value.size():
   v[i+j]+=float(a.value[i])*float(b.value[j]);m[i+j]+=float(a.magnitude[i])*float(b.magnitude[j])
 return {"value":v,"magnitude":m}
static func add(a:Dictionary,b:Dictionary,factor:float=1.0)->Dictionary:
 var v:Array=a.value.duplicate();var m:Array=a.magnitude.duplicate();v.resize(maxi(v.size(),b.value.size()));m.resize(v.size())
 for i in v.size():
  if i>=a.value.size():v[i]=0.0;m[i]=0.0
  if i<b.value.size():v[i]+=float(b.value[i])*factor;m[i]+=float(b.magnitude[i])*absf(factor)
 return {"value":v,"magnitude":m}
static func subtract_radius(p:Dictionary,radius:float)->Dictionary:
 p.value[0]-=radius*radius;p.magnitude[0]+=radius*radius;return p
static func features(ball:Vector3,motion:Vector3,a:Vector3,b:Vector3,c:Vector3,da:Vector3,db:Vector3,dc:Vector3,radius:float,plane:Array=[])->Array:
 var bv:Array=vector(ball);var mv:Array=vector(motion)
 var positions:Array=[vector(a),vector(b),vector(c)];var displacements:Array=[vector(da),vector(db),vector(dc)]
 var vertices:Array=[]
 for i in 3:vertices.append([subtract(positions[i],bv),subtract(displacements[i],mv)])
 var result:Array=[]
 for vertex in vertices:result.append(subtract_radius(dot_polynomial(vertex,vertex),radius))
 for edge in [[0,1],[1,2],[2,0]]:
  var first:int=edge[0];var last:int=edge[1]
  if _less(vertices[last],vertices[first]):var swap:int=first;first=last;last=swap
  var w:Array=vertices[first]
  # Compute each difference directly from original sampled components.
  var e:Array=[subtract(positions[last],positions[first]),subtract(displacements[last],displacements[first])]
  var ww:Dictionary=subtract_radius(dot_polynomial(w,w),radius);var we:Dictionary=dot_polynomial(w,e)
  result.append(add(multiply(ww,dot_polynomial(e,e)),multiply(we,we),-1.0))
 var pp:Array=[a,b,c,da,db,dc] if plane.size()!=6 else plane
 var pa:Array=vector(pp[0]);var pb:Array=vector(pp[1]);var pc:Array=vector(pp[2]);var pda:Array=vector(pp[3]);var pdb:Array=vector(pp[4]);var pdc:Array=vector(pp[5])
 var u:Array=[subtract(pb,pa),subtract(pdb,pda)];var v:Array=[subtract(pc,pa),subtract(pdc,pda)]
 var n:Array=[cross(u[0],v[0]),plus_vector(cross(u[0],v[1]),cross(u[1],v[0])),cross(u[1],v[1])]
 var nm:Array=[cross_magnitude(u[0],v[0]),plus_vector(cross_magnitude(u[0],v[1]),cross_magnitude(u[1],v[0])),cross_magnitude(u[1],v[1])]
 var w:Array=[subtract(pa,bv),subtract(pda,mv)]
 var wn:Dictionary=dot_polynomial(w,n,[],nm)
 result.push_front(add(multiply(wn,wn),dot_polynomial(n,n,nm,nm),-radius*radius))
 return result
static func _less(a:Array,b:Array)->bool:
 for vector_index in 2:
  for axis in 3:
   if a[vector_index][axis]!=b[vector_index][axis]:return a[vector_index][axis]<b[vector_index][axis]
 return false
static func _choose(n:int,k:int)->float:
 var key:Vector2i=Vector2i(n,k)
 if _binomial.has(key):return _binomial[key]
 var value:=1.0
 for i in range(1,k+1):value*=float(n-i+1)/float(i)
 _binomial[key]=value
 return value
static func strict_sign(p:Dictionary,limit:float)->Dictionary:
 var degree:int=p.value.size()-1
 var positive:=true;var negative:=true;var smallest:=INF
 var powers:Array=[]
 for i in range(degree+1):powers.append(pow(limit,i))
 if degree<0 or degree>6 or not is_finite(limit) or limit<0.0:return {"sign":0,"controls":0}
 for k in range(degree+1):
  var value:=0.0;var magnitude:=0.0;var absolute_sum:=0.0
  for i in range(k+1):
   var factor:float=float(powers[i])*_choose(k,i)/_choose(degree,i)
   var term:float=float(p.value[i])*factor
   value+=term;absolute_sum+=absf(term);magnitude+=float(p.magnitude[i])*absf(factor)
  var error:float=GAMMA*magnitude+CONVERSION_GAMMA*absolute_sum
  if not is_finite(value) or not is_finite(error):return {"sign":0,"controls":k+1}
  # Avoid a subnormal/underflow claim. Zero remains uncertain.
  if absf(value)<1e-280:positive=false;negative=false
  positive=positive and value>error;negative=negative and value < -error
  smallest=minf(smallest,absf(value)-error)
 return {"sign":1 if positive else (-1 if negative else 0),"controls":degree+1,"margin_lower":smallest}

static func _dot_vector(a:Array,b:Array)->float:
 return float(a[0])*float(b[0])+float(a[1])*float(b[1])+float(a[2])*float(b[2])
static func _at(a:Vector3,da:Vector3,t:float)->Array:
 return [float(a.x)+float(da.x)*t,float(a.y)+float(da.y)*t,float(a.z)+float(da.z)*t]
static func finite_root(feature:int,ball:Vector3,motion:Vector3,a:Vector3,b:Vector3,c:Vector3,da:Vector3,db:Vector3,dc:Vector3,radius:float,t:float)->Dictionary:
 var q:Array=_at(ball,motion,t)
 var vertices:Array=[_at(a,da,t),_at(b,db,t),_at(c,dc,t)]
 var distance:=INF
 var coordinate_sum:=0.0
 for point in [q,vertices[0],vertices[1],vertices[2]]:
  for value in point:coordinate_sum+=absf(value)
 var arithmetic_error:float=GAMMA*maxf(coordinate_sum,radius)
 if feature==0:
  var u:Array=subtract(vertices[1],vertices[0]);var v:Array=subtract(vertices[2],vertices[0]);var w:Array=subtract(q,vertices[0])
  var n:Array=cross(u,v);var nn:float=_dot_vector(n,n)
  if nn==0.0:return {"valid":false,"resolved":true,"reason":"collapsed_face_has_no_plane"}
  var normal_length:float=sqrt(nn)
  var magnitude:Array=cross_magnitude(u,v)
  var condition:float=sqrt(_dot_vector(magnitude,magnitude))/normal_length
  arithmetic_error*=1.0+condition
  if not is_finite(arithmetic_error) or arithmetic_error>0.00002:return {"valid":false,"resolved":false,"reason":"ill_conditioned_face_root"}
  var first:float=_dot_vector(cross(w,v),n)/nn
  var second:float=_dot_vector(cross(u,w),n)/nn
  if first<0.0 or second<0.0 or first+second>1.0:return {"valid":false,"resolved":true,"reason":"outside_finite_face"}
  distance=absf(_dot_vector(w,n))/normal_length
 elif feature>=4:
  var pair:Array=[[0,1],[1,2],[2,0]][feature-4]
  var start:Array=vertices[pair[0]];var edge:Array=subtract(vertices[pair[1]],start)
  var ee:float=_dot_vector(edge,edge)
  if ee==0.0:return {"valid":false,"resolved":true,"reason":"collapsed_edge_has_no_line"}
  var parameter:float=_dot_vector(subtract(q,start),edge)/ee
  if parameter<0.0 or parameter>1.0:return {"valid":false,"resolved":true,"reason":"outside_finite_edge"}
  var nearest:Array=[start[0]+edge[0]*parameter,start[1]+edge[1]*parameter,start[2]+edge[2]*parameter]
  var relative:Array=subtract(q,nearest);distance=sqrt(_dot_vector(relative,relative))
 else:
  var relative:Array=subtract(q,vertices[feature-1]);distance=sqrt(_dot_vector(relative,relative))
 # Root isolation bisects at most unit intervals40 times. ROOT_EPS1e-9
 # also covers critical-root deduplication. Distance to a finite moving
 # convex feature is Lipschitz in ball and vertex displacement, including
 # collapsed edges; no radius expansion is used for feature membership.
 var time_error:float=(motion.length()+maxf(da.length(),maxf(db.length(),dc.length())))*1e-9
 var error:float=arithmetic_error+time_error
 if not is_finite(distance):return {"valid":false,"resolved":false,"reason":"nonfinite_finite_feature"}
 return {"valid":absf(distance-radius)<=error,"resolved":true,"distance":distance,"distance_error_bound":error}

static func derivative(p:Dictionary)->Dictionary:
 ## Coefficients and absolute-term majorants get the SAME integer scale.
 ## This adds one multiplication within the existing conservative Gamma512
 ## arithmetic bound; no cancellation or zero threshold is introduced.
 var values:Array=[];var magnitudes:Array=[]
 for i in range(1,p.value.size()):
  values.append(float(p.value[i])*i);magnitudes.append(float(p.magnitude[i])*i)
 return {"value":values,"magnitude":magnitudes}

static func triangle_departure(ball:Vector3,motion:Vector3,a:Vector3,b:Vector3,c:Vector3,da:Vector3,db:Vector3,dc:Vector3,limit:float)->Dictionary:
 ## Quadratic simplex Bernstein controls of d/dt |p(w)+t*d(w)|^2.
 ## Every fixed material point strictly recedes if ALL controls are positive
 ## at BOTH time endpoints. Taking the minimum over the fixed simplex then
 ## preserves that uniform increase, so finite edge changes cannot re-enter.
 if not is_finite(limit) or limit<0.0 or limit>1.0:return {"departing":false,"controls":0}
 var bv:Array=vector(ball);var mv:Array=vector(motion)
 var ps:Array=[subtract(vector(a),bv),subtract(vector(b),bv),subtract(vector(c),bv)]
 var ds:Array=[subtract(vector(da),mv),subtract(vector(db),mv),subtract(vector(dc),mv)]
 var count:=0;var lower:=INF
 for i in 3:
  for j in range(i,3):
   var initial:=0.0;var initial_magnitude:=0.0;var change:=0.0;var change_magnitude:=0.0
   for axis in 3:
    var left:float=ps[i][axis]*ds[j][axis];var right:float=ps[j][axis]*ds[i][axis]
    var speed:float=2.0*ds[i][axis]*ds[j][axis]
    initial+=left+right;initial_magnitude+=absf(left)+absf(right)
    change+=speed;change_magnitude+=absf(speed)
   for t in [0.0,limit]:
    count+=1
    var value:float=initial+float(t)*change
    var error:float=GAMMA*(initial_magnitude+absf(t)*change_magnitude)+CONVERSION_GAMMA*(absf(initial)+absf(float(t)*change))
    if not is_finite(value) or not is_finite(error) or absf(value)<1e-280 or value<=error:return {"departing":false,"controls":count}
    lower=minf(lower,value-error)
 return {"departing":true,"controls":count,"derivative_lower":lower}
