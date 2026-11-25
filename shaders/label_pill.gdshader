shader_type spatial;
// Dark navy pixel pill behind an in-world Label3D (shot names, OUT, aim and smash
// labels): the same stair-cornered plate as the HUD pills (pixel_style_box.gd
// label_pill), billboarded like the label, no depth test, no light, no glow.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 fill : source_color = vec4(0.059, 0.133, 0.188, 0.86);
uniform vec2 cells = vec2(24.0, 6.0);   // pill size in UI pixels
uniform float alpha = 1.0;              // follows the label's fade

void vertex() {
	// Billboard that keeps the node's scale (the label pop scales the pill with it).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 cell = floor(UV * cells);
	vec2 edge = min(cell, cells - 1.0 - cell);
	if (edge.x + edge.y < 1.0) discard;            // stair corner: one UI pixel cut
	bool bevel = cells.y - 1.0 - cell.y < 1.0;      // bottom row a little darker
	ALBEDO = bevel ? fill.rgb * 0.6 : fill.rgb;
	ALPHA = fill.a * alpha;
}
