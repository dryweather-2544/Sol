class_name ShipTuning
extends Resource
## Handling numbers for one ship. Gears 0/1 follow the research gear table (FLY-12: 100 and
## 500 m/s); gear 2 is cruise (research: 5-10 km/s); acceleration and the rest are Sol's own tuning, expect to adjust by feel.

@export var gear_max_speed := PackedFloat64Array([100.0, 500.0, 10000.0])
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
## Points on the hull that touch the ground (ship-local): rear-left/right and front-left/right,
## in the order GroundContact expects: (-x,-z) (+x,-z) (-x,+z) (+x,+z).
@export var support_points := PackedVector3Array([
	Vector3(-2.8, -0.6, -2.6), Vector3(2.8, -0.6, -2.6), Vector3(-2.8, -0.6, 2.6), Vector3(2.8, -0.6, 2.6)])
