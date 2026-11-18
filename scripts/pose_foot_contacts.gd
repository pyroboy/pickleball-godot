extends RefCounted
## Pure contact contract. Body/torso/hip channels never own the court anchors.
## Authored foot placement/yaw are intentional contact edits, not body motion.
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const MIN_KNEE_DEG := 1.0
const MAX_KNEE_DEG := 155.0

static func authored(def, root: Vector3, forehand: Vector3, forward: Vector3, ankle_y: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(2):
		var right := index == 0
		var side := 1.0 if right else -1.0
		var lead: bool = def.lead_foot == index
		var offset: Vector3 = def.right_foot_offset if right else def.left_foot_offset
		var position: Vector3 = root + forehand * (side * def.stance_width * .5 + offset.x) + forward * ((def.front_foot_forward if lead else def.back_foot_back) + offset.z)
		position.y = ankle_y + offset.y
		var yaw: float = atan2(-forward.x, -forward.z) - deg_to_rad(def.right_foot_yaw_deg if right else def.left_foot_yaw_deg)
		result.append({"position": position, "yaw": yaw, "planted": offset.y <= .00001, "reason": "authored lift" if offset.y > .00001 else "court contact"})
	return result

static func split_sample(contacts: Array[Dictionary], sample: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = contacts.duplicate(true)
	var active: bool = bool(sample.get("active", false)) and str(sample.get("phase", "ready")) in ["split_load", "split_unweight", "split_land"]
	var lift := clampf(float(sample.get("foot_lift", 0.0)), 0.0, .025) if active else 0.0
	for contact in result:
		contact.position += Vector3.UP * lift
		contact.planted = contact.planted and lift <= .00001
		if lift > .00001: contact.reason = "explicit split-step flight"
	return result

static func reach_report(hip: Vector3, anchor: Vector3, thigh: float = Dimensions.THIGH_LENGTH, shin: float = Dimensions.SHIN_LENGTH) -> Dictionary:
	var requested := hip.distance_to(anchor)
	var minimum := sqrt(maxf(0.0, thigh * thigh + shin * shin + 2.0 * thigh * shin * cos(deg_to_rad(MAX_KNEE_DEG))))
	var maximum := sqrt(maxf(0.0, thigh * thigh + shin * shin + 2.0 * thigh * shin * cos(deg_to_rad(MIN_KNEE_DEG))))
	var distance := clampf(requested, minimum, maximum)
	return {"feasible": absf(requested - distance) <= .00001, "requested_distance": requested, "applied_distance": distance,
		"minimum": minimum, "maximum": maximum, "anchor": anchor, "limited": absf(requested - distance) > .00001,
		"reason": "" if absf(requested - distance) <= .00001 else "Planted foot unreachable: move hips within leg reach or explicitly move the foot"}
