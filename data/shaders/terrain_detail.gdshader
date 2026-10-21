// Sol terrain detail shader — PROTOTYPE (package A3). Original work. Not integrated; the gameplay agent integrates it (I3).
//
// Keeps the game's vertex colour as the MACRO colour (palette by height/latitude, already computed per world on the CPU)
// and multiplies it by a neutral detail albedo, so one texture set serves every world. Blend between a FLAT layer
// (regolith / soil) and a STEEP layer (fractured rock) by the slope weight carried in vertex colour ALPHA.
//
// Inputs from the mesh:   COLOR.rgb = macro colour (LINEAR values, like the game's current vertex colours; convert the
//                         sRGB palette hexes with Color.srgb_to_linear() when writing them),  COLOR.a = steep weight 0..1.
// Per chunk (CPU):        instance uniform tile_offset = fposmod(chunk_origin_in_planet_frame_doubles, TILE_PERIOD) per axis,
//                         TILE_PERIOD = 348 m (a common multiple of every tile size used here: 4, 6 and 29 m).
//                         Vertices stay chunk-local, so float32 never sees planet-scale numbers.
// Cost estimate [E, unmeasured]: up to 2 layers x (albedo 2 scales + normal + ORM) x 3 triplanar projections = 24 texture
//                         reads per pixel inside the fade distance, none beyond it. Measure at 1920x1080 before enabling by default.
shader_type spatial;
render_mode cull_disabled;

const float TILE_PERIOD = 348.0;

uniform sampler2D flat_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D flat_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D flat_orm : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D steep_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D steep_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D steep_orm : repeat_enable, filter_linear_mipmap_anisotropic;

uniform float flat_tile_metres = 4.0;
uniform float steep_tile_metres = 6.0;
uniform float far_tile_metres = 29.0;       // second, larger sampling scale for albedo (breaks visible repetition)
uniform float flat_mean_linear = 0.2148;      // mean LINEAR albedo luminance of each set (printed by check_texture.gd)
uniform float steep_mean_linear = 0.1515;
uniform float fade_start_metres = 80.0;
uniform float fade_end_metres = 250.0;
uniform float normal_strength = 1.0;
uniform float steep_sharpness = 6.0;        // how hard the slope weight is pushed toward 0/1 (rock breaks through dust)
// Visual-style controls (VisualStyle / PlanetLook). Defaults reproduce the original output exactly.
uniform float detail_contrast = 1.0;        // 1 = full detail texture, 0 = vertex colour only
uniform float triplanar_sharpness = 4.0;    // exponent on |normal| for the projection weights
uniform vec3 orbit_color = vec3(0.5);       // the ground hue seen from orbit (linear)
uniform float orbit_mix = 0.0;              // 0 = ground colours, set per frame from the viewer's altitude

instance uniform vec3 tile_offset = vec3(0.0);

varying vec3 local_position;
varying vec3 model_normal;
varying float view_distance;

void vertex() {
	local_position = VERTEX;
	model_normal = NORMAL;
	view_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

vec3 triplanar_weights(vec3 normal) {
	vec3 weights = pow(abs(normal), vec3(triplanar_sharpness));
	return weights / (weights.x + weights.y + weights.z);
}

vec3 sample_triplanar(sampler2D tex, vec3 position, vec3 weights) {
	return texture(tex, position.zy).rgb * weights.x + texture(tex, position.xz).rgb * weights.y + texture(tex, position.xy).rgb * weights.z;
}

// Tangent normal maps are OpenGL (Y+ up in the image). Godot's binormal points against the V axis, so green is flipped
// when mapping onto the (u, v) = (z,y) / (x,z) / (x,y) projections. UDN blend, returns a MODEL-space normal.
vec3 sample_triplanar_normal(sampler2D tex, vec3 position, vec3 normal, vec3 weights, float strength) {
	vec3 tangent_x = texture(tex, position.zy).xyz * 2.0 - 1.0;
	vec3 tangent_y = texture(tex, position.xz).xyz * 2.0 - 1.0;
	vec3 tangent_z = texture(tex, position.xy).xyz * 2.0 - 1.0;
	tangent_x.xy *= vec2(1.0, -1.0) * strength;
	tangent_y.xy *= vec2(1.0, -1.0) * strength;
	tangent_z.xy *= vec2(1.0, -1.0) * strength;
	vec3 from_x = vec3(tangent_x.xy + normal.zy, normal.x);
	vec3 from_y = vec3(tangent_y.xy + normal.xz, normal.y);
	vec3 from_z = vec3(tangent_z.xy + normal.xy, normal.z);
	return normalize(from_x.zyx * weights.x + from_y.xzy * weights.y + from_z.xyz * weights.z);
}

void fragment() {
	float fade = 1.0 - smoothstep(fade_start_metres, fade_end_metres, view_distance);
	vec3 geometric_normal = normalize(model_normal);
	vec3 detail_ratio = vec3(1.0);
	float roughness = 0.95;
	float occlusion = 1.0;
	vec3 shaded_normal = geometric_normal;

	if (fade > 0.001) {
		vec3 weights = triplanar_weights(geometric_normal);
		vec3 position = local_position + tile_offset;
		float steep_weight = clamp((COLOR.a - 0.5) * steep_sharpness + 0.5, 0.0, 1.0);
		vec3 albedo_mix = vec3(0.0);
		vec3 orm_mix = vec3(0.0);
		vec3 normal_mix = vec3(0.0);
		if (steep_weight < 0.999) {
			vec3 near = sample_triplanar(flat_albedo, position / flat_tile_metres, weights) / flat_mean_linear;
			vec3 far = sample_triplanar(flat_albedo, position / far_tile_metres, weights) / flat_mean_linear;
			albedo_mix += (1.0 - steep_weight) * (near * far);
			orm_mix += (1.0 - steep_weight) * sample_triplanar(flat_orm, position / flat_tile_metres, weights);
			normal_mix += (1.0 - steep_weight) * sample_triplanar_normal(flat_normal, position / flat_tile_metres, geometric_normal, weights, normal_strength);
		}
		if (steep_weight > 0.001) {
			vec3 near = sample_triplanar(steep_albedo, position / steep_tile_metres, weights) / steep_mean_linear;
			vec3 far = sample_triplanar(steep_albedo, position / far_tile_metres, weights) / steep_mean_linear;
			albedo_mix += steep_weight * (near * far);
			orm_mix += steep_weight * sample_triplanar(steep_orm, position / steep_tile_metres, weights);
			normal_mix += steep_weight * sample_triplanar_normal(steep_normal, position / steep_tile_metres, geometric_normal, weights, normal_strength);
		}
		detail_ratio = mix(vec3(1.0), clamp(albedo_mix, 0.0, 3.0), fade * detail_contrast);
		occlusion = mix(1.0, orm_mix.r, fade);
		roughness = mix(0.95, orm_mix.g, fade);
		shaded_normal = normalize(mix(geometric_normal, normalize(normal_mix), fade));
	}

	// Ice and snow (bright in every channel, unlike orange or salmon ground) keep their own colour from orbit, so the
	// poles stay white under the orbit tint.
	float bright = smoothstep(0.35, 0.6, min(COLOR.r, min(COLOR.g, COLOR.b)));
	ALBEDO = mix(COLOR.rgb * detail_ratio, orbit_color, orbit_mix * (1.0 - bright));
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.6;
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * shaded_normal));
}
