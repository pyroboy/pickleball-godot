class_name FakeBall extends RefCounted
## Plain RefCounted stub matching every field the RallyScorer reads from `ball`.
## Field names mirror scripts/ball.gd exactly — if you add a field there that
## the scorer reads, mirror it here too or tests will silently misalign.
##
## Use in tests:
##   var b := FakeBall.new()
##   b.global_position = Vector3(0, 0.1, 7.5)
##   b.last_hit_by = 1
##   b.bounces_since_last_hit = 1

var global_position: Vector3 = Vector3.ZERO
var linear_velocity: Vector3 = Vector3.ZERO
# Rally / hit tracking
var last_hit_by: int = -1                    # -1 = not yet hit, 0 = Blue, 1 = Red
var bounces_since_last_hit: int = 0          # incremented on each floor bounce
var ball_bounced_since_last_hit: bool = false
var was_volley: bool = false                 # captured at the moment of hit
# Two-bounce-rule tracking
var serving_side_bounced: bool = false
var receiving_side_bounced: bool = false
var both_bounces_complete: bool = false
# Lifecycle
var is_in_play: bool = true
var serve_team: int = -1
