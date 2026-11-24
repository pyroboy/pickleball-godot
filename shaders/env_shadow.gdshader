shader_type spatial;
// Contact shadows on the floor (visual only), one MultiMesh of flat quads.
// INSTANCE_CUSTOM.x: 0 = soft-edged ellipse (figures, chairs), 1 = rectangle (buildings,
// tables). Hard edges, one flat violet-gray tone: pixel-art shadows, no blur.
// Late-afternoon sun: each footprint is swept INSTANCE_CUSTOM.y metres along a fixed world
// direction (`sun_dir`, x/z; the players' blob shadows use the same one), so ellipses
// become capsules and rectangles long slanted blocks. The quad grows in the vertex stage to
// cover the sweep; the fragment tests the exact swept shape in footprint units.
render_mode unshaded, fog_disabled, shadows_disabled, depth_draw_never, blend_mix, cull_disabled;

uniform vec3 shadow_col : source_color = vec3(0.16, 0.13, 0.24);
uniform float strength = 0.38;
uniform vec2 sun_dir = vec2(0.8, 0.35);   // where shadows fall, world x/z
// the background push (env_toon.gdshader): the floor under a far shadow leans toward
// push_col, so the shadow does too (push_col * push_gain is the floor's own albedo scale)
uniform vec3 push_col : source_color = vec3(0.78, 0.76, 0.72);
uniform float push_gain = 2.2;
uniform vec2 court_half = vec2(3.05, 6.705);
uniform vec3 push = vec3(2.0, 7.0, 0.24);

varying float shape;
varying vec2 fp;      // footprint units: the footprint is [-0.5, 0.5] square / 0.5 circle
varying vec2 sweep;   // the sweep in footprint units
varying vec2 world_xz;

void vertex() {
	shape = INSTANCE_CUSTOM.x;
	// world x/z of the quad's local x and y axes (instance basis and the world's turn)
	mat2 m = mat2(MODEL_MATRIX[0].xz, MODEL_MATRIX[1].xz);
	vec2 l = vec2(0.0);
	if (abs(determinant(m)) > 1e-6) l = inverse(m) * (normalize(sun_dir) * INSTANCE_CUSTOM.y);
	vec2 f = VERTEX.xy;
	VERTEX.xy = f + vec2(f.x > 0.0 ? max(l.x, 0.0) : min(l.x, 0.0), f.y > 0.0 ? max(l.y, 0.0) : min(l.y, 0.0));
	fp = VERTEX.xy;
	sweep = l;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	if (shape < 0.5) {
		// capsule: within 0.5 of the segment from the footprint centre along the sweep
		float t = clamp(dot(fp, sweep) / max(dot(sweep, sweep), 1e-6), 0.0, 1.0);
		vec2 d = fp - sweep * t;
		if (dot(d, d) > 0.25) discard;
	} else {
		// the square swept along the segment: some t in [0, 1] has |fp - t * sweep| <= 0.5
		vec2 s = vec2(abs(sweep.x) < 1e-4 ? 1e-4 : sweep.x, abs(sweep.y) < 1e-4 ? 1e-4 : sweep.y);
		vec2 t1 = (fp - 0.5) / s;
		vec2 t2 = (fp + 0.5) / s;
		vec2 tn = min(t1, t2);
		vec2 tx = max(t1, t2);
		if (max(max(tn.x, tn.y), 0.0) > min(min(tx.x, tx.y), 1.0)) discard;
	}
	float k = push.z * smoothstep(push.x, push.y, length(max(abs(world_xz) - court_half, vec2(0.0))));
	ALBEDO = mix(shadow_col, push_col * push_gain, k);
	ALPHA = strength;
}
