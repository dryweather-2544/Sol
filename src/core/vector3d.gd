class_name Vector3D
extends RefCounted
## Three 64-bit floats (GDScript's Vector3 is 32-bit). For astronomical positions only.

var x: float
var y: float
var z: float


func _init(new_x: float = 0.0, new_y: float = 0.0, new_z: float = 0.0) -> void:
	x = new_x
	y = new_y
	z = new_z
