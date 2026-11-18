extends RefCounted
# Counts direct Ready transforms and actual full-pose clone call sites only.
# Nested production geometry helpers are unchanged and are not counted here.
const ActualPath = preload("res://scripts/stroke_swing_path.gd")
static var transforms: int = 0
static var pose_clones: int = 0
static var side_clones: int = 0
static var budget_clones: int = 0
static var reach_checks: int = 0
static var wrist_checks: int = 0
static var wrist_channels: int = 0
static func reset() -> void:
	pose_clones = 0; side_clones = 0; budget_clones = 0
	transforms = 0; reach_checks = 0; wrist_checks = 0; wrist_channels = 0
static func counts() -> Dictionary:
	return {"pose_clones": pose_clones, "side_clones": side_clones, "budget_clones": budget_clones, "transforms": transforms, "reach_checks": reach_checks, "wrist_checks": wrist_checks, "wrist_channels": wrist_channels}
static func world_transform(player, pose: PostureDefinition) -> Transform3D:
	transforms += 1
	return ActualPath.world_transform(player, pose)
static func canonical_transform(pose: PostureDefinition) -> Transform3D:
	return ActualPath.canonical_transform(pose)
static func _support_mode(pose: PostureDefinition) -> int:
	return ActualPath._support_mode(pose)
