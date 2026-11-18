extends Node


const Profile = preload("res://scripts/net_profile.gd")
const Runtime = preload("res://scripts/net_runtime.gd")
const FabricShader = preload("res://shaders/net_fabric.gdshader")
const NET_HEIGHT: = Profile.SIDELINE_HEIGHT
const MESH_COLUMNS: = 80
const MESH_ROWS: = 12

func create_net(parent: Node3D) -> StaticBody3D:
	var net: = Runtime.new()
	net.name = "Net"
	parent.add_child(net)
	net.collision_layer = 4
	net.collision_mask = 1
	var material: = PhysicsMaterial.new()
	material.bounce = 0.68
	material.absorbent = true
	material.friction = 0.8
	net.physics_material_override = material
	_add_fabric(net, false)
	_add_fabric(net, true)
	_add_collision(net)
	_add_posts(net)
	return net

func _add_fabric(net: StaticBody3D, tape: bool) -> void :
	var st: = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = 1 if tape else MESH_ROWS
	for row in range(rows):
		for column in range(MESH_COLUMNS):
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var u: float = float(column + corner.x) / MESH_COLUMNS
				var x: float = lerpf( - Profile.HALF_SPAN, Profile.HALF_SPAN, u)
				var v: float = float(row + corner.y) / rows
				if tape: v = lerpf(1.0 - Profile.TAPE_WIDTH / Profile.height_at(x), 1.0, v)
				st.set_uv(Vector2(u, v))
				st.set_normal(Vector3.FORWARD)
				st.add_vertex(Vector3(x, Profile.FLOOR_Y + Profile.height_at(x) * v, 0.001 if tape else 0.0))
	var instance: = MeshInstance3D.new()
	instance.name = "TopTape" if tape else "WovenFabric"
	instance.mesh = st.commit()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: = ShaderMaterial.new()
	material.shader = FabricShader
	material.set_shader_parameter("tape", tape)
	instance.material_override = material
	net.add_child(instance)
	net.register_material(material)

func _add_collision(net: StaticBody3D) -> void :


	for i in range(Profile.COLLISION_SEGMENTS):
		var left: float = lerpf( - Profile.HALF_SPAN, Profile.HALF_SPAN, float(i) / Profile.COLLISION_SEGMENTS)
		var right: float = lerpf( - Profile.HALF_SPAN, Profile.HALF_SPAN, float(i + 1) / Profile.COLLISION_SEGMENTS)
		var vertices: = PackedVector3Array()
		for x in [left, right]:
			for y in [Profile.FLOOR_Y - 0.01, Profile.top_y_at(x)]:
				for z in [ - Profile.THICKNESS / 2.0, Profile.THICKNESS / 2.0]: vertices.append(Vector3(x, y, z))
		var shape: = ConvexPolygonShape3D.new()
		shape.points = vertices
		shape.margin = 0.001
		var collision: = CollisionShape3D.new()
		collision.name = "NetSegment%02d" % i
		collision.shape = shape
		net.add_child(collision)

func _add_posts(net: StaticBody3D) -> void :
	var post_material: = StandardMaterial3D.new()
	post_material.albedo_color = Color(0.18, 0.23, 0.26)
	post_material.roughness = 0.5
	for direction in [-1.0, 1.0]:
		var post: = MeshInstance3D.new()
		post.name = "LeftPost" if direction < 0.0 else "RightPost"
		var cylinder: = Profile.post_mesh()
		post.mesh = cylinder
		post.material_override = post_material
		post.position = Vector3(direction * Profile.HALF_SPAN, Profile.FLOOR_Y + cylinder.height * 0.5, 0.0)
		net.add_child(post)
		var collision := CollisionShape3D.new()
		collision.name = String(post.name) + "Collision"
		var shape := ConvexPolygonShape3D.new()
		shape.points = cylinder.get_faces()
		shape.margin = 0.0
		collision.shape = shape
		collision.position = post.position
		net.add_child(collision)

func get_net_height() -> float:
	return Profile.CENTER_HEIGHT
