class_name PlanetBody
extends RefCounted
## One planet in its own frame (centre at the frame origin, non-rotating). Pure logic: gravity,
## atmosphere and terrain queries. Positions are WorldPos (64-bit).

const CRUISE_MIN_ALTITUDE_ABOVE_GROUND := 2000.0
## Below LEVEL_ASSIST_START_ALTITUDE metres the ship eases itself upright; full strength at LEVEL_ASSIST_FULL_ALTITUDE.
const LEVEL_ASSIST_START_ALTITUDE := 400.0
const LEVEL_ASSIST_FULL_ALTITUDE := 150.0

var frame_id: StringName = &"planet"
var radius: float
## Gravity at the reference radius, m/s^2. Falls off as 1/(r/R)^2 (research PLN-17).
var surface_gravity := 12.0
## Atmosphere thickness above radius, metres (research: 200 km).
var atmosphere_height := 200000.0
var height_function: HeightFunction
## Test hook: when set, replaces the noise: Callable(dx, dy, dz) -> float.
var height_override := Callable()


func _init(terrain_profile: TerrainProfile = TerrainProfile.new()) -> void:
	radius = terrain_profile.radius
	height_function = HeightFunction.new(terrain_profile)


## Quadtree depth at which a chunk is about 40 m across (about 1 m between vertices).
func finest_lod_level() -> int:
	return maxi(3, int(ceil(log(PI * radius / 80.0) / log(2.0))))


func terrain_height_xyz(dx: float, dy: float, dz: float) -> float:
	if height_override.is_valid():
		return height_override.call(dx, dy, dz)
	return height_function.height_xyz(dx, dy, dz)


## Distance from the planet centre to the terrain along the given unit direction.
func surface_radius_xyz(dx: float, dy: float, dz: float) -> float:
	return radius + terrain_height_xyz(dx, dy, dz)


func distance_from_center(position: WorldPos) -> float:
	return sqrt(position.x * position.x + position.y * position.y + position.z * position.z)


## Height of the ship's reference point above the terrain directly below it (metres).
func altitude_above_ground(position: WorldPos) -> float:
	var distance := distance_from_center(position)
	return distance - surface_radius_xyz(position.x / distance, position.y / distance, position.z / distance)


## 0 at the surface, 1 at the top of the atmosphere, above 1 in space (research FLY-27).
func atmosphere_ratio(position: WorldPos) -> float:
	if atmosphere_height <= 0.0:
		return INF # airless: always "in space"
	return maxf(0.0, (distance_from_center(position) - radius) / atmosphere_height)


func gravity_at(position: WorldPos) -> Vector3:
	var distance := maxf(distance_from_center(position), radius * 0.25)
	var strength := surface_gravity * (radius / distance) * (radius / distance)
	return -Vector3(position.x, position.y, position.z).normalized() * strength


## Local "up" (away from the planet centre) at a position.
func up_at(position: WorldPos) -> Vector3:
	var distance := distance_from_center(position)
	return Vector3(position.x / distance, position.y / distance, position.z / distance)


## Fills the per-tick environment for a ship at ship_state.
func fill_environment(ship_state: ShipState, environment: FlightEnvironment) -> void:
	var ratio := atmosphere_ratio(ship_state.position)
	ship_state.altitude_above_ground = altitude_above_ground(ship_state.position)
	environment.gravity = Vector3.ZERO if ship_state.landed else gravity_at(ship_state.position)
	if atmosphere_height <= 0.0:
		# No air to slow the ship, but still keep speed sane close to the ground.
		environment.max_speed_factor = lerpf(0.25, 1.0, smoothstep(100.0, 3000.0, ship_state.altitude_above_ground))
	else:
		environment.max_speed_factor = 1.0 if ratio >= 1.0 else lerpf(0.25, 1.0, smoothstep(0.1, 1.0, ratio))
	var cruise_allowed := ship_state.altitude_above_ground > CRUISE_MIN_ALTITUDE_ABOVE_GROUND
	environment.max_gear = PilotCommand.GEAR_CRUISE if cruise_allowed else PilotCommand.GEAR_COMBAT
	environment.cruise_speed_limit = maxf(500.0, ship_state.altitude_above_ground * 0.3)
	environment.level_up = up_at(ship_state.position)
	environment.level_assist = 0.0 if ship_state.landed or atmosphere_height <= 0.0 else clampf((LEVEL_ASSIST_START_ALTITUDE - ship_state.altitude_above_ground) / (LEVEL_ASSIST_START_ALTITUDE - LEVEL_ASSIST_FULL_ALTITUDE), 0.0, 1.0)
	ship_state.atmosphere_ratio = ratio
	ship_state.regime = FlightRegime.classify(ratio, ship_state.altitude_above_ground, ship_state.landed)
