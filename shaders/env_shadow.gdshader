shader_type spatial;
// Contact shadows on the floor (visual only), one MultiMesh of flat quads.
// INSTANCE_CUSTOM.x: 0 = soft-edged ellipse (figures, chairs), 1 = rectangle (buildings,
// tables). Hard edges, one flat violet-gray tone: pixel-art shadows, no blur.
render_mode unshaded, fog_disabled, shadows_disabled, depth_draw_never, blend_mix, cull_disabled;

uniform vec3 shadow_col : source_color = vec3(0.16, 0.13, 0.24);
uniform float strength = 0.38;

varying float shape;

void vertex() {
	shape = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 d = UV - 0.5;
	if (shape < 0.5 && dot(d, d) > 0.25) discard;
	ALBEDO = shadow_col;
	ALPHA = strength;
}
