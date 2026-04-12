extends Node
class_name HitFeedback
## Listens to ball signals and drives all hit FX:
##   - camera shake (via CameraRig.add_shake)
##   - hitstop (via TimeScale.request_hitstop)
##   - paddle contact burst + bounce burst + bounce decal (via FXPool)
##
## game.gd owns one of these, passes ball + camera_rig refs via setup().
## Keeping FX out of game.gd is the whole point.

const HIT_SHAKE_BASE: float = 0.25
const HIT_SHAKE_SCALE: float = 0.55
const HITSTOP_THRESHOLD: float = 0.7
const HITSTOP_DURATION: float = 0.06
const HITSTOP_SCALE: float = 0.05

var _ball: RigidBody3D
var _camera_rig: Node  # CameraRig — typed Node to avoid load order issues
var _players: Array = []

func setup(ball: RigidBody3D, camera_rig: Node, players: Array) -> void:
	_ball = ball
	_camera_rig = camera_rig
	_players = players
	if _ball != null:
		if not _ball.hit_by_paddle.is_connected(_on_hit):
			_ball.hit_by_paddle.connect(_on_hit)
		if not _ball.bounced.is_connected(_on_bounce):
			_ball.bounced.connect(_on_bounce)
	print("[HitFeedback] setup — ball=", _ball != null, " rig=", _camera_rig != null,
		" fxpool=", get_node_or_null("/root/FXPool") != null)

func _on_hit(player_num: int) -> void:
	if _ball == null:
		return
	var pos: Vector3 = _ball.global_position
	var vel: Vector3 = _ball.linear_velocity
	var strength: float = clampf(vel.length() / 20.0, 0.0, 1.0)
	print("[HitFeedback] hit p=", player_num, " strength=", "%.2f" % strength, " at ", pos)

	# Camera shake (scaled by Settings video.shake inside the rig)
	if _camera_rig != null and _camera_rig.has_method("add_shake"):
		_camera_rig.call("add_shake", HIT_SHAKE_BASE + HIT_SHAKE_SCALE * strength)

	# Hitstop on strong hits (ignored by TimeScale if slowmo active)
	if strength > HITSTOP_THRESHOLD and _settings_hitstop_enabled():
		var ts: Node = get_node_or_null("/root/TimeScale")
		if ts != null and ts.has_method("request_hitstop"):
			ts.call("request_hitstop", HITSTOP_DURATION, HITSTOP_SCALE)

	# Paddle contact burst — color by player
	var fx: Node = get_node_or_null("/root/FXPool")
	if fx != null and fx.has_method("spawn_burst"):
		var color: Color = _player_color(player_num)
		fx.call("spawn_burst", pos, color, strength, false)

func _on_bounce(bounce_pos: Vector3) -> void:
	var fx: Node = get_node_or_null("/root/FXPool")
	if fx == null:
		return
	var tint: Color = _zone_tint(bounce_pos)
	if fx.has_method("spawn_burst"):
		fx.call("spawn_burst", Vector3(bounce_pos.x, bounce_pos.y + 0.02, bounce_pos.z), tint, 0.7, true)
	if fx.has_method("spawn_decal"):
		fx.call("spawn_decal", bounce_pos, tint)

func _player_color(player_num: int) -> Color:
	if player_num == 0:
		return Color(0.35, 0.6, 1.0, 1.0)  # blue
	return Color(1.0, 0.4, 0.4, 1.0)  # red

func _zone_tint(bounce_pos: Vector3) -> Color:
	# Kitchen (non-volley zone) = cyan, baseline = orange, mid = white
	var abs_z: float = absf(bounce_pos.z)
	if abs_z < 1.8:
		return Color(0.4, 0.9, 1.0, 1.0)  # kitchen cyan
	if abs_z > 5.2:
		return Color(1.0, 0.6, 0.2, 1.0)  # baseline orange
	return Color(1.0, 1.0, 1.0, 1.0)

func _settings_hitstop_enabled() -> bool:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node == null or not settings_node.has_method("get_value"):
		return true
	return bool(settings_node.call("get_value", "video.hitstop", true))
