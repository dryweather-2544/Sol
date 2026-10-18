// Sol original: the cloud layer seen from inside or below it (and from just above). A screen-covering pass that ray-marches the slab of
// air between the layer's bottom and top spheres. It is drawn at the far plane with depth testing on (like the atmosphere pass), so it only
// ever covers sky: terrain and the ship are never painted over, and clouds are not drawn in front of distant terrain (known limitation). Same weather as the orbit shell (cloud_common.gdshaderinc); lit by the sun with one sun-ward density sample per
// step (Beer's law), a forward-scatter lobe for bright edges, and the world's cloud colour for the shaded sides.
// Units: shell space, where 1.0 is the layer's mid radius (CloudShell scales the node to it); shell_metres converts to metres.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled;

uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);   // direction the sunlight travels
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.45, 0.5, 0.6, 1.0);
uniform float bottom_radius = 0.9995;                 // shell units
uniform float top_radius = 1.0005;
uniform float fade_band = 0.004;                      // above the top, this pass fades out as the orbit shell fades in
uniform float shell_metres = 6.0e6;                   // metres per shell unit
uniform float extinction = 0.006;                     // opacity per metre at full density
uniform int steps_per_segment : hint_range(4, 32) = 14;

#include "res://data/shaders/cloud_common.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0e-7, 1.0); // covers the screen at the far plane (reverse-Z): only sky pixels pass the depth test
}

// Density 0..1 at a point in shell space (inside the slab).
float volume_density(vec3 pos, float radius, float thickness) {
	float height = clamp((radius - bottom_radius) / thickness, 0.0, 1.0);
	float profile = smoothstep(0.0, 0.18, height) * (1.0 - smoothstep(0.55, 1.0, height)); // flat-ish base, rounded top
	float base = cloud_density(pos / radius);
	if (base <= 0.001 || profile <= 0.001) {
		return 0.0;
	}
	vec3 metres = pos * shell_metres;
	float erosion = cloud_noise_at(fract(metres / 9000.0 + vec3(seed * 0.31, 0.0, seed * 0.17))) * 0.6 + cloud_noise_at(fract(metres / 2300.0)) * 0.4;
	return clamp((base * profile - (1.0 - erosion) * 0.45) * 1.9, 0.0, 1.0);
}

// Distances along a ray from camera_pos (direction ray) where it crosses the sphere of the given radius: x = entry, y = exit, x > y = misses.
vec2 sphere_hits(vec3 camera_pos, vec3 ray, float radius) {
	float b = dot(camera_pos, ray);
	float c = dot(camera_pos, camera_pos) - radius * radius;
	float disc = b * b - c;
	if (disc <= 0.0) {
		return vec2(1.0, -1.0);
	}
	float root = sqrt(disc);
	return vec2(-b - root, -b + root);
}

float hg_phase(float cos_angle, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cos_angle, 1.5));
}

void fragment() {
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 camera_pos = (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz) / scale;
	float camera_height = length(camera_pos);
	if (camera_height > top_radius + fade_band) {
		discard; // far above: the orbit shell draws the clouds
	}
	vec4 view_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
	vec3 view_dir = normalize(view_point.xyz / view_point.w);
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(view_dir, 0.0)).xyz);

	// The slab is the top sphere minus the bottom sphere: up to two segments along the ray.
	vec2 top = sphere_hits(camera_pos, ray, top_radius);
	vec2 bottom = sphere_hits(camera_pos, ray, bottom_radius);
	if (top.x > top.y) {
		discard;
	}
	float thickness = top_radius - bottom_radius;
	vec2 segments[2];
	segments[0] = vec2(max(top.x, 0.0), top.y);
	segments[1] = vec2(1.0, -1.0);
	if (bottom.x < bottom.y && bottom.y > 0.0) {
		segments[0] = vec2(max(top.x, 0.0), min(top.y, bottom.x));
		segments[1] = vec2(max(bottom.y, 0.0), top.y);
	}

	vec3 to_sun = -normalize(sun_direction);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))); // interleaved gradient noise: hides the step banding
	float metres_per_unit = shell_metres;
	float cos_sun = dot(ray, to_sun);
	float phase = mix(hg_phase(cos_sun, 0.55), hg_phase(cos_sun, -0.2), 0.3) * 4.0 * PI * 0.5 + 0.5;

	vec3 light = vec3(0.0);
	float transmittance = 1.0;
	for (int segment = 0; segment < 2; segment++) {
		float start_t = segments[segment].x;
		float end_t = segments[segment].y;
		if (end_t <= start_t) {
			continue;
		}
		float step_length = (end_t - start_t) / float(steps_per_segment);
		float t = start_t + step_length * jitter;
		for (int i = 0; i < steps_per_segment; i++) {
			vec3 pos = camera_pos + ray * t;
			float radius = length(pos);
			float density = volume_density(pos, radius, thickness);
			if (density > 0.002) {
				float optical = density * extinction * step_length * metres_per_unit;
				float step_alpha = 1.0 - exp(-optical);
				// One density sample toward the sun, a fifth of the slab away: how shaded this point is.
				vec3 sun_pos = pos + to_sun * (thickness * 0.5);
				float sun_density = volume_density(sun_pos, length(sun_pos), thickness);
				float sun_light = exp(-sun_density * extinction * thickness * 0.5 * metres_per_unit * 0.6);
				float daylight = smoothstep(-0.12, 0.3, dot(pos / radius, to_sun));
				vec3 lit = mix(shadow_color.rgb, cloud_color.rgb, sun_light) * (0.05 + 1.1 * daylight);
				lit += cloud_color.rgb * sun_light * daylight * (phase - 1.0) * 0.35; // bright rims toward the sun
				light += lit * step_alpha * transmittance;
				transmittance *= 1.0 - step_alpha;
				if (transmittance < 0.01) {
					break;
				}
			}
			t += step_length;
		}
		if (transmittance < 0.01) {
			break;
		}
	}

	float fade = 1.0 - smoothstep(top_radius, top_radius + fade_band, camera_height);
	ALBEDO = light * fade;
	ALPHA = (1.0 - transmittance) * fade;
}
