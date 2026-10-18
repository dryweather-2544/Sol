// Sol original: a thin glowing rim around a planet seen from space. Additive, brighter on the sunlit side.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 rim_color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0); // direction the light travels
uniform float strength = 2.2;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 6.0);
	float lit = clamp(dot(normalize(world_normal), -normalize(sun_direction)) * 0.9 + 0.35, 0.0, 1.0);
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(rim * lit * strength, 0.0, 1.0);
}
