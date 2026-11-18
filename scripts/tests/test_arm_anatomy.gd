extends SceneTree
const Anatomy = preload("res://scripts/arm_anatomy.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	for axial in [-70.0, 0.0, 70.0]:
		for flex in [-50.0, 0.0, 50.0]:
			for dev in [-20.0, 0.0, 20.0]:
				var relative: = Basis(Vector3.RIGHT, deg_to_rad(axial)) * Basis(Vector3.UP, deg_to_rad(flex)) * Basis(Vector3.BACK, deg_to_rad(dev))
				for world in [Basis.IDENTITY, Basis.from_euler(Vector3(0.31, -2.0, 0.42))]:
					var got: = Anatomy.decompose(world, world * relative)
					check(absf(got.flexion_deg - flex) < 0.001, "flexion independent of axial/world")
					check(absf(got.radial_deviation_deg - dev) < 0.001, "radial deviation independent of axial/world")
					check(absf(got.forearm_axial_deg - axial) < 0.001, "axial independent of wrist/world")
	var handshake: Basis = Anatomy.forearm_reference(Vector3(0, 1, 0), Vector3.ZERO, Vector3.FORWARD, Vector3.UP, false)
	check(handshake.x.is_equal_approx(Vector3.FORWARD) and handshake.y.is_equal_approx(Vector3.UP), "elbow-plane neutral has thumb up, not hinge normal")
	var left_handshake: Basis = Anatomy.forearm_reference(Vector3(0, 1, 0), Vector3.ZERO, Vector3.FORWARD, Vector3.UP, true)
	check(left_handshake.determinant() > 0.999 and left_handshake.y.is_equal_approx(Vector3.DOWN), "left proper transverse opposite anatomical thumbward")
	var neutral: = Anatomy.frame(Vector3.RIGHT, Vector3.UP)
	check(neutral.is_equal_approx(Basis.IDENTITY), "thumb-up neutral is declared")
	check(Anatomy.decompose(neutral, neutral).within_animation_budget, "neutral within art budget")
	check( not Anatomy.decompose(neutral, Basis(Vector3.BACK, deg_to_rad(60))).within_animation_budget, "excessive deviation reported rather than silently clamped")
	print("ARM ANATOMY ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
