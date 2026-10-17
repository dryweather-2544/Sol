class_name SystemNavigator
extends RefCounted
## Flight environment for a ship in the star-centred system frame (outside every body's sphere of
## influence): no gravity or air, and cruise speed scaled by distance to the nearest body, so
## crossing the system takes seconds yet arriving is gentle (the cap shrinks as a surface nears).

var system: StarSystem
## Current game time, set by the runtime each tick.
var time_seconds := 0.0


func _init(star_system: StarSystem) -> void:
	system = star_system


func fill_environment(ship_state: ShipState, environment: FlightEnvironment) -> void:
	var distance := system.distance_to_nearest_surface(ship_state.position, time_seconds)
	environment.gravity = Vector3.ZERO
	environment.max_speed_factor = 1.0
	environment.max_gear = PilotCommand.GEAR_CRUISE
	environment.cruise_speed_limit = clampf(distance * 0.3, 500.0, 2.0e7)
	environment.level_assist = 0.0
	ship_state.altitude_above_ground = distance
	ship_state.atmosphere_ratio = INF
	ship_state.regime = FlightRegime.SPACE
