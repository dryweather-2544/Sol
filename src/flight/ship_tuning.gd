class_name ShipTuning
extends Resource
## Handling numbers for one ship, per gear (Sol gear 0 dock, 1 combat, 2 cruise = Rodina gears 1, 2, 3). Values are
## the player-ship table of Rodina 1.6.2 (Scripts/DataGameplay/EGDataShipPlayer.lua, EGShipPlayer:UpdateGearSettings,
## lines 125-170), used by FlightModel in Sol's own implementation of the same rules; see docs/RODINA_PHYSICS_AUDIT.md.
## Cruise top speed is Sol's own distance-scaled limit (FlightEnvironment.cruise_speed_limit) instead of Rodina's
## relative-time multiplier; Sol's planets and distances are much smaller.

## Rodina MoveSpeed, m/s: the speed full thrust drives toward. Cruise is capped further by the environment.
@export var gear_max_speed := PackedFloat64Array([100.0, 500.0, 2.0e7])
## Rodina Acceleration: velocity change per second, as a fraction of MoveSpeed (dock 66 m/s^2, combat 1000 m/s^2).
@export var gear_acceleration := PackedFloat64Array([0.66, 2.0, 0.5])
## Rodina Deceleration: braking above MoveSpeed (fraction of current speed per second) and drag above DragSpeed.
@export var gear_deceleration := PackedFloat64Array([0.9, 0.75, 0.0])
## Rodina DragSpeed as a multiple of MoveSpeed (1500 m/s for dock and combat, 1.25 x MoveSpeed in cruise).
@export var gear_drag_speed_ratio := PackedFloat64Array([15.0, 3.0, 1.25])
## Rodina MoveStrengths, mapped to Sol axes: sideways (x), up/down (y) and backwards (+z). Forward is always full.
## They apply only while not braking (input with the motion, or none), so the ship can always stop.
@export var gear_lateral_strength := PackedFloat64Array([0.3, 0.3, 0.3])
@export var gear_vertical_strength := PackedFloat64Array([1.0, 0.3, 0.3])
@export var gear_reverse_strength := PackedFloat64Array([0.3, 0.6, 0.6])
## Rodina RotationHardness: how hard full turn input accelerates the spin, as a fraction of rotation_speed per second.
@export var gear_rotation_hardness := PackedFloat64Array([0.35, 0.7, 0.7])
## Atmosphere ratio at and below which rotation friction is the planet's full AtmosphereFriction (none at ratio 1 and
## above, i.e. in space). Rodina: 0.5 for dock and combat, 0.4 for cruise.
@export var gear_full_friction_ratio := PackedFloat64Array([0.5, 0.5, 0.4])
## Rodina EGShipPlayer.RotationSpeed, rad/s: cap on the combined pitch+yaw rate; roll is capped at twice this.
@export var rotation_speed := 2.5
## Sol additions (Rodina has neither): boost raises MoveSpeed; brake drives the velocity to zero at the rate full
## reverse thrust brakes in Rodina (brake_multiplier 1), without then reversing.
@export var boost_multiplier := 1.5
@export var brake_multiplier := 1.0


func gear_count() -> int:
	return gear_max_speed.size()
## Points on the hull that can touch the ground (ship-local). The first four are the landing
## gear, in the order GroundContact uses to fit the ground plane: (-x,-z) (+x,-z) (-x,+z) (+x,+z).
## The rest (nose and tail underside) only stop the hull passing through terrain; wings are not solid.
@export var support_points := PackedVector3Array([
	Vector3(-2.6, -2.0, -5.0), Vector3(2.6, -2.0, -5.0), Vector3(-2.6, -2.0, 8.5), Vector3(2.6, -2.0, 8.5),
	Vector3(0, -0.9, -7.3), Vector3(0, -0.9, 10.9)])
