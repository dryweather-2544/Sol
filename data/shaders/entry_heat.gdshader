// Sol original: atmospheric-entry heat sheath round the ship's nose (ShipEffects, rodina visual style only). Additive,
// strongest at grazing angles and on the forward (-z) side, fading in with `heat`.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform float heat : hint_range(0.0, 1.0) = 0.0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float forward = smoothstep(0.6, -0.9, model_position.z); // brightest at the nose (model -z)
	vec3 hot = mix(vec3(1.0, 0.35, 0.08), vec3(1.0, 0.85, 0.6), heat);
	ALBEDO = hot;
	ALPHA = clamp(rim * forward * heat * 1.6, 0.0, 1.0);
}
