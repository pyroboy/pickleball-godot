@tool
extends EditorScript

## One-shot migration: snapshot PostureLibrary defaults to res://data/postures/*.tres.
##
## HOW TO RUN (Godot editor only):
##   1. Open the project in Godot 4.6.
##   2. Open this script in the script editor.
##   3. Menu: File → Run (Ctrl+Shift+X).
##   4. Check the Output panel — one line per .tres written.
##
## Re-running is safe: it overwrites existing files with current defaults.
## If you want to keep hand-tuned edits, back them up first (or use git).
##
## After running, PostureLibrary.load_or_default() will load from disk instead
## of rebuilding in code. Byte-identical either way because _build_defaults()
## and the .tres files encode the same numbers.

const PostureDefinitionScript := preload("res://scripts/posture_definition.gd")
const PostureLibraryScript := preload("res://scripts/posture_library.gd")

const OUTPUT_DIR := "res://data/postures/"


func _run() -> void:
	print("[extract_postures] starting")
	_ensure_dir(OUTPUT_DIR)

	var lib = PostureLibraryScript.new()
	# Force a fresh rebuild from in-code defaults, ignoring any existing .tres on disk.
	# (lib._init already populated `definitions` — clear it first to avoid duplicates.)
	lib.definitions.clear()
	lib._build_defaults()

	var written := 0
	for d in lib.definitions:
		var filename := _filename_for(d)
		var path := OUTPUT_DIR + filename
		var err := ResourceSaver.save(d, path)
		if err == OK:
			print("  wrote %s  (id=%d, %s)" % [filename, d.posture_id, d.display_name])
			written += 1
		else:
			push_warning("  FAILED to save %s — error %d" % [path, err])

	print("[extract_postures] done. %d files written to %s" % [written, OUTPUT_DIR])


func _ensure_dir(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)
		print("  created directory: " + path)


func _filename_for(d: PostureDefinition) -> String:
	# e.g. "Low Wide Forehand" -> "05_low_wide_forehand.tres"
	# Prefix with zero-padded posture_id so directory listing stays in enum order.
	var base: String = d.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [d.posture_id, base]
