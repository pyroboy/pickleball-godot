class_name FakePlayer extends Node










var global_position: Vector3 = Vector3.ZERO
var paddle_position: Vector3 = Vector3.ZERO
var _num: int = 0

func _init(num: int = 0, pos: Vector3 = Vector3.ZERO) -> void :
	_num = num
	global_position = pos
	paddle_position = pos

func get_player_num() -> int:
	return _num

func get_paddle_position() -> Vector3:
	return paddle_position
