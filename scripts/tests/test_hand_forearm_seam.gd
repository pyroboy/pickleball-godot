extends SceneTree


const Hand = preload("res://scripts/articulated_hand.gd")
const ArmVisual = preload("res://scripts/player_arm_visual.gd")
var checks: = 0
var failures: Array[String] = []
class MockArm extends Node3D:
	var hand_mesh: = MeshInstance3D.new()
	func _init() -> void : add_child(hand_mesh)
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func mirror(v: Vector3, left: bool) -> Vector3: return Vector3( - v.x, v.y, v.z) if left else v
func nearest(origin: Vector3, direction: Vector3, triangles: PackedVector3Array) -> float:
	var distance: = INF
	for i in range(0, triangles.size(), 3):
		var point = Geometry3D.ray_intersects_triangle(origin, direction, triangles[i], triangles[i + 1], triangles[i + 2])
		if point != null: distance = minf(distance, origin.distance_to(point))
	return distance
func run() -> void :


	var shoulder: = Vector3(1.68572556972504, 1.31954073905945, 6.92269134521484)
	var elbow: = Vector3(1.94425249099731, 1.08385634422302, 6.93346881866455)
	var wrist: = Vector3(1.92000019550323, 0.880000054836273, 6.65000009536743)
	var anatomical_world: = Basis(Quaternion( - 0.478967040777206, 0.722439229488373, 0.112821623682976, 0.485740095376968).normalized())
	var fore_y: Vector3 = (wrist - elbow).normalized()
	var fore_x: Vector3 = (wrist - shoulder).cross(elbow - shoulder).normalized()
	var fore_world: = Basis(fore_x, fore_y, fore_x.cross(fore_y))
	var fore_mesh: ArrayMesh = ArmVisual._build(0.35, false, Color.WHITE, Hand.SKIN_COLOR)
	check(fore_mesh.get_surface_count() == 1, "unchanged single forearm surface")
	var fore_faces: PackedVector3Array = fore_mesh.get_faces()
	var normals: PackedVector3Array = fore_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal in normals: check(normal.is_finite() and normal.length() > 0.99, "finite unit forearm normal")
	var right_basis: = Basis.IDENTITY
	var right_frame: = Basis.IDENTITY
	for left in [false, true]:
		var arm: = MockArm.new();root.add_child(arm)
		var model: = Hand.new();model.initialize(arm, left);model.set_pose("GRIP")
		if not left:
			right_basis = model.anatomical_basis
			var mesh_world: Basis = anatomical_world * right_basis.inverse()
			right_frame = mesh_world.inverse() * fore_world
		var frame: Basis = right_frame
		if left: frame = Basis( - mirror(frame.x, true), mirror(frame.y, true), mirror(frame.z, true))
		check(frame.determinant() > 0.99999, "proper mirrored forearm frame")
		for bend in [-35.0, 0.0, 35.0]:
			var rotated: Basis = Basis(mirror(right_basis.y, left), deg_to_rad(bend)) * frame
			model.update_wrist_bridge(rotated)
			var tx: = Transform3D(rotated, model.wrist_socket - rotated.y * 0.175)
			var triangles: = PackedVector3Array()
			for point in fore_faces: triangles.append(tx * point)
			var skin: PackedVector3Array = model.sampled_triangles()
			for along in [ - 0.001, 0.002, 0.006]:
				for across in [0.0, 0.01, 0.016]:
					var origin: Vector3 = model.wrist_socket + mirror(right_basis.x, left) * along + mirror(right_basis.y, left) * across + mirror(right_basis.z, left) * 0.2
					var direction: Vector3 = - mirror(right_basis.z, left)
					var palm: float = nearest(origin, direction, skin)
					var fore: float = nearest(origin, direction, triangles)
					check(is_finite(palm), "dorsal heel remains a closed skin surface")
					check(fore >= palm - 5e-05, "forearm stays behind dorsal heel left=%s bend=%.0f along=%.3f across=%.3f gap=%.6f" % [left, bend, along, across, fore - palm])
		arm.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("HAND FOREARM SEAM: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
