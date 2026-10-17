extends Node3D
## Boot scene: space, one ship, chase camera, overlay. The player starts in the pilot seat.

var ship: Ship
var player_source := PlayerPilotSource.new()


func _ready() -> void:
	add_child(PlaceholderSpace.new())
	ship = Ship.new()
	add_child(ship)
	var floating_origin := FloatingOrigin.new()
	floating_origin.anchor = ship
	add_child(floating_origin) # after ship, so it runs after the ship's physics tick
	var camera := ChaseCamera.new()
	camera.target = ship
	camera.far = 200000.0
	add_child(camera)
	camera.snap_to_target()
	camera.current = true
	var overlay := DebugOverlay.new()
	overlay.ship = ship
	add_child(overlay)
	ship.controller.request_control(player_source, &"pilot_seat")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_source.add_mouse_motion(event.relative)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
