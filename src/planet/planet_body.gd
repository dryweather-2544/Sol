class_name PlanetBody
extends RefCounted
## One planet in its own frame (centre at the frame origin, non-rotating). Pure logic: gravity,
## atmosphere and terrain queries. Positions are WorldPos (64-bit).

const CRUISE_MIN_ALTITUDE_ABOVE_GROUND := 2000.0
const CRUISE_SPEED_LIMIT_IN_ATMOSPHERE := 8000.0
## Ships feel planet gravity 3.5 times as strongly as people on foot (Rodina kGravityMovementMult = 9.8 * 3.5 per g of
## SurfaceGravity, EGVehicle.lua:8, applied at 1548-1554), and at least 0.33 g of surface gravity on any world
## (kGravityMinPlanetGravity, :9, via EGPlanet:GetGravity's minimum). Walkers use gravity_at unscaled.
const SHIP_GRAVITY_MULTIPLIER := 3.5
const SHIP_MIN_SURFACE_GRAVITY_G := 0.33
const STANDARD_GRAVITY := 9.8

var frame_id: StringName = &"planet"
var radius: float
## Gravity at the reference radius, m/s^2. Falls off as 1/(r/R)^2 (research PLN-17).
var surface_gravity := 12.0
## Atmosphere thickness above radius, metres (research: 200 km).
var atmosphere_height := 200000.0
## Rodina AtmosphereFriction: how strongly the air damps a coasting ship's spin (1 on most worlds, 1.5 on Veles).
var atmosphere_friction := 1.0
## Can a person breathe at the surface without a suit tank?
var breathable := true
var height_function: HeightFunction
## How this world is drawn under the active visual style (colours only; never height). null = the original Sol rule.
var look: PlanetLook

func profile_or_default() -> TerrainProfile:
	return height_function.profile

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


## Gravity a ship feels here: planet gravity with at least SHIP_MIN_SURFACE_GRAVITY_G at the surface, times
## SHIP_GRAVITY_MULTIPLIER, falling off as 1/(r/R)^2 like gravity_at.
func ship_gravity_at(position: WorldPos) -> Vector3:
	var distance := maxf(distance_from_center(position), radius * 0.25)
	var surface := maxf(surface_gravity, SHIP_MIN_SURFACE_GRAVITY_G * STANDARD_GRAVITY) * SHIP_GRAVITY_MULTIPLIER
	return -Vector3(position.x, position.y, position.z).normalized() * surface * (radius / distance) * (radius / distance)


## Local "up" (away from the planet centre) at a position.
func up_at(position: WorldPos) -> Vector3:
	var distance := distance_from_center(position)
	return Vector3(position.x / distance, position.y / distance, position.z / distance)


## Fills the per-tick environment for a ship at ship_state.
func fill_environment(ship_state: ShipState, environment: FlightEnvironment) -> void:
	var ratio := atmosphere_ratio(ship_state.position)
	ship_state.altitude_above_ground = altitude_above_ground(ship_state.position)
	environment.gravity = Vector3.ZERO if ship_state.landed else ship_gravity_at(ship_state.position)
	var cruise_allowed := ship_state.altitude_above_ground > CRUISE_MIN_ALTITUDE_ABOVE_GROUND
	environment.max_gear = PilotCommand.GEAR_CRUISE if cruise_allowed else PilotCommand.GEAR_COMBAT
	environment.cruise_speed_limit = maxf(500.0, ship_state.altitude_above_ground * 0.3)
	if ratio < 1.0:
		environment.cruise_speed_limit = minf(environment.cruise_speed_limit, CRUISE_SPEED_LIMIT_IN_ATMOSPHERE)
	environment.level_up = up_at(ship_state.position)
	environment.atmosphere_ratio = ratio
	environment.atmosphere_friction = atmosphere_friction if atmosphere_height > 0.0 else 0.0
	environment.surface_gravity_g = surface_gravity / STANDARD_GRAVITY
	ship_state.atmosphere_ratio = ratio
	ship_state.regime = FlightRegime.classify(ratio, ship_state.altitude_above_ground, ship_state.landed)
