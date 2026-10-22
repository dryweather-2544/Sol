class_name CockpitCamera
extends Camera3D
## Fixed view from the pilot seat, a child of the ship. Toggled with toggle_view.


func _init() -> void:
	name = "CockpitCamera"
	near = 0.3
	far = CameraRange.clamp_far(0.3, 3.0e7) # main.gd sets both every frame; this start value is already safe (CameraRange)
	position = Vector3(0, -0.9 + 1.7, -5.8) # eye height above the dash, back from the glass so the frames stay thin
