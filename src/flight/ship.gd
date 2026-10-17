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
## Used instead of `planet` when the ship is in the system frame (outside every planet's reach).
var free_space: SystemNavigator
## Optional interior systems; when set, interlocks can hold the ship on the ground.
var systems: ShipSystems
## False when a GameSession drives simulate_tick itself (keeps tick order explicit).
var auto_tick := true
## The command applied on the latest tick (read by audio and HUD).
var last_command := PilotCommand.new()

signal destroyed


func _init() -> void:
	name = "Ship"
	controller.name = "PilotController"
	add_child(controller)


func _ready() -> void:
	add_to_group("origin_shift")
	if systems != null:
		var visuals := ShipVisuals.new()
		visuals.ship = self
		add_child(visuals)
	else:
		PlaceholderShipMesh.build(self)
	_sync_transform()


func _physics_process(delta: float) -> void:
	if auto_tick:
		simulate_tick(delta)


func simulate_tick(delta: float) -> void:
	if planet != null:
		planet.fill_environment(state, environment)
	elif free_space != null:
		free_space.fill_environment(state, environment)
	var command := controller.poll_command(state, delta)
	var takeoff_block := systems.takeoff_block_reason() if systems != null and state.landed else ""
	if takeoff_block != "":
		command = command.without_thrust()
	last_command = command
	FlightModel.step(state, command, tuning, environment, delta)
	if planet != null:
		GroundContact.resolve(state, planet, tuning, delta)
		_take_damage(delta)
		state.regime = FlightRegime.classify(state.atmosphere_ratio, state.altitude_above_ground, state.landed)
		if takeoff_block != "":
			state.status_message = "Takeoff blocked: " + takeoff_block
	_sync_transform()


func _sync_transform() -> void:
	transform = Transform3D(state.basis, state.position.to_local_vector3(render_origin))


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	_sync_transform()
	reset_physics_interpolation()


func _take_damage(delta: float) -> void:
	if state.hull <= 0.0:
		return
	var loss := ShipDamage.impact_damage(state.last_impact_speed) + ShipDamage.heating_rate(state.speed(), state.atmosphere_ratio) * delta
	if loss <= 0.0:
		return
	state.hull = maxf(0.0, state.hull - loss)
	if state.hull <= 0.0:
		destroyed.emit()
