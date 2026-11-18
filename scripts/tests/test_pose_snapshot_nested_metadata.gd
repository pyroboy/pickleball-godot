extends SceneTree
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	var source: PostureDefinition = PostureDefinition.new()
	source.posture_id = 0
	var baseline: PostureDefinition = PostureDefinition.new()
	baseline.posture_id = 0
	baseline.set_meta("serve_phase_charge", .41)
	var key = BodyKey.new()
	key.values["torso_yaw_deg"] = 7.0
	key.set_meta("nested_key_metadata", {"payload": [1, 2, PackedFloat64Array([.125, .375])]})
	baseline.windup_body = key
	var nested: Resource = Resource.new()
	nested.set_meta("nested_number", 12.75)
	baseline.set_meta("nested_dictionary", {"items": [nested], "ordinary": "unchanged"})
	source.set_meta("mobile_serve_baseline", baseline)
	var original: Dictionary = Snapshot.pose(source)
	var clone: PostureDefinition = source.duplicate(true)
	check(Snapshot.pose(clone) == original, "independently deep-cloned resources compare by value, not Resource IDs")
	baseline.set_meta("serve_phase_charge", .42)
	check(Snapshot.pose(source) != original, "nested PostureDefinition metadata change is detected")
	baseline.set_meta("serve_phase_charge", .41)
	check(Snapshot.pose(source) == original, "restored nested metadata returns to exact equality")
	nested.set_meta("nested_number", 13.75)
	check(Snapshot.pose(source) != original, "Resource metadata inside nested dictionary/array is detected")
	nested.set_meta("nested_number", 12.75)
	key.set_meta("nested_key_metadata", {"payload": [1, 3, PackedFloat64Array([.125, .375])]})
	check(Snapshot.pose(source) != original, "authored keyframe Resource metadata change is detected")
	key.set_meta("nested_key_metadata", {"payload": [1, 2, PackedFloat64Array([.125, .375])]})
	check(Snapshot.pose(source) == original, "complete graph restores without snapshot mutation")

	# No arbitrary recursion cap: changing the last Resource remains visible.
	var root_resource: Resource = Resource.new(); var leaf: Resource = root_resource
	for unused in range(24):
		var child: Resource = Resource.new(); leaf.set_meta("next", child); leaf = child
	leaf.set_meta("last", 1)
	source.set_meta("deep_metadata", root_resource)
	var deep_before: Dictionary = Snapshot.pose(source)
	check(Snapshot.pose(source) == deep_before, "24-level graph equality stays shallow")
	leaf.set_meta("last", 2)
	check(Snapshot.pose(source) != deep_before, "24-level nested Resource metadata is fully captured")
	leaf.set_meta("last", 1)
	check(Snapshot.pose(source) == deep_before, "24-level graph restoration compares exactly")

	# All compound edges must be references, including mixed dictionary/array
	# chains much deeper than Godot's built-in Dictionary equality limit.
	var deep_array: Array = []
	var tail: Array = deep_array
	for unused in range(128):
		var next: Array = []
		tail.append({"next": next}); tail = next
	tail.append("before")
	var mixed_before: Dictionary = Snapshot.value(deep_array)
	check(Snapshot.value(deep_array) == mixed_before, "128-level mixed graph equality stays shallow")
	tail[0] = "after"
	check(Snapshot.value(deep_array) != mixed_before, "128-level mixed graph leaf changes are detected")
	tail[0] = "before"
	check(Snapshot.value(deep_array) == mixed_before, "128-level mixed graph restoration compares exactly")

	# Explicit graph references cover cycles without truncation or identity noise.
	var cycle_a: Resource = Resource.new(); cycle_a.set_meta("self", cycle_a)
	var cycle_b: Resource = Resource.new(); cycle_b.set_meta("self", cycle_b)
	check(Snapshot.value(cycle_a) == Snapshot.value(cycle_b), "equivalent resource cycles use stable graph references")
	cycle_b.set_meta("different", true)
	check(Snapshot.value(cycle_a) != Snapshot.value(cycle_b), "metadata next to a cycle remains visible")
	cycle_a.remove_meta("self"); cycle_b.remove_meta("self")
	var array_a: Array = []; array_a.append(array_a)
	var array_b: Array = []; array_b.append(array_b)
	check(Snapshot.value(array_a) == Snapshot.value(array_b), "array cycles use stable graph references")
	array_a.clear(); array_b.clear()
	var shared: Resource = Resource.new()
	check(Snapshot.value([shared, shared]) != Snapshot.value([Resource.new(), Resource.new()]), "alias relationships remain distinct from equal independent resources")

	var shared_base: PostureDefinition = PostureDefinition.new()
	var tracked_a: PostureDefinition = PostureDefinition.new(); var tracked_b: PostureDefinition = PostureDefinition.new()
	tracked_a.set_meta("ready_tracking_base", shared_base); tracked_b.set_meta("ready_tracking_base", shared_base)
	check(Snapshot.pose(tracked_a) == Snapshot.pose(tracked_b), "same intentional Ready base identity compares equal")
	tracked_b.set_meta("ready_tracking_base", shared_base.duplicate(true))
	check(Snapshot.pose(tracked_a) != Snapshot.pose(tracked_b), "top-level Ready base identity contract remains enforced")
	print("POSE_SNAPSHOT_NESTED_METADATA ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
