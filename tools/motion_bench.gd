extends SceneTree
## Motion bench: one player on a quiet court walks a fixed course (stand, walk, run, stop,
## backpedal, shuffle, diagonal) while the card motion and the gameplay joints are recorded.
## No AI, ball or scoring: the match is loaded, then frozen, and the player is moved directly.
## Run through tools/motion_bench.sh (report + compare). About 10-20 s.
## Args (after --): --mb-out=<abs json path> [--mb-actor=0]

const SETTLE_FRAMES := 90
const ACCEL := 7.0            # m/s^2 toward each segment's target velocity
# name, seconds, forehand m/s, forward m/s (player frame: forward = toward the net)
const COURSE := [
	["stand", 1.5, 0.0, 0.0],
	["walk", 2.0, 0.0, 1.2],
	["stop", 1.0, 0.0, 0.0],
	["run", 1.6, 0.0, 3.6],
	["run_stop", 1.0, 0.0, 0.0],
	["backpedal", 1.8, 0.0, -1.6],
	["shuffle_r", 1.0, 2.0, 0.0],
	["shuffle_l", 2.0, -2.0, 0.0],
	["shuffle_r2", 1.0, 2.0, 0.0],
	["diagonal", 1.4, 1.8, -2.4],
	["settle", 1.2, 0.0, 0.0],
]

var _out := ""
var _actor := 0
var _game: Node
var _p
var _rig
var _frame := 0
var _phase := "load"
var _seg := 0
var _seg_t := 0.0
var _vel := Vector3.ZERO
var _fwd := Vector3.ZERO
var _fh := Vector3.ZERO
var _frames: Array = []
var _prev_feet := {}
var _t0 := 0
var _cost_sum := 0.0
var _cost_n := 0.0
var _cost_max := 0

## Stands in for the player's special-movement hook (match_erne_action.gd): while "active",
## player.gd takes this ground velocity, so its own physics step moves and steps the player.
class CourseMove extends RefCounted:
	var active := true
	var _taken_off := false
	var vel := Vector3.ZERO
	func before_physics(_d, _b) -> void: pass
	func ground_velocity() -> Vector3: return vel
	func maybe_start_ai(_a = null, _b = null, _c = null) -> bool: return false
	func notify_hit() -> void: pass
	func reset() -> void: pass
	func cancel(_why := "") -> void: pass
	func contact_opportunity(_b) -> Dictionary: return {}

var _move := CourseMove.new()

class Driver extends Node:
	var bench
	func _physics_process(delta: float) -> void: bench._physics(delta)
	func _process(delta: float) -> void: bench._sample(delta)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mb-out="): _out = a.trim_prefix("--mb-out=")
		if a.begins_with("--mb-actor="): _actor = int(a.trim_prefix("--mb-actor="))
	_t0 = Time.get_ticks_msec()
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.bench = self
	d.process_priority = 2000          # after the card rig (1000) and paddle skin (1001)
	d.process_physics_priority = -100  # before anything that reads the player this tick
	root.add_child.call_deferred(d)

func _freeze_match() -> void:
	var players: Array = _game.get_players()
	_p = players[clampi(_actor, 0, players.size() - 1)]
	for pl in players:
		if pl != _p: pl.set_physics_process(false)   # the others stand still
	_p.erne_action = _move   # ours walks the course through its own physics step
	var ball = _game.ball
	ball.set_physics_process(false)
	ball.freeze = true
	ball.is_in_play = false
	ball.global_position = Vector3(0.0, 1.0, -40.0 if _p.global_position.z > 0.0 else 40.0)
	_game.set_physics_process(false)
	var bpc = _game.get("between_point_controller")
	if bpc != null and is_instance_valid(bpc):
		bpc.set("_active", false)
		bpc.set_process(false)
		bpc.set_physics_process(false)
	_fwd = _p._get_forward_axis()
	_fh = _p._get_forehand_axis()
	_rig = _p.get_parent().get_node_or_null("PixelCards_%d" % _p.get_instance_id())

func _physics(delta: float) -> void:
	_frame += 1
	if _phase == "load":
		if _frame >= SETTLE_FRAMES and _game.is_inside_tree() and _game.ball != null:
			_freeze_match()
			_phase = "run"
		return
	if _phase != "run": return
	var seg: Array = COURSE[_seg]
	var target: Vector3 = _fh * float(seg[2]) + _fwd * float(seg[3])
	_vel = _vel.move_toward(target, ACCEL * delta)
	_move.vel = _vel
	_seg_t += delta
	if _seg_t >= float(seg[1]):
		_seg_t = 0.0
		_seg += 1
		if _seg >= COURSE.size():
			_phase = "done"
			_finish()

func _drawn(n: Node3D) -> Vector3:
	return _rig._xf(n).origin if _rig != null else n.get_global_transform_interpolated().origin

func _v(v: Vector3) -> Array: return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]

func _sample(_delta: float) -> void:
	if _phase != "run" or _p == null: return
	var m = _rig.get("_motion") if _rig != null else null
	var row := {"seg": COURSE[_seg][0], "speed": snappedf(_vel.length(), 0.001)}
	if m != null:
		row["w"] = snappedf(m._weight, 0.001)
		row["stride"] = snappedf(m._stride, 0.001)
	var paddle_arm = _rig.get("_paddle_arm") if _rig != null else null
	var arms := {}
	for side in ["right", "left"]:
		var arm = _p.get(side + "_arm_node")
		if arm == null: continue
		var raw: Vector3 = arm.hand_pivot.get_global_transform_interpolated().origin
		var drawn: Vector3 = _drawn(arm.hand_pivot)
		arms[side] = {"free": arm != paddle_arm, "drawn": _v(drawn), "off": snappedf((drawn - raw).dot(_fwd), 0.0001)}
	row["arms"] = arms
	var feet := {}
	for side in ["right", "left"]:
		var leg = _p.get(side + "_leg_node")
		var pos: Vector3 = leg.foot_pivot.global_position
		var locked: bool = bool(_p.leg_ik.get(side + "_foot_locked"))
		var slide := 0.0
		if locked and _prev_feet.has(side) and _prev_feet[side][1]:
			var d: Vector3 = pos - _prev_feet[side][0]
			slide = Vector2(d.x, d.z).length()
		_prev_feet[side] = [pos, locked]
		feet[side] = {"locked": locked, "slide": snappedf(slide, 0.00001), "z": snappedf((pos - _p.global_position).dot(_fwd), 0.0001)}
	row["feet"] = feet
	# Gameplay joints (what bench pose traces hold): must not change for visual-only work.
	var g := []
	for n in [_p.body_pivot, _p.right_arm_node.hand_pivot, _p.left_arm_node.hand_pivot, _p.right_arm_node.upper_pivot,
			_p.left_arm_node.upper_pivot, _p.right_leg_node.foot_pivot, _p.left_leg_node.foot_pivot, _p.paddle_node]:
		g.append(_v(n.global_position))
	row["g"] = g
	if _rig != null:
		var torso: Node3D = _p.body_pivot.get_node_or_null("TorsoMesh")
		var rs: Vector3 = _drawn(_p.right_arm_node.upper_pivot)
		var ls: Vector3 = _drawn(_p.left_arm_node.upper_pivot)
		var rr: Vector3 = _p.right_arm_node.upper_pivot.get_global_transform_interpolated().origin
		var lr: Vector3 = _p.left_arm_node.upper_pivot.get_global_transform_interpolated().origin
		var a: Vector3 = rs - ls; a.y = 0.0
		var b: Vector3 = rr - lr; b.y = 0.0
		row["twist"] = snappedf(rad_to_deg(b.signed_angle_to(a, Vector3.UP)), 0.01) if a.length() > 0.01 and b.length() > 0.01 and torso != null else 0.0
	var pm = root.get_node_or_null("PerfMonitor")
	if pm != null:
		var c: Array = pm.get_script().get("_frame_costs").get("card.motion", [])
		if not c.is_empty():
			_cost_sum += float(c[1]); _cost_n += 1.0; _cost_max = maxi(_cost_max, int(c[2]))
	_frames.append(row)

func _finish() -> void:
	var out := {"course": COURSE, "frames": _frames, "wall_ms": Time.get_ticks_msec() - _t0,
		"perf": {"card_motion_us_mean": snappedf(_cost_sum / maxf(_cost_n, 1.0), 0.1), "card_motion_us_max": _cost_max}}
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
		f.close()
	quit()
