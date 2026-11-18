extends SceneTree

const Anatomy = preload("res://scripts/arm_anatomy.gd")
var checks: = 0
var failures: Array[String] = []

func _initialize() -> void :
	call_deferred("run")

func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)

func run() -> void :
	for left in [false, true]:
		var arm = load("res://scenes/left_arm.tscn" if left else "res://scenes/right_arm.tscn").instantiate()
		root.add_child(arm)
		for court in [0, 1]:
			var world: = Basis(Vector3.UP, PI * court)
			for pole_turn in [ - 0.65, 0.0, 0.8]:
				var direction: Vector3 = (world * Vector3(0.36, - 0.42, - 0.83)).normalized()
				var perpendicular: Vector3 = direction.cross(world * Vector3.UP).normalized()
				var pole: Vector3 = arm.global_position + perpendicular.rotated(direction, pole_turn)
				var previous: = Basis.IDENTITY
				var has_previous: = false
				for span in [0.64, 0.69, 0.699, 0.6999, 0.69999, 0.699999, 0.7]:
					var shoulder: Vector3 = arm.upper_pivot.global_position
					var wrist: Vector3 = shoulder + direction * span
					arm.solve_ik(wrist, pole, null, wrist)
					var frame: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, left)
					var sign: float = -1.0 if left else 1.0
					var explicit_plane: Basis = Anatomy.frame((wrist - arm.forearm_pivot.global_position).normalized(), - arm.forearm_pivot.global_basis.y * sign)
					check(frame.y.dot(explicit_plane.y) > 0.99999, "measured neutral frame agrees with actual authored elbow plane")
					check(frame.determinant() > 0.99999, "reference keeps proper chirality on both courts")
					check(absf(shoulder.distance_to(arm.forearm_pivot.global_position) - arm.upper_arm_length) < 2e-06, "upper link stays exact")
					check(absf(wrist.distance_to(arm.forearm_pivot.global_position) - arm.forearm_length) < 2e-06, "forearm link stays exact through extension")
					if has_previous and span >= 0.69999:
						var angle: float = rad_to_deg(previous.get_rotation_quaternion().angle_to(frame.get_rotation_quaternion()))
						check(angle < 1.0, "straight-arm limit has no world-UP reference jump")
					previous = frame
					has_previous = true
		arm.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("FOREARM EXTENSION REFERENCE ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
