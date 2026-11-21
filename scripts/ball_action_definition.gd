extends PostureDefinition
## Ball pickup / ball throw between points: three authored keys on their own timeline.
## The keys use the stroke layout so the Pose Studio edits them like any pose:
##   windup_body = key 1 (pickup Reach, throw Wind-back), the main resource = key 2 (pickup Grab,
##   throw Release), follow_through_body = key 3 (pickup Rise, throw Follow).
## left_hand_offset is the ball hand. The game adds only the difference between each key and
## `baseline` (the code-built key this file was made from), see scripts/ball_actions.gd.

@export var action_id: int = 0          # 0 pickup, 1 throw
## Pickup: bend down to the ball (Grab at bend_time), then lift back to the carry (lift_time).
@export var bend_time: float = 0.42
@export var lift_time: float = 0.42
## Throw: hand winds back until windup_time, swings to release_time (ball leaves), then follows
## through for follow_time.
@export var windup_time: float = 0.15
@export var release_time: float = 0.55
@export var follow_time: float = 0.4
## Code-built keys at the time the file was made: {"windup"|"contact"|"finish": {field: value}}.
@export var baseline: Dictionary = {}
