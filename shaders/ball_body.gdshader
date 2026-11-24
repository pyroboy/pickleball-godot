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

void vertex() {
	VERTEX = ball_vertex(VERTEX, MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, false);
}

void fragment() {
	float d = dot(normalize(NORMAL), normalize(light_view));
	vec3 c = d < dark_below ? dark : (d > light_above ? light : mid);
	ALBEDO = c * gain;
}
