extends RefCounted
## Fit only actual visible editor geometry. Excludes floor, distant ball path and ghosts.
const MARGIN := .90
static func _mesh_points(node:Node, points:PackedVector3Array)->void:
	if node is Node3D and not node.is_visible_in_tree():return
	if node is MeshInstance3D and node.mesh!=null:
		var bounds:AABB=node.get_aabb()
		for corner in range(8):points.append(node.global_transform*bounds.get_endpoint(corner))
	for child in node.get_children():_mesh_points(child,points)
static func points(preview)->PackedVector3Array:
	var result:=PackedVector3Array()
	if is_instance_valid(preview.player):_mesh_points(preview.player,result)
	if is_instance_valid(preview.contact_preview):
		# The authored contact zone is an editing landmark; the illustrative feed
		# travels away from the player and must not dictate the camera distance.
		if is_instance_valid(preview.contact_preview.block):_mesh_points(preview.contact_preview.block,result)
		if is_instance_valid(preview.contact_preview.contact_marker):_mesh_points(preview.contact_preview.contact_marker,result)
	if is_instance_valid(preview.gizmo) and is_instance_valid(preview.gizmo.scene_root):_mesh_points(preview.gizmo.scene_root,result)
	# Pose Studio momentum arc (Trajectory on): its Wind-up / Contact / Finish points stay in view.
	if preview.get("momentum_on") and preview._arc_visible:result.append_array(preview.momentum_keys)
	return result
static func distance_for(preview, target:Vector3, minimum:float)->float:
	var aspect:float=float(preview.viewport.size.x)/maxf(preview.viewport.size.y,1)
	var vertical:float=tan(deg_to_rad(preview.camera.fov*.5))*MARGIN
	var horizontal:float=vertical*aspect
	var basis:Basis=preview.camera.global_transform.basis
	var required:float=minimum
	for point in points(preview):
		var local:Vector3=basis.transposed()*(point-target)
		required=maxf(required,local.z+maxf(absf(local.x)/maxf(horizontal,.01),absf(local.y)/maxf(vertical,.01))+.03)
	return required
