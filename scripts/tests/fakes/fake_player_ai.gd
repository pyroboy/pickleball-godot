class_name FakePlayerAI extends FakePlayer
## Fake player stub for AI tests. Mirrors the minimum surface of player.gd
## that PlayerAIBrain accesses in _compute_ai_shot_velocity / _simulate_landing.

var ai_desired_posture: int = 0
var min_z: float = -6.7
var max_z: float = 0.0
var paddle_posture: int = 0

func _init(player_num: int = 1, pos: Vector3 = Vector3.ZERO) -> void:
	super._init(player_num, pos)

func _get_posture_offset_for(posture: int) -> Vector3:
	return Vector3.ZERO
