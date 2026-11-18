extends RefCounted
const Budget=preload("res://scripts/live_arm_budget.gd")
const Anatomy=preload("res://scripts/arm_anatomy.gd")
const COMPONENT_RESERVE:float=1.0/64.0
const SCALAR_RESERVE:float=1.0/1073741824.0
const ANGLE_RESERVE:float=0.001
const FRAME_RESERVE:float=1.0/65536.0
static var enabled:bool=true
static var qualification:int=-1
static var qualification_usec:int=0
static var rotation_max_residual:float=0.0
static var rotation_table_bytes:PackedByteArray=PackedByteArray()

static func qualified()->bool:
 if qualification>=0:return qualification==1
 var begin:int=Time.get_ticks_usec()
 qualification=0
 var version:Dictionary=Engine.get_version_info()
 if int(version.get("major",0))!=4 or int(version.get("minor",0))!=6 or int(version.get("patch",0))!=3:return false
 if str(version.get("status",""))!="stable" or str(version.get("build",""))!="official":return false
 if not str(version.get("hash","" )).begins_with("7d41c59c4"):return false
 if Vector3(16777217.0,0.0,0.0).x!=16777216.0:return false
 if Anatomy.FLEXION_BUDGET_DEG!=70.0 or Anatomy.EXTENSION_BUDGET_DEG!=70.0 or Anatomy.RADIAL_BUDGET_DEG!=25.0 or Anatomy.ULNAR_BUDGET_DEG!=35.0 or Anatomy.AXIAL_BUDGET_DEG!=90.0:return false
 if Budget.STEP!=PI/36.0:return false
 var table:Array=[]
 for index in 72:
  var b:Basis=Basis(Vector3.UP,float(index)*Budget.STEP)
  if not b.is_finite():return false
  var cosine:float=b.x.x;var sine:float=-b.x.z
  var residual:float=absf(cosine*cosine+sine*sine-1.0)
  rotation_max_residual=maxf(rotation_max_residual,residual)
  if residual>1.0/1048576.0 or absf(b.y.y-1.0)>SCALAR_RESERVE:return false
  table.append([index,float(index)*Budget.STEP,b])
 rotation_table_bytes=var_to_bytes(table)
 qualification=1;qualification_usec=Time.get_ticks_usec()-begin
 return true

static func frame_ok(b:Basis)->bool:
 if not b.is_finite():return false
 if absf(b.x.length_squared()-1.0)>FRAME_RESERVE or absf(b.y.length_squared()-1.0)>FRAME_RESERVE or absf(b.z.length_squared()-1.0)>FRAME_RESERVE:return false
 if absf(b.x.dot(b.y))>FRAME_RESERVE or absf(b.x.dot(b.z))>FRAME_RESERVE or absf(b.y.dot(b.z))>FRAME_RESERVE:return false
 return absf(b.determinant()-1.0)<=2.0*FRAME_RESERVE

static func context(shoulder:Vector3,wrist:Vector3,hand:Basis,orth:Basis,axis:Vector3,center:Vector3,distance:float,along:float,radius:float,reference:Vector3,upper:float,fore:float,left:bool,maximum:float,initial:float)->Dictionary:
 if not qualified():return {"eligible":false,"reason":"build"}
 if not shoulder.is_finite() or not wrist.is_finite() or not axis.is_finite() or not center.is_finite() or not reference.is_finite() or not is_finite(distance) or not is_finite(along) or not is_finite(radius) or not is_finite(upper) or not is_finite(fore) or not is_finite(initial) or not is_finite(maximum):return {"eligible":false,"reason":"finite"}
 if maximum<0.5 or maximum>0.99 or initial<=1.001:return {"eligible":false,"reason":"threshold"}
 if upper<0.2 or upper>0.6 or fore<0.2 or fore>0.6 or distance<0.1 or distance>=upper+fore or distance<=absf(upper-fore) or radius<0.02:return {"eligible":false,"reason":"links"}
 for p:Vector3 in [shoulder,wrist,center]:
  if maxf(absf(p.x),maxf(absf(p.y),absf(p.z)))>12.0:return {"eligible":false,"reason":"world"}
 if not frame_ok(hand) or not frame_ok(orth):return {"eligible":false,"reason":"hand_frame"}
 if absf(axis.length_squared()-1.0)>FRAME_RESERVE or absf(reference.length_squared()-1.0)>FRAME_RESERVE or absf(axis.dot(reference))>FRAME_RESERVE:return {"eligible":false,"reason":"circle_frame"}
 var model_upper:float=sqrt(along*along+radius*radius)
 var rest:float=distance-along;var model_fore:float=sqrt(rest*rest+radius*radius)
 if not is_finite(model_upper) or not is_finite(model_fore) or model_upper<0.2 or model_fore<0.2:return {"eligible":false,"reason":"model_links"}
 var leverage:float=radius*distance/(model_upper*model_fore)
 if leverage<0.125:return {"eligible":false,"reason":"thumb_leverage"}
 var c:float=rest/model_fore;var s:float=radius/model_fore
 var normal:Vector3=axis.cross(reference);var sign_side:float=-1.0 if left else 1.0
 var coeff:Array=[]
 for col:Vector3 in [orth.x,orth.y,orth.z]:coeff.append([c*axis.dot(col),-s*reference.dot(col),-s*normal.dot(col)])
 coeff.append([-sign_side*s*axis.dot(orth.z),-sign_side*c*reference.dot(orth.z),-sign_side*c*normal.dot(orth.z)])
 coeff.append([0.0,-sign_side*normal.dot(orth.z),sign_side*reference.dot(orth.z)])
 return {"eligible":true,"coeff":coeff,"leverage":leverage}

static func scaled(a:Array,s:float)->Array:return [a[0]*s,a[1]*s,a[2]*s]
static func added(a:Array,b:Array)->Array:return [a[0]+b[0],a[1]+b[1],a[2]+b[2]]
static func evaluated(a:Array,theta:float)->float:return a[0]+a[1]*cos(theta)+a[2]*sin(theta)

static func allowed(a:float,b:float,c:float)->Array:
 if not is_finite(a) or not is_finite(b) or not is_finite(c):return [[0.0,TAU]]
 var radius:float=sqrt(b*b+c*c)
 if not is_finite(radius):return [[0.0,TAU]]
 if radius<0.000001:return [] if a< -radius-SCALAR_RESERVE else [[0.0,TAU]]
 if a>=radius-SCALAR_RESERVE:return [[0.0,TAU]]
 if a< -radius-SCALAR_RESERVE:return []
 var center:float=fposmod(atan2(c,b),TAU)
 var half:float=acos(clampf(-a/radius,-1.0,1.0))+ANGLE_RESERVE
 if not is_finite(center) or not is_finite(half) or half>=PI:return [[0.0,TAU]]
 var low:float=center-half;var high:float=center+half
 if low<0.0:return [[0.0,high],[low+TAU,TAU]]
 if high>TAU:return [[0.0,high-TAU],[low,TAU]]
 return [[low,high]]

static func empty_region(coeff:Array,left:bool,m:float)->bool:
 var sign_side:float=-1.0 if left else 1.0
 var flex:float=sin(deg_to_rad(70.0*sqrt(0.999*m)+0.01))
 var radial:float=tan(deg_to_rad(25.0*sqrt(0.999*m)+0.01))
 var ulnar:float=tan(deg_to_rad(35.0*sqrt(0.999*m)+0.01))
 var axial:float=tan(deg_to_rad(89.95*m+0.01))
 if not is_finite(flex) or not is_finite(radial) or not is_finite(ulnar) or not is_finite(axial):return false
 var e:float=COMPONENT_RESERVE+SCALAR_RESERVE
 var terms:Array=[coeff[0],added([flex,0.0,0.0],scaled(coeff[2],-1.0)),added([flex,0.0,0.0],coeff[2]),added(scaled(coeff[0],radial),scaled(coeff[1],sign_side)),added(scaled(coeff[0],ulnar),scaled(coeff[1],-sign_side)),added(scaled(coeff[4],axial),coeff[3]),added(scaled(coeff[4],axial),scaled(coeff[3],-1.0))]
 var margins:Array=[e,e,e,(radial+1.0)*e,(ulnar+1.0)*e,(axial+1.0)*e,(axial+1.0)*e]
 var intervals:Array=[[0.0,TAU]]
 for i in terms.size():
  var bands:Array=allowed(terms[i][0]+margins[i],terms[i][1],terms[i][2]);var next:Array=[]
  for current:Array in intervals:
   for band:Array in bands:
    var low:float=maxf(current[0],band[0]);var high:float=minf(current[1],band[1])
    if low<=high:next.append([low,high])
  intervals=next
  if intervals.size()>16:return false
  if intervals.is_empty():return true
 return false

static func rejects(shoulder:Vector3,wrist:Vector3,hand:Basis,orth:Basis,axis:Vector3,center:Vector3,distance:float,along:float,radius:float,reference:Vector3,upper:float,fore:float,left:bool,maximum:float,initial:float)->bool:
 var ctx:Dictionary=context(shoulder,wrist,hand,orth,axis,center,distance,along,radius,reference,upper,fore,left,maximum,initial)
 return bool(ctx.eligible) and empty_region(ctx.coeff,left,maximum)
