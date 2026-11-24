shader_type spatial;
// The ball's dark outline (visual only): the drawn ball grown by `outline_pixels` render
// pixels and drawn back faces only (inverted hull), so a 1-render-pixel near-black
// olive ring shows around the body on any court. Second pass of the body material
// (scripts/ball.gd). Flat colour, no glow.
render_mode unshaded, fog_disabled, shadows_disabled, cull_front;

#include "res://shaders/ball_shape.gdshaderinc"

uniform vec3 outline_color : source_color = vec3(0.078, 0.082, 0.047);
uniform float gain = 2.2;

void vertex() {
	VERTEX = ball_vertex(VERTEX, MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, true);
}

void fragment() {
	ALBEDO = outline_color * gain;
}
