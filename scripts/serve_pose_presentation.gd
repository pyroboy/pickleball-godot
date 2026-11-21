extends RefCounted


const ServeGrasp = preload("res://scripts/serve_ball_grasp_profile.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Calibration = preload("res://scripts/paddle_pose_calibration.gd")
const Takeback = preload("res://scripts/serve_takeback_profile.gd")
const CONTACT_INPLANE_DEG: = -80.0
const EXACT_APPROACH_PROGRESS: = 0.65
const FINISH_JOIN_PROGRESS: = 0.18
const SUPPORT_RELEASE_POLE: = Vector3( - 0.5, - 0.1, 0.35)
const PREPARATION: = {
	0: [[Vector3(0.268672347, -0.28018862, 0.56944561), Vector3(14.979384422, -60.341945648, -120.475997925), Vector3(0.386546731, 0.080505133, -0.034918308)], [Vector3(0.238306403, -0.283293486, 0.501543999), Vector3(16.839706421, -52.887851715, -121.66758728), Vector3(0.412435412, 0.075212598, -0.090404987)], [Vector3(0.205248356, -0.308280349, 0.412751198), Vector3(17.301006317, -42.081573486, -124.426063538), Vector3(0.444252968, 0.083855629, -0.133468628)]], 
	2: [[Vector3(0.268672347, -0.28018862, 0.56944561), Vector3(14.979384422, -60.341945648, -120.475997925), Vector3(0.386546731, 0.080505133, -0.034918308)], [Vector3(0.251663089, -0.308367968, 0.494595051), Vector3(19.832241058, -51.559253693, -128.350143433), Vector3(0.397240639, 0.085531473, -0.082380772)], [Vector3(0.25058794, -0.368356466, 0.3954072), Vector3(22.07906723, -38.16727066, -138.951156616), Vector3(0.399542451, 0.106404781, -0.11612463)]], 
	3: [[Vector3(0.268672347, -0.28018862, 0.56944561), Vector3(14.979384422, -60.341945648, -120.475997925), Vector3(0.386546731, 0.080505133, -0.034918308)], [Vector3(0.239409328, -0.278944433, 0.504515171), Vector3(15.269542694, -54.232635498, -119.7735672), Vector3(0.412421227, 0.075639009, -0.090116978)], [Vector3(0.21042788, -0.289511442, 0.429198265), Vector3(13.116189957, -47.955680847000004, -118.83946228), Vector3(0.440312028, 0.082894444, -0.134466648)]], 
	4: [[Vector3(0.268672347, -0.28018862, 0.56944561), Vector3(14.979384422, -60.341945648, -120.475997925), Vector3(0.386546731, 0.080505133, -0.034918308)], [Vector3(0.238449574, -0.284812272, 0.500802517), Vector3(17.199399948, -52.599388123, -122.189590454), Vector3(0.412046432, 0.07544291, -0.090239525)], [Vector3(0.206761241, -0.314037502, 0.409778595), Vector3(17.970697403, -41.142601013, -125.787887573), Vector3(0.442665339, 0.085528612, -0.132390022)]], 
}
const WITHDRAWAL: = {
	2: [[Vector3(0.50236845, -0.266399503, 0.545469284), Vector3(41.484558105, -65.444267273, -151.595428467), Vector3(0.438771009, 0.113415837, -0.055318356)], [Vector3(0.498659134, -0.287089884, 0.482423782), Vector3(41.303482056, -59.498569489, -154.446258545), Vector3(0.438637018, 0.115514994, -0.103713989)], [Vector3(0.519115925, -0.339787602, 0.395385265), Vector3(40.346427917, -49.708240509, -163.276916504), Vector3(0.420302272, 0.128356099, -0.134074688)]], 
	4: [[Vector3(0.50236845, -0.266399503, 0.545469284), Vector3(41.484558105, -65.444267273, -151.595428467), Vector3(0.438771009, 0.113415837, -0.055318356)], [Vector3(0.481984973, -0.270178974, 0.48916769), Vector3(39.175209045, -59.724819183, -149.082626343), Vector3(0.453494668, 0.108167887, -0.115226269)], [Vector3(0.466094255, -0.299199581, 0.41616869), Vector3(36.066665649, -51.322116852, -149.855804443), Vector3(0.465748668, 0.116515517, -0.163858414)]], 
	5: [[Vector3(0.50236845, -0.266399503, 0.545469284), Vector3(41.484558105, -65.444267273, -151.595428467), Vector3(0.438771009, 0.113415837, -0.055318356)], [Vector3(0.482177019, -0.269903064, 0.489372253), Vector3(39.090511322, -59.943798065, -148.978118896), Vector3(0.453426361, 0.10847342, -0.114990711)], [Vector3(0.464316726, -0.295846939, 0.417994976), Vector3(35.79119873, -51.99533844, -149.026504517), Vector3(0.46736443, 0.116043925, -0.164746284)]], 
}
const FINISH_STANDARD: = [Vector3(-0.460939646, 0.22222662, 0.329267979), Vector3(45.890895844, 11.23029232, -56.326999664), Vector3(0.219120264, 0.066035986, 0.478845596)]
const FINISH_SLICE: = [Vector3(-0.253511786, -0.017950892, 0.319516659), Vector3(18.220769882, 14.762685776, -88.60131073), Vector3(0.43791914, 0.157611132, 0.300766945)]
const FINISH_HIGH_SOFT: = [Vector3(-0.44240129, 0.33385098, 0.300920963), Vector3(59.752948761, 5.061683178, -49.274036407), Vector3(0.20140934, 0.112215996, 0.514547825)]


const FLAT_CONTACT_POLE: = Vector3(0.478425664, 0.14486462, 0.084719255)
const DROP_CONTACT_POLE: = Vector3(0.488656059, 0.197246442, 0.147048458)


static func prepare(pose: PostureDefinition, style: int, charge: float, held_offset: Vector3) -> PostureDefinition:
	var q: float = clampf(charge, 0.0, 1.0)
	pose = Takeback.apply(pose, q)
	pose.shoulder_protraction_m = ServeGrasp.protraction(q)
	pose.left_elbow_pole = ServeGrasp.pole(q, held_offset.y)
	pose.set_meta("serve_phase_profile", true)
	pose.set_meta("serve_phase_style", style)
	pose.set_meta("serve_phase_charge", q)
	pose.set_meta("serve_phase_held_offset", held_offset)
	return pose

static func finish(pose: PostureDefinition, style: int) -> PostureDefinition:
	var values: Array = FINISH_SLICE if style == 2 else (FINISH_HIGH_SOFT if style == 3 else FINISH_STANDARD)
	var head: Vector3 = Calibration.non_contact_head_from_legacy(values[0], _basis(values[1]))
	pose.paddle_forehand_mul = head.x;pose.paddle_y_offset = head.y;pose.paddle_forward_mul = head.z
	Orientation.set_canonical_basis(pose, _basis(values[1]))
	pose.right_elbow_pole = values[2]
	return pose

static func copy_context(source: PostureDefinition, target: PostureDefinition) -> void :
	if not source.has_meta("serve_phase_profile"): return
	target.set_meta("serve_phase_profile", true)
	target.set_meta("serve_phase_style", source.get_meta("serve_phase_style"))
	target.set_meta("serve_phase_charge", source.get_meta("serve_phase_charge"))
	target.set_meta("serve_phase_held_offset", source.get_meta("serve_phase_held_offset"))

static func _basis(degrees: Vector3) -> Basis:
	var a: Vector3 = degrees * (PI / 180.0)
	return Basis(Vector3.RIGHT, a.x) * Basis(Vector3.UP, a.y) * Basis(Vector3.FORWARD, a.z)

static func _curve(a: Vector3, b: Vector3, c: Vector3, q: float) -> Vector3:
	var first: bool = q <= 0.5
	var u: float = q * 2.0 if first else (q - 0.5) * 2.0
	var start: Vector3 = a if first else b
	var end: Vector3 = b if first else c
	var shared: Vector3 = (c - a) * 0.5
	var m0: Vector3 = b - a if first else shared
	var m1: Vector3 = shared if first else c - b
	return (2 * u * u * u - 3 * u * u + 1) * start + (u * u * u - 2 * u * u + u) * m0 + (-2 * u * u * u + 3 * u * u) * end + (u * u * u - u * u) * m1
