shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0, 1.0) = 0.22;
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float soft_edge = 1.0 - smoothstep(0.12, 1.0, radius);
	ALBEDO = vec3(0.025, 0.04, 0.065);
	ALPHA = soft_edge * opacity;
}
