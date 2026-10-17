class_name ShipState
extends RefCounted
## Pure flight data for one ship. Position is a WorldPos (64-bit); the rest is small enough
## for Vector3.

var position := WorldPos.new(&"space")
## World-frame velocity, metres per second.
var velocity := Vector3.ZERO
## Ship orientation in its frame; columns are the ship's right, up and back axes.
var basis := Basis.IDENTITY
## Ship-local angular velocity, radians per second about local x (pitch), y (yaw), z (roll).
var angular_velocity := Vector3.ZERO
var gear := PilotCommand.GEAR_DOCK

## Planet-relative telemetry, written by PlanetBody.fill_environment and GroundContact.
var landed := false
var altitude_above_ground := INF
var atmosphere_ratio := INF
var regime := FlightRegime.SPACE
var status_message := ""

## 1 = undamaged, 0 = destroyed.
var hull := 1.0
## Speed (m/s) into the ground on the latest tick; 0 when nothing was hit.
var last_impact_speed := 0.0


func speed() -> float:
	return velocity.length()
