// Hard square billboard for the Limnal effects. Same billboard maths as BILLBOARD_PARTICLES with keep_scale, plus a
// screen-space mask: nothing is drawn near the screen centre (so the pilot can see where they fly) and the effect
// builds toward the borders. The magenta core around the ship is exempt, as on Rodina.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

// Per emitter, in screen heights from the centre: fully clear inside clear_radius, fully visible outside full_radius.
// (A clear_radius below zero means the effect is not masked at all.)
instance uniform float clear_radius = 0.18;
instance uniform float full_radius = 0.6;
instance uniform vec3 tint : source_color = vec3(1.0); // multiplies the colour (pushes the violet toward magenta)

varying float mask;

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = SCREEN_UV - vec2(0.5);
	p.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float m = smoothstep(clear_radius, full_radius, length(p));
	ALBEDO = COLOR.rgb * tint;
	ALPHA = COLOR.a * m;
}
