extends RefCounted
## Ball pickup and ball throw between points (Pose Studio workspace "Ball actions").
## The motion is built in code (scripts/between_point_controller.gd: stand_pose(bend) plus the ball
## hand's wrist targets). Each action has a 3-key file in data/ball_actions/ that the studio edits;
## the game adds only the difference between each authored key and `baseline` (the code-built key
## the file was made from). A file nobody edited adds nothing, so play stays exactly as the code.
## Keys and timeline:
##   pickup  stand -> Reach (halfway down) -> Grab (hand on the ball, bend_time) -> Rise (halfway up) -> stand (+lift_time)
##   throw   carry -> Wind-back (windup_time) -> Release (release_time, ball leaves) -> Follow (+follow_time) -> carry
## The Grab hand is pinned to the ball (gameplay); key times are editable (they change how long a
## point break takes: dead ball only).

const Def = preload("res://scripts/ball_action_definition.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Carry = preload("res://scripts/player_carry_presentation.gd")
const HandPresentation = preload("res://scripts/player_hand_presentation.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")

const PICKUP := 0
const THROW := 1            # weak throw: underhand lob, pendulum arm
const THROW_STRONG := 2     # strong throw: overhand
const FILES := ["res://data/ball_actions/00_pickup.tres", "res://data/ball_actions/01_throw.tres", "res://data/ball_actions/02_throw_strong.tres"]
const NAMES := ["Ball pickup", "Ball throw (lob)", "Ball throw (strong)"]
const KEY_NAMES := [["Reach", "Grab", "Rise"], ["Wind-back", "Release", "Follow"], ["Wind-back", "Release", "Follow"]]
## A pass to a partner this far away or more uses the strong throw (the lob below it).
const STRONG_THROW_M := 6.0
## The ball hand swings on an arc around the shoulder between throw keys (a pendulum for the
## lob, over the top for the strong throw), not on a straight line. Left shoulder, player axes.
const SHOULDER := Vector3(-0.19, 0.37, 0.0)
const STAGES := ["windup", "contact", "finish"]
const POSTURE_ID_BASE := 90             # posture_id of the action files (90 pickup, 91 throw); not a stroke
const READY_ID := 20
## Code numbers, in player axes (forehand side, up, toward the net); between_point_controller.gd.
const CARRY_HAND := Vector3(-0.26, 0.05, 0.32)     # _carry_wrist
const FREE_HAND := Vector3(-0.15, 0.15, 0.55)      # PlayerArmIk default target of a free support hand (preview)
const ROOT_Y := 1.0                                # player origin above the court (game.gd reset positions, ground_y)
const FLOOR_REST_Y := 0.075 + 0.0375                # ball centre at rest (Ball.FLOOR_Y + BALL_RADIUS)
const PICKUP_BALL := Vector3(-0.22, FLOOR_REST_Y - ROOT_Y, 0.27)   # ball centre from the pickup root (_pickup_root)
const THROW_WINDUP := Vector3(0.0, -0.1, -0.1)     # PASS_PREP wind-up wrist from the carry
const THROW_FINISH := Vector3(0.0, 0.16, 0.12)     # PASS_PREP finish wrist from the carry
const RETURN_TIME := 0.3                           # throw: Follow key back to the carry
const EPS := 1e-4                                 # smaller changes are file rounding (0.1 mm, 0.0001 deg)
const HAND := "left_hand_offset"
## Not part of the delta: stroke-only data (folded into the endpoints or unused between points).
const SKIP_PREFIX := ["charge_", "ft_", "zone_", "ready_curve_", "ready_path_", "speed_"]
const SKIP := ["bend_time", "lift_time", "windup_time", "release_time", "follow_time", "swing_path_blend",
	"paddle_floor_clearance", "stroke_overlay_mix", "transition_pose_blend"]

static var _defs := {}
static var _deltas := {}
static var _fields: Array = []
static var revision := 0

# ---------------------------------------------------------------- code-built motion

## The between-point stand with a pickup bend (0 = stand, 1 = at the ball); exactly the
## controller's pose before its facing turn.
static func stand_pose(ready: PostureDefinition, bend: float) -> PostureDefinition:
	var pose: PostureDefinition = ready.duplicate(true)
	pose.right_hand_offset = Vector3.ZERO
	# A carry is a neutral handle grip, independent of the live READY regrip.
	pose.main_grip_rotation_deg = pose.paddle_in_hand_rotation_deg
	pose.right_shoulder_rotation_deg = Vector3(0, -8, 0)
	pose.left_shoulder_rotation_deg = Vector3(0, 8, 0)
	pose.shoulder_protraction_m = 0.05
	pose.left_elbow_pole = Vector3( - 0.58, - 0.35, - 0.07)
	pose.left_hand_mode = 4
	pose.left_hand_offset = Vector3.ZERO
	# Between points a player stands up: feet under the hips, no crouch (the athletic READY
	# stance comes back in SET_SERVE). A pickup bends from there.
	pose.crouch_amount = lerpf(0.0, 0.64, bend)
	pose.body_pitch_deg = lerpf(0.0, 8.0, bend)
	pose.torso_pitch_deg = lerpf(0.0, 12.0, bend)
	pose.stance_width = lerpf(0.28, 0.5, bend)
	pose.front_foot_forward = lerpf(0.02, pose.front_foot_forward, bend)
	pose.back_foot_back = lerpf(-0.02, pose.back_foot_back, bend)
	pose.head_track_ball_weight = 0.4
	Carry.apply(pose, bend)
	return pose

static func grab_hand() -> Vector3:
	return PICKUP_BALL + Vector3(0.0, HandPresentation.RETRIEVAL_BALL_DEPTH, 0.0)   # _pickup_wrist_position

## Code-built keys [key1, key2, key3] with the ball hand as a preview offset (left_hand_offset).
static func code_keys(id: int, ready: PostureDefinition) -> Array:
	var bends: Array = [0.5, 1.0, 0.5] if id == PICKUP else [0.0, 0.0, 0.0]
	var hands := [CARRY_HAND.lerp(grab_hand(), 0.5), grab_hand(), CARRY_HAND.lerp(grab_hand(), 0.5)] if id == PICKUP \
		else [CARRY_HAND + THROW_WINDUP, CARRY_HAND + THROW_FINISH, CARRY_HAND]
	var out: Array = []
	for i in 3:
		var p := stand_pose(ready, bends[i])
		p.left_hand_offset = hands[i] - FREE_HAND
		out.append(p)
	return out

## A fresh action file from the code (tools: ball_actions_make.gd). Its baseline is its own keys.
static func build(id: int, ready: PostureDefinition) -> Resource:
	var keys := code_keys(id, ready)
	var d = Def.new()
	for n in _storage(keys[1]): d.set(n, keys[1].get(n))
	d.action_id = id
	d.posture_id = POSTURE_ID_BASE + id
	d.display_name = NAMES[id]
	d.has_zone = false
	for i in [0, 2]:
		var k = BodyKey.new(); k.capture(keys[i])
		if i == 0: d.windup_body = k
		else: d.follow_through_body = k
		# Paddle head and face are not keyframe fields: carry them as the wind-up / finish deltas.
		var off := Vector3(keys[i].paddle_forehand_mul - keys[1].paddle_forehand_mul, keys[i].paddle_y_offset - keys[1].paddle_y_offset, keys[i].paddle_forward_mul - keys[1].paddle_forward_mul)
		var rot := Vector3(keys[i].paddle_pitch_base_deg - keys[1].paddle_pitch_base_deg, keys[i].paddle_yaw_base_deg - keys[1].paddle_yaw_base_deg, keys[i].paddle_roll_base_deg - keys[1].paddle_roll_base_deg)
		if i == 0: d.charge_paddle_offset = off; d.charge_paddle_rotation_deg = rot
		else: d.ft_paddle_offset = off; d.ft_paddle_rotation_deg = rot
	d.charge_hip_coil_deg = 0.0; d.ft_hip_uncoil_deg = 0.0; d.charge_body_rotation_deg = 0.0
	d.charge_back_foot_load = -keys[0].weight_shift; d.ft_front_foot_load = keys[2].weight_shift
	d.baseline = snapshot(d)
	return d

## {stage: {field: value}} of the three endpoints (what the studio shows at each key).
static func snapshot(def: Resource) -> Dictionary:
	var out := {}
	for st in 3:
		var e: PostureDefinition = Path.endpoint(def, st)
		var row := {}
		for f in delta_fields(): row[f] = e.get(f)
		out[STAGES[st]] = row
	return out

# ---------------------------------------------------------------- files

static func get_def(id: int) -> Resource:
	if id < 0 or id >= FILES.size(): return null
	if not _defs.has(id):
		var path: String = _override_path(id) if FileAccess.file_exists(_override_path(id)) and not skip_overrides else FILES[id]
		_defs[id] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) if ResourceLoader.exists(path) else null
	return _defs[id]

## Phone Pose Studio: an action saved on the device (until the Mac sync puts it in the repo and a
## new build ships it). The desktop studio shows the repo files only.
const OVERRIDE_DIR := "user://ball_action_overrides"
static var skip_overrides := false
static func _override_path(id: int) -> String:
	return OVERRIDE_DIR.path_join(FILES[id].get_file())

static func save_override(id: int, def: Resource) -> bool:
	if id < 0 or id >= FILES.size() or def == null: return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OVERRIDE_DIR))
	var copy: Resource = def.duplicate(true)
	if ResourceSaver.save(copy, _override_path(id)) != OK: return false
	var live := get_def(id)
	if live != null:
		for p in copy.get_property_list():
			if p.usage & PROPERTY_USAGE_STORAGE and p.name != "script" and not p.name.begins_with("resource_"): live.set(p.name, copy.get(p.name))
	_deltas.erase(id)
	revision += 1
	return true

## Drop an on-device action once the packaged one is the same (after a sync and a new build).
static func drop_override(id: int) -> void:
	if FileAccess.file_exists(_override_path(id)): DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path(id)))
	_defs.erase(id); _deltas.erase(id); revision += 1

static func all_definitions() -> Array:
	var out: Array = []
	for i in FILES.size():
		var d := get_def(i)
		if d != null: out.append(d)
	return out

static func is_action(def) -> bool:
	return def != null and def.get_script() == Def

## After a save on disk (studio reload): load fresh, drop the cached deltas.
static func reload(id: int) -> Resource:
	_defs[id] = ResourceLoader.load(FILES[id], "", ResourceLoader.CACHE_MODE_REPLACE) if ResourceLoader.exists(FILES[id]) else null
	_deltas.erase(id)
	revision += 1
	return _defs[id]

# ---------------------------------------------------------------- deltas

static func _storage(r: Resource) -> Array:
	var out: Array = []
	for p in r.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE): continue
		var n: String = p.name
		if n == "script" or n.begins_with("resource_") or n.begins_with("metadata/"): continue
		out.append(n)
	return out

## Float and Vector3 pose fields a key can change (body, arms, head, paddle) + the ball hand.
static func delta_fields() -> Array:
	if _fields.is_empty():
		var p := PostureDefinition.new()
		for prop in p.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_STORAGE): continue
			if prop.type != TYPE_FLOAT and prop.type != TYPE_VECTOR3: continue
			var n: String = prop.name
			if n in SKIP: continue
			var skip := false
			for s in SKIP_PREFIX: skip = skip or n.begins_with(s)
			if not skip: _fields.append(n)
	return _fields

static func _diff(a, b, field: String):
	var d = a - b
	if field.ends_with("_deg"):
		if d is float: d = wrapf(d, -180.0, 180.0)
		else: d = Vector3(wrapf(d.x, -180.0, 180.0), wrapf(d.y, -180.0, 180.0), wrapf(d.z, -180.0, 180.0))
	return d

## Per key: {field: delta} of a working copy (or the saved file) against its baseline; only
## changed fields. HAND = the ball hand (player axes). Pickup Grab never moves the hand (the ball).
static func deltas_of(def: Resource) -> Array:
	var out: Array = [{}, {}, {}]
	if def == null or def.get("baseline") == null or (def.baseline as Dictionary).is_empty(): return out
	for st in 3:
		var base: Dictionary = def.baseline.get(STAGES[st], {})
		var e: PostureDefinition = Path.endpoint(def, st)
		for f in base:
			var v = e.get(f)
			if v == null: continue
			var d = _diff(v, base[f], f)
			var big: bool = absf(d) > EPS if d is float else (absf(d.x) > EPS or absf(d.y) > EPS or absf(d.z) > EPS)
			if big: out[st][f] = d
	if int(def.action_id) == PICKUP: out[1].erase(HAND)
	return out

## Saved-file deltas for the game (cached until reload).
static func deltas(id: int) -> Array:
	if not _deltas.has(id): _deltas[id] = deltas_of(get_def(id))
	return _deltas[id]

static func has_edits(id: int) -> bool:
	for k in deltas(id):
		if not (k as Dictionary).is_empty(): return true
	return false

## Which throw a pass of this length uses (the strong one only when its file exists).
static func throw_for(distance: float) -> int:
	return THROW_STRONG if distance >= STRONG_THROW_M and get_def(THROW_STRONG) != null else THROW

## Hand between two points on an arc around a pivot (direction slerp, radius lerp).
static func arc(pivot: Vector3, a: Vector3, b: Vector3, w: float) -> Vector3:
	var va := a - pivot
	var vb := b - pivot
	if va.length() < 0.01 or vb.length() < 0.01: return a.lerp(b, w)
	return pivot + va.normalized().slerp(vb.normalized(), w) * lerpf(va.length(), vb.length(), w)

## Blend of two key deltas (missing field = 0).
static func mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for f in a:
		var z = Vector3.ZERO if a[f] is Vector3 else 0.0
		out[f] = lerp(a[f], b.get(f, z), w)
	for f in b:
		if not a.has(f): out[f] = lerp(Vector3.ZERO if b[f] is Vector3 else 0.0, b[f], w)
	return out

## Adds a blended delta to a pose (the ball hand is the controller's wrist target, not the pose).
static func add_to(pose: PostureDefinition, delta: Dictionary) -> void:
	for f in delta:
		if f == HAND: continue
		pose.set(f, pose.get(f) + delta[f])

static func hand(delta: Dictionary) -> Vector3:
	return delta.get(HAND, Vector3.ZERO)

## Pickup: blended delta at a bend while going down (Reach at 0.5, Grab at 1) or up (Rise at 0.5).
static func pickup_delta(keys: Array, bend: float, rising: bool) -> Dictionary:
	if not rising:
		return mix({}, keys[0], bend / 0.5) if bend <= 0.5 else mix(keys[0], keys[1], (bend - 0.5) / 0.5)
	var up := 1.0 - bend   # 0 at the ball, 1 back at the stand
	return mix(keys[1], keys[2], up / 0.5) if up <= 0.5 else mix(keys[2], {}, (up - 0.5) / 0.5)

# ---------------------------------------------------------------- timing

static func timing(id: int, field: String, fallback: float) -> float:
	var d := get_def(id)
	var v = d.get(field) if d != null else null
	return float(v) if v != null else fallback

## Key times on the action's timeline (seconds from its start) and its length.
static func key_times(def: Resource) -> Array:
	if int(def.action_id) == PICKUP:
		var bt: float = def.bend_time
		var lt: float = def.lift_time
		return [maxf(bt - 0.05, 0.01) * 0.5, bt, bt + maxf(lt - 0.08, 0.01) * 0.5, bt + lt]
	return [def.windup_time, def.release_time, def.release_time + def.follow_time, def.release_time + def.follow_time + RETURN_TIME]

## Timing fields a key-time drag writes: [field, value] for key i dragged to t seconds.
static func time_edit(def: Resource, i: int, t: float) -> Array:
	if int(def.action_id) == PICKUP:
		match i:
			0: return ["bend_time", clampf(t * 2.0 + 0.05, 0.15, 1.2)]
			1: return ["bend_time", clampf(t, 0.15, 1.2)]
			_: return ["lift_time", clampf((t - def.bend_time) * 2.0 + 0.08, 0.15, 1.2)]
	match i:
		0: return ["windup_time", clampf(t, 0.05, def.release_time - 0.05)]
		1: return ["release_time", clampf(t, def.windup_time + 0.05, 1.5)]
		_: return ["follow_time", clampf(t - def.release_time, 0.05, 1.2)]
