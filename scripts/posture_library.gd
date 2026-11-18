class_name PostureLibrary extends RefCounted
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")

const _PostureDefinition = preload("res://scripts/posture_definition.gd")
const MobilePoseStore = preload("res://scripts/mobile_pose_store.gd")
















const DATA_DIR: = "res://data/postures/"

var _by_id: Dictionary = {}
var definitions: Array = []


static var _singleton: PostureLibrary = null


static var _load_printed: bool = false


static func instance() -> PostureLibrary:
	if _singleton == null:
		_singleton = load("res://scripts/posture_library.gd").new()
	return _singleton


func _init() -> void :
	load_or_default()


func load_or_default() -> void :
	definitions.clear()
	_by_id.clear()
	_build_defaults()
	_load_from_disk()
	MobilePoseStore.apply_overrides(definitions, false)
	for d in definitions:
		_by_id[d.posture_id] = d


func get_def(posture_id: int):
	return _by_id.get(posture_id, null)


func has_def(posture_id: int) -> bool:
	return _by_id.has(posture_id)


func all_definitions():
	return definitions


func _load_from_disk() -> void :



	var files: PackedStringArray = ResourceLoader.list_directory(DATA_DIR)
	files.sort()
	for file_name in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var full_path: String = DATA_DIR + file_name

		var res: Resource = ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if not res is _PostureDefinition:
			push_warning("PostureLibrary: failed to load " + full_path)
			continue
		var pid: int = res.posture_id
		var replaced: = false
		for i in range(definitions.size()):
			if definitions[i].posture_id == pid:
				definitions[i] = res
				replaced = true
				break
		if not replaced:
			definitions.append(res)
		if not _load_printed:
			var def: _PostureDefinition = res
			if RuntimePolicy.developer_tools: print("[VERIFIED LOAD] %s | fh=%.4f fwd=%.4f y=%.4f zone=[%.3f..%.3f] y=[%.3f..%.3f] z=%.3f  (from %s)" % [
				def.display_name, 
				def.paddle_forehand_mul, def.paddle_forward_mul, def.paddle_y_offset, 
				def.zone_x_min, def.zone_x_max, def.zone_y_min, def.zone_y_max, def.zone_forward_offset, 
				file_name
			])
	_load_printed = true














func _build_defaults() -> void :

	var FOREHAND: = 0
	var FORWARD: = 1
	var BACKHAND: = 2
	var MEDIUM_OVERHEAD: = 3
	var HIGH_OVERHEAD: = 4
	var LOW_FOREHAND: = 5
	var LOW_FORWARD: = 6
	var LOW_BACKHAND: = 7
	var CHARGE_FOREHAND: = 8
	var CHARGE_BACKHAND: = 9
	var WIDE_FOREHAND: = 10
	var WIDE_BACKHAND: = 11
	var VOLLEY_READY: = 12
	var MID_LOW_FOREHAND: = 13
	var MID_LOW_BACKHAND: = 14
	var MID_LOW_FORWARD: = 15
	var MID_LOW_WIDE_FH: = 16
	var MID_LOW_WIDE_BH: = 17
	var LOW_WIDE_FOREHAND: = 18
	var LOW_WIDE_BACKHAND: = 19
	var READY: = 20






	definitions.append(_make(FOREHAND, "Forehand", 0, 2, {
		"pf": 0.55, "pfw": 0.5, "py": 0.0, 
		"pitch_signed": -30.0, "pitch_src": 2, 
		"roll_signed": 45.0, "roll_src": 1, 
		"zone": [0.3, 0.8, 0.3, 0.8], 
		"charge_offset": Vector3(0.05, 0.2, -0.3), 
		"charge_rot": Vector3(-30.0, 35.0, -15.0), 
		"charge_body_deg": 30.0, 
		"charge_hip_deg": 15.0, 
		"ft_offset": Vector3(0.15, 0.38, -0.2), 
		"ft_rot": Vector3(20.0, 25.0, -30.0), 
		"ft_hip_deg": 20.0, 
		"ft_load": 0.85, 
	}))

	definitions.append(_make(BACKHAND, "Backhand", 1, 2, {
		"pf": -0.55, "pfw": 0.5, "py": 0.0, 
		"pitch_signed": -30.0, "pitch_src": 2, 
		"roll_signed": -45.0, "roll_src": 1, 
		"zone": [-0.8, -0.3, 0.3, 0.8], 
		"charge_offset": Vector3(-0.05, 0.2, -0.28), 
		"charge_rot": Vector3(-30.0, -35.0, 15.0), 
		"charge_body_deg": 30.0, 
		"charge_hip_deg": 15.0, 
		"ft_offset": Vector3(-0.15, 0.36, -0.18), 
		"ft_rot": Vector3(20.0, -25.0, 30.0), 
		"ft_hip_deg": 20.0, 
		"ft_load": 0.85, 
	}))

	definitions.append(_make(WIDE_FOREHAND, "Wide Forehand", 0, 2, {
		"pf": 0.95, "pfw": 0.5, "py": 0.0, 
		"pitch_signed": -28.0, "pitch_src": 2, 
		"yaw_signed": 12.0, "yaw_src": 1, 
		"roll_signed": 35.0, "roll_src": 1, 
		"zone": [0.7, 1.2, 0.3, 0.8], 
		"charge_offset": Vector3(0.08, 0.22, -0.32), 
		"charge_rot": Vector3(-32.0, 40.0, -18.0), 
		"charge_body_deg": 32.0, 
		"charge_hip_deg": 16.0, 
		"ft_offset": Vector3(0.18, 0.4, -0.22), 
		"ft_rot": Vector3(22.0, 28.0, -32.0), 
		"ft_hip_deg": 22.0, 
		"ft_load": 0.87, 
	}))

	definitions.append(_make(WIDE_BACKHAND, "Wide Backhand", 1, 2, {
		"pf": -0.95, "pfw": 0.5, "py": 0.0, 
		"pitch_signed": -28.0, "pitch_src": 2, 
		"yaw_signed": -10.0, "yaw_src": 1, 
		"roll_signed": -30.0, "roll_src": 1, 
		"zone": [-1.2, -0.7, 0.3, 0.8], 
		"charge_offset": Vector3(-0.08, 0.22, -0.3), 
		"charge_rot": Vector3(-32.0, -40.0, 18.0), 
		"charge_body_deg": 32.0, 
		"charge_hip_deg": 16.0, 
		"ft_offset": Vector3(-0.18, 0.38, -0.2), 
		"ft_rot": Vector3(22.0, -28.0, 32.0), 
		"ft_hip_deg": 22.0, 
		"ft_load": 0.87, 
	}))

	definitions.append(_make(FORWARD, "Forward", 2, 2, {
		"pf": 0.0, "pfw": 0.5, "py": 0.0, 
		"pitch_signed": -25.0, "pitch_src": 2, 
		"zone": [-0.3, 0.3, 0.3, 0.8], 
		"charge_offset": Vector3(0.0, 0.12, -0.18), 
		"charge_rot": Vector3(-20.0, 0.0, 0.0), 
		"charge_body_deg": 15.0, 
		"charge_hip_deg": 10.0, 
		"ft_offset": Vector3(0.0, 0.32, 0.08), 
		"ft_rot": Vector3(30.0, 0.0, 16.0), 
		"ft_hip_deg": 18.0, 
		"ft_load": 0.82, 
	}))

	definitions.append(_make(VOLLEY_READY, "Volley Ready", 2, 2, {
		"pf": 0.0, "pfw": 0.5, "py": 0.12, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"zone": [-0.3, 0.3, 0.45, 0.9], 
		"charge_offset": Vector3(0.0, 0.15, -0.15), 
		"charge_rot": Vector3(-18.0, 0.0, 0.0), 
		"charge_body_deg": 12.0, 
		"charge_hip_deg": 8.0, 
		"ft_offset": Vector3(0.0, 0.28, 0.06), 
		"ft_rot": Vector3(28.0, 0.0, 14.0), 
		"ft_hip_deg": 16.0, 
		"ft_load": 0.8, 
	}))

	definitions.append(_make(READY, "Ready", 2, 2, {
		"pf": 0.0, "pfw": 0.55, "py": -0.28, 
		"pitch_signed": -55.0, "pitch_src": 2, 
		"yaw_signed": -15.0, "yaw_src": 1, 

		"charge_offset": Vector3(0.0, 0.0, 0.0), 
		"charge_rot": Vector3(0.0, 0.0, 0.0), 
		"charge_body_deg": 0.0, 
		"charge_hip_deg": 0.0, 
		"ft_offset": Vector3(0.0, 0.0, 0.0), 
		"ft_rot": Vector3(0.0, 0.0, 0.0), 
		"ft_hip_deg": 0.0, 
		"ft_load": 0.85, 
	}))


	definitions.append(_make(MEDIUM_OVERHEAD, "Medium Overhead", 3, 3, {
		"pf": 0.0, "pfw": 0.6, "py": 0.6, 
		"pitch_signed": -35.0, "pitch_src": 2, 
		"zone": [-0.4, 0.4, 1.2, 1.8], 
		"charge_offset": Vector3(0.0, 0.38, -0.2), 
		"charge_rot": Vector3(-46.0, 0.0, -8.0), 
		"charge_body_deg": 20.0, 
		"charge_hip_deg": 10.0, 
		"ft_offset": Vector3(0.0, -0.35, 0.45), 
		"ft_rot": Vector3(72.0, 0.0, 6.0), 
		"ft_hip_deg": 25.0, 
		"ft_load": 0.88, 
	}))

	definitions.append(_make(HIGH_OVERHEAD, "High Overhead", 3, 3, {
		"pf": 0.0, "pfw": 0.6, "py": 1.1, 
		"pitch_signed": -40.0, "pitch_src": 2, 
		"zone": [-0.4, 0.4, 1.7, 2.3], 
		"charge_offset": Vector3(0.0, 0.45, -0.18), 
		"charge_rot": Vector3(-62.0, 0.0, -8.0), 
		"charge_body_deg": 25.0, 
		"charge_hip_deg": 12.0, 
		"ft_offset": Vector3(0.0, -0.42, 0.5), 
		"ft_rot": Vector3(82.0, 0.0, 6.0), 
		"ft_hip_deg": 28.0, 
		"ft_load": 0.9, 
	}))


	definitions.append(_make(MID_LOW_FOREHAND, "Mid-Low Forehand", 0, 1, {
		"pf": 0.55, "pfw": 0.5, "py": -0.2, 
		"pitch_signed": -22.0, "pitch_src": 2, 
		"roll_signed": 38.0, "roll_src": 1, 
		"zone": [0.3, 0.8, 0.1, 0.55], 
		"charge_offset": Vector3(0.05, 0.16, -0.28), 
		"charge_rot": Vector3(-28.0, 35.0, -16.0), 
		"charge_body_deg": 28.0, 
		"charge_hip_deg": 14.0, 
		"ft_offset": Vector3(0.13, 0.35, -0.17), 
		"ft_rot": Vector3(18.0, 24.0, -28.0), 
		"ft_hip_deg": 19.0, 
		"ft_load": 0.83, 
	}))

	definitions.append(_make(MID_LOW_BACKHAND, "Mid-Low Backhand", 1, 1, {
		"pf": -0.55, "pfw": 0.5, "py": -0.2, 
		"pitch_signed": -22.0, "pitch_src": 2, 
		"roll_signed": -32.0, "roll_src": 1, 
		"zone": [-0.8, -0.3, 0.1, 0.55], 
		"charge_offset": Vector3(-0.05, 0.16, -0.26), 
		"charge_rot": Vector3(-28.0, -35.0, 16.0), 
		"charge_body_deg": 28.0, 
		"charge_hip_deg": 14.0, 
		"ft_offset": Vector3(-0.13, 0.33, -0.16), 
		"ft_rot": Vector3(18.0, -24.0, 28.0), 
		"ft_hip_deg": 19.0, 
		"ft_load": 0.83, 
	}))

	definitions.append(_make(MID_LOW_FORWARD, "Mid-Low Forward", 2, 1, {
		"pf": 0.0, "pfw": 0.5, "py": -0.2, 
		"pitch_signed": -25.0, "pitch_src": 2, 
		"zone": [-0.3, 0.3, 0.1, 0.55], 
		"charge_offset": Vector3(0.0, 0.1, -0.16), 
		"charge_rot": Vector3(-18.0, 0.0, 0.0), 
		"charge_body_deg": 14.0, 
		"charge_hip_deg": 9.0, 
		"ft_offset": Vector3(0.0, 0.3, 0.07), 
		"ft_rot": Vector3(28.0, 0.0, 15.0), 
		"ft_hip_deg": 16.0, 
		"ft_load": 0.8, 
	}))

	definitions.append(_make(MID_LOW_WIDE_FH, "Mid-Low Wide Forehand", 0, 1, {
		"pf": 0.95, "pfw": 0.5, "py": -0.2, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"yaw_signed": 10.0, "yaw_src": 1, 
		"roll_signed": 30.0, "roll_src": 1, 
		"zone": [0.7, 1.2, 0.1, 0.55], 
		"charge_offset": Vector3(0.1, 0.18, -0.3), 
		"charge_rot": Vector3(-30.0, 42.0, -18.0), 
		"charge_body_deg": 30.0, 
		"charge_hip_deg": 15.0, 
		"ft_offset": Vector3(0.16, 0.38, -0.19), 
		"ft_rot": Vector3(20.0, 27.0, -30.0), 
		"ft_hip_deg": 21.0, 
		"ft_load": 0.85, 
	}))

	definitions.append(_make(MID_LOW_WIDE_BH, "Mid-Low Wide Backhand", 1, 1, {
		"pf": -0.95, "pfw": 0.5, "py": -0.2, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"yaw_signed": -8.0, "yaw_src": 1, 
		"roll_signed": -28.0, "roll_src": 1, 
		"zone": [-1.2, -0.7, 0.1, 0.55], 
		"charge_offset": Vector3(-0.1, 0.18, -0.28), 
		"charge_rot": Vector3(-30.0, -42.0, 18.0), 
		"charge_body_deg": 30.0, 
		"charge_hip_deg": 15.0, 
		"ft_offset": Vector3(-0.16, 0.36, -0.18), 
		"ft_rot": Vector3(20.0, -27.0, 30.0), 
		"ft_hip_deg": 21.0, 
		"ft_load": 0.85, 
	}))


	definitions.append(_make(LOW_FOREHAND, "Low Forehand", 0, 0, {
		"pf": 0.55, "pfw": 0.5, "py": -0.62, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"roll_base": 180.0, "roll_signed": 10.0, "roll_src": 1, 
		"clearance": 0.45, 
		"zone": [0.3, 0.8, -0.3, 0.2], 
		"charge_offset": Vector3(0.05, 0.18, -0.28), 
		"charge_rot": Vector3(-25.0, 35.0, -15.0), 
		"charge_body_deg": 25.0, 
		"charge_hip_deg": 12.0, 
		"ft_offset": Vector3(0.12, 0.32, -0.15), 
		"ft_rot": Vector3(15.0, 20.0, -25.0), 
		"ft_hip_deg": 18.0, 
		"ft_load": 0.8, 
	}))

	definitions.append(_make(LOW_BACKHAND, "Low Backhand", 1, 0, {
		"pf": -0.55, "pfw": 0.5, "py": -0.62, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"roll_base": 180.0, "roll_signed": -10.0, "roll_src": 1, 
		"clearance": 0.45, 
		"zone": [-0.8, -0.3, -0.3, 0.2], 
		"charge_offset": Vector3(-0.05, 0.18, -0.26), 
		"charge_rot": Vector3(-25.0, -35.0, 15.0), 
		"charge_body_deg": 25.0, 
		"charge_hip_deg": 12.0, 
		"ft_offset": Vector3(-0.12, 0.3, -0.14), 
		"ft_rot": Vector3(15.0, -20.0, 25.0), 
		"ft_hip_deg": 18.0, 
		"ft_load": 0.8, 
	}))

	definitions.append(_make(LOW_FORWARD, "Low Forward", 2, 0, {
		"pf": 0.0, "pfw": 0.5, "py": -0.62, 
		"pitch_signed": -20.0, "pitch_src": 2, 
		"roll_base": 180.0, 
		"clearance": 0.45, 
		"zone": [-0.3, 0.3, -0.3, 0.2], 
		"charge_offset": Vector3(0.0, 0.1, -0.16), 
		"charge_rot": Vector3(-15.0, 0.0, 0.0), 
		"charge_body_deg": 12.0, 
		"charge_hip_deg": 8.0, 
		"ft_offset": Vector3(0.0, 0.28, 0.06), 
		"ft_rot": Vector3(25.0, 0.0, 14.0), 
		"ft_hip_deg": 15.0, 
		"ft_load": 0.78, 
	}))

	definitions.append(_make(LOW_WIDE_FOREHAND, "Low Wide Forehand", 0, 0, {
		"pf": 0.95, "pfw": 0.5, "py": -0.62, 
		"pitch_signed": -18.0, "pitch_src": 2, 
		"yaw_signed": 12.0, "yaw_src": 1, 
		"roll_base": 180.0, "roll_signed": 8.0, "roll_src": 1, 
		"clearance": 0.45, 
		"zone": [0.7, 1.2, -0.3, 0.2], 
		"charge_offset": Vector3(0.08, 0.15, -0.28), 
		"charge_rot": Vector3(-26.0, 42.0, -16.0), 
		"charge_body_deg": 26.0, 
		"charge_hip_deg": 13.0, 
		"ft_offset": Vector3(0.14, 0.33, -0.16), 
		"ft_rot": Vector3(16.0, 25.0, -28.0), 
		"ft_hip_deg": 18.0, 
		"ft_load": 0.82, 
	}))

	definitions.append(_make(LOW_WIDE_BACKHAND, "Low Wide Backhand", 1, 0, {
		"pf": -0.95, "pfw": 0.5, "py": -0.62, 
		"pitch_signed": -18.0, "pitch_src": 2, 
		"yaw_signed": -10.0, "yaw_src": 1, 
		"roll_base": 180.0, "roll_signed": -8.0, "roll_src": 1, 
		"clearance": 0.45, 
		"zone": [-1.2, -0.7, -0.3, 0.2], 
		"charge_offset": Vector3(-0.08, 0.15, -0.26), 
		"charge_rot": Vector3(-26.0, -42.0, 16.0), 
		"charge_body_deg": 26.0, 
		"charge_hip_deg": 13.0, 
		"ft_offset": Vector3(-0.14, 0.31, -0.15), 
		"ft_rot": Vector3(16.0, -25.0, 28.0), 
		"ft_hip_deg": 18.0, 
		"ft_load": 0.82, 
	}))




	definitions.append(_make(CHARGE_FOREHAND, "Charge Forehand", 0, 2, {
		"pf": 0.55, "pfw": -0.65, "py": 0.35, 

		"charge_offset": Vector3(0.0, 0.35, -1.15), 
		"charge_rot": Vector3(-45.0, 35.0, -20.0), 
		"charge_body_deg": 35.0, 
	}))

	definitions.append(_make(CHARGE_BACKHAND, "Charge Backhand", 1, 2, {
		"pf": -0.55, "pfw": -0.65, "py": 0.35, 

		"charge_offset": Vector3(0.0, 0.35, -1.15), 
		"charge_rot": Vector3(-45.0, -35.0, 20.0), 
		"charge_body_deg": 110.0, 
	}))


func _vec3_from_dict(d: Dictionary, key: String, default_val: Vector3) -> Vector3:
	if d.has(key) and d[key] is Vector3:
		return d[key]
	return default_val


func _make(pid: int, name: String, family_: int, tier_: int, p: Dictionary):
	var d = _PostureDefinition.new()
	d.posture_id = pid
	d.display_name = name
	d.family = family_
	d.height_tier = tier_

	d.paddle_forehand_mul = float(p.get("pf", 0.0))
	d.paddle_forward_mul = float(p.get("pfw", 0.0))
	d.paddle_y_offset = float(p.get("py", 0.0))

	d.paddle_pitch_base_deg = float(p.get("pitch_base", 0.0))
	d.paddle_pitch_signed_deg = float(p.get("pitch_signed", 0.0))
	d.paddle_pitch_sign_source = int(p.get("pitch_src", 0))

	d.paddle_yaw_base_deg = float(p.get("yaw_base", 0.0))
	d.paddle_yaw_signed_deg = float(p.get("yaw_signed", 0.0))
	d.paddle_yaw_sign_source = int(p.get("yaw_src", 0))

	d.paddle_roll_base_deg = float(p.get("roll_base", 0.0))
	d.paddle_roll_signed_deg = float(p.get("roll_signed", 0.0))
	d.paddle_roll_sign_source = int(p.get("roll_src", 0))

	d.paddle_floor_clearance = float(p.get("clearance", 0.06))

	if p.has("zone"):
		var z: Array = p["zone"]
		d.has_zone = true
		d.zone_x_min = float(z[0])
		d.zone_x_max = float(z[1])
		d.zone_y_min = float(z[2])
		d.zone_y_max = float(z[3])


	d.charge_paddle_offset = _vec3_from_dict(p, "charge_offset", Vector3.ZERO)
	d.charge_paddle_rotation_deg = _vec3_from_dict(p, "charge_rot", Vector3.ZERO)
	d.charge_body_rotation_deg = float(p.get("charge_body_deg", p.get("charge_body_rot_deg", 0.0)))
	d.charge_hip_coil_deg = float(p.get("charge_hip_deg", 0.0))
	d.charge_back_foot_load = float(p.get("charge_load", 0.7))

	d.zone_forward_offset = float(p.get("zone_fwd", 0.5))


	d.ft_paddle_offset = _vec3_from_dict(p, "ft_offset", Vector3.ZERO)
	d.ft_paddle_rotation_deg = _vec3_from_dict(p, "ft_rot", Vector3.ZERO)
	d.ft_hip_uncoil_deg = float(p.get("ft_hip_deg", 0.0))
	d.ft_front_foot_load = float(p.get("ft_load", 0.85))
	d.ft_duration_strike = float(p.get("ft_strike", 0.09))
	d.ft_duration_sweep = float(p.get("ft_sweep", 0.18))
	d.ft_duration_settle = float(p.get("ft_settle", 0.15))
	d.ft_duration_hold = float(p.get("ft_hold", 0.12))
	d.ft_ease_curve = int(p.get("ft_curve", 0))

	return d
