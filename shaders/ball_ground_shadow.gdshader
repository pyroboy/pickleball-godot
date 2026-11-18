shader_type spatial;
// One court-plane blob, never a light shadow, billboard or landing prediction.
// Keep depth testing: players/the ball can occlude it normally.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float opacity : hint_range(0.0, 1.0) = 0.72;
uniform vec2 apron_half_size = vec2(8.0, 20.0);
varying vec2 court_position;

void vertex() {
	court_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float soft_edge = 1.0 - smoothstep(0.25, 1.0, radius);
	float on_apron = float(abs(court_position.x) < apron_half_size.x && abs(court_position.y) < apron_half_size.y);
	ALBEDO = vec3(0.008, 0.014, 0.02);
	ALPHA = soft_edge * opacity * on_apron;
}
