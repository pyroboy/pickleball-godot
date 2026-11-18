extends RefCounted
## Bounded emergency lateral dive trajectory, expressed in ground-projected
## root coordinates. The pelvis follows a ballistic flight after push-off.
## The adapter resolves real rig support during landing and get-up.
const Base = preload("res://scripts/prototype/long_reach_pose.gd")
const DURATION := 2.80
const CONTACT_TIME := 0.58
const TAKEOFF := 0.24
const LANDING := 0.6133333333333333
const SLIDE_END := 1.03
const GETUP_START := 1.18
const FEET_PLANT := 1.88
const MAX_SPEED := 2.05
const ACCEL_START := 0.10
const MAX_ACCEL := MAX_SPEED / (TAKEOFF - ACCEL_START)
const GRAVITY := 9.81
const LAUNCH_SPEED := 0.65
const MAX_TRAVEL := MAX_SPEED * ((TAKEOFF - ACCEL_START) * 0.5 + LANDING - TAKEOFF + (SLIDE_END - LANDING) * 0.5)

static func maximum_travel(_height: float) -> float: return MAX_TRAVEL
static func capture_base(actor) -> Dictionary: return Base.capture_base(actor)

static func horizontal(time: float, speed: float = MAX_SPEED) -> Dictionary:
	var t := clampf(time, 0.0, DURATION)
	var load := TAKEOFF - ACCEL_START
	var air := LANDING - TAKEOFF
	var slide := SLIDE_END - LANDING
	if t <= ACCEL_START: return {"distance": 0.0, "speed": 0.0, "acceleration": 0.0}
	if t < TAKEOFF:
		var u := t - ACCEL_START
		return {"distance": 0.5 * speed / load * u * u, "speed": speed * u / load, "acceleration": speed / load}
	if t < LANDING: return {"distance": speed * (load * 0.5 + t - TAKEOFF), "speed": speed, "acceleration": 0.0}
	if t < SLIDE_END:
		var u := t - LANDING
		return {"distance": speed * (load * 0.5 + air + u - u * u / (2.0 * slide)), "speed": speed * (1.0 - u / slide), "acceleration": -speed / slide}
	return {"distance": speed * (load * 0.5 + air + slide * 0.5), "speed": 0.0, "acceleration": 0.0}

static func sample(time: float, direction: Vector3 = Vector3.RIGHT, travel: float = MAX_TRAVEL, backhand: bool = false, _contact_height: float = 0.5) -> Dictionary:
	var t := clampf(time, 0.0, DURATION) if is_finite(time) else 0.0
	var toward := Vector3(direction.x, 0.0, direction.z).normalized()
	if toward.length_squared() < 0.99: toward = Vector3.RIGHT
	var speed := MAX_SPEED * clampf(travel / MAX_TRAVEL, 0.0, 1.0)
	var track := horizontal(t, speed)
	var load := smoothstep(0.0, 0.11, t) * (1.0 - smoothstep(0.11, TAKEOFF, t))
	var pitch := deg_to_rad(74.0) * smoothstep(0.12, 0.59, t) * (1.0 - smoothstep(GETUP_START, 2.30, t))
	var air_time := clampf(t - TAKEOFF, 0.0, 0.60)
	var ballistic := LAUNCH_SPEED * air_time - 0.5 * GRAVITY * air_time * air_time
	var counter := smoothstep(0.045, 0.30, t) * (1.0 - smoothstep(1.86, 2.65, t))
	return {"phase": _phase(t), "time": t, "progress": t / DURATION, "finished": t >= DURATION,
		"root_offset": toward * float(track.distance), "root_velocity": toward * float(track.speed),
		"root_acceleration": toward * float(track.acceleration), "direction": toward,
		"load_drop": -0.115 * load - 0.08 * smoothstep(0.11, TAKEOFF, t), "ballistic_offset": ballistic, "tilt": pitch,
		"airborne": t > TAKEOFF and t < LANDING, "backhand": backhand,
		"counterbalance_weight": counter, "pole_weight": counter, "body_offset": Vector3.ZERO,
		"body_rotation": Vector3.ZERO, "body_yaw": 0.0, "torso_yaw": deg_to_rad(45.0 if backhand else -45.0) * smoothstep(0.08, 0.48, t) * (1.0 - smoothstep(1.80, 2.70, t)),
		"contact_weight": smoothstep(0.16, 0.52, t) * (1.0 - smoothstep(0.64, 1.0, t))}

static func _phase(t: float) -> StringName:
	if t < 0.10: return &"supported_load"
	if t < TAKEOFF: return &"push_off"
	if t < 0.48: return &"airborne_extension"
	if t < LANDING: return &"airborne_save"
	if t < SLIDE_END: return &"floor_landing_slide"
	if t < GETUP_START: return &"floor_recovery"
	if t < FEET_PLANT: return &"gather_under_body"
	if t < 2.42: return &"supported_get_up"
	if t < DURATION: return &"regrip_and_recover"
	return &"complete"
