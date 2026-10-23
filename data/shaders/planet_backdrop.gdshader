shader_type spatial;
// The active planet drawn as a sphere behind everything, only where nothing else was drawn. It fills the sky between the end of the
// terrain (cut by the camera's far plane) and the real horizon. Drawn in the transparent pass with no depth test, it reads the depth
// buffer itself and throws away every pixel that already holds terrain, the ship or the cockpit.
render_mode depth_draw_never, depth_test_disabled, cull_back, blend_mix;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 albedo : source_color = vec4(0.8, 0.55, 0.35, 1.0);
uniform float sky_depth = 100000.0; // view-space distance past which a pixel counts as empty sky (a little under the far plane)

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float linear_depth = -view.z / view.w;
	if (linear_depth < sky_depth) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}
