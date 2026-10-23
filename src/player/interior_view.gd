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
## The ship's layout, used to keep the third-person camera inside the walkable rooms (set by main every tick).
var layout: InteriorLayout
## Over-the-shoulder view: the player's own avatar is drawn and the camera sits behind it (pulled in against walls).
var third_person := false:
	set(value):
		third_person = value
		avatar.visible = value
var avatar := HumanoidAvatar.new()

const THIRD_PERSON_DISTANCE := 2.3
const THIRD_PERSON_SHOULDER := 0.4
const THIRD_PERSON_LIFT := 0.3
const CAMERA_CLEARANCE := 0.12
const CEILING_CLEARANCE := 2.3 # the camera stays under this height above the floor


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
	avatar.name = "PlayerAvatar"
	avatar.visible = false
	add_child(avatar)


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


## Where the player's eyes are (ship-local), whichever view is showing; interaction aims from here.
func eye_position() -> Vector3:
	return body.position + Vector3(0, InteriorBody.EYE_HEIGHT, 0)


func sync_view() -> void:
	var eye := eye_position()
	camera.rotation = Vector3(_pitch, body.yaw, 0.0)
	if not third_person:
		camera.position = eye
		return
	avatar.position = body.position
	avatar.rotation.y = body.yaw
	avatar.animate(body.velocity.length(), 1.0 / 60.0)
	var pivot := eye + Vector3(0, 0.1, 0)
	var aim := Basis.from_euler(Vector3(_pitch, body.yaw, 0.0))
	var offset := aim.z * THIRD_PERSON_DISTANCE + aim.x * THIRD_PERSON_SHOULDER + Vector3(0, THIRD_PERSON_LIFT, 0)
	# Pull the camera in along the boom until it would leave the walkable floor (walls, doorframes).
	var reach := 1.0
	if layout != null:
		reach = 0.0
		for step in range(1, 13):
			var t := step / 12.0
			var p := pivot + offset * t
			if not layout.is_position_walkable(p.x, p.z, CAMERA_CLEARANCE):
				break
			reach = t
	var cam := pivot + offset * reach
	cam.y = minf(cam.y, body.position.y + CEILING_CLEARANCE)
	camera.position = cam
	avatar.visible = reach * THIRD_PERSON_DISTANCE > 1.0 # too close to the wall: the body would fill the screen
