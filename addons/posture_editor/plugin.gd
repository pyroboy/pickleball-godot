@tool
extends EditorPlugin

const PostureEditorDock = preload("res://addons/posture_editor/posture_editor_dock.gd")
const PostureGizmoPlugin = preload("res://addons/posture_editor/posture_gizmo_plugin.gd")

var _dock: Control
var _gizmo_plugin: EditorNode3DGizmoPlugin

func _enter_tree() -> void:
	_dock = PostureEditorDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_gizmo_plugin = PostureGizmoPlugin.new()
	_gizmo_plugin.dock = _dock
	add_node_3d_gizmo_plugin(_gizmo_plugin)

func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
