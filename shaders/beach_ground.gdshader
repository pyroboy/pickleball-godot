shader_type spatial;
// Beach ground (visual only): packed sand inside the fence, dry sand with grain and
// wind ripples, wet sand, a foam line that washes up and back, shallow-to-deep water
// with wave lines and sparkles, hazing out toward the horizon. Everything is worked
// out on a 5 cm world grid so it matches the sprites' pixels. Colours are uniforms
// filled from assets/beach/beach_meta.json "palette" (tonemap-compensated).
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 sand : source_color;
uniform vec3 sand_dk : source_color;
uniform vec3 sand_lt : source_color;
uniform vec3 wet : source_color;
uniform vec3 wet_dk : source_color;
uniform vec3 foam : source_color;
uniform vec3 shallow : source_color;
uniform vec3 water : source_color;
uniform vec3 deep : source_color;
uniform vec3 deeper : source_color;
uniform vec3 haze : source_color;
uniform vec3 pad : source_color;
uniform vec3 pad_dk : source_color;
uniform vec3 curb : source_color;
uniform float gain = 2.2;
uniform float grid = 20.0;          // cells per metre
uniform float shore_z = -18.6;      // mean waterline (local z; ocean toward -z)
uniform vec2 pad_half = vec2(5.9, 9.8);        // packed area inside the fence
uniform vec2 court_half = vec2(3.35, 7.0);     // court surface half size (CourtSurface)

varying vec2 local;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void vertex() {
	local = VERTEX.xz;
}

void fragment() {
	vec2 cell = floor(local * grid);
	vec2 p = (cell + 0.5) / grid;
	float n = hash(cell);
	float t = TIME;
	float shore = shore_z + 0.7 * sin(p.x * 0.09) + 0.4 * sin(p.x * 0.23 + 1.3);
	// the wash: water runs up the beach and slides back every ~14 s
	float wash = 1.1 * (0.5 + 0.5 * sin(t * 0.45 + 0.6 * sin(p.x * 0.05)));
	float edge = shore + wash;
	float d = edge - p.y;                // > 0 in the water
	vec3 c;
	if (d > 0.0) {
		float depth = shore - p.y;
		c = depth < 1.2 ? mix(wet, shallow, 0.65) : depth < 5.0 ? shallow : depth < 16.0 ? water : depth < 40.0 ? deep : deeper;
		// wave lines rolling in
		float wl = (depth + t * 0.9 + 0.6 * sin(p.x * 0.3 + t * 0.4)) / 6.0;
		if (depth > 1.5 && depth < 45.0 && fract(wl) < 0.045 && n > 0.3) c = mix(c, foam, 0.55);
		// foam at the leading edge of the wash, broken up
		if (d < 0.22 + 0.12 * n) c = foam;
		else if (d < 0.5 && n > 0.6) c = mix(c, foam, 0.6);
		// sun sparkles
		if (depth > 3.0 && hash(cell + floor(t * 2.5)) > 0.9965) c = foam;
		c = mix(c, haze, smoothstep(70.0, 220.0, -p.y));
	} else {
		float inland = -d;
		float wet_band = shore + 2.4 - p.y;   // > 0 on wet sand (above the mean line)
		if (wet_band > 0.0 && p.y < edge + 2.4) {
			c = wet;
			if (n > 0.92) c = wet_dk;
			// the last wash leaves a darker damp strip that dries out
			if (p.y < shore + 1.1 + 0.3 * n) c = mix(c, wet_dk, 0.5);
		} else {
			c = sand;
			if (n > 0.93) c = sand_dk;
			else if (n < 0.05) c = sand_lt;
			float ripple = sin(p.y * 2.4 + sin(p.x * 0.45) * 1.6 + p.x * 0.15);
			if (ripple > 0.93) c = mix(c, sand_dk, 0.6);
		}
		vec2 a = abs(p);
		if (a.x < pad_half.x && a.y < pad_half.y) {
			c = n > 0.96 ? pad_dk : pad;
			vec2 ring = a - court_half;
			if (max(ring.x, ring.y) > 0.0 && max(ring.x, ring.y) < 0.22) c = curb;
		}
		// soft sand drift against the pad edge
		vec2 outside = a - pad_half;
		if (max(outside.x, outside.y) > 0.0 && max(outside.x, outside.y) < 0.12 + 0.2 * n) c = sand_lt;
	}
	ALBEDO = c * gain;
}
