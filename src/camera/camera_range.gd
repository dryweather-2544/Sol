class_name CameraRange
extends RefCounted
## Safe near/far planes. Godot builds a camera's projection in 32-bit floats. When the near plane is small next to the far
## distance (about far / near > 2^23), far + near and far - near round to the same float, the projection's z row becomes
## exactly -1 and the frustum's far plane degenerates (zero normal). The engine's frustum culling then rejects every
## mesh: only the sky and the HUD are drawn. That is what made the ship interior invisible in 2f9b74e, which gave the
## walking camera (near 0.05 m) the flight far plane (up to 4,000 km): far / near = 8e7. See docs/decisions/0013.

## far / near is kept at or under this: four float steps of margin in the projection's z row.
const MAX_RATIO := 4.0e6


## The far plane a camera with this near plane may use (never more than `far`).
static func clamp_far(near: float, far: float) -> float:
	return minf(far, near * MAX_RATIO)


## A near plane for this far distance: `wanted_near`, raised as far as `max_near` if the far plane needs it.
static func near_for(far: float, wanted_near: float, max_near: float) -> float:
	return clampf(far / MAX_RATIO, wanted_near, maxf(wanted_near, max_near))


## True when a perspective camera with these planes keeps a usable far plane (the engine's own float32 projection).
static func is_safe(near: float, far: float) -> bool:
	var projection := Projection.create_perspective(70.0, 16.0 / 9.0, near, far)
	return -1.0 - projection.z.z > 0.0
