class_name WorldPos
extends RefCounted
## A position inside one reference frame (for example one planet), stored in 64-bit floats.
##
## Godot's Vector3 is 32-bit in normal builds, which is only accurate to about half a metre
## 6,000 km from the origin. GDScript's float is 64-bit, so anything that must stay exact
## (ships, the player, saved positions) is kept here, and converted to a Vector3 relative to
## a nearby origin only when it is handed to the renderer or physics.

var frame_id: StringName
var x: float
var y: float
var z: float


func _init(new_frame_id: StringName = &"", new_x: float = 0.0, new_y: float = 0.0, new_z: float = 0.0) -> void:
	frame_id = new_frame_id
	x = new_x
	y = new_y
	z = new_z


static func from_vector3(frame_id_for_position: StringName, position_in_frame: Vector3) -> WorldPos:
	return WorldPos.new(frame_id_for_position, position_in_frame.x, position_in_frame.y, position_in_frame.z)


func duplicate_position() -> WorldPos:
	return WorldPos.new(frame_id, x, y, z)


## Returns a new position moved by offset_meters. Frame is unchanged.
func offset_by(offset_meters: Vector3) -> WorldPos:
	return WorldPos.new(frame_id, x + offset_meters.x, y + offset_meters.y, z + offset_meters.z)


## Vector from other_position to this position, as a Vector3.
## Only valid within one frame: positions in different frames have no shared origin, so
## mixing them is a bug and fails loudly instead of returning a wrong number.
func vector_from(other_position: WorldPos) -> Vector3:
	assert(frame_id == other_position.frame_id, "WorldPos.vector_from: positions are in different frames")
	if frame_id != other_position.frame_id:
		return Vector3.INF
	return Vector3(x - other_position.x, y - other_position.y, z - other_position.z)


func distance_to(other_position: WorldPos) -> float:
	var difference := vector_from(other_position)
	if difference == Vector3.INF:
		return INF
	return difference.length()


## Position relative to frame_origin, safe to use as a (32-bit) Vector3 when the result is small.
func to_local_vector3(frame_origin: WorldPos) -> Vector3:
	return vector_from(frame_origin)


func is_approximately_equal(other_position: WorldPos, tolerance_meters: float = 1e-6) -> bool:
	if frame_id != other_position.frame_id:
		return false
	return distance_to(other_position) <= tolerance_meters


func to_dictionary() -> Dictionary:
	return {"frame_id": String(frame_id), "x": x, "y": y, "z": z}


static func from_dictionary(data: Dictionary) -> WorldPos:
	return WorldPos.new(StringName(data.get("frame_id", "")), float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
