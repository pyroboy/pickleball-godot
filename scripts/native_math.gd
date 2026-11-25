class_name NativeMath extends RefCounted
## The native (C++) library of hot maths, when it is in this build (native/, GDExtension class
## PickleNative; docs/PERFORMANCE_PLAN.md step 8). Each native function is a port of a GDScript
## function that stays as the reference and the fallback: callers ask lib() and use their own
## script path when it returns null (library missing, or PerfToggles.native_math off).
static var _checked := false
static var _lib = null

static func lib():
	if not PerfToggles.native_math: return null
	if not _checked:
		_checked = true
		if ClassDB.class_exists(&"PickleNative"): _lib = ClassDB.instantiate(&"PickleNative")
	return _lib

static func available() -> bool:
	return lib() != null
