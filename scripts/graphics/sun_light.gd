class_name SunLight
extends RefCounted
## The one sun every visual reads (shadow rework 2026-11-25): the real DirectionalLight3D,
## the toon bands on props and players, the baked static shadow mask (shadow_mask.gd) and
## the projected player shadows. Visual only: nothing gameplay reads uses it.
##
## Sun behind-left of the gameplay camera at 40 degrees: shadows fall up and to the right on
## screen, away from the near player, about 1.2x the caster's height. The camera faces the
## other end after a change of ends (game.view_flipped()); the sun turns half a turn with it
## so the screen look never changes. barangay_world.gd calls set_flipped(); readers compare
## `version` (one int per frame) and re-read when it moves.

## Horizontal direction shadows fall in with the default camera (at +z, looking -z):
## +x (right) and -z (away from the camera, up the screen). World, unit, y = 0.
const BASE_SHADOW_DIR := Vector3(0.6, 0.0, -0.8)
## Sun elevation above the horizon, degrees. Shadow length = height / tan(elevation).
const ELEVATION_DEG := 40.0
## Warm sun, and the one shadow colour (#3b3a5c). Every shadow multiplies the ground by
## lerp(1, SHADOW_COLOR, SHADOW_OPACITY); the net's mesh shadow by NET_OPACITY.
const SUN_COLOR := Color(1.0, 0.86, 0.66)
const SHADOW_COLOR := Color("3b3a5c")
const SHADOW_OPACITY := 0.4
const NET_OPACITY := 0.2
const BALL_OPACITY := 0.55
## Horizon / fog colour: warm peach, matched to the sky's horizon.
const HORIZON_COLOR := Color(0.96, 0.78, 0.62)

## Kept for older readers: the default (unflipped) direction.
const SHADOW_DIR := BASE_SHADOW_DIR

static var flipped := false
static var version := 0


static func set_flipped(value: bool) -> void:
	if value == flipped: return
	flipped = value
	version += 1


## Horizontal direction shadows fall in right now (world, unit, y = 0).
static func shadow_dir() -> Vector3:
	return -BASE_SHADOW_DIR if flipped else BASE_SHADOW_DIR


## Unit vector from the ground toward the sun (world space), right now.
static func to_sun() -> Vector3:
	var e := deg_to_rad(ELEVATION_DEG)
	return (-shadow_dir() * cos(e) + Vector3.UP * sin(e)).normalized()


## How far a shadow reaches per metre of height (about 1.19).
static func shadow_length_per_metre() -> float:
	return 1.0 / tan(deg_to_rad(ELEVATION_DEG))


## Planar projection onto the ground: where the sun puts a point's shadow (y = ground_y).
static func project(p: Vector3, ground_y: float) -> Vector3:
	var d := -to_sun()   # light travel direction, d.y < 0
	var h := p.y - ground_y
	return Vector3(p.x - h * (d.x / d.y), ground_y, p.z - h * (d.z / d.y))
