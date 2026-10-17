class_name CubeSphere
extends RefCounted
## Maps a point on one of six cube faces to a direction on the sphere. Per face: a normal and
## two axes with cross(u_axis, v_axis) == normal, so triangle winding is the same on every face.

const FACE_NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const FACE_U_AXES := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
const FACE_V_AXES := [Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(0, 1, 0)]


## face_u, face_v in [-1, 1]. Returns a unit direction (as doubles inside a Vector3's worth of
## values is NOT possible, so callers needing 64-bit use direction_xyz).
static func direction(face: int, face_u: float, face_v: float) -> Vector3:
	var components := direction_xyz(face, face_u, face_v)
	return Vector3(components[0], components[1], components[2])


## Same as direction() but returns [x, y, z] as 64-bit floats.
static func direction_xyz(face: int, face_u: float, face_v: float) -> PackedFloat64Array:
	var normal: Vector3 = FACE_NORMALS[face]
	var u_axis: Vector3 = FACE_U_AXES[face]
	var v_axis: Vector3 = FACE_V_AXES[face]
	var cube_x := normal.x + u_axis.x * face_u + v_axis.x * face_v
	var cube_y := normal.y + u_axis.y * face_u + v_axis.y * face_v
	var cube_z := normal.z + u_axis.z * face_u + v_axis.z * face_v
	# "Spherified cube": spreads chunks more evenly than plain normalising.
	var x_squared := cube_x * cube_x
	var y_squared := cube_y * cube_y
	var z_squared := cube_z * cube_z
	var sphere_x := cube_x * sqrt(1.0 - y_squared * 0.5 - z_squared * 0.5 + y_squared * z_squared / 3.0)
	var sphere_y := cube_y * sqrt(1.0 - z_squared * 0.5 - x_squared * 0.5 + z_squared * x_squared / 3.0)
	var sphere_z := cube_z * sqrt(1.0 - x_squared * 0.5 - y_squared * 0.5 + x_squared * y_squared / 3.0)
	var length := sqrt(sphere_x * sphere_x + sphere_y * sphere_y + sphere_z * sphere_z)
	return PackedFloat64Array([sphere_x / length, sphere_y / length, sphere_z / length])
