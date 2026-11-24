shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Player ground blob (visual only). fx/ground_shadows.gd stretches it `stretch` times along
// its local +x (the late-afternoon sun's shadow direction), keeping its back edge at the
// feet; `feet_x` is where the feet sit on the unit plane (-0.5..0.5, 0 = centred).
uniform float opacity : hint_range(0.0, 1.0) = 0.22;
uniform float stretch = 1.0;
uniform float feet_x = 0.0;
varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

void fragment() {
	float radius = length(local * 2.0);
	// Soft penumbra plus a tighter, darker core under the feet so a player reads as planted.
	float soft_edge = 1.0 - smoothstep(0.12, 1.0, radius);
	float core = 1.0 - smoothstep(0.0, 0.55, length(vec2((local.x - feet_x) * 2.0 * stretch, local.y * 2.0)));
	// lighter toward the far end, like a long shadow
	float tail = mix(1.0, 0.6, smoothstep(feet_x, 0.5, local.x));
	ALBEDO = vec3(0.025, 0.04, 0.065);
	ALPHA = clamp(soft_edge * 0.75 * tail + core * 0.35, 0.0, 1.0) * opacity;
}
