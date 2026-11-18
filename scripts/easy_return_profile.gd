extends RefCounted



const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Profiles = preload("res://scripts/shot_profile.gd")

static func solve(physics: ShotPhysics, origin: Vector3, receiver: Vector3, 
		may_volley: bool) -> Dictionary:


	var lane_offset: float = randf_range(0.28, 0.7) * (-1.0 if randf() < 0.5 else 1.0)
	if randf() < 0.1: lane_offset *= 1.35
	var receive_x: float = clampf(receiver.x + lane_offset, -2.45, 2.45)
	var receive_z: float = clampf(receiver.z - 0.65, 1.55, 6.0)
	var volley: bool = may_volley and receiver.z <= 3.8


	var bounce_gap: float = clampf((receive_z - origin.z) * 0.17, 0.5, 1.5) * randf_range(0.9, 1.1)
	var landing_z: float = receive_z + randf_range(0.55, 0.85) if volley else receive_z - bounce_gap
	landing_z = clampf(landing_z, 1.15, 5.35)


	var landing_x: float = origin.x + (receive_x - origin.x) * (landing_z - origin.z) / maxf(receive_z - origin.z, 0.5)
	var target: = Vector3(clampf(landing_x, -2.7, 2.7), Flight.FLOOR_REST_Y, landing_z)
	var profile: Dictionary = Profiles.create(0, 0.12, "VOLLEY" if volley else "GROUNDSTROKE")
	var best: Dictionary = {}
	var best_score: float = INF





	var candidate_steps: Array[int] = [1, 2, 3, 4, 0, 5, 6, 7, 8]
	for candidate_index in range(candidate_steps.size()):
		if candidate_index == 4 and best_score < 3.0: break
		var duration: float = 0.85 + candidate_steps[candidate_index] * 0.15
		var launch: Dictionary = physics._solve_aim_candidate(origin, target, profile, duration, 0.0, "", 0.24)
		if launch.is_empty(): continue
		var flight: Dictionary = Flight.trace(origin, launch.velocity, launch.omega, 4.0, 2, false)
		var receive: Dictionary = {}
		var peak: float = origin.y
		for sample in flight.samples:
			peak = maxf(peak, sample.pos.y)
			if receive.is_empty() and sample.pos.z >= receive_z: receive = sample
		var score: float = float(launch.target_error) * 30.0
		if not launch.feasible: score += 200.0
		if receive.is_empty():
			score += 100.0
		else:
			var height: float = receive.pos.y


			score += absf(height - 1.0) * 3.0
			score += maxf(0.7 - height, 0.0) * 12.0
			score += maxf(height - 1.55, 0.0) * 8.0
			score += maxf(1.05 - float(receive.time), 0.0) * 15.0
			score += maxf(receive.vel.length() - 7.0, 0.0) * 2.0
			if int(receive.bounces) != (0 if volley else 1): score += 80.0


		score += maxf(peak - 3.25, 0.0) * 3.0 + launch.velocity.length() * 0.06
		if score < best_score:
			best_score = score
			best = launch
			best["easy_volley"] = volley
			best["receive_plane"] = receive_z
			best["receive_height"] = receive.pos.y if not receive.is_empty() else -1.0
			best["receive_time"] = receive.get("time", -1.0)
	best.erase("_score")
	return best
