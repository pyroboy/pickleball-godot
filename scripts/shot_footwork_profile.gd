extends RefCounted
## The selected tactical profile informs support timing, never contact authority.
## Existing authored feet remain untouched unless a movement plan owns the stance.

static func from_context(context: Dictionary) -> Dictionary:
	var profile: String = str(context.get("profile", "LEGACY")).to_upper()
	var result := {"profile": profile, "kind": "standard", "width": 0.54,
		"front": 0.06, "back": -0.06, "load_time": 0.08,
		"recovery_distance": 0.28, "recovery_speed": 0.85}
	match profile:
		"JAMMED":
			result.merge({"kind": "jam_clearance", "width": 0.58, "front": 0.08,
				"back": -0.14, "load_time": 0.09, "recovery_distance": 0.18, "recovery_speed": 0.65}, true)
		"HALF_VOLLEY":
			result.merge({"kind": "short_hop_settle", "width": 0.60, "front": 0.10,
				"back": -0.08, "load_time": 0.06, "recovery_distance": 0.16, "recovery_speed": 0.60}, true)
		"BLOCK", "RESET":
			result.merge({"kind": "absorb", "width": 0.58, "load_time": 0.06,
				"recovery_distance": 0.16, "recovery_speed": 0.60}, true)
	if str(context.get("recovery_kind", "")) in ["emergency", "extended_reach", "reach"]:
		result.merge({"kind": "emergency_recenter", "width": 0.66,
			"load_time": 0.10, "recovery_distance": 0.24, "recovery_speed": 0.60}, true)
	return result

static func context_from(contact: Dictionary) -> Dictionary:
	var context: Variant = contact.get("motion_context", {})
	return context if context is Dictionary else {}
