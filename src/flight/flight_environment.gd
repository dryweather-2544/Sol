class_name FlightEnvironment
extends RefCounted
## What the world does to a ship this tick, filled by PlanetBody (or SystemNavigator in open space). Empty space by default.

## Acceleration the ship feels, m/s^2 (planet frame). For ships this is Rodina's ship gravity (PlanetBody.ship_gravity_at).
var gravity := Vector3.ZERO
## Highest gear allowed here (cruise is refused near the ground).
var max_gear := 99
## Hard speed limit for cruise gear, m/s (Sol's stand-in for Rodina's cruise relative time).
var cruise_speed_limit := INF
## Local "up" (away from the planet centre); the roll levelling and the telemetry measure attitude against it.
var level_up := Vector3.UP
## (altitude) / (atmosphere height): 0 at the surface, 1 at the top of the air, INF in space or over an airless world.
var atmosphere_ratio := INF
## The planet's AtmosphereFriction (Rodina): rotation friction deep in its air. 0 = none.
var atmosphere_friction := 0.0
## Surface gravity in g (Rodina SurfaceGravity), for the roll levelling's gravity factor.
var surface_gravity_g := 1.0
## Strength of the roll levelling, 0..1 (Rodina ShipHorizonRollStrength; the player's setting, 1 for other ships).
var horizon_levelling := 1.0
