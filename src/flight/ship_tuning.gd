class_name ShipTuning
extends Resource
## Handling numbers for one ship. Gears 0/1 follow the research gear table (FLY-12: 100 and
## 500 m/s); gear 2 is cruise (research: 5-10 km/s near a planet; here the speed limit is set by distance to the nearest surface, so travel between worlds takes seconds); acceleration and the rest are Sol's own tuning, expect to adjust by feel.

@export var gear_max_speed := PackedFloat64Array([100.0, 500.0, 2.0e7])
@export var gear_acceleration := PackedFloat64Array([60.0, 150.0, 2500.0])
@export var gear_deceleration := PackedFloat64Array([80.0, 200.0, 4000.0])
## Fraction of full speed available sideways / vertically / forward-back (FLY-08: sideways is weaker).
@export var axis_strength := Vector3(0.5, 0.5, 1.0)
@export var boost_multiplier := 1.5
@export var brake_multiplier := 2.0
## Radians per second at full demand: pitch, yaw, roll.
@export var max_turn_rate := Vector3(1.5, 1.5, 2.5)
@export var turn_acceleration := 8.0
@export var turn_damping := 10.0


func gear_count() -> int:
	return gear_max_speed.size()
## Points on the hull that can touch the ground (ship-local). The first four are the landing
## gear, in the order GroundContact uses to fit the ground plane: (-x,-z) (+x,-z) (-x,+z) (+x,+z).
## The rest (nose and tail underside) only stop the hull passing through terrain; wings are not solid.
@export var support_points := PackedVector3Array([
	Vector3(-2.6, -2.0, -5.0), Vector3(2.6, -2.0, -5.0), Vector3(-2.6, -2.0, 8.5), Vector3(2.6, -2.0, 8.5),
	Vector3(0, -0.9, -7.3), Vector3(0, -0.9, 10.9)])
