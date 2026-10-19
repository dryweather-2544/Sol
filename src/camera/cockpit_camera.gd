class_name CockpitCamera
extends Camera3D
## Fixed view from the pilot seat, a child of the ship. Toggled with toggle_view.

var _base_position := Vector3(0, -0.9 + 1.5, -5.3)
var _entry_shake := 0.0


func _init() -> void:
	name = "CockpitCamera"
	near = 0.05
	far = 3.0e7
	position = _base_position


func set_entry_shake(amount: float) -> void:
	_entry_shake = clampf(amount, 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	var seconds := Time.get_ticks_msec() * 0.001
	var shake := _entry_shake * 0.035
	position = _base_position + Vector3(sin(seconds * 31.0) * shake, sin(seconds * 43.0 + 0.6) * shake * 0.7, 0.0)
	rotation = Vector3(sin(seconds * 27.0) * _entry_shake * 0.004, 0.0, sin(seconds * 19.0) * _entry_shake * 0.006)
