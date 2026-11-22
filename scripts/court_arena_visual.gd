extends Node3D
## Everything around the court that is not the court itself (visual only): the beach
## world in scripts/environment/beach_world.gd. It replaced the navy arena boards and
## the grass park (2026-11-22); `CourtArenaVisual` keeps its name because wall
## practice hides it by path.

const BeachWorld := preload("res://scripts/environment/beach_world.gd")

func setup(game: Node3D) -> void :
	name = "CourtArenaVisual"
	game.add_child(self)
	# The old stadium backdrop (a near-black 30 m cylinder, visual only, no collision)
	# would wall the beach in. Its top cap also shades the whole court from the sun,
	# and the current lighting was tuned under that shade, so keep it as a
	# shadow-only caster: unseen, same light.
	var backdrop := game.find_child("StadiumBackdrop", true, false)
	if backdrop is GeometryInstance3D:
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	BeachWorld.new().setup(game, self)
