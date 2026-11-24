shader_type spatial;
// The ball's ground blob (visual only): a crisp dark disc straight under the ball, its
// height cue (fx/ground_shadows.gd shrinks and fades it as the ball rises). Never a light
// shadow, billboard or landing prediction. Hard pixel edge with a slightly lighter rim,
// no gradient, and never under `min_pixels` render pixels across so it stays findable at
// the far baseline. Keep depth testing: players/the ball can occlude it normally.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform vec2 apron_half_size = vec2(8.0, 20.0);
uniform float min_pixels = 5.0;
varying vec2 court_position;
varying vec2 local;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float depth = max(-(VIEW_MATRIX * vec4(centre, 1.0)).z, 0.05);
	float px = size * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / depth;   // abs: y-flipped when drawn to a texture
	local = VERTEX.xz;   // -0.5..0.5 on the unit plane, before any growth
	VERTEX.xz *= max(1.0, min_pixels / max(px, 0.001));
	court_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float r = length(local) * 2.0;
	float on_apron = float(abs(court_position.x) < apron_half_size.x && abs(court_position.y) < apron_half_size.y);
	float shade = r < 0.62 ? 1.0 : (r < 1.0 ? 0.72 : 0.0);
	ALBEDO = vec3(0.008, 0.014, 0.02);
	ALPHA = shade * opacity * on_apron;
}
