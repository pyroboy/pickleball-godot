extends RefCounted
## Background people drawn like the players (visual only): pixel cards pinned to a simple
## skeleton, baked by tools/bake_crowd_cards.py from the same 3D-solid part builders as the
## player cards, but with 8 view directions instead of 16 and a coarser texel for distance.
##
## A person is a Dictionary (see `new_person`). `solve` turns its pose (arm presets, lean,
## head turn and nod, bounce, weight shift, walk phase) into joints in the world node's
## local space; `CardBatch` lays one camera-facing card per part on those joints, exactly
## like scripts/graphics/pixel_card_rig.gd (same anchors, limb stretch, mirroring and
## near/far draw bias), for every person in one dynamic mesh: one draw call.

## The crowd's own card shader: shaders/pixel_card.gdshader's atlas draw (hard alpha cut,
## unshaded, atlas pre-compensated, `gain`) plus the environment's distance fog
## (shaders/env_toon.gdshader `fog`): far out from the court lines the cards lean toward
## the same warm horizon colour as the buildings; the near crowd keeps full colour.
## Set per vertex: a card is small, its corners are all about as far out.
const CROWD_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_nearest;
uniform float gain = 1.0;
uniform vec3 fog_col : source_color = vec3(0.8, 0.66, 0.53);
uniform vec2 court_half = vec2(3.05, 6.705);
uniform vec3 fog = vec3(8.0, 0.02, 0.7);
varying float k;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float out_d = length(max(abs(wp.xz) - court_half, vec2(0.0)));
	k = fog.z * (1.0 - exp(-fog.y * max(out_d - fog.x, 0.0)));
}
void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) discard;
	ALBEDO = mix(c.rgb, fog_col, k) * gain;
}
"""
const META_PATH := "res://assets/crowd_cards/crowd_meta.json"
const ATLAS := preload("res://assets/crowd_cards/crowd_atlas.png")
const CARDS_PER_PERSON := 15
const HYSTERESIS_DEG := 6.0
const PART_BIAS := {"head": 0.02, "torso": 0.0, "shorts": -0.01, "upper_arm": 0.03, "forearm": 0.035,
	"hand": 0.04, "thigh": 0.012, "shin": 0.016, "shoe": 0.02}
const BIAS_BLEND := 0.04
const LIMB_OVERLAP := 1.04
const UPPER_ARM := 0.27
const FOREARM := 0.25
const THIGH := 0.42
const SHIN := 0.4

## Arm presets: [upper_dir, fore_dir] in the person's frame (x toward their +x side, y up,
## z forward), for the +x arm; the other arm mirrors x. A person's arm may also hold an
## Array [upper, fore] directly (walking swing, custom gestures).
const ARMS := {
	"idle_sit": [Vector3(0.15, -1.0, 0.35), Vector3(0.05, -0.25, 1.0)],
	"idle_stand": [Vector3(0.12, -1.0, 0.0), Vector3(0.05, -1.0, 0.18)],
	"knees": [Vector3(0.18, -0.8, 0.6), Vector3(0.05, -0.75, 0.7)],
	"clap_open": [Vector3(0.3, -0.45, 1.0), Vector3(-0.35, 0.25, 1.0)],
	"clap_shut": [Vector3(0.22, -0.45, 1.0), Vector3(-1.0, 0.25, 0.55)],
	"cheer_a": [Vector3(0.45, 1.0, 0.1), Vector3(0.15, 1.0, 0.0)],
	"cheer_b": [Vector3(0.6, 0.8, 0.15), Vector3(0.35, 1.0, 0.05)],
	"fist_up": [Vector3(0.3, 1.0, 0.1), Vector3(0.05, 1.0, 0.0)],
	"fist_mid": [Vector3(0.4, 0.2, 0.5), Vector3(0.1, 1.0, 0.2)],
	"hands_head": [Vector3(0.95, 0.75, 0.2), Vector3(-0.85, 0.45, -0.1)],
	"behind_head": [Vector3(0.8, 0.75, -0.25), Vector3(-0.85, 0.35, -0.3)],
	"facepalm": [Vector3(0.2, -0.2, 0.95), Vector3(-0.35, 0.95, 0.05)],
	"mouth": [Vector3(0.2, -0.3, 0.95), Vector3(-0.45, 0.9, 0.15)],
	"wince": [Vector3(0.3, -0.2, 0.9), Vector3(-0.55, 0.85, 0.2)],
	"lean_in": [Vector3(0.2, -0.85, 0.6), Vector3(0.0, -0.55, 0.85)],
	"stretch": [Vector3(0.2, 1.0, 0.0), Vector3(-0.3, 1.0, 0.0)],
	"counter": [Vector3(0.25, -0.35, 0.9), Vector3(-0.35, 0.0, 1.0)],
	"phone": [Vector3(0.15, -0.9, 0.45), Vector3(-0.25, 0.15, 1.0)],   # held low, at the chest
	"hold_paddle": [Vector3(0.12, -1.0, 0.3), Vector3(0.1, -0.2, 1.0)],
	"point": [Vector3(0.15, 0.25, 1.0), Vector3(0.05, 0.2, 1.0)],
	"reach_up": [Vector3(0.2, 0.6, 0.8), Vector3(0.1, 0.9, 0.5)],
	"wave_a": [Vector3(0.7, 0.7, 0.2), Vector3(0.1, 1.0, 0.1)],
	"wave_b": [Vector3(0.7, 0.7, 0.2), Vector3(0.55, 0.85, 0.1)],
	"arms_crossed": [Vector3(0.25, -0.9, 0.35), Vector3(-1.0, 0.15, 0.25)],
	"hands_hips": [Vector3(0.75, -0.65, -0.1), Vector3(-0.6, -0.6, 0.15)],
	"drink": [Vector3(0.2, -0.35, 0.9), Vector3(-0.35, 0.95, 0.15)],
	"fan_a": [Vector3(0.3, -0.3, 0.9), Vector3(-0.05, 0.95, 0.3)],
	"fan_b": [Vector3(0.3, -0.3, 0.9), Vector3(-0.45, 0.85, 0.3)],
	"shade": [Vector3(0.35, 0.35, 0.85), Vector3(-0.55, 0.45, 0.5)],
	"scratch": [Vector3(0.55, 0.85, 0.1), Vector3(-0.55, 0.6, -0.1)],
	"gesture_a": [Vector3(0.35, -0.6, 0.7), Vector3(0.1, 0.3, 1.0)],
	"gesture_b": [Vector3(0.45, -0.5, 0.7), Vector3(0.5, 0.4, 0.8)],
	"umbrella": [Vector3(0.25, -0.2, 0.6), Vector3(-0.1, 1.0, 0.2)],
	"carry_pole": [Vector3(0.5, 0.35, 0.15), Vector3(-0.05, 1.0, -0.05)],
	"carry_bag": [Vector3(0.18, -1.0, -0.05), Vector3(0.1, -1.0, 0.1)],
	"reach_down": [Vector3(0.15, -1.0, 0.45), Vector3(0.0, -1.0, 0.3)],
	"hold_ball": [Vector3(0.2, -0.8, 0.4), Vector3(0.0, 0.25, 1.0)],
	"windup": [Vector3(0.25, -0.8, -0.55), Vector3(0.1, -0.9, -0.4)],
	"release": [Vector3(0.15, 0.1, 1.0), Vector3(0.05, 0.7, 0.7)],
	"chin_rest": [Vector3(0.15, -0.6, 0.8), Vector3(-0.2, 0.95, 0.15)],
	"arm_on_knee": [Vector3(0.2, -0.75, 0.65), Vector3(0.0, -0.3, 1.0)],
	"hand_on_thigh": [Vector3(0.2, -0.95, 0.3), Vector3(0.0, -0.35, 1.0)],
	"pocket": [Vector3(0.2, -1.0, -0.1), Vector3(0.0, -1.0, 0.25)],
	"wave_small": [Vector3(0.35, -0.2, 0.6), Vector3(0.2, 1.0, 0.2)],
}


## Leg presets: [thigh_dir, shin_dir] in the person's frame for the +x leg (the other leg
## mirrors x). Seated thighs start at the seat; standing legs from the hips.
const LEGS := {
	"sit": [Vector3(0.05, -0.05, 1.0), Vector3(0.0, -1.0, 0.12)],
	"wide": [Vector3(0.45, -0.05, 0.9), Vector3(0.1, -1.0, 0.1)],
	"tucked": [Vector3(0.05, -0.05, 1.0), Vector3(0.0, -0.8, -0.6)],
	"cross_over": [Vector3(-0.35, 0.25, 0.9), Vector3(0.05, -1.0, 0.15)],
	"ankle_on_knee": [Vector3(0.6, 0.08, 0.8), Vector3(-1.0, 0.05, 0.1)],
	"knee_up": [Vector3(0.12, 0.8, 0.6), Vector3(0.0, -1.0, -0.25)],
	"stretch_out": [Vector3(0.08, -0.15, 1.0), Vector3(0.02, -0.5, 0.85)],
	"stand": [Vector3(0.0, -1.0, 0.02), Vector3(0.0, -1.0, -0.02)],
	"stand_wide": [Vector3(0.25, -1.0, 0.0), Vector3(0.12, -1.0, 0.0)],
	"stand_bent": [Vector3(0.05, -1.0, 0.18), Vector3(0.0, -1.0, -0.2)],
	"stand_cross": [Vector3(-0.14, -1.0, 0.05), Vector3(-0.1, -1.0, 0.0)],
}
## Postures: [right leg, left leg, extra hip push forward (m), lean].
const POSTURES := {
	"normal": ["sit", "sit", 0.0, 0.0],
	"wide": ["wide", "wide", 0.0, 0.0],
	"tucked": ["tucked", "tucked", 0.0, 0.06],
	"crossed": ["cross_over", "sit", 0.0, 0.0],
	"figure_four": ["ankle_on_knee", "sit", 0.0, -0.05],
	"knee_up": ["knee_up", "sit", 0.0, -0.06],
	"sprawl": ["stretch_out", "stretch_out", 0.1, -0.22],
	"stand": ["stand", "stand", 0.0, 0.0],
	"stand_wide": ["stand_wide", "stand_wide", 0.0, 0.0],
	"contrapposto": ["stand_bent", "stand", 0.0, 0.0],
	"cross_ankles": ["stand_cross", "stand", 0.0, 0.0],
}


static func new_person(pos: Vector3, yaw: float, seated: bool, profile: int, scale_f := 1.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "seated": seated, "seat_h": 0.44, "profile": profile, "s": scale_f,
		"lean": 0.0, "head_yaw": 0.0, "head_pitch": 0.0, "bounce": 0.0, "sway": 0.0, "walk": -1.0,
		"arm_l": "idle_sit" if seated else "idle_stand", "arm_r": "idle_sit" if seated else "idle_stand",
		"prop": "", "mode": "idle", "until": 0.0, "delay": 0.0, "then": "", "then_dur": 0.0,
		"next_idle": 0.0, "idle_kind": "", "idle_until": 0.0, "rate": 6.0, "watch": true, "visible": true,
		"cells": {}, "base_prop": 0, "posture": "normal" if seated else "stand", "trait": "calm"}


static func _arm(p: Dictionary, key: String, side: float) -> Array:
	var v = p[key]
	var pair: Array = v if v is Array else ARMS.get(v, ARMS.idle_stand)
	var u: Vector3 = pair[0]
	var f: Vector3 = pair[1]
	return [Vector3(u.x * side, u.y, u.z), Vector3(f.x * side, f.y, f.z)]


## Joints for a person (world-node local space). `ext`: the profile's baked extents.
static func solve(p: Dictionary, ext: Dictionary) -> Dictionary:
	var s: float = p.s
	var yaw: float = p.yaw
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side_axis := Vector3(cos(yaw), 0, -sin(yaw))
	var root := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.pos) + Vector3.UP * float(p.bounce) + side_axis * float(p.sway))
	var seated: bool = p.seated
	var walk: float = p.walk
	var hip_y: float = (float(p.seat_h) + 0.06) if seated else (THIGH + SHIN + 0.07) * s
	var j := {}
	j.fwd = fwd
	var posture: Array = POSTURES.get(p.posture, POSTURES.normal if seated else POSTURES.stand)
	if seated != (str(posture[0]) in ["sit", "wide", "tucked", "cross_over", "ankle_on_knee", "knee_up", "stretch_out"]):
		posture = POSTURES.normal if seated else POSTURES.stand
	var hip_push: float = posture[2]
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(side * 0.09 * s, hip_y, hip_push)
		var knee: Vector3
		var ankle: Vector3
		var leg: Array = LEGS[posture[0] if side > 0.0 else posture[1]]
		var td: Vector3 = leg[0]
		var sd: Vector3 = leg[1]
		td = Vector3(td.x * side, td.y, td.z).normalized()
		sd = Vector3(sd.x * side, sd.y, sd.z).normalized()
		if seated:
			knee = hip + td * THIGH * s
			ankle = knee + sd * SHIN * s
			if ankle.y < 0.07: ankle.y = 0.07
		elif walk < 0.0:
			knee = hip + td * THIGH * s
			ankle = knee + sd * SHIN * s
		elif walk >= 0.0:
			var ph := walk + (0.0 if side > 0.0 else PI)
			var swing := sin(ph)
			var thigh_dir := Vector3(0, -1, 0.55 * swing).normalized()
			knee = hip + thigh_dir * THIGH * s
			var bend := 0.75 * maxf(0.0, cos(ph))
			ankle = knee + Vector3(0, -1, 0.55 * swing - bend).normalized() * SHIN * s
		var tag := "l" if side < 0.0 else "r"
		j["hip_" + tag] = root * hip
		j["knee_" + tag] = root * knee
		j["ankle_" + tag] = root * ankle
	var pelvis := Vector3(0, hip_y, hip_push)
	var upper := root * Transform3D(Basis(Vector3.RIGHT, float(p.lean) + float(posture[3])), pelvis)
	var shorts: Array = ext.get("shorts", [0.15, -0.15, 0.15])
	var torso: Array = ext.get("torso", [0.2, -0.35, 0.2])
	var head: Array = ext.get("head", [0.15, -0.15, 0.15])
	var sc := s
	j.shorts = upper * Vector3(0, (0.08 - float(shorts[0]) + 0.03) * sc, 0)
	var torso_rel := (0.06 - float(torso[1])) * sc
	j.torso = upper * Vector3(0, torso_rel, 0)
	j.up = upper.basis.y
	var top := torso_rel + float(torso[0]) * sc
	var neck := Vector3(0, top - 0.03 * sc, 0)
	var head_xf := upper * Transform3D(Basis(Vector3.UP, float(p.head_yaw)) * Basis(Vector3.RIGHT, float(p.head_pitch)), neck)
	j.head = head_xf * Vector3(0, (-float(head[1]) - 0.04) * sc, 0)
	j.head_up = head_xf.basis.y
	j.head_fwd = head_xf.basis.z
	var shoulder_x := maxf(0.12, float(torso[2]) - 0.05) * sc
	for side: float in [-1.0, 1.0]:
		var arm := _arm(p, "arm_l" if side < 0.0 else "arm_r", side)
		var sh := Vector3(side * shoulder_x, top - 0.08 * sc, 0)
		var el: Vector3 = sh + (arm[0] as Vector3).normalized() * UPPER_ARM * s
		var wr: Vector3 = el + (arm[1] as Vector3).normalized() * FOREARM * s
		var tag := "l" if side < 0.0 else "r"
		j["sh_" + tag] = upper * sh
		j["el_" + tag] = upper * el
		j["wr_" + tag] = upper * wr
	return j


class CardBatch:
	var meta: Dictionary
	var mesh: ArrayMesh
	var instance: MeshInstance3D
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var count := 0
	var cell := Vector2.ZERO
	var tex := Vector2.ONE
	var cols := 8
	var texel := 0.05
	var parts: Dictionary = {}

	func _init(parent: Node3D, people_count: int) -> void:
		var f := FileAccess.open(META_PATH, FileAccess.READ)
		meta = JSON.parse_string(f.get_as_text())
		parts = meta.parts
		cell = Vector2(float(meta.cell[0]), float(meta.cell[1]))
		tex = Vector2(float(meta.atlas_px[0]), float(meta.atlas_px[1]))
		cols = int(meta.cols)
		texel = float(meta.meters_per_texel)
		count = people_count * CARDS_PER_PERSON
		verts.resize(count * 4)
		uvs.resize(count * 4)
		var idx := PackedInt32Array()
		idx.resize(count * 6)
		for i in count:
			var o := i * 4
			var t := i * 6
			idx[t] = o; idx[t + 1] = o + 1; idx[t + 2] = o + 2
			idx[t + 3] = o; idx[t + 4] = o + 2; idx[t + 5] = o + 3
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		mesh.custom_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 30, 160))
		var mat := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = CROWD_SHADER_CODE
		mat.shader = shader
		mat.set_shader_parameter("atlas", ATLAS)
		mat.set_shader_parameter("gain", float(meta.get("gain", 1.0)))
		instance = MeshInstance3D.new()
		instance.name = "CrowdCards"
		instance.mesh = mesh
		instance.material_override = mat
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)

	func extents(profile: int) -> Dictionary:
		return meta.profiles[profile % meta.profiles.size()].extents

	## View column for a facing direction, 45 degree steps with hysteresis.
	func _cell(p: Dictionary, key: String, fwd: Vector3, at: Vector3, cam: Vector3) -> int:
		var to_cam := cam - at
		to_cam.y = 0.0
		var f := Vector3(fwd.x, 0, fwd.z)
		var cells: Dictionary = p.cells
		if to_cam.length() < 0.001 or f.length() < 0.001: return int(cells.get(key, 0))
		var step := float(meta.view_deg)
		var rel := rad_to_deg(to_cam.normalized().signed_angle_to(f.normalized(), Vector3.UP))
		var cur := int(cells.get(key, -1))
		if cur >= 0 and absf(wrapf(rel - cur * step, -180.0, 180.0)) <= step * 0.5 + HYSTERESIS_DEG: return cur
		cur = posmod(roundi(rel / step), cols)
		cells[key] = cur
		return cur

	func write(i: int, p: Dictionary, j: Dictionary, cam: Vector3) -> void:
		var base := i * CARDS_PER_PERSON * 4
		if not p.visible:
			for v in CARDS_PER_PERSON * 4: verts[base + v] = Vector3(0, -40, 0)
			return
		var prof: Dictionary = meta.profiles[int(p.profile) % meta.profiles.size()]
		var block := Vector2(float(prof.block[0]), float(prof.block[1]))
		var s: float = texel * float(p.s)
		var body_cell := _cell(p, "body", j.fwd, j.torso, cam)
		var head_cell := _cell(p, "head", j.head_fwd, j.head, cam)
		var torso_pos: Vector3 = j.torso
		var c := 0
		# [part, a, b, prev, mirrored, facing up, cell, side root]
		var cards := [
			["head", j.head, null, null, false, j.head_up, head_cell, null],
			["torso", j.torso, null, null, false, j.up, body_cell, null],
			["shorts", j.shorts, null, null, false, Vector3.UP, body_cell, null]]
		for side in ["r", "l"]:
			var m: bool = side == "l"
			cards.append(["upper_arm", j["sh_" + side], j["el_" + side], null, m, null, body_cell, j["sh_" + side]])
			cards.append(["forearm", j["el_" + side], j["wr_" + side], null, m, null, body_cell, j["sh_" + side]])
			cards.append(["hand", j["wr_" + side], null, j["el_" + side], m, null, body_cell, j["sh_" + side]])
			cards.append(["thigh", j["hip_" + side], j["knee_" + side], null, m, null, body_cell, j["hip_" + side]])
			cards.append(["shin", j["knee_" + side], j["ankle_" + side], null, m, null, body_cell, j["hip_" + side]])
			cards.append(["shoe", j["ankle_" + side], null, null, m, Vector3.UP, body_cell, j["hip_" + side]])
		for card in cards:
			var part: String = card[0]
			var info: Dictionary = parts[part]
			var anchor := Vector2(float(info.anchor[0]), float(info.anchor[1]))
			var limb: bool = info.has("end") and card[2] != null
			var a: Vector3 = card[1]
			var b: Vector3
			if limb: b = card[2]
			elif card[3] != null: b = a + (a - (card[3] as Vector3)).normalized() * 0.06
			else: b = a
			var mid := (a + b) * 0.5
			var z := (cam - mid).normalized()
			var up_dir: Vector3
			var sy := s
			if limb or card[3] != null:
				var d := b - a
				var dp := d - z * d.dot(z)
				var texel_len := maxf(float(info.end[1]) - anchor.y, 1.0) if limb else 1.2
				if dp.length() < 0.0001: dp = -(Vector3.UP - z * z.y)
				up_dir = -dp.normalized()
				if limb: sy = dp.length() / texel_len
			else:
				var hint: Vector3 = card[5]
				up_dir = (hint - z * hint.dot(z)).normalized()
			var x := up_dir.cross(z).normalized()
			var k: int = card[6]
			if card[4]:
				x = -x
				k = (cols - k) % cols
			var origin := a + z * (mid - a).dot(z)
			var bias: float = float(PART_BIAS.get(part, 0.0))
			if card[7] != null:
				bias *= clampf(((card[7] as Vector3) - torso_pos).dot(z) / BIAS_BLEND, -1.0, 1.0)
			origin += z * bias
			var ys := sy * (LIMB_OVERLAP if limb else 1.0)
			var x0 := -anchor.x * s
			var x1 := (cell.x - anchor.x) * s
			var y0 := -anchor.y * ys
			var y1 := (cell.y - anchor.y) * ys
			var v := base + c * 4
			verts[v] = origin + x * x0 - up_dir * y0
			verts[v + 1] = origin + x * x1 - up_dir * y0
			verts[v + 2] = origin + x * x1 - up_dir * y1
			verts[v + 3] = origin + x * x0 - up_dir * y1
			var u0 := (block.x + k) * cell.x / tex.x
			var u1 := (block.x + k + 1.0) * cell.x / tex.x
			var v0 := (block.y + float(info.row)) * cell.y / tex.y
			var v1 := (block.y + float(info.row) + 1.0) * cell.y / tex.y
			uvs[v] = Vector2(u0, v0)
			uvs[v + 1] = Vector2(u1, v0)
			uvs[v + 2] = Vector2(u1, v1)
			uvs[v + 3] = Vector2(u0, v1)
			c += 1

	func commit() -> void:
		mesh.surface_update_vertex_region(0, 0, verts.to_byte_array())
		mesh.surface_update_attribute_region(0, 0, uvs.to_byte_array())
