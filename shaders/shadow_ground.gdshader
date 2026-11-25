shader_type spatial;
// The baked static shadows (visual only): one flat layer over the whole ground, just above
// the court lines and under the players' and the ball's shadows. It multiplies the floor,
// court and lines by the one shadow colour (scripts/graphics/sun_light.gd SHADOW_COLOR)
// at the opacity barangay_world.gd painted into the mask (L8: 0 none, Sun.NET_OPACITY under
// the net's weave, Sun.SHADOW_OPACITY elsewhere), so lines stay visible inside a shadow.
// Multiply in display terms: ground * mix(1, SHADOW_COLOR, opacity). The compatibility
// renderer blends on the displayed values, so the factor goes in as is (measured
// 2026-11-25: the rendered ratio is factor^1.04; a pow 2.2 made shadows twice too dark).
// Two masks, both nearest-sampled so the edges stair-step on their texel grid: 4 cm around
// the slab (published to ShadowMask) and 15 cm further out. Far out it fades with the
// floor's distance fog. Static: no TIME, nothing per frame.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul;

uniform sampler2D near_mask : filter_nearest, repeat_disable;
uniform sampler2D far_mask : filter_nearest, repeat_disable;
uniform vec4 near_rect = vec4(-20.0, -34.0, 40.0, 68.0);   // world x, z, size x, size z
uniform vec4 far_rect = vec4(-52.5, -76.5, 105.0, 153.0);
uniform vec3 shadow_col = vec3(0.231, 0.227, 0.361);       // #3b3a5c, display (sRGB) values
// the floor's distance fog (env_floor.gdshader): shadows fade where the floor fades
uniform vec2 court_half = vec2(3.05, 6.705);
uniform vec3 fog = vec3(8.0, 0.02, 0.7);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float mask_at(vec2 p) {
	vec2 u = (p - near_rect.xy) / near_rect.zw;
	if (u.x >= 0.0 && u.y >= 0.0 && u.x < 1.0 && u.y < 1.0) return textureLod(near_mask, u, 0.0).r;
	u = (p - far_rect.xy) / far_rect.zw;
	if (u.x >= 0.0 && u.y >= 0.0 && u.x < 1.0 && u.y < 1.0) return textureLod(far_mask, u, 0.0).r;
	return 0.0;
}

void fragment() {
	float m = mask_at(world_pos.xz);
	if (m < 0.004) discard;
	float out_d = length(max(abs(world_pos.xz) - court_half, vec2(0.0)));
	m *= 1.0 - fog.z * (1.0 - exp(-fog.y * max(out_d - fog.x, 0.0)));
	ALBEDO = mix(vec3(1.0), shadow_col, m);
}
