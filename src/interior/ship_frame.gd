class_name ShipFrame
extends RefCounted
## Conversions between the ship's local space and its planet frame, in 64-bit where it matters.


static func world_from_local(ship_state: ShipState, local_position: Vector3) -> WorldPos:
	return ship_state.position.offset_by(ship_state.basis * local_position)


static func local_from_world(ship_state: ShipState, world_position: WorldPos) -> Vector3:
	return ship_state.basis.transposed() * world_position.vector_from(ship_state.position)
