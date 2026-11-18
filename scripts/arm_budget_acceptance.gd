extends RefCounted
## Exact Boolean projection of LiveArmBudget.solve's existing result predicate.
## This does not produce a new elbow and must never replace a displayed solve.
const Budget=preload("res://scripts/live_arm_budget.gd")
const Screen=preload("res://scripts/qa_af_joint_region_screen.gd")
static var exact_cache={}
static var cache_hits=0
static var cache_misses=0
const CACHE_LIMIT=512
const CACHE_LIFETIME_TICKS=60
static var cache_epoch=-1
static var cache_clears=0
static func accepts(shoulder:Vector3,wrist:Vector3,elbow:Vector3,hand:Basis,upper:float,fore:float,left:bool,maximum:float=.98) -> bool:
 var _pt := Time.get_ticks_usec()
 var _pr = _perf_accepts(shoulder, wrist, elbow, hand, upper, fore, left, maximum)
 PerfMonitor.record("reach.accepts", Time.get_ticks_usec() - _pt)
 return _pr

static func _perf_accepts(shoulder:Vector3,wrist:Vector3,elbow:Vector3,hand:Basis,upper:float,fore:float,left:bool,maximum:float=.98) -> bool:
 return cached_core(shoulder,wrist,elbow,hand,upper,fore,left,maximum)
static func clear_cache()->void:
 exact_cache.clear();cache_epoch=Engine.get_physics_frames();cache_clears+=1
static func cached_core(shoulder:Vector3,wrist:Vector3,elbow:Vector3,hand:Basis,upper:float,fore:float,left:bool,maximum:float)->bool:
 # Full raw Variant encoding preserves signed zero and every float bit. No
 # quantization, actor identity, pose label or temporal assumption is involved.
 var tick=Engine.get_physics_frames()
 if cache_epoch<0 or tick<cache_epoch or tick-cache_epoch>=CACHE_LIFETIME_TICKS:clear_cache()
 var key=var_to_bytes([shoulder,wrist,elbow,hand,upper,fore,left,maximum])
 if exact_cache.has(key):cache_hits+=1;return exact_cache[key]
 cache_misses+=1
 var result=core(shoulder,wrist,elbow,hand,upper,fore,left,maximum)
 if exact_cache.size()>=CACHE_LIMIT:clear_cache()
 exact_cache[key]=result
 return result
static func core(shoulder:Vector3,wrist:Vector3,elbow:Vector3,hand:Basis,upper:float,fore:float,left:bool,maximum:float)->bool:
 if not shoulder.is_finite() or not wrist.is_finite() or not elbow.is_finite() or not hand.is_finite() or not is_finite(upper) or not is_finite(fore) or not is_finite(maximum) or maximum>1.:
  return fallback(shoulder,wrist,elbow,hand,upper,fore,left,maximum)
 var span=wrist-shoulder;var distance=span.length()
 if distance<.00001 or distance>=upper+fore or distance<=absf(upper-fore):return false
 var axis=span/distance;var along=(upper*upper-fore*fore+distance*distance)/(2.*distance);var radius=sqrt(maxf(0.,upper*upper-along*along));var center=shoulder+axis*along
 var radial=elbow-center;radial-=axis*radial.dot(axis)
 if radial.length_squared()<.00000001:radial=Vector3.UP-axis*axis.y
 if radial.length_squared()<.00000001:radial=Vector3.RIGHT-axis*axis.x
 radial=radial.normalized()
 var hand_orthonormal=hand.orthonormalized()
 var initial=cost(shoulder,wrist,center+radial*radius,hand_orthonormal,left)
 if not is_finite(initial):return fallback(shoulder,wrist,elbow,hand,upper,fore,left,maximum)
 # The original solve does not search a different plane if this one is <=1.
 if initial<=1.:return not initial>maximum
 var reference=hand.y-axis*hand.y.dot(axis)
 if reference.length_squared()<.00000001:reference=hand.z-axis*hand.z.dot(axis)
 reference=reference.normalized()
 if Screen.enabled and Screen.rejects(shoulder,wrist,hand,hand_orthonormal,axis,center,distance,along,radius,reference,upper,fore,left,maximum,initial):return false
 # Perf: feasibility predicate samples every 10 deg (36) instead of every 5 deg (72).
 # It only answers "is some elbow plane within budget"; budgets are wide, so a
 # 10 deg lattice finds the same answer in practice at half the cost.
 for index in 36:
  var angle=float(index)*Budget.STEP*2.0;var candidate=center+reference.rotated(axis,angle)*radius
  var candidate_cost=cost(shoulder,wrist,candidate,hand_orthonormal,left)
  if not is_finite(candidate_cost):return fallback(shoulder,wrist,elbow,hand,upper,fore,left,maximum)
  if candidate_cost<=maximum:return true
 return false
static func fallback(shoulder,wrist,elbow,hand,upper,fore,left,maximum)->bool:
 var full=Budget.solve(shoulder,wrist,elbow,hand,upper,fore,left)
 return bool(full.feasible) and not float(full.cost)>maximum

## Same numeric channel operations as Anatomy.decompose/Budget._cost, without
## constructing fields that this Boolean preflight never reads. Hand normalization
## is identical for every lattice sample and is computed once by the caller.
static func cost(shoulder:Vector3,wrist:Vector3,elbow:Vector3,hand_orthonormal:Basis,left:bool)->float:
 var Anatomy=Budget.Anatomy
 var forearm=Anatomy.forearm_reference(shoulder,elbow,wrist,Vector3.UP,left)
 var relative=forearm.orthonormalized().inverse()*hand_orthonormal
 var flexion=asin(clampf(relative.z.x,-1.,1.));var deviation=atan2(-relative.y.x,relative.x.x);var axial=atan2(-relative.z.y,relative.z.z)
 var sign_side=-1. if left else 1.;var flex_deg=rad_to_deg(flexion);var dev_deg=rad_to_deg(deviation)*sign_side;var axial_deg=rad_to_deg(axial)*sign_side
 var flex_limit=Anatomy.FLEXION_BUDGET_DEG if flex_deg>=0 else Anatomy.EXTENSION_BUDGET_DEG
 var dev_limit=Anatomy.RADIAL_BUDGET_DEG if dev_deg>=0 else Anatomy.ULNAR_BUDGET_DEG
 var ellipse=pow(flex_deg/flex_limit,2.)+pow(dev_deg/dev_limit,2.)
 return maxf(ellipse/.999,absf(axial_deg)/(Anatomy.AXIAL_BUDGET_DEG-.05))
