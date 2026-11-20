extends RefCounted
## Shared authored gameplay/IK fields. Mobile selects one group at a time.
const GROUPS = ["Upper body & hips", "Feet & knees", "Arms & elbow guides", "Head", "Paddle target & grip", "Motion timing", "Joint controls"]
static func fields(group: int, base: bool) -> Array:
	match group:
		0: return ([] if base else [v("body_position_offset","Whole body position (m)",-1.5,1.5,.01)]) + [f("crouch_amount","Crouch (m)",0,.75), f("weight_shift","Forward weight shift (1 = 0.1 m)",-2,2), f("body_yaw_deg","Whole body Y rotation (°)",-180,180,1), f("body_pitch_deg","Body lean (°)",-75,75,1), f("body_roll_deg","Body side lean (°)",-60,60,1), f("hip_yaw_deg","Hips + upper body Y (°)",-120,120,1), f("torso_yaw_deg","Upper body Y rotation (°)",-120,120,1), f("torso_pitch_deg","Chest lean adjustment (°)",-75,75,1), f("torso_roll_deg","Chest side lean (°)",-60,60,1), f("spine_curve_deg","Spine curve (°)",-60,60,1), f("shoulder_protraction_m","Shoulders forward (m)",0,.05,.001)]
		1: return [f("stance_width","Stance width (m)",.15,1.4), f("front_foot_forward","Front foot forward (m)",-1,1), f("back_foot_back","Back foot forward (m)",-1,1), f("right_foot_yaw_deg","Right foot angle (°)",-180,180,1), f("left_foot_yaw_deg","Left foot angle (°)",-180,180,1), f("right_foot_pitch_deg","Right foot pitch · + toes down (°)",-30,45,1), f("left_foot_pitch_deg","Left foot pitch · + toes down (°)",-30,45,1), v("right_foot_offset","Right foot placement (m)",-1,1), v("left_foot_offset","Left foot placement (m)",-1,1), v("right_knee_pole","Right knee bend guide (m)",-1,1), v("left_knee_pole","Left knee bend guide (m)",-1,1), o("lead_foot","Lead foot",["Right","Left"])]
		2: return [o("left_hand_mode","Support hand",["Auto","Paddle grip","Balance","Raised","Custom"]), v("right_hand_offset","Right hand target offset (m)",-.5,.5), v("left_hand_offset","Left hand target offset (m)",-.5,.5), f("right_elbow_swivel_deg","Right elbow swivel · + out (°)",-360,360,1), f("left_elbow_swivel_deg","Left elbow swivel · + out (°)",-360,360,1), f("elbow_swivel_weight","Elbow swivel weight (0 = guide point)",0,1), v("right_shoulder_rotation_deg","Right elbow guide rotation (°)",-180,180,1), v("left_shoulder_rotation_deg","Left elbow guide rotation (°)",-180,180,1), v("right_elbow_pole","Right elbow guide position (m)",-1,1), v("left_elbow_pole","Left elbow guide position (m)",-1,1)]
		3: return [f("head_yaw_deg","Head turn (°)",-100,100,1), f("head_pitch_deg","Head tilt (°)",-80,80,1), f("head_track_ball_weight","Live idle body ball tracking",0,1)]
		4: return [] if base else [o("paddle_hand","Paddle hand",["Right","Left"]), f("paddle_forehand_mul","Paddle sideways (m)",-1.5,1.5), f("paddle_y_offset","Paddle height offset (m)",-1,1.5), f("paddle_forward_mul","Paddle forward (m)",-1.5,1.5), f("paddle_pitch_base_deg","Paddle pitch / tilt (°)",-180,180,1), f("paddle_yaw_base_deg","Paddle yaw / turn (°)",-180,180,1), f("paddle_roll_base_deg","Paddle roll / twist (°)",-180,180,1), f("main_grip_rotation_deg","Main grip: rotate around handle (°)",-180,180,1), f("support_grip_rotation_deg","Support grip: rotate around handle (°)",-180,180,1), f("support_grip_slide_m","Support grip: slide along handle (m)",-.05,.025,.001), f("support_index_closure","Support finger closure",0,1), f("support_grip_style","Support grip style",0,1), f("paddle_floor_clearance","Paddle floor clearance (m)",.02,.3,.005), f("paddle_pitch_signed_deg","Directional pitch adjustment (°)",-180,180,1), o("paddle_pitch_sign_source","Pitch direction source",["None","Swing direction","Forward direction"]), f("paddle_yaw_signed_deg","Directional yaw adjustment (°)",-180,180,1), o("paddle_yaw_sign_source","Yaw direction source",["None","Swing direction","Forward direction"]), f("paddle_roll_signed_deg","Directional roll adjustment (°)",-180,180,1), o("paddle_roll_sign_source","Roll direction source",["None","Swing direction","Forward direction"])]
		_: return [f("stroke_overlay_mix","Live body-stance blend",0,1), f("recovery_time","Recovery (seconds)",0,1), f("landing_lockout_time","Landing pause (seconds)",0,1), f("jump_window","Takeoff timer × 2 (seconds)",0,1), f("split_step_hop_height","Split step height (m)",0,.5), f("lunge_distance","Lunge distance (m)",0,2)] if base else [f("charge_duration","Wind-up time (seconds)",.05,1), f("swing_path_blend","Swing curve blending",0,1), f("ft_duration_strike","Strike time (seconds)",.025,.5,.005), f("ft_duration_sweep","Sweep time (seconds)",.025,.5,.005), f("ft_duration_settle","Settle time (seconds)",.025,.5,.005), f("ft_duration_hold","Hold time (seconds)",0,.5,.005)]
static func f(field:String,label:String,lo:float,hi:float,step:float=.01)->Dictionary:
	return {"field":field,"label":label,"min":lo,"max":hi,"step":step,"type":"float"}
static func v(field:String,label:String,lo:float,hi:float,step:float=.01)->Dictionary:
	var d:=f(field,label,lo,hi,step);d.type="vector";return d
static func o(field:String,label:String,items:Array)->Dictionary:
	return {"field":field,"label":label,"items":items,"type":"option"}

const JOINT_IDS=["right_elbow","left_elbow","right_knee","left_knee","right_foot","left_foot","right_hand","left_hand","hips","torso","head","paddle"]
const JOINT_LABELS=["Right elbow","Left elbow","Right knee","Left knee","Right foot","Left foot","Right hand","Left hand","Hips","Upper body","Head","Paddle"]
static func joint_fields(id:String,base:bool)->Array:
	var names:Array=[]
	match id:
		"right_elbow":names=["right_elbow_pole","right_shoulder_rotation_deg"]
		"left_elbow":names=["left_elbow_pole","left_shoulder_rotation_deg"]
		"right_knee":names=["right_knee_pole","crouch_amount"]
		"left_knee":names=["left_knee_pole","crouch_amount"]
		"right_foot":names=["right_foot_pitch_deg","right_foot_yaw_deg","right_foot_offset"]
		"left_foot":names=["left_foot_pitch_deg","left_foot_yaw_deg","left_foot_offset"]
		"right_hand":names=["right_hand_offset","main_grip_rotation_deg","support_grip_rotation_deg","support_grip_slide_m"]
		"left_hand":names=["left_hand_offset","main_grip_rotation_deg","support_grip_rotation_deg","support_grip_slide_m"]
		"hips":names=["body_position_offset","crouch_amount","weight_shift","hip_yaw_deg","body_pitch_deg","body_roll_deg"]
		"torso":names=["torso_yaw_deg","torso_pitch_deg","torso_roll_deg","spine_curve_deg","shoulder_protraction_m"]
		"head":names=["head_yaw_deg","head_pitch_deg","head_track_ball_weight"]
		"paddle":return fields(4,base)
	var result:Array=[]
	for field in names:
		for group in range(5):
			for d in fields(group,base):
				if d.field==field:result.append(d)
	return result

## New editor input limits only. Loading/importing existing authored poses does
## not normalize them; physical reach still belongs to the unchanged rig.
const WRAPPED_BODY_FIELDS = ["body_yaw_deg", "right_foot_yaw_deg", "left_foot_yaw_deg", "right_shoulder_rotation_deg", "left_shoulder_rotation_deg"]
static func body_descriptor(field: String) -> Dictionary:
	for group in range(4):
		for descriptor in fields(group, false):
			if descriptor.field == field: return descriptor
	return {}

static func body_input_value(descriptor: Dictionary, requested: float) -> float:
	if not is_finite(requested): return NAN
	if descriptor.field in WRAPPED_BODY_FIELDS:
		return requested if requested >= -180.0 and requested <= 180.0 else wrapf(requested, -180.0, 180.0)
	return clampf(requested, float(descriptor.min), float(descriptor.max))

## Rotation controls describe axes of rotation, never translation directions.
## Position guides are stance-relative except the main hand, which is paddle-local.
static func axis_label(d: Dictionary, axis: int, main_hand: bool = false) -> String:
	if axis < 0 or d.type == "component": return d.label
	if d.field.ends_with("_rotation_deg"):
		return ["Pitch about X (°)", "Yaw about Y (°)", "Roll about Z (°)"][axis]
	if main_hand and d.field.ends_with("_hand_offset"):
		return ["Paddle-local X offset (m)", "Along handle Y (m)", "Paddle-local Z offset (m)"][axis]
	return ["Sideways X (m)", "Height Y (m)", "Forward Z (m)"][axis]

# A single owner for every existing scalar/vector field. Joint selection routes
# here without changing any authored schema or setter.
const CATEGORIES = ["Upper body", "Hips & stance", "Right arm", "Left arm", "Right leg & foot", "Left leg & foot", "Head", "Paddle & hands", "Motion timing"]
const CATEGORY_JOINTS = ["torso", "hips", "right_elbow", "left_elbow", "right_foot", "left_foot", "head", "paddle", ""]
const CATEGORY_FIELDS = [
	["torso_yaw_deg","torso_pitch_deg","torso_roll_deg","spine_curve_deg","shoulder_protraction_m"],
	["body_position_offset","body_yaw_deg","hip_yaw_deg","body_pitch_deg","body_roll_deg","crouch_amount","weight_shift","stance_width","front_foot_forward","back_foot_back","lead_foot"],
	["right_elbow_pole","right_shoulder_rotation_deg"],
	["left_elbow_pole","left_shoulder_rotation_deg"],
	["right_foot_pitch_deg","right_foot_yaw_deg","right_foot_offset","right_knee_pole"],
	["left_foot_pitch_deg","left_foot_yaw_deg","left_foot_offset","left_knee_pole"],
	["head_yaw_deg","head_pitch_deg","head_track_ball_weight"],
	["paddle_hand","paddle_pitch_base_deg","paddle_yaw_base_deg","paddle_roll_base_deg","paddle_forehand_mul","paddle_y_offset","paddle_forward_mul","paddle_floor_clearance","paddle_pitch_signed_deg","paddle_pitch_sign_source","paddle_yaw_signed_deg","paddle_yaw_sign_source","paddle_roll_signed_deg","paddle_roll_sign_source","left_hand_mode","right_hand_offset","left_hand_offset","main_grip_rotation_deg","support_grip_rotation_deg","support_grip_slide_m","support_index_closure","support_grip_style"],
	[]
]
static func category_for_joint(id:String)->int:
	if id.ends_with("hand") or id=="paddle":return 7
	if id.ends_with("knee"):return 4 if id.begins_with("right") else 5
	return CATEGORY_JOINTS.find(id)

static func category_fields(index:int,base:bool)->Array:
	if index==8:return fields(5,base)
	var result:Array=[]
	for field in CATEGORY_FIELDS[index]:
		for group in range(5):
			for descriptor in fields(group,base):
				if descriptor.field==field:result.append(descriptor)
	return result
