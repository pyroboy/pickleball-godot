shader_type spatial;
// The ball's dark outline (visual only): the drawn ball grown by `outline_pixels` render
// pixels and drawn back faces only (inverted hull), so a 1-render-pixel near-black
// olive ring shows around the body on any court. Second pass of the body material
// (scripts/ball.gd). Flat colour, no glow.
render_mode unshaded, fog_disabled, shadows_disabled, cull_front;

#include "res://shaders/ball_shape.gdshaderinc"

uniform vec3 outline_color : source_color = vec3(0.078, 0.082, 0.047);
uniform float gain = 2.2;

varying vec3 centre_view;   // the ball's middle, view space
varying vec3 motion_view;   // `motion`, view space

void vertex() {
	float along;
	centre_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	motion_view = (VIEW_MATRIX * vec4(motion, 0.0)).xyz;
	VERTEX = ball_vertex(VERTEX, MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, true, true, 1.0, along);
	tail = along;
}

void fragment() {
	// No outline at the rear of the oblong: where the ball is lengthening on screen the ring is
	// left open, so the ball runs into its blur tail instead of being fenced off from it.
	float seen = length(motion_view.xy);
	if (seen > 0.2 * radius) {
		vec2 from_centre = VERTEX.xy - centre_view.xy;
		float behind = dot(normalize(from_centre + vec2(1e-6)), -motion_view.xy / seen);   // 1 straight behind the ball
		if (behind > mix(1.0, 0.1, clamp(seen / (0.9 * radius), 0.0, 1.0))) discard;
	}
	ALBEDO = outline_color * gain;
}
