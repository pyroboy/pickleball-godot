extends Node
class_name CameraShake
## Trauma-based camera shake. Owned by CameraRig; applies offsets on top of
## the follow transform via Camera3D.h_offset / v_offset + a small roll on rotation.z.
##
## Call add_trauma(amount) to shake. Trauma decays automatically.
## The final shake magnitude is scaled by an external intensity multiplier
## (read from Settings autoload — falls back to 1.0 if not present).

const TRAUMA_POWER: float = 2.0
const DECAY: float = 1.8
const MAX_OFFSET_H: float = 0.35
const MAX_OFFSET_V: float = 0.25
const MAX_ROLL: float = 0.08
const NOISE_SPEED: float = 22.0

var trauma: float = 0.0
var _camera: Camera3D
var _noise: FastNoiseLite
var _time: float = 0.0
var _base_roll: float = 0.0
var _has_base_roll: bool = false

func setup(camera: Camera3D) -> void:
	_camera = camera
	_noise = FastNoiseLite.new()
	_noise.seed = 1337
	_noise.frequency = 2.0

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + maxf(0.0, amount))

func reset() -> void:
	trauma = 0.0
	if _camera != null:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		if _has_base_roll:
			_camera.rotation.z = _base_roll

func update(delta: float) -> void:
	if _camera == null:
		return
	if not _has_base_roll:
		_base_roll = _camera.rotation.z
		_has_base_roll = true

	_time += delta * NOISE_SPEED

	var intensity: float = 1.0
	var settings_node: Node = _get_settings_node()
	if settings_node != null and settings_node.has_method("get_value"):
		intensity = float(settings_node.call("get_value", "video.shake", 1.0))

	var shake: float = pow(trauma, TRAUMA_POWER) * intensity
	if shake <= 0.0001:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera.rotation.z = _base_roll
	else:
		var nx: float = _noise.get_noise_2d(_time, 0.0)
		var ny: float = _noise.get_noise_2d(_time, 100.0)
		var nr: float = _noise.get_noise_2d(_time, 200.0)
		_camera.h_offset = nx * MAX_OFFSET_H * shake
		_camera.v_offset = ny * MAX_OFFSET_V * shake
		_camera.rotation.z = _base_roll + nr * MAX_ROLL * shake

	trauma = maxf(0.0, trauma - DECAY * delta)

func _get_settings_node() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root: Window = tree.root
	if root == null:
		return null
	return root.get_node_or_null("Settings")
