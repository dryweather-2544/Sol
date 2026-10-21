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
## Distance along the ship's velocity to the first atmosphere top it would hit (the surface of airless bodies and
## stars), metres; INF when its path misses every body. Warp is refused when the ship would get there within
## FlightModel.WARP_LOOKAHEAD_SECONDS (Rodina CheckLimnalViability / CheckLimnalAtmosphereCollision ray-sphere test).
var warp_clearance := INF


## Distance from origin along unit direction to where the ray enters the sphere (centre, radius); INF if it misses or
## points away. Scalars, so system-frame positions keep their double precision.
static func ray_to_sphere(ox: float, oy: float, oz: float, direction: Vector3, cx: float, cy: float, cz: float, radius: float) -> float:
	var rx := ox - cx
	var ry := oy - cy
	var rz := oz - cz
	var b := rx * direction.x + ry * direction.y + rz * direction.z
	var c := rx * rx + ry * ry + rz * rz - radius * radius
	if c <= 0.0:
		return 0.0 # already inside
	var h := b * b - c
	if b >= 0.0 or h < 0.0:
		return INF
	return -b - sqrt(h)
