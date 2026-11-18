extends SceneTree

const PickupCamera = preload("res://scripts/camera/between_point_camera.gd")
var failures: Array[String] = []
var checks: = 0
var focus: = Vector3(0, 0.8, 0)
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func get_focus() -> Vector3: return focus
func run() -> void:
	root.size = Vector2i(432, 936)
	var camera: = Camera3D.new()
	root.add_child(camera)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.position = Vector3(0, 10, 14)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.fov = 44.0
	camera.v_offset = 0.4
	var saved: = camera.global_transform
	var controller = PickupCamera.new()
	check(controller.begin(camera, get_focus), "close pickup begins")
	controller.advance(1.0)
	for step in 120:
		focus.x = sin(float(step) / 60.0) * 2.0
		focus.z = float(step) / 120.0 * 3.0
		controller.advance(1.0 / 60.0)
		var offset: Vector3 = camera.global_position - controller._focus
		check(offset.length() < 6.1, "pickup stays close")
		check(offset.x > 0 and offset.z > 0, "pickup never crosses to opposite side")
		check(is_equal_approx(camera.fov, 50.0), "pickup never widens during tracking")
		for point in [controller._focus + Vector3(0, -0.8, 0), controller._focus + Vector3(0, 1.35, 0)]:
			check(not camera.is_position_behind(point) and root.get_visible_rect().grow(-12).has_point(camera.unproject_position(point)), "pickup full body visible")
	controller.advance(1.1)
	check(not controller.active, "pickup ends on schedule")
	check(camera.global_transform.is_equal_approx(saved), "pickup restores original camera")
	check(is_equal_approx(camera.v_offset, 0.4) and is_equal_approx(camera.fov, 44), "pickup restores framing")
	print("CLOSE PICKUP CAMERA: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
