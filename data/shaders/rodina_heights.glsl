#[compute]
#version 450

// Rodina's planet height functions (Shaders/PlanetPerun.h, PlanetJarilo.h, PlanetVeles.h,
// PlanetMorena.h, PlanetAsteroid.h) with the GenerationVars from EGDataPlanets.lua, run per point on the
// GPU in float32 as Rodina does. src/planet/rodina_planets.gd is the same code in 64-bit on the CPU; keep
// the two in step. Noise is _perlin.h (improved Perlin, seed added to the coordinate, period 256).

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer DirectionBuffer {
	vec4 directions[];
} direction_buffer;

layout(set = 0, binding = 1, std430) restrict writeonly buffer HeightBuffer {
	float heights[];
} height_buffer;

layout(set = 0, binding = 2, std430) restrict readonly buffer PointBuffer {
	vec4 points[];
} point_buffer;

// Optional second output: the planet feature texture (base, plateau, mountains, holes) per point, written only when
// params.features_enabled is 1 (PSPlanetColors in each Planet<Name>.fx). Mirrors RodinaPlanets.features().
layout(set = 0, binding = 3, std430) restrict writeonly buffer FeatureBuffer {
	vec4 features[];
} feature_buffer;

layout(push_constant, std430) uniform Params {
	uint count;
	uint grammar; // TerrainProfile.Grammar: 1 Perun, 2 Jarilo, 3 Veles, 4 Morena, 5 Asteroid
	float asteroid_scale;
	uint features_enabled;
} params;

const float PI = 3.14159265358979;
const int VORONOI_COUNT = 1000;

const int PERM[256] = int[256](
	151,160,137,91,90,15,
	131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
	190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
	88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,134,139,48,27,166,
	77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
	102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,
	135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,
	5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
	223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
	129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,
	251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,
	49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
	138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180);

const vec3 GRADIENTS[16] = vec3[16](
	vec3(1, 1, 0), vec3(-1, 1, 0), vec3(1, -1, 0), vec3(-1, -1, 0),
	vec3(1, 0, 1), vec3(-1, 0, 1), vec3(1, 0, -1), vec3(-1, 0, -1),
	vec3(0, 1, 1), vec3(0, -1, 1), vec3(0, 1, -1), vec3(0, -1, -1),
	vec3(1, 1, 0), vec3(0, -1, 1), vec3(-1, 1, 0), vec3(0, -1, -1));

int perm(int index) {
	return PERM[index & 255];
}

float grad(int hash_value, float x, float y, float z) {
	vec3 g = GRADIENTS[hash_value & 15];
	return g.x * x + g.y * y + g.z * z;
}

// _perlin.h PerlinNoise
float perlin_noise(vec3 p) {
	vec3 cube = floor(p);
	vec3 wrapped = mod(cube, 256.0);
	int xi = int(wrapped.x);
	int yi = int(wrapped.y);
	int zi = int(wrapped.z);
	float x = p.x - cube.x;
	float y = p.y - cube.y;
	float z = p.z - cube.z;
	float u = x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
	float v = y * y * y * (y * (y * 6.0 - 15.0) + 10.0);
	float w = z * z * z * (z * (z * 6.0 - 15.0) + 10.0);
	int a = perm(xi) + yi;
	int aa = perm(a) + zi;
	int ab = perm(a + 1) + zi;
	int b = perm(xi + 1) + yi;
	int ba = perm(b) + zi;
	int bb = perm(b + 1) + zi;
	return mix(
		mix(mix(grad(perm(aa), x, y, z), grad(perm(ba), x - 1.0, y, z), u),
			mix(grad(perm(ab), x, y - 1.0, z), grad(perm(bb), x - 1.0, y - 1.0, z), u), v),
		mix(mix(grad(perm(aa + 1), x, y, z - 1.0), grad(perm(ba + 1), x - 1.0, y, z - 1.0), u),
			mix(grad(perm(ab + 1), x, y - 1.0, z - 1.0), grad(perm(bb + 1), x - 1.0, y - 1.0, z - 1.0), u), v),
		w);
}

// _perlin.h PerlinAndDerivative: (d/dx, d/dy, d/dz, value)
vec4 perlin_and_derivative(vec3 p) {
	vec3 cube = floor(p);
	vec3 wrapped = mod(cube, 256.0);
	int xi = int(wrapped.x);
	int yi = int(wrapped.y);
	int zi = int(wrapped.z);
	float x = p.x - cube.x;
	float y = p.y - cube.y;
	float z = p.z - cube.z;
	float du = x * x * (x * (x * 30.0 - 60.0) + 30.0);
	float dv = y * y * (y * (y * 30.0 - 60.0) + 30.0);
	float dw = z * z * (z * (z * 30.0 - 60.0) + 30.0);
	float u = x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
	float v = y * y * y * (y * (y * 6.0 - 15.0) + 10.0);
	float w = z * z * z * (z * (z * 6.0 - 15.0) + 10.0);
	float a = grad(perm(perm(perm(xi) + yi) + zi), x, y, z);
	float b = grad(perm(perm(perm(xi + 1) + yi) + zi), x - 1.0, y, z);
	float c = grad(perm(perm(perm(xi) + yi + 1) + zi), x, y - 1.0, z);
	float d = grad(perm(perm(perm(xi + 1) + yi + 1) + zi), x - 1.0, y - 1.0, z);
	float e = grad(perm(perm(perm(xi) + yi) + zi + 1), x, y, z - 1.0);
	float f = grad(perm(perm(perm(xi + 1) + yi) + zi + 1), x - 1.0, y, z - 1.0);
	float g = grad(perm(perm(perm(xi) + yi + 1) + zi + 1), x, y - 1.0, z - 1.0);
	float h = grad(perm(perm(perm(xi + 1) + yi + 1) + zi + 1), x - 1.0, y - 1.0, z - 1.0);
	float k1 = b - a;
	float k2 = c - a;
	float k3 = e - a;
	float k4 = a - b - c + d;
	float k5 = a - c - e + g;
	float k6 = a - b - e + f;
	float k7 = -a + b + c - d + e - f - g + h;
	return vec4(
		du * (k1 + k4 * v + k6 * w + k7 * v * w),
		dv * (k2 + k4 * u + k5 * w + k7 * w * u),
		dw * (k3 + k5 * v + k6 * u + k7 * u * v),
		a + k1 * u + k2 * v + k3 * w + k4 * u * v + k5 * v * w + k6 * w * u + k7 * u * v * w);
}

// _perlin.h FractalPerlin, normalised to 0..1
float fractal_perlin(float seed, vec3 p, float mult_change, float octave_base, float octave_change, int octaves) {
	float frequency = octave_base;
	float noise = 0.0;
	float range_sum = 0.0;
	float mult = 1.0;
	for (int octave = 0; octave < octaves; octave++) {
		noise += mult * perlin_noise(vec3(seed) + p * frequency);
		range_sum += mult;
		frequency *= octave_change;
		mult *= mult_change;
	}
	if (range_sum <= 0.0) {
		return 0.5;
	}
	return clamp((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0);
}

// _perlin.h FractalPerlinDerivative(...).xyz
vec3 fractal_derivative(float seed, vec3 p, float mult_change, float octave_base, float octave_change, int octaves) {
	float frequency = octave_base;
	vec3 total = vec3(0.0);
	float mult = 1.0;
	for (int octave = 0; octave < octaves; octave++) {
		total += mult * perlin_and_derivative(vec3(seed) + p * frequency).xyz;
		frequency *= octave_change;
		mult *= mult_change;
	}
	return total;
}

// _perlin.h SpecialPerlin, normalised to 0..1
float special_perlin(float seed, vec3 p, float mult_change, float octave_base, float octave_change, int octaves) {
	float frequency = octave_base;
	float noise = 0.0;
	float range_sum = 0.0;
	float mult = 1.0;
	float dx = 0.0;
	float dz = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		vec4 nd = perlin_and_derivative(vec3(seed) + p * frequency);
		dx += nd.x;
		dz += nd.z;
		noise += mult * nd.w / (1.0 + dx * dx + dz * dz);
		range_sum += mult;
		frequency *= octave_change;
		mult *= mult_change;
	}
	if (range_sum <= 0.0) {
		return 0.5;
	}
	return clamp((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0);
}

// --- _utility.h ------------------------------------------------------------------------------

float ratio(float value, float from_low, float from_high) {
	if (from_high == from_low) {
		return value > from_low ? 1.0 : 0.0;
	}
	return clamp((value - from_low) / (from_high - from_low), 0.0, 1.0);
}

float analogue(float value, float from_low, float from_high, float to_low, float to_high) {
	return to_low + (to_high - to_low) * ratio(value, from_low, from_high);
}

float ease_out_in_sin2(float t) {
	return analogue(sin(analogue(t, 0.0, 1.0, -PI * 0.5, PI * 0.5)), -1.0, 1.0, 0.0, 1.0);
}

float ease_in_sin(float t) {
	return 1.0 - sin(clamp(1.0 - t, 0.0, 1.0) * PI * 0.5);
}

float ease_out_in_sin(float t) {
	float s = sin(clamp(t, 0.0, 1.0) * PI * 0.5);
	return s * s;
}

float hsmooth(float edge_a, float edge_b, float x) {
	float t = ratio(x, edge_a, edge_b);
	return t * t * (3.0 - 2.0 * t);
}

float holes_remap(float value, vec4 edges) {
	if (value <= edges.y) {
		return hsmooth(edges.x, edges.y, value);
	}
	if (value <= edges.z) {
		return 1.0;
	}
	if (value <= edges.w) {
		return hsmooth(edges.w, edges.z, value);
	}
	return 0.0;
}

// --- _voronoi.h ------------------------------------------------------------------------------

float nearest_distance(vec3 p) {
	float best = 1.0e9;
	for (int index = 0; index < VORONOI_COUNT; index++) {
		best = min(best, length(p - point_buffer.points[index].xyz));
	}
	return best;
}

// GetPoint(p, d1): the nearest point strictly farther than d1
float next_distance(vec3 p, float after) {
	float best = 1.0e9;
	for (int index = 0; index < VORONOI_COUNT; index++) {
		float d = length(p - point_buffer.points[index].xyz);
		if (d > after && d < best) {
			best = d;
		}
	}
	return best;
}

float voronoi_one(vec3 p, float max_distance) {
	return analogue(nearest_distance(p), 0.0, max_distance, 1.0, 0.0);
}

float voronoi_two(vec3 p, float factor1, float factor2, float max_distance) {
	float d1 = nearest_distance(p);
	float d2 = next_distance(p, d1);
	return analogue(factor1 * d1 + factor2 * d2, 0.0, max_distance, 1.0, 0.0);
}

// --- planets ---------------------------------------------------------------------------------

float perun_height(vec3 p) {
	vec3 mask_distort = p - fractal_derivative(10.0, p, 1.0, 1.0, 2.0, 2);
	vec3 distort = p - fractal_derivative(0.0, p, 1.0, 1.0, 2.0, 9);
	vec3 mask_coord = normalize(p + mask_distort * 0.05 + distort * 0.005);
	vec3 base_coords = normalize(p + distort * 0.02);
	vec3 mountain_distort = mask_coord - fractal_derivative(10.0, mask_coord, 1.0, 2.0, 2.0, 2);
	vec3 mountain_coord1 = normalize(mask_coord + mountain_distort * 0.2);
	vec3 mountain_coords = normalize(p + distort * 0.001);
	float base = voronoi_two(base_coords, 0.5, 0.5, 0.25);
	float holes = holes_remap(fractal_perlin(0.0, mountain_coords, 0.5, 128.0, 2.0, 4), vec4(0.275, 0.375, 0.375, 0.55));
	float plateau = analogue(fractal_perlin(10.0, mask_coord, 0.56, 3.0, 2.0, 12), 0.5, 0.675, 0.0, 1.0);
	float mountain_mask = analogue(fractal_perlin(10.0, mountain_coord1, 0.6, 3.0, 2.0, 5), 0.45, 0.6, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0);
	mountains = mountain_mask * mountains;
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0);
	float roughness = analogue(mountains, 0.0, 0.9, 0.3, 0.5);
	mountains = mountains * mountains;
	plateau = ease_out_in_sin2(analogue(plateau, 0.1, 0.425, 0.0, 1.0));
	base = ease_out_in_sin2(analogue(base, 0.4, 0.7, 0.3, 1.0));
	base = mix(base, 0.0, plateau);
	base = mix(base, 0.0, mountains);
	mountains = mix(mountains, 0.0, holes);
	float height = 0.0;
	if (mountains > 0.0) {
		height += mountains * (20000.0 * fractal_perlin(0.0, p, roughness, 500.0, 2.0, 12));
	}
	if (plateau > 0.0) {
		height += plateau * (12000.0 + 5000.0 * fractal_perlin(0.0, p, 0.5, 300.0, 2.0, 10));
	}
	if (base > 0.0) {
		height += base * (500.0 * fractal_perlin(0.0, p, 0.35, 3750.0, 2.0, 7));
	}
	return height;
}

float jarilo_height(vec3 p) {
	vec3 map_distort = p - fractal_derivative(10.0, p, 1.0, 1.0, 2.0, 2);
	vec3 feature_distort = p - fractal_derivative(0.0, p, 1.0, 1.0, 2.0, 9);
	vec3 base_coords = normalize(p + map_distort * 0.06 + feature_distort * 0.02);
	float base = voronoi_two(base_coords, 0.5, 0.5, 0.2);
	vec3 plateau_coord = normalize(p + map_distort * 0.05 + feature_distort * 0.0);
	float plateau = analogue(fractal_perlin(20.0, plateau_coord, 0.5, 2.0, 2.0, 16), 0.4, 0.8, 0.0, 1.0);
	vec3 mountain_distort = plateau_coord - fractal_derivative(10.0, plateau_coord, 1.0, 2.0, 2.0, 2);
	vec3 mountain_coord1 = normalize(plateau_coord + mountain_distort * 0.0);
	vec3 mountain_coords = normalize(p + feature_distort * 0.001);
	float mountain_mask = analogue(fractal_perlin(20.0, mountain_coord1, 0.5, 2.0, 2.0, 5), 0.1, 0.4, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.45, 0.8, 0.0, 1.0);
	float holes = holes_remap(fractal_perlin(0.0, p, 0.5, 2500.0, 2.0, 4), vec4(0.0, 0.0, 0.375, 0.5));
	mountains = mountain_mask * mountains;
	float dunes = base;
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0);
	float roughness = analogue(mountains, 0.0, 0.9, 0.3, 0.5);
	mountains = mountains * mountains;
	plateau = ease_out_in_sin2(analogue(plateau, 0.05, 0.1, 0.0, 1.0));
	dunes = ease_out_in_sin2(analogue(dunes, 0.4, 0.7, 0.0, 1.0));
	dunes = analogue(plateau, 0.0, 0.15, dunes, 0.0);
	dunes = analogue(mountains, 0.05, 0.1, dunes, 0.0);
	float height = 0.0;
	if (mountains > 0.0) {
		height += mountains * (50000.0 * special_perlin(0.0, p, roughness, 500.0, 2.0, 12));
	}
	if (plateau > 0.0) {
		float plateau_hills = special_perlin(153.0, p, 0.5, 4000.0, 2.0, 9);
		plateau_hills = mix(plateau_hills, 0.45, holes);
		height += plateau * (2000.0 + 2000.0 * plateau_hills);
	}
	if (dunes > 0.0) {
		vec3 dune_distort = fractal_derivative(12.0, p, 0.5, 100.0, 2.0, 3);
		vec3 dune_coord = normalize(p + dune_distort * 0.001);
		float dune_control = sin(dot(dune_coord, vec3(1.0, -1.0, -1.0)) * 1000.0);
		float x1 = fract(dot(dune_coord, vec3(1.0, 1.0, 1.0)) * 800.0);
		float x2 = fract(dot(dune_coord, vec3(1.0, 1.0, 1.0)) * 800.0 + 0.5);
		float shape1 = ease_in_sin(abs(analogue(x1, 0.0, 1.0, -1.0, 1.0)));
		float shape2 = ease_in_sin(abs(analogue(x2, 0.0, 1.0, -1.0, 1.0)));
		float dune1 = shape1 * ease_out_in_sin(analogue(dune_control, 1.0, -1.0, 0.0, 1.0));
		float dune2 = shape2 * ease_out_in_sin(analogue(dune_control, -1.0, 1.0, 0.0, 1.0));
		height += dunes * (700.0 * dune1 + 700.0 * dune2);
	}
	return height;
}

float veles_height(vec3 p) {
	float base = voronoi_one(p, 0.25);
	float half_mask = analogue(p.x, -0.9, 0.0, 0.3, 2.0);
	float holes = fractal_perlin(0.0, p, 0.5, 128.0, 2.0, 4);
	if (holes <= 0.375) {
		holes = hsmooth(0.275, 0.375, holes);
	} else {
		holes = hsmooth(0.55, 0.375, holes);
	}
	float plate_cracks = analogue(abs(0.5 - fractal_perlin(10.0, p, 0.56, 10.0, 2.0, 10)), 0.0, 0.025, 1.0, 0.25);
	float plate_mask = fractal_perlin(10.0, p, 0.6, 1.0, 2.0, 10) * half_mask;
	float plate = analogue(plate_mask, 0.4, 0.41, 0.0, 1.0);
	float mountain_mask = analogue(plate_mask, 0.375, 0.45, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, p, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0);
	mountains = mountain_mask * mountains;
	float plateau = plate - plate_cracks;
	plateau = ease_out_in_sin2(plateau);
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0);
	float roughness = analogue(mountains, 0.0, 0.9, 0.3, 0.5);
	mountains = mountains * mountains;
	base = mix(base, 0.0, plateau);
	base = mix(base, 0.0, mountains);
	float volcano = pow(max(analogue(base, 0.875, 0.995, 0.0, 1.0), 0.0), 3.0);
	if (base > 0.9955) {
		volcano = analogue(base, 0.9955, 0.998, 1.0, 0.45);
	}
	volcano = hsmooth(0.0, 1.0, volcano);
	base = ease_out_in_sin2(analogue(base, 0.4, 0.7, 0.3, 1.0));
	mountains = mix(mountains, 0.0, holes);
	float height = 0.0;
	if (mountains > 0.0) {
		height += mountains * (20000.0 * fractal_perlin(0.0, p, roughness, 500.0, 2.0, 12));
	}
	if (plateau > 0.0) {
		height += plateau * (15000.0 + 5000.0 * fractal_perlin(0.0, p, 0.5, 300.0, 2.0, 10));
	}
	float lowland = base * 8000.0 + volcano * 5000.0;
	if (lowland != 0.0) {
		height += lowland * fractal_perlin(0.0, p, 0.5, 500.0, 2.0, 12);
	}
	height += volcano * 30000.0;
	return height;
}

// Sol: Morena's big plate cracks off (see RodinaPlanets.MORENA_BIG_CRACK_SCALE).
const float MORENA_BIG_CRACK_SCALE = 0.0;

float morena_height(vec3 p) {
	vec3 crack_distort_big = fractal_derivative(12.0, p, 0.5, 0.5, 2.0, 8);
	vec3 crack_distort = fractal_derivative(10.0, p, 0.5, 2.0, 2.0, 8);
	vec3 crack_coord = normalize(p + crack_distort_big * 0.05 + crack_distort * 0.075);
	float plate_perlin = fractal_perlin(10.0, p, 0.6, 60.0, 2.0, 7);
	float pi = 3.14159;
	float big_mask_1 = plate_perlin - cos(max(min(30.0 * (0.9 * crack_coord.z + 0.3 * crack_coord.y), 8.0 * pi), -8.0 * pi));
	float big_mask_2 = plate_perlin - cos(max(min(30.0 * (1.0 * crack_coord.z + 0.0 * crack_coord.y), 8.0 * pi), -8.0 * pi));
	float plate_cracks = min(abs(big_mask_1), abs(big_mask_2));
	float small_cracks = fractal_perlin(0.0, p, 0.56, 25.0, 2.0, 10);
	small_cracks = min(abs(0.46 - small_cracks), min(abs(0.5 - small_cracks), abs(0.54 - small_cracks)));
	small_cracks = hsmooth(0.0, 1.0, analogue(small_cracks, 0.003, 0.010, 1.0, 0.0));
	float hills = 0.0;
	float dunes = 0.0;
	if (big_mask_1 < 0.0 || big_mask_2 < 0.0) {
		hills = analogue(plate_cracks, 0.35, 1.0, 0.0, 1.0);
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.5, 1.0, 0.0));
	} else if (big_mask_1 > 0.0 && big_mask_2 > 0.0) {
		dunes = analogue(plate_cracks, 0.4, 1.0, 0.0, 1.0);
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.35, 1.0, 0.0));
	}
	float big_cracks = ease_out_in_sin(analogue(plate_cracks, 0.05, 0.15, 1.0, 0.0)) * 0.75 * MORENA_BIG_CRACK_SCALE;
	float small = small_cracks * 0.25;
	float dune_mask = analogue(dunes, 0.0, 0.15, 0.0, 1.0);
	float cracks = max(big_cracks, small);
	float plateau = mix(1.0, 0.0, dune_mask);
	float mountains = mix(hills, 0.0, cracks);
	float height = 14000.0;
	height += plateau * (-1000.0 + 2000.0 * fractal_perlin(0.0, p, 0.48, 300.0, 2.0, 6));
	height += cracks * -15000.0;
	if (mountains > 0.0) {
		height += mountains * (30000.0 * fractal_perlin(0.0, p, 0.5, 500.0, 2.0, 12));
	}
	if (dune_mask > 0.0) {
		vec3 dune_distort = fractal_derivative(12.0, p, 0.5, 100.0, 2.0, 3);
		vec3 dune_coord = normalize(p + dune_distort * 0.001);
		float control = sin(dot(dune_coord, vec3(1.0, -1.0, -1.0)) * 1000.0);
		float x1 = fract(dot(dune_coord, vec3(1.0, 1.0, 1.0)) * 400.0);
		float x2 = fract(dot(dune_coord, vec3(1.0, 1.0, 1.0)) * 400.0 + 0.5);
		float shape1 = ease_in_sin(abs(analogue(x1, 0.0, 1.0, -1.0, 1.0)));
		float shape2 = ease_in_sin(abs(analogue(x2, 0.0, 1.0, -1.0, 1.0)));
		float dune1 = shape1 * ease_out_in_sin(analogue(control, 1.0, -1.0, 0.0, 1.0));
		float dune2 = shape2 * ease_out_in_sin(analogue(control, -1.0, 1.0, 0.0, 1.0));
		height += dune_mask * (800.0 * dune1 + 800.0 * dune2);
	}
	return height;
}

// Sol's craggier asteroid mountains; keep in step with RodinaPlanets.ASTEROID_MOUNTAIN_EDGE / _AMPLITUDE.
const float ASTEROID_MOUNTAIN_EDGE = 0.1;
const float ASTEROID_MOUNTAIN_AMPLITUDE = 1400.0;
const float ASTEROID_CRAG_AMPLITUDE = 1000.0; // Sol-only sharp creases; keep in step with RodinaPlanets.ASTEROID_CRAG_AMPLITUDE

float asteroid_height(vec3 p, float scale) {
	float plateau = analogue(fractal_perlin(113.0, p, 0.5, 0.5, 2.0, 12), 0.0, 1.0, 0.0, 1.0);
	float mountain_mask = analogue(fractal_perlin(20.0, p, 0.5, 0.5, 2.0, 3), -1.0, -1.0, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, p, 0.5, 1.0, 2.0, 3), ASTEROID_MOUNTAIN_EDGE, 1.0, 0.0, 1.0);
	mountains = mountain_mask * mountains;
	mountains = analogue(mountains, 0.0, 0.3, 0.0, 1.0);
	float roughness = analogue(mountains, 0.0, 0.9, 0.3, 0.5);
	mountains = mountains * mountains;
	plateau = analogue(plateau, 0.0, 1.0, 0.0, 1.0);
	float height = -1000.0;
	if (mountains > 0.0) {
		height += mountains * ASTEROID_MOUNTAIN_AMPLITUDE * fractal_perlin(0.0, p, roughness, 2.5, 2.0, 10);
		height += mountains * ASTEROID_CRAG_AMPLITUDE * (0.2 - abs(fractal_perlin(5.0, p, 0.55, 40.0, 2.0, 6) - 0.47));
	}
	height += plateau * 3000.0;
	return height * scale;
}

// --- planet features (GetPlanetFeatures + PSPlanetColors); keep in step with RodinaPlanets.*_features ------------

vec4 perun_features(vec3 p) {
	vec3 mask_distort = p - fractal_derivative(10.0, p, 1.0, 1.0, 2.0, 2);
	vec3 distort = p - fractal_derivative(0.0, p, 1.0, 1.0, 2.0, 9);
	vec3 mask_coord = normalize(p + mask_distort * 0.05 + distort * 0.005);
	vec3 base_coords = normalize(p + distort * 0.02);
	vec3 mountain_distort = mask_coord - fractal_derivative(10.0, mask_coord, 1.0, 2.0, 2.0, 2);
	vec3 mountain_coord1 = normalize(mask_coord + mountain_distort * 0.2);
	vec3 mountain_coords = normalize(p + distort * 0.001);
	float base = voronoi_two(base_coords, 0.5, 0.5, 0.25);
	float holes = holes_remap(fractal_perlin(0.0, mountain_coords, 0.5, 128.0, 2.0, 4), vec4(0.275, 0.375, 0.375, 0.55));
	float plateau = analogue(fractal_perlin(10.0, mask_coord, 0.56, 3.0, 2.0, 12), 0.5, 0.675, 0.0, 1.0);
	float mountain_mask = analogue(fractal_perlin(10.0, mountain_coord1, 0.6, 3.0, 2.0, 5), 0.45, 0.6, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0);
	return vec4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes);
}

vec4 jarilo_features(vec3 p) {
	vec3 map_distort = p - fractal_derivative(10.0, p, 1.0, 1.0, 2.0, 2);
	vec3 feature_distort = p - fractal_derivative(0.0, p, 1.0, 1.0, 2.0, 9);
	vec3 base_coords = normalize(p + map_distort * 0.06 + feature_distort * 0.02);
	float base = voronoi_two(base_coords, 0.5, 0.5, 0.2);
	vec3 plateau_coord = normalize(p + map_distort * 0.05);
	float plateau = analogue(fractal_perlin(20.0, plateau_coord, 0.5, 2.0, 2.0, 16), 0.4, 0.8, 0.0, 1.0);
	vec3 mountain_coords = normalize(p + feature_distort * 0.001);
	float mountain_mask = analogue(fractal_perlin(20.0, plateau_coord, 0.5, 2.0, 2.0, 5), 0.1, 0.4, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.45, 0.8, 0.0, 1.0);
	float holes = holes_remap(fractal_perlin(0.0, p, 0.5, 2500.0, 2.0, 4), vec4(0.0, 0.0, 0.375, 0.5));
	return vec4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes);
}

vec4 veles_features(vec3 p) {
	float base = voronoi_one(p, 0.25);
	float half_mask = analogue(p.x, -0.9, 0.0, 0.3, 2.0);
	float holes = fractal_perlin(0.0, p, 0.5, 128.0, 2.0, 4);
	if (holes <= 0.375) {
		holes = hsmooth(0.275, 0.375, holes);
	} else {
		holes = hsmooth(0.55, 0.375, holes);
	}
	float plate_cracks = analogue(abs(0.5 - fractal_perlin(10.0, p, 0.56, 10.0, 2.0, 10)), 0.0, 0.025, 1.0, 0.25);
	float plate_mask = fractal_perlin(10.0, p, 0.6, 1.0, 2.0, 10) * half_mask;
	float plate = analogue(plate_mask, 0.4, 0.41, 0.0, 1.0);
	float mountain_mask = analogue(plate_mask, 0.375, 0.45, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, p, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0);
	return vec4(base, plate - plate_cracks, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes);
}

vec4 morena_features(vec3 p) {
	vec3 crack_distort_big = fractal_derivative(12.0, p, 0.5, 0.5, 2.0, 8);
	vec3 crack_distort = fractal_derivative(10.0, p, 0.5, 2.0, 2.0, 8);
	vec3 crack_coord = normalize(p + crack_distort_big * 0.05 + crack_distort * 0.075);
	float plate_perlin = fractal_perlin(10.0, p, 0.6, 60.0, 2.0, 7);
	float pi = 3.14159;
	float big_mask_1 = plate_perlin - cos(max(min(30.0 * (0.9 * crack_coord.z + 0.3 * crack_coord.y), 8.0 * pi), -8.0 * pi));
	float big_mask_2 = plate_perlin - cos(max(min(30.0 * (1.0 * crack_coord.z + 0.0 * crack_coord.y), 8.0 * pi), -8.0 * pi));
	float plate_cracks = min(abs(big_mask_1), abs(big_mask_2));
	float hills = 0.0;
	float dunes = 0.0;
	if (big_mask_1 < 0.0 || big_mask_2 < 0.0) {
		hills = analogue(plate_cracks, 0.35, 1.0, 0.0, 1.0);
	} else if (big_mask_1 > 0.0 && big_mask_2 > 0.0) {
		dunes = analogue(plate_cracks, 0.4, 1.0, 0.0, 1.0);
	}
	float big_cracks = pow(analogue(plate_cracks, 0.0, 0.5, 1.0, 0.0), 1.5) * MORENA_BIG_CRACK_SCALE;
	return vec4(fractal_perlin(8.0, p, 0.5, 8.0, 2.0, 8), big_cracks, hills, analogue(dunes, 0.0, 0.75, 0.0, 1.0));
}

vec4 asteroid_features(vec3 p) {
	vec3 map_distort = p - fractal_derivative(20.0, p, 1.0, 1.0, 2.0, 2);
	vec3 feature_distort = p - fractal_derivative(0.0, p, 1.0, 1.0, 2.0, 9);
	vec3 base_coords = normalize(p + map_distort * 0.1 + feature_distort * 0.005);
	float base = voronoi_two(base_coords, 0.5, 0.5, 0.25);
	float plateau = analogue(fractal_perlin(113.0, p, 0.5, 0.5, 2.0, 12), 0.0, 1.0, 0.0, 1.0);
	float mountain_mask = analogue(fractal_perlin(20.0, p, 0.5, 0.5, 2.0, 3), -1.0, -1.0, 0.0, 1.0);
	float mountains = analogue(fractal_perlin(0.0, p, 0.5, 1.0, 2.0, 3), ASTEROID_MOUNTAIN_EDGE, 1.0, 0.0, 1.0);
	float holes = holes_remap(fractal_perlin(0.0, p, 0.5, 128.0, 2.0, 4), vec4(1.0, 1.0, 1.0, 1.0));
	return vec4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes);
}

void main() {
	uint index = gl_GlobalInvocationID.x;
	if (index >= params.count) {
		return;
	}
	vec3 p = direction_buffer.directions[index].xyz;
	float height = 0.0;
	if (params.grammar == 1u) {
		height = perun_height(p);
	} else if (params.grammar == 2u) {
		height = jarilo_height(p);
	} else if (params.grammar == 3u) {
		height = veles_height(p);
	} else if (params.grammar == 4u) {
		height = morena_height(p);
	} else if (params.grammar == 5u) {
		height = asteroid_height(p, params.asteroid_scale);
	}
	height_buffer.heights[index] = height;
	if (params.features_enabled == 1u) {
		vec4 feature = vec4(0.0);
		if (params.grammar == 1u) {
			feature = perun_features(p);
		} else if (params.grammar == 2u) {
			feature = jarilo_features(p);
		} else if (params.grammar == 3u) {
			feature = veles_features(p);
		} else if (params.grammar == 4u) {
			feature = morena_features(p);
		} else if (params.grammar == 5u) {
			feature = asteroid_features(p);
		}
		feature_buffer.features[index] = feature;
	}
}
