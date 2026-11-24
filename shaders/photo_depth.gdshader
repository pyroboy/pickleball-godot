shader_type spatial;
// Photo mode distance map (scripts/ui/photo_mode.gd). A full-screen quad in front of a second
// camera that copies the photo camera into a small off-screen view. It reads the depth buffer
// and writes each pixel's distance along the view axis, so shaders/photo_focus.gdshader can
// blur every pixel by its real distance. Only that second camera sees this quad.
//
// Packing: the distance becomes an 18-bit number, six bits in each of red, green and blue.
// Each six-bit digit d is stored as the byte 64 + 3 * d: the view's colour output crushes
// values under about 64 and can be off by one, and this spacing survives both.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float max_distance = 120.0;   // m; farther (and the sky) reads as this
uniform bool calibrate = false;       // write the fixed digits 5, 33, 60 everywhere (start-up check)
uniform bool pre_linearise = false;   // for a renderer that converts this output to sRGB

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	highp float raw = texture(depth_tex, SCREEN_UV).r;
	highp vec4 view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, raw) * 2.0 - 1.0, 1.0);   // Compatibility: z in -1..1
	highp float dist = -view.z / view.w;
	if (dist <= 0.0) dist = max_distance;
	highp float n = floor(clamp(dist / max_distance, 0.0, 1.0) * 262143.0 + 0.5);
	highp float hi = floor(n / 4096.0);
	highp float mid = floor((n - hi * 4096.0) / 64.0);
	highp float lo = n - hi * 4096.0 - mid * 64.0;
	vec3 digits = calibrate ? vec3(5.0, 33.0, 60.0) : vec3(hi, mid, lo);
	vec3 packed = (64.0 + 3.0 * digits) / 255.0;
	ALBEDO = pre_linearise ? to_linear(packed) : packed;
}
