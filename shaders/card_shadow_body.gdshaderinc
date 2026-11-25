// Body of the player shadow shader, shared by the solid shadow (card_shadow.gdshader) and its
// soft rim under the lens blur (card_shadow_soft.gdshader, which defines SOFT_EDGE first).
uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 light_dir = vec3(-0.46, -0.643, 0.613);   // world, unit, y < 0
uniform float ground_y = 0.075;    // court surface (Ball.FLOOR_Y)
uniform float shadow_y = 0.085;    // drawn this little above it
uniform vec3 shadow_color : source_color = vec3(0.231, 0.227, 0.361);
uniform float opacity = 0.4;
uniform float cast = 1.0;          // 0 = this player casts nothing (first person)
uniform sampler2D shadow_mask : filter_nearest, repeat_disable;
uniform bool has_mask = false;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);   // world x, z of the min corner; size x, z

uniform float tick_blend = 1.0;   // as in pixel_card.gdshader: CUSTOM0 is the corner one tick ago
// Joints: each card is a flat picture turned to the camera and set a little nearer or further
// for draw order, so slid along the sun two cards that meet at a joint can land apart and the
// shadow shows a gap at the knee, elbow or hip. Every card's shadow is therefore made `grow`
// atlas texels longer at both ends (a texel is 2.8 cm), along the part's own length only:
// limbs reach into the next part and close the gap, and nothing gets wider (growing it on all
// sides made the shadows fat).
uniform vec2 atlas_px = vec2(640.0, 440.0);
uniform vec2 cell_uv = vec2(0.0625, 0.0909);
uniform float grow = 0.0;   // extra length at both ends, texels; not needed since the parts meet at their joints
// Lens blur (serve aim, slow motion: scripts/solo_aim_focus.gd through ground_shadows.gd
// `lens_soften`): the lens blurs what is drawn before it, and this shadow is drawn after, so
// it stayed razor sharp on a blurred court. card_shadow_soft.gdshader (this code with
// SOFT_EDGE) adds a soft rim of `soften` texels around the shadow while the lens is on.
uniform float soften = 0.0;
// Motion blur (the players' own blur: pixel_card_body.gdshaderinc): a fast limb's shadow leaves
// a soft trail too. The solid shadow stays as it is; the soft pass adds, behind it along the
// way the part's shadow moved, a trail that is as dark as the share of the exposure the
// shadow covered that spot. `smear` is the blur strength (0 = none).
uniform float smear = 0.0;
const float TRAIL_SHUTTER = 0.5;   // exposure as a share of a tick, as for the cards
const float TRAIL_FROM = 1.0;      // texels of trail before any is drawn
const float TRAIL_MAX = 14.0;
varying vec3 tick_motion;          // the shadow's own move this tick, view space
uniform float true_shape = 1.0;   // 0 = cast by the camera-facing cards themselves (the old, broken joints; for comparison)
varying vec2 world_xz;

void vertex() {
	// CUSTOM2: this corner of the part's true shape (joint to joint, facing the sun) as an
	// offset from the card's corner (pixel_card_rig.gd / pickle_cards.cpp). The card itself is
	// a camera-facing picture, which is why its shadow used to break at the joints.
	VERTEX = mix(CUSTOM0.xyz, VERTEX, tick_blend) + CUSTOM2.xyz * true_shape;
	float k = (VERTEX.y - ground_y) / min(light_dir.y, -1e-3);
	VERTEX = vec3(VERTEX.x - k * light_dir.x, shadow_y, VERTEX.z - k * light_dir.z);
	world_xz = VERTEX.xz;
	// The corner's eased motion per tick (CUSTOM1), slid along the light like the corner itself.
	vec3 move = CUSTOM1.xyz;
	float km = move.y / min(light_dir.y, -1e-3);
	tick_motion = (VIEW_MATRIX * vec4(move.x - km * light_dir.x, 0.0, move.z - km * light_dir.z, 0.0)).xyz;
}

bool casts(vec2 uv, vec2 cell_id) {
	return floor(uv / cell_uv) == cell_id && texture(atlas, uv).a >= 0.5;
}

// The card's shadow at this point: its own art, or art within `reach` texels of it.
bool grown(vec2 uv, float reach) {
	vec2 cell_id = floor(uv / cell_uv);
	if (casts(uv, cell_id)) return true;
	if (reach <= 0.0) return false;
	// The art runs down the cell from the part's joint to its far end: lengthen along that.
	float step_v = reach / atlas_px.y;
	return casts(uv + vec2(0.0, step_v), cell_id) || casts(uv - vec2(0.0, step_v), cell_id)
		|| casts(uv + vec2(0.0, step_v * 0.5), cell_id) || casts(uv - vec2(0.0, step_v * 0.5), cell_id);
}

void fragment() {
	if (cast < 0.5) discard;
	float cover = 1.0;
#ifdef SOFT_EDGE
	// Only outside the solid shadow: the lens rim and the motion trail.
	if ((soften <= 0.0 && smear <= 0.0) || grown(UV, grow)) discard;
	vec2 cell_id = floor(UV / cell_uv);
	cover = 0.0;
	if (soften > 0.0) {
		// How much of a ring `soften` texels out is shadow.
		float hits = 0.0;
		for (int k = 0; k < 8; k++) {
			float turn = float(k) * 0.7853982;
			vec2 at = UV + vec2(cos(turn), sin(turn)) * (0.5 + soften) / atlas_px;
			if (casts(at, cell_id)) hits += 1.0;
		}
		cover = hits / 8.0;
	}
	if (smear > 0.0) {
		// How far the shadow's art moved over this pixel during the exposure, as in the card
		// shader: the share of that path that is shadow is how long this spot was shaded.
		float mx = dFdx(VERTEX.x);
		float my = dFdy(VERTEX.y);
		if (abs(mx) > 1e-7 && abs(my) > 1e-7) {
			vec2 moved = (dFdx(UV) * (tick_motion.x / mx) + dFdy(UV) * (tick_motion.y / my)) * atlas_px;
			float texels = length(moved);
			float trail = min(texels * TRAIL_SHUTTER * smear, TRAIL_MAX);
			if (trail >= TRAIL_FROM) {
				vec2 along = moved / texels / atlas_px;
				float shaded = 0.0;
				for (int k = 0; k < 6; k++) {
					if (casts(UV + along * (trail * (float(k) + 0.5) / 6.0), cell_id)) shaded += 1.0;
				}
				cover = max(cover, shaded / 6.0);
			}
		}
	}
	if (cover < 0.05) discard;
#else
	if (!grown(UV, grow)) discard;
#endif
	float mask = 0.0;
	if (has_mask) {
		vec2 m = (world_xz - mask_rect.xy) / mask_rect.zw;
		if (all(greaterThanEqual(m, vec2(0.0))) && all(lessThanEqual(m, vec2(1.0)))) mask = texture(shadow_mask, m).r;
	}
	float dark = opacity * cover;
	if (mask >= dark - 0.002) discard;
	ALBEDO = mix(vec3(1.0), shadow_color, dark) / mix(vec3(1.0), shadow_color, mask);
}
