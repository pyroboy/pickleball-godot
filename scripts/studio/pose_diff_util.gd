extends RefCounted
## Pose Studio diff helpers (static; shared by scripts/studio/pose_studio.gd and
## scripts/debug/pose_studio_link.gd). Working copy vs a fresh disk load of the pose file,
## one row per changed field: {stage, field, text}, stage = the FILE SECTION the value
## lives in (windup = windup_body dict, finish = follow_through_body dict, contact = the
## main resource incl. charge_* / ft_* deltas), text = value_text(value) (var_to_str, floats rounded).
## Keyframe freezing (a contact edit copies the old value into both keyframe dicts) shows
## up as windup / finish rows, which is what the file must receive.
## Usage: PoseDiff.diff(ed._current, PoseDiff.load_disk(key), ed._base)

const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
const KEYFRAMES := [["windup", "windup_body"], ["finish", "follow_through_body"]]
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
## Serves (v00..v06) are code-built and tuned by this file, not a .tres.
const SERVE_TUNING := "data/serve_tuning.json"

static func is_serve_key(key: String) -> bool:
	return key.begins_with("v")

static func key_of(def: Resource) -> String:
	if def is BasePoseDefinition: return "b%02d" % def.base_pose_id
	if ServeStore.is_serve(def): return "v%02d" % ServeStore.style_id(def)
	return "s%02d" % def.posture_id

## Mobile editor working-copy key ("stroke:13" / "base:4") for a pose key.
static func copy_key(key: String) -> String:
	if is_serve_key(key): return "serve:" + str(int(key.substr(1)))
	return ("base:" if key.begins_with("b") else "stroke:") + str(int(key.substr(1)))

## The library resource the game holds for s13 / b04, or null.
static func live_def(key: String) -> Resource:
	if key.length() < 2 or not key.substr(1).is_valid_int(): return null
	var id := int(key.substr(1))
	if key.begins_with("s"): return PostureLibrary.instance().get_def(id)
	if key.begins_with("b"): return BasePoseLibrary.instance().get_def(id)
	if is_serve_key(key): return ServeStore.get_def(id)
	return null

static func file_of(key: String) -> String:
	if is_serve_key(key): return SERVE_TUNING
	var live := live_def(key)
	return live.resource_path.trim_prefix("res://") if live else ""

## Fresh copy of the pose file (resource cache ignored), normalized like the editor's copy.
static func load_disk(key: String) -> Resource:
	if is_serve_key(key):   # the code-built serve + the tuning file as it is now (+ grip, as the live one)
		if live_def(key) == null: return null
		ServeStore._tuning = null
		var d: Resource = ServeStore.packaged_default(int(key.substr(1)))
		if d != null:
			GripStore.apply_to_definition(d)
			PaddleRotation.normalize_pose(d)
		return d
	var live := live_def(key)
	if live == null or live.resource_path == "": return null
	var r: Resource = ResourceLoader.load(live.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if r != null and key.begins_with("s"): PaddleRotation.normalize_pose(r)  # same as _select_pose's copy
	return r

static func storage_props(r: Resource) -> Array:
	var out: Array = []
	for p in r.get_property_list():
		var n: String = p.name
		if not (p.usage & PROPERTY_USAGE_STORAGE): continue
		if n == "script" or n.begins_with("resource_") or n.begins_with("metadata/"): continue
		out.append(n)
	return out

## Shortest decimal (up to 9 places) that reads back within 1e-9: an edit to 0.104 is written
## "0.104", not var_to_str's "0.10400000000000001". Floats keep a ".0" so dict values stay float.
## f32: a Vector component (32-bit); the text must read back to exactly that 32-bit value.
static func float_text(x: float, f32 := false) -> String:
	if is_nan(x) or is_inf(x): return var_to_str(x)
	for d in range(0, 10):
		var s := String.num(x, d)
		var ok: bool = Vector2(s.to_float(), 0.0).x == x if f32 else absf(s.to_float() - x) <= 1e-9 * maxf(1.0, absf(x))
		if ok:
			if not ("." in s or "e" in s): s += ".0"
			return s
	return var_to_str(x)

static func value_text(v) -> String:
	if v is float: return float_text(v)
	if v is Vector3: return "Vector3(%s, %s, %s)" % [float_text(v.x, true), float_text(v.y, true), float_text(v.z, true)]
	if v is Vector2: return "Vector2(%s, %s)" % [float_text(v.x, true), float_text(v.y, true)]
	return var_to_str(v)

## [{stage, field, text}] (plus {text: null, removed: true} for a keyframe key missing
## from the working copy). base = body stance (no keyframe sections).
static func diff(cur: Resource, disk: Resource, base: bool) -> Array:
	var changes: Array = []
	if cur == null or disk == null: return changes
	for n in storage_props(cur):
		if n in ["windup_body", "follow_through_body"]: continue
		var a = cur.get(n)
		if a is Resource: continue
		if a != disk.get(n): changes.append({"stage": "contact", "field": n, "text": value_text(a)})
	if not base:
		for pair in KEYFRAMES:
			var kw: Resource = cur.get(pair[1])
			var kd: Resource = disk.get(pair[1])
			var wv: Dictionary = kw.values if kw else {}
			var dv: Dictionary = kd.values if kd else {}
			for f in wv:
				if not dv.has(f) or wv[f] != dv[f]:
					changes.append({"stage": pair[0], "field": str(f), "text": value_text(wv[f])})
			for f in dv:
				if not wv.has(f): changes.append({"stage": pair[0], "field": str(f), "text": null, "removed": true})
	return changes

## Copy the file on disk into the live library resource (same identity the game holds).
## Returns false if the key or file is unknown. Callers drop the editor's working copy.
static func reload_live(key: String) -> bool:
	if is_serve_key(key):   # rebuilt from the tuning file on the next get_def
		if live_def(key) == null: return false
		ServeStore._tuning = null
		ServeStore._live.erase(int(key.substr(1)))
		return true
	var live := live_def(key)
	if live == null: return false
	var fresh: Resource = ResourceLoader.load(live.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null: return false
	for n in storage_props(fresh):
		var v = fresh.get(n)
		live.set(n, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	return true
