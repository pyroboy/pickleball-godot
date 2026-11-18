extends "res://scripts/tests/cloud_landscape_navigation.gd"
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="): Engine.physics_ticks_per_second = int(argument.trim_prefix("--rate="))
	super._initialize()
