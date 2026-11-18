extends RefCounted
## Visual-only Ready -> authored Windup -> extended Strong Windup.
## The caller owns the existing input clock; this class never charges a shot.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Variants = preload("res://scripts/stroke_windup_variants.gd")
const ReadyMotion = preload("res://scripts/incoming_ready_motion.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const WINDUP_SECONDS := 0.6
const STRONG_SECONDS := 1.2
const LIMIT_EPSILON := 0.00015
const EXTENSION_CACHE_LIMIT := 64
var _curves: Dictionary = {}
var report: Dictionary = {}

func reset(clear_curves: bool = true) -> void:
	if clear_curves: _curves.clear()
	report.clear()

func sample(base: PostureDefinition, ready: PostureDefinition, held_seconds: float, player = null, directional_only: bool = false) -> PostureDefinition:
	var elapsed: float = maxf(held_seconds, 0.0)
	var windup: PostureDefinition = Path.sample(base, 0.0)
	var pose: PostureDefinition
	if elapsed <= WINDUP_SECONDS:
		var progress: float = smoothstep(0.0, WINDUP_SECONDS, elapsed)
		pose = ReadyMotion.GripTransition.sample(ready, windup, progress) if ReadyMotion.GripTransition.supports_both_joined(ready, windup) else Path.blend_pose(ready, windup, progress)
		report = {"stage": "ready_to_windup", "held_seconds": elapsed, "strong_weight": 0.0, "applied_distance_m": 0.0}
	else:
		var progress: float = 0.0 if directional_only else smoothstep(WINDUP_SECONDS, STRONG_SECONDS, elapsed)
		pose = _strong_pose(base, windup, progress, player)
		report["stage"] = "windup_to_strong"
		report["held_seconds"] = elapsed
	# Identity follows the selected incoming stroke even while its geometry is Ready.
	pose.posture_id = base.posture_id
	pose.display_name = base.display_name
	pose.family = base.family
	pose.height_tier = base.height_tier
	pose.set_meta("held_hit_seconds", elapsed)
	pose.set_meta("visual_wrist_lag_deg", 0.0)
	return pose

func prewarm(base: PostureDefinition, base_sampler: Callable = Callable(), cache_key: String = "", refresh: bool = false) -> void:
	_curve(base, base_sampler, cache_key, refresh)

func _curve(base: PostureDefinition, base_sampler: Callable = Callable(), cache_key: String = "", refresh: bool = false):
	var id: String = str(base.posture_id) if cache_key.is_empty() else cache_key
	if refresh and _curves.has(id):
		var current: PostureDefinition = base if base_sampler.is_valid() else PostureLibrary.instance().get_def(base.posture_id)
		if current != null and _source_fingerprint(current) != _curves[id].fingerprint: _curves.erase(id)
	if not _curves.has(id):
		# Canonical cached geometry cannot retain an old world/root transform.
		# The live contact fit is applied below and its limits are checked per sample.
		var source: PostureDefinition = base if base_sampler.is_valid() else PostureLibrary.instance().get_def(base.posture_id)
		if source == null: source = base
		source = source.duplicate(true)
		var curve = Variants.new()
		curve.configure(source, Variants.STRONG, base_sampler)
		_curves[id] = {"source": source, "normal": base_sampler.call(source, 0.0) if base_sampler.is_valid() else Path.sample(source, 0.0), "curve": curve, "fingerprint": _source_fingerprint(source), "extensions": {}}
	return _curves[id]

func _candidate(base: PostureDefinition, windup: PostureDefinition, data: Dictionary, amount: float) -> PostureDefinition:
	var normal: PostureDefinition = data.normal
	# Canonical extension depends only on the immutable curve and exact amount.
	# Live root/contact/body fitting still runs below for every candidate.
	var samples: Dictionary = data.extensions
	if not samples.has(amount):
		if samples.size() >= EXTENSION_CACHE_LIMIT: samples.erase(samples.keys()[0])
		var sampled: PostureDefinition = data.curve.sample_amount(data.source, 0.0, amount)
		# Retain only the values consumed below, never a pose or its bake payload.
		# Scalar floats retain their original precision (Vector3 would round them).
		samples[amount] = [sampled.paddle_forehand_mul, sampled.paddle_y_offset, sampled.paddle_forward_mul, Orientation.canonical_basis(sampled)]
	var extended: Array = samples[amount]
	var pose: PostureDefinition = windup.duplicate(true)
	pose.paddle_forehand_mul += float(extended[0]) - normal.paddle_forehand_mul
	pose.paddle_y_offset += float(extended[1]) - normal.paddle_y_offset
	pose.paddle_forward_mul += float(extended[2]) - normal.paddle_forward_mul
	var turn: Basis = Orientation.canonical_basis(normal).inverse() * (extended[3] as Basis)
	Orientation.set_canonical_basis(pose, Orientation.canonical_basis(windup) * turn)
	return pose

func _strong_pose(base: PostureDefinition, windup: PostureDefinition, amount: float, player) -> PostureDefinition:
	return extend_windup(base, windup, amount, player)

func extend_windup(base: PostureDefinition, windup: PostureDefinition, amount: float, player, base_sampler: Callable = Callable(), cache_key: String = "") -> PostureDefinition:
	var data: Dictionary = _curve(base, base_sampler, cache_key)
	var applied: float = amount
	var original_transform := Transform3D.IDENTITY
	var allowed := 0.0
	if player != null:
		original_transform = Path.world_transform(player, windup)
		var old_distance: float = WristReach.wrist_world(original_transform, windup).distance_to(Body.shoulder_world(player, windup))
		allowed = maxf(WristReach.link_budget(player, windup), old_distance) + LIMIT_EPSILON
	var pose: PostureDefinition = _candidate(base, windup, data, applied)
	if player != null and not _fits_precomputed(pose, player, allowed):
		var low := 0.0
		var high := amount
		for iteration in range(10):
			var middle: float = (low + high) * 0.5
			if _fits_precomputed(_candidate(base, windup, data, middle), player, allowed): low = middle
			else: high = middle
		applied = low
		pose = _candidate(base, windup, data, applied)
	report = {"strong_weight": applied, "limited": applied < amount - 0.001, "applied_distance_m": float(data.curve.report.applied_distance_m) * applied}
	return pose

func _fits(pose: PostureDefinition, original: PostureDefinition, player) -> bool:
	var original_transform: Transform3D = Path.world_transform(player, original)
	var old_distance: float = WristReach.wrist_world(original_transform, original).distance_to(Body.shoulder_world(player, original))
	var allowed: float = maxf(WristReach.link_budget(player, pose), old_distance) + LIMIT_EPSILON
	return _fits_precomputed(pose, player, allowed)

func _fits_precomputed(pose: PostureDefinition, player, allowed: float) -> bool:
	var actual: Transform3D = Path.world_transform(player, pose)
	var stance: Basis = Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
	var desired_head: Vector3 = player.global_position + stance * (Path.canonical_transform(pose) * D.HEAD_OFFSET)
	if desired_head.distance_to(actual * D.HEAD_OFFSET) > LIMIT_EPSILON: return false
	var shoulder: Vector3 = Body.shoulder_world(player, pose)
	return WristReach.wrist_world(actual, pose).distance_to(shoulder) <= allowed

static func _source_fingerprint(source: PostureDefinition) -> String:
	# Bakes are immutable, sealed data; never validate/copy a megabyte payload
	# just to detect a held-curve source change.
	return preload("res://scripts/mobile_pose_store.gd").authored_fingerprint(source)+str(source.elbow_preset_bake.get("payload_sha256",""))
