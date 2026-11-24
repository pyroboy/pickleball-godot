shader_type canvas_item;
// Pixel post (ROADMAP Phase 2). The 3D world renders at 1/3 resolution (root
// scaling_3d_scale, see pixel_post.gd) and the engine upscales it with bilinear
// filtering. Each output pixel reads the upscaled image at the centre of the
// low-res pixel it falls in; there the bilinear weights are exactly one texel, so
// the result is a true nearest-neighbour upscale: court, players and effects share
// one hard pixel grid. Then a subtle grade and vignette, both per low-res pixel so
// they stay on the grid. UI layers sit above this at full resolution.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float scale = 0.3333333;    // root scaling_3d_scale
uniform float contrast = 1.06;
uniform float saturation = 1.08;
uniform float vignette = 0.22;      // 0 = off

void fragment() {
	// Low-res buffer size as the engine computes it (truncated), so the grid also
	// lines up when the screen is not a multiple of 3 (blocks are then 3 or 4 px).
	vec2 lo = max(floor((1.0 / SCREEN_PIXEL_SIZE) * scale + 0.001), vec2(1.0));
	vec2 uv = (floor(SCREEN_UV * lo) + 0.5) / lo;
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	vec2 d = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.75)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
