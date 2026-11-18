extends "res://scripts/tests/fixtures/ready_tracking_pass14_candidate_counted.gd"
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
var samples: Array = []
var sample_ids: Array[int] = []
func _sample_into(result: PostureDefinition, base_torso_yaw: float, base_basis: Basis, head_from_grip: Vector3, grip: Vector3, weight: float) -> void:
	super._sample_into(result, base_torso_yaw, base_basis, head_from_grip, grip, weight)
	samples.append({"weight": weight, "pose": Snapshot.pose(result)})
	sample_ids.append(result.get_instance_id())
