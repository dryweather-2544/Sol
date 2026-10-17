class_name ShipTuning
extends Resource
## Handling numbers for one ship. Gear 0/1 follow the research gear table (FLY-12: 100 and
## 500 m/s); acceleration and the rest are Sol's own tuning, expect to adjust by feel.

@export var gear_max_speed := PackedFloat64Array([100.0, 500.0])
@export var gear_acceleration := PackedFloat64Array([60.0, 150.0])
@export var gear_deceleration := PackedFloat64Array([80.0, 200.0])
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
