extends RefCounted
## Small vector pictograms rasterized only for the open mobile editor.
static func for_caption(caption:String)->String:
	match caption:
		"Copy pose JSON","Copy again":return "copy"
		"Back":return "back"
		"Front","Side","Reset view":return "camera"
		"Wind-up":return "windup"
		"Contact":return "contact"
		"Finish":return "finish"
		"Play":return "play"
		"Stop":return "stop"
		"Save pose","Save all & back":return "save"
		"Revert","Revert pose","Default","Restore default":return "reset"
		"Select all":return "select"
	return ""
static func texture(symbol:String)->Texture2D:
	var path:String=""
	match symbol:
		"copy":path='<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>'
		"back":path='<path d="M20 12H4m7-7-7 7 7 7"/>'
		"camera":path='<rect x="2" y="6" width="20" height="15" rx="2"/><circle cx="12" cy="13" r="4"/><path d="M7 6l2-3h6l2 3"/>'
		"windup":path='<path d="M5 15a8 8 0 1 1 9 5M5 15V7m0 8h8"/>'
		"contact":path='<circle cx="12" cy="12" r="6"/><path d="M12 1v5m0 12v5M1 12h5m12 0h5"/>'
		"finish":path='<path d="M5 22V3m0 0h14l-4 5 4 5H5"/>'
		"play":path='<path d="m7 3 14 9-14 9Z"/>'
		"stop":path='<rect x="5" y="5" width="14" height="14" rx="1"/>'
		"save":path='<path d="M3 3h15l3 3v15H3Zm4 0v7h10V3M7 21v-7h10v7"/>'
		"reset":path='<path d="M4 10a8 8 0 1 1 1 8M4 10V3m0 7h7"/>'
		"select":path='<rect x="3" y="3" width="18" height="18" stroke-dasharray="3 2"/><path d="m7 12 3 3 7-7"/>'
	var image:=Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24"><g fill="none" stroke="#eef5fa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+path+'</g></svg>')
	return ImageTexture.create_from_image(image)
