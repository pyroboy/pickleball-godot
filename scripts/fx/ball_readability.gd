extends MeshInstance3D
## Retired cue (visual only). It drew a yellow ring with a hollow centre around a small
## ball: a halo, which the ball no longer needs. The ball now draws itself bigger, with a
## 3-render-pixel minimum size and a dark 1-pixel outline (scripts/ball.gd,
## shaders/ball_body.gdshader, shaders/ball_readability.gdshader = that outline).
## The node stays, empty and hidden, because game.gd adds it to the ball and tools
## (cine.gd, the loading prewarm) still look it up.

const CueShader = preload("res://shaders/ball_readability.gdshader")
var ball_radius: = 0.0375

func _ready() -> void :
	name = "BallReadability"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
