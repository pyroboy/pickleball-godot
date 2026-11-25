extends RefCounted
## Match-load shader warm-up (docs/PERFORMANCE_PLAN.md step 5, PerfToggles.material_prewarm).
## The renderer compiles a material's shader the first time something draws with it, so a
## material first shown mid-rally (shot-name pills, OUT label, kitchen flash, a shadow layer
## turned on) froze that frame. A few frames after the match is built, every material in the
## match that the camera can see is drawn once on a speck in front of the camera (far under a
## pixel), then the specks are freed. Visual only: nothing here is under a player's BodyPivot
## (those meshes are skipped), and nothing is read by gameplay.

const WAIT_FRAMES := 4      # let the match finish building (HUD, fx, labels) first
const SHOW_FRAMES := 3      # frames the specks stay (the first draw compiles)
const MAX_SPECKS := 240
const AHEAD := 1.5          # metres in front of the camera
const SPECK := 0.0002       # metres: a fraction of a pixel at AHEAD


static func run(game: Node) -> void:
	if not PerfToggles.material_prewarm or game == null: return
	var tree: SceneTree = game.get_tree()
	for k in WAIT_FRAMES: await tree.process_frame
	if not is_instance_valid(game) or not game.is_inside_tree(): return
	var cam: Camera3D = game.get_viewport().get_camera_3d()
	if cam == null: return
	var t0 := Time.get_ticks_usec()
	var host := Node3D.new()
	host.name = "MaterialPrewarm"
	host.top_level = true
	game.add_child(host)
	host.global_transform = cam.get_global_transform_interpolated().translated_local(Vector3(0.0, 0.0, -AHEAD))
	var speck := QuadMesh.new()
	speck.size = Vector2(SPECK, SPECK)
	var seen: Dictionary = {}
	var counts := {"materials": 0, "labels": 0, "multimesh": 0}
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if seen.size() >= MAX_SPECKS: break
		var gi := node as GeometryInstance3D
		if gi == host or host.is_ancestor_of(gi): continue
		if (gi.layers & cam.cull_mask) == 0: continue
		if "BodyPivot" in str(gi.get_path()): continue   # the hidden classic body: never drawn
		if gi is Label3D:
			_label_speck(gi, host, seen, counts)
			continue
		if gi is CPUParticles3D or gi is GPUParticles3D: continue   # the loading-stage prewarm covers the bursts
		var mats: Array = []
		if gi.material_override != null: mats.append(gi.material_override)
		if gi.material_overlay != null: mats.append(gi.material_overlay)
		var mm: MultiMesh = null
		if gi is MultiMeshInstance3D:
			mm = (gi as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and gi.material_override == null:
				for s in mm.mesh.get_surface_count():
					if mm.mesh.surface_get_material(s) != null: mats.append(mm.mesh.surface_get_material(s))
		elif gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and gi.material_override == null:
			var mi := gi as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(s)
				if m == null: m = mi.mesh.surface_get_material(s)
				if m != null: mats.append(m)
		for m in mats:
			var key := [m.get_instance_id(), mm != null]
			if seen.has(key): continue
			seen[key] = true
			host.add_child(_mesh_speck(speck, m, mm, gi.layers & cam.cull_mask))
			counts.materials += 1
			if mm != null: counts.multimesh += 1
	var build_us := Time.get_ticks_usec() - t0
	for k in SHOW_FRAMES: await tree.process_frame
	if is_instance_valid(host): host.queue_free()
	var pm = tree.root.get_node_or_null("PerfMonitor")
	if pm != null: pm.note("material_prewarm", {"materials": counts.materials, "labels": counts.labels, "multimesh": counts.multimesh, "build_us": build_us})


static func _mesh_speck(speck: QuadMesh, m: Material, like: MultiMesh, layers: int) -> GeometryInstance3D:
	var out: GeometryInstance3D
	if like != null:
		# Instanced drawing is its own shader version: draw it instanced too.
		var mm := MultiMesh.new()
		mm.transform_format = like.transform_format
		mm.use_colors = like.use_colors
		mm.use_custom_data = like.use_custom_data
		mm.mesh = speck
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		if mm.use_colors: mm.set_instance_color(0, Color.WHITE)
		if mm.use_custom_data: mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		out = mmi
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = speck
		out = mi
	out.material_override = m
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.layers = layers
	return out


## Label3D builds its own material from these settings: one speck per combination.
static func _label_speck(src: Label3D, host: Node3D, seen: Dictionary, counts: Dictionary) -> void:
	var key := ["label", src.font, src.shaded, src.double_sided, src.no_depth_test, src.fixed_size, src.alpha_cut,
		src.alpha_antialiasing_mode, src.billboard, src.texture_filter, src.outline_size > 0]
	if seen.has(key): return
	seen[key] = true
	var l := Label3D.new()
	for prop in ["font", "font_size", "outline_size", "shaded", "double_sided", "no_depth_test", "fixed_size",
			"alpha_cut", "alpha_scissor_threshold", "alpha_hash_scale", "alpha_antialiasing_mode",
			"alpha_antialiasing_edge", "billboard", "texture_filter", "render_priority", "outline_render_priority"]:
		l.set(prop, src.get(prop))
	l.text = "0"
	l.pixel_size = SPECK / maxf(float(src.font_size), 1.0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.layers = src.layers
	host.add_child(l)
	counts.labels += 1
