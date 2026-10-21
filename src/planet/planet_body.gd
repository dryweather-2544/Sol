class_name PlanetBody
extends RefCounted
## One planet in its own frame (centre at the frame origin, non-rotating). Pure logic: gravity,
## atmosphere and terrain queries. Positions are WorldPos (64-bit).

## Cruise speeds (see cruise_speed_limit). Rodina: 5000 m/s at the surface, 10000 m/s from 20 km, 5000 m/s while
## entering the air (kAmosphericEntrySpeed). Sol: above the air, 0.3 m/s per metre of altitude, 500 m/s to 2e7 m/s.
const CRUISE_SURFACE_SPEED := 5000.0
const CRUISE_HIGH_SPEED := 10000.0
const CRUISE_HIGH_SPEED_ALTITUDE := 20000.0
const CRUISE_ENTRY_SPEED := 5000.0
const CRUISE_SPEED_PER_METRE_OF_ALTITUDE := 0.3
const CRUISE_MIN_SPEED := 500.0
const CRUISE_MAX_SPEED := 2.0e7
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
## The warp drive is installed (set by WorldRuntime each tick): warp is then allowed above the air.
var warp_allowed := false
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


## Cruise-gear top speed here, m/s.
## - In the air: Rodina's cruise MoveSpeed, 5000 m/s at the surface rising to 10000 m/s 20 km up
##   (EGDataShipPlayer.lua:169), and no more than 5000 m/s while still entering (EGVehicle:UpdateGearSettings,
##   EGVehicle.lua:947-955; relative time is also off in the air there).
## - Above the air (and over airless worlds): Sol's distance-scaled limit (0.3 x altitude, 2e7 m/s at most), standing
##   in for Rodina's relative time; never below the in-air speed at the top of the atmosphere, so leaving it is smooth.
## - Airless worlds near their surface keep Sol's 0.3 x altitude (at least 500 m/s): a tiny moon or asteroid cannot
##   take Rodina's 5 km/s at ground level.
func cruise_speed_limit(altitude: float, ratio: float, in_atmosphere: bool) -> float:
	var distance_scaled := clampf(altitude * CRUISE_SPEED_PER_METRE_OF_ALTITUDE, CRUISE_MIN_SPEED, CRUISE_MAX_SPEED)
	if atmosphere_height <= 0.0:
		return distance_scaled
	var in_air_speed := lerpf(CRUISE_SURFACE_SPEED, CRUISE_HIGH_SPEED, clampf(altitude / CRUISE_HIGH_SPEED_ALTITUDE, 0.0, 1.0))
	if ratio < 1.0:
		return in_air_speed if in_atmosphere else minf(in_air_speed, CRUISE_ENTRY_SPEED)
	return maxf(distance_scaled, CRUISE_HIGH_SPEED)


## Fills the per-tick environment for a ship at ship_state.
func fill_environment(ship_state: ShipState, environment: FlightEnvironment) -> void:
	var ratio := atmosphere_ratio(ship_state.position)
	ship_state.altitude_above_ground = altitude_above_ground(ship_state.position)
	environment.gravity = Vector3.ZERO if ship_state.landed else ship_gravity_at(ship_state.position)
	# Cruise is allowed at any height, as in Rodina (gated only by the story there, EGDataShipPlayer.lua:52-81). Warp, once
	# the drive is installed, anywhere above the air (Rodina CheckLimnalViability: not inside the atmosphere,
	# EGVehicle.lua:1586-1589), as long as the path does not hit the air soon (warp_clearance, ray to the air's top).
	environment.max_gear = PilotCommand.GEAR_WARP if warp_allowed and ratio >= 1.0 else PilotCommand.GEAR_CRUISE
	var speed := ship_state.velocity.length()
	environment.warp_clearance = FlightEnvironment.ray_to_sphere(ship_state.position.x, ship_state.position.y, ship_state.position.z, ship_state.velocity / speed, 0.0, 0.0, 0.0, radius + maxf(atmosphere_height, 0.0)) if speed > 1e-6 else INF
	environment.cruise_speed_limit = cruise_speed_limit(ship_state.altitude_above_ground, ratio, ship_state.in_atmosphere)
	environment.level_up = up_at(ship_state.position)
	environment.atmosphere_ratio = ratio
	environment.atmosphere_friction = atmosphere_friction if atmosphere_height > 0.0 else 0.0
	environment.surface_gravity_g = surface_gravity / STANDARD_GRAVITY
	ship_state.atmosphere_ratio = ratio
	ship_state.regime = FlightRegime.classify(ratio, ship_state.altitude_above_ground, ship_state.landed)
