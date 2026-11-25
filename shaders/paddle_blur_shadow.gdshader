shader_type spatial;
// Shadow of the paddle's motion blur (visual only). The next pass of each swept paddle part
// (paddle_blur.gdshader, scripts/graphics/paddle_skin.gd): the same swept shape, every vertex
// slid along the sun's light down to the court like the paddle's own shadow
// (mesh_shadow.gdshader), darkest at the paddle and fading to nothing where the sweep began.
// It tests and writes the players' shadow stencil, so it only darkens court that no solid
// shadow has darkened. No TIME.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul;
stencil_mode read, write, compare_not_equal, 64;

uniform mat4 before = mat4(1.0);
uniform vec3 centre = vec3(0.0);
uniform vec3 light_dir = vec3(-0.46, -0.643, 0.613);
uniform float ground_y = 0.075;
uniform float shadow_y = 0.085;
uniform vec3 shadow_color : source_color = vec3(0.231, 0.227, 0.361);
uniform float opacity = 0.4;
varying float tail;

void vertex() {
	vec3 now = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 was = (before * vec4(VERTEX, 1.0)).xyz;
	vec3 moved = now - was;
	tail = 0.0;
	vec3 at = now;
	if (dot(moved, moved) > 1e-8 && dot(now - centre, moved) < 0.0) {
		tail = 1.0;
		at = was;
	}
	float k = (at.y - ground_y) / min(light_dir.y, -1e-3);
	at = vec3(at.x - k * light_dir.x, shadow_y, at.z - k * light_dir.z);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(at, 1.0)).xyz;
}

void fragment() {
	if (tail <= 0.01) discard;
	float fade = 1.0 - tail;
	ALBEDO = mix(vec3(1.0), shadow_color, opacity * 0.85 * fade * sqrt(fade));
}
