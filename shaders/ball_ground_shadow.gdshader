shader_type spatial;
// The ball's ground shadow (visual only): a plain oval where the sun casts it, slid along
// the light from the ball and drawn out along it like the players' shadows (placed by
// fx/ground_shadows.gd, which also shrinks and lightens it as the ball rises). Never a
// billboard or landing prediction. Multiplies the ground by
// lerp(1, shadow_color, opacity) (SunLight.SHADOW_COLOR, about Sun.BALL_OPACITY): court lines
// stay visible, and it is drawn after every other shadow (render_priority) so it still reads
// inside a player's or the net's shadow. Hard pixel edge, never under `min_pixels` render
// pixels across so it stays findable at the far baseline. Depth tested: players and the ball
// occlude it normally. No TIME.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul;

uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform vec3 shadow_color : source_color = vec3(0.231, 0.227, 0.361);
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
	if (dot(local, local) > 0.25 || abs(court_position.x) > apron_half_size.x || abs(court_position.y) > apron_half_size.y) discard;
	ALBEDO = mix(vec3(1.0), shadow_color, opacity);
}
