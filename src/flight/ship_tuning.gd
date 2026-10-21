class_name ShipTuning
extends Resource
## Handling numbers for one ship, per gear (Sol gear 0 dock, 1 combat, 2 cruise = Rodina gears 1, 2, 3). Values are
## the player-ship table of Rodina 1.6.2 (Scripts/DataGameplay/EGDataShipPlayer.lua, EGShipPlayer:UpdateGearSettings,
## lines 131-177), used by FlightModel in Sol's own implementation of the same rules; see docs/RODINA_PHYSICS_AUDIT.md.
## Cruise top speed is Sol's own distance-scaled limit (FlightEnvironment.cruise_speed_limit) instead of Rodina's
## relative-time multiplier; Sol's planets and distances are much smaller.

## Rodina MoveSpeed, m/s: the speed full thrust drives toward. Cruise is capped further by the environment.
## Gear 0 is Sol's PRECISION gear (Rodina's dock/landing gear, scaled to Sol's ship): Rodina's 100 m/s suits a ship
## whose ramp alone is 32.4 m long (EGDataItems.lua:1155); Sol's whole ship is about 20 m, its ramp 4.2 m, so 30 m/s
## (Sol's choice) gives the same few-ship-lengths-per-second feel near the ground.
@export var gear_max_speed := PackedFloat64Array([30.0, 500.0, 2.0e7, 1.0e8])
## Rodina Acceleration: velocity change per second, as a fraction of MoveSpeed (dock 66 m/s^2, combat 1000 m/s^2).
@export var gear_acceleration := PackedFloat64Array([0.66, 2.0, 0.5, 1.0]) # warp: Rodina gear 4 Acceleration 1
## Rodina Deceleration: braking above MoveSpeed (fraction of current speed per second) and drag above DragSpeed.
@export var gear_deceleration := PackedFloat64Array([0.9, 0.75, 0.0, 0.0])
## Rodina DragSpeed as a multiple of MoveSpeed (1500 m/s for dock and combat, 1.25 x MoveSpeed in cruise).
@export var gear_drag_speed_ratio := PackedFloat64Array([15.0, 3.0, 1.25, 1.25])
## Rodina MoveStrengths, mapped to Sol axes: sideways (x), up/down (y) and backwards (+z). Forward is always full.
## They apply only while not braking (input with the motion, or none), so the ship can always stop.
## Precision vertical is 0.4 (Rodina dock: 1.0) so full down thrust (12 m/s) touches down under the 15 m/s damage limit.
## Warp: Rodina gear 4 MoveStrengths (0, 0, 0) and a fixed forward drive (EGDataShipPlayer.lua:211-220, EGVehicle.lua:1437-1441).
@export var gear_lateral_strength := PackedFloat64Array([0.3, 0.3, 0.3, 0.0])
@export var gear_vertical_strength := PackedFloat64Array([0.4, 0.3, 0.3, 0.0])
@export var gear_reverse_strength := PackedFloat64Array([0.3, 0.6, 0.6, 0.0])
## Station keeping (Sol's, for the precision gear): with no input the velocity is driven to zero at the gear's
## acceleration instead of coasting, and the engines hold the ship against gravity up to hover_thrust_limit m/s^2.
## It is Rodina's MoveLock idea (match a target velocity, which Rodina's AI uses) given to the pilot in one gear.
## Combat and cruise keep Rodina's rule: no input, no force; momentum and gravity carry the ship.
@export var gear_station_keeping := PackedByteArray([1, 0, 0, 0])
@export var hover_thrust_limit := 60.0
## Rodina RotationHardness: how hard full turn input accelerates the spin, as a fraction of rotation_speed per second.
@export var gear_rotation_hardness := PackedFloat64Array([0.35, 0.7, 0.7, 0.3])
## Atmosphere ratio at and below which rotation friction is the planet's full AtmosphereFriction (none at ratio 1 and
## above, i.e. in space). Rodina: 0.5 for dock and combat, 0.4 for cruise.
@export var gear_full_friction_ratio := PackedFloat64Array([0.5, 0.5, 0.4, 0.4])
## Rodina EGShipPlayer.RotationSpeed, rad/s: cap on the combined pitch+yaw rate; roll is capped at twice this.
@export var rotation_speed := 2.5
## Sol additions (Rodina has neither): boost raises MoveSpeed; brake drives the velocity to zero at the rate full
## reverse thrust brakes in Rodina (brake_multiplier 1), without then reversing.
@export var boost_multiplier := 1.5
@export var brake_multiplier := 1.0
## Warp gear's multiplier over the distance-scaled cruise cap. Sol's cruise is already
## distance-scaled, so the native 209.7 relative-time value is not applied directly.
@export var warp_speed_multiplier := 6.7
## Rodina gear 4: RotationFriction 2 everywhere (EGDataShipPlayer.lua:228), and LimnalStartTime 1.8 s before the drive's
## relative time applies (:45, :213-219): until then warp moves at the cruise limit.
@export var warp_rotation_friction := 2.0
@export var warp_start_time := 1.8


func gear_count() -> int:
	return gear_max_speed.size()
## Points on the hull that can touch the ground (ship-local). The first four are the landing
## gear, in the order GroundContact uses to fit the ground plane: (-x,-z) (+x,-z) (-x,+z) (+x,+z).
## The rest (nose and tail underside) only stop the hull passing through terrain; wings are not solid.
@export var support_points := PackedVector3Array([
	Vector3(-2.6, -2.0, -5.0), Vector3(2.6, -2.0, -5.0), Vector3(-2.6, -2.0, 8.5), Vector3(2.6, -2.0, 8.5),
	Vector3(0, -0.9, -7.3), Vector3(0, -0.9, 10.9)])
