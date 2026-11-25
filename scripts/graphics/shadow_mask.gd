extends RefCounted
## Contract between the baked static shadows and the projected player shadows (visual only).
##
## The world (barangay_world.gd) paints every static shadow (net, posts, poles, umbrella,
## stalls, buildings, banderitas, crowd ovals) into one L8 image over a world-xz rectangle:
## texel value = shadow opacity there (0 none, Sun.NET_OPACITY under the net mesh,
## Sun.SHADOW_OPACITY elsewhere), unioned by max so overlaps never darken twice. It is drawn
## by one ground layer and published here. Player shadows read it and only add what the
## mask has not already darkened, so a player in a prop's shadow is not darker either.
##
## Readers: keep `version`, re-read texture / rect when it changes (one int compare per frame).

## The mask (null until the world has baked it; then no static shadows anywhere).
static var texture: Texture2D = null
## World xz rectangle the texture covers: position = min corner (x, z), size in metres.
static var rect := Rect2()
static var version := 0


static func publish(tex: Texture2D, world_rect: Rect2) -> void:
	texture = tex
	rect = world_rect
	version += 1
