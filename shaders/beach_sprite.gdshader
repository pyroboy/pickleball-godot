shader_type spatial;
// Beach world sprites (visual only), drawn from one MultiMesh per mode.
// Per instance: transform = position + sprite size in metres (basis scale),
// CUSTOM = atlas rect (u0, v0, width, height; negative width = mirrored),
// COLOR.r = sway amount (palms), COLOR.g = sway phase.
// Colours are pre-compensated for the Filmic tonemap like the player cards
// (tools/bake_beach_sprites.py), so draw unshaded with the cards' gain.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque, shadows_disabled, skip_vertex_transform;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float gain = 2.2;
// 1 = stand upright and turn about the vertical axis to face the camera;
// 0 = keep the instance's own orientation (ground decals, bunting).
uniform float billboard = 1.0;
uniform float alpha_cut = 0.5;

varying vec4 rect;

void vertex() {
	rect = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 world;
	float h = VERTEX.y;   // 0 at the feet, 1 at the top (QuadMesh centre offset 0.5)
	if (billboard > 0.5) {
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		right = normalize(vec3(right.x, 0.0, right.z) + vec3(1e-5, 0.0, 0.0));
		float sway = COLOR.r * sin(TIME * (0.9 + 0.35 * COLOR.g) + COLOR.g * 6.2832)
			+ COLOR.r * 0.35 * sin(TIME * 2.3 + COLOR.g * 11.0);
		world = origin + right * (VERTEX.x * sx + sway * h * h) + vec3(0.0, 1.0, 0.0) * (VERTEX.y * sy);
		// nudge toward the camera so a sprite standing on a flat decal never z-fights it
		world += normalize(INV_VIEW_MATRIX[3].xyz - world) * 0.02;
	} else {
		world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float u = rect.z < 0.0 ? 1.0 - UV.x : UV.x;
	vec2 uv = rect.xy + vec2(u * abs(rect.z), UV.y * rect.w);
	vec4 c = texture(atlas, uv);
	if (c.a < alpha_cut) discard;
	ALBEDO = c.rgb * gain;
}
