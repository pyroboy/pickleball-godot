shader_type spatial;
// The tail of the ball's motion blur (visual only). In flight the ball is a solid oblong
// (ball_body / ball_readability, ball_shape.gdshaderinc). This third pass of the ball's
// material (scripts/ball.gd) draws that oblong once more, `tail_lengthen` times longer back
// along the flight: the blur stretches most at the tail. It is see-through, in the ball's own
// tones, and its opacity falls in a straight line along the flight from the ball to the rear
// tip (a linear, directional blur), thinning toward its sides. It is drawn behind the solid
// oblong (pushed back in depth), so only what trails out behind the ball shows, also when the
// ball flies straight away from the camera. Plain alpha blend, no glow, no outline.
render_mode unshaded, fog_disabled, shadows_disabled, cull_back, depth_draw_never, blend_mix;

#include "res://shaders/ball_shape.gdshaderinc"

uniform vec3 dark : source_color = vec3(0.239, 0.294, 0.059);
uniform vec3 mid : source_color = vec3(0.365, 0.443, 0.090);
uniform vec3 light : source_color = vec3(0.396, 0.443, 0.173);
uniform float gain = 2.2;
uniform vec3 light_view = vec3(-0.5, 0.7, 0.5);
uniform float dark_below = -0.2;
uniform float light_above = 0.9;
uniform float tail_lengthen = 2.8;   // the tail's length as a multiple of the oblong's extra length
uniform float tail_opacity = 0.85;   // where the tail leaves the ball

void vertex() {
	float along;
	vec3 shape = ball_vertex(VERTEX, MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, false, true, tail_lengthen, along);
	tail = along;
	// Same place on screen, further away: behind the solid oblong.
	vec4 seen = MODELVIEW_MATRIX * vec4(shape, 1.0);
	seen.xyz *= 1.0 + (2.6 * radius + length(motion) * tail_lengthen) / max(length(seen.xyz), 0.05);
	VERTEX = (inverse(MODELVIEW_MATRIX) * seen).xyz;
}

void fragment() {
	if (length(motion) < 0.0005) discard;
	vec3 n = normalize(NORMAL);
	float d = dot(n, normalize(light_view));
	vec3 c = d < dark_below ? dark : (d > light_above ? light : mid);
	c = mix(c, mid, 0.7 * tail);   // the tones run together toward the rear
	float across = mix(1.0, mix(0.45, 1.0, clamp(abs(n.z), 0.0, 1.0)), tail);
	ALBEDO = c * gain;
	ALPHA = tail_opacity * (1.0 - tail) * across;   // linear along the flight
}
