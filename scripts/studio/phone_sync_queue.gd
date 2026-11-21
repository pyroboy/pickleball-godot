extends RefCounted
## Phone Pose Studio -> Mac. Every phone save, note and star rating is one small JSON file in
## user://pose_studio_queue (the app's Documents folder). tools/phone_sync.sh on the Mac pulls that
## folder (xcrun devicectl), applies the entries oldest first with tools/pose_notes.py (as the
## desktop studio's Save, Add note and Rate do), then pushes back:
##   user://pose_studio_queue/synced.json   {"ids": [...]}: applied entries (deleted here on read)
##   user://pose_studio_sync/notes.json     {key: [note]}: the repo's notes (replies included)
##   user://pose_studio_sync/ratings.json   {key: {stars, version, stale}}: latest rating per pose
##   user://pose_studio_sync/versions.json  {key: [{n, author, message, time}]}: version history
## Entry: {id, kind: "save" | "note" | "rate", time, source: "phone", key, ...}
##   save: changes [{stage, field, text}] (Pose Studio diff rows), message
##   note: text, stage, time_on_timeline        rate: stars (1..5)

const DIR := "user://pose_studio_queue"
const SYNCED := "user://pose_studio_queue/synced.json"
const PULLED := "user://pose_studio_sync"
## Fields of synced phone saves, {key: {"stage.field": text}}: once the installed build has them,
## the pose's on-device override is dropped (cleanup_overrides), so later desktop edits show.
const SYNCED_FIELDS := "user://pose_studio_queue/synced_fields.json"
static var _seq := 0

static func enqueue(kind: String, payload: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_seq = (_seq + 1) % 1000
	var id := "%d_%03d_%s" % [int(Time.get_unix_time_from_system() * 1000.0), _seq, kind]
	var rec: Dictionary = payload.duplicate(true)
	rec["id"] = id
	rec["kind"] = kind
	rec["time"] = Time.get_datetime_string_from_system(false, true)
	rec["source"] = "phone"
	var f := FileAccess.open(DIR.path_join(id + ".json"), FileAccess.WRITE)
	if f == null: return ""
	f.store_string(JSON.stringify(rec))
	f.close()
	return id

## Entries the Mac has not applied yet, oldest first (applied ones are deleted here).
static func pending() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null: return out
	var synced := _synced()
	var names := Array(d.get_files())
	names.sort()
	for n in names:
		if not String(n).ends_with(".json") or String(n).begins_with("synced"): continue   # synced.json, synced_fields.json
		var id := String(n).trim_suffix(".json")
		if synced.has(id):
			_log_synced(JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(n))))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(n)))
			continue
		var rec = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(n)))
		if rec is Dictionary: out.append(rec)
	return out

static func pending_for(key: String, kind: String = "") -> Array:
	return pending().filter(func(r): return r.get("key") == key and (kind == "" or r.get("kind") == kind))

static func _synced() -> Dictionary:
	var out := {}
	var doc = _json(SYNCED)
	if doc is Dictionary:
		for id in doc.get("ids", []): out[str(id)] = true
	return out

static func _json(path: String):
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Notes for a pose: the repo's (as of the last sync), then the ones still on the phone.
static func notes_for(key: String) -> Array:
	var out: Array = []
	var doc = _json(PULLED.path_join("notes.json"))
	if doc is Dictionary:
		for n in doc.get(key, []): if n is Dictionary: out.append(n)
	for r in pending_for(key, "note"):
		out.append({"text": r.get("text", ""), "stage": r.get("stage", ""), "time": r.get("time_on_timeline"), "status": "on phone", "author": "user"})
	return out

## Stars shown for a pose: the latest phone rating not synced yet, else the repo's.
static func stars_for(key: String) -> int:
	var mine := pending_for(key, "rate")
	if not mine.is_empty(): return int(mine[-1].get("stars", 0))
	var doc = _json(PULLED.path_join("ratings.json"))
	if doc is Dictionary and doc.get(key) is Dictionary and not bool(doc[key].get("stale", false)): return int(doc[key].get("stars", 0))
	return 0

static func versions_for(key: String) -> Array:
	var doc = _json(PULLED.path_join("versions.json"))
	return doc.get(key, []) if doc is Dictionary else []

static func _log_synced(rec) -> void:
	if not (rec is Dictionary) or rec.get("kind") != "save": return
	var log = _json(SYNCED_FIELDS)
	if not (log is Dictionary): log = {}
	var k := String(rec.get("key", ""))
	var fields: Dictionary = log.get(k, {})
	for c in rec.get("changes", []): fields["%s.%s" % [c.get("stage", ""), c.get("field", "")]] = c.get("text", "")
	log[k] = fields
	_write(SYNCED_FIELDS, log)

static func _write(path: String, obj) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(obj)); f.close()

## Phone studio start: drop the on-device override of each pose whose synced phone edits are all
## in the installed build (and that has no save still waiting), so the build's pose shows, later
## desktop edits included. A pose whose phone edits the build lacks keeps its override.
static func cleanup_overrides() -> Array:
	var PoseDiff = load("res://scripts/studio/pose_diff_util.gd")
	var Store = load("res://scripts/mobile_pose_store.gd")
	pending()   # logs entries the Mac has applied
	var log = _json(SYNCED_FIELDS)
	if not (log is Dictionary) or log.is_empty(): return []
	var waiting := {}
	for r in pending(): if r.get("kind") == "save": waiting[r.get("key")] = true
	var dropped: Array = []
	for k in log.keys():
		if waiting.has(k): continue
		var live: Resource = PoseDiff.live_def(k)
		var packaged: Resource = PoseDiff.load_disk(k) if not PoseDiff.is_action_key(k) else ResourceLoader.load(PoseDiff.BallActions.FILES[int(k.substr(1))], "", ResourceLoader.CACHE_MODE_IGNORE)
		if live == null or packaged == null: continue
		var cmp: Resource = live.duplicate(true)
		if not (cmp is BasePoseDefinition): PoseDiff.PaddleRotation.normalize_pose(cmp)
		var differs := {}
		for row in PoseDiff.diff(cmp, packaged, k.begins_with("b")): differs["%s.%s" % [row.stage, row.field]] = true
		var contained := true
		for f in (log[k] as Dictionary).keys(): if differs.has(f): contained = false
		if not contained: continue
		if PoseDiff.is_action_key(k): PoseDiff.BallActions.drop_override(int(k.substr(1)))
		elif PoseDiff.is_serve_key(k):
			PoseDiff.ServeStore.reset(live)
			PoseDiff.ServeStore.copy_values(PoseDiff.ServeStore.packaged_default(int(k.substr(1))), live)
		else:
			Store.reset(live)
			Store.copy_values(ResourceLoader.load(live.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE), live)
		log.erase(k)
		dropped.append(k)
	_write(SYNCED_FIELDS, log)
	return dropped
