class_name ShipTuning
extends Resource
## Handling numbers for one ship. Gears 0/1 follow the research gear table (FLY-12: 100 and
## 500 m/s); gear 2 is cruise (research: 5-10 km/s near a planet; here the speed limit is set by
## distance to the nearest surface). Axes/accelerations follow the recovered MoveStrengths
## relationships; cruise remains Sol-tuned for a readable approach.

@export var gear_max_speed := PackedFloat64Array([100.0, 500.0, 2.0e7])
@export var gear_acceleration := PackedFloat64Array([60.0, 1000.0, 2500.0])
@export var gear_deceleration := PackedFloat64Array([80.0, 200.0, 4000.0])
## Fraction of full speed available sideways / vertically / forward-back (FLY-08: sideways is weaker).
## Kept for tools that use a single vector; FlightModel uses gear_axis_strength.
@export var axis_strength := Vector3(0.5, 0.5, 1.0)
## Rodina's MoveStrengths table is (right, forward, up). Sol is (right, up, back), so the
## forward component maps to -Z and the up component maps to +Y. DOCK is vertical-led, COMBAT
## and CRUISE are forward-led but deliberately weaker laterally/vertically.
@export var gear_axis_strength := PackedVector3Array([
	Vector3(0.30, 1.00, 0.30),
	Vector3(0.30, 0.30, 0.60),
	Vector3(0.30, 0.30, 0.60),
])
@export var boost_multiplier := 1.5
@export var brake_multiplier := 2.0
## Rodina EGShipPlayer.RotationSpeed = 2.5 rad/s. Rotation is inertia-driven rather than a
## direct rate target: hardness controls angular acceleration, and friction only bites while
## coasting. (The recovered engine applies friction per physics tick; Sol does the equivalent
## in its fixed tick.)
@export var rotation_speed := 2.5
@export var rotation_hardness := PackedFloat64Array([0.35, 0.7, 0.7])
## Space is frictionless. Atmospheric friction is supplied by FlightEnvironment's density.
@export var rotation_friction_atmosphere := 0.9


func gear_count() -> int:
	return gear_max_speed.size()


func rotation_hardness_for(gear: int) -> float:
	var index := clampi(gear, 0, rotation_hardness.size() - 1)
	return rotation_hardness[index] if rotation_hardness.size() > 0 else 1.0


func axis_strength_for(gear: int) -> Vector3:
	var index := clampi(gear, 0, gear_axis_strength.size() - 1)
	return gear_axis_strength[index] if gear_axis_strength.size() > 0 else axis_strength
## Points on the hull that can touch the ground (ship-local). The first four are the landing
## gear, in the order GroundContact uses to fit the ground plane: (-x,-z) (+x,-z) (-x,+z) (+x,+z).
## The rest (nose and tail underside) only stop the hull passing through terrain; wings are not solid.
@export var support_points := PackedVector3Array([
	Vector3(-2.6, -2.0, -5.0), Vector3(2.6, -2.0, -5.0), Vector3(-2.6, -2.0, 8.5), Vector3(2.6, -2.0, 8.5),
	Vector3(0, -0.9, -7.3), Vector3(0, -0.9, 10.9)])
