class_name FlightEnvironment
extends RefCounted
## What the world does to a ship this tick. Empty space for now; M1 adds planet gravity,
## atmosphere and terrain queries.

var gravity := Vector3.ZERO
## Multiplies gear speed (atmosphere drag). 1 = none.
var max_speed_factor := 1.0
## Highest gear allowed here (cruise is refused near the ground).
var max_gear := 99
## Hard speed limit for cruise gear, m/s.
var cruise_speed_limit := INF
## Landing assist: when level_assist > 0 and the pilot is not pitching/rolling, the ship eases
## its up axis toward level_up (local planet up). 0 = off.
var level_up := Vector3.UP
var level_assist := 0.0
## Atmosphere density proxy, 0 at the top of the atmosphere and 1 at sea level.
var air_density := 0.0
## Speed lost per second to atmospheric drag along the velocity vector, m/s^2.
var drag_acceleration := 0.0
## Actual velocity-vector flight-path angle relative to the local horizon, degrees. Negative = descending.
var flight_path_angle_deg := 0.0
## Relative speed used by the entry model, m/s.
var entry_speed := 0.0
