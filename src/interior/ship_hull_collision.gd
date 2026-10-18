class_name ShipHullCollision
extends RefCounted
## Keeps a person walking outside from walking through the hull: pushes a ship-local feet
## position out of the hull box, except in the mouth of a deployed ramp.

const HULL_HALF_WIDTH := 3.2
const HULL_FRONT_Z := -7.3
const HULL_REAR_Z := 10.9
const HULL_BOTTOM_Y := -1.2
const HULL_TOP_Y := 1.9
const PERSON_HEIGHT := 1.75


## Returns the (possibly corrected) ship-local feet position. ramp_rect is only excepted when deployed.
static func push_out(local_feet: Vector3, radius: float, ramp_rect: Rect2, ramp_deployed: bool) -> Vector3:
	var feet := local_feet
	var head_y := feet.y + PERSON_HEIGHT
	if head_y < HULL_BOTTOM_Y or feet.y > HULL_TOP_Y:
		return feet
	if ramp_deployed and ramp_rect.grow(radius).has_point(Vector2(feet.x, feet.z)):
		return feet
	var inside_x := absf(feet.x) < HULL_HALF_WIDTH + radius
	var inside_z := feet.z > HULL_FRONT_Z - radius and feet.z < HULL_REAR_Z + radius
	if not (inside_x and inside_z):
		return feet
	var push_left := feet.x - (-HULL_HALF_WIDTH - radius)
	var push_right := (HULL_HALF_WIDTH + radius) - feet.x
	var push_front := feet.z - (HULL_FRONT_Z - radius)
	var push_rear := (HULL_REAR_Z + radius) - feet.z
	var smallest := minf(minf(push_left, push_right), minf(push_front, push_rear))
	if smallest == push_left:
		feet.x = -HULL_HALF_WIDTH - radius
	elif smallest == push_right:
		feet.x = HULL_HALF_WIDTH + radius
	elif smallest == push_front:
		feet.z = HULL_FRONT_Z - radius
	else:
		feet.z = HULL_REAR_Z + radius
	return feet
