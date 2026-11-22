extends RefCounted
## Low-poly 3D figures for the environment (visual only): people, chickens, a dog.
## Every body part is one instance of a unit cube in a single MultiMesh (one draw call
## for every figure), coloured per instance and shaded by shaders/env_toon.gdshader.
## Poses are direction vectors per limb in the figure's own frame (x right, y up,
## z forward = facing), solved into part transforms here.

const PERSON_PARTS := 16
const CHICKEN_PARTS := 9
const DOG_PARTS := 10

# person part slots
enum {HIPS, TORSO, HEAD, HAIR, HAIR2, UA_L, FA_L, UA_R, FA_R, TH_L, SH_L, TH_R, SH_R, FOOT_L, FOOT_R, PROP}

static var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))


## Basis whose Y axis points along `dir` (for limbs), size applied after.
static func _along(dir: Vector3, size: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x * size.x, y * size.y, z * size.z)


static func _limb(root: Transform3D, a: Vector3, dir: Vector3, length: float, thick: float) -> Transform3D:
	var d := dir.normalized()
	return root * Transform3D(_along(d, Vector3(thick, length, thick)), a + d * length * 0.5)


## Arm/leg presets: [upper_dir, fore_dir] in the figure frame, for the RIGHT side; the
## left side mirrors x. Seated legs are handled separately.
const ARMS := {
	"idle_sit": [Vector3(0.15, -1.0, 0.35), Vector3(0.05, -0.25, 1.0)],
	"idle_stand": [Vector3(0.12, -1.0, 0.0), Vector3(0.05, -1.0, 0.18)],
	"clap_open": [Vector3(0.3, -0.45, 1.0), Vector3(-0.35, 0.25, 1.0)],
	"clap_shut": [Vector3(0.22, -0.45, 1.0), Vector3(-1.0, 0.25, 0.55)],
	"cheer_a": [Vector3(0.45, 1.0, 0.1), Vector3(0.15, 1.0, 0.0)],
	"cheer_b": [Vector3(0.6, 0.8, 0.15), Vector3(0.35, 1.0, 0.05)],
	"hands_head": [Vector3(0.95, 0.75, 0.2), Vector3(-0.85, 0.45, -0.1)],
	"wince": [Vector3(0.3, -0.2, 0.9), Vector3(-0.55, 0.85, 0.2)],
	"lean_in": [Vector3(0.2, -0.85, 0.6), Vector3(0.0, -0.55, 0.85)],
	"stretch": [Vector3(0.2, 1.0, 0.0), Vector3(-0.3, 1.0, 0.0)],
	"counter": [Vector3(0.25, -0.35, 0.9), Vector3(-0.35, 0.0, 1.0)],
	"phone": [Vector3(0.15, -0.85, 0.5), Vector3(-0.25, 0.55, 1.0)],
	"hold_paddle": [Vector3(0.12, -1.0, 0.3), Vector3(0.1, -0.2, 1.0)],
	"point": [Vector3(0.15, 0.25, 1.0), Vector3(0.05, 0.2, 1.0)],
	"reach_up": [Vector3(0.2, 0.6, 0.8), Vector3(0.1, 0.9, 0.5)],
	"wave": [Vector3(0.7, 0.7, 0.2), Vector3(0.1, 1.0, 0.1)],
}


static func new_person(pos: Vector3, yaw: float, seated: bool, colors: Dictionary, style: int, scale_f := 1.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "seated": seated, "seat_h": 0.44, "c": colors, "style": style, "s": scale_f,
		"lean": 0.0, "head_yaw": 0.0, "head_pitch": 0.0, "bounce": 0.0, "arm_r": "idle_sit" if seated else "idle_stand",
		"arm_l": "idle_sit" if seated else "idle_stand", "prop": "", "mode": "idle", "until": 0.0, "delay": 0.0,
		"next_idle": 0.0, "idle_kind": "", "base": 0, "rate": 6.0, "watch": true}


## Writes the person's 16 parts into `mm` from `p.base`.
static func pose_person(mm: MultiMesh, p: Dictionary) -> void:
	var s: float = p.s
	var root := Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(p.pos) + Vector3(0, float(p.bounce), 0))
	var b: int = p.base
	var seated: bool = p.seated
	var hip_y: float = (float(p.seat_h) + 0.05) if seated else 0.84 * s
	var pelvis := Vector3(0, hip_y, 0)
	# legs
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(side * 0.09 * s, hip_y, 0)
		var th := TH_L if side < 0.0 else TH_R
		var sh := SH_L if side < 0.0 else SH_R
		var ft := FOOT_L if side < 0.0 else FOOT_R
		var knee: Vector3
		var ankle: Vector3
		if seated:
			knee = hip + Vector3(side * 0.02, -0.02, 0.4 * s)
			ankle = Vector3(knee.x, 0.06, knee.z + 0.04)
		else:
			knee = hip + Vector3(0, -0.42 * s, 0.02)
			ankle = Vector3(hip.x, 0.06, 0.0)
		mm.set_instance_transform(b + th, _limb(root, hip, knee - hip, (knee - hip).length(), 0.12 * s))
		mm.set_instance_transform(b + sh, _limb(root, knee, ankle - knee, (ankle - knee).length(), 0.1 * s))
		mm.set_instance_transform(b + ft, root * Transform3D(Basis.from_scale(Vector3(0.1, 0.06, 0.22) * s), ankle + Vector3(0, -0.03, 0.05)))
	mm.set_instance_transform(b + HIPS, root * Transform3D(Basis.from_scale(Vector3(0.32, 0.16, 0.21) * s), pelvis + Vector3(0, 0.04, 0)))
	# upper body leans about the pelvis
	var upper := root * Transform3D(Basis(Vector3.RIGHT, float(p.lean)), pelvis)
	mm.set_instance_transform(b + TORSO, upper * Transform3D(Basis.from_scale(Vector3(0.36, 0.46, 0.21) * s), Vector3(0, 0.33 * s, 0)))
	var head := upper * Transform3D(Basis(Vector3.UP, float(p.head_yaw)) * Basis(Vector3.RIGHT, float(p.head_pitch)), Vector3(0, 0.69 * s, 0))
	mm.set_instance_transform(b + HEAD, head * Transform3D(Basis.from_scale(Vector3(0.2, 0.22, 0.2) * s), Vector3(0, 0.11 * s, 0)))
	var style: int = p.style
	match style:
		0:   # short hair
			mm.set_instance_transform(b + HAIR, head * Transform3D(Basis.from_scale(Vector3(0.22, 0.07, 0.22) * s), Vector3(0, 0.22 * s, -0.01)))
			mm.set_instance_transform(b + HAIR2, head * Transform3D(Basis.from_scale(Vector3(0.22, 0.12, 0.05) * s), Vector3(0, 0.16 * s, -0.095 * s)))
		1:   # long hair
			mm.set_instance_transform(b + HAIR, head * Transform3D(Basis.from_scale(Vector3(0.23, 0.07, 0.23) * s), Vector3(0, 0.22 * s, -0.01)))
			mm.set_instance_transform(b + HAIR2, head * Transform3D(Basis.from_scale(Vector3(0.23, 0.3, 0.06) * s), Vector3(0, 0.08 * s, -0.1 * s)))
		2:   # cap with a brim
			mm.set_instance_transform(b + HAIR, head * Transform3D(Basis.from_scale(Vector3(0.22, 0.08, 0.22) * s), Vector3(0, 0.23 * s, 0)))
			mm.set_instance_transform(b + HAIR2, head * Transform3D(Basis.from_scale(Vector3(0.18, 0.025, 0.12) * s), Vector3(0, 0.2 * s, 0.14 * s)))
		_:   # bald / buzz
			mm.set_instance_transform(b + HAIR, head * Transform3D(Basis.from_scale(Vector3(0.21, 0.03, 0.21) * s), Vector3(0, 0.215 * s, 0)))
			mm.set_instance_transform(b + HAIR2, _hidden)
	# arms
	var hand_r := Vector3.ZERO
	for side: float in [-1.0, 1.0]:
		var preset: Array = ARMS.get(p.arm_l if side < 0.0 else p.arm_r, ARMS.idle_stand)
		var u: Vector3 = preset[0]
		var f: Vector3 = preset[1]
		u.x *= side
		f.x *= side
		var shoulder := Vector3(side * 0.225 * s, 0.53 * s, 0)
		var elbow := shoulder + u.normalized() * 0.27 * s
		mm.set_instance_transform(b + (UA_L if side < 0.0 else UA_R), _limb(upper, shoulder, u, 0.27 * s, 0.085 * s))
		mm.set_instance_transform(b + (FA_L if side < 0.0 else FA_R), _limb(upper, elbow, f, 0.27 * s, 0.08 * s))
		if side > 0.0: hand_r = elbow + f.normalized() * 0.27 * s
	if p.prop == "paddle":
		mm.set_instance_transform(b + PROP, upper * Transform3D(Basis.from_scale(Vector3(0.2, 0.26, 0.03) * s), hand_r + Vector3(0, 0.1 * s, 0.05)))
	else:
		mm.set_instance_transform(b + PROP, _hidden)


static func color_person(mm: MultiMesh, p: Dictionary) -> void:
	var c: Dictionary = p.c
	var b: int = p.base
	var map := {HIPS: c.shorts, TORSO: c.shirt, HEAD: c.skin, HAIR: c.hair, HAIR2: c.hair, UA_L: c.skin, FA_L: c.skin,
		UA_R: c.skin, FA_R: c.skin, TH_L: c.shorts, SH_L: c.skin, TH_R: c.shorts, SH_R: c.skin, FOOT_L: c.feet,
		FOOT_R: c.feet, PROP: c.get("prop", c.shirt)}
	if int(p.style) == 2:
		map[HAIR] = c.cap
		map[HAIR2] = c.cap
	for k in map: mm.set_instance_color(b + k, map[k])


# ---------------------------------------------------------------- chickens

static func new_chicken(pos: Vector3, colors: Dictionary) -> Dictionary:
	return {"pos": pos, "yaw": 0.0, "c": colors, "base": 0, "mode": "peck", "next": 0.0, "target": pos,
		"home": pos, "step": 0, "head_down": false, "flap": false}


static func pose_chicken(mm: MultiMesh, k: Dictionary) -> void:
	var root := Transform3D(Basis(Vector3.UP, float(k.yaw)), Vector3(k.pos))
	var b: int = k.base
	var down: bool = k.head_down
	var step: int = k.step
	mm.set_instance_transform(b + 0, root * Transform3D(Basis.from_scale(Vector3(0.2, 0.18, 0.3)), Vector3(0, 0.24, 0)))
	mm.set_instance_transform(b + 1, root * Transform3D(Basis(Vector3.RIGHT, 0.6) * Basis.from_scale(Vector3(0.14, 0.16, 0.08)), Vector3(0, 0.33, -0.15)))
	var head_pos := Vector3(0, 0.2, 0.2) if down else Vector3(0, 0.4, 0.15)
	mm.set_instance_transform(b + 2, root * Transform3D(Basis.from_scale(Vector3(0.1, 0.11, 0.11)), head_pos))
	mm.set_instance_transform(b + 3, root * Transform3D(Basis.from_scale(Vector3(0.03, 0.05, 0.07)), head_pos + Vector3(0, 0.07, 0)))
	mm.set_instance_transform(b + 4, root * Transform3D(Basis.from_scale(Vector3(0.04, 0.03, 0.05)), head_pos + Vector3(0, -0.01, 0.07)))
	for side: float in [-1.0, 1.0]:
		var lift := 0.04 if (step % 2 == 0) == (side > 0.0) and k.mode == "walk" else 0.0
		mm.set_instance_transform(b + (5 if side < 0.0 else 6), root * Transform3D(Basis.from_scale(Vector3(0.025, 0.16, 0.025)), Vector3(side * 0.05, 0.08 + lift, 0)))
		var wing := Basis(Vector3.FORWARD, side * (1.1 if k.flap and step % 2 == 0 else 0.15))
		mm.set_instance_transform(b + (7 if side < 0.0 else 8), root * Transform3D(wing * Basis.from_scale(Vector3(0.03, 0.13, 0.22)), Vector3(side * 0.11, 0.26, 0)))


static func color_chicken(mm: MultiMesh, k: Dictionary) -> void:
	var c: Dictionary = k.c
	var b: int = k.base
	var cols := [c.body, c.tail, c.body, c.comb, c.beak, c.beak, c.beak, c.wing, c.wing]
	for i in CHICKEN_PARTS: mm.set_instance_color(b + i, cols[i])


# ---------------------------------------------------------------- dog

static func new_dog(pos: Vector3, colors: Dictionary) -> Dictionary:
	return {"pos": pos, "yaw": 0.0, "c": colors, "base": 0, "mode": "sleep", "next": 6.0, "until": 0.0, "step": 0, "home": pos}


static func pose_dog(mm: MultiMesh, d: Dictionary) -> void:
	var root := Transform3D(Basis(Vector3.UP, float(d.yaw)), Vector3(d.pos))
	var b: int = d.base
	var mode: String = d.mode
	var lying := mode == "sleep"
	var step: int = d.step
	var body_y := 0.16 if lying else 0.4
	var head_up := mode == "bark" and step % 2 == 0
	mm.set_instance_transform(b + 0, root * Transform3D(Basis.from_scale(Vector3(0.26, 0.24, 0.62)), Vector3(0, body_y, 0)))
	var head := Vector3(0, body_y + (0.0 if lying else (0.24 if head_up else 0.16)), 0.4)
	mm.set_instance_transform(b + 1, root * Transform3D(Basis.from_scale(Vector3(0.2, 0.2, 0.2)), head))
	mm.set_instance_transform(b + 2, root * Transform3D(Basis.from_scale(Vector3(0.11, 0.09, 0.14)), head + Vector3(0, -0.04, 0.15)))
	for side: float in [-1.0, 1.0]:
		mm.set_instance_transform(b + (3 if side < 0.0 else 4), root * Transform3D(Basis.from_scale(Vector3(0.06, 0.12, 0.05)), head + Vector3(side * 0.08, 0.13 if not lying else 0.06, -0.03)))
	var wag := 0.6 * sin(float(step) * 2.2) if mode != "sleep" else 0.0
	mm.set_instance_transform(b + 5, root * Transform3D(Basis(Vector3.UP, wag) * Basis(Vector3.RIGHT, -0.9) * Basis.from_scale(Vector3(0.05, 0.26, 0.05)), Vector3(0, body_y + 0.12, -0.36)))
	var i := 6
	for z: float in [0.22, -0.22]:
		for side: float in [-1.0, 1.0]:
			if lying:
				mm.set_instance_transform(b + i, root * Transform3D(Basis.from_scale(Vector3(0.07, 0.06, 0.2)), Vector3(side * 0.1, 0.04, z + 0.12)))
			else:
				var swing := 0.35 * sin(float(step) * 1.6 + (PI if (side > 0.0) == (z > 0.0) else 0.0)) if mode == "walk" else 0.0
				mm.set_instance_transform(b + i, root * Transform3D(Basis(Vector3.RIGHT, swing) * Basis.from_scale(Vector3(0.07, 0.3, 0.07)), Vector3(side * 0.09, 0.15, z)))
			i += 1


static func color_dog(mm: MultiMesh, d: Dictionary) -> void:
	var c: Dictionary = d.c
	var b: int = d.base
	var cols := [c.body, c.body, c.snout, c.ear, c.ear, c.body, c.leg, c.leg, c.leg, c.leg]
	for i in DOG_PARTS: mm.set_instance_color(b + i, cols[i])
