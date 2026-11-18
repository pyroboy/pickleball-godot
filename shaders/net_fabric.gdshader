shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;
uniform bool tape = false;
uniform vec4 impacts[4]; // local x, local y, age, signed amplitude
uniform float half_span = 3.3528;
uniform float floor_y = 0.075;
void vertex() {
	float displacement = 0.0;
	// Both posts and the tensioned top/bottom edges remain anchored.
	float anchor = sin(UV.y * 3.14159265) * max(0.0, 1.0 - pow(abs(VERTEX.x) / half_span, 8.0));
	for (int i = 0; i < 4; i++) {
		vec4 hit = impacts[i];
		float distance_from_hit = length(vec2((VERTEX.x - hit.x) * 0.82, (VERTEX.y - hit.y) * 1.4));
		displacement += hit.w * exp(-hit.z * 3.4) * exp(-distance_from_hit * 3.8)
			* sin(hit.z * 22.0 - distance_from_hit * 9.0);
	}
	VERTEX.z += clamp(displacement * anchor, -0.045, 0.045);
}
void fragment() {
	if (tape) {
		ALBEDO = vec3(0.91, 0.94, 0.90);
		ALPHA = 1.0;
	} else {
		// Procedural woven squares; derivatives soften subpixel lines on phones.
		vec2 grid = UV * vec2(167.64, 22.2);
		vec2 cell = abs(fract(grid - 0.5) - 0.5);
		vec2 aa = min(fwidth(grid), vec2(0.48));
		vec2 strand = vec2(1.0) - smoothstep(vec2(0.045) - aa, vec2(0.045) + aa, cell);
		float weave = max(strand.x, strand.y);
		ALBEDO = vec3(0.085, 0.115, 0.135);
		ALPHA = weave * 0.94;
	}
}
