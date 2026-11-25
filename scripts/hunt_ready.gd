extends RefCounted
## Hunting ready pose: at the kitchen line in a soft rally the player waits with the paddle
## down and out in front, set to take the next ball out of the air, instead of the upright
## Ready. A baked pose (data/ready_variants/hunt_ready.tres, a Ready variant that keeps
## posture id 20 so every "is Ready" rule still holds), never solved in play.
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const PATH := "res://data/ready_variants/hunt_ready.tres"

static var _pose: PostureDefinition
static var _loaded := false

static func pose() -> PostureDefinition:
	if not _loaded:
		_loaded = true
		_pose = ResourceLoader.load(PATH) as PostureDefinition
	return _pose

## Soft rally ball in play (both bounces done, under HUNT_MAX_SPEED) and the player within
## HUNT_DEPTH m of the kitchen line. A fast ball brings the paddle back up to Ready.
static func hunting(player, ball) -> bool:
	if not Tuning.HUNT_POSE_ON or player == null or ball == null or pose() == null: return false
	if not ball.is_in_play or not ball.both_bounces_complete: return false
	if absf(player.global_position.z) > PickleballConstants.NON_VOLLEY_ZONE + Tuning.HUNT_DEPTH: return false
	return ball.linear_velocity.length() < Tuning.HUNT_MAX_SPEED

## The waiting pose for this player now: Hunt Ready while hunting, else Ready.
static func ready_for(player, ball) -> PostureDefinition:
	return pose() if hunting(player, ball) else PostureLibrary.instance().get_def(player.PaddlePosture.READY)
