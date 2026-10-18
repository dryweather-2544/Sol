// Sol original: a thin cloud layer on a shell sphere, seen from above it (orbit and high altitude). Procedural: the weather is 3D
// value-noise fbm sampled at the unit direction of each pixel's point on the sphere, so it needs no texture, has no poles or seams,
// and is identical for a planet and its scaled-down distant impostor.
// Lit by the sun with a soft terminator, and self-shadowed by two noise samples taken toward the sun. From inside the layer this shell
// is discarded below the layer's top; cloud_volume.gdshader draws the clouds from there down.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled;

uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);   // direction the sunlight travels
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.45, 0.5, 0.6, 1.0); // colour of the underside / self-shadowed parts
uniform float fade_band = 0.004;                       // shell-units above the layer's top over which this view fades out as the camera comes down into it
uniform float top_radius = 1.0;                         // radius of the layer's top in shell units; below it the volume pass (cloud_volume.gdshader) takes over

#include "res://data/shaders/cloud_common.gdshaderinc"

varying vec3 vertex_pos;

void vertex() {
	vertex_pos = VERTEX;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); // explicit, like the atmosphere shader
}

void fragment() {
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 camera_pos = (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz) / scale; // shell space: the cloud layer is the unit sphere
	float camera_height = length(camera_pos);
	if (camera_height < top_radius || FRONT_FACING == false) {
		discard; // only the outward-facing side, only from above the layer
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

	float fade = smoothstep(top_radius, top_radius + fade_band, camera_height);
	ALBEDO = color;
	ALPHA = clamp(density * 0.95, 0.0, 1.0) * fade;
}
