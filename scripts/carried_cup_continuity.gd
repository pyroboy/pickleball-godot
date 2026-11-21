extends RefCounted
const META="carried_cup_continuity"
static func remember(player)->void:
 var arm=player.left_arm_node
 player.set_meta(META,{"basis":arm.hand_mesh.global_basis.orthonormalized(),"elbow":arm.forearm_pivot.global_position,"upper":arm.upper_pivot.global_basis.orthonormalized(),"fore":arm.forearm_pivot.global_basis.orthonormalized(),"body":player.body_pivot.global_transform,"tick":Engine.get_physics_frames()})
