extends SceneTree
const Profile = preload("res://scripts/body_surface_profile.gd")
const Torso = preload("res://scripts/articulated_torso_mesh.gd")
const Face = preload("res://scripts/player_face_visual.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(value: bool, label: String) -> void :
	checks += 1
	if not value: failures.append(label)
func run() -> void :
	var front: Array[PackedVector3Array] = Profile.surface_rings(false)
	var back: Array[PackedVector3Array] = Profile.surface_rings(true)
	check(front.size() == 17 and front[0].size() == 16, "bounded rounded body topology")
	for row in front.size():
		for index in front[row].size():
			var a: Vector3 = front[row][index]; var b: Vector3 = back[row][index]
			check(b.is_equal_approx(Vector3( - a.x, a.y, - a.z)), "both courts share proper anatomical facing")
	var profile: Array[Vector3] = Profile.rings()
	check(front[11][0].y > profile[11].y + 0.019 and absf(front[11][4].y - profile[11].y) < 1e-05, "shoulder shell fills cap cleft without changing centre chest")
	check( - front[10][5].z > - front[10][4].z + 0.002, "subtle bilateral pectoral contour")
	check(front[11][11].z > Profile.cross_section()[11].y * profile[11].z + 0.003, "subtle posterior scapular contour")
	for facing in [false, true]:
		var mesh: ArrayMesh = Torso._build(Color.BLUE, Color("1650ae"), Color.CYAN, facing)
		var count: int = Torso.mesh_build_count
		check(mesh == Torso._build(Color.BLUE, Color("1650ae"), Color.CYAN, facing), "body geometry cached across actors")
		check(count == Torso.mesh_build_count, "cache lookup does not rebuild")
		check(mesh.get_surface_count() == 1 and mesh.get_faces().size() / 3 <= 560, "one body draw within triangle budget")
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var skin: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var total: = 0.0
			for slot in 4: total += skin[index * 4 + slot]
			check(absf(total - 1.0) < 4.0 / 65535.0, "skin weights normalized")
			check(vertices[index].is_finite(), "finite body vertices")
		var rings: Array[PackedVector3Array] = Profile.surface_rings(facing)
		for ring in rings:
			for point in ring:
				var found: = false
				for vertex in vertices:
					if vertex.distance_squared_to(point) < 1e-12: found = true;break
				check(found, "clearance bind rings equal rendered surface")
	var chin: Vector3 = Face._ring_point(Face.HEAD_PROFILE[0], 0.0)
	var rear: Vector3 = Face._ring_point(Face.HEAD_PROFILE[0], PI)
	check(chin.z < - 0.056 and chin.y < - 0.105, "projected chin replaces pointed egg base")
	check(rear.y > chin.y + 0.015, "mandibular line rises into neck")
	check(Face.HEAD_PROFILE[2].x > Face.HEAD_PROFILE[1].x + 0.012, "cheeks taper toward jaw and chin")
	for row in Face.HEAD_PROFILE.size():
		for step in 20:
			var normal: Vector3 = Face._head_normal(Face.HEAD_PROFILE, row, TAU * step / 20.0)
			check(normal.is_finite() and absf(normal.length() - 1.0) < 1e-05, "jaw normals follow shaped surface")
	for failure in failures: push_error(failure)
	print("POSTPREVIEW BODY SHAPE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
