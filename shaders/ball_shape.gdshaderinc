// Drawn shape of the in-game ball (visual only), shared by its body (ball_body.gdshader)
// and its dark outline (ball_readability.gdshader); scripts/ball.gd sets the uniforms.
// The mesh is the visual sphere (bigger than the physics sphere, which nothing here
// touches). Sizes are in 3D render pixels (VIEWPORT_SIZE is the 1/3-scale render, see
// scripts/graphics/pixel_post.gd):
// - the body never drops below `min_pixels` across, so the far-court ball keeps a shape;
// - the outline adds `outline_pixels` all round;
// - the whole shape, outline included, is lifted to stay above `floor_y`, so a bounce
//   never sinks the bigger ball (or its outline) into the court.

uniform float radius = 0.05625;        // mesh radius, metres
uniform float min_pixels = 3.0;        // smallest body diameter on screen, render pixels
uniform float outline_pixels = 1.0;    // outline width, render pixels
uniform float floor_y = 0.081;         // lowest point of the drawn shape, world y
// Motion blur (scripts/fx/ball_trail.gd sets `motion` every frame; zero = a round ball): the
// way the ball came during the exposure, world metres. In flight the ball itself is an oblong:
// body and outline are lengthened back along `motion` into an ellipsoid whose front tip is the
// real ball's front (`stretched`, `lengthen` 1). Behind it a third pass (ball_soft.gdshader)
// draws the same shape lengthened further (`lengthen` over 1): the blur's tail, see-through,
// fading in a straight line along the flight. The outline (ball_readability.gdshader) is left
// open at the rear, where the ball runs into that tail.
uniform vec3 motion = vec3(0.0);
varying float tail;

// Model-space vertex of the drawn ball; `outline` grows it by the outline width. `along` is
// what the caller's vertex() stores in `tail` (a varying can only be set there).
vec3 ball_vertex(vec3 vertex, mat4 model, mat4 view, mat4 proj, vec2 viewport, bool outline, bool stretched, float lengthen, out float along) {
	vec3 centre = model[3].xyz;
	float depth = max(-(view * vec4(centre, 1.0)).z, 0.05);
	// abs: the Compatibility renderer flips y in the projection when drawing to a texture
	float body_px = max(2.0 * radius * abs(proj[1][1]) * viewport.y * 0.5 / depth, 0.001);
	float body = max(1.0, min_pixels / body_px);
	float outer = body + 2.0 * outline_pixels / body_px;
	float lift = max(0.0, floor_y + radius * outer - centre.y);
	mat3 to_model = inverse(mat3(model));
	vec3 drawn = vertex * (outline ? outer : body) + to_model * vec3(0.0, lift, 0.0);
	along = 0.0;
	float travelled = length(motion) * lengthen;
	if (stretched && travelled > 0.0005) {
		// Each point moves back by half the length at the middle, none at the front tip and all
		// of it at the rear tip: a sphere becomes an ellipsoid.
		vec3 flight = normalize(motion);
		float rear = -dot(normalize(mat3(model) * vertex), flight);
		vec3 back = -flight * travelled * 0.5 * (1.0 + rear);
		// never under the court: lifted like the ball itself
		back.y = max(back.y, floor_y + radius * outer - (centre.y + lift));
		drawn += to_model * back;
		along = 0.5 * (1.0 + rear);
	}
	return drawn;
}
