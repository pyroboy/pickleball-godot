class_name BasePoseLibrary extends RefCounted

const _BasePoseDefinition = preload("res://scripts/base_pose_definition.gd")

const DATA_DIR := "res://data/base_poses/"

var _by_id: Dictionary = {}
var definitions: Array = []

static var _singleton: BasePoseLibrary = null


static func instance() -> BasePoseLibrary:
	if _singleton == null:
		_singleton = load("res://scripts/base_pose_library.gd").new()
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
	for def in definitions:
		_by_id[def.base_pose_id] = def


func get_def(base_pose_id: int):
	return _by_id.get(base_pose_id, null)


func has_def(base_pose_id: int) -> bool:
	return _by_id.has(base_pose_id)


func all_definitions() -> Array:
	return definitions


func _load_from_disk() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(DATA_DIR + file_name)
			if res != null:
				definitions.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()


func _build_defaults() -> void:
	definitions.append(_make(0, "Athletic Ready", {
		"intent": 0, "mix": 0.88, "stance": 0.44, "crouch": 0.12,
		"front": 0.08, "back": -0.08, "body_yaw": 8.0, "body_pitch": 4.0,
		"torso_pitch": 6.0, "track": 0.95, "left_mode": 1,
	}))
	definitions.append(_make(1, "Split Step", {
		"intent": 0, "mix": 0.92, "stance": 0.52, "crouch": 0.20,
		"front": 0.02, "back": -0.02, "torso_pitch": 8.0, "body_pitch": 6.0,
		"recovery": 0.10, "split_hop": 0.05, "left_mode": 1,
	}))
	definitions.append(_make(2, "Recovery Ready", {
		"intent": 0, "mix": 0.86, "stance": 0.42, "crouch": 0.14,
		"front": 0.05, "back": -0.05, "torso_pitch": 5.0, "body_pitch": 5.0,
		"recovery": 0.16, "left_mode": 1,
	}))
	definitions.append(_make(3, "Kitchen Neutral", {
		"intent": 0, "mix": 0.86, "stance": 0.38, "crouch": 0.10,
		"front": 0.10, "back": -0.04, "torso_pitch": 4.0, "left_mode": 1,
	}))
	definitions.append(_make(4, "Dink Base", {
		"intent": 1, "mix": 0.82, "stance": 0.42, "crouch": 0.24,
		"front": 0.10, "back": -0.08, "torso_pitch": 12.0, "body_pitch": 8.0,
		"track": 1.0, "left_mode": 1,
	}))
	definitions.append(_make(5, "Drop Reset Base", {
		"intent": 2, "mix": 0.80, "stance": 0.46, "crouch": 0.20,
		"front": 0.12, "back": -0.10, "torso_pitch": 10.0, "body_pitch": 7.0,
		"left_mode": 1,
	}))
	definitions.append(_make(6, "Punch Volley Ready", {
		"intent": 3, "mix": 0.78, "stance": 0.40, "crouch": 0.15,
		"front": 0.12, "back": -0.06, "body_pitch": 4.0, "left_mode": 1,
		"right_shoulder": Vector3(-2.0, 4.0, 4.0),
	}))
	definitions.append(_make(7, "Dink Volley Ready", {
		"intent": 4, "mix": 0.82, "stance": 0.40, "crouch": 0.20,
		"front": 0.08, "back": -0.06, "torso_pitch": 9.0, "body_pitch": 6.0,
		"left_mode": 1,
	}))
	definitions.append(_make(8, "Deep Volley Ready", {
		"intent": 5, "mix": 0.76, "stance": 0.44, "crouch": 0.14,
		"front": 0.10, "back": -0.08, "torso_pitch": 5.0, "left_mode": 1,
	}))
	definitions.append(_make(9, "Groundstroke Base", {
		"intent": 6, "mix": 0.72, "stance": 0.50, "crouch": 0.15,
		"front": 0.15, "back": -0.16, "body_yaw": 14.0, "torso_yaw": 10.0,
		"torso_pitch": 6.0, "left_mode": 0,
	}))
	definitions.append(_make(10, "Lob Defense Base", {
		"intent": 7, "mix": 0.70, "stance": 0.47, "crouch": 0.12,
		"front": 0.02, "back": -0.14, "body_pitch": -5.0, "torso_pitch": -6.0,
		"head_pitch": -8.0, "left_mode": 3,
	}))
	definitions.append(_make(11, "Forehand Lunge", {
		"intent": 6, "mix": 0.92, "stance": 0.68, "crouch": 0.28,
		"front": 0.18, "back": -0.20, "weight": 0.45, "lead": 0,
		"body_yaw": 16.0, "body_roll": -8.0, "torso_pitch": 12.0,
		"r_foot": Vector3(0.18, 0.0, 0.18), "l_foot": Vector3(-0.08, 0.0, -0.16),
		"recovery": 0.18, "lunge": 0.95,
	}))
	definitions.append(_make(12, "Backhand Lunge", {
		"intent": 6, "mix": 0.92, "stance": 0.68, "crouch": 0.28,
		"front": 0.18, "back": -0.20, "weight": -0.45, "lead": 1,
		"body_yaw": -16.0, "body_roll": 8.0, "torso_pitch": 12.0,
		"r_foot": Vector3(0.08, 0.0, -0.16), "l_foot": Vector3(-0.18, 0.0, 0.18),
		"recovery": 0.18, "lunge": 0.95,
	}))
	definitions.append(_make(13, "Low Scoop Lunge", {
		"intent": 2, "mix": 0.94, "stance": 0.64, "crouch": 0.34,
		"front": 0.14, "back": -0.18, "torso_pitch": 16.0, "body_pitch": 12.0,
		"track": 1.0, "left_mode": 0, "recovery": 0.18, "lunge": 0.90,
	}))
	definitions.append(_make(14, "Overhead Prep", {
		"intent": 8, "mix": 0.66, "stance": 0.48, "crouch": 0.10,
		"front": 0.04, "back": -0.18, "body_pitch": -8.0, "torso_pitch": -10.0,
		"torso_yaw": 4.0, "head_pitch": -10.0, "left_mode": 3,
		"left_hand": Vector3(0.0, 0.08, 0.10),
	}))
	definitions.append(_make(15, "Jump Takeoff", {
		"intent": 8, "mix": 0.78, "stance": 0.44, "crouch": 0.22,
		"front": 0.04, "back": -0.10, "body_pitch": 10.0, "torso_pitch": 8.0,
		"jump_window": 0.36, "left_mode": 3,
	}))
	definitions.append(_make(16, "Air Smash", {
		"intent": 8, "mix": 0.58, "stance": 0.36, "crouch": 0.04,
		"front": 0.00, "back": -0.04, "body_pitch": -6.0, "torso_pitch": -8.0,
		"left_mode": 3, "left_hand": Vector3(0.0, 0.12, 0.16),
	}))
	definitions.append(_make(17, "Landing Recovery", {
		"intent": 0, "mix": 0.90, "stance": 0.50, "crouch": 0.24,
		"front": 0.10, "back": -0.12, "body_pitch": 12.0, "torso_pitch": 10.0,
		"recovery": 0.16, "landing": 0.16, "left_mode": 1,
	}))
	definitions.append(_make(18, "Lateral Shuffle", {
		"intent": 0, "mix": 0.84, "stance": 0.52, "crouch": 0.12,
		"front": 0.06, "back": -0.06, "body_roll": 3.0, "torso_pitch": 4.0,
		"left_mode": 1,
	}))
	definitions.append(_make(19, "Crossover Run", {
		"intent": 0, "mix": 0.70, "stance": 0.56, "crouch": 0.08,
		"front": 0.18, "back": -0.18, "body_pitch": 10.0, "torso_pitch": 8.0,
		"left_mode": 0,
	}))
	definitions.append(_make(20, "Backpedal", {
		"intent": 7, "mix": 0.74, "stance": 0.48, "crouch": 0.08,
		"front": -0.04, "back": -0.06, "body_pitch": -6.0, "torso_pitch": -4.0,
		"head_pitch": -6.0, "left_mode": 1,
	}))
	definitions.append(_make(21, "Decel Plant", {
		"intent": 0, "mix": 0.88, "stance": 0.55, "crouch": 0.18,
		"front": 0.22, "back": -0.12, "body_pitch": 12.0, "torso_pitch": 10.0,
		"weight": 0.18, "recovery": 0.14, "left_mode": 1,
	}))


func _make(id: int, name: String, props: Dictionary):
	var def = _BasePoseDefinition.new()
	def.base_pose_id = id
	def.display_name = name
	def.canonical_intent = props.get("intent", 0)
	def.stroke_overlay_mix = props.get("mix", 0.82)
	def.recovery_time = props.get("recovery", 0.12)
	def.landing_lockout_time = props.get("landing", 0.12)
	def.jump_window = props.get("jump_window", 0.36)
	def.split_step_hop_height = props.get("split_hop", 0.0)
	def.lunge_distance = props.get("lunge", 0.0)
	def.right_hand_offset = props.get("right_hand", Vector3.ZERO)
	def.right_elbow_pole = props.get("right_elbow", Vector3.ZERO)
	def.right_shoulder_rotation_deg = props.get("right_shoulder", Vector3.ZERO)
	def.left_hand_mode = props.get("left_mode", 0)
	def.left_hand_offset = props.get("left_hand", Vector3.ZERO)
	def.left_elbow_pole = props.get("left_elbow", Vector3.ZERO)
	def.left_shoulder_rotation_deg = props.get("left_shoulder", Vector3.ZERO)
	def.stance_width = props.get("stance", 0.35)
	def.front_foot_forward = props.get("front", 0.12)
	def.back_foot_back = props.get("back", -0.08)
	def.right_foot_yaw_deg = props.get("right_yaw", 0.0)
	def.left_foot_yaw_deg = props.get("left_yaw", 0.0)
	def.right_knee_pole = props.get("right_knee", Vector3.ZERO)
	def.left_knee_pole = props.get("left_knee", Vector3.ZERO)
	def.right_foot_offset = props.get("r_foot", Vector3.ZERO)
	def.left_foot_offset = props.get("l_foot", Vector3.ZERO)
	def.lead_foot = props.get("lead", 0)
	def.crouch_amount = props.get("crouch", 0.0)
	def.weight_shift = props.get("weight", 0.0)
	def.hip_yaw_deg = props.get("hip_yaw", 0.0)
	def.torso_yaw_deg = props.get("torso_yaw", 0.0)
	def.torso_pitch_deg = props.get("torso_pitch", 0.0)
	def.torso_roll_deg = props.get("torso_roll", 0.0)
	def.spine_curve_deg = props.get("spine", 0.0)
	def.body_yaw_deg = props.get("body_yaw", 0.0)
	def.body_pitch_deg = props.get("body_pitch", 0.0)
	def.body_roll_deg = props.get("body_roll", 0.0)
	def.head_yaw_deg = props.get("head_yaw", 0.0)
	def.head_pitch_deg = props.get("head_pitch", 0.0)
	def.head_track_ball_weight = props.get("track", 1.0)
	return def
