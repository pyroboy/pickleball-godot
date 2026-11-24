shader_type spatial;
// Landing ring where the ball bounced (visual only, fx/bounce_decal.gd): a flat ring on
// the court in the zone tint with a 1-render-pixel dark edge outside it. The line is at
// least `line_pixels` render pixels thick and the plane at least `min_pixels` across, so
// it still reads at the far baseline. Plain colours, alpha fade, no glow.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform vec3 edge_color : source_color = vec3(0.02, 0.025, 0.02);
uniform float progress = 0.0;        // 0 at the bounce .. 1 gone
uniform float start_radius = 0.31;   // ring radius at the bounce, fraction of the plane's half size
uniform float end_radius = 0.46;     // room outside for the line and edge where the court is foreshortened
uniform float line_pixels = 1.5;
uniform float min_pixels = 20.0;
varying vec2 local;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float depth = max(-(VIEW_MATRIX * vec4(centre, 1.0)).z, 0.05);
	float px = size * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / depth;   // abs: y-flipped when drawn to a texture
	local = VERTEX.xz;   // -0.5..0.5 on the unit plane, before any growth
	VERTEX.xz *= max(1.0, min_pixels / max(px, 0.001));
}

void fragment() {
	float r = length(local) * 2.0;
	// r per render pixel, larger where the court is foreshortened
	float pix = length(vec2(dFdx(r), dFdy(r)));
	float out_t = 1.0 - progress;
	float ring = mix(start_radius, end_radius, 1.0 - out_t * out_t * out_t);   // quick out, then settles
	float half_line = clamp(pix * line_pixels * 0.5, 0.03, max(0.03, 0.98 - ring - pix));
	float d = r - ring;
	float fade = 1.0 - progress * progress;   // holds, then goes
	if (abs(d) < half_line) {
		ALBEDO = tint.rgb;
		ALPHA = tint.a * fade;
	} else if (d > 0.0 && d < half_line + pix) {
		ALBEDO = edge_color;
		ALPHA = 0.8 * fade;
	} else {
		ALBEDO = edge_color;
		ALPHA = 0.0;
	}
}
