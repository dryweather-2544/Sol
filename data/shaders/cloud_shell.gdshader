// Sol original: a thin cloud layer on a shell sphere, seen from above it (orbit and high altitude). Procedural: the weather is 3D
// value-noise fbm sampled at the unit direction of each pixel's point on the sphere, so it needs no texture, has no poles or seams,
// and is identical for a planet and its scaled-down distant impostor.
// Lit by the sun with a soft terminator, and self-shadowed by two noise samples taken toward the sun. From inside the layer this shell
// is discarded and fades out near it (the in-atmosphere clouds are a later step).
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled;

uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);   // direction the sunlight travels
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.45, 0.5, 0.6, 1.0); // colour of the underside / self-shadowed parts
uniform float coverage : hint_range(0.0, 1.0) = 0.5;  // 0 = clear, 1 = overcast
uniform float seed = 0.0;                              // per-world offset so every planet has its own weather
uniform float drift = 0.0;                             // slow rotation of the weather, radians
uniform float fade_band = 0.004;                       // shell-units above the shell over which the layer fades out when approached

varying vec3 vertex_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// Cloud density 0..1 at a unit direction: large weather systems modulated by finer structure.
float cloud_density(vec3 direction) {
	float c = cos(drift);
	float s = sin(drift);
	vec3 d = vec3(c * direction.x + s * direction.z, direction.y, -s * direction.x + c * direction.z);
	vec3 p = d * 3.0 + vec3(seed * 17.31, seed * 5.77, seed * 11.13);
	float weather = value_noise(p) * 0.55 + value_noise(p * 2.1) * 0.3 + value_noise(p * 4.3) * 0.15;
	float detail = value_noise(p * 9.0) * 0.5 + value_noise(p * 18.0) * 0.3 + value_noise(p * 37.0) * 0.2;
	float shape = weather * 0.7 + detail * 0.3;
	// Summed value noise clumps around 0.5 (its variance shrinks with every octave), so stretch it: otherwise nearly every point is
	// partly clouded and the layer reads as one flat sheet instead of separate systems with clear sky between them.
	shape = clamp((shape - 0.5) * 2.6 + 0.5, 0.0, 1.0);
	float threshold = 1.0 - coverage;
	return smoothstep(threshold - 0.03, threshold + 0.15, shape);
}

void vertex() {
	vertex_pos = VERTEX;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); // explicit, like the atmosphere shader
}

void fragment() {
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 camera_pos = (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz) / scale; // shell space: the cloud layer is the unit sphere
	float camera_height = length(camera_pos);
	if (camera_height < 1.0 || FRONT_FACING == false) {
		discard; // only the outward-facing side, only from above
	}
	vec3 ray = normalize(vertex_pos - camera_pos);
	// Exact hit on the unit sphere (the mesh is only a coarse cover), nearest point.
	float b = dot(camera_pos, ray);
	float discriminant = b * b - (camera_height * camera_height - 1.0);
	if (discriminant <= 0.0) {
		discard;
	}
	vec3 hit = camera_pos + ray * (-b - sqrt(discriminant));
	vec3 normal = normalize(hit);

	float density = cloud_density(normal);
	if (density <= 0.002) {
		discard;
	}

	vec3 to_sun = -normalize(sun_direction);
	float facing = dot(normal, to_sun);
	float daylight = smoothstep(-0.12, 0.35, facing);

	// Self-shadow: how thick the cloud is a little way toward the sun (about 24 km and 60 km on Aurelia).
	vec3 toward = normalize(to_sun - normal * facing + normal * 0.0001);
	float step_angle = 0.004;
	float thickness_a = cloud_density(normalize(normal + toward * step_angle));
	float thickness_b = cloud_density(normalize(normal + toward * step_angle * 2.5));
	float shadowing = clamp((thickness_a * 0.6 + thickness_b * 0.4) * density * 1.2, 0.0, 1.0);

	vec3 lit = mix(cloud_color.rgb, shadow_color.rgb, shadowing * 0.85);
	vec3 color = lit * (0.04 + 1.15 * daylight);
	// Bright thin edges where the layer is wispy.
	color += cloud_color.rgb * (1.0 - density) * daylight * 0.25;

	float fade = smoothstep(1.0, 1.0 + fade_band, camera_height);
	ALBEDO = color;
	ALPHA = clamp(density * 0.95, 0.0, 1.0) * fade;
}
