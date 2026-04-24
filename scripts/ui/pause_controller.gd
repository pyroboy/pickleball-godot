extends Node
## Autoload "PauseController".
## Listens for the Escape key on any scene and opens an in-game pause menu.
## Coordinates with TimeScale autoload so slowmo/hitstop state is restored
## cleanly when the menu closes.
##
## Also throttles FPS + auto-pauses when the game window loses focus to save CPU.

const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")

var _menu: Node = null
var _manual_paused: bool = false
var _focus_paused: bool = false
var _previous_max_fps: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window := get_window()
	if window:
		window.focus_entered.connect(_on_window_focus_entered)
		window.focus_exited.connect(_on_window_focus_exited)

func _set_pause_state() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _manual_paused or _focus_paused

func _on_window_focus_exited() -> void:
	_previous_max_fps = Engine.max_fps
	Engine.max_fps = 5
	_focus_paused = true
	_set_pause_state()
	print("[PauseController] window focus lost — throttling to 5 FPS")

func _on_window_focus_entered() -> void:
	Engine.max_fps = _previous_max_fps
	_focus_paused = false
	_set_pause_state()
	print("[PauseController] window focus regained — restoring FPS")

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

	_menu = PauseMenuScript.new()
	_menu.set_meta("controller", self)
	tree.current_scene.add_child(_menu)

	if TimeScale != null and TimeScale.has_method("force_normal"):
		TimeScale.force_normal()
	_manual_paused = true
	_set_pause_state()
	print("[PauseController] opened")

func close() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null

	_manual_paused = false
	_set_pause_state()
	if TimeScale != null and TimeScale.has_method("release_forced_normal"):
		TimeScale.release_forced_normal()
	print("[PauseController] closed")
