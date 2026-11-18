extends RefCounted

const Kit = preload("res://scripts/tests/fixtures/player_athlete_visual_before_knee.gd")
static func mesh(thigh_length: float, shin_length: float, upper: bool, shorts: Color, skin: Color, sock: Color) -> ArrayMesh:
	if upper:
		var half: = thigh_length * 0.5
		return Kit._limb_rings([Vector3(0.052, - half, 0.055), Vector3(0.071, - half * 0.12, 0.068), 
			Vector3(0.094, - half * 0.1, 0.088), Vector3(0.096, half * 0.72, 0.091), Vector3(0.083, half, 0.077)], 
			[skin, skin, shorts, shorts, shorts], 10)
	var half: = shin_length * 0.5
	return Kit._limb_rings([Vector3(0.037, - half, 0.039), Vector3(0.044, - half * 0.22, 0.045), 
		Vector3(0.043, - half * 0.2, 0.044), Vector3(0.052, half * 0.5, 0.054), Vector3(0.049, half, 0.051)], 
		[sock, sock, skin, skin, skin], 10)
