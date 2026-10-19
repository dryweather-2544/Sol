extends SceneTree
## Actual-scene flight demo: accelerate, coast, yaw while retaining world velocity, translate
## sideways, then brake. Saves frames and prints the measured state.

class DemoPilot extends PilotSource:
	var frame := 0
	var velocity_before_turn := Vector3.ZERO

	func _init() -> void:
		source_id = &"flight_demo"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		frame += 1
		var command := PilotCommand.new()
		command.gear = PilotCommand.GEAR_CRUISE
		if frame < 60:
			command.brake = true
		elif frame < 240:
			command.thrust = Vector3(0, 0, -1)
			if frame == 239:
				velocity_before_turn = ship_state.velocity
		elif frame < 420:
			command.turn = Vector3(0, 1, 0)
		elif frame < 540:
			command.thrust = Vector3.RIGHT
		else:
			command.brake = true
		return command

var main: Node
var pilot := DemoPilot.new()
var frames := 0
var shots := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main.menu.dismiss()
		main.chase_camera.current = true
		# Start level so yaw/roll can be judged against a horizon.
		var up: Vector3 = main.planet.up_at(main.ship.state.position)
		var forward: Vector3 = up.cross(Vector3.RIGHT).cross(up).normalized()
		main.ship.state.basis = Basis.looking_at(forward, up)
		main.ship._sync_transform()
		main.chase_camera.snap_to_target()
		var demo_source := pilot
		main.ship.controller.release_control(main.player_source)
		main.ship.controller.request_control(demo_source, &"pilot_seat")
	if frames < 10:
		return false
	if frames in [60, 180, 300, 420, 540, 660]:
		var state: ShipState = main.ship.state
		var camera: Camera3D = main.chase_camera
		var ship_basis: Basis = main.ship.global_basis
		var relative: Vector3 = camera.global_position - main.ship.global_position
		print("DEMO f=%d speed=%.1f lateral=%.4f behind=%.1f right_dot=%.4f" % [
			frames, state.speed(), relative.dot(ship_basis.x), relative.dot(ship_basis.z),
			camera.global_basis.x.dot(ship_basis.x)])
		var image := root.get_viewport().get_texture().get_image()
		image.save_png("artifacts/flight_demo_%02d.png" % shots)
		shots += 1
	if frames == 300:
		print("TURN_VELOCITY before=%s after=%s" % [pilot.velocity_before_turn, main.ship.state.velocity])
	if frames >= 720:
		quit()
	return false
