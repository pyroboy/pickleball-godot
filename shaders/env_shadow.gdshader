shader_type spatial;
// Shadows of the things that move around the court (visual only): people, animals and the
// pandesal cart, one MultiMesh of flat unit planes placed by barangay_world.gd `_write_fig`
// (local x along the sun, from just behind the feet). Each is a hard oval on the same 4 cm
// grid as the baked static mask, multiplying the ground by the one shadow colour like
// shadow_ground.gdshader. Where the mask already shades the ground it only adds the
// difference, so a figure standing in a prop's shadow is not darker (max union).
// Static shader: no TIME; the instances only move when the figures do (12 Hz steps).
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul;

uniform sampler2D near_mask : filter_nearest, repeat_disable;
uniform vec4 near_rect = vec4(-20.0, -34.0, 40.0, 68.0);
uniform float texel = 0.04;
uniform vec3 shadow_col = vec3(0.231, 0.227, 0.361);   // #3b3a5c, display values
uniform float opacity = 0.4;
uniform vec2 court_half = vec2(3.05, 6.705);
uniform vec3 fog = vec3(8.0, 0.02, 0.7);

varying vec3 world_pos;
varying vec2 o_c;     // the oval's centre and its two half-axes x 2 (world x, z)
varying vec2 o_ax;
varying vec2 o_az;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	o_c = MODEL_MATRIX[3].xz;
	o_ax = MODEL_MATRIX[0].xz;
	o_az = MODEL_MATRIX[2].xz;
}

void fragment() {
	// test the texel centre, so the oval's edge steps with the baked mask's texels
	vec2 p = near_rect.xy + (floor((world_pos.xz - near_rect.xy) / texel) + 0.5) * texel;
	mat2 m2 = mat2(o_ax, o_az);
	if (abs(determinant(m2)) < 1e-8) discard;
	vec2 l = inverse(m2) * (p - o_c);
	if (dot(l, l) > 0.25) discard;
	vec2 u = (p - near_rect.xy) / near_rect.zw;
	float m = 0.0;
	if (u.x >= 0.0 && u.y >= 0.0 && u.x < 1.0 && u.y < 1.0) m = textureLod(near_mask, u, 0.0).r;
	float out_d = length(max(abs(world_pos.xz) - court_half, vec2(0.0)));
	float keep = 1.0 - fog.z * (1.0 - exp(-fog.y * max(out_d - fog.x, 0.0)));
	float s = opacity * keep;
	m *= keep;
	if (s <= m + 0.002) discard;
	ALBEDO = mix(vec3(1.0), shadow_col, s) / mix(vec3(1.0), shadow_col, m);
}
