// Sol original: a thin glowing rim around a planet seen from space. Additive, brighter on the sunlit side.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 rim_color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0); // direction the light travels
uniform float strength = 2.2;
// Rodina (N13): a softer, wider limb (lower power) and a haze of the atmosphere colour over the lit disc, so the whole
// world reads tinted from orbit (screenshots: purple Perun, peach-glowing Jarilo). Defaults are the Sol look.
uniform float rim_power = 6.0;
uniform float disc_haze = 0.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power) + disc_haze;
	float lit = clamp(dot(normalize(world_normal), -normalize(sun_direction)) * 0.9 + 0.35, 0.0, 1.0);
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(rim * lit * strength, 0.0, 1.0);
}
