extends SceneTree
## Writes data/ball_actions/00_pickup.tres, 01_throw.tres (lob) and 02_throw_strong.tres from the code-built between-point motion
## (scripts/ball_actions.gd). Run once, or with --force to start a file over (loses its edits):
##   godot --headless --path . -s tools/ball_actions_make.gd [-- --force]
const Actions = preload("res://scripts/ball_actions.gd")

func _init() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	var ready: PostureDefinition = PostureLibrary.instance().get_def(Actions.READY_ID)
	for id in Actions.FILES.size():
		var path: String = Actions.FILES[id]
		if ResourceLoader.exists(path) and not force:
			print("[ball_actions] keep ", path); continue
		var d := Actions.build(id, ready)
		var err := ResourceSaver.save(d, path)
		print("[ball_actions] wrote ", path, " err=", err)
	quit()
