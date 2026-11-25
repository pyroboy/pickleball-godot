extends DirectionalLight3D
## The real light on the shared sun (scripts/graphics/sun_light.gd, visual only): aimed
## along -Sun.to_sun() and aimed again when Sun.version moves (the sun turns with the camera
## after a change of ends). One int compare a frame; stops with the pause like everything.

const Sun := preload("res://scripts/graphics/sun_light.gd")

var _version := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # aimed from _process
	_aim()


func _process(_delta: float) -> void:
	if Sun.version != _version: _aim()


func _aim() -> void:
	_version = Sun.version
	# light travels away from the sun: the node's -Z along -Sun.to_sun()
	basis = Basis.looking_at(-Sun.to_sun(), Vector3.UP)
