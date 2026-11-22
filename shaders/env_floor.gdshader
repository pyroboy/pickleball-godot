shader_type spatial;
// Barangay court floor (visual only), used by the big ground plane and by CourtSurface so
// the two meet without a seam: a gray cement slab (15 x 28 m) with hairline cracks,
// darker patched squares and old water stains near the edges; faded yellow basketball
// lines under everything; the kitchen tinted faded green; a drainage gutter along one
// side; packed dirt with weeds beyond. The bright pickleball lines are their own mesh on
// top (court.gd CourtLines) and stay the clearest thing on the floor.
// Worked out on a 5 cm world grid so the pattern matches the pixel look. `flip` follows
// the camera's half turn after a change of ends so the far end always looks the same.
// Colours are tonemap-compensated (scripts/environment/env_palette.gd).
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 cement : source_color;
uniform vec3 cement_dk : source_color;
uniform vec3 cement_lt : source_color;
uniform vec3 patch_col : source_color;
uniform vec3 crack : source_color;
uniform vec3 stain : source_color;
uniform vec3 bball : source_color;
uniform vec3 kitchen : source_color;
uniform vec3 gutter : source_color;
uniform vec3 grate : source_color;
uniform vec3 dirt : source_color;
uniform vec3 dirt_dk : source_color;
uniform vec3 dirt_lt : source_color;
uniform vec3 grass : source_color;
uniform vec3 grass_dk : source_color;
uniform float gain = 2.2;
uniform float flip = 1.0;
uniform float grid = 20.0;
uniform vec2 slab_half = vec2(7.5, 14.0);
uniform vec2 kitchen_half = vec2(3.05, 2.134);
uniform vec2 gutter_x = vec2(7.78, 8.14);

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.31));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// distance to the nearest Voronoi cell edge (cells ~1.4 m): hairline crack network
float crack_edge(vec2 p) {
	vec2 q = p / 1.4;
	vec2 i = floor(q);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 o = c + hash2(c);
			float d = length(q - o);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return (d2 - d1) * 1.4;
}

float ring(float d, float w) {
	return step(abs(d), w);
}

// faded basketball markings: 1 on a line, 0 off
// The old basketball court, scaled with the slab (cut to 80 %): a full-size layout
// (15 x 28 m) shrunk so its boundary sits just inside the new slab edge, like the
// undersized courts painted on most barangay slabs. Line width stays 6 cm.
uniform float bball_scale = 0.796;

float bball_lines(vec2 p_world) {
	vec2 p = p_world / bball_scale;
	vec2 a = abs(p);
	float w = 0.03 / bball_scale;
	float on = 0.0;
	on = max(on, ring(a.x - 7.35, w) * step(a.y, 13.85));
	on = max(on, ring(a.y - 13.85, w) * step(a.x, 7.35));
	on = max(on, ring(p.y, w) * step(a.x, 7.35));                       // half-court line
	on = max(on, ring(length(p) - 1.8, w));                              // centre circle
	on = max(on, ring(a.x - 2.45, w) * step(8.1, a.y) * step(a.y, 13.85)); // key sides
	on = max(on, ring(a.y - 8.1, w) * step(a.x, 2.45));                  // free-throw line
	on = max(on, ring(length(vec2(a.x, a.y - 8.1)) - 1.8, w) * step(a.y, 8.1));
	float basket = 12.275;
	float arc_end = basket - sqrt(6.75 * 6.75 - 6.6 * 6.6);
	on = max(on, ring(length(vec2(a.x, a.y - basket)) - 6.75, w) * step(a.y, arc_end));
	on = max(on, ring(a.x - 6.6, w) * step(arc_end, a.y) * step(a.y, 13.85));
	return on;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p0 = world_pos.xz * flip;
	vec2 cell = floor(p0 * grid);
	vec2 p = (cell + 0.5) / grid;
	float n = hash(cell);
	vec2 a = abs(p);
	vec3 c;
	if (a.x < slab_half.x && a.y < slab_half.y) {
		// cement: two-tone mottling plus grain
		float m = vnoise(p * 0.7) + 0.5 * vnoise(p * 2.3);
		c = m > 0.95 ? cement_lt : (m < 0.55 ? cement_dk : cement);
		if (n > 0.95) c = cement_dk;
		else if (n < 0.03) c = cement_lt;
		// patched squares (2.5 m grid), crisp edges
		vec2 pc = floor(p / 2.5);
		float ph = hash(pc + 7.0);
		if (ph > 0.84) {
			vec2 local = p - pc * 2.5;
			vec2 lo = 0.3 + hash2(pc) * 0.6;
			vec2 hi = lo + 0.5 + hash2(pc + 3.0) * 0.8;
			if (all(greaterThan(local, lo)) && all(lessThan(local, hi))) c = n > 0.9 ? cement_dk : patch_col;
		}
		// water stains near the slab edge: blotches with a lighter tide mark
		float edge = min(slab_half.x - a.x, slab_half.y - a.y);
		if (edge < 2.6) {
			float s = vnoise(p * 0.9 + 4.0) - edge * 0.12;
			if (s > 0.55) c = mix(c, stain, 0.7);
			else if (s > 0.52) c = mix(c, cement_lt, 0.5);
		}
		// kitchen: faded green, worn in spots
		if (a.x < kitchen_half.x && a.y < kitchen_half.y) {
			float wear = vnoise(p * 1.7 + 11.0);
			c = mix(c, kitchen, wear > 0.25 ? 0.75 : 0.35);
		}
		// faded basketball lines with worn gaps
		if (bball_lines(p) > 0.5 && vnoise(p * 3.1) > 0.28 && n > 0.12) c = mix(c, bball, 0.7);
		// hairline cracks: a few long runs where a low-frequency mask allows, thinned so
		// they read as hairlines, kept faint inside the pickleball court
		float in_court = step(a.x, 3.4) * step(a.y, 7.0);
		if (crack_edge(p) < 0.022 && vnoise(p * 0.3 + 2.0) > 0.7 + 0.08 * in_court && n > 0.15)
			c = mix(c, crack, 0.75 - 0.3 * in_court);
	} else if (p.x > gutter_x.x && p.x < gutter_x.y && a.y < slab_half.y + 0.3) {
		c = fract(p.y / 0.2) < 0.25 ? grate : gutter;
	} else {
		c = dirt;
		if (n > 0.9) c = dirt_dk;
		else if (n < 0.06) c = dirt_lt;
		float g = vnoise(p * 0.55 + 31.0) + 0.35 * vnoise(p * 3.0);
		float near = max(a.x - slab_half.x, a.y - slab_half.y);
		if (g > 1.0 - clamp(near * 0.04, 0.0, 0.25)) c = n > 0.5 ? grass : grass_dk;
	}
	ALBEDO = c * gain;
}
