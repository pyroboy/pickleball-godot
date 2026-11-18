extends SceneTree
const Face = preload("res://scripts/player_face_visual.gd")
const Gaze = preload("res://scripts/player_head_gaze.gd")
const SKIN: = Color("dbb18b")
var checks: = 0
var failures: Array[String] = []

func _initialize() -> void : call_deferred("run")

func check(value: bool, message: String) -> void :
	checks += 1
	if not value: failures.append(message)

func run() -> void :
	for forward in [Vector3.FORWARD, Vector3.BACK]:
		var mesh: ArrayMesh = Face.mesh(SKIN, forward)
		check(mesh == Face.mesh(SKIN, forward), "face geometry is cached")
		check(mesh.get_surface_count() == 1, "all features fit the existing head draw call")
		var arrays: = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(indices.size() / 3 < 2200, "head stays in the mobile triangle budget")
		check(colors.size() == vertices.size() and normals.size() == vertices.size(), "every vertex has a baked color and normal")
		var skin_count: = 0
		var front_eye_count: = 0
		var nose_count: = 0
		var ear_count: = 0
		for i in range(vertices.size()):
			check(vertices[i].is_finite() and normals[i].is_finite(), "face contains no invalid vertex or normal")
			if colors[i].is_equal_approx(SKIN): skin_count += 1
			if colors[i].is_equal_approx(Face.EYE_WHITE):
				front_eye_count += 1
				check(vertices[i].dot(forward) > 0.055, "eyes face the player's own forward direction")
			if vertices[i].dot(forward) > 0.102: nose_count += 1
			if absf(vertices[i].x) > 0.091: ear_count += 1
		check(skin_count > 150, "head/ears/nose use the hand skin palette")
		check(front_eye_count > 30 and nose_count > 0 and ear_count > 0, "eyes, projecting nose, and ear silhouette exist")
		var head: = MeshInstance3D.new()
		root.add_child(head)
		head.position = Vector3(0.2, 0.8, 0.4)
		head.basis = Gaze.local_gaze_basis(Basis.IDENTITY, forward, forward + Vector3(0.3, 0.2, 0))
		var original: = head.transform
		var old_eye: = MeshInstance3D.new()
		old_eye.mesh = SphereMesh.new()
		head.add_child(old_eye)
		var attachment: = Marker3D.new()
		head.add_child(attachment)
		var material: = StandardMaterial3D.new()
		Face.apply(head, SKIN, forward, material)
		check(head.transform.is_equal_approx(original), "face replacement preserves gaze pivot and orientation")
		check(head.get_child_count() == 1 and head.get_child(0) == attachment, "legacy eye draw calls removed without removing attachments")
		check(head.material_override == material, "face shares the supplied athlete material")
		Face.apply(head, SKIN, forward, material)
		check(head.mesh == mesh and head.get_child_count() == 1, "reapplying face creates no mesh or nodes")
		head.queue_free()
	var other_skin: ArrayMesh = Face.mesh(Color("8c5a40"))
	check(other_skin != Face.mesh(SKIN), "different skin selections get separate cached geometry")
	await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER FACE VISUAL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
