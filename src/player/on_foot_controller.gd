class_name OnFootController
extends Node3D
## Thin node around OnFootBody: reads keys and mouse, runs the body each physics tick, owns the
## first-person camera. Inactive (and invisible) while the player is in the ship.

const MOUSE_RADIANS_PER_PIXEL := 0.0022

var planet: PlanetBody
var body := OnFootBody.new()
var render_origin := WorldPos.new(&"planet")
var camera := Camera3D.new()
var active := false:
	set(value):
		active = value
		visible = value
		camera.current = value
var _mouse_yaw_this_tick := 0.0
var _look_pitch := 0.0


func _init() -> void:
	name = "OnFootController"
	camera.name = "FirstPersonCamera"
	camera.position = Vector3(0, OnFootBody.EYE_HEIGHT, 0)
	camera.near = 0.05
	camera.far = 40000.0
	add_child(camera)
	visible = false


func _ready() -> void:
	add_to_group("origin_shift")


func add_mouse_motion(relative_pixels: Vector2) -> void:
	_mouse_yaw_this_tick -= relative_pixels.x * MOUSE_RADIANS_PER_PIXEL
	_look_pitch = clampf(_look_pitch - relative_pixels.y * MOUSE_RADIANS_PER_PIXEL, -1.5, 1.5)
	camera.rotation.x = _look_pitch


func _physics_process(delta: float) -> void:
	if not active:
		return
	var command := OnFootCommand.new()
	command.move = Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("thrust_back", "thrust_forward"))
	command.run = Input.is_action_pressed("boost")
	command.jump = Input.is_action_pressed("move_up")
	command.yaw_delta = _mouse_yaw_this_tick + Input.get_axis("yaw_right", "yaw_left") * 2.0 * delta
	_mouse_yaw_this_tick = 0.0
	simulate_tick(command, delta)


func simulate_tick(command: OnFootCommand, delta: float) -> void:
	body.step(command, planet, delta)
	sync_transform()


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	sync_transform()
	reset_physics_interpolation()


func sync_transform() -> void:
	var up := planet.up_at(body.position)
	transform = Transform3D(Basis.looking_at(body.heading, up), body.position.to_local_vector3(render_origin))
