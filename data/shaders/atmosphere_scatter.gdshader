// Atmospheric scattering on a shell sphere, orbit to ground. Rayleigh + Mie single scattering after Sean O'Neil, "Accurate Atmospheric
// Scattering" (GPU Gems 2, 2004), via the Godot port in Cuberact's planet project (MIT licence, see ATTRIBUTION.md):
//   https://github.com/cuberact/godot-cuberact-planet-chunked-lod  (shaders/atmosphere.gdshader)
//   Original: Copyright (c) 2004 Sean O'Neil. Godot adaptation: Cuberact (MIT).
// Changes for Sol (6000 km planets, floating origin, impostor planets at any scale):
//   * Everything is normalised so the shell (the atmosphere's outer edge) is a unit sphere: no kilometre or metre units reach the maths,
//     so a planet and its scaled-down distant impostor render identically.
//   * Camera position is derived from CAMERA_POSITION_WORLD and the node's model matrix, so no per-frame camera plumbing is needed.
//   * The mesh only supplies coverage. Where the ray enters or leaves the atmosphere, and where it hits the planet, are found
//     analytically, so the shell's facets do not show and planet disks get haze in front of them.
//   * Camera outside the shell: the shell sphere's front faces are shaded. Camera inside: a screen-covering quad (fullscreen = true) is
//     drawn at the far depth instead, because the camera's far plane is only 20-40 km on the ground while the shell's far side is
//     thousands of km away and would be clipped. Each of the two draws discards itself when it is not the right one.
//   * Optical depth is integrated numerically (along the view ray as it is marched, and 4 short steps toward the sun from each sample)
//     instead of O'Neil's polynomial. The polynomial is only valid for rays that leave the atmosphere; for rays heading into the planet
//     (the planet's disc seen from space, the far horizon) it reaches ~1e19 and cancels into garbage. The planet casts a shadow on samples.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled;

group_uniforms scattering;
uniform float kr : hint_range(0.0, 0.02) = 0.0035;          // Rayleigh scattering coefficient
uniform float km : hint_range(0.0, 0.02) = 0.001;           // Mie scattering coefficient
uniform float sun_intensity : hint_range(0.0, 120.0) = 16.0;
uniform float g : hint_range(-1.0, 0.0) = -0.95;            // Mie phase asymmetry
uniform float scale_depth : hint_range(0.01, 1.0) = 0.25;   // altitude fraction of average density
uniform int num_samples : hint_range(1, 12) = 5;
uniform vec3 wavelengths = vec3(0.65, 0.57, 0.475);          // micrometres; AtmosphereShell derives them from the world's colour

group_uniforms runtime;
uniform bool fullscreen = false;                              // true on the screen-covering quad used from inside the atmosphere
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);           // direction the sunlight travels
uniform float inner_ratio = 0.97;                             // planet surface radius / shell radius

varying vec3 vertex_pos;

// Atmosphere density at shell-space radius r, 1 at the planet surface, falling off exponentially.
float density_at(float r, float scale_over_depth) {
	return exp(scale_over_depth * (inner_ratio - r));
}

void vertex() {
	vertex_pos = VERTEX;
	// Writing POSITION anywhere switches off Godot's default clip-space transform for every path, so both paths set it.
	if (fullscreen) {
		POSITION = vec4(VERTEX.xy, 1.0e-7, 1.0); // reverse-Z: just in front of the far plane, so geometry and the planet draw over it
	} else {
		POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	}
}

void fragment() {
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 camera_pos = (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz) / scale; // shell space: the atmosphere edge is the unit sphere
	bool camera_inside = dot(camera_pos, camera_pos) < 1.0;
	vec3 ray;
	if (fullscreen) {
		if (!camera_inside) {
			discard;
		}
		vec4 view_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
		ray = normalize((INV_VIEW_MATRIX * vec4(normalize(view_point.xyz / view_point.w), 0.0)).xyz);
	} else {
		if (camera_inside == FRONT_FACING) {
			discard;
		}
		ray = normalize(vertex_pos - camera_pos);
	}

	// Where the ray enters the atmosphere (start) and where it leaves it or hits the planet (end), as distances along the ray.
	float b = dot(camera_pos, ray);
	float c = dot(camera_pos, camera_pos) - 1.0;
	float discriminant = b * b - c;
	if (discriminant <= 0.0) {
		discard;
	}
	float root = sqrt(discriminant);
	float start_t = camera_inside ? 0.0 : max(0.0, -b - root);
	float end_t = -b + root;
	float inner_c = dot(camera_pos, camera_pos) - inner_ratio * inner_ratio;
	float inner_disc = b * b - inner_c;
	if (inner_disc > 0.0) {
		float planet_t = -b - sqrt(inner_disc);
		if (planet_t > start_t) {
			end_t = min(end_t, planet_t);
		}
	}
	float far_dist = end_t - start_t;
	if (far_dist <= 0.0) {
		discard;
	}
	vec3 start_pos = camera_pos + ray * start_t;

	float thickness = 1.0 - inner_ratio;
	float atm_scale = 1.0 / thickness;
	float scale_over_depth = atm_scale / scale_depth;
	vec3 inv_wavelength4 = 1.0 / (wavelengths * wavelengths * wavelengths * wavelengths);
	float kr_sun = kr * sun_intensity;
	float km_sun = km * sun_intensity;
	float kr_4pi = kr * 4.0 * PI;
	float km_4pi = km * 4.0 * PI;
	vec3 to_sun = -normalize(sun_direction);

	float sample_length = far_dist / float(num_samples);
	float scaled_length = sample_length * atm_scale;
	vec3 sample_point = start_pos + ray * (sample_length * 0.5);
	vec3 front_color = vec3(0.0);
	float view_depth = 0.0; // optical depth from the camera side of the ray to the current sample, in atmosphere thicknesses
	for (int i = 0; i < num_samples; i++) {
		float h = length(sample_point);
		float d = density_at(h, scale_over_depth);
		float step_depth = d * scaled_length;

		// Optical depth from this sample to the sun, unless the planet blocks the sun.
		float sun_b = dot(sample_point, to_sun);
		float sun_c = h * h - 1.0;
		float sun_exit = -sun_b + sqrt(max(sun_b * sun_b - sun_c, 0.0));
		float planet_c = h * h - inner_ratio * inner_ratio;
		float planet_disc = sun_b * sun_b - planet_c;
		bool in_planet_shadow = planet_disc > 0.0 && (-sun_b - sqrt(planet_disc)) > 0.0;
		if (!in_planet_shadow) {
			float sun_depth = 0.0;
			float sun_step = sun_exit * 0.25;
			for (int j = 0; j < 4; j++) {
				float sun_h = length(sample_point + to_sun * (sun_step * (float(j) + 0.5)));
				sun_depth += density_at(sun_h, scale_over_depth) * sun_step * atm_scale;
			}
			vec3 attenuate = exp(-(sun_depth + view_depth + 0.5 * step_depth) * (inv_wavelength4 * kr_4pi + km_4pi));
			front_color += attenuate * step_depth;
		}
		view_depth += step_depth;
		sample_point += ray * sample_length;
	}

	vec3 rayleigh_color = front_color * (inv_wavelength4 * kr_sun);
	vec3 mie_color = front_color * km_sun;
	float cos_angle = dot(to_sun, -ray);
	float rayleigh_phase = 0.75 * (1.0 + cos_angle * cos_angle);
	float g2 = g * g;
	float mie_phase = 1.5 * ((1.0 - g2) / (2.0 + g2)) * (1.0 + cos_angle * cos_angle) / pow(1.0 + g2 - 2.0 * g * cos_angle, 1.5);

	vec3 scattered = rayleigh_phase * rayleigh_color + mie_phase * mie_color;
	// Composite as: result = scattered light + what is behind * transmittance. blend_premul_alpha gives ALBEDO + behind * (1 - ALPHA), so
	// ALBEDO is the scattered light itself and ALPHA the view ray's opacity (1 - mean transmittance).
	vec3 transmittance = exp(-view_depth * (inv_wavelength4 * kr_4pi + km_4pi));
	ALBEDO = scattered;
	ALPHA = clamp(1.0 - (transmittance.r + transmittance.g + transmittance.b) * (1.0 / 3.0), 0.0, 1.0);
}
