extends Node
## Net.gd - Creates the pickleball net
##
## NOTE on net posts: real pickleball has separate metal posts outside the
## sidelines. This game models the net as a single StaticBody3D with a box
## collider spanning COURT_WIDTH - 0.2. No distinct post colliders exist, so
## the "serve hits post = fault" rule (USA Pickleball Rule 4.L) is not
## enforced — there's no physical target to detect. Balls passing through the
## 0.1m gap where posts would be are already out-of-bounds via the sideline
## check, so the practical rule impact is zero.

const COURT_WIDTH := 6.1
const NET_HEIGHT := 0.91

func create_net(parent: Node3D) -> StaticBody3D:
	var net: StaticBody3D = StaticBody3D.new()
	net.name = "Net"
	parent.add_child(net)
	net.global_position = Vector3(0, NET_HEIGHT / 2.0, 0)
	
	var net_mesh: BoxMesh = BoxMesh.new()
	net_mesh.size = Vector3(COURT_WIDTH - 0.2, NET_HEIGHT, 0.04)
	
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = net_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.95)
	mesh_inst.material_override = mat
	net.add_child(mesh_inst)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(COURT_WIDTH - 0.2, NET_HEIGHT, 0.04)
	col.shape = shape
	net.add_child(col)
	
	net.physics_material_override = PhysicsMaterial.new()
	net.physics_material_override.bounce = 0.3
	net.physics_material_override.friction = 0.8
	
	return net

func get_net_height() -> float:
	return NET_HEIGHT
