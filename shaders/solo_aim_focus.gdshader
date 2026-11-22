shader_type canvas_item;
render_mode unshaded;
// Slow-mo lens (docs/PICKLEBALL_2.5D_PROPOSAL.pdf, pages 19-21).
//
// A real depth of field, not a flat background blur: the focus plane sits at
// the hitter's depth with a 1.5 m sharp band, and blur grows with
// |depth - focus| / depth, so the far end and the near foreground soften like
// a tilt-shift. Depth comes from the known court plane: each pixel's camera
// ray is met with y = 0 (anything at or above the horizon counts as far).
// The blur reads the screen texture's mip pyramid (a cheap Kawase-style
// filter: a few taps at the right level). A light cool dim and desaturation
// follow the blur. Opponents and partner keep a feathered mask that caps
// their blur at ~1.6 px and halves the dim; the hitter, ball and aim target
// stay crisp. The aim arc and UI draw after this layer, never softened.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(720.0, 1280.0);
uniform float effect_mix = 1.0;
uniform float strength = 0.14;          // cool dim at full blur
uniform float max_blur_px = 6.0;        // logical px at full defocus
uniform float desaturate = 0.32;
uniform float focus_depth = 11.7;       // metres from the camera
uniform float focus_band = 1.5;         // metres kept sharp around it
uniform float defocus_gain = 1.1;       // blur is full when |d - f| / d reaches 1 / gain
uniform vec3 cam_origin = vec3(0.0, 8.0, 14.0);
uniform vec3 ray_tl = vec3(0.0, 0.0, -1.0);
uniform vec3 ray_tr = vec3(0.0, 0.0, -1.0);
uniform vec3 ray_bl = vec3(0.0, 0.0, -1.0);
uniform vec3 ray_br = vec3(0.0, 0.0, -1.0);
uniform vec2 target_uv = vec2(-2.0);
uniform vec2 ball_uv = vec2(-2.0);
uniform vec2 foot_uv[4];
uniform vec2 head_uv[4];
uniform float player_cap[4];            // max blur px inside the mask; 0 = crisp, < 0 = unused
uniform float radius = 70.0;

const float FAR_DEPTH = 60.0;

float segment_distance(vec2 pixel, vec2 start, vec2 end) {
	vec2 segment = end - start;
	float along = clamp(dot(pixel - start, segment) / max(dot(segment, segment), 0.001), 0.0, 1.0);
	return length(pixel - start - segment * along);
}

float ground_depth(vec2 uv) {
	vec3 dir = normalize(mix(mix(ray_tl, ray_tr, uv.x), mix(ray_bl, ray_br, uv.x), uv.y));
	if (dir.y > -0.002) return FAR_DEPTH;
	return min(cam_origin.y / -dir.y, FAR_DEPTH);
}

vec3 sample_blur(vec2 uv, float blur_px) {
	vec2 tex = vec2(textureSize(screen_texture, 0));
	vec2 r_uv = vec2(blur_px) / viewport_size;
	float texels = blur_px * tex.x / viewport_size.x;
	// Four diagonal taps half a radius out, each from the mip that already
	// averages about that footprint: a dual-filter look for 5 reads.
	float lod = max(log2(max(texels, 1.0)) - 0.5, 0.0);
	vec2 o = r_uv * 0.5;
	vec3 c = textureLod(screen_texture, uv, lod).rgb * 0.2;
	c += textureLod(screen_texture, uv + vec2(o.x, o.y), lod).rgb * 0.2;
	c += textureLod(screen_texture, uv + vec2(-o.x, o.y), lod).rgb * 0.2;
	c += textureLod(screen_texture, uv + vec2(o.x, -o.y), lod).rgb * 0.2;
	c += textureLod(screen_texture, uv + vec2(-o.x, -o.y), lod).rgb * 0.2;
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = uv * viewport_size;
	float depth = ground_depth(uv);
	float off = max(abs(depth - focus_depth) - focus_band * 0.5, 0.0) / max(depth, 0.5);
	float defocus = clamp(off * defocus_gain, 0.0, 1.0);
	defocus = defocus * defocus * (3.0 - 2.0 * defocus);
	float blur_px = max_blur_px * defocus;
	float dim_scale = 1.0;
	for (int i = 0; i < 4; i++) {
		if (player_cap[i] < 0.0) continue;
		float inside = 1.0 - smoothstep(radius * 0.36, radius * 0.70, segment_distance(pixel, foot_uv[i] * viewport_size, head_uv[i] * viewport_size));
		blur_px = mix(blur_px, min(blur_px, player_cap[i]), inside);
		dim_scale = min(dim_scale, mix(1.0, player_cap[i] <= 0.0 ? 0.0 : 0.5, inside));
	}
	float ball = 1.0 - smoothstep(radius * 0.16, radius * 0.34, length(pixel - ball_uv * viewport_size));
	float target = 1.0 - smoothstep(radius * 0.40, radius, length(pixel - target_uv * viewport_size));
	float crisp = max(ball, target);
	blur_px *= 1.0 - crisp;
	dim_scale *= 1.0 - crisp;
	vec3 original = textureLod(screen_texture, uv, 0.0).rgb;
	float amount = clamp(blur_px / 1.0, 0.0, 1.0) * effect_mix;
	vec3 col = blur_px > 0.25 ? mix(original, sample_blur(uv, blur_px), amount) : original;
	// Dim and desaturation follow the blur, so the sharp band stays true colour.
	float look = defocus * dim_scale * effect_mix;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * vec3(0.92, 0.97, 1.06), desaturate * look);
	col = mix(col, vec3(0.018, 0.035, 0.065), strength * look);
	COLOR = vec4(col, 1.0);
}
