class_name OnFootController
extends Node3D
## Visual side of walking outside: places a first-person camera at the body's eyes. The body itself
## is stepped by GameSession; this node only reads it, and collects mouse look.

const MOUSE_RADIANS_PER_PIXEL := 0.0022

var planet: PlanetBody
var body: OnFootBody
var render_origin := WorldPos.new(&"planet")
var camera := Camera3D.new()
var pending_yaw := 0.0
var avatar := HumanoidAvatar.new()
var third_person := false:
	set(value):
		third_person = value
		_apply_view_mode()
var _look_pitch := 0.0


func _init() -> void:
	name = "OnFootController"
	camera.name = "FirstPersonCamera"
	camera.position = Vector3(0, OnFootBody.EYE_HEIGHT, 0)
	camera.near = 0.05
	camera.far = 40000.0
	add_child(camera)


func _ready() -> void:
	add_to_group("origin_shift")
	add_child(avatar)
	_apply_view_mode()


func add_mouse_motion(relative_pixels: Vector2) -> void:
	pending_yaw -= relative_pixels.x * MOUSE_RADIANS_PER_PIXEL * GameSettings.instance().mouse_sensitivity
	_look_pitch = clampf(_look_pitch - relative_pixels.y * MOUSE_RADIANS_PER_PIXEL * GameSettings.instance().mouse_sensitivity * GameSettings.instance().pitch_sign(), -1.5, 1.5)
	camera.rotation.x = _look_pitch


func get_pitch() -> float:
	return _look_pitch


func set_pitch(value: float) -> void:
	_look_pitch = clampf(value, -1.5, 1.5)
	camera.rotation.x = _look_pitch


func take_pending_yaw() -> float:
	var yaw := pending_yaw
	pending_yaw = 0.0
	return yaw


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	sync_transform()
	reset_physics_interpolation()


func _apply_view_mode() -> void:
	avatar.visible = third_person
	# Over-the-shoulder: behind and above the head, looking along the heading.
	camera.position = Vector3(0.5, OnFootBody.EYE_HEIGHT + 0.55, 3.6) if third_person else Vector3(0, OnFootBody.EYE_HEIGHT, 0)


func sync_transform() -> void:
	if body.position.x == 0.0 and body.position.y == 0.0 and body.position.z == 0.0:
		return # body not placed yet (player has not left the ship)
	var up := planet.up_at(body.position)
	transform = Transform3D(Basis.looking_at(body.heading, up), body.position.to_local_vector3(render_origin))
	avatar.animate(body.velocity.length() if body.grounded else 0.0, 1.0 / 60.0)
