extends RefCounted
## The human player's swing as pure functions: one definition shared by the game
## (human_contact_controller.gd) and Pose Studio's Hold / Play (mobile_pose_sequence.gd), so the
## studio cannot drift from the game. Nothing here reads input, the ball or the scene.
const DriveMotion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const BodyTurn = preload("res://scripts/rally_body_turn.gd")

## Power (0..1) from how long Hit was held (input_handler.gd: charge time / the full-charge time).
static func charge_for_hold(seconds: float) -> float:
	return clampf(seconds / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.0, 1.0)

## Game rules laid over every pose of a human swing (today: the forehand's forced body turn,
## rally_body_turn.gd). The authored pose is not changed.
static func layers(pose: PostureDefinition) -> PostureDefinition:
	return BodyTurn.sample(pose)

## Stroke progress (0 Wind-up .. 0.5 Contact) at fraction `factor` of the strike time: an even
## pace, or the stroke's own strike easing when it has one.
static func strike_progress(def: PostureDefinition, factor: float) -> float:
	return 0.5 * Ramp.normalized(def, Ramp.STRIKE, factor) if Ramp.custom(def, Ramp.STRIKE) else factor * 0.5

## The pose at fraction `factor` of the strike: the swing at that progress, eased out of the
## pose the hand had at release (`start_pose`, may be null).
static func strike_pose(def: PostureDefinition, factor: float, charge: float, is_volley: bool, spin_mode: int, near_kitchen: bool,
		shot_intent: String, motion_context: Dictionary, start_pose: PostureDefinition) -> PostureDefinition:
	var pose: PostureDefinition = layers(DriveMotion.sample_drive(def, strike_progress(def, factor), charge, is_volley, spin_mode, near_kitchen, shot_intent, motion_context))
	if start_pose:
		pose = Path.blend_pose(pose, start_pose, pow(1.0 - factor, 2.0))
	return pose

## Stroke progress (0.5 Contact .. 1 Finish) at fraction `time_fraction` of the follow-through time.
static func finish_progress(def: PostureDefinition, time_fraction: float) -> float:
	return Path.release_progress(def, 1, clampf(time_fraction, 0, 1))

## The pose at that point of the follow-through, eased out of the pose at contact (`start_pose`).
static func finish_pose(def: PostureDefinition, time_fraction: float, charge: float, is_volley: bool, spin_mode: int, near_kitchen: bool,
		shot_intent: String, motion_context: Dictionary, start_pose: PostureDefinition) -> PostureDefinition:
	var factor: float = finish_progress(def, time_fraction)
	var pose: PostureDefinition = layers(DriveMotion.sample_drive(def, factor, charge, is_volley, spin_mode, near_kitchen, shot_intent, motion_context))
	if start_pose:
		pose = Path.blend_pose(pose, start_pose, pow(clampf((1.0 - factor) * 2.0, 0.0, 1.0), 2.0))
	return pose
