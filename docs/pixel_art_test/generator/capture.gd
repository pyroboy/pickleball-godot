extends SceneTree
var frames := 0
const OUT := "/private/tmp/claude-501/-Users-arjomagno--claude-spares-spare-NyRAqp/da740810-5ae9-4e29-a263-0cde91478894/scratchpad/art/ingame_%d.png"
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(_d: float) -> bool:
	frames += 1
	if frames in [60, 150, 240]:
		var vp := root.get_viewport()
		var cam := vp.get_camera_3d()
		if cam:
			print("CAM frame=", frames, " pos=", cam.global_position, " rot_deg=", cam.global_rotation_degrees,
				" fov=", cam.fov, " keep_aspect=", cam.keep_aspect, " proj=", cam.projection, " v_off=", cam.v_offset,
				" size=", vp.get_visible_rect().size)
		vp.get_texture().get_image().save_png(OUT % frames)
	if frames >= 240:
		quit()
	return false
