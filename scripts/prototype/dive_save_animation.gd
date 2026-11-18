extends RefCounted
## Grounded lunge presentation. Court anchors are separate from body transforms.
## No airborne phase: one foot supports each deliberate swing, then both load.
const DURATION := 1.60
const MAX_TRAVEL := 0.45
const KEY_TIMES: Array = [0.0,0.10,0.28,0.43,0.72,1.05,1.32,1.60]
const ROOT: Array = [0.0,0.0,0.25,1.0,1.0,1.0,1.0,1.0]
const DROP: Array = [0.0,-0.08,-0.19,-0.30,-0.30,-0.30,-0.07,0.0]
const LEAN: Array = [0.0,0.0,0.035,0.105,0.080,0.035,0.0,0.0]
static func sample(time_seconds: float, direction: Vector3=Vector3.RIGHT, travel: float=MAX_TRAVEL) -> Dictionary:
	var t:=clampf(time_seconds,0.0,DURATION) if is_finite(time_seconds) else 0.0
	var toward:=Vector3(direction.x,0,direction.z)
	if not toward.is_finite() or toward.length_squared()<0.000001:toward=Vector3.RIGHT
	toward=toward.normalized()
	var distance:=clampf(travel,0.0,MAX_TRAVEL) if is_finite(travel) else 0.0
	var lead:=smoothstep(0.10,0.28,t)
	var trail:=smoothstep(0.76,1.05,t)
	var lead_lift:=_lift(t,0.10,0.28,0.045)
	var trail_lift:=_lift(t,0.76,1.05,0.045)
	var contact:=smoothstep(.20,.40,t)*(1.0-smoothstep(.58,.90,t))
	return {"phase":_phase(t),"progress":t/DURATION,"finished":t>=DURATION,
		"root_offset":toward*_curve(t,ROOT)*distance,
		"body_offset":Vector3.UP*_curve(t,DROP),
		"body_rotation":Vector3.UP.cross(toward)*_curve(t,LEAN),
		"paddle_offset":toward*.08*contact+Vector3.DOWN*.12*contact,
		"paddle_rotation":Vector3.ZERO,"contact_weight":contact,
		"lead_travel":distance*lead,"trail_travel":distance*trail,
		"lead_lift":lead_lift,"trail_lift":trail_lift,
		"lead_planted":lead_lift<=0.000001,"trail_planted":trail_lift<=0.000001,
		"lead_yaw_weight":lead,"trail_yaw_weight":trail,"airborne":false}
static func _lift(t:float,start:float,end:float,height:float)->float:
	if t<=start or t>=end:return 0.0
	var u:float=(t-start)/(end-start)
	return height*16*u*u*(1-u)*(1-u)
static func _curve(t:float,values:Array)->float:
	for i in range(KEY_TIMES.size()-1):
		if t<=float(KEY_TIMES[i+1]):return lerpf(float(values[i]),float(values[i+1]),smoothstep(float(KEY_TIMES[i]),float(KEY_TIMES[i+1]),t))
	return float(values[-1])
static func _phase(t:float)->StringName:
	if t<.10:return &"load"
	if t<.28:return &"lead_step"
	if t<.40:return &"plant_and_load"
	if t<.57:return &"grounded_contact"
	if t<.76:return &"supported_hold"
	if t<1.05:return &"gather_trailing_foot"
	if t<DURATION:return &"rise_and_recover"
	return &"complete"
