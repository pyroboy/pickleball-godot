extends Node3D
## Small ground-level identity cues, without collision or contact authority.
## Your ring is thick and team blue so it reads at a glance; the other rings show only on
## the server (gold). Name tags sit on the floor in front of the feet, and step up above
## the head while that spot would cover the move stick or the HIT pad on screen.
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const CuePriority = preload("res://scripts/ui/player_cue_priority.gd")
const TAG_FONT_SIZE := 34
const TAG_PIXEL := .004
const TAG_HEAD_HEIGHT := 1.2    # above the body origin (head is ~0.92): a nameplate over the card
const TAG_CLEAR_MARGIN := 16.0  # screen px the floor spot must be clear by before the tag returns
const YOUR_RING := UiTheme.TEAM_BLUE
var game
var rows:Array=[]
func setup(owner)->void:
	game=owner;name="DoublesIdentityCues"
	for actor in game.get_players():
		var human:bool=not actor.is_ai
		var marker:=MeshInstance3D.new();var ring:=TorusMesh.new()
		# Yours: about 4x the band width, flattened onto the floor.
		ring.inner_radius=.2 if human else .235;ring.outer_radius=.29 if human else .255;ring.rings=16;ring.ring_segments=3
		marker.mesh=ring;marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if human: marker.scale=Vector3(1,.45,1)
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=YOUR_RING if human else Color("e8f4ff")
		marker.material_override=material;marker.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(marker)
		var label:=Label3D.new();label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=false
		label.font_size=TAG_FONT_SIZE;label.pixel_size=TAG_PIXEL;label.outline_size=9;label.outline_modulate=Color("102538")
		label.modulate=Color("c9e7ff") if actor.team_id==0 else Color("ffc9c2")
		var base:String="YOU" if human else "PARTNER" if actor.team_id==0 else "OPP 1" if actor.actor_id==1 else "OPP 2"
		label.text=base
		label.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(label)
		# Both tag texts are built once: no per-frame string work.
		rows.append({"actor":actor,"marker":marker,"label":label,"material":material,"names":[base,base+" · SERVE"],"half_w":[_half_width(label,base),_half_width(label,base+" · SERVE")],"serving":-1,"above":false})
	_update_cues()
func _process(_delta:float)->void:_update_cues()
func _update_cues()->void:
	if game==null:return
	var show:bool=game.hud!=null and game.hud._gameplay_visible and not game._tool_state_active()
	visible=show
	if not show:return
	var server=game.get_server_actor() if game.game_state in [game.GameState.WAITING,game.GameState.SERVING] and not game.match_over else null
	var camera:Camera3D=get_viewport().get_camera_3d()
	var controls=game.get("mobile_controls")
	var avoid:bool=camera!=null and controls!=null and controls.enabled and controls.visible
	# One player cue at a time: your ring and tag step aside for the aim, timing,
	# landing, smash and movement cues (player_cue_priority.gd).
	var you_cue:bool=CuePriority.current(game)==CuePriority.YOU
	for row in rows:
		var actor=row.actor;var is_server:bool=actor==server;var human:bool=not actor.is_ai
		var end_sign:float=-1.0 if actor.court_side==1 else 1.0
		var at:Vector3=actor.get_global_transform_interpolated().origin   # drawn position (smooth at 30 Hz physics)
		row.marker.global_position=Vector3(at.x,PickleballConstants.FLOOR_Y+.018,at.z)
		row.marker.visible=(human and you_cue) or (not human and is_server)
		var serving:int=int(is_server)
		if serving!=row.serving:   # text and colour change only when the server changes
			row.serving=serving;row.label.text=row.names[serving]
			if not human: row.material.albedo_color=Color("ffe49a") if is_server else Color("e8f4ff")
		row.label.visible=(human and you_cue) or (not human and (actor.team_id==0 or is_server))
		var feet:=Vector3(at.x,PickleballConstants.FLOOR_Y+.095,at.z+end_sign*.55)
		var above:bool=false
		if avoid and row.label.visible:
			var rect:Rect2=_tag_rect(camera,feet,row.half_w[serving])
			var margin:float=TAG_CLEAR_MARGIN if row.above else 0.0
			above=rect.size.x>0.0 and (rect.grow(margin).intersects(controls.stick_zone) or rect.grow(margin).intersects(controls.hit_zone))
		row.above=above
		row.label.global_position=Vector3(at.x,at.y+TAG_HEAD_HEIGHT,at.z) if above else feet

## Half the tag's width in metres (font metrics x pixel size), plus its outline.
static func _half_width(label:Label3D,text:String)->float:
	var font:Font=label.font if label.font!=null else ThemeDB.fallback_font
	return (font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x+label.outline_size*2.0)*label.pixel_size*0.5

## Screen rect of a billboard tag centred on `at` (empty when behind the camera).
static func _tag_rect(camera:Camera3D,at:Vector3,half_w:float)->Rect2:
	if camera.is_position_behind(at):return Rect2()
	var basis:Basis=camera.global_basis
	var center:Vector2=camera.unproject_position(at)
	var half_h:float=(TAG_FONT_SIZE*0.75+9.0)*TAG_PIXEL
	var ext:=Vector2((camera.unproject_position(at+basis.x*half_w)-center).length(),(camera.unproject_position(at+basis.y*half_h)-center).length())
	return Rect2(center-ext,ext*2.0)

## Debug (hud --ui-rects): drawn screen rects of the visible name tags.
func screen_rects()->Dictionary:
	var result:={}
	var camera:Camera3D=get_viewport().get_camera_3d()
	if camera==null or not visible:return result
	for row in rows:
		if row.label.visible:
			var rect:Rect2=_tag_rect(camera,row.label.global_position,row.half_w[max(row.serving,0)])
			if rect.size.x>0.0:result["tag_%s_%d%s"%[str(row.names[0]).replace(" ","_"),row.actor.get_actor_id(),"_up" if row.above else ""]]=rect
	return result
