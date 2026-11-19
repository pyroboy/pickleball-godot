shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0, 1.0) = 0.22;
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	// Soft penumbra plus a tighter, darker core so a player reads as planted on the floor.
	float soft_edge = 1.0 - smoothstep(0.12, 1.0, radius);
	float core = 1.0 - smoothstep(0.0, 0.55, radius);
	ALBEDO = vec3(0.025, 0.04, 0.065);
	ALPHA = clamp(soft_edge * 0.75 + core * 0.35, 0.0, 1.0) * opacity;
}
