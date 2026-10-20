// Sol original: a deliberately simple, two-colour atmospheric limb for the Rodina presentation
// profile. This is not a Rayleigh/Mie integral; it matches the recovered Rodina atmosphere filter
// (a hue blend between two authored colours) and the released screenshots' thin coloured limb.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 horizon_color : source_color = vec4(0.78, 0.53, 0.46, 1.0);
uniform vec4 zenith_color : source_color = vec4(0.10, 0.20, 0.24, 1.0);
uniform vec4 sun_color : source_color = vec4(0.35, 0.92, 0.92, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);
uniform float strength = 0.60;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// A soft but clearly coloured edge. The reference has a thin limb rather than a white halo.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 14.0);
	float lit = clamp(dot(normalize(world_normal), -normalize(sun_direction)) * 0.55 + 0.45, 0.0, 1.0);
	vec3 color = mix(zenith_color.rgb, horizon_color.rgb, 0.30 + 0.55 * lit);
	color = mix(color, sun_color.rgb, pow(max(dot(normalize(world_normal), -normalize(sun_direction)), 0.0), 8.0) * 0.35);
	ALBEDO = color;
	ALPHA = clamp(rim * strength * (0.70 + 0.30 * lit), 0.0, 0.95);
}
