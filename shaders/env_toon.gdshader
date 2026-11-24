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
// multipliers in linear light: the side away from the sun cools toward violet, not black
uniform vec3 mid_band = vec3(0.82, 0.8, 0.88);
uniform vec3 dark_band = vec3(0.6, 0.56, 0.74);
uniform float sway_amount = 0.12;
// distance haze: far houses and trees fade toward a pale sky tone so the court reads first
uniform vec3 haze : source_color = vec3(0.8, 0.85, 0.88);
uniform vec2 haze_range = vec2(26.0, 150.0);
uniform float haze_max = 0.6;
uniform float sway_hz = 8.0;
// Weathering (buildings only, 0 elsewhere): mottled paint, dirt splashed up the base of
// the walls, rain streaks running down, peeling paint showing bare concrete, rust on the
// roofs. Worked out on a 5 cm world grid so it reads as pixels, like the floor.
uniform float grime = 0.0;
uniform vec3 grime_dirt : source_color = vec3(0.45, 0.36, 0.27);
uniform vec3 grime_bare : source_color = vec3(0.62, 0.6, 0.56);
uniform vec3 grime_rust : source_color = vec3(0.55, 0.32, 0.2);

varying vec3 world_normal;
varying vec3 world_pos;
varying vec3 tint;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 weather(vec3 c, vec3 n, vec3 wp) {
	vec3 q = (floor(wp * 20.0) + 0.5) / 20.0;
	float cell = hash(floor(wp.xz * 20.0) + floor(wp.y * 20.0) * 17.0);
	if (abs(n.y) > 0.6) {
		// roofs and ledges: mottling and rust blooms
		float m = vnoise(q.xz * 1.3) + 0.5 * vnoise(q.xz * 4.0);
		if (m > 1.05) c = mix(c, grime_rust, 0.45);
		else if (m < 0.45) c *= 0.9;
		return c;
	}
	// walls: a 2D coordinate along the wall (u) and up it (v)
	float u = abs(n.x) > abs(n.z) ? q.z : q.x;
	float v = q.y;
	float m = vnoise(vec2(u, v) * 0.9) + 0.5 * vnoise(vec2(u, v) * 3.3);
	if (m > 1.1) c *= 0.86;                      // patchy, faded paint
	else if (m < 0.42) c = mix(c, c * 1.08, 0.6);
	// peeling paint: bare concrete with a darker rim
	float peel = vnoise(vec2(u, v) * 3.2 + 7.0) * vnoise(vec2(u, v) * 0.7 + 3.0);
	if (peel > 0.62) c = mix(c, grime_bare, 0.8);
	else if (peel > 0.58) c *= 0.84;
	// rain streaks running down from ledges and window sills
	float col = floor(u * 9.0);
	float streak = vnoise(vec2(col * 1.37, v * 0.7 + hash(vec2(col, 3.0)) * 9.0));
	if (hash(vec2(col, 1.0)) > 0.72 && streak > 0.55) c = mix(c, c * grime_dirt * 1.6, 0.35);
	// dirt splashed up from the ground
	float splash = 0.55 + 0.35 * vnoise(vec2(u * 2.0, 1.0));
	if (v < splash) c = mix(c, grime_dirt, clamp((splash - v) / splash, 0.0, 1.0) * (0.55 + 0.25 * cell));
	if (cell > 0.985) c *= 0.75;                 // specks
	return c;
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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = COLOR.rgb;
}

void fragment() {
	// The renderer hands vertex and instance colours over already in linear light
	// (measured 2026-11-22: converting again crushed every dark colour to black).
	vec3 base = tint;
	// faces are drawn from both sides: light the side the camera sees
	vec3 n = normalize(world_normal);
	if (dot(n, CAMERA_POSITION_WORLD - world_pos) < 0.0) n = -n;
	float d = dot(n, normalize(light_dir));
	vec3 c;
	if (d > 0.5) c = base;
	else if (d > 0.0) c = base * mid_band;
	else c = base * dark_band;
	if (grime > 0.5 && dot(base, vec3(0.333)) > 0.03) c = weather(c, n, world_pos);   // not on dark glass
	c = mix(c, haze, haze_max * smoothstep(haze_range.x, haze_range.y, length(world_pos.xz)));
	ALBEDO = c * gain;
}
