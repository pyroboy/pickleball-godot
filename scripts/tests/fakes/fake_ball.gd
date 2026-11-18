class_name FakeBall extends RefCounted










var global_position: Vector3 = Vector3.ZERO
var linear_velocity: Vector3 = Vector3.ZERO

var last_hit_by: int = -1
var bounces_since_last_hit: int = 0
var ball_bounced_since_last_hit: bool = false
var was_volley: bool = false

var serving_side_bounced: bool = false
var receiving_side_bounced: bool = false
var both_bounces_complete: bool = false

var is_in_play: bool = true
var serve_team: int = -1
