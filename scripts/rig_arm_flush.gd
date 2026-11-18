extends Node
## Solves every player's deferred arm IK (PlayerPaddlePosture.ensure_arm_pose)
## once at the end of each physics tick and each rendered frame, so arms are
## posed exactly once per tick and are always current before drawing.
## Contact authority (physics priority 200) and hit checks ensure on demand first.

func _ready() -> void:
	process_priority = 100000
	process_physics_priority = 100000

func _physics_process(_delta: float) -> void:
	_flush()

func _process(_delta: float) -> void:
	_flush()

func _flush() -> void:
	var game = get_parent()
	if game == null or not game.has_method("get_players"): return
	for p in game.get_players():
		if "posture" in p and p.posture != null: p.posture.ensure_arm_pose()
