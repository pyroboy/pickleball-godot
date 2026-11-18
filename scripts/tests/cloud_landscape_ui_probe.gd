extends SceneTree
func _initialize(): call_deferred('run')
func run():
	root.content_scale_size = Vector2i(720,1280)
	root.size = Vector2i(960,540)
	await process_frame
	var controller=root.get_node('PauseController')
	root.focus_exited.disconnect(controller._on_window_focus_exited)
	root.focus_entered.disconnect(controller._on_window_focus_entered)
	paused=true
	var pause = load('res://tools/cloud_qa/landscape_ui_candidate_pause_menu.gd').new();root.add_child(pause)
	await process_frame
	pause._on_reset_requested()
	await process_frame
	for i in 10: await process_frame
	var dialog = pause._reset_dialog
	for c in [pause._reset_button, dialog.get_label(),dialog.get_ok_button()]:
		print(c.get_class(), ': font=',c.get_theme_font_size('font_size'),' min=',c.custom_minimum_size,' size=',c.size,' canvas_transform=',c.get_global_transform_with_canvas(),' screen=',c.get_screen_transform(),' final=',c.get_viewport().get_final_transform())
	print('window ',dialog.size,' ',dialog.position,' embedded=',dialog.is_embedded(),' decoration=',dialog.get_size_with_decorations(),' ',dialog.get_position_with_decorations())
	for n in ['panel','embedded_border','embedded_unfocused_border']:
		var t='AcceptDialog' if n=='panel' else 'Window'
		var style=dialog.get_theme_stylebox(n)
		print(n,' ',var_to_str(style))
		for p in style.get_property_list():
			if p.usage & PROPERTY_USAGE_STORAGE: print(p.name,' = ',style.get(p.name))
	quit()
