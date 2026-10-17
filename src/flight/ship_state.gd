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


func speed() -> float:
	return velocity.length()
