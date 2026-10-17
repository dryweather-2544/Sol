class_name InteriorBody
extends RefCounted
## A person walking inside the ship, in ship-local coordinates. Because everything here is
## ship-local, the ship's speed, rotation and floating-origin shifts cannot affect it.

const WALK_SPEED := 3.0
const RUN_SPEED := 5.0
const ACCELERATION := 30.0
const RADIUS := 0.3
const EYE_HEIGHT := 1.65

## Feet position, ship-local.
var position := Vector3.ZERO
## Yaw about ship-local up; 0 faces -z (forward), positive turns left.
var yaw := 0.0
var velocity := Vector2.ZERO # (x, z)


func place(local_position: Vector3, facing_yaw: float) -> void:
	position = local_position
	yaw = facing_yaw
	velocity = Vector2.ZERO


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func step(command: OnFootCommand, layout: InteriorLayout, delta: float) -> void:
	yaw += command.yaw_delta
	var facing := forward()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := right * command.move.x + facing * command.move.y
	wish = wish.limit_length(1.0)
	var target := Vector2(wish.x, wish.z) * (RUN_SPEED if command.run else WALK_SPEED)
	velocity = velocity.move_toward(target, ACCELERATION * delta)
	var new_x := position.x + velocity.x * delta
	if layout.is_position_walkable(new_x, position.z, RADIUS):
		position.x = new_x
	else:
		velocity.x = 0.0
	var new_z := position.z + velocity.y * delta
	if layout.is_position_walkable(position.x, new_z, RADIUS):
		position.z = new_z
	else:
		velocity.y = 0.0
	position.y = layout.floor_height_at(position.x, position.z)
