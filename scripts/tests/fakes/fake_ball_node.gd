class_name FakeBallNode extends Node
## Node-based fake ball for tests that need a Node (e.g. ShotPhysics).
## For RefCounted-based ball (RallyScorer tests), use FakeBall instead.

var global_position: Vector3 = Vector3.ZERO
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var last_hit_by: int = -1
var bounces_since_last_hit: int = 0
var ball_bounced_since_last_hit: bool = false
var was_volley: bool = false
var is_in_play: bool = true
var bounce_count: int = 0
var can_register_floor_bounce: bool = true
var was_above_bounce_height: bool = true
