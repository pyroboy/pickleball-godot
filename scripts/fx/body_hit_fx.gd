extends Node3D
## Ball-hits-player reaction: the ball deflects off the body (the point already
## ended for that player's team), a pixel spark + burst marks the impact, and an
## "Ouch!" bubble pops above the player's head and fades.
## Listens to RallyScorer.body_struck. Nothing is parented under a player's
## BodyPivot (gameplay scans meshes there): every node lives under this one.

const RESTITUTION := 0.35        # bounce along the contact normal (soft body)
const TANGENT_KEEP := 0.55       # sliding speed kept along the body
const MIN_OUT_SPEED := 1.2       # m/s away from the body, so the ball never sticks
const POP_UP := 0.9              # m/s upward kick: the ball drops off, not along the floor
const JITTER_DEG := 14.0         # random spread of the outgoing direction
const SPEED_JITTER := 0.12       # +/- share of outgoing speed
const SEPARATION := 0.02         # m pushed out along the normal

const BUBBLE_SECONDS := 1.0
const SPARK_SECONDS := 0.28
const CHUNK_COUNT := 7           # pixel chunks in the burst (own RNG: CPUParticles would
const CHUNK_SECONDS := 0.34      # draw from the global RNG the seeded AI uses)
const BUBBLE_PX := 0.016         # world metres per bubble pixel (chunky, reads as pixel art)
const BUBBLE_TEXT := "Ouch!"
const HEAD_CLEARANCE := 0.32     # m above the head centre
const BUBBLE_FILL := Color("eff6df")
const BUBBLE_EDGE := Color("28545e")
const BUBBLE_INK := Color("c8322b")
const SPARK_COLOR := Color("ffd24a")
const BURST_COLOR := Color("ff7a4a")

signal fx_spawned(kind: String, node: Node)

var _game
var _rng := RandomNumberGenerator.new()   # own RNG: never draws from the seeded AI RNG
var _bubbles: Array = []   # [{node, player, age}]
var _sparks: Array = []    # [{node, age}]
var _bursts: Array = []    # [{node, age, velocities}]
var _chunk_texture: ImageTexture
var _spark_texture: ImageTexture

func setup(game) -> void:
	_game = game
	name = "BodyHitFx"
	if game.rally_scorer != null and game.rally_scorer.has_signal("body_struck"):
		game.rally_scorer.body_struck.connect(_on_body_struck)
	_spark_texture = ImageTexture.create_from_image(_spark_image())
	var chunk := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	chunk.fill(Color.WHITE)
	_chunk_texture = ImageTexture.create_from_image(chunk)
	_rng.seed = 0x0bad

func _on_body_struck(actor_id: int, evidence: Dictionary) -> void:
	var ball = _game.ball
	var player = _game.get_player_by_actor_id(actor_id)
	if ball == null or player == null: return
	var point: Vector3 = evidence.get("point", ball.global_position)
	_rng.seed = hash([int(ball.flight_id), actor_id])   # same hit -> same bounce and burst (bench stays reproducible)
	if evidence.has("normal"):
		# Authority path: the swept query found the hit, the ball itself passed
		# through, so give it the bounce the body would have.
		var center: Vector3 = player.global_position
		var result: Dictionary = deflect(ball.linear_velocity, evidence.get("normal", Vector3.ZERO), point - Vector3(center.x, point.y, center.z), _rng)
		var incoming: Vector3 = ball.linear_velocity
		ball.global_position = point + Vector3(result.normal) * SEPARATION
		ball.linear_velocity = result.velocity
		# Bench evidence (once per hit): what the body did to the ball.
		PerfMonitor.note("body_deflect", {"actor": actor_id, "in": _v(incoming), "out": _v(result.velocity), "normal": _v(result.normal),
			"raw_normal": _v(evidence.get("normal", Vector3.ZERO)), "point": _v(point)})
		ball.angular_velocity *= 0.3
	spawn_impact(point)
	spawn_bubble(player)

static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

## Reflect an incoming velocity off a soft body. normal may face either way;
## fallback (ball centre minus body axis) is used when it is missing.
static func deflect(velocity: Vector3, normal: Vector3, fallback: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var n: Vector3 = normal
	if n.length_squared() < 1e-6: n = fallback
	if n.length_squared() < 1e-6: n = -velocity
	if n.length_squared() < 1e-6: n = Vector3.UP
	n = n.normalized()
	if n.dot(velocity) > 0.0: n = -n          # face the incoming ball
	var vn: float = velocity.dot(n)            # <= 0
	var tangent: Vector3 = velocity - n * vn
	var out: Vector3 = tangent * TANGENT_KEEP - n * vn * RESTITUTION
	if out.dot(n) < MIN_OUT_SPEED: out += n * (MIN_OUT_SPEED - out.dot(n))
	out.y += POP_UP
	var speed: float = out.length() * (1.0 + rng.randf_range(-SPEED_JITTER, SPEED_JITTER))
	var axis: Vector3 = out.cross(Vector3.UP if absf(out.normalized().y) < 0.95 else Vector3.RIGHT).normalized()
	axis = axis.rotated(out.normalized(), rng.randf_range(0.0, TAU))
	var dir: Vector3 = out.normalized().rotated(axis, deg_to_rad(rng.randf_range(0.0, JITTER_DEG)))
	if dir.dot(n) < 0.15: dir = (dir + n * (0.15 - dir.dot(n))).normalized()   # jitter never sends it back in
	return {"velocity": dir * speed, "normal": n}

func spawn_impact(point: Vector3) -> void:
	var burst := Node3D.new()
	burst.name = "BodyHitBurst"
	add_child(burst)
	burst.global_position = point
	var velocities: Array = []
	for i in CHUNK_COUNT:
		var chunk := _billboard(_chunk_texture, 0.022, 9)
		chunk.modulate = BURST_COLOR if i % 2 == 0 else SPARK_COLOR
		burst.add_child(chunk)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.1, 1.0), _rng.randf_range(-1, 1)).normalized()
		velocities.append(dir * _rng.randf_range(1.2, 2.6))
	_bursts.append({"node": burst, "age": 0.0, "velocities": velocities})
	fx_spawned.emit("burst", burst)
	var spark := _billboard(_spark_texture, 0.03, 10)
	spark.name = "BodyHitSpark"
	spark.modulate = SPARK_COLOR
	add_child(spark)
	spark.global_position = point
	spark.scale = Vector3.ONE * 0.4
	_sparks.append({"node": spark, "age": 0.0})
	fx_spawned.emit("spark", spark)

func _billboard(texture: Texture2D, pixel_size: float, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.render_priority = priority
	sprite.pixel_size = pixel_size
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite

func spawn_bubble(player) -> void:
	for entry in _bubbles:           # one bubble per player: a second hit restarts it
		if entry.player == player:
			entry.age = 0.0
			return
	var bubble := Node3D.new()
	bubble.name = "OuchBubble"
	var label := Label3D.new()
	label.text = BUBBLE_TEXT
	label.font_size = 30
	label.pixel_size = 0.006
	label.outline_size = 0
	label.modulate = BUBBLE_INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.render_priority = 12
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text_px: Vector2 = font.get_string_size(BUBBLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size) * label.pixel_size / BUBBLE_PX
	var w: int = int(ceil(text_px.x)) + 8
	var h: int = int(ceil(text_px.y)) + 5
	var tail := 4
	var back := Sprite3D.new()
	back.texture = ImageTexture.create_from_image(_bubble_image(w, h, tail))
	back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	back.no_depth_test = true
	back.shaded = false
	back.render_priority = 11
	back.pixel_size = BUBBLE_PX
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.centered = false
	back.offset = Vector2(-w * 0.5, 0.0)       # tail tip at the anchor, bubble above it
	# Label offset is in its own pixels: centre the text inside the bubble body.
	label.offset = Vector2(0.0, (tail + h * 0.5) * BUBBLE_PX / label.pixel_size)
	bubble.add_child(back)
	bubble.add_child(label)
	add_child(bubble)
	_bubbles.append({"node": bubble, "player": player, "age": 0.0, "back": back, "label": label})
	_place_bubble(_bubbles[-1])
	fx_spawned.emit("bubble", bubble)

func _head_anchor(player) -> Vector3:
	var head: Node3D = player.find_child("HeadMesh", true, false) as Node3D
	if head != null: return head.get_global_transform_interpolated().origin + Vector3.UP * HEAD_CLEARANCE
	return player.get_global_transform_interpolated().origin + Vector3.UP * 1.9

func _place_bubble(entry: Dictionary) -> void:
	var t: float = float(entry.age)
	# Pop: overshoot to 1.25 then settle; drift up a little; fade over the last third.
	var pop: float = 1.0 + 0.25 * sin(clampf(t / 0.18, 0.0, 1.0) * PI) if t < 0.18 else 1.0
	var grow: float = clampf(t / 0.08, 0.0, 1.0)
	var fade: float = 1.0 - smoothstep(BUBBLE_SECONDS * 0.65, BUBBLE_SECONDS, t)
	var node: Node3D = entry.node
	if is_instance_valid(entry.player):
		node.global_position = _head_anchor(entry.player) + Vector3.UP * 0.12 * t
	node.scale = Vector3.ONE * maxf(0.01, pop * lerpf(0.4, 1.0, grow))
	(entry.back as Sprite3D).modulate.a = fade
	(entry.label as Label3D).modulate.a = fade

func _process(delta: float) -> void:
	if _bubbles.is_empty() and _sparks.is_empty() and _bursts.is_empty(): return
	var real: float = delta / maxf(Engine.time_scale, 0.05)
	for index in range(_bubbles.size() - 1, -1, -1):
		var entry: Dictionary = _bubbles[index]
		entry.age += real
		if entry.age >= BUBBLE_SECONDS or not is_instance_valid(entry.player):
			entry.node.queue_free()
			_bubbles.remove_at(index)
			continue
		_place_bubble(entry)
	for index in range(_sparks.size() - 1, -1, -1):
		var entry: Dictionary = _sparks[index]
		entry.age += real
		var share: float = entry.age / SPARK_SECONDS
		if share >= 1.0:
			entry.node.queue_free()
			_sparks.remove_at(index)
			continue
		var spark: Sprite3D = entry.node
		spark.scale = Vector3.ONE * lerpf(0.4, 1.3, sqrt(share))
		spark.rotation.z = share * 0.6
		spark.modulate.a = 1.0 - share * share

	for index in range(_bursts.size() - 1, -1, -1):
		var entry: Dictionary = _bursts[index]
		entry.age += real
		if entry.age >= CHUNK_SECONDS:
			entry.node.queue_free()
			_bursts.remove_at(index)
			continue
		var t: float = entry.age
		var chunks: Array = entry.node.get_children()
		for i in chunks.size():
			var v: Vector3 = entry.velocities[i]
			var chunk: Sprite3D = chunks[i]
			chunk.position = v * t + Vector3.DOWN * 4.5 * t * t
			chunk.modulate.a = 1.0 - smoothstep(CHUNK_SECONDS * 0.5, CHUNK_SECONDS, t)

func active_count() -> int:
	return _bubbles.size() + _sparks.size() + _bursts.size()

## 4-point pixel star with a hollow ring: the "hit" spark.
static func _spark_image() -> Image:
	var size := 15
	var c := 7
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for i in size:
		var d: int = absi(i - c)
		var arm: Color = Color.WHITE if d < 6 else Color(1, 1, 1, 0.6)
		image.set_pixel(i, c, arm)
		image.set_pixel(c, i, arm)
		if d <= 3:
			image.set_pixel(i, i, Color(1, 1, 1, 0.85))
			image.set_pixel(i, size - 1 - i, Color(1, 1, 1, 0.85))
	for y in size:
		for x in size:
			var r: float = Vector2(x - c, y - c).length()
			if r > 4.5 and r < 5.6 and (x + y) % 2 == 0: image.set_pixel(x, y, Color.WHITE)
	return image

## Speech bubble body (w x h) with a pointed tail of `tail` rows below it,
## flat pixel corners, 1 px border. Image row 0 is the top.
static func _bubble_image(w: int, h: int, tail: int) -> Image:
	var image := Image.create(w, h + tail, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var corner: bool = (x == 0 or x == w - 1) and (y == 0 or y == h - 1)
			if corner: continue
			var edge: bool = x == 0 or x == w - 1 or y == 0 or y == h - 1 or ((x == 1 or x == w - 2) and (y == 1 or y == h - 2))
			image.set_pixel(x, y, BUBBLE_EDGE if edge else BUBBLE_FILL)
	var mid: int = w / 2
	for row in tail:
		var y: int = h - 1 + row
		var half: int = tail - row
		for x in range(mid - half, mid + half + 1):
			if x < 0 or x >= w or y >= h + tail: continue
			var edge: bool = x == mid - half or x == mid + half or row == tail - 1
			image.set_pixel(x, y, BUBBLE_EDGE if edge else BUBBLE_FILL)
	return image
