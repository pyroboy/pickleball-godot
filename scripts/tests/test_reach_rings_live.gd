extends "res://scripts/tests/test_extended_paddle_reach.gd"


func run() -> void :
	var settings = root.get_node("Settings")
	var previous = settings.get_value("beta_debug.reach_rings", false)
	settings._config.set_value("beta_debug", "reach_rings", true)
	await super.run()
	settings._config.set_value("beta_debug", "reach_rings", previous)
