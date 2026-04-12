extends Node3D
## Autoload "FXPool".
## Pre-allocates impact bursts + bounce decals so we don't instantiate/free
## every rally hit. Pool items are direct children of this autoload node —
## autoloads live under /root, survive scene changes, and render fine in
## world space without any reparenting gymnastics.

const ImpactBurstScript = preload("res://scripts/fx/impact_burst.gd")
const BounceDecalScript = preload("res://scripts/fx/bounce_decal.gd")

const INIT_BURSTS: int = 8   # Mobile: reduced from 12
const INIT_DECALS: int = 4   # Mobile: reduced from 8
const MAX_BURSTS: int = 8   # Mobile: reduced from 24
const MAX_DECALS: int = 4   # Mobile: reduced from 16

var _bursts: Array[ImpactBurst] = []
var _decals: Array[BounceDecal] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(INIT_BURSTS):
		_add_burst()
	for i in range(INIT_DECALS):
		_add_decal()
	print("[FXPool] ready — ", _bursts.size(), " bursts, ", _decals.size(), " decals")

func _add_burst() -> ImpactBurst:
	var b: ImpactBurst = ImpactBurstScript.new()
	add_child(b)
	_bursts.append(b)
	return b

func _add_decal() -> BounceDecal:
	var d: BounceDecal = BounceDecalScript.new()
	add_child(d)
	_decals.append(d)
	return d

func spawn_burst(pos: Vector3, color: Color, strength: float = 1.0, upward: bool = false) -> void:
	if not _settings_particles_on():
		print("[FXPool] burst skipped — particles off")
		return
	print("[FXPool] spawn_burst at ", pos, " color=", color, " strength=", "%.2f" % strength)
	var free_burst: ImpactBurst = _find_free_burst()
	if free_burst == null:
		if _bursts.size() < MAX_BURSTS:
			free_burst = _add_burst()
		else:
			free_burst = _bursts[0]
	free_burst.play(pos, color, strength * _density_scale(), upward)
	_bursts.erase(free_burst)
	_bursts.append(free_burst)

func spawn_decal(pos: Vector3, color: Color) -> void:
	if not _settings_particles_on():
		return
	var free_decal: BounceDecal = _find_free_decal()
	if free_decal == null:
		if _decals.size() < MAX_DECALS:
			free_decal = _add_decal()
		else:
			free_decal = _decals[0]
	free_decal.play(pos, color)
	_decals.erase(free_decal)
	_decals.append(free_decal)

func _find_free_burst() -> ImpactBurst:
	for b in _bursts:
		if not b.is_active():
			return b
	return null

func _find_free_decal() -> BounceDecal:
	for d in _decals:
		if not d.is_active():
			return d
	return null

func _settings_particles_on() -> bool:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node == null or not settings_node.has_method("get_value"):
		return true
	return int(settings_node.call("get_value", "video.particle_density", 2)) > 0

func _density_scale() -> float:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node == null or not settings_node.has_method("get_value"):
		return 1.0
	var d: int = int(settings_node.call("get_value", "video.particle_density", 2))
	match d:
		0: return 0.0
		1: return 0.5
		2: return 1.0
		3: return 1.3
	return 1.0
