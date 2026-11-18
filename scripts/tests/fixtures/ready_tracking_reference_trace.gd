extends "res://scripts/tests/fixtures/ready_ball_tracking_code27_reference.gd"
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
var samples: Array = []
var sample_ids: Array[int] = []
func _sample(base: PostureDefinition, grip: Vector3, weight: float) -> PostureDefinition:
	var result: PostureDefinition = super._sample(base, grip, weight)
	samples.append({"weight": weight, "pose": Snapshot.pose(result)})
	sample_ids.append(result.get_instance_id())
	return result
