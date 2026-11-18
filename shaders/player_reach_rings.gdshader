shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// A single two-triangle plane. Soft alpha creates the glow on Compatibility
// Android without bloom, lights, textures, depth reads, or extra trajectory work.
uniform float half_extent = 1.4;
uniform float inner_radius = 0.64;
uniform float outer_radius = 1.25;
uniform int active_band = 0;
uniform bool plan_active = false;
uniform vec2 plan_target = vec2(0.0);
uniform vec2 contact_direction = vec2(0.0, -1.0);

float band(float distance_to_ring, float core, float halo) {
	return (1.0 - smoothstep(core, core + 0.01, distance_to_ring)) * 0.72
		+ (1.0 - smoothstep(core, halo, distance_to_ring)) * 0.28;
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * half_extent * 2.0;
	float radius = length(point);
	float inside = band(abs(radius - inner_radius), 0.016, 0.065);
	float outside = band(abs(radius - outer_radius), 0.014, 0.075);
	float toward_contact = smoothstep(0.82, 0.98, dot(point / max(radius, 0.001), contact_direction));
	float inner_opacity = active_band == 1 ? 0.90 : 0.46;
	float outer_opacity = active_band == 2 ? 0.92 : 0.34;
	vec3 cyan = vec3(0.20, 0.83, 1.0);
	vec3 amber = vec3(1.0, 0.72, 0.20);
	vec3 outer_color = active_band == 2 ? amber : cyan;
	float inner_alpha = inside * inner_opacity;
	float outer_alpha = outside * outer_opacity;
	ALBEDO = mix(cyan, outer_color, outer_alpha / max(inner_alpha + outer_alpha, 0.001));
	float arc = active_band == 0 ? 0.0 : toward_contact * (active_band == 2 ? outside : inside);
	ALBEDO = mix(ALBEDO, vec3(1.0), arc * 0.45);
	ALPHA = clamp(max(inner_alpha, outer_alpha) + arc * 0.08, 0.0, 1.0);
	if (plan_active) {
		float length_squared = max(dot(plan_target, plan_target), 0.0001);
		float along = clamp(dot(point, plan_target) / length_squared, 0.0, 1.0);
		float line = 1.0 - smoothstep(0.012, 0.025, length(point - plan_target * along));
		float dash = step(0.40, fract(along * sqrt(length_squared) * 6.0));
		float landing = band(abs(length(point - plan_target) - 0.13), 0.012, 0.035);
		float planned = max(line * dash * 0.70, landing * 0.90);
		ALBEDO = mix(ALBEDO, vec3(0.98, 0.44, 0.95), planned);
		ALPHA = max(ALPHA, planned);
	}
}
