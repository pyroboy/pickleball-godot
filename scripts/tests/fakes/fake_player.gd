class_name FakePlayer extends Node
## Plain RefCounted stub matching the scorer's view of a player. Mirrors the
## minimum surface of scripts/player.gd that RallyScorer reads:
##   - global_position (Vector3)
##   - get_player_num() (int, 0 = Blue, 1 = Red)
##   - get_paddle_position() (Vector3)
##
## Use in tests:
##   var p := FakePlayer.new(0, Vector3(1.5, 1.0, 6.8))
##   p.paddle_position = Vector3(1.8, 1.0, 6.8)  # optional, defaults to body

var global_position: Vector3 = Vector3.ZERO
var paddle_position: Vector3 = Vector3.ZERO   # test-settable override for paddle
var _num: int = 0

func _init(num: int = 0, pos: Vector3 = Vector3.ZERO) -> void:
	_num = num
	global_position = pos
	paddle_position = pos  # default paddle = body position unless overridden

func get_player_num() -> int:
	return _num

func get_paddle_position() -> Vector3:
	return paddle_position
