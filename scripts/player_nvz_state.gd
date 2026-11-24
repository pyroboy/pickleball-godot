extends RefCounted



const SurfaceContacts = preload("res://scripts/player_surface_contacts.gd")
const LINE_EPSILON: = 0.0001
const GROUND_EPSILON: = 0.006
const FAR_FROM_KITCHEN_M := 1.8
var established_outside: = false
var _last_root: = Vector3.INF

static func footprints(player) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ik = player.leg_ik if "leg_ik" in player else null
	if ik == null or not ik.feet_initialized: return result
	for side in [0, 1]:
		var foot: Vector3 = ik.right_foot_smooth if side == 0 else ik.left_foot_smooth
		var leg = player.right_leg_node if side == 0 and "right_leg_node" in player else (player.left_leg_node if "left_leg_node" in player else null)
		var minimum: Vector3 = foot - Vector3(0.06, 0.04, 0.13)
		var maximum: Vector3 = foot + Vector3(0.06, 0.01, 0.13)
		if leg != null and "foot_mesh" in leg and leg.foot_mesh != null and leg.foot_mesh.mesh != null:


			var mesh: MeshInstance3D = leg.foot_mesh
			var ankle: = Transform3D(leg.foot_pivot.global_transform.basis, foot)
			var transform: Transform3D = ankle * mesh.transform
			minimum = Vector3.INF
			maximum = - Vector3.INF
			var box: AABB = mesh.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = transform * box.get_endpoint(corner)
				minimum = minimum.min(point)
				maximum = maximum.max(point)
		var grounded: bool = minimum.y <= PickleballConstants.FLOOR_Y + GROUND_EPSILON
		var within_width: bool = maximum.x >= - PickleballConstants.COURT_WIDTH * 0.5 and minimum.x <= PickleballConstants.COURT_WIDTH * 0.5
		var inside: bool = within_width and maximum.z >= - PickleballConstants.NON_VOLLEY_ZONE - LINE_EPSILON and minimum.z <= PickleballConstants.NON_VOLLEY_ZONE + LINE_EPSILON
		result.append({"grounded": grounded, "inside": inside, "min": minimum, "max": maximum})
	return result

func update(player) -> void :
	if _last_root.is_finite() and player.global_position.distance_to(_last_root) > 1.5:
		established_outside = false
	_last_root = player.global_position
	var ik = player.leg_ik if "leg_ik" in player else null
	if ik != null and "_last_body_position" in ik:
		var stale: float = Vector2(player.global_position.x - ik._last_body_position.x, player.global_position.z - ik._last_body_position.z).length()
		if stale > 0.85:
			established_outside = false
			return
	var feet: Array[Dictionary] = footprints(player)
	if feet.size() != 2:
		established_outside = false
		return
	var other_inside := false
	# Perf: no body part of a player standing more than FAR_FROM_KITCHEN_M behind the kitchen
	# line can be on the ground inside the kitchen, so the mesh scan is skipped for them.
	if absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + FAR_FROM_KITCHEN_M:
		for contact in SurfaceContacts.ground_contacts(player):
			if contact.inside: other_inside = true
	if other_inside: established_outside = false
	var both_outside: = not other_inside
	for foot in feet:
		if foot.grounded and foot.inside: established_outside = false
		both_outside = both_outside and foot.grounded and not foot.inside
	if both_outside: established_outside = true

func can_volley(player) -> bool:
	update(player)
	return established_outside

static func ground_contacts(player) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = footprints(player)
	contacts.append_array(SurfaceContacts.ground_contacts(player))
	return contacts

static func touches_ground(player) -> bool:
	var contacts: Array[Dictionary] = ground_contacts(player)
	if contacts.is_empty():
		# Compatibility for non-rig rule fixtures only. Real players are measured.
		if "body_pivot" in player: return false
		if "is_jumping" in player and player.is_jumping: return false
		return absf(player.global_position.x) <= PickleballConstants.COURT_WIDTH * 0.5 + LINE_EPSILON and absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + LINE_EPSILON
	for contact in contacts:
		if contact.grounded and contact.inside: return true
	return false
