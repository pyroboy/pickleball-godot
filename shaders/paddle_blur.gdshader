shader_type spatial;
// Motion blur of the paddle (visual only; scripts/graphics/paddle_skin.gd). The paddle's parts
// are drawn once more with this shader. Every vertex on the trailing side of the part (the
// side it is moving away from) is put back where it was at the start of the exposure, using
// the part's whole earlier transform, so turning and travelling are both followed. The faces
// between the leading and trailing vertices then span exactly the space the part swept
// through. They are drawn see-through, strongest at the paddle and fading to nothing at the
// start of the sweep: one continuous streak, not copies. Faces that did not stretch are not
// drawn, so a paddle at rest costs no pixels.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform bool has_tex = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float rough = 0.7;
uniform mat4 before = mat4(1.0);   // this part's world transform at the start of the exposure
uniform vec3 centre = vec3(0.0);   // the part's middle now, world
uniform float strength = 0.55;     // opacity right behind the paddle
varying float tail;

void vertex() {
	vec3 now = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 was = (before * vec4(VERTEX, 1.0)).xyz;
	vec3 moved = now - was;
	tail = 0.0;
	if (dot(moved, moved) > 1e-8 && dot(now - centre, moved) < 0.0) {
		tail = 1.0;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(was, 1.0)).xyz;
	}
}

void fragment() {
	if (tail <= 0.01) discard;
	vec4 c = has_tex ? texture(tex, UV) * tint : tint;
	float fade = 1.0 - tail;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	ALPHA = strength * fade * sqrt(fade);
}
