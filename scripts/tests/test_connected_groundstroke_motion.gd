extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Ready = preload("res://scripts/incoming_ready_motion.gd")
const Support = preload("res://scripts/groundstroke_support_motion.gd")
const POSES: Array[String] = ["00_forehand", "01_forward", "02_backhand", "03_medium_overhead", "04_high_overhead", "05_low_forehand", "06_low_forward", "07_low_backhand", "08_charge_forehand", "09_charge_backhand", "10_wide_forehand", "11_wide_backhand", "12_volley_ready", "13_mid_low_forehand", "14_mid_low_backhand", "15_mid_low_forward", "16_mid_low_wide_forehand", "17_mid_low_wide_backhand", "18_low_wide_forehand", "19_low_wide_backhand", "20_ready"]
var failures: Array[String] = []
var checks: = 0

class RigPlayer extends Node3D:
	var player_num: = 0
	var body_pivot: Node3D
	var right_arm_node: Node3D
	var left_arm_node: Node3D
	var right_leg_node: Node3D
	var left_leg_node: Node3D
	const COURT_FLOOR_Y: = 0.075
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if player_num == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if player_num == 0 else Vector3.BACK
	func _get_swing_sign() -> float: return -1.0 if player_num == 0 else 1.0
	func setup() -> void :
		body_pivot = Node3D.new();body_pivot.name = "BodyPivot";add_child(body_pivot)
		var chest: = Node3D.new();chest.name = "TorsoMesh";body_pivot.add_child(chest)
		var head: = Node3D.new();head.name = "HeadMesh";chest.add_child(head)
		var hips: = Node3D.new();hips.name = "HipsMesh";body_pivot.add_child(hips)
		right_arm_node = Node3D.new();left_arm_node = Node3D.new()
		right_leg_node = Node3D.new();left_leg_node = Node3D.new()
		for node in [right_arm_node, left_arm_node, right_leg_node, left_leg_node]: body_pivot.add_child(node)
		for arm in [right_arm_node, left_arm_node]:
			var pivot: = Node3D.new();pivot.name = "UpperArmPivot";arm.add_child(pivot)

func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func close_vec(a: Vector3, b: Vector3, label: String, tolerance: float = 1e-05) -> void :
	check(a.distance_to(b) <= tolerance, "%s error %.7f" % [label, a.distance_to(b)])
func load_pose(name: String) -> PostureDefinition:
	return load("res://data/postures/%s.tres" % name)
func legacy_shoulder(player: RigPlayer, pose: PostureDefinition) -> Vector3:
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, - player._get_forward_axis())
	var canonical: = Basis.from_euler(Vector3( - (28.0 + pose.torso_pitch_deg + pose.spine_curve_deg), - (pose.hip_yaw_deg + pose.torso_yaw_deg), pose.torso_roll_deg) * (PI / 180.0))
	var old_chest: = Transform3D(stance * canonical * stance.inverse(), Vector3(0, 0.05, 0))
	var side: float = -1.0 if pose.paddle_hand == 1 else 1.0
	return player.global_transform * Body.pivot_transform(player, pose) * old_chest * (player._get_forehand_axis() * side * 0.18 + Vector3.UP * 0.1)
func legacy_paddle(player: RigPlayer, pose: PostureDefinition) -> Transform3D:
	var basis: Basis = Path.paddle_basis(player, pose)
	var head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
	head = PaddleReach.clamp_head_with_floor(head, legacy_shoulder(player, pose), player.COURT_FLOOR_Y + pose.paddle_floor_clearance)
	return Transform3D(basis, head - basis.y * PaddleSize.HEAD_CENTER_Y)

func run() -> void :
	var player: = RigPlayer.new();root.add_child(player);player.position = Vector3(0, 1, 0);player.setup()
	for side in [0, 1]:
		player.player_num = side
		for name in POSES:
			var base: PostureDefinition = load_pose(name)
			for dominant in [0, 1]:
				var pose: PostureDefinition = base.lerp_with(base, 0)
				pose.paddle_hand = dominant
				var tag: = "%s side%d hand%d" % [name, side, dominant]
				Body.apply(player, pose)
				var arm: Node3D = player.left_arm_node if dominant == 1 else player.right_arm_node
				close_vec(arm.get_node("UpperArmPivot").global_position, Body.shoulder_world(player, pose), tag + " query/drawing")
				close_vec(Body.torso_transform(player, pose) * Vector3(0, - 0.17, 0), Body.waist_transform(player, pose).origin, tag + " chest/waist join")
				close_vec(Body.waist_transform(player, pose).origin, Body.abdomen_transform(player, pose) * Vector3(0, Body.Dimensions.ABDOMEN_LENGTH, 0), tag + " waist/abdomen join")
				close_vec(Body.abdomen_transform(player, pose).origin, Body.pelvis_transform(player, pose) * Vector3(0, Body.Dimensions.PELVIS_HALF_HEIGHT, 0), tag + " abdomen/pelvis join")
				var old: Transform3D = legacy_paddle(player, pose)
				var now: Transform3D = Path.world_transform(player, pose)
				close_vec(old.origin, now.origin, tag + " contact origin remains exact")
				check(old.basis.is_equal_approx(now.basis), tag + " contact basis remains exact")
		for style in range(7):
			var serve: PostureDefinition = Motion.serve_style_contact(style)
			close_vec(legacy_paddle(player, serve).origin, Path.world_transform(player, serve).origin, "serve contact style%d side%d" % [style, side])

		for bend in [-18.0, 0.0, 18.0]:
			var pose: PostureDefinition = load_pose("20_ready").lerp_with(load_pose("20_ready"), 0)
			pose.spine_curve_deg = bend;pose.torso_roll_deg = bend * 0.6;pose.hip_yaw_deg = 23;pose.torso_yaw_deg = -17
			Body.apply(player, pose)
			close_vec(Body.torso_transform(player, pose) * Vector3(0, - 0.17, 0), Body.waist_transform(player, pose).origin, "independent bend seam")
			close_vec(player.right_arm_node.global_position, Body.shoulder_world(player, pose), "independent bend query")
	_test_motion(player)
	print("CONNECTED GROUNDSTROKE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	player.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_motion(player: RigPlayer) -> void :
	player.player_num = 0
	var fh: PostureDefinition = load_pose("00_forehand")
	var ready: PostureDefinition = load_pose("20_ready")
	for name in ["02_backhand", "11_wide_backhand"]:
		var base: PostureDefinition = load_pose(name)
		var load: PostureDefinition = Motion.held_drive_pose(base, 1)
		var contact: PostureDefinition = Motion.sample_drive(base, 0.5, 1)
		var a: Basis = Body.pivot_transform(player, load).basis * Body.torso_transform(player, load).basis
		var b: Basis = Body.pivot_transform(player, contact).basis * Body.torso_transform(player, contact).basis
		var uncoil: float = rad_to_deg(a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion()))
		check(uncoil > 12 and uncoil < 30, name + " has bounded actual pre-contact uncoil")
		check(is_equal_approx(contact.body_yaw_deg, base.body_yaw_deg) and is_equal_approx(contact.hip_yaw_deg, base.hip_yaw_deg) and is_equal_approx(contact.torso_yaw_deg, base.torso_yaw_deg), name + " contact body retained")
	for charge in [0.0, 0.25, 0.6, 1.0]:
		var held: PostureDefinition = Motion.held_drive_pose(fh, charge)
		var first: PostureDefinition = Motion.sample_drive(fh, 0, charge)
		close_vec(Path.support_hand_offset(held), Path.support_hand_offset(first), "no off-hand release snap q%.2f" % charge)
		var previous: = Path.support_hand_offset(first)
		for step in range(1, 65):
			var pose: PostureDefinition = Motion.sample_drive(fh, step / 64.0, charge)
			var target: Vector3 = Path.support_hand_offset(pose)
			check(target.distance_to(previous) < 0.065, "smooth off-hand step%d q%.2f" % [step, charge])
			previous = target
		var def: PostureDefinition = Motion.drive_definition(fh, charge)
		var original_finish: PostureDefinition = Path.blend_pose(def, Path.sample(def, 1), charge)
		close_vec(previous, Path.support_hand_offset(original_finish), "authored finish/recovery hand retained")
	var contact_pose: PostureDefinition = Motion.sample_drive(fh, 0.5, 1)
	close_vec(Path.world_transform(player, contact_pose).origin, Path.world_transform(player, fh).origin, "off-hand does not move contact paddle")
	var tucked: Vector3 = Path.support_hand_offset(contact_pose);tucked.z = - tucked.z
	close_vec(tucked, Support.tuck_target(fh), "free hand cleared at impact")
	for mode in [1, 2, 3]:
		var explicit: PostureDefinition = fh.lerp_with(fh, 0);explicit.left_hand_mode = mode
		var pose: PostureDefinition = explicit.lerp_with(explicit, 0)
		var original: Vector3 = Path.support_hand_offset(pose)
		Support.swing(pose, explicit, 0.2, 1, false)
		close_vec(Path.support_hand_offset(pose), original, "explicit support mode retained")
	for base in [fh, load_pose("02_backhand")]:
		var pose: PostureDefinition = base.lerp_with(base, 0)
		var original: Vector3 = Path.support_hand_offset(pose)
		Support.swing(pose, base, 0.2, 1, base.family == 0)
		close_vec(Path.support_hand_offset(pose), original, "kitchen/volley and BH exemptions")
	var outside: PostureDefinition = Ready.prepare(fh, ready, 0.4, false, false)
	var kitchen: PostureDefinition = Ready.prepare(fh, ready, 0.4, false, true)
	check(Path.support_hand_offset(outside).distance_to(Path.support_hand_offset(kitchen)) > 0.05, "outside anticipation differs from compact kitchen")
	close_vec(Path.world_transform(player, outside).origin, Path.world_transform(player, kitchen).origin, "anticipation preserves paddle")
