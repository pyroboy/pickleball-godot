shader_type spatial;
// Sun shadow of a solid 3D mesh (visual only): the paddle. An extra pass on the mesh's own
// material (scripts/graphics/paddle_skin.gd) that draws the mesh once more with every vertex
// slid along the sun's light down to the court, the same projection as the players' shadow
// (card_shadow.gdshader):
//     x' = x - h * (d.x / d.y), z' = z - h * (d.z / d.y), y' = shadow_y, h = y - ground_y
// so the shadow is the mesh's exact silhouette from the sun and turns with the swing.
// It tests and writes the players' shadow stencil, so where the paddle's shadow lies on a
// player's (the hand's, the arm's) the court is darkened once, not twice. Multiplies the
// ground by lerp(1, shadow_color, opacity), less whatever the baked static shadows already
// applied there. One material for every paddle (scripts/fx/ground_shadows.gd keeps its sun
// and mask current). No TIME.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul, world_vertex_coords;
stencil_mode read, write, compare_not_equal, 64;

uniform vec3 light_dir = vec3(-0.46, -0.643, 0.613);   // world, unit, y < 0
uniform float ground_y = 0.075;
uniform float shadow_y = 0.085;
uniform vec3 shadow_color : source_color = vec3(0.231, 0.227, 0.361);
uniform float opacity = 0.4;
uniform sampler2D shadow_mask : filter_nearest, repeat_disable;
uniform bool has_mask = false;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
varying vec2 world_xz;

void vertex() {
	float k = (VERTEX.y - ground_y) / min(light_dir.y, -1e-3);
	VERTEX = vec3(VERTEX.x - k * light_dir.x, shadow_y, VERTEX.z - k * light_dir.z);
	world_xz = VERTEX.xz;
}

void fragment() {
	float mask = 0.0;
	if (has_mask) {
		vec2 m = (world_xz - mask_rect.xy) / mask_rect.zw;
		if (all(greaterThanEqual(m, vec2(0.0))) && all(lessThanEqual(m, vec2(1.0)))) mask = texture(shadow_mask, m).r;
	}
	if (mask >= opacity - 0.002) discard;
	ALBEDO = mix(vec3(1.0), shadow_color, opacity) / mix(vec3(1.0), shadow_color, mask);
}
