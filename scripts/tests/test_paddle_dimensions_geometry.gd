extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")


const D = preload("res://scripts/paddle_dimensions.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const BALL_RADIUS: = 0.0375
var checks: = 0
var failures: Array[String] = []
var outline: PackedVector2Array
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func polygon_head_distance(point: Vector3) -> float:
	var p: = Vector2(point.x, point.y)
	var minimum: = INF
	var inside: = true
	for index in outline.size():
		var a: Vector2 = outline[index]
		var edge: Vector2 = outline[(index + 1) % outline.size()] - a
		var offset: Vector2 = p - a
		var closest: Vector2 = a + edge * clampf(offset.dot(edge) / edge.length_squared(), 0.0, 1.0)
		minimum = minf(minimum, p.distance_to(closest))
		if edge.cross(offset) < -1e-08: inside = false
	var xy: float = - minimum if inside else minimum
	var z: float = absf(point.z) - D.HEAD_HALF_THICKNESS
	return Vector2(maxf(xy, 0.0), maxf(z, 0.0)).length() + minf(maxf(xy, z), 0.0)
func run() -> void :
	outline = D.head_outline()
	check(is_equal_approx(D.LENGTH, 0.4191) and is_equal_approx(D.WIDTH, 0.1905), "vendor external length/width")
	check(is_equal_approx(D.HANDLE_LENGTH, 0.1397) and is_equal_approx(D.THICKNESS, 0.016), "vendor handle/thickness")
	check(is_equal_approx(D.HEAD_CENTER_Y, 0.2794), "derived real head center")
	check(is_equal_approx(D.HANDLE_RADIUS * TAU, 0.10795), "vendor circumference conversion")
	check(outline.size() == 34 and D.head_hull_points().size() == 68, "shared render/collider outline")
	check(D.MAIN_GRIP_Y > 0 and D.MAIN_GRIP_Y < D.SUPPORT_GRIP_Y and D.SUPPORT_GRIP_Y < D.HANDLE_LENGTH, "both anchors on physical handle")
	check(is_equal_approx(Planner.IMPACT_DISTANCE, 0.1) and is_equal_approx(WristReach.DEFAULT_LINK_BUDGET, 0.7), "existing center reference and physical wrist budget")
	var error: float = G.head_outline_error_bound()
	check(error > 0.000458 and error < 0.00046, "inscribed hull error bound")
	check(G.contact_surface_tolerance() > 0 and is_equal_approx(G.contact_surface_tolerance() + error, 0.005), "physical5mm allowance includes approximation")
	var worst: = 0.0
	var accepted: = 0
	for iy in range(25):
		for ix in range(25):
			for z in [ - 0.06, - 0.008, 0.0, 0.008, 0.06]:
				var point: = Vector3( - 0.15 + ix * 0.0125, 0.1 + iy * 0.015, z)
				var analytic: float = G.distance_to_head_shape(point)
				var actual: float = polygon_head_distance(point)
				worst = maxf(worst, actual - analytic)
				check(actual >= analytic - 2e-06 and actual - analytic <= error + 2e-06, "analytic/hull bound at " + str(point))
				if analytic <= BALL_RADIUS + G.contact_surface_tolerance():
					accepted += 1
					check(actual <= BALL_RADIUS + 0.005001, "accepted point exceeds actual physical gap")
				var nearest: Vector3 = G.closest_head_surface(point, Vector3(0, 0, 1 if z <= 0 else -1))
				check(absf(G.distance_to_head_shape(nearest)) < 2e-06, "closest surface lies on shared capsule")
	check(accepted > 100, "physical boundary coverage")
	for sign_z in [-1.0, 1.0]:
		var face: Vector3 = D.HEAD_OFFSET + Vector3(0, 0, sign_z * D.HEAD_HALF_THICKNESS)
		check(absf(G.distance_to_head_shape(face)) < 1e-06, "actual thin face")
		var tangent: Vector3 = face + Vector3(0, 0, sign_z * BALL_RADIUS)
		check(absf(G.distance_to_head_shape(tangent) - BALL_RADIUS) < 1e-06, "true tangent")
		var separated: Vector3 = tangent + Vector3(0, 0, sign_z * 0.0051)
		check(G.distance_to_head_shape(separated) > BALL_RADIUS + G.contact_surface_tolerance(), "old5mm boundary is not enlarged")
	check(G.distance_to_head_shape(Vector3(0.11, 0.4, 0.05)) > BALL_RADIUS + G.contact_surface_tolerance(), "legacy oversized head no longer accepts contact")
	check(G.distance_to_paddle_shape(Vector3(0, D.MAIN_GRIP_Y, 0)) < 0 and G.distance_to_head_shape(Vector3(0, D.MAIN_GRIP_Y, 0)) > BALL_RADIUS, "handle is not a striking head")
	for point in G.sample_head_surface():
		check(point.y >= - 1e-06 and point.y <= D.LENGTH + 1e-06, "surface sample length bound")
		check(G.distance_to_paddle_shape(point) < 2e-06, "sample lies on/in physical paddle")
		if point.y > D.HANDLE_LENGTH + 1e-06: check(polygon_head_distance(point) < 2e-06, "head sample lies on exact rendered hull")
	for failure in failures: push_error(failure)
	print("PADDLE DIMENSIONS GEOMETRY: %d checks, %d failures; hull error max=%.9fm bound=%.9fm accepted=%d" % [checks, failures.size(), worst, error, accepted])
	quit(0 if failures.is_empty() else 1)
