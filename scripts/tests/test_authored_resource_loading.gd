extends SceneTree



const Postures = preload("res://scripts/posture_library.gd")
const Bases = preload("res://scripts/base_pose_library.gd")
const POSTURE_FILES: Array[String] = ["00_forehand.tres", "01_forward.tres", "02_backhand.tres", "03_medium_overhead.tres", "04_high_overhead.tres", "05_low_forehand.tres", "06_low_forward.tres", "07_low_backhand.tres", "08_charge_forehand.tres", "09_charge_backhand.tres", "10_wide_forehand.tres", "11_wide_backhand.tres", "12_volley_ready.tres", "13_mid_low_forehand.tres", "14_mid_low_backhand.tres", "15_mid_low_forward.tres", "16_mid_low_wide_forehand.tres", "17_mid_low_wide_backhand.tres", "18_low_wide_forehand.tres", "19_low_wide_backhand.tres", "20_ready.tres"]
const BASE_FILES: Array[String] = ["00_athletic_ready.tres", "01_split_step.tres", "02_recovery_ready.tres", "03_kitchen_neutral.tres", "04_dink_base.tres", "05_drop_reset_base.tres", "06_punch_volley_ready.tres", "07_dink_volley_ready.tres", "08_deep_volley_ready.tres", "09_groundstroke_base.tres", "10_lob_defense_base.tres", "11_forehand_lunge.tres", "12_backhand_lunge.tres", "13_low_scoop_lunge.tres", "14_overhead_prep.tres", "15_jump_takeoff.tres", "16_air_smash.tres", "17_landing_recovery.tres", "18_lateral_shuffle.tres", "19_crossover_run.tres", "20_backpedal.tres", "21_decel_plant.tres"]
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func same_stored_value(a: Variant, b: Variant) -> bool:
	if a is Resource or b is Resource:
		if not a is Resource or not b is Resource: return false
		if a.get_script() != b.get_script(): return false
		for property in a.get_property_list():
			var key: String = property.name
			if int(property.usage) & PROPERTY_USAGE_STORAGE == 0 or key in ["resource_path", "resource_name", "resource_local_to_scene", "script"]: continue
			if not same_stored_value(a.get(key), b.get(key)): return false
		return true
	if a is Array or b is Array:
		if not a is Array or not b is Array or a.size() != b.size(): return false
		for i in range(a.size()):
			if not same_stored_value(a[i], b[i]): return false
		return true
	if a is Dictionary or b is Dictionary:
		if not a is Dictionary or not b is Dictionary or a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_stored_value(a[key], b[key]): return false
		return true
	return a == b
func verify_library(library, directory: String, expected: Array[String], id_property: String) -> void :
	var listed: PackedStringArray = ResourceLoader.list_directory(directory)
	check(library.all_definitions().size() == expected.size(), directory + " authored count")
	var ids: Dictionary = {}
	for file_name in expected:
		var path: = directory + file_name
		check(listed.has(file_name), path + " retains original exported resource name")
		check(ResourceLoader.exists(path), path + " resolves through resource loader")
		var reference: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if reference == null:
			check(false, path + " direct authored reference failed")
			continue
		var id: int = reference.get(id_property)
		check( not ids.has(id), path + " unique authored ID")
		ids[id] = true
		var actual: Resource = library.get_def(id)
		check(actual != null, path + " library ID exists")
		if actual == null: continue
		check(actual.resource_path == path, path + " came from authored resource, not fallback")
		check(same_stored_value(actual, reference), path + " all stored fields match authored data")
func run() -> void :
	create_timer(20).timeout.connect( func(): push_error("Authored resource loading timeout");quit(2))
	var postures = Postures.new()
	var bases = Bases.new()
	verify_library(postures, Postures.DATA_DIR, POSTURE_FILES, "posture_id")
	verify_library(bases, Bases.DATA_DIR, BASE_FILES, "base_pose_id")

	postures.load_or_default()
	bases.load_or_default()
	verify_library(postures, Postures.DATA_DIR, POSTURE_FILES, "posture_id")
	verify_library(bases, Bases.DATA_DIR, BASE_FILES, "base_pose_id")
	check( not is_equal_approx(postures.get_def(0).paddle_forehand_mul, 0.55), "authored forehand differs from old 0.55 fallback")
	check( not is_equal_approx(postures.get_def(20).paddle_y_offset, -0.28), "authored ready differs from old -0.28 fallback")

	var changed: Resource = postures.get_def(0).duplicate(true)
	changed.paddle_forehand_mul += 0.01
	check( not same_stored_value(changed, postures.get_def(0)), "field comparison detects changed paddle geometry")
	changed = postures.get_def(0).duplicate(true)
	check(changed.windup_body != null, "authored forehand has nested windup keyframe")
	if changed.windup_body != null:
		changed.windup_body.values["body_pitch_deg"] = float(changed.windup_body.values.get("body_pitch_deg", 0.0)) + 1.0
		check( not same_stored_value(changed, postures.get_def(0)), "field comparison detects changed nested body keyframe")
	for failure in failures: push_error(failure)
	print("AUTHORED RESOURCE LOADING: %d checks, %d failures; 21 stroke + 22 base resources and reload verified" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
