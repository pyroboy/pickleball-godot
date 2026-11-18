extends RefCounted
## Private render samples. No Game/Ball, gameplay signals, input or random calls.
const Burst = preload("res://scripts/fx/impact_burst.gd")
const DecalVisual = preload("res://scripts/fx/bounce_decal.gd")
const Readability = preload("res://scripts/fx/ball_readability.gd")
const Shadows = preload("res://scripts/fx/ground_shadows.gd")
const HudVisual = preload("res://scripts/ui/hud.gd")

static func fingerprint() -> Array:
 var result: Array=[]
 for script in [Burst,DecalVisual,Readability,Shadows,HudVisual]:
  result.append([script.resource_path,script.source_code.sha256_text()])
 for path in ["res://shaders/ball_readability.gdshader","res://shaders/ground_shadow.gdshader","res://shaders/ball_ground_shadow.gdshader","res://scripts/ui/hud_chrome.gd","res://scripts/ui/scoreboard_ball.gd","res://scripts/ui/game_ui_theme.gd"]:
  result.append([path,FileAccess.get_file_as_string(path).sha256_text()])
 return result

static func create(host: Node, viewport: SubViewport, world: Node3D) -> Dictionary:
 var pool=host.get_node_or_null("/root/FXPool")
 if pool==null or pool._bursts.is_empty():return {"ok":false,"reason":"canonical_particle_resources_missing"}
 var canonical: CPUParticles3D=pool._bursts[0]._particles
 # CPUParticles3D's constructor consumes global Math::rand in Godot 4.6.3.
 # Its render base is a MultiMesh with TRANSFORM_3D, colors and custom data.
 # Reuse the existing pool's exact immutable mesh/material in that same render
 # representation, without constructing/emitting another CPU particle owner.
 var particles:=MultiMeshInstance3D.new()
 particles.name="PrivateCanonicalImpactInstances"
 var instances:=MultiMesh.new()
 instances.transform_format=MultiMesh.TRANSFORM_3D
 instances.use_colors=true;instances.use_custom_data=true
 instances.instance_count=Burst.BASE_COUNT
 instances.mesh=canonical.mesh
 for i in Burst.BASE_COUNT:
  instances.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.7),Vector3(-.32+float(i)*.09,.60+float(i%3)*.05,0)))
  instances.set_instance_color(i,Color.WHITE)
  instances.set_instance_custom_data(i,Color(0,0,0,1))
 particles.multimesh=instances
 particles.material_override=canonical.material_override
 particles.cast_shadow=canonical.cast_shadow
 particles.transparency=canonical.transparency
 particles.layers=canonical.layers
 world.add_child(particles)
 var decal:=DecalVisual.new();decal.process_mode=Node.PROCESS_MODE_DISABLED
 world.add_child(decal);decal.position=Vector3(.35,.1,.15);decal.visible=true
 # This is a private label/panel instance, not a Game/HUD signal emission.
 var hud:=HudVisual.new();hud.process_mode=Node.PROCESS_MODE_DISABLED
 viewport.add_child(hud)
 hud.show_rally_result("FAULT · SIDE OUT", "NEXT SERVE · SECOND BOUNCE")
 hud.fault.text="FAULT";hud.fault.show();hud.out_text.show()
 hud.speed.text="36 km/h";hud.speed.modulate.a=1
 hud.shot_type.text="PERFECT · GREAT · GOOD";hud.shot_type.modulate.a=1
 var cue:=Readability.new();world.add_child(cue);cue.position=Vector3(-.35,.45,-4)
 var ball_target:=Node3D.new();world.add_child(ball_target);ball_target.position=Vector3(-.35,.45,0)
 var actor_target:=Node3D.new();world.add_child(actor_target);actor_target.position=Vector3(.35,1,0)
 var shadows:=Shadows.new();world.add_child(shadows)
 shadows.setup(ball_target,actor_target,actor_target)
 shadows.process_mode=Node.PROCESS_MODE_DISABLED
 var material: BaseMaterial3D=canonical.material_override
 return {"ok":true,"weak_nodes":[weakref(particles),weakref(decal),weakref(hud),weakref(cue),weakref(shadows)],"evidence":{"canonical_particle_mesh":canonical.mesh.get_instance_id(),"private_particle_mesh":instances.mesh.get_instance_id(),"canonical_particle_material":canonical.material_override.get_instance_id(),"private_particle_material":particles.material_override.get_instance_id(),"instance_count":instances.instance_count,"private_buffer_float_count":instances.buffer.size(),"instance_stride_floats":20,"canonical_renderer_base_valid":canonical.get_base().is_valid(),"transform_format":instances.transform_format,"colors":instances.use_colors,"custom_data":instances.use_custom_data,"particle_flags":{"shading":material.shading_mode,"transparency":material.transparency,"cull":material.cull_mode,"vertex_color":material.vertex_color_use_as_albedo,"cast_shadow":particles.cast_shadow},"particle_process_owner_created":false,"particle_emission_called":false,"decal_tween_created":decal._tween!=null,"canonical_shader_paths":[Readability.CueShader.resource_path,Shadows.ShaderSource.resource_path,Shadows.BallShaderSource.resource_path],"hud_private":true,"sources":fingerprint()}}
