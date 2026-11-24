shader_type spatial;
// Main-menu pickleball (visual only): a neon yellow-green ball with 40 drilled holes,
// drawn with the same three flat bands as the environment (no glow) and a dark hole
// interior with a lit lip. Holes are worked out in the ball's own space, so they turn
// with it. Rendered at half resolution, so the edges read as pixels.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 dark : source_color = vec3(0.06, 0.56, 0.24);
uniform vec3 mid : source_color = vec3(0.17, 0.94, 0.42);
uniform vec3 light : source_color = vec3(0.66, 1.0, 0.72);
uniform vec3 rim_col : source_color = vec3(0.9, 1.0, 0.85);
uniform vec3 hole_col : source_color = vec3(0.02, 0.24, 0.1);
uniform vec3 lip_col : source_color = vec3(0.07, 0.65, 0.27);
uniform vec3 sun = vec3(-0.55, 0.65, 0.52);
uniform float hole_r = 0.17;
uniform float gain = 1.0;

varying vec3 obj_n;
varying vec3 world_n;

void vertex() {
	obj_n = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 hole_dir(int i) {
	float golden = 3.14159265 * (3.0 - sqrt(5.0));
	float y = 1.0 - 2.0 * (float(i) + 0.5) / 40.0;
	float r = sqrt(1.0 - y * y);
	float a = golden * float(i);
	return vec3(cos(a) * r, y, sin(a) * r);
}

void fragment() {
	vec3 n = normalize(world_n);
	vec3 l = normalize(sun);
	float lam = max(dot(n, l), 0.0);
	float best = -1.0;
	vec3 hc = vec3(0.0);
	for (int i = 0; i < 40; i++) {
		vec3 h = hole_dir(i);
		float d = dot(obj_n, h);
		if (d > best) { best = d; hc = h; }
	}
	float ang = acos(clamp(best, -1.0, 1.0));
	vec3 col;
	if (ang < hole_r) {
		// lit lip on the hole side facing away from the sun
		vec3 hw = normalize((MODEL_MATRIX * vec4(hc, 0.0)).xyz);
		vec3 to_c = hw - n * dot(n, hw);
		col = (dot(to_c, l) < -0.02 && ang > hole_r * 0.55) ? lip_col : hole_col;
	} else {
		col = lam < 0.3 ? dark : (lam < 0.72 ? mid : light);
		if (lam > 0.985) col = rim_col;

	}
	ALBEDO = col * gain;
}
