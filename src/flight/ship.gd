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
## Optional: when set, the ship feels its gravity/atmosphere and collides with its terrain.
var planet: PlanetBody


func _init() -> void:
	name = "Ship"
	controller.name = "PilotController"
	add_child(controller)


func _ready() -> void:
	add_to_group("origin_shift")
	PlaceholderShipMesh.build(self)
	_sync_transform()


func _physics_process(delta: float) -> void:
	simulate_tick(delta)


func simulate_tick(delta: float) -> void:
	if planet != null:
		planet.fill_environment(state, environment)
	var command := controller.poll_command(state, delta)
	FlightModel.step(state, command, tuning, environment, delta)
	if planet != null:
		GroundContact.resolve(state, planet, tuning, delta)
		state.regime = FlightRegime.classify(state.atmosphere_ratio, state.altitude_above_ground, state.landed)
	_sync_transform()


func _sync_transform() -> void:
	transform = Transform3D(state.basis, state.position.to_local_vector3(render_origin))


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	_sync_transform()
	reset_physics_interpolation()
