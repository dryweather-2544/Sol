// The star's halo (Sol's own): a camera-facing quad, additive, centred on the star and pushed just behind it so the star's
// disc covers the middle. Only a soft, smooth falloff of scattered light round the disc, like a real star seen from space.
// The quad reaches `reach` star radii from its centre.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float reach = 4.0;
uniform vec3 inner_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 outer_color : source_color = vec3(1.0, 0.55, 0.22);
uniform float strength = 1.0;

varying vec2 quad_uv;

void vertex() {
	quad_uv = UV * 2.0 - 1.0;
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	float dist = max(length(cam - centre), 1.0);
	vec3 to_cam = (cam - centre) / dist;
	// Through the star's centre (a hair behind): the disc's visible surface is all nearer than that, so the disc still covers
	// the middle. Pushing it back a whole radius put the quad beyond the camera's far plane when the star is close, and it
	// popped in and out as the view turned.
	float push = radius * 0.02;
	vec3 pushed = centre - to_cam * push;
	float perspective = (dist + push) / dist; // keep the apparent size
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(pushed, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(vec4(radius * perspective, 0.0, 0.0, 0.0), vec4(0.0, radius * perspective, 0.0, 0.0), vec4(0.0, 0.0, radius * perspective, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// A soft, smooth halo of scattered light close round the disc: no streamers, rays or rings.
	float r = length(quad_uv) * reach; // in star radii
	float near_glow = exp(-(r - 1.0) * 5.0) * 0.8;
	float far_glow = exp(-(r - 1.0) * 1.3) * 0.07;
	float halo = (near_glow + far_glow) * smoothstep(0.985, 1.02, r);
	float fade = 1.0 - smoothstep(0.8, 1.0, length(quad_uv)); // the quad's edge is never visible
	vec3 colour = mix(inner_color, outer_color, clamp((r - 1.0) / 2.0, 0.0, 1.0));
	ALBEDO = colour * halo * strength * fade;
}
