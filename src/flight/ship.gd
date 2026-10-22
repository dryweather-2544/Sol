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
## Combat: set by the scene/director. With no ProjectileSim the guns do nothing.
var projectiles: ProjectileSim
var team_id := 0
var upgrades := ShipUpgrades.new()
var hull_color := Color(0.62, 0.66, 0.72)
var weapon := Weapon.ship_gun()
## Nose of the ship, where shots leave (ship-local).
var muzzle_offset := Vector3(0, -0.2, -7.6)
## Rodina's player ship has two gun barrels (GunBarrelLeft/Right); shots alternate between them.
const BARREL_X := 1.2
## False on the player's ship: its main gun is the dorsal turret (ShipTurret). Other ships keep the nose guns.
var nose_gun_enabled := true
## Both barrels are angled to cross at this range ahead of the nose, so a burst closes on the reticle (the camera looks
## along the ship's nose) instead of running parallel and off to the sides.
const CONVERGENCE := 600.0
var _next_barrel := -1.0

signal destroyed

const FUEL_CRUISE_PER_SECOND := 0.002
const FUEL_WARP_PER_SECOND := 0.01
const FUEL_BOOST_PER_SECOND := 0.006


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
		PlaceholderShipMesh.build(self, hull_color)
	_sync_transform()


func _physics_process(delta: float) -> void:
	if auto_tick:
		simulate_tick(delta)


func simulate_tick(delta: float) -> void:
	if planet != null:
		planet.fill_environment(state, environment)
	elif free_space != null:
		free_space.fill_environment(state, environment)
	# The player's ship (the one with interior systems) uses the player's levelling setting; others Rodina's default.
	environment.horizon_levelling = GameSettings.instance().ship_horizon_levelling if systems != null else 1.0
	var tank_empty := state.fuel <= 0.0
	state.allowed_gear = mini(environment.max_gear, PilotCommand.GEAR_COMBAT if tank_empty else PilotCommand.GEAR_WARP)
	var command := controller.poll_command(state, delta)
	if tank_empty:
		environment.max_gear = mini(environment.max_gear, PilotCommand.GEAR_COMBAT)
		if command.boost:
			command = command.without_boost()
	var takeoff_block := systems.takeoff_block_reason() if systems != null and state.landed else ""
	if takeoff_block != "":
		command = command.without_thrust()
	if systems != null:
		systems.set_demand(command)
		var engine_factor := systems.engine_factor()
		if engine_factor < 1.0:
			command = command.with_thrust_scaled(engine_factor)
	last_command = command
	FlightModel.step(state, command, tuning, environment, delta)
	state.clutch = command.clutch and state.gear < PilotCommand.GEAR_WARP
	_burn_fuel(command, delta)
	_fire_weapon(command, delta)
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
	state.impact_damage_cooldown = maxf(0.0, state.impact_damage_cooldown - delta)
	var impact_loss := 0.0
	if state.impact_damage_cooldown <= 0.0 and state.last_impact_speed > 0.0:
		impact_loss = ShipDamage.impact_damage(state.last_impact_speed, state.last_impact_incidence) * upgrades.damage_taken_multiplier()
		if impact_loss > 0.0:
			state.impact_damage_cooldown = ShipDamage.IMPACT_DAMAGE_COOLDOWN
	var heating_loss := ShipDamage.entry_damage_rate(state.atmosphere_resistance) * delta * upgrades.damage_taken_multiplier()
	var loss := impact_loss + heating_loss
	if loss <= 0.0:
		return
	if systems != null:
		if impact_loss > 0.0:
			systems.damage_subsystem(ShipSubsystems.Id.ENGINES, impact_loss) # touchdown shocks hit the drive
		if heating_loss > 0.0:
			systems.damage_subsystem(ShipSubsystems.Id.REACTOR, heating_loss)
	state.hull = maxf(0.0, state.hull - loss)
	if state.hull <= 0.0:
		destroyed.emit()


func _burn_fuel(command: PilotCommand, delta: float) -> void:
	var burn := 0.0
	if state.gear == PilotCommand.GEAR_CRUISE and command.thrust != Vector3.ZERO:
		burn += FUEL_CRUISE_PER_SECOND
	elif state.gear == PilotCommand.GEAR_WARP and command.thrust != Vector3.ZERO:
		burn += FUEL_WARP_PER_SECOND
	if command.boost and command.thrust != Vector3.ZERO:
		burn += FUEL_BOOST_PER_SECOND
	state.fuel = maxf(0.0, state.fuel - burn * upgrades.fuel_burn_multiplier() * delta)


## Guns work in the COMBAT gear only: dock/precision is for landing and cruise/warp are too fast to aim.
static func gear_allows_fire(gear: int) -> bool:
	return gear == PilotCommand.GEAR_COMBAT


func _fire_weapon(command: PilotCommand, delta: float) -> void:
	weapon.update(delta)
	if not nose_gun_enabled or projectiles == null or not command.fire or state.hull <= 0.0 or not Ship.gear_allows_fire(state.gear):
		return
	var local_muzzle := muzzle_offset + Vector3(_next_barrel * BARREL_X, 0.0, 0.0)
	var muzzle := state.position.offset_by(state.basis * local_muzzle)
	var aim := state.basis * (Vector3(0.0, 0.0, -CONVERGENCE) - local_muzzle).normalized()
	var base_damage := weapon.damage
	weapon.damage = base_damage * upgrades.gun_damage_multiplier()
	if weapon.try_fire(projectiles, muzzle, aim, state.velocity, team_id, self, systems.weapon_factor() if systems != null else 1.0):
		_next_barrel = -_next_barrel
	weapon.damage = base_damage
