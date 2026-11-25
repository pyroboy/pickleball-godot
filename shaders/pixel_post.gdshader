shader_type canvas_item;
// Pixel post (ROADMAP Phase 2). The 3D world renders at 1/3 resolution (root
// scaling_3d_scale, see pixel_post.gd) and the engine upscales it with bilinear
// filtering. Each output pixel reads the upscaled image at the centre of the
// low-res pixel it falls in; there the bilinear weights are exactly one texel, so
// the result is a true nearest-neighbour upscale: court, players and effects share
// one hard pixel grid. Then the grade and a faint vignette, both per low-res pixel so
// they stay on the grid. UI layers sit above this at full resolution.
//
// Golden-hour grade (lighting pass 2026-11-25, one sun: scripts/graphics/sun_light.gd):
// near-neutral colours (cement, sky, whites) warm up; saturated ones (the ball's
// yellow-green, the team kits) are left alone, by their chroma. Then split toning by
// luminance: shadows lean cool blue-violet, highlights warm. Every tint here keeps the
// channel mean (its weights sum to zero), so the grey ramp tools/calibrate_cards.gd
// measures (its average of r, g, b) is unchanged by them. The vignette is faint and falls
// off a little more in blue than in red, so the corners go warm, not grey.
// Saturation is baked into the card and environment colour compensation
// (tools/bake_pixel_cards.py, scripts/environment/env_palette.gd POST_SATURATION): change
// it only together with those. Contrast went 1.06 -> 1.1 on purpose in the golden-hour
// pass (a little more punch than the calibration assumed); re-measuring the LUT with
// tools/calibrate_cards.gd would hand that back.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float scale = 0.3333333;    // root scaling_3d_scale
uniform float contrast = 1.1;
uniform float saturation = 1.08;
uniform vec3 warm = vec3(1.05, 1.0, 0.95);
uniform vec2 warm_chroma = vec2(0.06, 0.24);   // full grade below, none above (max - min of rgb)
// split toning: zero-sum tints, scaled by `split.x` in the shadows and `split.y` in the
// highlights (shadows below ~0.45 luminance, highlights above ~0.6)
uniform vec3 shadow_tint = vec3(-0.2, -0.6, 0.8);   // blue-violet
uniform vec3 highlight_tint = vec3(0.7, 0.1, -0.8); // warm
uniform vec2 split = vec2(0.045, 0.035);
uniform float vignette = 0.1;       // 0 = off
uniform vec3 vignette_tint = vec3(0.8, 1.0, 1.25);

void fragment() {
	// Low-res buffer size as the engine computes it (truncated), so the grid also
	// lines up when the screen is not a multiple of 3 (blocks are then 3 or 4 px).
	vec2 lo = max(floor((1.0 / SCREEN_PIXEL_SIZE) * scale + 0.001), vec2(1.0));
	vec2 uv = (floor(SCREEN_UV * lo) + 0.5) / lo;
	vec3 c = texture(screen_tex, uv).rgb;
	float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	c = mix(c * warm, c, smoothstep(warm_chroma.x, warm_chroma.y, chroma));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// shadows: fade in above near-black (black stays black), out by mid-grey
	float ws = smoothstep(0.02, 0.12, l) * (1.0 - smoothstep(0.2, 0.5, l));
	float wh = smoothstep(0.55, 0.9, l);
	c += shadow_tint * (split.x * ws) + highlight_tint * (split.y * wh);
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	vec2 d = uv - 0.5;
	c *= 1.0 - vignette * vignette_tint * smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.75)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
