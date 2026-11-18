extends Control
## Real scene-space geometry, with touch-sized picking against its projection.
## The authored field setters remain the only path into the constrained rig.
signal dragged(axis: int, amount: float)
const COLORS := [Color("ff777b"), Color("66e6a5"), Color("71afff")]
const SEGMENTS := 96
var preview
var mode := 0
var enabled := false
var bindings: Array = [{}, {}, {}]
var caption := ""
var ui_scale := 1.0
var world_axes: Array = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
# Metres / authored unit and right-handed radians / authored radian.
var unit_scales: Array = [1.0, 1.0, 1.0]
var angle_signs: Array = [1.0, 1.0, 1.0]
var scene_root: Node3D
var _arrows: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _axis := -1
var _touch := -1
var _drag_center := Vector2.ZERO
var _last_point := Vector2.ZERO
var _drag_origin := Vector3.ZERO
var _drag_axis := Vector3.UP
var _drag_u := Vector3.RIGHT
var _drag_v := Vector3.BACK
var _drag_radius := .3
var _drag_angle := 0.0
var _drag_value := 0.0
var _drag_depth := false
var _drag_edge := false
var _drag_camera := Transform3D.IDENTITY
var _drag_size := Vector2.ZERO
var _pixels_per_unit := 250.0
var _length := .4
var _last_visual_state: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(cancel_gesture)
	visibility_changed.connect(_visibility_changed)
	_build_scene()

func _build_scene() -> void:
	scene_root = Node3D.new(); scene_root.name = "SelectedPartSceneGizmo"
	preview.camera.get_parent().add_child(scene_root)
	for axis in range(3):
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[axis]; material.emission_enabled = true
		material.emission = COLORS[axis]; material.emission_energy_multiplier = .38
		material.roughness = .45; material.no_depth_test = true; material.render_priority = 20
		_materials.append(material)
		var arrow := Node3D.new(); arrow.name = ["MoveX", "MoveY", "MoveZ"][axis]; scene_root.add_child(arrow)
		var stem := CylinderMesh.new(); stem.top_radius = .022; stem.bottom_radius = .022; stem.height = .78
		var shaft := MeshInstance3D.new(); shaft.mesh = stem; shaft.material_override = material; shaft.position.y = .44; shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; arrow.add_child(shaft)
		var cone := CylinderMesh.new(); cone.top_radius = 0; cone.bottom_radius = .075; cone.height = .20
		var tip := MeshInstance3D.new(); tip.mesh = cone; tip.material_override = material; tip.position.y = .9; tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; arrow.add_child(tip)
		_arrows.append(arrow)
		var torus := TorusMesh.new(); torus.inner_radius = .977; torus.outer_radius = 1.023; torus.rings = 96; torus.ring_segments = 8
		var ring := MeshInstance3D.new(); ring.name = ["RotateX", "RotateY", "RotateZ"][axis]
		ring.mesh = torus; ring.material_override = material; ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; scene_root.add_child(ring); _rings.append(ring)
	var sphere := SphereMesh.new(); sphere.radius = .021; sphere.height = .042
	var hub := MeshInstance3D.new(); hub.mesh = sphere; hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var white := StandardMaterial3D.new(); white.albedo_color = Color("ecffff"); white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.no_depth_test = true; white.render_priority = 21; hub.material_override = white; scene_root.add_child(hub)
	sync_scene()

func configure(value: Array, text: String, active: bool, rotation_mode: int) -> void:
	if bindings != value or enabled != active or mode != rotation_mode: cancel_gesture()
	bindings = value; caption = text; enabled = active; mode = rotation_mode
	sync_scene(); queue_redraw()

func anchor() -> Vector2:
	return preview.joint_screen_position(preview.selected_joint) if preview != null else Vector2.INF

func center() -> Vector2:
	# Never inset or tether: the geometry lives at the actual solved 3D part.
	return anchor()

func origin() -> Vector3:
	return preview.joint_world_position(preview.selected_joint)

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.mobile_pose_gizmo", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	sync_scene()

func sync_scene() -> void:
	if not is_instance_valid(scene_root): return
	var point := origin()
	var active := visible and is_visible_in_tree() and enabled and point.is_finite() and anchor().is_finite()
	var state: Array = [point, preview.camera.global_transform, preview.camera.fov, size, visible, active, mode, bindings.duplicate(true), world_axes.duplicate(), _axis, ui_scale]
	if state == _last_visual_state: return
	_last_visual_state = state
	scene_root.visible = active
	if active:
		# Constant useful on-screen size, but every vertex is projected in 3D.
		# Unlike billboard rings, foreshortening and mutual intersections remain.
		var depth: float = maxf(.2, -preview.camera.to_local(point).z)
		_length = clampf(depth * 2.0 * tan(deg_to_rad(preview.camera.fov * .5)) * 94.0 * ui_scale / maxf(size.y, 1.0), .18, .85)
		scene_root.global_position = point
		for axis in range(3):
			var available: bool = not bindings[axis].is_empty()
			_arrows[axis].visible = available and mode == 0
			_rings[axis].visible = available and mode == 1
			var normal: Vector3 = world_axes[axis].normalized()
			var frame := _axis_frame(normal)
			_arrows[axis].basis = frame.scaled(Vector3.ONE * _length)
			_rings[axis].basis = frame.scaled(Vector3.ONE * world_radius(axis))
			_materials[axis].emission_energy_multiplier = .9 if _axis == axis else .38
	preview.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _axis_frame(normal: Vector3) -> Basis:
	var u: Vector3 = normal.cross(Vector3.BACK if absf(normal.dot(Vector3.BACK)) < .85 else Vector3.RIGHT).normalized()
	# x cross y = z; ring_point traverses u toward v around +normal.
	return Basis(u, normal, u.cross(normal).normalized())

func ring_frame(axis: int) -> Dictionary:
	var normal: Vector3 = world_axes[axis].normalized()
	var u: Vector3 = _axis_frame(normal).x
	return {"u": u, "v": normal.cross(u).normalized(), "normal": normal}

func world_radius(axis: int) -> float:
	return _length * (1.0 - .08 * axis)

func radius(axis: int) -> float:
	return anchor().distance_to(ring_point(axis, 0.0))

func ring_world_point(axis: int, angle: float) -> Vector3:
	var frame := ring_frame(axis)
	return origin() + (frame.u * cos(angle) + frame.v * sin(angle)) * world_radius(axis)

func ring_point(axis: int, angle: float) -> Vector2:
	return preview._world_screen_position(ring_world_point(axis, angle))

func axis_geometry(axis: int) -> Dictionary:
	var normal: Vector3 = world_axes[axis].normalized()
	var point := origin()
	var end: Vector2 = preview._world_screen_position(point + normal * _length)
	var projected: Vector2 = end - anchor()
	var depth := projected.length() < 17.0 * ui_scale
	var scale: float = (94.0 * ui_scale if depth else projected.length()) / maxf(_length, .001) * float(unit_scales[axis])
	return {"direction": Vector2.UP if depth else projected.normalized(), "end": end, "scale": scale, "depth": depth}

func _ray(point: Vector2) -> Dictionary:
	var pixel: Vector2 = point * Vector2(preview.viewport.size) / preview.size
	return {"origin": preview.camera.project_ray_origin(pixel), "direction": preview.camera.project_ray_normal(pixel)}

func hit_axis(point: Vector2) -> int:
	if not enabled or not visible or not is_visible_in_tree() or not anchor().is_finite(): return -1
	var nearest := -1
	var best := 20.0 * ui_scale
	for axis in range(3):
		if bindings[axis].is_empty(): continue
		var gap := INF
		if mode == 1:
			for index in range(SEGMENTS):
				var a := ring_point(axis, TAU * index / SEGMENTS)
				var b := ring_point(axis, TAU * (index + 1) / SEGMENTS)
				if a.is_finite() and b.is_finite(): gap = minf(gap, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
		else:
			var geometry := axis_geometry(axis)
			var start: Vector2 = preview._world_screen_position(origin() + world_axes[axis].normalized() * _length * .25)
			gap = point.distance_to(geometry.end) if geometry.depth else point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, geometry.end))
		if gap < best: best = gap; nearest = axis
	return nearest

func _line_parameter(point: Vector2) -> float:
	var ray := _ray(point)
	var w: Vector3 = _drag_origin - ray.origin
	var b: float = _drag_axis.dot(ray.direction)
	var denominator: float = 1.0 - b * b
	if denominator < .0001: return _drag_value
	return (b * ray.direction.dot(w) - _drag_axis.dot(w)) / denominator

func _plane_angle(point: Vector2) -> float:
	var ray := _ray(point)
	var denominator: float = _drag_axis.dot(ray.direction)
	if absf(denominator) < .0001: return _drag_angle
	var t: float = _drag_axis.dot(_drag_origin - ray.origin) / denominator
	if t < 0: return _drag_angle
	var offset: Vector3 = ray.origin + ray.direction * t - _drag_origin
	if offset.length() < _drag_radius * .1: return _drag_angle
	return atan2(offset.dot(_drag_v), offset.dot(_drag_u))

func _closest_ring_angle(axis: int, point: Vector2) -> float:
	var best := INF
	var angle := 0.0
	for index in range(SEGMENTS * 2):
		var candidate: float = TAU * index / (SEGMENTS * 2)
		var gap := point.distance_squared_to(ring_point(axis, candidate))
		if gap < best: best = gap; angle = candidate
	return angle

func begin(point: Vector2, touch: int = -1) -> bool:
	sync_scene()
	var axis := hit_axis(point)
	if axis < 0: return false
	_drag_center = anchor(); _axis = axis; _touch = touch; _last_point = point
	_drag_origin = origin(); _drag_axis = world_axes[axis].normalized()
	_drag_camera = preview.camera.global_transform; _drag_size = size
	_drag_radius = world_radius(axis)
	if mode == 0:
		var geometry := axis_geometry(axis)
		_drag_depth = geometry.depth; _pixels_per_unit = geometry.scale
		_drag_value = _line_parameter(point)
	else:
		var frame := ring_frame(axis); _drag_u = frame.u; _drag_v = frame.v
		var ray := _ray(point)
		_drag_edge = absf(_drag_axis.dot(ray.direction)) < .12
		_drag_angle = _closest_ring_angle(axis, point) if _drag_edge else _plane_angle(point)
	sync_scene()
	return true

func move(point: Vector2) -> void:
	if _axis < 0: return
	if not preview.camera.global_transform.is_equal_approx(_drag_camera) or size != _drag_size:
		cancel_gesture(); return
	var amount := 0.0
	if mode == 1:
		if _drag_edge:
			# A ray parallel to the ring plane has no reliable plane intersection.
			# Follow the projected 3D tangent instead, preserving the chosen branch.
			var at: Vector3 = _drag_origin + (_drag_u * cos(_drag_angle) + _drag_v * sin(_drag_angle)) * _drag_radius
			var next: Vector3 = _drag_origin + (_drag_u * cos(_drag_angle + .01) + _drag_v * sin(_drag_angle + .01)) * _drag_radius
			var tangent: Vector2 = (preview._world_screen_position(next) - preview._world_screen_position(at)) / .01
			if tangent.length() > 6.0 * ui_scale:
				amount = clampf((point - _last_point).dot(tangent) / tangent.length_squared(), -.35, .35)
			_drag_angle += amount
		else:
			var angle := _plane_angle(point)
			amount = wrapf(angle - _drag_angle, -PI, PI); _drag_angle = angle
		amount = rad_to_deg(amount) / float(angle_signs[_axis])
	else:
		if _drag_depth: amount = (point - _last_point).dot(Vector2.UP) / _pixels_per_unit
		else:
			var parameter := _line_parameter(point)
			amount = (parameter - _drag_value) / float(unit_scales[_axis]); _drag_value = parameter
	_last_point = point
	if is_finite(amount) and absf(amount) > .000001: dragged.emit(_axis, amount)
	sync_scene()

func input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if _axis >= 0:
			if event.index == _touch and (not event.pressed or event.canceled): cancel_gesture()
			return true
		if event.pressed and not event.canceled: return begin(event.position, event.index)
	elif event is InputEventScreenDrag and _axis >= 0:
		if event.index == _touch: move(event.position)
		return true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION: return _axis >= 0
		if _axis >= 0:
			if not event.pressed and _touch < 0: cancel_gesture()
			return true
		if event.pressed: return begin(event.position)
	elif event is InputEventMouseMotion and _axis >= 0:
		if _touch < 0: move(event.position)
		return true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var was_dragging := _axis >= 0
		cancel_gesture(); return was_dragging
	return false

func cancel_gesture() -> void:
	_axis = -1; _touch = -1
	if is_instance_valid(scene_root): sync_scene()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): cancel_gesture()
	sync_scene()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: cancel_gesture()
	elif what == NOTIFICATION_PREDELETE and is_instance_valid(scene_root): scene_root.queue_free()

# Selection and drag feedback are supplied by the colored scene handles.
