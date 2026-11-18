extends RefCounted


const Styles = preload("res://scripts/serve_style.gd")
const Policy = preload("res://scripts/runtime_policy.gd")
var mesh: MeshInstance3D
var _live_ball
var _saved_visible: = true
var _plans: Dictionary = {}
var plan_build_count: = 0

func update(player, pose: PostureDefinition, enabled: bool) -> void :
	if not Policy.developer_tools or not enabled or player == null or pose == null or not bool(pose.get_meta("runtime_preview_serve", false)):
		restore();return
	var game = player.get_parent()
	var ball = game.get("ball") if game != null else null
	if ball == null:
		restore();return
	if _live_ball != ball:
		restore();_live_ball = ball;_saved_visible = ball.visible
	_live_ball.visible = false
	if not is_instance_valid(mesh):
		mesh = MeshInstance3D.new();mesh.name = "EditorServeBallPreview"
		var original: MeshInstance3D = null


		for child in ball.get_children():
			if child is MeshInstance3D and child.mesh is SphereMesh and is_equal_approx(child.mesh.radius, Ball.BALL_RADIUS):
				original = child;break
		if original != null:
			mesh.mesh = original.mesh
			mesh.material_override = original.get_active_material(0)
		else:
			var sphere: = SphereMesh.new();sphere.radius = Ball.BALL_RADIUS;sphere.height = Ball.BALL_RADIUS * 2.0
			sphere.radial_segments = 12;sphere.rings = 6;mesh.mesh = sphere
		game.add_child(mesh)
	var phase: String = str(pose.get_meta("preview_serve_phase", "HELD"))
	var elapsed: float = float(pose.get_meta("preview_serve_release_elapsed", 0.0))
	var style: int = int(pose.get_meta("preview_serve_style", 0))
	var plan: Dictionary = _plan(style, player.global_position.y)


	mesh.visible = phase == "HELD" or elapsed <= float(plan.contact_time) + 1e-06
	if not mesh.visible: return
	var offset: Vector3
	if phase == "HELD": offset = pose.get_meta("preview_serve_held_offset", Styles.hold_offset(style))
	else:
		var point: Vector3 = _position_at(plan, elapsed)
		offset = Vector3(point.x, point.y - player.global_position.y, - point.z)
	mesh.global_position = player.global_position + player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + player._get_forward_axis() * offset.z

func _plan(style: int, height: float) -> Dictionary:
	var key: = "%d:%.6f" % [style, height]
	if not _plans.has(key):

		if _plans.size() >= 14: _plans.clear()
		_plans[key] = Styles.release_plan(Vector3(0, height, 0), false, style)
		plan_build_count += 1
	return _plans[key]

func _position_at(plan: Dictionary, elapsed: float) -> Vector3:
	if elapsed <= 0.0: return plan.release_position
	if elapsed >= float(plan.contact_time): return plan.contact_position
	var samples: Array = plan.samples
	if samples.is_empty(): return plan.release_position
	var low: = 0; var high: int = samples.size() - 1
	while low < high:
		var mid: int = (low + high) / 2
		if float(samples[mid].time) < elapsed: low = mid + 1
		else: high = mid
	var before: Dictionary = samples[maxi(0, low - 1)]
	var after: Dictionary = samples[low]
	var duration: float = float(after.time) - float(before.time)
	var first: Vector3 = before.pos
	return first.lerp(after.pos, clampf((elapsed - float(before.time)) / maxf(duration, 1e-06), 0.0, 1.0))

func restore() -> void :
	if is_instance_valid(_live_ball): _live_ball.visible = _saved_visible
	_live_ball = null
	if is_instance_valid(mesh): mesh.visible = false

func dispose() -> void :
	restore()
	if is_instance_valid(mesh): mesh.queue_free()
	mesh = null
	_plans.clear()
