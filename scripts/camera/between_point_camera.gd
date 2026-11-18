extends RefCounted

var active: = false
var _camera: Camera3D
var _saved: Dictionary = {}
var _start_view: = Transform3D.IDENTITY
var _focus_provider: = Callable()
var _focus: = Vector3(0, 0.8, 0)
var _elapsed: = 0.0
var _duration: = 4.0

func begin(camera: Camera3D, focus_provider: Callable, duration: float = 4.0) -> bool:
	if active or not is_instance_valid(camera): return false
	_camera = camera
	_focus_provider = focus_provider
	_duration = clampf(duration, 1.0, 6.0)
	_elapsed = 0.0
	_saved = {"transform": camera.global_transform, "projection": camera.projection, "keep_aspect": camera.keep_aspect, 
		"fov": camera.fov, "size": camera.size, "frustum_offset": camera.frustum_offset, "h_offset": camera.h_offset, "v_offset": camera.v_offset}
	_start_view = camera.get_camera_transform()
	_focus = _read_focus()
	active = true
	return true

func advance(delta: float) -> void :
	if not active: return
	if not is_instance_valid(_camera): end();return
	_elapsed += maxf(0, delta)
	if _elapsed >= _duration:
		end();return
	_focus = _focus.lerp(_read_focus(), 1 - exp( - maxf(0, delta) * 3.5))
	# Follow the pickup from one close, Blue-side view. The old 10–12m
	# two-angle orbit made the player tiny and crossed the court mid-pickup.
	var close_offset: = Vector3(2.4, 2.6, 4.8)
	var close_view: = Transform3D(Basis.IDENTITY, _focus + close_offset).looking_at(_focus, Vector3.UP)
	var t: = _elapsed / _duration
	var view: Transform3D
	var fov: float
	var close_fov: = 50.0 if int(_saved.keep_aspect) == Camera3D.KEEP_WIDTH else 60.0
	if t < 0.22:
		var blend: = smoothstep(0.0, 0.22, t)
		view = _start_view.interpolate_with(close_view, blend)
		fov = lerpf(float(_saved.fov), close_fov, blend)
	elif t < 0.84:
		view = close_view
		fov = close_fov
	else:
		var blend: = smoothstep(0.84, 1.0, t)
		view = close_view.interpolate_with(_start_view, blend)
		fov = lerpf(close_fov, float(_saved.fov), blend)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.keep_aspect = int(_saved.keep_aspect)
	_camera.h_offset = 0
	_camera.v_offset = 0
	_camera.global_transform = view
	_camera.fov = fov

func _read_focus() -> Vector3:
	if _focus_provider.is_valid():
		var value: Variant = _focus_provider.call()
		if value is Vector3 and value.is_finite():
			return Vector3(clampf(value.x, -8, 8), clampf(value.y, 0.4, 1.3), clampf(value.z, -11, 11))
	return Vector3(0, 0.8, 0)

func end() -> void :
	if active and is_instance_valid(_camera) and _camera.is_inside_tree() and not _saved.is_empty():
		_camera.projection = int(_saved.projection)
		_camera.keep_aspect = int(_saved.keep_aspect)
		_camera.fov = float(_saved.fov)
		_camera.size = float(_saved.size)
		_camera.frustum_offset = _saved.frustum_offset
		_camera.h_offset = float(_saved.h_offset)
		_camera.v_offset = float(_saved.v_offset)
		_camera.global_transform = _saved.transform
	active = false
	_saved.clear()
	_focus_provider = Callable()
	_camera = null
