class_name FakeGame extends RefCounted
## RefCounted stub matching the surface of scripts/game.gd that PlayerAIBrain
## calls in _compute_ai_shot_velocity() and _apply_ai_hit().
## Three methods delegate to ShotPhysics (no setup() needed for pure computation):
##   - compute_shot_spin(shot_type, vel, charge_ratio, player_num, posture)
##   - compute_sweet_spot_speed(ball_pos, paddle_pos, velocity)
##   - compute_sweet_spot_spin(ball_pos, paddle_pos, velocity)
## Use in tests:
##   var game := FakeGame.new()

var _Shot := ShotPhysics.new()

func compute_shot_spin(shot_type: String, vel: Vector3, charge_ratio: float, player_num: int, posture: int) -> Vector3:
	return _Shot.compute_shot_spin(shot_type, vel, charge_ratio, player_num, posture)

func compute_sweet_spot_speed(ball_pos: Vector3, paddle_pos: Vector3, velocity: Vector3) -> float:
	return _Shot.compute_sweet_spot_speed(ball_pos, paddle_pos, velocity)

func compute_sweet_spot_spin(ball_pos: Vector3, paddle_pos: Vector3, velocity: Vector3) -> Vector3:
	return _Shot.compute_sweet_spot_spin(ball_pos, paddle_pos, velocity)
