extends TestBase
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Wrist = preload("res://scripts/tests/pose_anatomical_wrist.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_ready_face_clearance, test_authored_swept_clearance, test_contextual_swept_clearance, test_partial_charge_serve_clearance])

func test_ready_face_clearance() -> void :
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	for side in [0, 1]:
		var player = Side.new(side)
		for pose in [ready, Motion.kitchen_ready(ready)]:
			_assert_ge(Geometry.face_clearance(player, pose), 0.08, "ready paddle has comfortable face clearance")
			_assert_ge(Geometry.sampled_chest_clearance(player, pose, surface), 0.08, "ready paddle stays ahead of chest")
			var basis: Basis = Path.paddle_basis(player, pose)


			var face_angle: float = rad_to_deg(acos(clampf(absf(basis.z.dot(player._get_forward_axis())), 0.0, 1.0)))
			_assert_in_range(face_angle, 49.0, 51.0, "joined Ready retains approved 50-degree oblique blade")
			_assert_gt(basis.y.y, 0.0, "ready head stays above handle")
			_assert_eq_f(basis.determinant(), 1.0, 1e-05, "ready uses a proper rotation")

func test_authored_swept_clearance() -> void :
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	for def in PostureLibrary.instance().all_definitions():
		for side in [0, 1]:
			var player = Side.new(side)
			for step in range(65):
				var pose: PostureDefinition = Path.sample(def, step / 64.0)
				var tag: String = "%s side%d sample%d" % [def.display_name, side, step]
				_assert_gt(Geometry.face_clearance(player, pose), 0.01, tag + " paddle intersects face")
				_assert_ge(Geometry.sampled_chest_clearance(player, pose, surface), 0.0, tag + " paddle intersects chest")

func test_contextual_swept_clearance() -> void :
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	for id in [0, 2, 4, 5, 7]:
		for mode in range(3):
			for side in [0, 1]:
				var player = Side.new(side)
				var def: PostureDefinition = PostureLibrary.instance().get_def(id)
				for step in range(33):
					var pose: PostureDefinition = Motion.sample_drive(def, step / 32.0, 1.0, false, mode)
					var tag: String = "%s spin%d side%d sample%d" % [def.display_name, mode, side, step]
					_assert_gt(Geometry.face_clearance(player, pose), 0.01, tag + " profile paddle intersects face")
					_assert_ge(Geometry.sampled_chest_clearance(player, pose, surface), 0.0, tag + " profile paddle intersects chest")

func test_partial_charge_serve_clearance() -> void :
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	for side in [0, 1]:
		var player = Side.new(side)
		for charge in [0.05, 0.25, 0.5, 0.75, 1.0]:
			for spin in range(3):
				var previous: Array[Basis] = []
				for step in range(65):
					var t: float = step / 64.0
					var poses: Array[PostureDefinition] = [
						Motion.serve_strike(Motion.serve_preparation(charge, spin), t, spin), 
						Motion.serve_follow_through(charge, t, spin), 
						Motion.ServeJoint.recover_to_ready(Motion.serve_follow_through(charge, 1.0, spin), ready, t), 
						Motion.sample_drive(PostureLibrary.instance().get_def(3), t, charge, false, spin), 
						Motion.sample_drive(PostureLibrary.instance().get_def(4), t, charge, false, spin)]
					for kind in range(poses.size()):
						var pose: PostureDefinition = poses[kind]
						var tag: String = "side%d power%.2f spin%d phase%d sample%d" % [side, charge, spin, kind, step]
						var tx: Transform3D = Path.world_transform(player, pose)
						_assert_ge(Geometry.face_clearance(player, pose), 0.04, tag + " face clearance")
						_assert_ge(Geometry.sampled_chest_clearance(player, pose, surface), 0.04, tag + " chest clearance")
						_assert_le(Wrist.main_world(player, pose).distance_to(Geometry.Body.shoulder_world(player, pose)), 0.7001, tag + " anatomical wrist reach")
						if step == 0: previous.append(tx.basis)
						else:
							_assert_lt(previous[kind].get_rotation_quaternion().angle_to(tx.basis.get_rotation_quaternion()), deg_to_rad(18.0), tag + " discontinuous rotation")
							previous[kind] = tx.basis
