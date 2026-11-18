extends SceneTree


const Size = preload("res://scripts/paddle_dimensions.gd")
const Calibration = preload("res://scripts/paddle_pose_calibration.gd")
const Serve = preload("res://scripts/serve_pose_presentation.gd")
const Carry = preload("res://scripts/player_carry_presentation.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
var checks: = 0
var errors: Array[String] = []
var maximum_grip_error: = 0.0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: errors.append(label)
func head(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul)
func canonical(value: Vector3) -> Vector3: return Vector3(value.x, value.y, - value.z)
func compare(pose: PostureDefinition, old_head: Vector3, old_basis: Basis, label: String) -> void :
	var new_basis: Basis = Orientation.canonical_basis(pose)
	var old_grip: Vector3 = canonical(old_head) - old_basis.y * 0.33
	var new_grip: Vector3 = canonical(head(pose)) - new_basis.y * (Size.HEAD_CENTER_Y - Size.MAIN_GRIP_Y)
	var error: float = old_grip.distance_to(new_grip)
	maximum_grip_error = maxf(maximum_grip_error, error)
	check(error < 1e-06, label + " main virtual grip exact")
	check(new_basis.is_equal_approx(old_basis), label + " fixed paddle basis")
	for left in [false, true]:
		var socket: = Vector3(0.035 if left else - 0.035, - 0.055, 0.034)
		var old_wrist: Vector3 = old_grip + Grip.basis(old_basis, left) * socket
		var new_wrist: Vector3 = new_grip + Grip.basis(new_basis, left) * socket
		check(old_wrist.distance_to(new_wrist) < 1e-06, label + " calibrated wrist exact")
func preparation_old(style: int, q: float) -> Array:
	var samples: Array = Serve.PREPARATION[style if Serve.PREPARATION.has(style) else 0]
	var segment: int = 0 if q <= 0.5 else 1
	var u: float = q * 2.0 if segment == 0 else (q - 0.5) * 2.0
	var basis: Basis = Basis(Serve._basis(samples[segment][1]).get_rotation_quaternion().slerp(Serve._basis(samples[segment + 1][1]).get_rotation_quaternion(), u))
	return [Serve._curve(samples[0][0], samples[1][0], samples[2][0], q), basis]
func run() -> void :
	check(is_equal_approx(Calibration.CURRENT_HEAD_TO_MAIN_GRIP, 0.2244), "vendor grip-to-head lever")
	for style in range(7):
		for step in range(101):
			var q: float = step / 100.0
			var pose: = PostureDefinition.new()
			var old: Array = preparation_old(style, q)
			Serve.prepare(pose, style, q, Vector3(0.48, 0.22, 0.44))
			compare(pose, old[0], old[1], "prepare %d %.2f" % [style, q])
			if style in [2, 4, 5, 6] and step % 10 == 0:
				var samples: Array = Serve.WITHDRAWAL[5 if style == 6 else style]
				var segment: int = 0 if q <= 0.5 else 1
				var u: float = q * 2.0 if segment == 0 else (q - 0.5) * 2.0
				var target: Basis = Basis(Serve._basis(samples[segment][1]).get_rotation_quaternion().slerp(Serve._basis(samples[segment + 1][1]).get_rotation_quaternion(), u))
				var target_head: Vector3 = Serve._curve(samples[0][0], samples[1][0], samples[2][0], q)
				for release_step in range(11):
					var progress: float = release_step / 10.0
					var weight: float = smoothstep(0.0, 1.0, progress)
					var sample: PostureDefinition = pose.duplicate(true)
					Serve.release_withdrawal(sample, style, progress)
					compare(sample, old[0].lerp(target_head, weight), Basis(old[1].get_rotation_quaternion().slerp(target.get_rotation_quaternion(), weight)), "withdrawal %d %.2f %.2f" % [style, q, progress])
		var finish: = PostureDefinition.new()
		var values: Array = Serve.FINISH_SLICE if style == 2 else (Serve.FINISH_HIGH_SOFT if style == 3 else Serve.FINISH_STANDARD)
		Serve.finish(finish, style)
		compare(finish, values[0], Serve._basis(values[1]), "finish %d" % style)
		var contact: = PostureDefinition.new()
		contact.paddle_forehand_mul = 0.48;contact.paddle_y_offset = - 0.12;contact.paddle_forward_mul = 0.44
		var original_head: Vector3 = head(contact)
		Serve.contact_orientation(contact, style)
		check(head(contact) == original_head, "contact is excluded from legacy rebase")
	for step in range(101):
		var bend: float = step / 100.0
		var index: int = mini(3, int(bend * 4))
		var weight: float = bend * 4 - index
		var old_head: Vector3 = Carry.KEYS[index][0].lerp(Carry.KEYS[index + 1][0], weight)
		var old_basis: Basis = Carry._basis(Carry.KEYS[index][1]).slerp(Carry._basis(Carry.KEYS[index + 1][1]), weight)
		var pose: = PostureDefinition.new()
		Carry.apply(pose, bend)
		compare(pose, old_head, old_basis, "carry %.2f" % bend)
	for error in errors: push_error(error)
	print("NON-CONTACT PADDLE REBASE ", checks, " checks; ", errors.size(), " failures; maximum grip error ", maximum_grip_error)
	quit(0 if errors.is_empty() else 1)
