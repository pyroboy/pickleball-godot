shader_type canvas_item;
render_mode unshaded;
// Photo mode focus blur (scripts/ui/photo_mode.gd), built on the solo aim slow-motion blur
// (solo_aim_focus.gdshader): a screen-space blur with screen capsules around the players and the
// ball. The renderer gives no depth buffer here, so every pixel gets a distance another way:
//   - players and the ball: their own distance from the camera (inside their capsule);
//   - the court floor: the view ray meets the floor plane;
//   - everything else (stands, buildings, sky): the view ray meets a box around the arena.
// Blur grows with how far that distance is from the focus distance (thin lens: |d - f| / d).
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 viewport_size = vec2(720.0, 1280.0);
uniform float blur_radius = 0.0;          // pixels at full blur; from the aperture
uniform float focus_distance = 8.0;       // m
uniform float focus_range = 0.5;          // m either side kept fully sharp
uniform vec3 cam_pos;
uniform vec3 cam_right;
uniform vec3 cam_up;
uniform vec3 cam_forward;
uniform vec2 tan_half;                    // tan of half the view angle, x and y
uniform float floor_y = 0.075;
uniform vec2 arena_half = vec2(20.0, 24.0);   // m: x and z half size of the backdrop box
uniform vec4 seg[5];                      // start uv (xy), end uv (zw), drawn far to near
uniform float seg_radius[5];              // pixels
uniform float seg_dist[5];                // m from the camera

const int TAPS = 16;

float segment_distance(vec2 pixel, vec2 start, vec2 end) {
	vec2 segment = end - start;
	float along = clamp(dot(pixel - start, segment) / max(dot(segment, segment), 0.001), 0.0, 1.0);
	return length(pixel - start - segment * along);
}

float scene_distance(vec2 uv) {
	vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	vec3 dir = normalize(cam_forward + cam_right * ndc.x * tan_half.x + cam_up * ndc.y * tan_half.y);
	float t = 1e6;
	if (dir.y < -1e-4) t = (floor_y - cam_pos.y) / dir.y;
	// Backdrop box walls.
	if (abs(dir.x) > 1e-4) t = min(t, ((dir.x > 0.0 ? arena_half.x : -arena_half.x) - cam_pos.x) / dir.x);
	if (abs(dir.z) > 1e-4) t = min(t, ((dir.z > 0.0 ? arena_half.y : -arena_half.y) - cam_pos.z) / dir.z);
	// Distance along the view axis, as a lens sees it.
	return max(t, 0.05) * max(dot(dir, cam_forward), 0.05);
}

float coc(float d) {
	float off = max(abs(d - focus_distance) - focus_range, 0.0);
	return clamp(1.5 * off / max(d, 0.05), 0.0, 1.0);
}

void fragment() {
	vec2 pixel = SCREEN_UV * viewport_size;
	float amount = coc(scene_distance(SCREEN_UV));
	for (int i = 0; i < 5; i++) {
		if (seg_radius[i] <= 0.0) continue;
		float d = segment_distance(pixel, seg[i].xy * viewport_size, seg[i].zw * viewport_size);
		float inside = 1.0 - smoothstep(seg_radius[i] * 0.55, seg_radius[i], d);
		amount = mix(amount, coc(seg_dist[i]), inside);
	}
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 color = original;
	float radius = blur_radius * amount;
	if (radius > 0.25) {
		vec3 sum = original;
		for (int i = 0; i < TAPS; i++) {
			float r = sqrt((float(i) + 0.5) / float(TAPS));
			float a = float(i) * 2.39996;
			sum += textureLod(screen_texture, SCREEN_UV + vec2(cos(a), sin(a)) * r * radius / viewport_size, 0.0).rgb;
		}
		color = sum / float(TAPS + 1);
	}
	COLOR = vec4(color, 1.0);
}
