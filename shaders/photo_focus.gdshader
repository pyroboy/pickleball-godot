shader_type canvas_item;
render_mode unshaded;
// Photo mode focus blur (scripts/ui/photo_mode.gd). Every pixel is blurred by its own distance
// from the camera, read from the distance map that shaders/photo_depth.gdshader renders from
// the real depth buffer (players, ball, court, buildings: whatever is drawn there).
//
// One pass, depth aware: a sample only counts if its own blur disc reaches this pixel, so a
// sharp player never smears into the blurred background and nothing sharp is softened; a
// blurred thing in front still spreads over what is behind it. Samples lie on a spiral that
// is denser near the centre (weighted by the area each one stands for), so small and large
// blurs both get enough of them.
//
// Fallback (use_map = false, when the distance map cannot be read on this device): distance
// from where the view ray meets the floor or a box around the arena, with a capsule around
// each player and the ball carrying its own distance.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_map : repeat_disable, filter_nearest;
uniform bool use_map = false;
uniform float map_max = 120.0;            // m: shaders/photo_depth.gdshader max_distance
uniform float block = 2.0;                // screen pixels per 3D pixel (pixel_post.gd)
uniform vec2 viewport_size = vec2(720.0, 1280.0);
uniform float blur_radius = 0.0;          // largest blur radius, in viewport_size units
uniform float focus_distance = 8.0;       // m
uniform float focus_range = 0.5;          // m either side kept fully sharp
uniform int taps = 16;
uniform vec3 cam_pos;
uniform vec3 cam_right;
uniform vec3 cam_up;
uniform vec3 cam_forward;
uniform vec2 tan_half;                    // tan of half the view angle, x and y
uniform float floor_y = 0.075;
uniform vec2 arena_half = vec2(20.0, 24.0);   // m: x and z half size of the backdrop box
uniform vec4 seg[5];                      // fallback: start uv (xy), end uv (zw), drawn far to near
uniform float seg_radius[5];              // pixels
uniform float seg_dist[5];                // m from the camera

const float PI_F = 3.14159265;
const float SHARP = 0.5642;               // radius of a disc one pixel in area

float segment_distance(vec2 pixel, vec2 start, vec2 end) {
	vec2 segment = end - start;
	float along = clamp(dot(pixel - start, segment) / max(dot(segment, segment), 0.001), 0.0, 1.0);
	return length(pixel - start - segment * along);
}

float fallback_distance(vec2 uv) {
	vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	vec3 dir = normalize(cam_forward + cam_right * ndc.x * tan_half.x + cam_up * ndc.y * tan_half.y);
	float t = 1e6;
	if (dir.y < -1e-4) t = (floor_y - cam_pos.y) / dir.y;
	if (abs(dir.x) > 1e-4) t = min(t, ((dir.x > 0.0 ? arena_half.x : -arena_half.x) - cam_pos.x) / dir.x);
	if (abs(dir.z) > 1e-4) t = min(t, ((dir.z > 0.0 ? arena_half.y : -arena_half.y) - cam_pos.z) / dir.z);
	float d = max(t, 0.05) * max(dot(dir, cam_forward), 0.05);
	vec2 pixel = uv * viewport_size;
	for (int i = 0; i < 5; i++) {
		if (seg_radius[i] <= 0.0) continue;
		if (segment_distance(pixel, seg[i].xy * viewport_size, seg[i].zw * viewport_size) < seg_radius[i]) d = seg_dist[i];
	}
	return d;
}

// Centre of the 3D pixel block this uv falls in: colour and distance are read for the same block.
vec2 block_uv(vec2 uv, vec2 pixel_size) {
	vec2 step_uv = block * pixel_size;
	return (floor(uv / step_uv) + 0.5) * step_uv;
}

float scene_distance(vec2 uv) {
	if (!use_map) return fallback_distance(uv);
	vec3 c = texture(depth_map, uv).rgb;
	highp vec3 digit = clamp(floor((c * 255.0 - 64.0) / 3.0 + 0.5), 0.0, 63.0);
	return map_max * (digit.r / 64.0 + digit.g / 4096.0 + digit.b / 262144.0);
}

// Blur radius of something at distance d (thin lens: grows with |d - focus| / d).
float blur_of(highp float d) {
	float off = max(abs(d - focus_distance) - focus_range, 0.0);
	return blur_radius * clamp(1.5 * off / max(d, 0.05), 0.0, 1.0);
}

void fragment() {
	vec2 here = block_uv(SCREEN_UV, SCREEN_PIXEL_SIZE);
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	highp float centre_d = scene_distance(here);
	float centre_r = blur_of(centre_d);
	float centre_w = 1.0 / (PI_F * pow(max(centre_r, SHARP), 2.0));
	vec3 sum = original * centre_w;
	float weight = centre_w;
	if (blur_radius > 0.25) {
		float ring = blur_radius / float(taps);
		for (int i = 0; i < taps; i++) {
			float r = (float(i) + 0.5) * ring;
			float a = float(i) * 2.39996;
			vec2 uv = block_uv(SCREEN_UV + vec2(cos(a), sin(a)) * r / viewport_size, SCREEN_PIXEL_SIZE);
			highp float d = scene_distance(uv);
			float reach = blur_of(d);
			// Something farther cannot spread over a nearer thing more than that thing is blurred.
			if (d > centre_d) reach = min(reach, centre_r);
			float cover = clamp(reach - r + 0.5, 0.0, 1.0);
			if (cover <= 0.0) continue;
			float w = cover * 2.0 * PI_F * r * ring / (PI_F * pow(max(reach, SHARP), 2.0));
			sum += textureLod(screen_texture, uv, 0.0).rgb * w;
			weight += w;
		}
	}
	COLOR = vec4(sum / weight, 1.0);
}
