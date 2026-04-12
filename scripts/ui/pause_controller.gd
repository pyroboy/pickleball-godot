extends Node
## Autoload "PauseController".
## Listens for the Escape key on any scene and opens an in-game pause menu.
## Coordinates with TimeScale autoload so slowmo/hitstop state is restored
## cleanly when the menu closes.
##
## Pause menu is instantiated lazily via scripts/ui/pause_menu.gd and
## parented to the current scene. The menu script owns its own visuals;
## this autoload just manages lifecycle.

const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")

var _menu: Node = null
var _was_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if _menu != null and is_instance_valid(_menu):
		close()
	else:
		open()

func open() -> void:
	if _menu != null and is_instance_valid(_menu):
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return

	_was_paused = tree.paused
	_menu = PauseMenuScript.new()
	_menu.set_meta("controller", self)
	tree.current_scene.add_child(_menu)

	if TimeScale != null and TimeScale.has_method("force_normal"):
		TimeScale.force_normal()
	tree.paused = true
	print("[PauseController] opened")

func close() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null

	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _was_paused
	if TimeScale != null and TimeScale.has_method("release_forced_normal"):
		TimeScale.release_forced_normal()
	print("[PauseController] closed")
