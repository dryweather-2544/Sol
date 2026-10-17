class_name Ship
extends Node3D
## Thin node around the pure flight code: asks the controller for a command, runs FlightModel,
## and places itself at state.position relative to render_origin.

var tuning := ShipTuning.new()
var state := ShipState.new()
var environment := FlightEnvironment.new()
var controller := PilotController.new()
## Where Vector3 (0,0,0) is in the ship's frame. FloatingOrigin moves this to keep nodes near zero.
var render_origin := WorldPos.new(&"space")


func _init() -> void:
	name = "Ship"
	controller.name = "PilotController"
	add_child(controller)


func _ready() -> void:
	PlaceholderShipMesh.build(self)
	_sync_transform()


func _physics_process(delta: float) -> void:
	simulate_tick(delta)


func simulate_tick(delta: float) -> void:
	var command := controller.poll_command(state, delta)
	FlightModel.step(state, command, tuning, environment, delta)
	_sync_transform()


func _sync_transform() -> void:
	transform = Transform3D(state.basis, state.position.to_local_vector3(render_origin))
