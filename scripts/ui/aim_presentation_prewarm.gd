extends RefCounted
## Isolated loading-stage renderer warm-up. No Game, input, Ball or RNG owner.
const VERSION := "isolated-match-prewarm-X1"
const VisualSamples = preload("normal_match_visual_samples.gd")
const Trail = preload("res://scripts/fx/ball_trail.gd")
const Trajectory = preload("res://scripts/game_trajectory.gd")
const Arc = preload("res://scripts/ui/aim_arc_style.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const BlurShader = preload("res://shaders/solo_aim_focus.gdshader")
const DimShader = preload("res://shaders/solo_aim_focus_dim.gdshader")
static var _completed: Dictionary = {}
static var _inflight: Dictionary = {}
class WarmSession extends RefCounted:
 var cancelled := false
 var cancel_reason := ""
 var cancel_usec := 0
 var draws := 0
 var phase := "loading_draw"
 func _on_post_draw() -> void: draws+=1

static func cancel_for(host: Node, reason: String = "loading_back") -> bool:
 var session: WarmSession=_inflight.get(host.get_instance_id())
 if session==null:return false
 if not session.cancelled:
  session.cancelled=true;session.cancel_reason=reason;session.cancel_usec=Time.get_ticks_usec()
 return true

static func active_report(host: Node) -> Dictionary:
 var session: WarmSession=_inflight.get(host.get_instance_id())
 if session==null:return {}
 return {"phase":session.phase,"cancelled":session.cancelled,"draws":session.draws,"cancel_usec":session.cancel_usec}

static func _wait_draw(tree: SceneTree, session: WarmSession) -> bool:
 var previous := session.draws
 # SceneTree process frames continue while paused/minimized; cancellation
 # does not depend on a further GPU draw or a restored window.
 while session.draws==previous and not session.cancelled:await tree.process_frame
 return not session.cancelled

static func _finish_session(host_id: int, session: WarmSession) -> void:
 if RenderingServer.frame_post_draw.is_connected(session._on_post_draw):RenderingServer.frame_post_draw.disconnect(session._on_post_draw)
 _inflight.erase(host_id)
const VIEWPORT_FIELDS := ["msaa_3d", "msaa_2d", "screen_space_aa", "use_taa", "use_debanding", "scaling_3d_mode", "scaling_3d_scale", "use_hdr_2d"]

class LoadingCurtain extends CanvasLayer:
 func _input(_event: InputEvent) -> void:
  # Brief loading is deliberately noninteractive; no synthetic action edges.
  get_viewport().set_input_as_handled()

class ArcDrawing extends Control:
 var arc_style := 0
 func _draw() -> void:
  var scale: float = Layout.scale_for(size)
  var path := PackedVector2Array()
  for i in 24:
   var t := float(i)/23.0
   path.append(Vector2(size.x*(0.23+0.52*t),size.y*(0.70-0.43*sin(t*PI*.5))))
  var color := Color(0.82,1.0,0.52,0.92)
  Arc.draw(self,path,Rect2(Vector2.ZERO,size),color,scale,arc_style)
  var outline := PackedVector2Array()
  for i in 49:
   var a := TAU*float(i)/48.0
   outline.append(size*Vector2(.75,.27)+Vector2(cos(a)*32.0,sin(a)*18.0)*scale)
  draw_colored_polygon(outline,Color(color,.12))
  draw_polyline(outline,color,1.8*scale,true)
  # Same fallback marker pipeline used when an estimate has no outline.
  draw_arc(size*Vector2(.3,.45),8*scale,0,TAU,24,color,1.5*scale,true)

static func _key(root_view: Viewport, extent: Vector2i, options: Dictionary) -> String:
 var values: Array = [VERSION,extent,RenderingServer.get_current_rendering_method(),int(options.get("arc_style",0)),int(options.get("shadow_quality",1)),BlurShader.code.sha256_text(),DimShader.code.sha256_text(),(Trajectory as GDScript).source_code.sha256_text(),(Arc as GDScript).source_code.sha256_text(),(Trail as GDScript).source_code.sha256_text()]
 values.append(VisualSamples.fingerprint())
 for field in VIEWPORT_FIELDS: values.append(root_view.get(field))
 return str(values)

static func prepare(host: Node, extent: Vector2i, options: Dictionary = {}) -> Dictionary:
 var start := Time.get_ticks_usec()
 var root_view := host.get_viewport()
 var key := _key(root_view,extent,options)
 if _completed.has(key): return {"status":"already_warm","elapsed_usec":Time.get_ticks_usec()-start,"key":key,"created_nodes":0}
 if DisplayServer.get_name()=="headless": return {"status":"headless_skipped","elapsed_usec":Time.get_ticks_usec()-start}
 if host.find_child("Game",true,false)!=null: return {"status":"requires_loading_stage","elapsed_usec":Time.get_ticks_usec()-start}
 if extent.x<2 or extent.y<2: return {"status":"invalid_extent","elapsed_usec":Time.get_ticks_usec()-start}
 var before_children: Array = []
 for child in host.get_children(): before_children.append(child.get_instance_id())
 var before_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
 var scale_before := Engine.time_scale
 var tree := host.get_tree()
 var host_id := host.get_instance_id()
 if _inflight.has(host_id):return {"status":"already_inflight","elapsed_usec":Time.get_ticks_usec()-start}
 var session := WarmSession.new()
 _inflight[host_id]=session
 RenderingServer.frame_post_draw.connect(session._on_post_draw)
 var loading: LoadingCurtain
 if not bool(options.get("external_loading",false)):
  loading=LoadingCurtain.new()
  loading.name="AimPrewarmLoading";loading.layer=120;loading.process_mode=Node.PROCESS_MODE_ALWAYS
  host.add_child(loading)
  var background := ColorRect.new()
  background.color=Color(.018,.035,.065,1);background.mouse_filter=Control.MOUSE_FILTER_STOP
  background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);loading.add_child(background)
  var message := Label.new()
  message.text="Preparing shot visuals…";message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
  message.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
  message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.add_child(message)
 # The user's loading message is presented before the expensive private draw.
 var loading_drew: bool=await _wait_draw(tree,session)
 if not loading_drew:
  if is_instance_valid(loading):loading.queue_free()
  for index in 2:await tree.process_frame
  _finish_session(host_id,session)
  return {"status":"cancelled","elapsed_usec":Time.get_ticks_usec()-start,"cancel_reason":session.cancel_reason,"cancel_to_return_usec":Time.get_ticks_usec()-session.cancel_usec,"private_viewports_created":0,"viewport_freed":true}
 var loading_visible_usec := Time.get_ticks_usec()
 session.phase="create_private"
 var viewport := SubViewport.new()
 viewport.name="AimPrewarmViewport";viewport.size=extent;viewport.own_world_3d=true
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
 viewport.process_mode=Node.PROCESS_MODE_ALWAYS
 for field in VIEWPORT_FIELDS: viewport.set(field,root_view.get(field))
 host.add_child(viewport)
 RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
 var weak_view: WeakRef = weakref(viewport)
 var world := Node3D.new();viewport.add_child(world)
 var environment := WorldEnvironment.new();world.add_child(environment)
 var env := Environment.new()
 env.background_mode=Environment.BG_SKY
 var sky := Sky.new();var sky_material := ProceduralSkyMaterial.new()
 sky_material.sky_top_color=Color(.3,.52,.85);sky_material.sky_horizon_color=Color(.78,.86,.95);sky_material.sky_curve=.12
 sky_material.ground_bottom_color=Color(.1,.13,.18);sky_material.ground_horizon_color=Color(.38,.42,.5)
 sky_material.sun_angle_max=30.0;sky_material.sun_curve=.15;sky.sky_material=sky_material;env.sky=sky
 env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;env.ambient_light_energy=.32
 env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.tonemap_exposure=1.05;env.tonemap_white=6.0
 env.fog_enabled=false   # mirrors Game._setup_environment (pixel look: no fog)
 environment.environment=env
 # Exact Combined C Game._setup_environment light definitions, followed by
 # its current video.shadow_quality setting. These nodes belong only to world.
 var sun := DirectionalLight3D.new()
 sun.name="Sun"
 sun.rotation_degrees=Vector3(-60,35,0)
 sun.light_energy=1.8
 sun.light_color=Color(1.0,.96,.88)
 sun.shadow_enabled=int(options.get("shadow_quality",1))>0
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
 sun.directional_shadow_max_distance=40.0
 sun.shadow_bias=.03
 sun.shadow_normal_bias=2.0
 sun.shadow_blur=1.3
 sun.shadow_opacity=.85
 sun.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
 world.add_child(sun)
 var camera := Camera3D.new();world.add_child(camera)
 camera.position=Vector3(0,2.4,3.2);camera.look_at(Vector3(0,.2,0));camera.current=true
 # Use the existing private presentation class and its exact material/ribbon
 # builder. No Ball or Game is made. Its live-ball validator must not clear
 # this isolated sample; only this private callback is disconnected.
 var trail := Trail.new()
 trail.process_mode=Node.PROCESS_MODE_DISABLED
 world.add_child(trail)
 if RenderingServer.frame_pre_draw.is_connected(trail._before_draw):
  RenderingServer.frame_pre_draw.disconnect(trail._before_draw)
 var trail_initial_history := trail._points.size()
 trail._points=PackedVector3Array([Vector3(-.45,.28,0),Vector3(-.32,.3,0),Vector3(-.19,.33,0),Vector3(-.06,.35,0),Vector3(.07,.37,0),Vector3(.20,.39,0),Vector3(.33,.42,0),Vector3(.46,.44,0)])
 trail._rebuild_mesh()
 var trail_evidence := {"canonical_class":trail.get_script().resource_path,"source_sha256":(Trail as GDScript).source_code.sha256_text(),"initial_history":trail_initial_history,"private_history":trail._points.size(),"ball_absent":trail._ball==null,"mesh_class":trail.mesh.get_class(),"surfaces":trail.mesh.get_surface_count(),"shading":trail._material.shading_mode,"transparency":trail._material.transparency,"blend":trail._material.blend_mode,"cull":trail._material.cull_mode,"vertex_color":trail._material.vertex_color_use_as_albedo,"no_received_shadows":trail._material.disable_receive_shadows,"world_position":trail.global_position}
 var weak_trail: WeakRef = weakref(trail)
 var samples: Dictionary=VisualSamples.create(host,viewport,world)
 # Invoke only the canonical presentation factory. setup(game) is never called.
 var trajectory := Trajectory.new();world.add_child(trajectory);trajectory._create_landing_cursor()
 trajectory.landing_cursor.position=Vector3(0,.105,0)
 trajectory.landing_cursor.scale=Vector3(.35,.12,.65)
 trajectory.landing_cursor.visible=true
 trajectory.landing_label.position=Vector3(0,.39,0)
 trajectory.landing_label.text="ESTIMATED SPREAD";trajectory.landing_label.visible=true
 trajectory._cursor_material.albedo_color=Color("5ff0ff");trajectory._cursor_material.emission=Color("5ff0ff")
 var layer := CanvasLayer.new();layer.layer=-1;viewport.add_child(layer)
 var dim := ColorRect.new();dim.size=Vector2(extent);dim.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var material := ShaderMaterial.new();material.shader=BlurShader;dim.material=material;layer.add_child(dim)
 var drawing := ArcDrawing.new();drawing.size=Vector2(extent);drawing.arc_style=int(options.get("arc_style",0));layer.add_child(drawing)
 var scale: float = Layout.scale_for(Vector2(extent))
 var uniforms := {"viewport_size":Vector2(extent),"target_uv":Vector2(.75,.27),"blue_uv":Vector2(.3,.75),"blue_head_uv":Vector2(.3,.4),"red_uv":Vector2(.7,.35),"red_head_uv":Vector2(.7,.2),"ball_uv":Vector2(.5,.4),"radius":70.0*scale,"strength":float(options.get("dim",.14)),"blur_radius":maxf(.65,float(options.get("blur",.65)))*2.0*scale,"effect_mix":1.0}
 var stages: Array = []
 for variant in ["blur","dim"]:
  if session.cancelled:break
  session.phase="draw_"+variant
  material.shader=BlurShader if variant=="blur" else DimShader
  for name in uniforms:
   if variant=="dim" and name in ["blur_radius","effect_mix"]: continue
   material.set_shader_parameter(name,uniforms[name])
  trajectory.landing_label.text="ESTIMATED SPREAD" if variant=="blur" else "CHECK ARC\nPERFECT TRAINING\nAIM"
  drawing.queue_redraw()
  var variant_start := Time.get_ticks_usec()
  for index in 2:
   if not await _wait_draw(tree,session):break
  if session.cancelled:break
  stages.append({"variant":variant,"wall_usec":Time.get_ticks_usec()-variant_start,"private_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),"private_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()),"shader":material.shader.resource_path,"size":viewport.size,"visible_draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"canvas_draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
 var rendered := stages.size()==2
 for stage in stages: rendered=rendered and int(stage.visible_draw_calls)>0 and int(stage.canvas_draw_calls)>0
 var warm_finished_usec := Time.get_ticks_usec()
 session.phase="cleanup_viewport"
 viewport.queue_free()
 for index in 2: await tree.process_frame
 var viewport_freed: bool = weak_view.get_ref()==null
 # These resources are private. Release local references before returning to
 # a queued quit; never clear or mutate the shared canonical shader resources.
 material=null;env=null;sky=null;sky_material=null
 session.phase="cleanup_resources"
 if is_instance_valid(loading): loading.queue_free()
 for index in 2: await tree.process_frame
 var after_children: Array = []
 for child in host.get_children(): after_children.append(child.get_instance_id())
 var unchanged_children := before_children==after_children
 var samples_freed := true
 for weak_node in samples.get("weak_nodes",[]): samples_freed=samples_freed and weak_node.get_ref()==null
 var cleanup_ok := viewport_freed and weak_trail.get_ref()==null and samples_freed and bool(samples.get("ok",false))
 var result := {"status":"cancelled" if session.cancelled and cleanup_ok and unchanged_children else "completed" if cleanup_ok and unchanged_children and rendered else "render_or_cleanup_failed","cancelled":session.cancelled,"cancel_reason":session.cancel_reason,"cancel_to_return_usec":Time.get_ticks_usec()-session.cancel_usec if session.cancelled else 0,"elapsed_usec":Time.get_ticks_usec()-start,"loading_visible_usec":loading_visible_usec,"warm_finished_usec":warm_finished_usec,"warm_draw_usec":warm_finished_usec-loading_visible_usec,"stages":stages,"key":key,"extent":extent,"rendered_both_families":rendered,"shadow_quality":int(options.get("shadow_quality",1)),"private_light_definitions":"Combined C Sun (no CourtFill)","viewport_freed":viewport_freed,"private_trail":trail_evidence,"private_trail_freed":weak_trail.get_ref()==null,"normal_match_samples":samples.get("evidence",{}),"normal_match_samples_freed":samples_freed,"host_children_unchanged":unchanged_children,"nodes_before":before_nodes,"nodes_after":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"time_scale_unchanged":Engine.time_scale==scale_before,"game_absent":host.find_child("Game",true,false)==null,"scope":"Private presentation only; caller owns the loading input/lifecycle. Cached return creates no viewport. No simulation, synthetic input or RNG calls. Private viewport/resources are released before a queued quit."}
 _finish_session(host_id,session)
 if result.status=="completed": _completed[key]=true
 return result
