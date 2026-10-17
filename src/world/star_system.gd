class_name StarSystem
extends RefCounted
## The whole solar system as data: bodies, analytic orbits, and conversions between the system
## frame (star at the origin) and each body's own non-rotating frame. Pure logic.

const SYSTEM_FRAME: StringName = &"system"
const SOI_EXIT_FACTOR := 1.2 ## leave a body's frame at 1.2x its sphere of influence, so the edge does not flicker

var bodies := {} # id -> BodyDef
var star_id: StringName = &"sol"
var home_id: StringName = &"planet"


## The shipped system: a star, an inner hot world, the home planet with a moon, a big outer
## world and an asteroid. Home keeps the id "planet" so older saves still point at it.
static func default_system() -> StarSystem:
	var system := StarSystem.new()
	var star := BodyDef.new()
	star.id = &"sol"
	star.display_name = "Sol"
	star.is_star = true
	star.radius = 3.0e8
	star.atmosphere_height = 0.0
	star.color = Color(1.0, 0.9, 0.6)
	system.bodies[star.id] = star

	var home := BodyDef.new()
	home.id = &"planet"
	home.display_name = "Aurelia"
	home.radius = 6.0e6
	home.surface_gravity = 12.0
	home.atmosphere_height = 200000.0
	home.orbit_radius = 1.5e9
	home.orbit_period = 2.0e6
	home.spin_period = 6000.0
	home.terrain_profile = TerrainProfile.new()
	home.color = Color(0.4, 0.55, 0.35)
	system.bodies[home.id] = home

	var moon := BodyDef.new()
	moon.id = &"selene"
	moon.display_name = "Selene"
	moon.parent_id = &"planet"
	moon.radius = 1.7e6
	moon.surface_gravity = 3.5
	moon.atmosphere_height = 0.0
	moon.orbit_radius = 1.0e8
	moon.orbit_period = 1.0e6
	moon.orbit_phase = 1.0
	moon.spin_period = 9000.0
	moon.terrain_profile = _profile(7777, 1.7e6, 500.0, 1100.0, 4.0, 1.0)
	moon.terrain_profile.mid_amplitude = 100.0
	moon.terrain_profile.large_amplitude = 300.0
	moon.color = Color(0.7, 0.7, 0.72)
	system.bodies[moon.id] = moon

	var inner := BodyDef.new()
	inner.id = &"cinder"
	inner.display_name = "Cinder"
	inner.radius = 4.2e6
	inner.surface_gravity = 7.0
	inner.atmosphere_height = 60000.0
	inner.orbit_radius = 0.7e9
	inner.orbit_period = 0.9e6
	inner.orbit_phase = 2.2
	inner.spin_period = 7500.0
	inner.terrain_profile = _profile(4242, 4.2e6, 1800.0, 4800.0, 10.0, 2.0)
	inner.color = Color(0.75, 0.35, 0.2)
	system.bodies[inner.id] = inner

	var outer := BodyDef.new()
	outer.id = &"verdant"
	outer.display_name = "Verdant"
	outer.radius = 8.5e6
	outer.surface_gravity = 15.0
	outer.atmosphere_height = 300000.0
	outer.orbit_radius = 2.6e9
	outer.orbit_period = 4.5e6
	outer.orbit_phase = 4.0
	outer.spin_period = 5400.0
	outer.terrain_profile = _profile(9090, 8.5e6, 2000.0, 3000.0, 9.0, 1.8)
	outer.color = Color(0.3, 0.5, 0.65)
	system.bodies[outer.id] = outer

	var asteroid := BodyDef.new()
	asteroid.id = &"pebble"
	asteroid.display_name = "Pebble"
	asteroid.radius = 1.5e4
	asteroid.surface_gravity = 0.6
	asteroid.atmosphere_height = 0.0
	asteroid.orbit_radius = 3.3e9
	asteroid.orbit_period = 6.0e6
	asteroid.orbit_phase = 0.5
	asteroid.spin_period = 1200.0
	asteroid.terrain_profile = _profile(31337, 1.5e4, 1500.0, 0.0, 2.0, 0.5)
	asteroid.terrain_profile.macro_scale = 3.0
	asteroid.terrain_profile.mid_amplitude = 60.0
	asteroid.terrain_profile.large_amplitude = 150.0
	asteroid.terrain_profile.mid_wavelength = 1500.0
	asteroid.terrain_profile.large_wavelength = 6000.0
	asteroid.color = Color(0.5, 0.45, 0.4)
	system.bodies[asteroid.id] = asteroid
	return system


static func _profile(terrain_seed: int, radius: float, macro: float, mountains: float, hills: float, rough: float) -> TerrainProfile:
	var profile := TerrainProfile.new()
	profile.terrain_seed = terrain_seed
	profile.radius = radius
	profile.macro_amplitude = macro
	profile.mountain_amplitude = mountains
	profile.hill_amplitude = hills
	profile.rough_amplitude = rough
	return profile


## Body centre in the system frame (star-centred, metres) at game time t seconds.
func body_position(body_id: StringName, time_seconds: float) -> Vector3D:
	var body: BodyDef = bodies[body_id]
	if body.is_star:
		return Vector3D.new(0.0, 0.0, 0.0)
	var parent_position := Vector3D.new(0.0, 0.0, 0.0) if body.parent_id == &"" else body_position(body.parent_id, time_seconds)
	var angle := body.orbit_phase + TAU * time_seconds / body.orbit_period
	return Vector3D.new(parent_position.x + cos(angle) * body.orbit_radius, parent_position.y, parent_position.z + sin(angle) * body.orbit_radius)


## Body velocity in the system frame (metres per second), the analytic derivative of body_position.
func body_velocity(body_id: StringName, time_seconds: float) -> Vector3D:
	var body: BodyDef = bodies[body_id]
	if body.is_star:
		return Vector3D.new(0.0, 0.0, 0.0)
	var parent_velocity := Vector3D.new(0.0, 0.0, 0.0) if body.parent_id == &"" else body_velocity(body.parent_id, time_seconds)
	var angle := body.orbit_phase + TAU * time_seconds / body.orbit_period
	var speed := TAU * body.orbit_radius / body.orbit_period
	return Vector3D.new(parent_velocity.x - sin(angle) * speed, parent_velocity.y, parent_velocity.z + cos(angle) * speed)


## A body's frame id is its own id; the star-centred frame is SYSTEM_FRAME.
func frame_origin(frame_id: StringName, time_seconds: float) -> Vector3D:
	if frame_id == SYSTEM_FRAME:
		return Vector3D.new(0.0, 0.0, 0.0)
	return body_position(frame_id, time_seconds)


func frame_velocity(frame_id: StringName, time_seconds: float) -> Vector3D:
	if frame_id == SYSTEM_FRAME:
		return Vector3D.new(0.0, 0.0, 0.0)
	return body_velocity(frame_id, time_seconds)


## Re-express a position given in `position.frame_id` in `target_frame` (same instant).
func convert_position(position: WorldPos, target_frame: StringName, time_seconds: float) -> WorldPos:
	var source_origin := frame_origin(position.frame_id, time_seconds)
	var target_origin := frame_origin(target_frame, time_seconds)
	return WorldPos.new(target_frame, position.x + source_origin.x - target_origin.x, position.y + source_origin.y - target_origin.y, position.z + source_origin.z - target_origin.z)


## Re-express a velocity given relative to `from_frame` as relative to `to_frame` (Galilean).
func convert_velocity(velocity: Vector3, from_frame: StringName, to_frame: StringName, time_seconds: float) -> Vector3:
	var from_velocity := frame_velocity(from_frame, time_seconds)
	var to_velocity := frame_velocity(to_frame, time_seconds)
	return velocity + Vector3(from_velocity.x - to_velocity.x, from_velocity.y - to_velocity.y, from_velocity.z - to_velocity.z)


## Which frame a position (in any frame) belongs to: the body whose sphere of influence it is inside
## (the one it is deepest inside, relative to its size), else the system frame. `current_frame` gets
## hysteresis: a ship stays in its frame until 1.2x the sphere of influence.
func frame_for(position: WorldPos, time_seconds: float, current_frame: StringName) -> StringName:
	var system_position := convert_position(position, SYSTEM_FRAME, time_seconds)
	var best: StringName = SYSTEM_FRAME
	var best_ratio := INF
	for body_id in bodies:
		var body: BodyDef = bodies[body_id]
		if body.is_star:
			continue
		var center := body_position(body_id, time_seconds)
		var distance := sqrt(pow(system_position.x - center.x, 2.0) + pow(system_position.y - center.y, 2.0) + pow(system_position.z - center.z, 2.0))
		var limit := body.sphere_of_influence() * (SOI_EXIT_FACTOR if body_id == current_frame else 1.0)
		var ratio := distance / limit
		if ratio < 1.0 and ratio < best_ratio:
			best = body_id
			best_ratio = ratio
	return best


## Distance from a system-frame point to the nearest body surface (stars included), for travel speed.
func distance_to_nearest_surface(system_position: WorldPos, time_seconds: float) -> float:
	var nearest := INF
	for body_id in bodies:
		var body: BodyDef = bodies[body_id]
		var center := body_position(body_id, time_seconds)
		var distance := sqrt(pow(system_position.x - center.x, 2.0) + pow(system_position.y - center.y, 2.0) + pow(system_position.z - center.z, 2.0)) - body.radius
		nearest = minf(nearest, distance)
	return maxf(nearest, 0.0)


## Direction sunlight travels at a position inside a body's frame, including the day/night turn
## of the planet (the sun circles the sky once per spin_period).
func sun_direction_in_frame(frame_id: StringName, time_seconds: float) -> Vector3:
	if frame_id == SYSTEM_FRAME:
		return Vector3(0, 0, -1)
	var center := body_position(frame_id, time_seconds)
	var away_from_star := Vector3(center.x, center.y, center.z).normalized()
	var body: BodyDef = bodies[frame_id]
	return away_from_star.rotated(Vector3.UP, -TAU * time_seconds / body.spin_period)


func build_planet_body(body_id: StringName) -> PlanetBody:
	var body: BodyDef = bodies[body_id]
	var planet := PlanetBody.new(body.terrain_profile)
	planet.frame_id = body.id
	planet.surface_gravity = body.surface_gravity
	planet.atmosphere_height = body.atmosphere_height
	return planet
