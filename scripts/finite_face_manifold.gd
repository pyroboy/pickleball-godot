extends RefCounted
## Frictionless nonadhesive constraint on one actual finite affine mesh face.
## A physical response/legality owner must qualify entry; this helper awards nothing.
const Surface=preload("res://scripts/player_surface_contacts.gd")
const Poly=preload("res://scripts/moving_triangle_reentry.gd")
const SLOP:=0.00002
const MAX_CHORD_ERROR:=0.000005
const MAX_POSITION_ERROR:=0.000001
const MAX_VELOCITY_ERROR:=0.0002
const MAX_STEPS:=256
const MAX_REFINEMENTS:=18
static var _faces:Dictionary={}
static var _support_certificates:Dictionary={}
static var _support_sequence:=0

static func topology(mesh:Mesh,offset:int)->Dictionary:
 var sources:PackedInt32Array=Surface.rigid_planar_face_sources(mesh)
 if offset<0 or offset/3>=sources.size() or sources[offset/3]<0:return {}
 var source:int=sources[offset/3]
 var key:Array=[mesh,Surface.mesh_geometry_key(mesh),source]
 if _faces.has(key):return _faces[key]
 var vertices:PackedVector3Array=Surface.posed_triangles(mesh,Transform3D.IDENTITY,[])
 var offsets:=PackedInt32Array();var edges:Dictionary={};var points:Dictionary={}
 for i in range(0,vertices.size()-2,3):
  if sources[i/3]!=source:continue
  offsets.append(i)
  for j in 3:
   var a:Vector3=vertices[i+j];var b:Vector3=vertices[i+(j+1)%3]
   points[a]=i+j
   var pair:Array=[a,b];if _less(b,a):pair=[b,a]
   if not edges.has(pair):edges[pair]=0
   edges[pair]+=1
 var links:Dictionary={}
 for edge in edges:
  if edges[edge]>2:_faces[key]={};return {}
  if edges[edge]==1:
   for k in 2:
    if not links.has(edge[k]):links[edge[k]]=[]
    links[edge[k]].append(edge[1-k])
 if links.size()<3:_faces[key]={};return {}
 for point in links:
  if links[point].size()!=2:_faces[key]={};return {}
 var first:Vector3=links.keys()[0];var last:=Vector3.INF;var current:Vector3=first
 var polygon:=PackedInt32Array()
 for ignored in links.size():
  polygon.append(int(points[current]))
  var next:Vector3=links[current][0] if links[current][0]!=last else links[current][1]
  last=current;current=next
  if current==first:break
 if polygon.size()!=links.size() or current!=first:_faces[key]={};return {}
 var normal:Vector3=(vertices[source+1]-vertices[source]).cross(vertices[source+2]-vertices[source]).normalized()
 var turn:=0.0
 for i in polygon.size():
  var a:Vector3=vertices[polygon[i]];var b:Vector3=vertices[polygon[(i+1)%polygon.size()]];var c:Vector3=vertices[polygon[(i+2)%polygon.size()]]
  var value:float=(b-a).cross(c-b).dot(normal)
  if absf(value)<1e-10:continue
  if turn!=0.0 and value*turn<0.0:_faces[key]={};return {}
  turn=value
 if turn==0.0:_faces[key]={};return {}
 if turn<0.0:polygon.reverse()
 var sum_area:=0.0;var hull_area:=0.0
 for i in offsets:
  sum_area+=absf((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).dot(normal))
 for i in polygon.size():hull_area+=vertices[polygon[i]].cross(vertices[polygon[(i+1)%polygon.size()]]).dot(normal)
 if absf(sum_area-absf(hull_area))>1e-7:_faces[key]={};return {}
 var result:Dictionary={"source":source,"offsets":offsets,"polygon":polygon}
 _faces[key]=result;return result

static func _less(a:Vector3,b:Vector3)->bool:
 if a.x!=b.x:return a.x<b.x
 if a.y!=b.y:return a.y<b.y
 return a.z<b.z

static func from_parts(previous:Dictionary,current:Dictionary,offset:int,normal:Vector3)->Dictionary:
 if not current.get("equipment",false) or not previous.get("equipment",false) or not current.palette.is_empty() or not previous.palette.is_empty() or current.mesh!=previous.mesh:return {}
 # A changed source cannot reuse the old rigid face or silently rewrite its history.
 var live_key:Array=Surface.mesh_geometry_key(current.mesh)
 var before_key:Array=previous.get("mesh_key",live_key)
 var current_key:Array=current.get("mesh_key",live_key)
 if before_key!=current_key or current_key!=live_key:return {}
 var shape:Dictionary=topology(current.mesh,offset)
 if shape.is_empty():return {}
 var old:PackedVector3Array=Surface.snapshot_triangles(previous);var now:PackedVector3Array=Surface.snapshot_triangles(current)
 if old.size()!=now.size():return {}
 var source:int=shape.source
 var face:Dictionary={"a":old[source],"b":old[source+1],"c":old[source+2],"da":now[source]-old[source],"db":now[source+1]-old[source+1],"dc":now[source+2]-old[source+2],"polygon":PackedVector3Array(),"motion":PackedVector3Array(),"offsets":shape.offsets,"source":source,"orientation":1.0}
 for index in shape.polygon:
  face.polygon.append(old[index]);face.motion.append(now[index]-old[index])
 var frame:Dictionary=frame_at(face,0.0,1.0)
 if not frame.valid:return {}
 if Vector3(frame.n).dot(normal)<0.0:face.orientation=-1.0
 return face

static func frame_at(face:Dictionary,t:float,seconds:float)->Dictionary:
 if seconds<=0.0:return {"valid":false}
 var a:Vector3=face.a+face.da*t;var u:Vector3=face.b-face.a+(face.db-face.da)*t;var v:Vector3=face.c-face.a+(face.dc-face.da)*t
 var du:Vector3=face.db-face.da;var dv:Vector3=face.dc-face.da
 var cross:Vector3=u.cross(v);var length:float=cross.length()
 if length<1e-10 or not is_finite(length):return {"valid":false}
 var orientation:float=face.get("orientation",1.0)
 var n:Vector3=cross/length
 var first:Vector3=du.cross(v)+u.cross(dv);var second:Vector3=2.0*du.cross(dv)
 var dl:float=n.dot(first);var dn:Vector3=(first-n*dl)/length
 var ddl:float=(first.dot(first)+cross.dot(second)-dl*dl)/length
 var ddn:Vector3=(second-n*ddl-2.0*dn*dl)/length
 var dddl:float=(3.0*first.dot(second)-3.0*dl*ddl)/length
 var dddn:Vector3=(-3.0*ddn*dl-3.0*dn*ddl-n*dddl)/length
 return {"valid":true,"a":a,"av":Vector3(face.da)/seconds,"n":n*orientation,"dn":dn*orientation/seconds,"ddn":ddn*orientation/(seconds*seconds),"dddn":dddn*orientation/(seconds*seconds*seconds),"length":length}

static func finite_margin(face:Dictionary,point:Vector3,t:float)->float:
 var f:Dictionary=frame_at(face,t,1.0)
 if not f.valid:return -INF
 # Polygon winding is tied to original triangle normal, not chosen ball side.
 var n:Vector3=Vector3(f.n)*float(face.get("orientation",1.0));var margin:=INF
 for i in face.polygon.size():
  var a:Vector3=face.polygon[i]+face.motion[i]*t;var j:int=(i+1)%face.polygon.size();var b:Vector3=face.polygon[j]+face.motion[j]*t
  var edge:Vector3=b-a
  if edge.length()<1e-10:return -INF
  margin=minf(margin,(point-a).dot(n.cross(edge).normalized()))
 return margin

static func qualify_interval(face:Dictionary,from:Vector3,to:Vector3,start:float,end:float,radius:float)->Dictionary:
 ## Whole-interval polynomial certificate, not a midpoint/gap sample.
 if not from.is_finite() or not to.is_finite() or not is_finite(start) or not is_finite(end) or not is_finite(radius) or radius<=0 or start<0 or end<start or end>1:return {"qualified":false,"reason":"invalid_interval"}
 var a:Vector3=face.a+face.da*start;var da:Vector3=face.da*(end-start)
 var u:Array=[Vector3(face.b-face.a)+(face.db-face.da)*start,Vector3(face.db-face.da)*(end-start)]
 var v:Array=[Vector3(face.c-face.a)+(face.dc-face.da)*start,Vector3(face.dc-face.da)*(end-start)]
 var n:Array=[Vector3(u[0]).cross(v[0]),Vector3(u[0]).cross(v[1])+Vector3(u[1]).cross(v[0]),Vector3(u[1]).cross(v[1])]
 var s:Array=Poly._dot_poly([from-a,to-from-da],n)
 for i in s.size():s[i]*=float(face.get("orientation",1.0))
 if _extreme(s,false)<-1e-12:return {"qualified":false,"reason":"opposite_face_side"}
 var norm:Array=Poly._dot_poly(n,n)
 if _extreme(norm,false)<1e-18:return {"qualified":false,"reason":"collapsed_face"}
 var penetration:Array=Poly._add(Poly._mul(s,s),norm,-maxf(0.0,radius-SLOP)*maxf(0.0,radius-SLOP))
 if _extreme(penetration,false)<-maxf(Poly._scale(penetration)*1e-10,1e-18):return {"qualified":false,"reason":"penetration_exceeds_contact_slop"}
 var gap:Array=Poly._add(Poly._mul(s,s),norm,-(radius+SLOP)*(radius+SLOP))
 if _extreme(gap,true)>maxf(Poly._scale(gap)*1e-10,1e-18):return {"qualified":false,"reason":"proven_separation_exceeds_slop"}
 for i in face.polygon.size():
  var j:int=(i+1)%face.polygon.size()
  var p:Array=[Vector3(face.polygon[i])+Vector3(face.motion[i])*start,Vector3(face.motion[i])*(end-start)]
  var e:Array=[Vector3(face.polygon[j])-Vector3(face.polygon[i])+(Vector3(face.motion[j])-Vector3(face.motion[i]))*start,(Vector3(face.motion[j])-Vector3(face.motion[i]))*(end-start)]
  var nx:Array=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
  for ni in n.size():
   for ei in e.size():nx[ni+ei]+=Vector3(n[ni]).cross(e[ei])
  var inside:Array=Poly._dot_poly([from-Vector3(p[0]),to-from-Vector3(p[1])],nx)
  if _extreme(inside,false)<-maxf(Poly._scale(inside)*1e-9,1e-15):return {"qualified":false,"reason":"finite_face_exit"}
 return {"qualified":true,"reason":"same_finite_face_within_contact_slop","max_gap_bound":SLOP}


static func finite_interval_margin(face:Dictionary,from:Vector3,to:Vector3,start:float,end:float,exclude_edge:int=-1)->float:
 var u:Array=[Vector3(face.b-face.a)+(face.db-face.da)*start,Vector3(face.db-face.da)*(end-start)]
 var v:Array=[Vector3(face.c-face.a)+(face.dc-face.da)*start,Vector3(face.dc-face.da)*(end-start)]
 var n:Array=[Vector3(u[0]).cross(v[0]),Vector3(u[0]).cross(v[1])+Vector3(u[1]).cross(v[0]),Vector3(u[1]).cross(v[1])]
 var margin:=INF
 for i in face.polygon.size():
  if i==exclude_edge:continue
  var j:int=(i+1)%face.polygon.size()
  var p:Array=[Vector3(face.polygon[i])+Vector3(face.motion[i])*start,Vector3(face.motion[i])*(end-start)]
  var e:Array=[Vector3(face.polygon[j])-Vector3(face.polygon[i])+(Vector3(face.motion[j])-Vector3(face.motion[i]))*start,(Vector3(face.motion[j])-Vector3(face.motion[i]))*(end-start)]
  var nx:Array=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
  for ni in n.size():
   for ei in e.size():nx[ni+ei]+=Vector3(n[ni]).cross(e[ei])
  var scalar:Array=Poly._dot_poly([from-Vector3(p[0]),to-from-Vector3(p[1])],nx)
  var norm_bound:=0.0
  for vector in nx:norm_bound+=Vector3(vector).length()
  if norm_bound<1e-18:return -INF
  var value:float=_extreme(scalar,false)
  if value<0.0:return value/norm_bound
  margin=minf(margin,value/norm_bound)
 return margin

static func _extreme(p:Array,maximum:bool)->float:
 var candidates:Array=[0.0,1.0];candidates.append_array(Poly._roots(Poly._derivative(p),0.0,1.0))
 var result:float=-INF if maximum else INF
 for t in candidates:
  var value:float=Poly._value(p,float(t));result=maxf(result,value) if maximum else minf(result,value)
 return result

static func _acceleration(face:Dictionary,q:Vector3,velocity:Vector3,t:float,seconds:float)->Dictionary:
 var f:Dictionary=frame_at(face,t,seconds)
 if not f.valid:return {"valid":false}
 var reaction:float=-2.0*Vector3(f.dn).dot(velocity-Vector3(f.av))-Vector3(f.ddn).dot(q-Vector3(f.a))
 return {"valid":is_finite(reaction),"reaction":reaction,"acceleration":Vector3(f.n)*maxf(0.0,reaction),"frame":f}

static func _rk(face:Dictionary,q:Vector3,v:Vector3,t:float,h:float,seconds:float)->Dictionary:
 var k1:Dictionary=_acceleration(face,q,v,t,seconds)
 if not k1.valid:return {"valid":false}
 var k2:Dictionary=_acceleration(face,q+v*h*.5,v+Vector3(k1.acceleration)*h*.5,t+h/seconds*.5,seconds)
 if not k2.valid:return {"valid":false}
 var k3:Dictionary=_acceleration(face,q+(v+Vector3(k1.acceleration)*h*.5)*h*.5,v+Vector3(k2.acceleration)*h*.5,t+h/seconds*.5,seconds)
 if not k3.valid:return {"valid":false}
 var k4:Dictionary=_acceleration(face,q+(v+Vector3(k2.acceleration)*h*.5)*h,v+Vector3(k3.acceleration)*h,t+h/seconds,seconds)
 if not k4.valid:return {"valid":false}
 return {"valid":true,"q":q+(v*6.0+(Vector3(k1.acceleration)+Vector3(k2.acceleration)+Vector3(k3.acceleration))*h)*h/6.0,
  "v":v+(Vector3(k1.acceleration)+2.0*Vector3(k2.acceleration)+2.0*Vector3(k3.acceleration)+Vector3(k4.acceleration))*h/6.0,
  "min_reaction":minf(minf(k1.reaction,k2.reaction),minf(k3.reaction,k4.reaction))}

static func _derivative_bounds(face:Dictionary,q:Vector3,velocity:Vector3,t:float,h:float,seconds:float)->Dictionary:
 var u0:Vector3=face.b-face.a+(face.db-face.da)*t;var v0:Vector3=face.c-face.a+(face.dc-face.da)*t
 var du:Vector3=(face.db-face.da)/seconds;var dv:Vector3=(face.dc-face.da)/seconds
 var cross0:Vector3=u0.cross(v0);var cross1:Vector3=du.cross(v0)+u0.cross(dv);var cross2:Vector3=du.cross(dv)
 var norm:Array=Poly._dot_poly([cross0,cross1*h,cross2*h*h],[cross0,cross1*h,cross2*h*h])
 var minimum:float=sqrt(maxf(_extreme(norm,false),0.0))
 if minimum<1e-10:return {"valid":false}
 var p:float=maxf(cross1.length(),(cross1+cross2*2.0*h).length())/minimum
 var pp:float=2.0*cross2.length()/minimum+3.0*p*p
 # Re-anchor the SAME affine plane at the initial nearest plane point.
 # Constant barycentric coordinates preserve its exact trajectory and reduce
 # artificial derivative bounds caused by a remote polygon corner.
 var initial_frame:Dictionary=frame_at(face,t,seconds)
 var anchor:Vector3=q-Vector3(initial_frame.n)*(q-Vector3(initial_frame.a)).dot(initial_frame.n)
 var relative:Vector3=anchor-Vector3(initial_frame.a)
 var uu:float=u0.dot(u0);var uv:float=u0.dot(v0);var vv:float=v0.dot(v0)
 var determinant:float=uu*vv-uv*uv
 if absf(determinant)<1e-16:return {"valid":false}
 var bu:float=(relative.dot(u0)*vv-relative.dot(v0)*uv)/determinant
 var bv:float=(relative.dot(v0)*uu-relative.dot(u0)*uv)/determinant
 var anchor_velocity:Vector3=Vector3(face.da)/seconds+du*bu+dv*bv
 var relative_speed:float=(velocity-anchor_velocity).length()
 var relative_position:float=q.distance_to(anchor)
 var denominator:float=1.0-2.0*p*h-.5*pp*h*h
 if denominator<=0.0:return {"valid":false}
 var acceleration:float=(2.0*p*relative_speed+pp*(relative_position+relative_speed*h))/denominator
 var third:float=12.0*p*2.0*cross2.length()/minimum+15.0*p*p*p
 var max_speed:float=relative_speed+acceleration*h
 var max_position:float=relative_position+relative_speed*h+.5*acceleration*h*h
 var reaction_rate:float=3.0*pp*max_speed+third*max_position
 var r:float=2.0*cross2.length()/minimum
 var fourth:float=12.0*r*r+126.0*p*p*r+105.0*p*p*p*p
 var reaction_second:float=4.0*third*max_speed+fourth*max_position+3.0*acceleration*p*p
 var snap:float=reaction_second+2.0*reaction_rate*p+acceleration*pp
 return {"valid":true,"acceleration":acceleration,"reaction_rate":reaction_rate,"snap":snap}


static func _edge_exit(face:Dictionary,q:Vector3,velocity:Vector3,start:float,h:float,seconds:float,endpoint:Vector3,acceleration_bound:float)->Dictionary:
 var u:Vector3=face.b-face.a+(face.db-face.da)*start
 var v:Vector3=face.c-face.a+(face.dc-face.da)*start
 var du:Vector3=(face.db-face.da)/seconds;var dv:Vector3=(face.dc-face.da)/seconds
 var n:Array=[u.cross(v),du.cross(v)+u.cross(dv),du.cross(dv)]
 var best:Dictionary={}
 for index in face.polygon.size():
  var j:int=(index+1)%face.polygon.size()
  var a:Vector3=face.polygon[index]+face.motion[index]*start
  var av:Vector3=face.motion[index]/seconds
  var edge:Vector3=face.polygon[j]+face.motion[j]*start-a
  var edge_velocity:Vector3=(face.motion[j]-face.motion[index])/seconds
  var m:Array=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
  for i in 3:
   m[i]+=Vector3(n[i]).cross(edge);m[i+1]+=Vector3(n[i]).cross(edge_velocity)
  var p0:float=(q-a).dot(m[0])
  var end_m:Vector3=m[0]+m[1]*h+m[2]*h*h+m[3]*h*h*h
  var p1:float=(endpoint-a-av*h).dot(end_m)
  if p0<0.0 or p1>=0.0:continue
  var relative_v:Vector3=velocity-av;var relative_q:Vector3=q-a
  var derivative:float=relative_v.dot(m[0])+relative_q.dot(m[1])
  var m0_bound:float=Vector3(m[0]).length()+Vector3(m[1]).length()*h+Vector3(m[2]).length()*h*h+Vector3(m[3]).length()*h*h*h
  var m1_bound:float=Vector3(m[1]).length()+2.0*Vector3(m[2]).length()*h+3.0*Vector3(m[3]).length()*h*h
  var m2_bound:float=2.0*Vector3(m[2]).length()+6.0*Vector3(m[3]).length()*h
  var second_bound:float=acceleration_bound*m0_bound+2.0*(relative_v.length()+acceleration_bound*h)*m1_bound+(relative_q.length()+relative_v.length()*h+.5*acceleration_bound*h*h)*m2_bound
  if derivative+second_bound*h>=0.0:continue
  var low:=0.0;var high:=h;var low_state:Dictionary={"q":q,"v":velocity}
  for iteration in 24:
   var middle:float=(low+high)*.5
   var first:Dictionary=_rk(face,q,velocity,start,middle*.5,seconds)
   var state:Dictionary=_rk(face,first.q,first.v,start+middle*.5/seconds,middle*.5,seconds)
   if not state.get("valid",false):return {}
   var mt:Vector3=m[0]+m[1]*middle+m[2]*middle*middle+m[3]*middle*middle*middle
   var value:float=(Vector3(state.q)-a-av*middle).dot(mt)
   if value>=0.0:low=middle;low_state=state
   else:high=middle
  if best.is_empty() or low<float(best.elapsed):
   best={"elapsed":low,"position":low_state.q,"velocity":low_state.v,"edge":index,"time_bracket":Vector2(start+low/seconds,start+high/seconds),"edge_derivative_upper":derivative+second_bound*h,"event_position_error_bound":(velocity.length()+acceleration_bound*h)*(high-low)}
 return best

static func step(face:Dictionary,q:Vector3,velocity:Vector3,start:float,end:float,seconds:float,radius:float)->Dictionary:
 var began:int=Time.get_ticks_usec()
 var result:Dictionary=_step_impl(face,q,velocity,start,end,seconds,radius)
 if result.get("complete",false) and result.get("reason","")=="maintained_finite_face":
  var error:float=float(result.chord_error_bound)+float(result.integration_position_bound)+float(result.position_projection)
  # The existing step proves finite inward clearance and a constrained
  # curved path. Its chord plus numerical error is well within old slop.
  if error<SLOP and float(result.finite_margin_lower_bound)>error:
   _support_sequence+=1
   _support_certificates[_support_sequence]={"geometry":_support_geometry(face),"from":result.from,"to":result.position,"start":start,"end":result.time,"seconds":seconds,"radius":radius,"error":error,"margin":result.finite_margin_lower_bound}
   result["support_certificate_id"]=_support_sequence
   if _support_certificates.size()>32:_support_certificates.erase(_support_certificates.keys()[0])
 result.calculation_us=Time.get_ticks_usec()-began
 return result

static func _step_impl(face:Dictionary,q:Vector3,velocity:Vector3,start:float,end:float,seconds:float,radius:float)->Dictionary:
 if not q.is_finite() or not velocity.is_finite() or not is_finite(start) or not is_finite(end) or not is_finite(seconds) or not is_finite(radius) or seconds<=0 or radius<=0 or start<0 or end<start or end>1:return {"complete":false,"reason":"invalid_manifold_interval","time":start}
 for key in ["a","b","c","da","db","dc"]:
  if not Vector3(face.get(key,Vector3.INF)).is_finite():return {"complete":false,"reason":"invalid_face_geometry","time":start}
 var f:Dictionary=frame_at(face,start,seconds)
 if not f.valid:return {"complete":false,"reason":"collapsed_face","time":start}
 var gap:float=(q-Vector3(f.a)).dot(f.n)-radius
 if absf(gap)>SLOP:return {"complete":false,"reason":"outside_contact_slop","time":start,"gap":gap}
 var relative_normal:float=(velocity-Vector3(f.av)).dot(f.n)+(q-Vector3(f.a)).dot(f.dn)
 if relative_normal>maxf(1e-8,(velocity.length()+Vector3(f.av).length()+(q-Vector3(f.a)).length()*Vector3(f.dn).length())*8e-7):return {"complete":true,"released":true,"reason":"positive_separation_velocity","time":start,"position":q,"velocity":velocity}
 var initial_impulse:float=maxf(0.0,-relative_normal)
 velocity+=Vector3(f.n)*initial_impulse
 # Numerical seating has its own receipt and is bounded by preexisting slop.
 var seating:float=-gap;q+=Vector3(f.n)*seating
 var initial:Dictionary=_acceleration(face,q,velocity,start,seconds)
 if not initial.valid:return {"complete":false,"reason":"invalid_reaction","time":start}
 if initial.reaction<=0.0:return {"complete":true,"released":true,"reason":"nonadhesive_release","time":start,"position":q,"velocity":velocity,"reaction":initial.reaction,"normal_impulse":initial_impulse,"seating":seating}
 var h:float=(end-start)*seconds
 var refinements:=0
 while refinements<MAX_REFINEMENTS:
  var bounds:Dictionary=_derivative_bounds(face,q,velocity,start,h,seconds)
  var bound:float=float(bounds.get("acceleration",INF))
  var chord_error:float=bound*h*h/8.0
  var reaction_lower:float=float(initial.reaction)-float(bounds.get("reaction_rate",INF))*h
  if reaction_lower<0.0:
   h*=.5;refinements+=1;continue
  if not is_finite(chord_error) or chord_error>MAX_CHORD_ERROR:h*=.5;refinements+=1;continue
  var whole:Dictionary=_rk(face,q,velocity,start,h,seconds)
  var half:Dictionary=_rk(face,q,velocity,start,h*.5,seconds)
  if not whole.get("valid",false) or not half.get("valid",false):return {"complete":false,"reason":"invalid_integrator","time":start}
  var second:Dictionary=_rk(face,half.q,half.v,start+h/seconds*.5,h*.5,seconds)
  if not second.get("valid",false):return {"complete":false,"reason":"invalid_integrator","time":start}
  var position_error:float=Vector3(second.q).distance_to(whole.q)
  var velocity_error:float=Vector3(second.v).distance_to(whole.v)
  var lambda_prime:float=-3.0*Vector3(f.ddn).dot(velocity-Vector3(f.av))-Vector3(f.dddn).dot(q-Vector3(f.a))
  var jerk:Vector3=Vector3(f.n)*lambda_prime+Vector3(f.dn)*float(initial.reaction)
  var taylor_q:Vector3=q+velocity*h+Vector3(initial.acceleration)*(.5*h*h)+jerk*(h*h*h/6.0)
  var taylor_v:Vector3=velocity+Vector3(initial.acceleration)*h+jerk*(.5*h*h)
  var integration_position_bound:float=Vector3(second.q).distance_to(taylor_q)+float(bounds.snap)*pow(h,4)/24.0
  var integration_velocity_bound:float=Vector3(second.v).distance_to(taylor_v)+float(bounds.snap)*pow(h,3)/6.0
  var finish:float=start+h/seconds
  var frame:Dictionary=frame_at(face,finish,seconds)
  var next_q:Vector3=second.q;var next_v:Vector3=second.v
  var defect:float=(next_q-Vector3(frame.a)).dot(frame.n)-radius
  var speed_defect:float=(next_v-Vector3(frame.av)).dot(frame.n)+(next_q-Vector3(frame.a)).dot(frame.dn)
  if position_error>MAX_POSITION_ERROR or velocity_error>MAX_VELOCITY_ERROR or absf(defect)>MAX_POSITION_ERROR or absf(speed_defect)>MAX_VELOCITY_ERROR or integration_position_bound>MAX_POSITION_ERROR or integration_velocity_bound>MAX_VELOCITY_ERROR:
   h*=.5;refinements+=1;continue
  var margin:float=finite_margin(face,next_q,finish)
  var finite_bound:float=finite_interval_margin(face,q,next_q,start,finish)
  var pulling:bool=minf(half.min_reaction,second.min_reaction)<0.0
  if margin<0.0 and not pulling:
   var exit:Dictionary=_edge_exit(face,q,velocity,start,h,seconds,next_q,bound)
   if not exit.is_empty() and float(exit.elapsed)>0.0 and finite_interval_margin(face,q,exit.position,start,start+float(exit.elapsed)/seconds,int(exit.edge)) >= bound*float(exit.elapsed)*float(exit.elapsed)/8.0+integration_position_bound:
    var exit_time:float=start+float(exit.elapsed)/seconds
    return {"complete":true,"released":true,"reason":"finite_face_exit","time":exit_time,"position":exit.position,"velocity":exit.velocity,"from":q,"velocity_from":velocity,
     "normal_impulse":initial_impulse,"seating":seating,"elapsed":exit.elapsed,"integration_position_bound":integration_position_bound,"integration_velocity_bound":integration_velocity_bound,
     "chord_error_bound":bound*float(exit.elapsed)*float(exit.elapsed)/8.0,"acceleration_bound":bound,"position_projection":0.0,"velocity_projection":0.0,"reaction_lower_bound":reaction_lower,"finite_exit_certificate":exit,"work":refinements+25}
  if (margin<0.0 or pulling or finite_bound<chord_error+integration_position_bound) and h>1e-7:h*=.5;refinements+=1;continue
  if margin<0.0 or pulling:
   return {"complete":true,"released":true,"reason":"finite_face_exit" if margin<0.0 else "nonadhesive_release","time":start,"position":q,"velocity":velocity,"normal_impulse":initial_impulse,"seating":seating,"event_time_bracket":Vector2(start,finish),"event_position_error_bound":velocity.length()*h+.5*bound*h*h}
  if finite_bound<chord_error+integration_position_bound:
   h*=.5;refinements+=1;continue
  # Remove only roundoff-scale constraint defects. Record separately.
  next_q-=Vector3(frame.n)*defect;next_v-=Vector3(frame.n)*speed_defect
  return {"complete":true,"released":false,"reason":"maintained_finite_face","time":finish,"position":next_q,"velocity":next_v,"from":q,"velocity_from":velocity,
   "integration_position_bound":integration_position_bound,"integration_velocity_bound":integration_velocity_bound,"snap_bound":bounds.snap,
   "normal_impulse":initial_impulse,"seating":seating,"position_error":position_error,"velocity_error":velocity_error,"position_projection":absf(defect),"velocity_projection":absf(speed_defect),
   "finite_margin_lower_bound":finite_bound,"chord_error_bound":chord_error,"acceleration_bound":bound,"min_reaction":minf(half.min_reaction,second.min_reaction),"reaction_lower_bound":reaction_lower,"work":refinements+1,"elapsed":h}
 return {"complete":false,"reason":"manifold_numerical_budget","time":start,"work":refinements}

static func _support_geometry(face:Dictionary)->Array:
 return [face.a,face.b,face.c,face.da,face.db,face.dc,face.get("orientation",1.0),face.get("source",-1),face.get("offsets",PackedInt32Array()).duplicate(),face.polygon.duplicate(),face.motion.duplicate()]
static func accepted_support_certificate(id:int,face:Dictionary,from:Vector3,to:Vector3,start:float,end:float,seconds:float,radius:float)->Dictionary:
 if not _support_certificates.has(id):return {}
 var certificate:Dictionary=_support_certificates[id]
 if certificate.geometry!=_support_geometry(face) or certificate.from!=from or certificate.to!=to or certificate.start!=start or certificate.end!=end or certificate.seconds!=seconds or certificate.radius!=radius:return {}
 return {"qualified":true,"reason":"same_finite_face_within_contact_slop","max_gap_bound":SLOP}
