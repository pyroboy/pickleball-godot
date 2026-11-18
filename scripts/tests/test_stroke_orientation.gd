extends TestBase

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Wrist = preload("res://scripts/tests/pose_anatomical_wrist.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")

class CourtSide extends RefCounted:
	var player_num: int = 0
	var global_position: = Vector3(0, 1, 0)
	var global_transform: = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	const COURT_FLOOR_Y: float = 0.075
	func _init(side: int): player_num = side
	func _get_swing_sign(): return -1.0 if player_num == 0 else 1.0
	func _get_forward_axis(): return Vector3.FORWARD if player_num == 0 else Vector3.BACK
	func _get_forehand_axis(): return Vector3.RIGHT if player_num == 0 else Vector3.LEFT

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_blue_authored_angles_are_preserved, 
		test_every_stroke_mirrors_shaft_face_head_and_shoulder, 
		test_contact_orientation_is_shot_specific, 
		test_backhands_keep_dominant_hand_and_original_contact, 
		test_all_curves_are_reachable_without_hand_switching, 
		test_linked_planned_contact_preserves_lower_receive_guides])

func test_linked_planned_contact_preserves_lower_receive_guides() -> void :
	var source: PostureDefinition = PostureLibrary.instance().get_def(2)
	var original: PostureDefinition = source.duplicate(true)
	for side in range(2):
		var player = CourtSide.new(side)
		var head: Vector3 = player.global_position + source.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis()) - Vector3.UP * 0.15
		var planned: PostureDefinition = Planner.pose_at(player, source, head)
		var contact: PostureDefinition = Path.sample(planned, 0.5)
		_assert_eq_v3(Path.world_transform(player, contact) * PaddleSize.HEAD_OFFSET, head, 1e-05, "lower linked receive retains exact selected head")
		_assert_eq_f(contact.crouch_amount, planned.crouch_amount, 1e-05, "lower linked receive retains knee load")
		_assert_eq_v3(contact.right_elbow_pole, planned.right_elbow_pole, 1e-05, "lower linked contact keeps dominant elbow adjustment")
		_assert_eq_v3(contact.left_elbow_pole, planned.left_elbow_pole, 1e-05, "lower linked contact keeps support elbow adjustment")
		for stage in [0, 2]:
			var old_endpoint: PostureDefinition = Path.endpoint(source, stage)
			var lowered_endpoint: PostureDefinition = Path.endpoint(planned, stage)
			_assert_eq_f(lowered_endpoint.crouch_amount - old_endpoint.crouch_amount, 0.15, 1e-05, "lower receive translates endpoint knee load")
			_assert_eq_v3(lowered_endpoint.right_elbow_pole, old_endpoint.right_elbow_pole - Vector3.UP * 0.15, 1e-05, "lower receive translates endpoint dominant guide")
			_assert_eq_v3(lowered_endpoint.left_elbow_pole, old_endpoint.left_elbow_pole - Vector3.UP * 0.15, 1e-05, "lower receive translates endpoint support guide")
	_assert_eq(source.right_elbow_path, original.right_elbow_path, "planning must not mutate saved dominant route")
	_assert_eq(source.left_elbow_path, original.left_elbow_path, "planning must not mutate saved support route")
	_assert_eq(source.windup_body.values, original.windup_body.values, "planning must not mutate saved windup body")
	_assert_eq(source.follow_through_body.values, original.follow_through_body.values, "planning must not mutate saved finish body")

func _stance_vector(player, vector: Vector3) -> Vector3:
	return Vector3(vector.dot(player._get_forehand_axis()), vector.y, vector.dot(player._get_forward_axis()))

func _face_toward_net(player, basis: Basis) -> Vector3:
	return basis.z if basis.z.dot(player._get_forward_axis()) >= 0 else - basis.z

func test_blue_authored_angles_are_preserved() -> void :
	var player = CourtSide.new(0)
	for def in PostureLibrary.instance().all_definitions():
		for step in range(33):
			var pose = Path.sample(def, step / 32.0)
			var angles: Vector3 = pose.resolve_paddle_rotation_deg(-1, -1) * (PI / 180.0)
			var legacy: = Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) * Basis(Vector3.FORWARD, angles.z)
			_assert_true(Path.paddle_basis(player, pose).is_equal_approx(legacy), "%s sample%d blue authoring changed" % [def.display_name, step])

func test_every_stroke_mirrors_shaft_face_head_and_shoulder() -> void :
	var blue = CourtSide.new(0)
	var red = CourtSide.new(1)
	for def in PostureLibrary.instance().all_definitions():
		for step in range(65):
			var pose = Path.sample(def, step / 64.0)
			var a: Transform3D = Path.world_transform(blue, pose)
			var b: Transform3D = Path.world_transform(red, pose)
			var tag: String = "%s sample%d" % [def.display_name, step]
			_assert_eq_v3(_stance_vector(blue, a.basis.y), _stance_vector(red, b.basis.y), 1e-05, tag + " shaft")
			_assert_eq_v3(_stance_vector(blue, _face_toward_net(blue, a.basis)), _stance_vector(red, _face_toward_net(red, b.basis)), 1e-05, tag + " striking face")
			_assert_eq_v3(_stance_vector(blue, a * PaddleSize.HEAD_OFFSET - blue.global_position), _stance_vector(red, b * PaddleSize.HEAD_OFFSET - red.global_position), 1e-05, tag + " head")
			_assert_eq_v3(_stance_vector(blue, Body.shoulder_world(blue, pose) - blue.global_position), _stance_vector(red, Body.shoulder_world(red, pose) - red.global_position), 1e-05, tag + " shoulder")

func test_contact_orientation_is_shot_specific() -> void :
	for side in range(2):
		var player = CourtSide.new(side)
		for def in PostureLibrary.instance().all_definitions():
			var basis: Basis = Path.paddle_basis(player, def)
			var face: Vector3 = _face_toward_net(player, basis)
			if def.height_tier < 2:
				_assert_lt(basis.y.y, -0.6, def.display_name + " low head stays below hand")
				_assert_gt(face.y, 0.08, def.display_name + " low face stays open despite downward shaft")
			elif def.family == 3:
				_assert_gt(basis.y.y, 0.8, def.display_name + " overhead reaches upward")
			elif def.posture_id == 20:
				_assert_gt(basis.y.y, 0.0, "relaxed Ready keeps head above handle")

				_assert_gt(face.dot(player._get_forward_axis()), cos(PI / 3), "joined Ready blade faces play within 60 degrees")
			elif def.posture_id in [1, 12]:
				_assert_gt(basis.y.y, 0.85, def.display_name + " compact guard stays up")

func test_backhands_keep_dominant_hand_and_original_contact() -> void :


	var contacts: = {
		2: Vector3(-0.46337748, 0.24756992, 0.4405713), 
		7: Vector3(-0.42, -0.62, 0.55), 
		11: Vector3(-0.6461487, 0.1466484, 0.56538296), 
		14: Vector3(-0.46764064, -0.2123962, 0.5438068), 
		17: Vector3(-0.6369686, -0.20000005, 0.53999996), 
		19: Vector3(-0.62, -0.49, 0.4), 
	}
	var ready = PostureLibrary.instance().get_def(20)
	var charge = PostureLibrary.instance().get_def(9)
	_assert_false(charge.has_zone, "charge posture has no collision/contact area")
	_assert_eq(charge.paddle_hand, 0, "loaded backhand retains dominant hand")
	_assert_eq(charge.left_hand_mode, 1, "loaded backhand keeps both hands joined")
	_assert_lt(charge.paddle_forward_mul, -0.2, "loaded backhand prepares behind body")
	for id in contacts:
		var def = PostureLibrary.instance().get_def(id)
		_assert_eq_v3(Vector3(def.paddle_forehand_mul, def.paddle_y_offset, def.paddle_forward_mul), contacts[id], 1e-06, def.display_name + " original contact")
		for step in range(33):
			var pose = Path.sample(def, step / 32.0)
			_assert_eq(pose.paddle_hand, 0, def.display_name + " right dominant hand")
			var linked: bool = id == 2
			_assert_eq(pose.left_hand_mode, 1 if linked else 4, def.display_name + " standard linked/wide-low free support")
			_assert_eq_v3(pose.right_hand_offset, Vector3(0, - 0.05, 0) if linked else Vector3.ZERO, 1e-05, def.display_name + " authored dominant handle seat")
			if linked:
				_assert_eq_v3(pose.left_hand_offset, Vector3.ZERO, 1e-05, "joined support stays on shaft")
				_assert_eq_f(pose.support_grip_style, 1.0, 1e-05, "joined support preserves blade-clearing articulation")
				_assert_eq_f(pose.main_grip_rotation_deg, -30.0, 1e-05, "joined dominant grip rotation")
				_assert_eq_f(pose.support_grip_rotation_deg, 0.0, 1e-05, "joined support grip rotation")
			var recovery = Path.endpoint(def, 2).lerp_with(ready, step / 32.0)
			_assert_eq(recovery.paddle_hand, 0, def.display_name + " recovery must not transfer paddle")

func test_all_curves_are_reachable_without_hand_switching() -> void :
	for def in PostureLibrary.instance().all_definitions():
		for side in range(2):
			var player = CourtSide.new(side)
			for step in range(65):
				var pose = Path.sample(def, step / 64.0)
				var transform: Transform3D = Path.world_transform(player, pose)
				var wrist: Vector3 = Wrist.main_world(player, pose)
				var head: Vector3 = transform * PaddleSize.HEAD_OFFSET
				var authored_head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
				var tag: String = "%s side%d sample%d" % [def.display_name, side, step]
				_assert_eq(pose.paddle_hand, 0, tag + " hand")
				_assert_le(wrist.distance_to(Body.shoulder_world(player, pose)), 0.7001, tag + " anatomical wrist reach")
				_assert_le(head.distance_to(authored_head), 0.015, tag + " no hidden reach clipping")
				if def.posture_id in [2, 9]:
					var support_pose: PostureDefinition = pose.duplicate()
					support_pose.paddle_hand = 1
					_assert_le(Wrist.support_world(player, pose).distance_to(Body.shoulder_world(player, support_pose)), 0.7001, tag + " anatomical support wrist reach")
					if def.posture_id == 2 and step == 32:
						_assert_eq_v3(head, authored_head, 1e-05, tag + " exact original contact head")
