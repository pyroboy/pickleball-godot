extends Node
## Reduce only options-list vertical travel. Native gesture recognition, child
## cancellation, scrollbar grabs and inertia remain owned by ScrollContainer.
## Horizontal value sliders never pass through this adapter.
const TRAVEL_SCALE := 0.85
var scroll:ScrollContainer
var bar:VScrollBar
var _mode:=""
var _pressed:=false
var _origin:=0.0
var _applied:=0.0
var _sync:=false

func configure(target:ScrollContainer)->void:
	scroll=target;bar=scroll.get_v_scroll_bar()
	process_mode=Node.PROCESS_MODE_ALWAYS
	scroll.scroll_deadzone=12
	scroll.scroll_started.connect(func():_mode="touch")
	scroll.scroll_ended.connect(func():_mode="")
	bar.value_changed.connect(_damp)

func _input(event:InputEvent)->void:
	if not is_instance_valid(scroll) or not scroll.is_visible_in_tree():return
	if event is InputEventScreenTouch:
		if event.pressed and scroll.get_global_rect().has_point(event.position):
			_pressed=true;_origin=bar.value;_applied=bar.value
		elif not event.pressed:_pressed=false
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed and bar.get_global_rect().has_point(event.position):
				_pressed=true;_mode="bar";_origin=bar.value;_applied=bar.value
			elif not event.pressed:
				_pressed=false
				if _mode=="bar":_mode=""
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and scroll.get_global_rect().has_point(event.position):
			_mode="wheel";_applied=bar.value;call_deferred("_end_wheel")

func _end_wheel()->void:
	if _mode=="wheel":_mode=""

func _damp(value:float)->void:
	if _sync or _mode.is_empty():return
	var adjusted:float=_origin+(value-_origin)*TRAVEL_SCALE if _pressed else _applied+(value-_applied)*TRAVEL_SCALE
	_sync=true;bar.set_value_no_signal(adjusted);_applied=bar.value;_sync=false
