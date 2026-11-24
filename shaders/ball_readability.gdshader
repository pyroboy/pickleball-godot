shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float ball_radius = 0.0375;
uniform float minimum_pixels = 8.0;
uniform float maximum_pixels = 12.0;
uniform float fade_start_pixels = 5.0;
uniform float fade_end_pixels = 10.0;
// Pixel viewport: a ball thinner than this many render pixels can miss every pixel
// centre and vanish for a frame, so the cue then carries a solid dot of this size.
uniform float minimum_ball_pixels = 2.0;
varying float cue_opacity;
varying float dot_radius;
void vertex() {
	// Use the actual ball center/depth, never a projected floor position.
	// Clip-space expansion ignores the body's spin and keeps the visual cue
	// screen-aligned without changing its world mesh or physics sphere.
	vec4 view_center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 center = PROJECTION_MATRIX * view_center;
	vec4 edge = PROJECTION_MATRIX * (view_center + vec4(ball_radius * 2.0, 0.0, 0.0, 0.0));
	float projected_pixels = abs(edge.x / edge.w - center.x / center.w) * VIEWPORT_SIZE.x * 0.5;
	float diameter = clamp(projected_pixels * 1.4, minimum_pixels, maximum_pixels);
	cue_opacity = 1.0 - smoothstep(fade_start_pixels, fade_end_pixels, projected_pixels);
	dot_radius = projected_pixels < minimum_ball_pixels ? minimum_ball_pixels / diameter : 0.0;
	POSITION = center;
	POSITION.xy += VERTEX.xy * diameter * 2.0 / VIEWPORT_SIZE * center.w;
}
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float outer = 1.0 - smoothstep(0.82, 1.0, radius);
	float hollow_center = smoothstep(0.20, 0.36, radius);
	float dark_outline = smoothstep(0.65, 0.77, radius);
	ALBEDO = mix(vec3(1.0, 0.96, 0.20), vec3(0.025, 0.04, 0.065), dark_outline);
	ALPHA = outer * hollow_center * cue_opacity * 0.96;
	if (radius < dot_radius) {
		ALBEDO = vec3(1.0, 0.96, 0.20);
		ALPHA = 1.0;
	}
}
