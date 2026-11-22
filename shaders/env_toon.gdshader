shader_type spatial;
// Environment props and figures (visual only): real 3D geometry with pixel-art shading.
// Colour comes from vertex colours (merged prop meshes) or MultiMesh instance colours
// (figures), already tonemap-compensated by scripts/environment/env_palette.gd. Light is
// three flat bands from a fixed sun with violet-shifted shadow sides and no outlines; the
// half-resolution PixelPost turns the edges into hard pixels.
// Vertex alpha < 1 marks swaying parts (flag, banderitas, laundry): 1 - alpha is the sway
// weight. The sway steps at 8 Hz so its pixels change in clean jumps instead of crawling.
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;

uniform float gain = 2.2;
uniform vec3 light_dir = vec3(-0.45, 0.8, 0.4);   // toward the sun, world space
uniform vec3 shade_tint : source_color = vec3(0.62, 0.55, 0.82);
uniform float sway_amount = 0.12;
uniform float sway_hz = 8.0;

varying vec3 world_normal;
varying vec3 tint;

vec3 to_linear(vec3 s) {
	return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
}

void vertex() {
	float sway = 1.0 - COLOR.a;
	if (sway > 0.001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = floor(TIME * sway_hz) / sway_hz;
		float w = sin(t * 2.3 + wp.x * 0.9 + wp.z * 0.4) + 0.5 * sin(t * 4.1 + wp.x * 2.1);
		VERTEX.x += w * sway * sway_amount;
		VERTEX.z += w * sway * sway_amount * 0.5;
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
}

void fragment() {
	vec3 base = to_linear(tint);
	float d = dot(normalize(world_normal), normalize(light_dir));
	vec3 c;
	if (d > 0.55) c = base;
	else if (d > 0.05) c = base * mix(vec3(1.0), shade_tint, 0.35) * 0.86;
	else c = base * shade_tint * 0.72;
	ALBEDO = c * gain;
}
