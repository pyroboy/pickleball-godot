extends RefCounted
## Private elapsed-time transport. Authored key controls remain separate.
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
var owner
var sequence = Sequence.new()
var active := false
var elapsed := 0.0
var speed := 1.0
var sample: Dictionary = {}
var _signature := ""
var _mode: OptionButton
var _stance: OptionButton
var _motion: OptionButton
var _speed: OptionButton
var _slider: HSlider
var _label: Label
var _phase_picker: OptionButton
var _marks: Array[float] = []
var _settings_button:Button
var _options:VBoxContainer

func mount(editor, parent: Container, settings_parent: Container = null) -> void:
	owner = editor
	if settings_parent == null:settings_parent=parent
	_settings_button=owner.button(settings_parent,"Preview · Charge → release · 1× ▸",func():pass)
	_settings_button.toggle_mode=true;_settings_button.set_meta("compact_pose_row",true)
	var options:=VBoxContainer.new();_options=options;options.visible=false;settings_parent.add_child(options)
	_settings_button.toggled.connect(func(on):
		options.visible=on
		if on:owner._view_options.hide();owner._view_toggle.set_pressed_no_signal(false)
		owner.call_deferred("_fit_content"))
	var row:=HBoxContainer.new();row.name="TimelineOptions";options.add_child(row)
	_mode = _choice(row,["Charge → release","Charge → release → Ready","Receive → charge → release","Charge → release → receive","Stroke only · diagnostic"])
	_mode.tooltip_text = "Play gradually charges from Ready, then releases at gameplay speed. Stroke only is an explicit core+Hold diagnostic, not full-animation or gameplay validation. Receive is a named opponent-cue fixture."
	_stance = _choice(row,["Authored stance","Preview Open","Preview Closed"])
	_stance.tooltip_text = "Private stance comparison; does not edit keys or save a gameplay stance rule."
	var advanced:=HBoxContainer.new();options.add_child(advanced)
	_motion = _choice(advanced,["Runtime · full charge","Authored keys"])
	_motion.tooltip_text = "Runtime fixture uses full charge, grounded contact and no spin. Live opponents/contact fitting are not simulated. Serves use the selected serve style."
	_speed = _choice(advanced,["1× gameplay","¼× slow"])
	_speed.item_selected.connect(func(index:int): speed=1.0 if index==0 else 0.25;_update_settings_caption())
	for choice in [_mode,_stance,_motion]: choice.item_selected.connect(_options_changed)
	var time_row := HBoxContainer.new(); parent.add_child(time_row)
	_phase_picker = OptionButton.new(); _phase_picker.fit_to_longest_item=false;_phase_picker.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_phase_picker.custom_minimum_size.x=170*owner._s;_phase_picker.set_meta("compact_pose_row",true);time_row.add_child(_phase_picker); _phase_picker.item_selected.connect(_jump_phase); _phase_picker.add_item("Timeline");owner._controls.append(_phase_picker)
	_slider = HSlider.new(); _slider.min_value=0; _slider.max_value=1; _slider.step=0.0001; _slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size.y=72*owner._s;_slider.set_meta("compact_pose_row",true);owner._controls.append(_slider);_slider.scrollable=false; _slider.tooltip_text="Elapsed-time timeline. Drag to inspect any context frame without changing the selected authored key."
	time_row.add_child(_slider); _slider.value_changed.connect(_seek)
	_label = Label.new(); _label.modulate=owner.Ui.MUTED;_label.hide(); _label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(_label)
	_label.text="Elapsed-time preview · selected key stays unchanged"

func close_options()->void:
	if is_instance_valid(_options):_options.hide();_settings_button.set_pressed_no_signal(false)

func _choice(row: Container, labels: Array) -> OptionButton:
	var control := OptionButton.new();control.fit_to_longest_item=false;control.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;control.size_flags_horizontal=Control.SIZE_EXPAND_FILL;control.set_meta("compact_pose_row",true)
	for label in labels: control.add_item(label)
	row.add_child(control)
	owner._controls.append(control)
	return control

func invalidate() -> void:
	active=false; sample.clear(); _signature=""
	if is_instance_valid(_label): _label.text="Elapsed-time preview · selected key stays unchanged";_label.hide()
	if is_instance_valid(_slider):
		var available:bool=not owner._base and owner._has_motion()
		_slider.editable=available;_phase_picker.disabled=not available;_settings_button.disabled=not available
		for choice in [_mode,_stance,_motion,_speed]:choice.disabled=not available
		if not available:close_options()

func _configure() -> bool:
	if owner._base or not owner._has_motion(): return false
	var signature: String = owner._elbow_preset_panel.signature(owner._current)+":"+str(owner._variant_mode)+":"+str(_mode.selected)+":"+str(_stance.selected)+":"+str(_motion.selected)
	if signature != _signature:
		sequence.configure(owner._current,_mode.selected,_stance.selected,owner._variant_mode,_motion.selected==0,owner._preview.player)
		_signature=signature
		_marks=[0.0,sequence.prefix_seconds,sequence.prefix_seconds+sequence.release_seconds,sequence.prefix_seconds+sequence.stroke_seconds]
		_phase_picker.clear()
		for label in ["Start","Wind-up / release","Contact","Finish"]:_phase_picker.add_item(label)
		if _mode.selected == Sequence.Mode.STROKE_ONLY:
			_marks.append(sequence.duration);_phase_picker.add_item("Hold end")
		elif _mode.selected != Sequence.Mode.STROKE:
			_marks.append(sequence.prefix_seconds+sequence.full_seconds);_phase_picker.add_item("Ready")
			_marks.append(sequence.duration);_phase_picker.add_item("Sequence end")
	return true

func start(resume: bool) -> void:
	if not _configure(): return
	if not resume or not active or elapsed >= sequence.duration: elapsed=0.0
	active=true; _sample()

func advance(dt: float) -> bool:
	if not active or not _configure(): return true
	# The editor supplies an unscaled wall delta and suspends it during focus/dialog pause.
	elapsed=minf(elapsed+maxf(dt,0.0)*speed,sequence.duration)
	_sample()
	return elapsed>=sequence.duration

func _sample() -> void:
	_label.show()
	sample=sequence.sample(elapsed)
	owner._progress=sample.progress
	_slider.set_value_no_signal(elapsed/maxf(sequence.duration,0.001))
	_label.text="%.2f / %.2f s · %s · %s" % [elapsed,sequence.duration,sample.phase,"1×" if speed==1 else "¼× slow"]

func pose(fallback: PostureDefinition) -> PostureDefinition:
	return sample.pose if active and not sample.is_empty() else fallback

func refresh_joint_guide() -> void:
	if not active or sample.is_empty():
		owner._preview.set_joint_motion_context(Callable(), "")
		return
	# The displayed sequence owns the phase clock. A candidate is overlaid by the
	# same panel function used for the live frame, not by changing authored keys.
	var candidate_source: PostureDefinition = owner._elbow_preset_panel.preview_source(owner._current)
	var candidate_hash: String = str(candidate_source.elbow_preset_bake.get("payload_sha256", ""))
	var signature: String = _signature + ":guide:" + candidate_hash + ":candidate:" + str(candidate_source != owner._current)
	owner._preview.set_joint_motion_context(_joint_guide_pose, signature)

func _joint_guide_pose(progress: float) -> PostureDefinition:
	var value: PostureDefinition
	if sequence.style >= 0:
		# Serve playback is elapsed-time based, with Contact at its own duration.
		var seconds: float = sequence.release_seconds * progress * 2.0 if progress <= 0.5 else sequence.release_seconds + (sequence.stroke_seconds - sequence.release_seconds) * (progress - 0.5) * 2.0
		value = sequence.sample(sequence.prefix_seconds + seconds).pose
	else:
		value = sequence._stance_copy(sequence._stroke_pose(progress))
	var matching_runtime: bool = sequence.permits_core_overlay()
	return owner._elbow_preset_panel.preview_pose_at(value, progress, matching_runtime)

func after_refresh() -> void:
	if not active or sample.is_empty(): return
	owner._phase.text="Preview";owner._phase.tooltip_text=sample.phase+" · selected authored key unchanged"
	# The illustration uses absolute release time, not eased paddle time.
	var local := clampf(elapsed-sequence.prefix_seconds,0,sequence.stroke_seconds)
	var ball_progress: float = 0.5*local/maxf(sequence.release_seconds,0.001) if local <= sequence.release_seconds else 0.5+0.5*(local-sequence.release_seconds)/maxf(sequence.stroke_seconds-sequence.release_seconds,0.001)
	owner._preview.set_preview_progress(ball_progress)
	if bool(sample.split.get("active",false)) and str(sample.split.get("phase","")) in ["split_load","split_unweight","split_land"] and ResourceLoader.exists("res://scripts/ui/mobile_pose_split_step_preview.gd"):
		load("res://scripts/ui/mobile_pose_split_step_preview.gd").show(owner._preview,sample.pose,sample.split)

func _update_settings_caption()->void:
	_settings_button.text="Preview · "+["Charge → release","Charge → Ready","Receive → charge","Charge → receive","Stroke only · diagnostic"][_mode.selected]+" · "+["Saved","Open","Closed"][_stance.selected]+" · "+("1×" if speed==1 else "¼× slow")+" ▾"

func _options_changed(_index: int) -> void:
	owner._elbow_preset_panel.context_changed()
	_update_settings_caption()
	owner._stop(); _signature=""; elapsed=0.0
	if not _configure(): return
	active=true; _sample(); owner._refresh_preview()

func _seek(value: float) -> void:
	owner._elbow_preset_panel.context_changed()
	owner._stop()
	if not _configure(): return
	active=true; elapsed=value*sequence.duration; _sample(); owner._refresh_preview()
	owner._resume_playback=true; owner._play.text="Resume"

func _jump_phase(index: int) -> void:
	if not _configure() or index>=_marks.size():return
	_seek(_marks[index]/maxf(sequence.duration,0.001))
