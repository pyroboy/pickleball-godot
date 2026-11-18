shader_type canvas_item;
// Pixel post (VISUAL_PASS_PLAN step 2). The 3D world renders at 1/2 resolution
// (root scaling_3d_scale = 0.5) and the engine upscales it with bilinear
// filtering. Sampling one texel per 2x2 output block turns that into hard
// pixel blocks; then a subtle grade and vignette. UI layers sit above this.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float unblur = 0.6;         // undo the engine's bilinear upscale (0 = soft)
uniform float block = 2.0;          // output pixels per 3D pixel (1 / scaling_3d_scale)
uniform float contrast = 1.06;
uniform float saturation = 1.08;
uniform float vignette = 0.22;      // 0 = off

void fragment() {
	// Centre of this output block = centre of one half-res 3D pixel. A linear
	// sample there averages the block; the bilinear upscale smeared each pixel
	// ~1/4 into its neighbours, so push it back away from the neighbour blocks.
	vec2 centre = (floor(FRAGCOORD.xy / block) + 0.5) * block;
	vec2 sp = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, centre * sp).rgb;
	vec3 n = texture(screen_tex, (centre + vec2(block, 0.0)) * sp).rgb + texture(screen_tex, (centre - vec2(block, 0.0)) * sp).rgb
		+ texture(screen_tex, (centre + vec2(0.0, block)) * sp).rgb + texture(screen_tex, (centre - vec2(0.0, block)) * sp).rgb;
	c = c + unblur * (c - n * 0.25);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.75)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
