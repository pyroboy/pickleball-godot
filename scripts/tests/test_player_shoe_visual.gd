extends SceneTree
const Shoe = preload("res://scripts/player_shoe_visual.gd")
var checks: = 0
var failures: Array[String] = []

func _initialize() -> void : call_deferred("run")

func check(value: bool, message: String) -> void :
	checks += 1
	if not value: failures.append(message)

func run() -> void :
	for palette in [[Color("168be4"), Color("1650ae")], [Color("d84d60"), Color("942e46")]]:
		var mesh: ArrayMesh = Shoe.mesh(palette[0], palette[1])
		check(mesh == Shoe.mesh(palette[0], palette[1]), "identical shoes share a cached mesh")
		check(mesh.get_surface_count() == 1, "all shoe details share one draw call")
		var bounds: = mesh.get_aabb()
		check(bounds.position.is_equal_approx(Vector3( - 0.05, - 0.025, - 0.08)), "shoe AABB origin preserves sole/NVZ/serve geometry")
		check(bounds.size.is_equal_approx(Vector3(0.1, 0.05, 0.16)), "shoe AABB size preserves sole/NVZ/serve geometry")
		var arrays: = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(indices.size() / 3 < 450, "shoe stays in the mobile triangle budget")
		var lace_count: = 0
		var lining_count: = 0
		var upper_count: = 0
		for i in range(vertices.size()):
			check(vertices[i].is_finite() and normals[i].is_finite(), "shoe contains no invalid vertex or normal")
			if colors[i].is_equal_approx(Shoe.LACE):
				lace_count += 1
				check(vertices[i].y > 0.007, "laces sit on the raised instep")
			if colors[i].is_equal_approx(Shoe.LINING): lining_count += 1
			if colors[i].is_equal_approx(Shoe.UPPER): upper_count += 1
		check(lace_count > 12 and lining_count > 12 and upper_count > 30, "laces, recessed ankle lining, and shaped upper are present")
		var foot: = MeshInstance3D.new()
		root.add_child(foot)
		foot.position = Vector3(0.2, - 0.015, - 0.03)
		foot.rotation_degrees = Vector3(12, 28, -8)
		var original: = foot.transform
		var material: = StandardMaterial3D.new()
		Shoe.apply(foot, palette[0], palette[1], material)
		check(foot.transform.is_equal_approx(original), "shoe replacement preserves foot/contact transform")
		check(foot.get_child_count() == 0 and foot.material_override == material, "shoe adds no feature nodes or materials")
		foot.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER SHOE VISUAL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
