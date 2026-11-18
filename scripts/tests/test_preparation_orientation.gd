extends SceneTree
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Prep = preload("res://scripts/stroke_preparation_orientation.gd")
const Styles = preload("res://scripts/serve_style.gd")
var failures: Array[String] = []
var checks: = 0
var maximum_charge_step_deg: = 0.0
class PosePlayer extends RefCounted:
	var player_num: = 0
	var global_position: = Vector3(0, 1, 0)
	var global_transform: = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	const COURT_FLOOR_Y: = 0.075
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if player_num == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if player_num == 0 else Vector3.BACK
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and failures.size() < 80: failures.append(label)
func same(a: Transform3D, b: Transform3D, label: String) -> void :
	check(a.origin.distance_to(b.origin) < 1e-05 and a.basis.is_equal_approx(b.basis), label)
func position(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul)
func legacy_drive(base: PostureDefinition, t: float, charge: float) -> PostureDefinition:

	var def: PostureDefinition = Motion.drive_definition(base, charge)
	var pose: PostureDefinition = Path.sample(def, t)
	if t < 0.5:
		var slot: float = pow(sin(PI * t * 2), 2) * Motion.drive_strength(base, charge)
		pose.paddle_y_offset -= 0.26 * slot;pose.paddle_forward_mul -= 0.06 * slot
		pose.paddle_forehand_mul += (0.18 if base.family == 0 else - 0.18) * slot * clampf((0.62 - absf(base.paddle_forehand_mul)) / 0.12, 0, 1)
		if base.family == 1: pose.left_hand_offset += Vector3( - 0.1, - 0.15, 0) * slot
	return Path.blend_pose(def, pose, charge)
func run() -> void :
	var player: = PosePlayer.new()
	for side in [0, 1]:
		player.player_num = side
		for file in ["00_forehand", "10_wide_forehand", "02_backhand", "03_medium_overhead", "04_high_overhead"]:
			var base: PostureDefinition = load("res://data/postures/%s.tres" % file)
			for charge in [0.0, 0.35, 0.58, 0.65, 0.8, 1.0]:
				var held: PostureDefinition = Motion.held_drive_pose(base, charge)
				var start: PostureDefinition = Motion.sample_drive(base, 0, charge)
				same(Path.world_transform(player, held), Path.world_transform(player, start), file + " held/release exact")
				for step in range(65):
					var t: float = step / 64.0
					var actual: PostureDefinition = Motion.sample_drive(base, t, charge)
					var old: PostureDefinition = legacy_drive(base, t, charge)
					var a: Transform3D = Path.world_transform(player, actual)
					var b: Transform3D = Path.world_transform(player, old)
					check(position(actual).distance_to(position(old)) < 1e-06, file + " prep never translates head")
					check(a.basis.y.distance_to(b.basis.y) < 1e-05, file + " prep preserves shaft direction")
					check((a * PaddleSize.MAIN_GRIP_OFFSET).distance_to(b * PaddleSize.MAIN_GRIP_OFFSET) < 1e-05, file + " prep preserves grip-axis center")
					var lag: float = actual.get_meta("visual_wrist_lag_deg", 0.0)
					check(lag >= 0 and lag <= 6.00001, file + " bounded phase lag")
					if t == 0 or t >= 0.4: check(lag == 0, file + " late/initial lag exact zero")
					if t >= 0.4: same(a, b, file + " exact late approach/contact/finish")
			for compact in [true, false]:
				if compact:
					var pose: PostureDefinition = Motion.sample_drive(base, 0.2, 1, true)
					check(pose.get_meta("visual_wrist_lag_deg", 0.0) == 0, "volley has no preparation wrist lag")
		for style in range(7):
			var previous: = Basis.IDENTITY
			for step in range(101):
				var charge: float = step / 100.0
				var pose: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style))
				var basis: Basis = Prep.canonical_basis(pose)
				if step > 0:
					var turn: float = rad_to_deg(previous.get_rotation_quaternion().angle_to(basis.get_rotation_quaternion()))
					maximum_charge_step_deg = maxf(maximum_charge_step_deg, turn)
					check(turn < 6.0, "continuous serve charge face")
				previous = basis
				if charge < 0.45:
					check(pose.has_meta("reference_serve_load") and pose.has_meta("reference_serve_rotation"), "compact original pose values retained")
					var rotation: Vector3 = pose.get_meta("reference_serve_rotation")
					var original: PostureDefinition = Motion.original_serve_load(pose)
					check(original.resolve_paddle_rotation_deg(-1, -1).distance_to(rotation) < 1e-05, "restore full original serve face")
				check(pose.get_meta("serve_phase_charge", -1.0) == charge, "exact shared charge context")
				for wait in [0.0, 0.4, 0.8, 1.0]:
					var waiting: PostureDefinition = Motion.serve_style_wait(pose, wait, style)
					check(waiting.get_meta("serve_phase_style", -1) == style and waiting.get_meta("serve_phase_charge", -1.0) == charge, "wait retains shared phase context")
					same(Path.world_transform(player, Motion.serve_style_strike(waiting, 0.0, style)), Path.world_transform(player, waiting), "style strike begins at actual release pose")
					for t in [0.65, 0.8, 1.0]:
						var actual: Transform3D = Path.world_transform(player, Motion.serve_style_strike(waiting, t, style))
						var original: Transform3D = Path.world_transform(player, Motion._legacy_serve_style_strike(waiting, t, style))
						check((actual * PaddleSize.HEAD_OFFSET).distance_to(original * PaddleSize.HEAD_OFFSET) < 1e-05 and actual.basis.z.distance_to(original.basis.z) < 1e-05, "exact late serve head/face path")
						if t == 1.0: same(actual, Path.world_transform(player, Motion.serve_style_contact(style)), "exact shared serve contact")

	print("PREPARATION ORIENTATION: %d checks, %d failures; max 1%% charge step %.4f deg" % [checks, failures.size(), maximum_charge_step_deg])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
