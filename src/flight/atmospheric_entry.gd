class_name AtmosphericEntry
extends RefCounted
## Original, game-scale atmospheric-entry model. It is deliberately not a hypersonic solver:
## density and heating are smooth proxies chosen so the player can read angle/speed/heat and
## recover. The important physical distinction is that the corridor uses the actual velocity
## vector, not the ship's nose direction.

enum Corridor { SPACE, SHALLOW, CONTROLLED, STEEP, TOO_FAST }

const DENSITY_POWER := 1.8
const DRAG_SCALE := 90000.0
const DRAG_CAP := 420.0
const HEAT_RATE_SCALE := 0.35
const COOLING_BASE := 0.020
const COOLING_DENSITY := 0.035
const HEAT_DAMAGE_START := 0.75
const HEAT_DAMAGE_SCALE := 0.12
const WARNING_HEAT := 0.35
const CRITICAL_HEAT := 0.68
const SHALLOW_ANGLE := -3.0
const STEEP_ANGLE := -55.0
const FAST_SPEED := 9000.0
const SPEED_FOR_HEAT := 1000.0
const SPEED_RANGE_FOR_HEAT := 5000.0
const MAX_HEAT := 1.5


## Fill the environment and per-ship entry telemetry for the current tick. Call after
## PlanetBody.fill_environment has set altitude/gravity, and before FlightModel.step so drag
## is applied in the same tick.
static func fill_environment(ship_state: ShipState, planet: PlanetBody, environment: FlightEnvironment) -> void:
	if planet == null or planet.atmosphere_height <= 0.0:
		environment.air_density = 0.0
		environment.drag_acceleration = 0.0
		environment.flight_path_angle_deg = 0.0
		environment.entry_speed = ship_state.velocity.length()
		ship_state.entry_density = 0.0
		ship_state.entry_speed = environment.entry_speed
		ship_state.entry_corridor = Corridor.SPACE
		ship_state.entry_warning = ""
		ship_state.entry_heat_rate = 0.0
		ship_state.entry_atmosphere_height = 0.0
		return
	var ratio := planet.atmosphere_ratio(ship_state.position)
	var density := pow(clampf(1.0 - ratio, 0.0, 1.0), DENSITY_POWER)
	var speed := ship_state.velocity.length()
	var up := planet.up_at(ship_state.position)
	var vertical := ship_state.velocity.dot(up)
	var horizontal := sqrt(maxf(0.0, speed * speed - vertical * vertical))
	var angle := rad_to_deg(atan2(vertical, horizontal))
	var descent := clampf(-vertical / maxf(speed, 1.0), 0.0, 1.0)
	var drag := minf(DRAG_CAP, density * speed * speed / DRAG_SCALE * (0.55 + 0.45 * descent))
	environment.air_density = density
	environment.drag_acceleration = drag
	environment.flight_path_angle_deg = angle
	environment.entry_speed = speed
	ship_state.entry_density = density
	ship_state.entry_speed = speed
	ship_state.entry_angle_deg = angle
	ship_state.entry_atmosphere_height = planet.atmosphere_height
	ship_state.entry_corridor = _classify(density, speed, angle, ship_state.altitude_above_ground, planet.atmosphere_height)
	ship_state.entry_heat_rate = _heat_rate(density, speed, descent)
	ship_state.entry_warning = _warning(ship_state, density, speed, angle)


## Integrate thermal load and damage rate. Kept separate so tests can step the same maths
## without a Node or a rendered frame.
static func step_thermal(ship_state: ShipState, delta: float) -> void:
	if ship_state.landed:
		# Once the ship is down, the airflow is gone. Let the hull cool quickly and stop
		# applying thermal damage; a landing should be the end of the entry, not a slow burn.
		ship_state.entry_heat = move_toward(ship_state.entry_heat, 0.0, 0.25 * delta)
		ship_state.entry_damage_rate = 0.0
		ship_state.entry_warning = ""
		return
	var cooling := COOLING_BASE + ship_state.entry_density * COOLING_DENSITY
	var net := ship_state.entry_heat_rate - cooling
	ship_state.entry_heat = clampf(ship_state.entry_heat + net * delta, 0.0, MAX_HEAT)
	ship_state.entry_damage_rate = maxf(0.0, ship_state.entry_heat - HEAT_DAMAGE_START) * HEAT_DAMAGE_SCALE
	if ship_state.entry_heat <= 0.001 and ship_state.entry_density <= 0.001:
		ship_state.entry_heat = 0.0
	ship_state.entry_warning = _warning(ship_state, ship_state.entry_density, ship_state.entry_speed, ship_state.entry_angle_deg)


static func corridor_label(corridor: int) -> String:
	return ["SPACE", "SHALLOW", "CONTROLLED", "STEEP", "TOO FAST"][clampi(corridor, 0, 4)]


static func _classify(density: float, speed: float, angle: float, altitude: float, atmosphere_height: float) -> int:
	if density <= 0.01 and altitude > atmosphere_height * 1.05:
		return Corridor.SPACE
	if speed > FAST_SPEED:
		return Corridor.TOO_FAST
	if angle > SHALLOW_ANGLE:
		return Corridor.SHALLOW
	if angle < STEEP_ANGLE:
		return Corridor.STEEP
	return Corridor.CONTROLLED


static func _heat_rate(density: float, speed: float, descent: float) -> float:
	if density <= 0.0:
		return 0.0
	var speed_factor := maxf(0.0, speed - SPEED_FOR_HEAT) / SPEED_RANGE_FOR_HEAT
	return density * speed_factor * speed_factor * (0.55 + 0.45 * descent) * HEAT_RATE_SCALE


static func _warning(ship_state: ShipState, density: float, speed: float, angle: float) -> String:
	if density <= 0.005 and ship_state.altitude_above_ground > ship_state.entry_atmosphere_height * 1.05:
		return ""
	if ship_state.entry_heat >= CRITICAL_HEAT:
		return "CRITICAL HEAT - PULL UP OR BRAKE"
	if ship_state.entry_heat >= WARNING_HEAT:
		return "HULL HEATING - REDUCE SPEED"
	if speed < 1200.0:
		return ""
	if speed > FAST_SPEED:
		return "ENTRY TOO FAST - BRAKE"
	if angle < STEEP_ANGLE:
		return "STEEP ENTRY - PULL UP"
	if angle > SHALLOW_ANGLE:
		return "SHALLOW APPROACH - MAY SKIP"
	return ""
