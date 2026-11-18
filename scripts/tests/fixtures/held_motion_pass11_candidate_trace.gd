extends "res://scripts/held_hit_motion.gd"
const Snapshot = preload("res://scripts/tests/fixtures/ready_tracking_parity_snapshot.gd")
var samples: Array = []
var sample_ids: Array[int] = []
var fits: Array = []
func _candidate(base: PostureDefinition, windup: PostureDefinition, data: Dictionary, amount: float, candidate: PostureDefinition = null, windup_basis_override = null) -> PostureDefinition:
	var result: PostureDefinition = super._candidate(base, windup, data, amount, candidate, windup_basis_override)
	samples.append({"amount": amount, "pose": Snapshot.pose(result)})
	sample_ids.append(result.get_instance_id())
	return result
func _fits_precomputed(pose: PostureDefinition, player, allowed: float) -> bool:
	var result: bool = super._fits_precomputed(pose, player, allowed)
	fits.append({"allowed": allowed, "fits": result})
	return result
