shader_type spatial;
// In-game pickleball body (visual only): the standard neon yellow-green in three flat
// bands, no glow, no rim light. Lit from the upper left in view space so it reads the
// same from every camera. Colours are stored values for the game's chain (unshaded x
// gain, 3D buffer clamp, Filmic, PixelPost); scripts/ball.gd has the on-screen targets.
render_mode unshaded, fog_disabled, shadows_disabled, cull_back;

#include "res://shaders/ball_shape.gdshaderinc"

uniform vec3 dark : source_color = vec3(0.239, 0.294, 0.059);
uniform vec3 mid : source_color = vec3(0.365, 0.443, 0.090);
uniform vec3 light : source_color = vec3(0.396, 0.443, 0.173);
uniform float gain = 2.2;
uniform vec3 light_view = vec3(-0.5, 0.7, 0.5);   // toward the light, view space
uniform float dark_below = -0.2;    // ~15 % of the disc: lower-right crescent
uniform float light_above = 0.9;    // ~10 % of the disc: upper-left spot

// Holes (visual only): a pickleball's round holes, as darker dots fixed to the ball's own
// surface. The drawn ball itself never rotates, so `turn` carries the ball's real spin
// (scripts/fx/ball_trail.gd adds up its angular velocity) and the holes roll with it. 32 holes, evenly spread: the 12 corners of
// an icosahedron and the 20 of a dodecahedron (by symmetry, 7 directions checked per pixel).
// Their edges are softened over a pixel so they do not flicker on a ball a few pixels wide,
// they fade out as the ball lengthens in flight (holes on a fast ball blur away), and they
// only show on a ball drawn big enough to hold them (HOLES_FROM_PX to HOLES_FULL_PX across):
// on a ball 3-6 pixels wide a hole is a stray dark pixel, which only makes the ball harder to see.
const float HOLES_FROM_PX = 6.5;
const float HOLES_FULL_PX = 11.0;
varying float ball_px;              // the ball's width on screen, render pixels
uniform float holes = 0.75;         // how dark the holes are, 0 = a plain ball
uniform float hole_size = 0.19;     // a hole's radius as an angle on the ball, radians
uniform mat3 turn = mat3(1.0);      // the ball's accumulated spin
varying vec3 surface;               // this point on the ball, in the ball's own frame

float hole_cover(vec3 p) {
	vec3 a = abs(normalize(p));
	const float G = 1.618034;
	float near = max(max(dot(a, normalize(vec3(0.0, 1.0, G))), dot(a, normalize(vec3(1.0, G, 0.0)))), dot(a, normalize(vec3(G, 0.0, 1.0))));
	near = max(near, dot(a, vec3(0.57735)));
	near = max(near, max(max(dot(a, normalize(vec3(0.0, 1.0 / G, G))), dot(a, normalize(vec3(1.0 / G, G, 0.0)))), dot(a, normalize(vec3(G, 0.0, 1.0 / G)))));
	float edge = cos(hole_size);
	float soft = max(fwidth(near), 0.004);
	return smoothstep(edge - soft, edge + soft, near);
}

void vertex() {
	float along;
	surface = turn * VERTEX;
	float depth = max(-(VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).z, 0.05);
	ball_px = 2.0 * radius * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / depth;
	VERTEX = ball_vertex(VERTEX, MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, false, true, 1.0, along);
	tail = along;
}

void fragment() {
	float d = dot(normalize(NORMAL), normalize(light_view));
	vec3 c = d < dark_below ? dark : (d > light_above ? light : mid);
	float shown = holes * smoothstep(HOLES_FROM_PX, HOLES_FULL_PX, ball_px);
	if (shown > 0.0) {
		float blurred = clamp(length(motion) / (1.4 * radius), 0.0, 1.0);
		c = mix(c, dark * 0.6, hole_cover(surface) * shown * (1.0 - 0.8 * blurred));
	}
	ALBEDO = c * gain;
}
