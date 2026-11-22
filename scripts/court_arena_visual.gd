extends Node3D
## Everything around the court that is not the court itself (visual only): the barangay
## court world in scripts/environment/barangay_world.gd (2026-11-22; it replaced the navy
## arena boards and grass park, then a short-lived beach). `CourtArenaVisual` keeps its
## name because wall practice hides it by path.

const BarangayWorld := preload("res://scripts/environment/barangay_world.gd")

func setup(game: Node3D) -> void :
	name = "CourtArenaVisual"
	game.add_child(self)
	# The old stadium backdrop (a near-black 30 m cylinder, visual only, no collision)
	# would wall the world in. Its top cap also shades the whole court from the sun,
	# and the current lighting was tuned under that shade, so keep it as a
	# shadow-only caster: unseen, same light.
	var backdrop := game.find_child("StadiumBackdrop", true, false)
	if backdrop is GeometryInstance3D:
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	BarangayWorld.new().setup(game, self)
