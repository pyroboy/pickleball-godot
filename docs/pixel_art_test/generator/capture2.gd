extends SceneTree
var frames := 0
var rig = null
const OUT := "/private/tmp/claude-501/-Users-arjomagno--claude-spares-spare-NyRAqp/da740810-5ae9-4e29-a263-0cde91478894/scratchpad/art/rally_%d.png"
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _force_center() -> void:
	if rig: rig._update_centered(1.0 / 60.0)
func _process(_d: float) -> bool:
	frames += 1
	var vp := root.get_viewport()
	if frames == 60:
		rig = vp.get_camera_3d().get_parent()
		RenderingServer.frame_pre_draw.connect(_force_center)
	if frames in [120, 180]:
		var cam := vp.get_camera_3d()
		print("CAM frame=", frames, " pos=", cam.global_position, " rot_deg=", cam.global_rotation_degrees,
			" fov=", cam.fov, " keep_aspect=", cam.keep_aspect, " v_off=", cam.v_offset, " elev=", rig._portrait_frame_elevation)
		vp.get_texture().get_image().save_png(OUT % frames)
	if frames >= 180: quit()
	return false
