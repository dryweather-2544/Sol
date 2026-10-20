class_name ShipHullCollision
extends RefCounted
## Keeps a person walking outside from walking through the hull: pushes a ship-local feet
## position out of the hull box, except in the mouth of a deployed ramp.

## The pressure hull's outer extent (ShipExterior): sides with the chine strake, prow, rear loading face with its door frame,
## belly and roof. Gear legs are not solid.
const HULL_HALF_WIDTH := 3.8
const HULL_FRONT_Z := -9.25
const HULL_REAR_Z := 10.98
const HULL_BOTTOM_Y := -1.32
const HULL_TOP_Y := 2.25
const PERSON_HEIGHT := 1.75
## The engine pods stand upright beside the hull when landed (ShipExterior tilts them): x/z footprint and height.
const POD_MIN_X := 3.95
const POD_MAX_X := 6.1
const POD_MIN_Z := 5.85
const POD_MAX_Z := 8.15
const POD_BOTTOM_Y := -1.6
const POD_TOP_Y := 3.25


## Returns the (possibly corrected) ship-local feet position. ramp_rect is only excepted when deployed.
static func push_out(local_feet: Vector3, radius: float, ramp_rect: Rect2, ramp_deployed: bool) -> Vector3:
	var feet := local_feet
	if not (ramp_deployed and ramp_rect.grow(radius).has_point(Vector2(feet.x, feet.z))):
		feet = _push_out_of_box(feet, radius, -HULL_HALF_WIDTH, HULL_HALF_WIDTH, HULL_FRONT_Z, HULL_REAR_Z, HULL_BOTTOM_Y, HULL_TOP_Y)
	for side in [-1.0, 1.0]:
		var min_x := POD_MIN_X if side > 0.0 else -POD_MAX_X
		var max_x := POD_MAX_X if side > 0.0 else -POD_MIN_X
		# Never back toward the hull: the gap between hull and pod is narrower than a person.
		feet = _push_out_of_box(feet, radius, min_x, max_x, POD_MIN_Z, POD_MAX_Z, POD_BOTTOM_Y, POD_TOP_Y, -side)
	return feet


## Moves the feet out through the nearest side of one upright box (x/z footprint, y from bottom to top),
## if a person standing there would overlap it. `closed_x_side` -1/+1 forbids leaving through the -x/+x side.
static func _push_out_of_box(local_feet: Vector3, radius: float, min_x: float, max_x: float, min_z: float, max_z: float, bottom_y: float, top_y: float, closed_x_side := 0.0) -> Vector3:
	var feet := local_feet
	if feet.y + PERSON_HEIGHT < bottom_y or feet.y > top_y:
		return feet
	if feet.x <= min_x - radius or feet.x >= max_x + radius or feet.z <= min_z - radius or feet.z >= max_z + radius:
		return feet
	var push_left := feet.x - (min_x - radius) if closed_x_side >= 0.0 else INF
	var push_right := (max_x + radius) - feet.x if closed_x_side <= 0.0 else INF
	var push_front := feet.z - (min_z - radius)
	var push_rear := (max_z + radius) - feet.z
	var smallest := minf(minf(push_left, push_right), minf(push_front, push_rear))
	if smallest == push_left:
		feet.x = min_x - radius
	elif smallest == push_right:
		feet.x = max_x + radius
	elif smallest == push_front:
		feet.z = min_z - radius
	else:
		feet.z = max_z + radius
	return feet
