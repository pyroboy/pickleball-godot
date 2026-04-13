class_name PostureLibrary extends RefCounted

const _PostureDefinition = preload("res://scripts/posture_definition.gd")

## Loads and indexes the 21 PostureDefinition Resources.
##
## Phase 1: Library is NOT yet consumed by runtime code. It can be instantiated
## and inspected, but player_paddle_posture.gd / player_hitting.gd /
## player_body_animation.gd still use their original hardcoded switches.
## Wiring happens in Phase 2.
##
## Loading strategy (in priority order):
##   1. Load all res://data/postures/*.tres files if the directory exists
##   2. Otherwise fall back to _build_defaults() — the in-code copy of the
##      current hardcoded values. Gameplay stays byte-identical either way.
##
## To snapshot current defaults to disk as .tres files, run the editor script
## at tools/extract_postures.gd (File → Run in the Godot editor).

const DATA_DIR := "res://data/postures/"

var _by_id: Dictionary = {}   # posture_id -> PostureDefinition
var definitions: Array = []

## Singleton: lazily initialized on first access.
static var _singleton: PostureLibrary = null


static func instance() -> PostureLibrary:
	if _singleton == null:
		_singleton = load("res://scripts/posture_library.gd").new()
	return _singleton


func _init() -> void:
	load_or_default()


func load_or_default() -> void:
	definitions.clear()
	_by_id.clear()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DATA_DIR)):
		_load_from_disk()
	if definitions.is_empty():
		_build_defaults()
	for d in definitions:
		_by_id[d.posture_id] = d


func get_def(posture_id: int):
	return _by_id.get(posture_id, null)


func has_def(posture_id: int) -> bool:
	return _by_id.has(posture_id)


func all_definitions():
	return definitions


func _load_from_disk() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			var res: Resource = load(DATA_DIR + f)
			if res != null:
				definitions.append(res)
		f = dir.get_next()
	dir.list_dir_end()


## Source-of-truth extraction of every hardcoded posture value.
##
## These numbers are LITERAL COPIES of:
##   - scripts/player_paddle_posture.gd:14-83   (paddle constants + zones)
##   - scripts/player_paddle_posture.gd:50-76   (POSTURE_ZONES)
##   - scripts/player_paddle_posture.gd:1313-1365 (get_posture_offset_for)
##   - scripts/player_paddle_posture.gd:1367-1406 (rotation offsets)
##
## If you change a number here, you MUST also change it in the source file
## (Phase 1) — they are duplicated intentionally for byte-identical migration.
## Phase 2 will replace the source file's hardcoded functions with library
## lookups, at which point this becomes the single source of truth.
func _build_defaults() -> void:
	# Enum IDs from scripts/player.gd:42-64
	var FOREHAND            := 0
	var FORWARD             := 1
	var BACKHAND            := 2
	var MEDIUM_OVERHEAD     := 3
	var HIGH_OVERHEAD       := 4
	var LOW_FOREHAND        := 5
	var LOW_FORWARD         := 6
	var LOW_BACKHAND        := 7
	var CHARGE_FOREHAND     := 8
	var CHARGE_BACKHAND     := 9
	var WIDE_FOREHAND       := 10
	var WIDE_BACKHAND       := 11
	var VOLLEY_READY        := 12
	var MID_LOW_FOREHAND    := 13
	var MID_LOW_BACKHAND    := 14
	var MID_LOW_FORWARD     := 15
	var MID_LOW_WIDE_FH     := 16
	var MID_LOW_WIDE_BH     := 17
	var LOW_WIDE_FOREHAND   := 18
	var LOW_WIDE_BACKHAND   := 19
	var READY               := 20

	# Family: 0=FH, 1=BH, 2=center, 3=overhead
	# Tier:   0=LOW, 1=MID_LOW, 2=NORMAL, 3=OVERHEAD
	# Sign source: 0=None, 1=SwingSign, 2=FwdSign

	# ── Normal tier ──────────────────────────────────────────────
	definitions.append(_make(FOREHAND, "Forehand", 0, 2, {
		"pf": 0.5, "pfw": 0.4, "py": 0.0,
		"roll_signed": 45.0, "roll_src": 1,
		"zone": [0.2, 0.55, 0.5, 1.0],
		"charge_offset": Vector3(0.05, 0.20, -0.30),
		"charge_rot": Vector3(-30.0, 35.0, -15.0),
		"charge_body_deg": 30.0,
		"charge_hip_deg": 15.0,
		"ft_offset": Vector3(0.15, 0.38, -0.20),
		"ft_rot": Vector3(20.0, 25.0, -30.0),
		"ft_hip_deg": 20.0,
		"ft_load": 0.85,
	}))

	definitions.append(_make(BACKHAND, "Backhand", 1, 2, {
		"pf": -0.42, "pfw": 0.36, "py": 0.0,  # 0.4 * 0.9 = 0.36
		"zone": [-0.55, -0.2, 0.5, 1.0],
		"charge_offset": Vector3(-0.05, 0.20, -0.28),
		"charge_rot": Vector3(-30.0, -35.0, 15.0),
		"charge_body_deg": 30.0,
		"charge_hip_deg": 15.0,
		"ft_offset": Vector3(-0.15, 0.36, -0.18),
		"ft_rot": Vector3(20.0, -25.0, 30.0),
		"ft_hip_deg": 20.0,
		"ft_load": 0.85,
	}))

	definitions.append(_make(WIDE_FOREHAND, "Wide Forehand", 0, 2, {
		"pf": 0.85, "pfw": 0.55, "py": 0.0,
		"yaw_signed": 12.0, "yaw_src": 1,
		"roll_signed": 35.0, "roll_src": 1,
		"zone": [0.5, 1.1, 0.48, 1.0],
		"charge_offset": Vector3(0.08, 0.22, -0.32),
		"charge_rot": Vector3(-32.0, 40.0, -18.0),
		"charge_body_deg": 32.0,
		"charge_hip_deg": 16.0,
		"ft_offset": Vector3(0.18, 0.40, -0.22),
		"ft_rot": Vector3(22.0, 28.0, -32.0),
		"ft_hip_deg": 22.0,
		"ft_load": 0.87,
	}))

	definitions.append(_make(WIDE_BACKHAND, "Wide Backhand", 1, 2, {
		"pf": -0.72, "pfw": 0.52, "py": 0.0,
		"yaw_signed": -10.0, "yaw_src": 1,
		"roll_signed": -30.0, "roll_src": 1,
		"zone": [-1.1, -0.5, 0.48, 1.0],
		"charge_offset": Vector3(-0.08, 0.22, -0.30),
		"charge_rot": Vector3(-32.0, -40.0, 18.0),
		"charge_body_deg": 32.0,
		"charge_hip_deg": 16.0,
		"ft_offset": Vector3(-0.18, 0.38, -0.20),
		"ft_rot": Vector3(22.0, -28.0, 32.0),
		"ft_hip_deg": 22.0,
		"ft_load": 0.87,
	}))

	definitions.append(_make(FORWARD, "Forward", 2, 2, {
		# FORWARD falls through get_posture_offset_for default: forward * 0.42
		"pf": 0.0, "pfw": 0.42, "py": 0.0,
		"zone": [-0.15, 0.15, 0.5, 1.0],
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
		"pf": 0.0, "pfw": 0.50, "py": 0.12,
		"pitch_signed": -15.0, "pitch_src": 2,
		"zone": [-0.2, 0.2, 0.55, 0.9],
		"charge_offset": Vector3(0.0, 0.15, -0.15),
		"charge_rot": Vector3(-18.0, 0.0, 0.0),
		"charge_body_deg": 12.0,
		"charge_hip_deg": 8.0,
		"ft_offset": Vector3(0.0, 0.28, 0.06),
		"ft_rot": Vector3(28.0, 0.0, 14.0),
		"ft_hip_deg": 16.0,
		"ft_load": 0.80,
	}))

	definitions.append(_make(READY, "Ready", 2, 2, {
		"pf": 0.0, "pfw": 0.55, "py": -0.28,
		"pitch_signed": -55.0, "pitch_src": 2,
		"yaw_signed": -15.0, "yaw_src": 1,
		# READY has no zone in POSTURE_ZONES
		"charge_offset": Vector3(0.0, 0.0, 0.0),
		"charge_rot": Vector3(0.0, 0.0, 0.0),
		"charge_body_deg": 0.0,
		"charge_hip_deg": 0.0,
		"ft_offset": Vector3(0.0, 0.0, 0.0),
		"ft_rot": Vector3(0.0, 0.0, 0.0),
		"ft_hip_deg": 0.0,
		"ft_load": 0.85,
	}))

	# ── Overhead tier ────────────────────────────────────────────
	definitions.append(_make(MEDIUM_OVERHEAD, "Medium Overhead", 3, 3, {
		"pf": 0.5, "pfw": 0.7, "py": 0.6,
		"zone": [-0.35, 0.35, 0.8, 1.3],
		"charge_offset": Vector3(0.0, 0.38, -0.20),
		"charge_rot": Vector3(-46.0, 0.0, -8.0),
		"charge_body_deg": 20.0,
		"charge_hip_deg": 10.0,
		"ft_offset": Vector3(0.0, -0.35, 0.45),
		"ft_rot": Vector3(72.0, 0.0, 6.0),
		"ft_hip_deg": 25.0,
		"ft_load": 0.88,
	}))

	definitions.append(_make(HIGH_OVERHEAD, "High Overhead", 3, 3, {
		"pf": 0.5, "pfw": 0.8, "py": 1.1,
		"zone": [-0.35, 0.35, 1.1, 1.8],
		"charge_offset": Vector3(0.0, 0.45, -0.18),
		"charge_rot": Vector3(-62.0, 0.0, -8.0),
		"charge_body_deg": 25.0,
		"charge_hip_deg": 12.0,
		"ft_offset": Vector3(0.0, -0.42, 0.50),
		"ft_rot": Vector3(82.0, 0.0, 6.0),
		"ft_hip_deg": 28.0,
		"ft_load": 0.90,
	}))

	# ── Mid-low tier ─────────────────────────────────────────────
	definitions.append(_make(MID_LOW_FOREHAND, "Mid-Low Forehand", 0, 1, {
		"pf": 0.5, "pfw": 0.50, "py": -0.18,
		"pitch_signed": 20.0, "pitch_src": 2,
		"roll_signed": 38.0, "roll_src": 1,
		"zone": [0.2, 0.55, 0.15, 0.52],
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
		"pf": -0.42, "pfw": 0.48, "py": -0.18,
		"pitch_signed": 20.0, "pitch_src": 2,
		"roll_signed": -32.0, "roll_src": 1,
		"zone": [-0.55, -0.2, 0.15, 0.52],
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
		"pf": 0.0, "pfw": 0.52, "py": -0.18,
		"pitch_signed": 25.0, "pitch_src": 2,
		"zone": [-0.15, 0.15, 0.15, 0.52],
		"charge_offset": Vector3(0.0, 0.10, -0.16),
		"charge_rot": Vector3(-18.0, 0.0, 0.0),
		"charge_body_deg": 14.0,
		"charge_hip_deg": 9.0,
		"ft_offset": Vector3(0.0, 0.30, 0.07),
		"ft_rot": Vector3(28.0, 0.0, 15.0),
		"ft_hip_deg": 16.0,
		"ft_load": 0.80,
	}))

	definitions.append(_make(MID_LOW_WIDE_FH, "Mid-Low Wide Forehand", 0, 1, {
		"pf": 0.88, "pfw": 0.58, "py": -0.20,
		"pitch_signed": 18.0, "pitch_src": 2,
		"yaw_signed": 10.0, "yaw_src": 1,
		"roll_signed": 30.0, "roll_src": 1,
		"zone": [0.5, 1.1, 0.1, 0.50],
		"charge_offset": Vector3(0.10, 0.18, -0.30),
		"charge_rot": Vector3(-30.0, 42.0, -18.0),
		"charge_body_deg": 30.0,
		"charge_hip_deg": 15.0,
		"ft_offset": Vector3(0.16, 0.38, -0.19),
		"ft_rot": Vector3(20.0, 27.0, -30.0),
		"ft_hip_deg": 21.0,
		"ft_load": 0.85,
	}))

	definitions.append(_make(MID_LOW_WIDE_BH, "Mid-Low Wide Backhand", 1, 1, {
		"pf": -0.74, "pfw": 0.54, "py": -0.20,
		"pitch_signed": 18.0, "pitch_src": 2,
		"yaw_signed": -8.0, "yaw_src": 1,
		"roll_signed": -28.0, "roll_src": 1,
		"zone": [-1.1, -0.5, 0.1, 0.50],
		"charge_offset": Vector3(-0.10, 0.18, -0.28),
		"charge_rot": Vector3(-30.0, -42.0, 18.0),
		"charge_body_deg": 30.0,
		"charge_hip_deg": 15.0,
		"ft_offset": Vector3(-0.16, 0.36, -0.18),
		"ft_rot": Vector3(20.0, -27.0, 30.0),
		"ft_hip_deg": 21.0,
		"ft_load": 0.85,
	}))

	# ── Low tier (inverted paddle, roll 180) ─────────────────────
	definitions.append(_make(LOW_FOREHAND, "Low Forehand", 0, 0, {
		"pf": 0.5, "pfw": 0.55, "py": -0.62,
		"roll_base": 180.0, "roll_signed": 10.0, "roll_src": 1,
		"clearance": 0.45,
		"zone": [0.2, 0.55, -0.2, 0.2],
		"charge_offset": Vector3(0.05, 0.18, -0.28),
		"charge_rot": Vector3(-25.0, 35.0, -15.0),
		"charge_body_deg": 25.0,
		"charge_hip_deg": 12.0,
		"ft_offset": Vector3(0.12, 0.32, -0.15),
		"ft_rot": Vector3(15.0, 20.0, -25.0),
		"ft_hip_deg": 18.0,
		"ft_load": 0.80,
	}))

	definitions.append(_make(LOW_BACKHAND, "Low Backhand", 1, 0, {
		"pf": -0.42, "pfw": 0.55, "py": -0.62,
		"roll_base": 180.0, "roll_signed": -10.0, "roll_src": 1,
		"clearance": 0.45,
		"zone": [-0.55, -0.2, -0.2, 0.2],
		"charge_offset": Vector3(-0.05, 0.18, -0.26),
		"charge_rot": Vector3(-25.0, -35.0, 15.0),
		"charge_body_deg": 25.0,
		"charge_hip_deg": 12.0,
		"ft_offset": Vector3(-0.12, 0.30, -0.14),
		"ft_rot": Vector3(15.0, -20.0, 25.0),
		"ft_hip_deg": 18.0,
		"ft_load": 0.80,
	}))

	definitions.append(_make(LOW_FORWARD, "Low Forward", 2, 0, {
		"pf": 0.0, "pfw": 0.55, "py": -0.62,
		"roll_base": 180.0,
		"clearance": 0.45,
		"zone": [-0.15, 0.15, -0.2, 0.2],
		"charge_offset": Vector3(0.0, 0.10, -0.16),
		"charge_rot": Vector3(-15.0, 0.0, 0.0),
		"charge_body_deg": 12.0,
		"charge_hip_deg": 8.0,
		"ft_offset": Vector3(0.0, 0.28, 0.06),
		"ft_rot": Vector3(25.0, 0.0, 14.0),
		"ft_hip_deg": 15.0,
		"ft_load": 0.78,
	}))

	definitions.append(_make(LOW_WIDE_FOREHAND, "Low Wide Forehand", 0, 0, {
		"pf": 0.90, "pfw": 0.60, "py": -0.62,
		"yaw_signed": 12.0, "yaw_src": 1,
		"roll_base": 180.0, "roll_signed": 8.0, "roll_src": 1,
		"clearance": 0.45,
		"zone": [0.5, 1.1, -0.2, 0.15],
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
		"pf": -0.78, "pfw": 0.56, "py": -0.62,
		"yaw_signed": -10.0, "yaw_src": 1,
		"roll_base": 180.0, "roll_signed": -8.0, "roll_src": 1,
		"clearance": 0.45,
		"zone": [-1.1, -0.5, -0.2, 0.15],
		"charge_offset": Vector3(-0.08, 0.15, -0.26),
		"charge_rot": Vector3(-26.0, -42.0, 16.0),
		"charge_body_deg": 26.0,
		"charge_hip_deg": 13.0,
		"ft_offset": Vector3(-0.14, 0.31, -0.15),
		"ft_rot": Vector3(16.0, -25.0, 28.0),
		"ft_hip_deg": 18.0,
		"ft_load": 0.82,
	}))

	# ── Charge tier (behind player) ──────────────────────────────
	# From player_paddle_posture.gd:1336-1340
	# forehand * PADDLE_SIDE_OFFSET(0.5) + forward * -PADDLE_CHARGE_FOREHAND_BEHIND(0.65) + (0, 0.35, 0)
	definitions.append(_make(CHARGE_FOREHAND, "Charge Forehand", 0, 2, {
		"pf": 0.5, "pfw": -0.65, "py": 0.35,
		# charge_offset = charged_position - contact_position = (fh*0.5 + fwd*-0.65 + up*0.35) - (fh*0.5 + fwd*0.4 + up*0.0) = fwd*(-1.05) + up*0.35
		"charge_offset": Vector3(0.0, 0.35, -1.05),
		"charge_rot": Vector3(-45.0, 35.0, -20.0),
		"charge_body_deg": 35.0,
	}))

	definitions.append(_make(CHARGE_BACKHAND, "Charge Backhand", 1, 2, {
		"pf": -0.42, "pfw": -0.65, "py": 0.35,
		# mirrored: fh*-0.42 + fwd*-0.65 + up*0.35 - (fh*-0.42 + fwd*0.36 + up*0.0) = fwd*(-1.01) + up*0.35
		"charge_offset": Vector3(0.0, 0.35, -1.01),
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

	# Charge fields
	d.charge_paddle_offset = _vec3_from_dict(p, "charge_offset", Vector3.ZERO)
	d.charge_paddle_rotation_deg = _vec3_from_dict(p, "charge_rot", Vector3.ZERO)
	d.charge_body_rotation_deg = float(p.get("charge_body_deg", p.get("charge_body_rot_deg", 0.0)))
	d.charge_hip_coil_deg = float(p.get("charge_hip_deg", 0.0))
	d.charge_back_foot_load = float(p.get("charge_load", 0.7))

	# Follow-through fields
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
