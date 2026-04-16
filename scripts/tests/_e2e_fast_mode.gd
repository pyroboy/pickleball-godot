
extends Node
func _ready() -> void:
	var ts = get_node("/root/TimeScale")
	ts.set_test_fast_forward(10.0)
	await get_tree().create_timer(0.5).timeout
	var game = get_node("/root/Game")
	var practice = game.get_node("practice_launcher")
	practice.launch_ball()
	print("[E2E] 10x speed ball launched")
