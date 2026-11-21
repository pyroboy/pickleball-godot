extends RefCounted
## Only maps existing authoring degrees of freedom. No pose/rig math lives here.
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const POS := ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul"]
const ROT := ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]

static func binding(field: String, component: int, label: String) -> Dictionary:
	return {"field": field, "component": component, "label": label}

static func channels(id: String, rotate: bool, pose: Resource, base: bool, serve: bool, stage: int, support_gripping: bool = false) -> Dictionary:
	var result := {"axes": [{}, {}, {}], "note": "", "space": "stance"}
	var axes: Array = result.axes
	if id.is_empty() or pose == null:
		result.note = "Choose a part in Select joint"; return result
	if not rotate:
		var field := ""
		if id.ends_with("elbow") or id.ends_with("knee"):
			field = id + "_pole"; result.note = "Bend guide · IK keeps limbs connected"
		elif id.ends_with("foot"):
			field = id + "_offset"; result.note = "Foot placement · floor/reach limits"
		elif id.ends_with("hand"):
			var main: bool = (id == "left_hand") == (not base and pose.paddle_hand == 1)
			if main or support_gripping:
				axes[1] = binding(id + "_offset" if main else "support_grip_slide_m", 1 if main else -1, "Slide")
				result.space = "paddle"; result.note = "Grip slide along handle · X / Z locked"
			else: field = id + "_offset"; result.note = "Hand target · arm reach applies"
		elif id == "hips" and not base:
			field = "body_position_offset"; result.note = "Whole body offset · paddle fixed"
		elif id == "paddle" and not base:
			for axis in range(3): axes[axis] = binding(POS[axis], -1, ["X", "Y", "Z"][axis])
			result.note = "Paddle target · reach/floor limits"
		else: result.note = "Move unavailable · choose Rotate"
		if not field.is_empty():
			for axis in range(3): axes[axis] = binding(field, axis, ["X", "Y", "Z"][axis])
		if id.ends_with("foot") and (serve or (not base and pose.body_position_offset != Vector3.ZERO)):
			axes[1] = {}; result.note = "Foot X / Z · height stays floor-constrained"
	else:
		var fields: Array = []
		if id == "paddle" and not base:
			fields = ROT; result.note = "Paddle angles · drag colored rings"
		elif id == "hips":
			fields = ["body_pitch_deg", "hip_yaw_deg", "body_roll_deg"]
			result.note = "Body lean / hip turn / body side lean"
		elif id == "torso": fields = ["torso_pitch_deg", "torso_yaw_deg", "torso_roll_deg"]
		elif id == "head": fields = ["head_pitch_deg", "head_yaw_deg", ""]
		elif id.ends_with("foot"):
			fields = [id + "_pitch_deg", id + "_yaw_deg", ""]; result.note = "Foot pitch / yaw · grounded sole limits pitch"
		elif id.ends_with("elbow"):
			var field: String = id.replace("elbow", "shoulder_rotation_deg")
			for axis in range(3): axes[axis] = binding(field, axis, ["Pitch", "Yaw", "Roll"][axis])
			result.note = "Elbow guide rotation · grip/reach limits"
		elif id.ends_with("hand") and not base:
			var main: bool = (id == "left_hand") == (pose.paddle_hand == 1)
			if main or support_gripping:
				axes[1] = binding("main_grip_rotation_deg" if main else "support_grip_rotation_deg", -1, "Grip")
				result.note = "Grip turn around handle · one axis"
			else: result.note = "Free-hand rotation unavailable"
		else: result.note = "Rotate unavailable · Move edits bend guide" if id.ends_with("knee") else "Rotate unavailable"
		for axis in range(fields.size()):
			if not fields[axis].is_empty(): axes[axis] = binding(fields[axis], -1, ["Pitch", "Yaw", "Roll"][axis])
		if result.note.is_empty(): result.note = "Authored angles · drag colored rings"
	for axis in range(3):
		if axes[axis].is_empty(): continue
		if pose.get(axes[axis].field) == null or (serve and not Serve.is_field_editable(stage, axes[axis].field)): axes[axis] = {}
	if serve:
		if id == "paddle" and stage == 1: result.note = "Contact rotation · ball point fixed" if rotate else "Move locked · Contact ball point fixed"
		elif id.ends_with("foot") and stage != 0: result.note = "Feet planted · edit in Wind-up"
		elif id in ["left_hand", "left_elbow"] and stage == 0: result.note = "Held-ball hand protected in Wind-up"
	return result

static func available(channels: Dictionary) -> bool:
	for axis in channels.axes:
		if not axis.is_empty(): return true
	return false
