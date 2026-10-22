class_name InteriorView
extends Node3D
## Camera for walking inside the ship. A child of the ship node, so it rides along with the ship
## (and is interpolated with it); position and yaw come from the InteriorBody, pitch from the mouse.

const MOUSE_RADIANS_PER_PIXEL := 0.0022

var body: InteriorBody
var camera := Camera3D.new()
var _pitch := 0.0
## A dim lamp that travels with the eyes, so rooms are never pitch black (on while walking inside; see set_lamp).
var lamp := OmniLight3D.new()
## Yaw accumulated from the mouse since the last tick; GameSession feeds it in as yaw_delta.
var pending_yaw := 0.0


func _init() -> void:
	name = "InteriorView"
	camera.name = "InteriorCamera"
	camera.near = 0.05
	camera.far = 40000.0
	add_child(camera)
	lamp.name = "HeadLamp"
	lamp.light_energy = 0.3
	lamp.omni_range = 6.0
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.shadow_enabled = false
	lamp.visible = false
	camera.add_child(lamp)


func add_mouse_motion(relative_pixels: Vector2) -> void:
	pending_yaw -= relative_pixels.x * MOUSE_RADIANS_PER_PIXEL * GameSettings.instance().mouse_sensitivity
	_pitch = clampf(_pitch - relative_pixels.y * MOUSE_RADIANS_PER_PIXEL * GameSettings.instance().mouse_sensitivity * GameSettings.instance().pitch_sign(), -1.4, 1.4)


func get_pitch() -> float:
	return _pitch


func set_pitch(value: float) -> void:
	_pitch = clampf(value, -1.4, 1.4)


func set_lamp(on: bool) -> void:
	lamp.visible = on


func take_pending_yaw() -> float:
	var yaw := pending_yaw
	pending_yaw = 0.0
	return yaw


func sync_view() -> void:
	camera.position = body.position + Vector3(0, InteriorBody.EYE_HEIGHT, 0)
	camera.rotation = Vector3(_pitch, body.yaw, 0.0)
