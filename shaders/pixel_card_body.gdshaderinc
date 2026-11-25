// Body of the pixel card shader, shared by its solid pass (pixel_card.gdshader) and its soft
// motion-blur pass (pixel_card_soft.gdshader, which defines SOFT_PASS before including this).

uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D atlas_other : source_color, filter_nearest;
uniform vec2 atlas_px = vec2(640.0, 440.0);
uniform float gain = 1.0;
uniform float accent_mix = 0.0;
uniform vec3 accent_color : source_color = vec3(1.0);
uniform float team_ref_lum = 0.2;
uniform float flash = 0.0;   // 1 = card drawn white (hit flash, rally_moments.gd)
uniform float shading = 0.0;   // 1 = stepped golden-hour sun bands + rim
uniform vec3 to_sun = vec3(-0.809, 0.469, -0.354);   // world, unit (SunLight.to_sun())
// Atlas-space colours (before `gain`; screen ~ (218, 200, 160) warm light, cool violet shade).
uniform vec3 rim_color : source_color = vec3(0.51, 0.38, 0.27);
// Shade band: toward the one shadow colour (SunLight.SHADOW_COLOR #3b3a5c), hue only (its
// brightest channel kept), by shade_mix, then a little darker.
uniform vec3 shadow_color : source_color = vec3(0.231, 0.227, 0.361);
uniform float shade_mix = 0.32;
uniform float shade_dark = 0.94;
uniform float lit_boost = 1.14;
uniform float rim_mix = 0.7;
// Cards built once per physics tick (pixel_card_rig.gd, PerfToggles.card_tick_build): VERTEX is
// this tick's corner, CUSTOM0 the same corner one tick ago, tick_blend the share of the tick
// that has passed (the engine's physics interpolation fraction). 1 = VERTEX as it is.
uniform float tick_blend = 1.0;
// Motion blur (pixel_card_rig.gd, Settings video.motion_smear; 0 = off). The two corners above
// give each part's real motion this tick for free. For a part that moved, every card pixel
// averages BLUR_TAPS reads of the art along the way that part came during the shutter time
// (BLUR_SHUTTER of a tick, times `smear`): what a camera's exposure does. Pixels the part
// covered for the whole exposure stay solid and are drawn here; pixels it covered for part
// of it (both edges of a moving limb) are drawn by the soft pass with that share as their
// opacity (pixel_card_soft.gdshader, same code, alpha blended). Slow parts take the plain
// path below and cost nothing extra.
uniform float smear = 0.0;                        // blur strength: 1 = the shutter below
uniform vec2 cell_uv = vec2(0.0625, 0.0909);      // one atlas cell in UV: a read never leaves the part's own cell
const float BLUR_SHUTTER = 0.5;                   // exposure as a share of a tick (0.5 = 1/60 s)
const float BLUR_EASE = 3.0;                      // texels of blur over which it comes in
const float BLUR_FROM = 0.75;                      // texels of blur before the blur path is taken
const float BLUR_MAX = 14.0;                      // longest blur, texels
const int BLUR_TAPS = 8;
const float DEPTH_STRETCH = 0.7;                  // share of the missing on-screen motion given back to motion in depth
const float DEPTH_STRETCH_MAX = 2.5;              // at most this much longer
const float SUN_BAND = 2.0;
varying vec3 tick_motion;                         // this corner's move this tick, view space, metres

void vertex() {
	tick_motion = (VIEW_MATRIX * MODEL_MATRIX * vec4(CUSTOM1.xyz, 0.0)).xyz;   // eased joint motion (pixel_card_rig.gd / pickle_cards.cpp)
	// Stretch blur: motion toward or away from the camera hardly crosses the screen, so a part
	// running into the court would barely blur. Its on-screen motion is lengthened toward what
	// the same speed would show sideways (direction unchanged), by DEPTH_STRETCH of the way.
	float across = length(tick_motion.xy);
	if (across > 1e-5) tick_motion.xy *= mix(1.0, min(length(tick_motion) / across, DEPTH_STRETCH_MAX), DEPTH_STRETCH);
	VERTEX = mix(CUSTOM0.xyz, VERTEX, tick_blend);
}
const float SHADE_BAND = 3.0;

vec3 accent(vec3 rgb, vec2 uv) {
	if (accent_mix > 0.5) {
		vec3 o = texture(atlas_other, uv).rgb;
		float hi = max(rgb.r, max(rgb.g, rgb.b));
		float sat = (hi - min(rgb.r, min(rgb.g, rgb.b))) / max(hi, 0.001);
		if (distance(rgb, o) > 0.02 && sat > 0.25) {
			float shade = dot(rgb, vec3(0.2126, 0.7152, 0.0722)) / team_ref_lum;
			rgb = accent_color * clamp(shade, 0.25, 1.0);
		}
	}
	return rgb;
}

void fragment() {
	vec2 uv = UV;
	vec4 c = texture(atlas, uv);
	// How far the art moved over this pixel during the exposure, in atlas texels.
	float blur_len = 0.0;
	vec2 blur_dir = vec2(0.0);
	if (smear > 0.0) {
		float mx = dFdx(VERTEX.x);
		float my = dFdy(VERTEX.y);
		if (abs(mx) > 1e-7 && abs(my) > 1e-7) {
			vec2 moved = (dFdx(uv) * (tick_motion.x / mx) + dFdy(uv) * (tick_motion.y / my)) * atlas_px;   // texels this tick
			float texels = length(moved);
			if (texels > 1e-4) {
				blur_len = min(texels * BLUR_SHUTTER * smear, BLUR_MAX);
				blur_dir = moved / texels / atlas_px;   // one texel along the motion, in UV
			}
		}
	}
	float solid = c.a >= 0.5 ? 1.0 : 0.0;
	vec3 rgb = vec3(0.0);
	if (solid > 0.5) {
	rgb = accent(c.rgb, uv);
	if (shading > 0.5) {
		// Sun direction on screen, in the sign convention of this renderer's derivatives.
		vec3 sv = (VIEW_MATRIX * vec4(to_sun, 0.0)).xyz;
		vec2 s = vec2(sv.x * sign(dFdx(VERTEX.x) + 1e-9), sv.y * sign(dFdy(VERTEX.y) + 1e-9));
		if (dot(s, s) > 1e-6) {
			s = normalize(s);
			vec2 px_uv = dFdx(uv) * s.x + dFdy(uv) * s.y;   // one render pixel toward the sun, in UV
			vec2 tex_dir = px_uv * atlas_px;
			float tl = length(tex_dir);
			if (tl > 1e-6) {
				vec2 t_uv = tex_dir / tl / atlas_px;   // one atlas texel toward the sun, in UV
				bool rim = texture(atlas, uv + px_uv).a < 0.5;
				bool lit = texture(atlas, uv + t_uv * SUN_BAND).a < 0.5 || texture(atlas, uv + t_uv).a < 0.5;
				bool shade = texture(atlas, uv - t_uv * SHADE_BAND).a < 0.5;
				// Sun behind the drawn face (toward the camera's far side): the whole card leans to shade.
				float front = sv.z;
				if (rim) rgb = mix(rgb, rim_color, rim_mix);
				else if (lit) rgb = rgb * lit_boost;
				else if (shade || front < -0.35) rgb = rgb * mix(vec3(1.0), shadow_color / max(shadow_color.b, 1e-3), shade_mix) * shade_dark;
			}
		}
	}
	}
	// The blur eases in over BLUR_EASE texels: from the sharp, sun-shaded pixel to the exposure's
	// average, in colour and in coverage, so a part crossing the threshold does not switch looks.
	float alpha = solid;
	if (blur_len >= BLUR_FROM) {
		// The part was here earlier in the exposure wherever the art further along its motion is solid.
		vec2 cell_id = floor(uv / cell_uv);
		vec3 sum = vec3(0.0);
		float covered = 0.0;
		for (int k = 0; k < BLUR_TAPS; k++) {
			vec2 at = uv + blur_dir * (blur_len * (float(k) + 0.5) / float(BLUR_TAPS));
			if (floor(at / cell_uv) != cell_id) continue;
			vec4 tap = texture(atlas, at);
			if (tap.a >= 0.5) {
				sum += accent(tap.rgb, at);
				covered += 1.0;
			}
		}
		float share = covered / float(BLUR_TAPS);
		float w = smoothstep(BLUR_FROM, BLUR_FROM + BLUR_EASE, blur_len);
		float sharp_part = solid * (1.0 - w);
		float blur_part = share * w;
		alpha = sharp_part + blur_part;
		if (alpha > 0.001) rgb = (rgb * sharp_part + (covered > 0.0 ? sum / covered : rgb) * blur_part) / alpha;
	}
#ifdef SOFT_PASS
	if (alpha <= 0.004 || alpha >= 0.999) discard;
	ALBEDO = mix(rgb * gain, vec3(1.0), flash);
	ALPHA = alpha;
#else
	if (alpha < 0.999) discard;
	ALBEDO = mix(rgb * gain, vec3(1.0), flash);
#endif
}
