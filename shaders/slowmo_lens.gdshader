shader_type spatial;
// Slow-mo lens (docs/PICKLEBALL_2.5D_PROPOSAL.pdf, pages 19-21), drawn as a
// full-screen quad at the end of the 3D pass so it reads the real depth
// buffer: every pixel (court, net, players, buildings, crowd) blurs by its own
// distance from the focus plane, like a real lens. No masks, no halos.
//
// Tilt-shift: the focus band sits on the far court where the shot goes; the
// net softens a little, the server and near court blur at reduced strength,
// the scenery behind blurs fully. Blur reads the screen mip pyramid. A light
// cool dim and desaturation follow the blur. The ball stays crisp; the aim
// arc, target ring and UI draw on canvas layers after this, never softened.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float effect_mix = 1.0;
uniform float strength = 0.14;          // cool dim at full blur
uniform float max_blur = 0.012;         // blur radius at full defocus, as a fraction of screen width
uniform float desaturate = 0.32;
uniform float focus_depth = 17.0;       // metres from the camera
uniform float focus_band = 3.5;         // metres kept sharp around it
uniform float defocus_gain = 1.6;       // blur is full when |d - f| / d reaches 1 / gain
uniform float near_strength = 0.55;     // foreground blurs less than the background
uniform vec2 ball_uv = vec2(-2.0);
uniform float ball_radius = 0.03;       // fraction of screen width

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float scene_depth(vec2 uv, mat4 inv_proj) {
	float raw = textureLod(depth_texture, uv, 0.0).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw * 2.0 - 1.0, 1.0);
	return min(length(view.xyz / view.w), 80.0);
}

vec3 sample_blur(vec2 uv, float r) {
	vec2 tex = vec2(textureSize(screen_texture, 0));
	vec2 r_uv = vec2(r, r * tex.x / tex.y);
	float lod = max(log2(max(r * tex.x, 1.0)) - 0.5, 0.0);
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
	float depth = scene_depth(uv, INV_PROJECTION_MATRIX);
	float off = max(abs(depth - focus_depth) - focus_band * 0.5, 0.0) / max(depth, 0.5);
	float defocus = clamp(off * defocus_gain, 0.0, 1.0);
	defocus = defocus * defocus * (3.0 - 2.0 * defocus);
	if (depth < focus_depth) defocus *= near_strength;
	vec2 tex = vec2(textureSize(screen_texture, 0));
	vec2 d = (uv - ball_uv) * vec2(1.0, tex.y / tex.x);
	defocus *= smoothstep(ball_radius * 0.5, ball_radius, length(d));
	float r = max_blur * defocus;
	vec3 original = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 col = r * tex.x > 0.4 ? mix(original, sample_blur(uv, r), effect_mix) : original;
	float look = defocus * effect_mix;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * vec3(0.92, 0.97, 1.06), desaturate * look);
	col = mix(col, vec3(0.018, 0.035, 0.065), strength * look);
	ALBEDO = col;
}
