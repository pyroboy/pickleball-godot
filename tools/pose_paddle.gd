extends SceneTree
## Paddle placement helper for stroke keys: prints where the paddle is at each key and turns
## "head here, tip pointing there" into the values tools/pose_set.py takes.
##
##   godot --headless --path . -s tools/pose_paddle.gd -- s04
##   godot --headless --path . -s tools/pose_paddle.gd -- s04 drop head=0.25,1.13,-0.24 tip=0.1,-0.97,-0.2
##
## Coordinates are the pose review's: x toward the forehand side, y height above the court,
## z toward the net (metres). tip is the direction from handle to paddle head. The paddle face
## keeps the direction it has at that key now (face=x,y,z overrides it). Stages: windup, drop,
## contact, finish. Nothing is written: it prints the pose_set.py arguments.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Rotation = preload("res://scripts/paddle_rotation.gd")
const ROOT_HEIGHT := 0.92   # paddle_y_offset 0 is this high above the court (pose review: head y - paddle_y_offset)
const STAGES := {"windup": 0, "contact": 1, "finish": 2, "drop": 3}
const OFFSET_FIELD := {"windup": "charge_paddle_offset", "finish": "ft_paddle_offset", "drop": "drop_paddle_offset"}
const ROTATION_FIELD := {"windup": "charge_paddle_rotation_deg", "finish": "ft_paddle_rotation_deg", "drop": "drop_paddle_rotation_deg"}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].begins_with("s"):
		print("usage: -s tools/pose_paddle.gd -- s04 [stage head=x,y,z tip=x,y,z [face=x,y,z]]"); quit(1); return
	var def: PostureDefinition = load("res://scripts/posture_library.gd").instance().get_def(int(args[0].substr(1)))
	if def == null:
		print("no stroke pose ", args[0]); quit(1); return
	for stage in ["windup", "drop", "contact", "finish"]:
		if stage == "drop" and not Path.has_drop(def): continue
		var pose: PostureDefinition = Path.endpoint(def, STAGES[stage])
		var b: Basis = Rotation.unspun_basis(pose)
		print("%-8s head %s  tip %s  face %s  euler %s" % [stage, _v(_head(pose)), _v(_world(b.y)), _v(_world(b.z)), _v(Rotation.euler(b))])
	if args.size() >= 2:
		_solve(def, args)
	quit(0)

func _solve(def: PostureDefinition, args: PackedStringArray) -> void:
	var stage: String = args[1]
	if not OFFSET_FIELD.has(stage):
		print("stage must be windup, drop or finish (contact is the main pose)"); return
	var head := Vector3.INF; var tip := Vector3.INF; var face := Vector3.INF
	for a in args.slice(2):
		var kv := a.split("=")
		if kv.size() != 2: continue
		var p := kv[1].split_floats(",")
		if p.size() != 3: continue
		var v := Vector3(p[0], p[1], p[2])
		match kv[0]:
			"head": head = v
			"tip": tip = v
			"face": face = v
	var contact: PostureDefinition = Path.endpoint(def, 1)
	var now: PostureDefinition = Path.endpoint(def, STAGES[stage])   # a stroke without a Drop gives Contact here
	var out := PackedStringArray()
	if head != Vector3.INF:
		var d: Vector3 = head - _head(contact)
		out.append("contact.%s='Vector3(%.3f, %.3f, %.3f)'" % [OFFSET_FIELD[stage], d.x, d.y, d.z])
	if tip != Vector3.INF:
		var y: Vector3 = _canon(tip).normalized()
		var z: Vector3 = _canon(face) if face != Vector3.INF else Rotation.unspun_basis(now).z
		z = z - y * z.dot(y)
		if z.length() < 0.05: z = Rotation.unspun_basis(now).x.cross(y)
		z = z.normalized()
		var e: Vector3 = Rotation.euler(Basis(y.cross(z), y, z))
		var base: Vector3 = contact.resolve_paddle_rotation_deg(-1.0, -1.0)
		var r: Vector3 = Rotation.vector(e - base)
		out.append("contact.%s='Vector3(%.3f, %.3f, %.3f)'" % [ROTATION_FIELD[stage], r.x, r.y, r.z])
	print("python3 tools/pose_set.py %s %s" % [args[0], " ".join(out)])

func _head(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset + ROOT_HEIGHT, pose.paddle_forward_mul)

## Canonical paddle frame is (x forehand, y up, z away from the net); the review frame has z toward the net.
func _world(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)

func _canon(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
