// One Rodina particle style (EGDataParticles.lua Styles[1]) as a Godot particle process shader. RodinaEmitter fills the
// uniforms from RodinaParticleDefs, already scaled to Sol's ship. The emitter node's +Y is the AttachParticles direction.
// Reading of Rodina's fields (engine-side, not in the Lua; see RodinaEmitter for why):
//   spawn point = Offset + a random point in a sphere of radius Size (Size 0 = the point itself)
//   normal      = unit vector from the sphere's centre to the spawn point (a random direction when Size is 0)
//   velocity    = VelocityBase + VelocityRange * random(-1..1 per axis) + normal * (VelocityNormalBase + random(0..1) * VelocityNormalRange)
//   acceleration= Acceleration + normal * AccelerationNormal          (constant over the particle's life)
//   keys        = Color / Alpha / Size piecewise-linear over age / Lifetime (held before the first and after the last key)
// world_rotation = 1 (WORLD_ROTATION and default orientations): the particle follows the emitter's position but keeps the
// world orientation it was born with, so turning the ship does not swing the trail; 0 (LOCAL): fully ship-relative.
shader_type particles;
render_mode disable_force, disable_velocity;

uniform vec3 offset;
uniform float spawn_radius;
uniform vec3 velocity_base;
uniform vec3 velocity_range;
uniform float velocity_normal_base;
uniform float velocity_normal_range;
uniform vec3 acceleration;
uniform float acceleration_normal;
uniform int world_rotation = 1;
uniform int key_count = 2;
uniform float key_time[5];
uniform vec4 key_color[5]; // rgb colour, a alpha
uniform float key_size[5];

float rand_from(inout uint state) {
	state = state * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	word = (word >> 22u) ^ word;
	return float(word) / 4294967295.0;
}

void key_at(float t, out vec4 color, out float size) {
	color = key_color[0];
	size = key_size[0];
	for (int i = 1; i < 5; i++) {
		if (i >= key_count) {
			break;
		}
		float t0 = key_time[i - 1];
		float t1 = key_time[i];
		if (t >= t1) {
			color = key_color[i];
			size = key_size[i];
		} else if (t > t0) {
			float f = (t - t0) / max(t1 - t0, 1e-6);
			color = mix(key_color[i - 1], key_color[i], f);
			size = mix(key_size[i - 1], key_size[i], f);
			break;
		} else {
			break;
		}
	}
}

void start() {
	uint state = RANDOM_SEED ^ (INDEX * 9781u + NUMBER * 6271u);
	vec3 in_sphere;
	vec3 normal;
	// Uniform direction, then a radius with cube-root weighting so the sphere is evenly filled.
	float z = rand_from(state) * 2.0 - 1.0;
	float a = rand_from(state) * 6.2831853;
	float r = sqrt(max(0.0, 1.0 - z * z));
	normal = vec3(r * cos(a), z, r * sin(a));
	in_sphere = normal * spawn_radius * pow(rand_from(state), 1.0 / 3.0);
	vec3 jitter = vec3(rand_from(state), rand_from(state), rand_from(state)) * 2.0 - 1.0;
	vec3 position = offset + in_sphere;
	vec3 velocity = velocity_base + velocity_range * jitter + normal * (velocity_normal_base + rand_from(state) * velocity_normal_range);
	vec3 accel = acceleration + normal * acceleration_normal;
	if (world_rotation == 1) {
		mat3 frame = mat3(normalize(EMISSION_TRANSFORM[0].xyz), normalize(EMISSION_TRANSFORM[1].xyz), normalize(EMISSION_TRANSFORM[2].xyz));
		float length_scale = length(EMISSION_TRANSFORM[0].xyz);
		position = frame * position * length_scale;
		velocity = frame * velocity * length_scale;
		accel = frame * accel * length_scale;
	}
	USERDATA1 = vec4(position, 0.0);
	USERDATA2 = vec4(velocity, 0.0);
	USERDATA3 = vec4(accel, 0.0);
	CUSTOM = vec4(0.0);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = (world_rotation == 1 ? EMISSION_TRANSFORM[3].xyz : vec3(0.0)) + position;
}

void process() {
	CUSTOM.y += DELTA;
	float age = CUSTOM.y;
	vec3 position = USERDATA1.xyz + USERDATA2.xyz * age + 0.5 * USERDATA3.xyz * age * age;
	vec4 color;
	float size;
	key_at(clamp(age / LIFETIME, 0.0, 1.0), color, size);
	COLOR = color;
	float scale = world_rotation == 1 ? length(EMISSION_TRANSFORM[0].xyz) : 1.0;
	TRANSFORM = mat4(1.0);
	TRANSFORM[0].xyz *= size * scale;
	TRANSFORM[1].xyz *= size * scale;
	TRANSFORM[2].xyz *= size * scale;
	TRANSFORM[3].xyz = (world_rotation == 1 ? EMISSION_TRANSFORM[3].xyz : vec3(0.0)) + position;
	if (age > LIFETIME) {
		ACTIVE = false;
	}
}
