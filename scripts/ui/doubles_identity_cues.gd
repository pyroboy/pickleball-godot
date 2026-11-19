extends Node3D
## Small ground-level identity cues, without collision or contact authority.
const Layout=preload("res://scripts/ui/mobile_layout.gd")
var game
var rows:Array=[]
func setup(owner)->void:
	game=owner;name="DoublesIdentityCues"
	for actor in game.get_players():
		var marker:=MeshInstance3D.new();var ring:=TorusMesh.new()
		ring.inner_radius=.235;ring.outer_radius=.255;ring.rings=16;ring.ring_segments=3
		marker.mesh=ring;marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("e8f4ff")
		marker.material_override=material;marker.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(marker)
		var label:=Label3D.new();label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=false
		label.font_size=34;label.pixel_size=.004;label.outline_size=9;label.outline_modulate=Color("102538")
		label.modulate=Color("c9e7ff") if actor.team_id==0 else Color("ffc9c2")
		label.text="YOU" if not actor.is_ai else "PARTNER" if actor.team_id==0 else ""
		label.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(label);rows.append({"actor":actor,"marker":marker,"label":label,"material":material})
	_update_cues()
func _process(_delta:float)->void:_update_cues()
func _update_cues()->void:
	if game==null:return
	var show:bool=game.hud!=null and game.hud._gameplay_visible and not game._tool_state_active()
	visible=show
	if not show:return
	var server=game.get_server_actor() if game.game_state in [game.GameState.WAITING,game.GameState.SERVING] and not game.match_over else null
	for row in rows:
		var actor=row.actor;var is_server:bool=actor==server;var human:bool=not actor.is_ai
		var end_sign:float=-1.0 if actor.court_side==1 else 1.0
		var at:Vector3=actor.get_global_transform_interpolated().origin   # drawn position (smooth at 30 Hz physics)
		row.marker.global_position=Vector3(at.x,PickleballConstants.FLOOR_Y+.018,at.z)
		row.marker.visible=human or is_server
		row.material.albedo_color=Color("ffe49a") if is_server else Color("e8f4ff")
		row.label.global_position=Vector3(at.x,PickleballConstants.FLOOR_Y+.095,at.z+end_sign*.55)
		row.label.text=("YOU" if human else "PARTNER" if actor.team_id==0 else "OPP 1" if actor.actor_id==1 else "OPP 2")+ (" · SERVE" if is_server else "")
		row.label.visible=human or actor.team_id==0 or is_server
