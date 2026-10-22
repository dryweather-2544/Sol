// The star's surface (Sol's own), after an extreme-ultraviolet photograph of the Sun, but white hot: a mottled boiling
// network of fine granules, dark filament lanes, and bright active regions in two belts either side of the equator. Each
// region is a magnetic dipole: its loops are drawn as the contours of the dipole's field-line equation (f = y^2 / r^3),
// with white-hot patches at the two feet. The limb is brightened (as in UV images), not darkened. Emissive and HDR
// (values above 1) so the glow pass blooms it.
shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

uniform vec3 dark_color : source_color = vec3(0.45, 0.13, 0.02);
uniform vec3 mid_color : source_color = vec3(1.0, 0.55, 0.14);
uniform vec3 hot_color : source_color = vec3(1.0, 0.82, 0.5);
uniform vec3 white_color : source_color = vec3(1.0, 0.98, 0.93);
uniform float brightness = 2.3;
uniform float granule_scale = 60.0;
uniform float boil_speed = 0.012;
uniform int region_count = 0; // active-region loops: off (they read as odd rings)

varying vec3 obj_dir;

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash1(i), hash1(i + vec3(1, 0, 0)), f.x), mix(hash1(i + vec3(0, 1, 0)), hash1(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash1(i + vec3(0, 0, 1)), hash1(i + vec3(1, 0, 1)), f.x), mix(hash1(i + vec3(0, 1, 1)), hash1(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(7.1, 3.3, 1.7);
		a *= 0.5;
	}
	return v;
}

// distance to the nearest and second-nearest feature point
vec2 worley(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				float d = length(g + hash3(i + g) - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(d1, d2);
}

// Bright magnetic loops and feet of every active region at direction p (x: loops, y: feet).
vec2 active_regions(vec3 p, float t) {
	float loops = 0.0;
	float feet = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= region_count) {
			break;
		}
		vec3 h = hash3(vec3(float(i) * 1.7 + 0.3, 3.1, 9.4));
		float side = (i % 2 == 0) ? 1.0 : -1.0;
		float lat = side * (0.1 + 0.4 * h.x); // two belts either side of the equator
		float lon = h.y * 6.2831853;
		vec3 c = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));
		float z = dot(p, c);
		if (z < 0.9) {
			continue; // outside this region's reach
		}
		vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), c));
		vec3 north = cross(c, east);
		float tilt = (h.z - 0.5) * 0.7;
		vec3 a = east * cos(tilt) + north * sin(tilt);
		vec3 b = cross(c, a);
		float x = dot(p, a);
		float y = dot(p, b);
		float d2 = x * x + y * y;
		float reach = 1.0 - smoothstep(0.22, 0.46, sqrt(d2));
		// dipole field lines: contours of y^2 / r^3, drifting slowly
		float f = (y * y + 0.004) / pow(d2 + 0.012, 1.5);
		float line = abs(fract(log(f) * 0.85 - t * 0.4 + h.z * 5.0) - 0.5);
		// broad soft bands (not thin rays), and none right on top of the feet where the contours bunch up into rings
		float arc = (1.0 - smoothstep(0.0, 0.3, line)) * reach * smoothstep(0.05, 0.16, sqrt(d2));
		float foot_x = 0.11 + 0.05 * h.x;
		float foot = exp(-(pow(x - foot_x, 2.0) + y * y) * 260.0) + exp(-(pow(x + foot_x, 2.0) + y * y) * 260.0);
		loops = max(loops, arc * (0.35 + 0.3 * h.y));
		feet = max(feet, foot * (0.45 + 0.3 * h.x));
	}
	return vec2(loops, feet);
}

void vertex() {
	obj_dir = normalize(VERTEX);
}

void fragment() {
	float t = TIME * boil_speed;
	// the whole star turns very slowly
	float spin = TIME * 0.004;
	vec3 p = vec3(obj_dir.x * cos(spin) - obj_dir.z * sin(spin), obj_dir.y, obj_dir.x * sin(spin) + obj_dir.z * cos(spin));
	vec3 warp = vec3(fbm(p * 4.0 + vec3(0.0, t, 0.0)), fbm(p * 4.0 + vec3(5.2, 0.0, t)), fbm(p * 4.0 + vec3(t, 9.1, 0.0))) - 0.5;

	// Anti-aliasing: pixel_size is how much of the unit sphere one pixel covers. Detail whose cells are under ~3 pixels
	// is faded out (to its average) instead of shimmering as the camera moves.
	float pixel_size = length(fwidth(obj_dir));
	float fine_ok = 1.0 - smoothstep(0.16, 0.34, pixel_size * granule_scale);
	float mid_ok = 1.0 - smoothstep(0.16, 0.34, pixel_size * 26.0);
	// the fine mottled network
	vec2 w = worley(p * granule_scale + warp * 4.0 + vec3(0.0, t * 20.0, 0.0));
	float cell = mix(0.5, 1.0 - smoothstep(0.1, 0.8, w.x), fine_ok);
	float lane = mix(0.8, smoothstep(0.0, 0.25, w.y - w.x), fine_ok);
	float mottle = mix(0.5, fbm(p * 26.0 + warp * 3.0 + vec3(t * 3.0)), mid_ok);
	float network = clamp(0.25 + 0.55 * mottle + 0.25 * cell * lane - 0.12 * (1.0 - lane), 0.0, 1.0);
	// large dim and bright regions, and dark filament lanes between the active belts
	network *= 0.8 + 0.4 * fbm(p * 4.0 + vec3(1.0, 2.0, 3.0));
	float filament = smoothstep(0.58, 0.74, fbm(p * 9.0 + warp * 2.0 + vec3(4.0, 8.0, 2.0)));
	network *= 1.0 - 0.55 * filament;

	vec2 ar = active_regions(p, TIME * boil_speed);
	float heat = network * 0.75 + ar.x * 0.75 + ar.y * 1.0;

	vec3 colour = mix(dark_color, mid_color, smoothstep(0.1, 0.55, heat));
	colour = mix(colour, hot_color, smoothstep(0.5, 0.9, heat));
	colour = mix(colour, white_color, smoothstep(0.85, 1.35, heat));

	// ultraviolet limb brightening: brightest at the edge
	float mu = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - mu, 2.2);
	colour *= (0.85 + 0.9 * rim) * (0.6 + 0.6 * clamp(heat, 0.0, 1.2));
	colour = mix(colour, white_color * 1.1, clamp(ar.y * 0.35, 0.0, 0.5));
	ALBEDO = colour * brightness;
}
