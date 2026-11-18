extends RefCounted
## Test-only navigation for controls split across body-part categories/subviews.
## Always use real editor navigation; never manufacture controls or change poses.
static func select_field(editor, field: String) -> void:
	for category in range(editor.Fields.CATEGORIES.size()):
		for descriptor in editor.Fields.category_fields(category, editor._base):
			if descriptor.field != field: continue
			var view: int = editor._paddle_view
			if category == 7 and not editor._base:
				if field in editor.ROT or field.contains("signed") or field.contains("sign_source"): view = 0
				elif field in editor.POS or field == "paddle_floor_clearance": view = 1
				else: view = 2
			if editor._category.selected != category or editor._paddle_view != view:
				editor._paddle_view = view
				editor._select_category(category)
			return
	assert(false, "No body-part category owns field: " + field)

static func open_section(editor, caption: String) -> void:
	for node in editor._fields.find_children("*", "Button", true, false):
		if node.toggle_mode and node.text.begins_with(caption):
			node.button_pressed = true
			return
	assert(false, "No collapsible section found: " + caption)

static func reveal_field(editor, field: String) -> void:
	select_field(editor, field)
	for descriptor in editor.Fields.category_fields(editor._category.selected, editor._base):
		if descriptor.field == field and descriptor.type == "vector":
			open_section(editor, descriptor.label)
			return
