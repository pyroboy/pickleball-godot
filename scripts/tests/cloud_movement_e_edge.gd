extends SceneTree
const Guide = preload("res://scripts/ui/incoming_movement_guide.gd")
const Before = preload("res://tools/cloud_qa/movement_e_before_guide.gd")
const Feeds = preload("res://tools/cloud_qa/movement_guide_fixtures.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
var game
var guide
var before
var rate := 60
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var name := ""
var output := "/tmp/movement-edge-readability.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(name + ": " + label)

func run() -> void:
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game); Feeds.detach_automatic(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	guide = Guide.new(); game.add_child(guide); guide.setup(game)
	before = Before.new(); game.add_child(before); before.setup(game)
	for item in [guide,before]: item.set_process(false); item.set_physics_process(false)
	for physical in [Vector2i(390,844),Vector2i(430,932),Vector2i(540,960),Vector2i(960,540)]:
		root.size = physical; root.content_scale_size = Vector2i(720,1280)
		await process_frame; await process_frame
		game.mobile_controls._layout(); game.camera_rig.update(0.0)
		var size := root.get_visible_rect().size
		var ratio := Vector2(physical)/size
		var pixels := minf(ratio.x,ratio.y)
		var metrics := Guide.visual_metrics(size,pixels)
		var band := Guide.court_band(size,Guide.Layout.safe_rect(root))
		name = "group_geometry_" + str(physical)
		var exclusions: Array[Rect2] = guide._control_exclusions(metrics.gap)
		exclusions.append_array(guide._edge_hud_exclusions(metrics.gap))
		edge_hud_rectangles(metrics)
		var anchors := [band.position + Vector2(20,20),Vector2(band.end.x-20,band.position.y+20),band.end-Vector2(20,20),Vector2(band.position.x+20,band.end.y-20),Vector2(band.position.x+20,band.get_center().y),Vector2(band.end.x-20,band.get_center().y)]
		var shown := 0
		var hidden := 0
		var max_usec := 0
		for index in 24:
			var direction := Vector2.from_angle(TAU*float(index)/24)
			for anchor: Vector2 in anchors:
				var ball := anchor + Vector2(20,-15) if index%3 == 0 else Vector2.INF
				var started := Time.get_ticks_usec()
				var group: Dictionary = guide._edge_group(anchor,direction,Vector2(110,44)*metrics.scale,band,ball,metrics,exclusions,pixels)
				max_usec = maxi(max_usec,Time.get_ticks_usec()-started)
				if group.is_empty(): hidden += 1; continue
				shown += 1
				validate_group(group,direction,band,ball,metrics,exclusions,pixels)
				var stable: Dictionary = guide._edge_group(anchor,direction,Vector2(110,44)*metrics.scale,band,ball,metrics,exclusions,pixels)
				check(stable == group,"identical frame changes safe group placement")
		check(shown > 100,"readable groups over-suppressed ordinary edge directions")
		var blocked: Array[Rect2] = [band]
		check(guide._edge_group(band.get_center(),Vector2.RIGHT,Vector2(110,44),band,Vector2.INF,metrics,blocked,pixels).is_empty(),"fully occluded group not hidden")
		rows.append({"case":name,"shown":shown,"hidden":hidden,"max_group_cpu_usec":max_usec})
		edge_side_stability(band,metrics,pixels)
		await on_court_parity(physical)
		edge_crossings(physical,pixels)
		edge_invalidity()
	current_scene = null; game.queue_free(); await process_frame; await process_frame
	var until := Time.get_ticks_usec()+150000
	while Time.get_ticks_usec()<until: OS.delay_msec(5); await process_frame
	var report := {"rate":rate,"checks":checks,"failures":failures,"cases":rows,"scope":"Separate edge-only presentation patch after frozen D; no physics/advice changes"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for error in failures: push_error(error)
	print("MOVEMENT EDGE READABILITY %d Hz: %d checks, %d failures" % [rate,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func validate_group(group: Dictionary, direction: Vector2, band: Rect2, ball: Vector2, metrics: Dictionary, exclusions: Array[Rect2], pixels: float) -> void:
	var arrow: PackedVector2Array = group.arrow
	var wings: PackedVector2Array = group.wings
	var displayed := (arrow[1]-arrow[0]).normalized()
	var head: float = (wings[1]-(wings[0]+wings[2])*0.5).dot(direction)
	check(displayed.dot(direction)>0.99999,"clipping changed original projected direction")
	check(head*pixels>=7.99,"head smaller than8physical pixels")
	check((arrow[0].distance_to(arrow[1])-head)*pixels>=13.99,"shaft shorter than14physical pixels")
	check(band.encloses(group.glyph_rect) and band.encloses(group.label_rect),"group leaves safe court band")
	check(not Guide._overlaps_any(group.glyph_rect.merge(group.label_rect),exclusions),"composite group covers active controls")
	var card: Rect2 = group.label_rect
	var glyph: Rect2 = group.glyph_rect
	var separation := Vector2(maxf(0,maxf(card.position.x-glyph.end.x,glyph.position.x-card.end.x)),maxf(0,maxf(card.position.y-glyph.end.y,glyph.position.y-card.end.y))).length()
	check(separation*pixels>=3.99 and separation*pixels<=8.01,"card detached from glyph")
	if ball.is_finite():
		var clearance: float = maxf(14.0*metrics.scale,metrics.stroke*5)
		check(not glyph.grow(clearance).has_point(ball) and not card.grow(clearance).has_point(ball),"group covers live ball")
		for line in [[arrow[0],arrow[1]],[wings[0],wings[1]],[wings[1],wings[2]]]:
			check(Geometry2D.get_closest_point_to_segment(ball,line[0],line[1]).distance_to(ball)>=clearance,"draw-time ball guard clips glyph")
	for point: Vector2 in arrow: check(band.has_point(point),"shaft endpoint gets clipped")
	for point: Vector2 in wings: check(band.has_point(point),"head endpoint gets clipped")

func prepare_pair(status: String, mirrored: bool) -> void:
	var player = Feeds.prepare(game,status,mirrored)
	if status == "NO_TIME":
		player.global_position.x = 3 if mirrored else -3
		player.leg_ik.feet_initialized = false; player._process(0.0)
		game.ball.global_position.y = 1.1
		game.ball.linear_velocity = Vector3(0,-0.5,-0.3 if mirrored else 0.3)
	for item in [guide,before]:
		item.player = player; item.advisor = Guide.Advisor.new(); item._reset_generation = game._point_reset_generation
		item.cancel(); item.tick(0.0,Feeds.flight(game))
	if status == "NO_TIME":
		for frame in range(ceili(Guide.NO_TIME_ENTRY_SECONDS*rate)):
			for item in [guide,before]: item.tick(1.0/rate,Feeds.flight(game))

func on_court_parity(physical: Vector2i) -> void:
	name = "on_court_exact_parity_" + str(physical)
	var count := 0
	for status in ["MOVE","TIGHT","NO_TIME"]:
		for mirrored in [false,true]:
			prepare_pair(status,mirrored)
			var original: Dictionary = before.presentation_state()
			check(not original.is_empty() and not original.edge,"reference on-court fixture unavailable")
			if original.is_empty() or original.edge: continue
			for frame in range(rate/2):
				guide._reproject(); before._reproject()
				check(guide.presentation_state() == before.presentation_state(),"on-court presentation changed")
				count += 1
	rows.append({"case":name,"identical_frames":count})
	await process_frame

func edge_crossings(physical: Vector2i,pixels: float) -> void:
	name = "edge_crossings_"+str(physical)
	prepare_pair("MOVE",false)
	var camera: Camera3D = root.get_camera_3d()
	var saved := camera.global_transform
	var shown := 0
	var edge_shown := 0
	for frame in range(rate*2):
		camera.global_transform = saved
		camera.global_position.x += sin(float(frame)/rate*TAU)*18.0
		guide._reproject()
		var state: Dictionary = guide.presentation_state()
		if state.is_empty(): continue
		shown += 1
		check(state.target_world.x == guide._advice.target_root.x and state.target_world.z == guide._advice.target_root.z,"edge layout moved verified floor target")
		if not state.edge: continue
		edge_shown += 1
		check(state.ring.is_empty(),"edge annotation invents floor ring")
		var floor_root := Vector3(guide.player.global_position.x,Guide.FLOOR_LIFT+PickleballConstants.FLOOR_Y,guide.player.global_position.z)
		var expected: Vector2 = (state.center-camera.unproject_position(floor_root)).normalized()
		var arrow: PackedVector2Array = state.arrow
		check((arrow[1]-arrow[0]).normalized().dot(expected)>0.99999,"same-edge offscreen direction reversed")
		check(arrow[0].distance_to(arrow[1])*pixels>=21.99,"visible edge lost readable shaft/head")
	check(shown>0 and edge_shown>0,"camera crossing produced no edge guide")
	rows.append({"case":name,"visible_frames":shown,"edge_frames":edge_shown})
	camera.global_transform = saved
	guide._advice = {"visible":false,"status":"UNKNOWN"};guide._reproject()
	check(guide.presentation_state().is_empty(),"unknown advice retained edge glyph")
	prepare_pair("MOVE",false)
	game.ball.is_in_play = false;guide._process(0)
	check(guide.presentation_state().is_empty(),"dead ball retained edge group")
	guide.cancel();check(guide._edge_strategy.is_empty(),"cancel retained edge strategy")

func edge_side_stability(band: Rect2,metrics: Dictionary,pixels: float) -> void:
	name = "edge_safe_side_stability"
	guide._edge_strategy = []
	var empty: Array[Rect2] = []
	var anchor := Vector2(band.end.x-20,band.get_center().y)
	var size: Vector2 = Vector2(110,44)*metrics.scale
	var initial: Dictionary = guide._edge_group(anchor,Vector2.RIGHT,size,band,Vector2.INF,metrics,empty,pixels)
	check(not initial.is_empty(),"stable edge setup hidden")
	if initial.is_empty(): return
	var bounds: Rect2 = initial.glyph_rect.merge(initial.label_rect).grow(maxf(14*metrics.scale,metrics.stroke*5))
	var previous: Array = initial.strategy
	var switches := 0
	for frame in range(rate*2):
		var ball := Vector2(bounds.end.x+sin(float(frame)/rate*TAU*4)*0.25/pixels,bounds.get_center().y)
		var group: Dictionary = guide._edge_group(anchor,Vector2.RIGHT,size,band,ball,metrics,empty,pixels)
		check(not group.is_empty(),"safe alternate edge group flickered hidden")
		if group.is_empty(): continue
		if group.strategy != previous: switches += 1
		previous = group.strategy
		validate_group(group,Vector2.RIGHT,band,ball,metrics,empty,pixels)
	check(switches<=1,"subpixel ball boundary caused repeated edge layout switches")
	rows.append({"case":name,"switches":switches,"frames":rate*2})

func edge_invalidity() -> void:
	name = "edge_immediate_invalidity"
	var camera: Camera3D = root.get_camera_3d()
	var saved := camera.global_transform
	for invalidation in ["unknown","flight","bounce","dead","reset","setting","behind","camera"]:
		camera.global_transform = saved
		prepare_pair("MOVE",false)
		var found := false
		for shift in [-18.0,18.0,-8.0,8.0]:
			camera.global_transform = saved;camera.global_position.x += shift
			guide._reproject()
			var state: Dictionary = guide.presentation_state()
			if not state.is_empty() and state.edge: found = true;break
		check(found,"edge invalidity setup unavailable: "+invalidation)
		match invalidation:
			"unknown": guide._advice = {"visible":false,"status":"UNKNOWN"}
			"flight": game.ball.flight_id += 1
			"bounce": game.ball.bounces_since_last_hit += 1
			"dead": game.ball.is_in_play = false
			"reset": game._point_reset_generation += 1
			"setting": root.get_node("Settings")._config.set_value("gameplay","movement_guide",false)
			"behind":
				var target: Vector3 = guide._advice.target_root
				target.y = PickleballConstants.FLOOR_Y+Guide.FLOOR_LIFT
				camera.look_at(camera.global_position-(target-camera.global_position),Vector3.UP)
				check(camera.is_position_behind(target),"test camera did not put target behind")
			"camera": camera.clear_current(false)
		guide._process(0)
		check(guide.presentation_state().is_empty(),"stale edge retained after "+invalidation)
		camera.make_current()
		root.get_node("Settings")._config.set_value("gameplay","movement_guide",true)
	camera.global_transform = saved

func edge_hud_rectangles(metrics: Dictionary) -> void:
	var panels := [game.hud._score_panel,game.hud._status_panel,game.hud._toolbar,game.reaction_button]
	for panel: Control in panels:
		var old_rect := panel.get_global_rect().grow(metrics.gap)
		var visible_before := panel.visible
		var position_before := panel.position
		var rects: Array[Rect2] = guide._edge_hud_exclusions(metrics.gap)
		var old_count := rects.count(old_rect)
		var was_drawn := panel.is_visible_in_tree()
		panel.hide()
		check(guide._edge_hud_exclusions(metrics.gap).count(old_rect) == old_count-int(was_drawn),"HUD exclusion ignores actual visibility")
		panel.show()
		panel.position += Vector2(-13,-17)
		var moved := panel.get_global_rect().grow(metrics.gap)
		rects = guide._edge_hud_exclusions(metrics.gap)
		check(rects.has(moved) and rects.count(old_rect) == old_count-int(was_drawn),"HUD rectangle not recomputed immediately")
		panel.hide()
		check(not guide._edge_hud_exclusions(metrics.gap).has(moved),"hidden HUD retained an exclusion")
		panel.position = position_before
		panel.visible = visible_before
	for rect: Rect2 in guide._edge_hud_exclusions(metrics.gap):
		check(not rect.encloses(root.get_visible_rect()),"whole-canvas exclusion")
