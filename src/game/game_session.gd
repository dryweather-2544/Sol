class_name GameSession
extends RefCounted
## The director: owns the player's whole situation (seated / inside / outside), ties the ship,
## its interior systems and the player's bodies together, and performs every transition
## (stand up, sit, airlock, walkway, walk out, walk in) as a continuous change of frame, never a
## teleport. Scenes only feed it commands and draw the result, so the full loop is testable headless.

enum Mode { SEATED, SITTING, INSIDE, OUTSIDE }

const ACTOR := &"player"
const PILOT_SEAT := &"pilot_seat"
## The deployed ramp is walked on as ground (an outside floor), so walking along, across or off it follows the input.
## The walker changes between the ship's interior and the outside at the outer doorway, at the hull's rear face:
## going in a little before it, coming out a little after it (the gap stops flip-flopping on the line).
const DOOR_ENTER_Z := ShipHullCollision.HULL_REAR_Z + 0.1
const DOOR_EXIT_Z := ShipHullCollision.HULL_REAR_Z + 0.35
## Feet may be this far below the ramp surface and still step onto it; any lower and the ramp's edge is a wall.
const RAMP_STEP_UP := 0.4
## Radius of the walker against the hull and the ramp's sides.
const OUTSIDE_RADIUS := 0.4
const DOORWAY_MARGIN := 0.5
## Crew stations that exist in the layout but are not usable yet (reactor panel and fire gear come with N4, the gun with N6).
const STATION_NAMES := {&"engine_station": "Engine station", &"gunner_seat": "Gunner seat"}

var planet: PlanetBody
var ship: Ship
var systems: ShipSystems
var player_state := PlayerState.new()
var interior_body := InteriorBody.new()
var exterior_body := OnFootBody.new()
var pilot_source: PilotSource
## Gunner station: the player is on the dorsal gun while an AI pilot flies. gunner_trigger is the fire button, set by the scene.
var gunner_station := false
var gunner_trigger := false
var gunner_ai: AIPilotSource
var discovery_log := DiscoveryLog.new()
var suit := SuitState.new()
var progress := ProgressTracker.new()
var inventory := Inventory.new()
var loot_log := LootLog.new()
## Scanner (PoiScanner): seconds until the next pulse is allowed, and how long the readout stays on screen after one.
var scan_cooldown := 0.0
var scan_readout_seconds := 0.0
## The AI crew aboard (walking the interior; see ShipCrew).
var crew := ShipCrew.new()
var crew_brain := CrewBrain.new()
## POIs near the player, set by the scene each tick (for crates and solid props).
var nearby_pois: Array = []
## Combat: one projectile world shared by every shooter; enemy_targets is filled by the encounter director.
var projectiles := ProjectileSim.new()
var enemy_targets: Array = []
var pistol := Weapon.pistol()
## True while the walker is inside an outpost depot (sealed and pressurised).
var in_building := false
var cleared_log := LootLog.new() ## POIs whose guards were destroyed (same id-set ledger as looted crates)
var _player_ship_target: ShipCombatant
var _player_foot_target: CombatTargets.OnFootTarget
var repairing := false

## Emitted when the run cannot go on (ship destroyed, suffocated); the scene decides what happens next.
signal player_lost(reason: String)
## The player used the workbench; the scene opens the upgrade screen.
signal workbench_requested
## Observer only (audio): the player used something inside the ship and it was refused; `reason` is the message shown.
signal interaction_refused(point_id: StringName, reason: String)
## The player rested on the bed in the living area; the scene saves the game.
signal rest_requested
## The player used the airlock computer; the scene opens its menu.
signal airlock_requested
## The player used a ship machine (ops_computer, scanners, ftl_radio, battery_array, limnal_drive); the scene opens its screen.
signal machine_requested(kind: StringName)
## The player used the reactor panel; the scene opens the reactor screen.
signal reactor_requested
## The Mayday ambush has started; the scene spawns the hostile ship(s). Carries the beacon direction on Selene.
signal ambush_requested(beacon_direction: Vector3)
## Sprays left in the carried fire extinguisher (refilled at the locker in engineering).
const EXTINGUISHER_CHARGES := 6
const EXTINGUISHER_STRENGTH := 0.35
var extinguisher_charges := 0
var _burning_room_count := 0
var mode := Mode.SEATED
## The player's view ray inside the ship (ship-local), set by the scene each frame. While `has_look` is true, interacting
## and the prompt use what you are looking at (press F on the door itself); without it (headless tests, tools) they use
## the nearest interaction point to the player's feet.
var look_origin := Vector3.ZERO
var look_direction := Vector3.ZERO
var has_look := false
var message := ""
var message_seconds_left := 0.0
var _sit_start_position := Vector3.ZERO
var _sit_elapsed := 0.0


func _init(planet_body: PlanetBody, player_ship: Ship, source: PilotSource) -> void:
	planet = planet_body
	ship = player_ship
	pilot_source = source
	systems = ShipSystems.new()
	ship.systems = systems
	ship.nose_gun_enabled = false # the dorsal turret is the player ship's gun (pilot's fire button works it)
	ship.auto_tick = false
	systems.seats.seat_occupied.connect(_on_seat_occupied)
	progress.ambush_triggered.connect(func(beacon_direction: Vector3):
		systems.ambush_armed = true
		ambush_requested.emit(beacon_direction))
	systems.ambush_hit.connect(func(): _say("Engines hit! Fire in engineering!"))
	ship.destroyed.connect(func(): player_lost.emit("Ship destroyed"))
	ship.projectiles = projectiles
	exterior_body.floor_override = Callable(self, "_floor_override")
	ship.team_id = 0
	_player_ship_target = ShipCombatant.new(ship, 0)
	_player_foot_target = CombatTargets.OnFootTarget.new(self)
	suit.died.connect(func(): player_lost.emit("Out of oxygen"))
	inventory.add(ItemDefinition.OXYGEN_TANK, 1)
	inventory.add(ItemDefinition.REPAIR_KIT, 1)
	ship.controller.request_control(pilot_source, PILOT_SEAT)
	systems.seats.try_sit(ACTOR, PILOT_SEAT)
	systems.seats.update(SeatManager.SIT_SECONDS) # start the game already seated


## Advance one physics tick. foot_command drives whichever body is walking.
func tick(delta: float, foot_command: OnFootCommand) -> void:
	message_seconds_left = maxf(0.0, message_seconds_left - delta)
	scan_cooldown = maxf(0.0, scan_cooldown - delta)
	scan_readout_seconds = maxf(0.0, scan_readout_seconds - delta)
	if not systems.walkway.is_stowed() and planet != null:
		_fit_ramp_to_ground() # follows the ship if it settles or shifts while the ramp is out
	systems.walkway.occupied = _is_anyone_on_ramp()
	for portal_id in systems.layout.portals:
		systems.occupied_portals[portal_id] = _is_in_doorway(systems.layout.portals[portal_id])
	crew.mark_occupied(systems)
	systems.ambient_pressure = 1.0 if planet != null and planet.breathable and ship.state.atmosphere_ratio < 1.0 else 0.0
	exterior_body.jetpack_fuel_available = suit.has_fuel()
	ship.simulate_tick(delta)
	systems.update(delta, ship.state)
	crew.update(delta, systems)
	crew_brain.update(delta, crew, systems, ship, enemy_targets)
	if gunner_station:
		systems.turret.update_manual(delta, ship, systems.weapon_factor(), projectiles, gunner_trigger, ship.upgrades.gun_damage_multiplier())
	else:
		var trigger := false # the pilot flies; only the gunner station (or the crew gunner) shoots the roof gun
		systems.turret.update(delta, ship, enemy_targets, systems.seats.state_of(&"gunner_seat") == SeatManager.SeatState.OCCUPIED, systems.weapon_factor(), projectiles, trigger, ship.upgrades.gun_damage_multiplier())
	systems.turret_firing = systems.turret.firing
	_update_repair(delta)
	var burning_now := systems.hazards.burning_rooms()
	if burning_now.size() > _burning_room_count:
		_say("FIRE in the %s!" % String(burning_now[-1]).replace("_", " "))
	_burning_room_count = burning_now.size()
	match mode:
		Mode.SITTING:
			# Glide into the seat instead of snapping, so the camera and body move continuously.
			_sit_elapsed += delta
			var progress := smoothstep(0.0, 1.0, clampf(_sit_elapsed / SeatManager.SIT_SECONDS, 0.0, 1.0))
			interior_body.position = _sit_start_position.lerp(systems.layout.seats[PILOT_SEAT]["position"], progress)
		Mode.INSIDE:
			interior_body.step(foot_command, systems.layout, delta)
			_maybe_walk_out()
		Mode.OUTSIDE:
			exterior_body.step(foot_command, planet, delta)
			_keep_outside_body_out_of_hull()
			_maybe_walk_in()
	_update_suit(delta)
	pistol.update(delta)
	var targets: Array = [_player_ship_target, _player_foot_target]
	targets.append_array(enemy_targets)
	projectiles.step(delta, targets)


func set_look(origin: Vector3, direction: Vector3) -> void:
	look_origin = origin
	look_direction = direction
	has_look = true


## The door or station the interact key would use right now (&"" for nothing).
func interaction_target() -> StringName:
	if has_look:
		return systems.layout.look_target(look_origin, look_direction)
	return systems.layout.nearest_interaction(interior_body.position)


## The airlock computer's buttons: "in", "close" or "out". Returns "" or the reason it was refused.
func airlock_command(goal: StringName) -> String:
	var failure := systems.request_airlock(goal, ship.state)
	if failure != "":
		interaction_refused.emit(&"airlock_outer" if goal == &"out" else &"airlock_inner", failure)
	return failure


func _door_prompt(portal_id: StringName) -> String:
	var open: bool = (systems.layout.portals[portal_id] as Portal).target_open
	match portal_id:
		&"airlock_inner": return "F — Close inner airlock door" if open else "F — Open inner airlock door"
		&"airlock_outer": return "F — Close outer door and stow ramp" if open else "F — Open outer door"
	return "F — Close door" if open else "F — Open door"


## The context-sensitive action key.
func interact() -> void:
	match mode:
		Mode.SEATED:
			_stand_up()
		Mode.SITTING:
			if systems.seats.cancel_sit(ACTOR):
				player_state.try_cancel_sit()
				mode = Mode.INSIDE
		Mode.INSIDE:
			_interact_inside()
		Mode.OUTSIDE:
			if not _try_open_crate():
				_say("Walk up the ramp to board")


## Captain's hotkeys: orders to the crew and the reactor's power split.
func order_crew_fix() -> void:
	_say(crew_brain.toggle_order(&"engineer", CrewBrain.Goal.ORDER_FIX, crew))


func order_crew_turret() -> void:
	_say(crew_brain.toggle_order(&"gunner", CrewBrain.Goal.ORDER_TURRET, crew))


func cycle_power_preset() -> void:
	_say("Power split: " + crew_brain.cycle_power_preset(systems, ACTOR))


func prompt() -> String:
	if message_seconds_left > 0.0:
		return message
	var context := _context_prompt()
	var scan := scan_text()
	if scan == "":
		return context
	return scan if context == "" else context + "\n" + scan


func _context_prompt() -> String:
	match mode:
		Mode.SEATED:
			return "F — Stand up"
		Mode.SITTING:
			return "Sitting down...  (F to cancel)"
		Mode.INSIDE:
			if systems.hazards.fire_in(player_room()) > 0.0 and extinguisher_charges > 0:
				return "F: spray the fire (%d sprays left)" % extinguisher_charges
			var nearest := interaction_target()
			if systems.layout.portals.has(nearest):
				return _door_prompt(nearest)
			match nearest:
				&"pilot_seat": return "F — Sit in pilot seat"
				&"reactor_panel": return "F — Reactor control"
				&"extinguisher_locker": return "F — Take fire extinguisher"
				&"engine_station": return "F — Engine station (install a part)"
				&"gunner_seat": return "F — Tactical console (dorsal gun)"
				&"workbench": return "F — Workbench (upgrades)"
				&"airlock_computer": return "F — Airlock computer"
				&"ops_computer": return "F — Operations computer"
				&"scanners": return "F — Scanners"
				&"ftl_radio": return "F — Pilot wave radio"
				&"battery_array": return "F — Battery array"
				&"limnal_drive": return "F — Limnal drive"
				&"bed": return "F — Rest (saves the game)"
				&"medbed": return "F — Use med bay"
				&"repair_panel": return "F — Repair hull" if not repairing else "F — Stop repairing"
		Mode.OUTSIDE:
			var crate := _nearest_crate()
			if not crate.is_empty():
				return PoiDefinition.ACTION_PROMPTS[(crate["poi"] as PoiInstance).type]
			if systems.walkway.is_deployed():
				return "Walk up the ramp to board"
	return ""


## Position of the player in the planet frame, whichever body is active.
func player_world_position() -> WorldPos:
	if mode == Mode.OUTSIDE:
		return exterior_body.position
	var inside_like := mode == Mode.INSIDE or mode == Mode.SITTING
	return ShipFrame.world_from_local(ship.state, interior_body.position if inside_like else _seat_local_position())


## Legal-state checks used by the fuzz test; returns "" when everything is consistent.
func validate() -> String:
	if not player_state.is_legal():
		return "player state illegal"
	if not systems.airlock.is_invariant_ok():
		return "both airlock doors open"
	match mode:
		Mode.SEATED:
			var expected_source: PilotSource = gunner_ai if gunner_station else pilot_source
			if ship.controller.current_source != expected_source or not systems.seats.is_seated(ACTOR):
				return "seated but not piloting"
		Mode.INSIDE:
			if not systems.layout.is_position_walkable(interior_body.position.x, interior_body.position.z, 0.0):
				return "interior body outside walkable area"
			if ship.controller.current_source != null:
				return "standing inside but ship still has a pilot"
		Mode.OUTSIDE:
			if planet.altitude_above_ground(exterior_body.position) < -0.01:
				return "outside body below ground"
	if systems.walkway.state == WalkwayController.State.STOWED and systems.layout.ramp_walkable:
		return "ramp walkable while stowed"
	for person in crew.members:
		if person.seat_id == &"" and not systems.layout.is_position_walkable(person.body.position.x, person.body.position.z, 0.0):
			return "crew member %s is inside a wall at %s" % [person.id, str(person.body.position)]
		if person.seat_id != &"" and systems.seats.seat_of(person.id) != person.seat_id:
			return "crew member %s thinks they hold a seat they do not" % person.id
	return ""


func _seat_local_position() -> Vector3:
	return systems.layout.seats[PILOT_SEAT]["position"]


## Swaps between the pilot's seat and the gun. On the gun an AI flies (it closes on the nearest hostile, weaving);
## its own trigger is ignored, the player's fire button works the turret. Only from the pilot seat.
func toggle_gunner_station() -> void:
	if gunner_station:
		_end_gunner_station()
		_say("Back at the helm")
		return
	if mode != Mode.SEATED or ship.controller.current_source != pilot_source:
		return
	ship.controller.release_control(pilot_source)
	gunner_ai = AIPilotSource.new(AIPilotSource.Mode.ATTACK)
	gunner_ai.target_provider = func(): return _gunner_ai_target(false)
	gunner_ai.target_velocity_provider = func(): return _gunner_ai_target(true)
	ship.controller.request_control(gunner_ai, &"gunner_ai")
	gunner_station = true
	_say("On the dorsal gun - autopilot flying")


func _end_gunner_station() -> void:
	if not gunner_station:
		return
	gunner_station = false
	gunner_trigger = false
	if gunner_ai != null:
		ship.controller.release_control(gunner_ai)
		gunner_ai = null
	if mode == Mode.SEATED:
		ship.controller.request_control(pilot_source, PILOT_SEAT)


func _gunner_ai_target(velocity: bool):
	var enemy := systems.turret.pick_target(ship, enemy_targets)
	if enemy == null:
		return Vector3.ZERO if velocity else null
	return enemy.combat_velocity() if velocity else enemy.combat_position()


func _stand_up() -> void:
	_end_gunner_station()
	if not systems.seats.stand(ACTOR):
		return
	player_state.try_stand_up()
	ship.controller.release_control(pilot_source)
	var seat: Dictionary = systems.layout.seats[PILOT_SEAT]
	interior_body.place(seat["exit_position"], seat["facing_yaw"])
	mode = Mode.INSIDE
	if ship.state.regime == FlightRegime.ATMOSPHERE or ship.state.regime == FlightRegime.NEAR_GROUND:
		if not ship.state.landed:
			_say("Ship is unpiloted and parked - it will keep drifting")


func _on_seat_occupied(_seat_id: StringName, actor_id: StringName) -> void:
	if actor_id != ACTOR:
		return
	if mode == Mode.SITTING or player_state.posture == PlayerState.Posture.SITTING_DOWN:
		player_state.try_finish_sit()
		mode = Mode.SEATED
		interior_body.position = _seat_local_position()
		ship.controller.request_control(pilot_source, PILOT_SEAT)
		if systems.takeoff_block_reason() != "":
			systems.secure_for_takeoff()
			_say("Securing the ship for takeoff...")
	elif mode == Mode.SEATED:
		pass


## The engine station takes the engine coupling; otherwise it only reports the engines' state.
func _use_engine_station() -> String:
	if inventory.count(ItemDefinition.ENGINE_COUPLING) > 0:
		_say(progress.install_engine_coupling(self))
		return ""
	if systems.subsystems.cap[ShipSubsystems.Id.ENGINES] < 1.0:
		return "The engine coupling is burnt out - you need a new one"
	return "Engines nominal (%d%%)" % (systems.subsystems.value(ShipSubsystems.Id.ENGINES) * 100.0)


func _interact_inside() -> void:
	var point := interaction_target()
	var failure := ""
	if point != &"extinguisher_locker" and extinguisher_charges > 0 and systems.hazards.fire_in(player_room()) > 0.0:
		extinguisher_charges -= 1
		systems.hazards.extinguish(player_room(), EXTINGUISHER_STRENGTH)
		_say("Sprayed (%d left)" % extinguisher_charges if systems.hazards.fire_in(player_room()) > 0.0 else "Fire out")
		return
	match point:
		&"pilot_seat":
			if not player_state.try_begin_sit().ok():
				failure = "Cannot sit down now"
			elif not systems.seats.try_sit(ACTOR, PILOT_SEAT):
				player_state.try_cancel_sit()
				failure = "Seat is taken"
			else:
				mode = Mode.SITTING
				_sit_start_position = interior_body.position
				_sit_elapsed = 0.0
		_ when systems.layout.portals.has(point) and (systems.layout.portals[point] as Portal).kind == Portal.Kind.DOOR:
			failure = systems.toggle_door(point) # every plain door, side rooms included, opens by looking at it and pressing F
		&"reactor_panel":
			reactor_requested.emit()
		&"extinguisher_locker":
			extinguisher_charges = EXTINGUISHER_CHARGES
			_say("Extinguisher ready (%d sprays)" % extinguisher_charges)
		&"engine_station":
			failure = _use_engine_station()
		&"gunner_seat":
			_say(_tactical_report(), 4.0) # a status read-out, not a fake control: the gun is fired from the helm (H)
		&"airlock_inner":
			failure = systems.toggle_inner_door()
		&"workbench":
			workbench_requested.emit()
		&"airlock_computer":
			airlock_requested.emit()
		&"ops_computer", &"scanners", &"ftl_radio", &"battery_array", &"limnal_drive":
			machine_requested.emit(point)
		&"bed":
			rest_requested.emit()
		&"medbed":
			if suit.health >= 0.99 and suit.oxygen >= 0.99:
				_say("The scanner finds nothing wrong")
			else:
				suit.health = 1.0
				suit.oxygen = 1.0
				_say("Treated: full health")
		&"repair_panel":
			failure = _toggle_repair()
		&"airlock_outer":
			failure = systems.toggle_outer_door(ship.state)
			if failure == "" and systems.airlock.outer.target_open:
				_fit_ramp_to_ground()
		_:
			failure = "Nothing to use here"
	if failure != "":
		_say(failure)
		interaction_refused.emit(point, failure)


## What the tactical console reports about the real dorsal gun (ShipTurret) and the gear that arms it.
func _tactical_report() -> String:
	var turret := systems.turret
	var armed := Ship.gear_allows_fire(ship.state.gear)
	var state := "OVERHEATED" if turret.overheated else ("armed" if armed else "safe (combat gear arms it)")
	return "Dorsal gun %s, heat %d%%. Fire it from the pilot seat: H mans the gun." % [state, roundi(turret.heat * 100.0)]


## Ramp end height so the walkway meets the ground (ship-local y), clamped to a usable range.
func _fit_ramp_to_ground() -> void:
	var layout := systems.layout
	var end_local := Vector3(0.0, layout.floor_y, layout.ramp_rect.end.y)
	var end_world := ShipFrame.world_from_local(ship.state, end_local)
	var distance := planet.distance_from_center(end_world)
	var ground_distance := planet.surface_radius_xyz(end_world.x / distance, end_world.y / distance, end_world.z / distance)
	var ground_world := WorldPos.new(end_world.frame_id, end_world.x / distance * ground_distance, end_world.y / distance * ground_distance, end_world.z / distance * ground_distance)
	layout.ramp_end_y = clampf(ShipFrame.local_from_world(ship.state, ground_world).y, layout.floor_y - 3.0, layout.floor_y + 0.5)


func _is_in_doorway(portal: Portal) -> bool:
	if mode == Mode.INSIDE:
		return portal.opening.grow(DOORWAY_MARGIN).has_point(Vector2(interior_body.position.x, interior_body.position.z))
	return false


func _is_anyone_on_ramp() -> bool:
	var ramp := systems.layout.ramp_rect
	match mode:
		Mode.INSIDE:
			return ramp.has_point(Vector2(interior_body.position.x, interior_body.position.z))
		Mode.OUTSIDE:
			var local := ShipFrame.local_from_world(ship.state, exterior_body.position)
			return ramp.has_point(Vector2(local.x, local.z)) and systems.walkway.progress > 0.0
	return false


## Inside -> outside once the walker is out through the outer doorway onto the ramp. Position, heading and velocity
## carry over unchanged; from here the ramp is an outside floor (see _ramp_floor_distance).
func _maybe_walk_out() -> void:
	if not systems.layout.ramp_walkable or interior_body.position.z < DOOR_EXIT_Z:
		return
	if not player_state.try_go_outside().ok():
		return
	var feet_world := ShipFrame.world_from_local(ship.state, interior_body.position)
	var heading := ship.state.basis * interior_body.forward()
	exterior_body.place_on_ground(planet, feet_world, heading)
	exterior_body.velocity = ship.state.basis * Vector3(interior_body.velocity.x, 0.0, interior_body.velocity.y)
	mode = Mode.OUTSIDE


## Outside -> inside when the walker, on the deployed ramp, reaches the outer doorway. Position, heading and
## velocity carry over unchanged.
func _maybe_walk_in() -> void:
	if not systems.walkway.is_deployed():
		return
	var local := ShipFrame.local_from_world(ship.state, exterior_body.position)
	var ramp := systems.layout.ramp_rect
	var in_doorway := absf(local.x) <= ramp.size.x * 0.5 - InteriorBody.RADIUS and local.z < DOOR_ENTER_Z and local.z > ramp.position.y - OUTSIDE_RADIUS
	if not in_doorway or not player_state.try_go_inside().ok():
		return
	var facing_local := ship.state.basis.transposed() * exterior_body.heading
	var yaw := atan2(-facing_local.x, -facing_local.z)
	var velocity_local := ship.state.basis.transposed() * exterior_body.velocity
	interior_body.place(Vector3(local.x, systems.layout.floor_height_at(local.x, local.z), local.z), yaw)
	interior_body.velocity = Vector2(velocity_local.x, velocity_local.z)
	mode = Mode.INSIDE


func _keep_outside_body_out_of_hull() -> void:
	var local := ShipFrame.local_from_world(ship.state, exterior_body.position)
	var corrected := ShipHullCollision.push_out(local, OUTSIDE_RADIUS, systems.layout.ramp_rect, systems.walkway.progress > 0.0)
	if corrected != local:
		var corrected_world := ShipFrame.world_from_local(ship.state, corrected)
		if exterior_body.grounded:
			exterior_body.place_on_ground(planet, corrected_world, exterior_body.heading)
		else:
			exterior_body.position = corrected_world
			exterior_body.velocity = Vector3.ZERO
		local = corrected
	_keep_out_of_ramp_sides(local)


## The deployed ramp is a solid wedge: from the ground beside it, its sides are a wall wherever its surface is more
## than RAMP_STEP_UP above the feet. The walker slides along that wall (only the velocity into it is removed).
func _keep_out_of_ramp_sides(local: Vector3) -> void:
	if not systems.walkway.is_deployed():
		return
	var layout := systems.layout
	var ramp := layout.ramp_rect
	var half_width := ramp.size.x * 0.5
	if absf(local.x) >= half_width + OUTSIDE_RADIUS or local.z <= ramp.position.y or local.z >= ramp.end.y:
		return
	if local.y >= layout.ramp_height_at(local.z) - RAMP_STEP_UP:
		return # standing on the ramp (or able to step onto it)
	# Out through the nearest face: either side, or the far end if the ramp's end stands above the ground there.
	var corrected_local := Vector3(half_width + OUTSIDE_RADIUS, local.y, local.z)
	var outward := ship.state.basis.x
	if local.x < 0.0:
		corrected_local.x = -corrected_local.x
		outward = -outward
	if ramp.end.y + OUTSIDE_RADIUS - local.z < half_width + OUTSIDE_RADIUS - absf(local.x):
		corrected_local = Vector3(local.x, local.y, ramp.end.y + OUTSIDE_RADIUS)
		outward = ship.state.basis.z
	var corrected_world := ShipFrame.world_from_local(ship.state, corrected_local)
	var velocity := exterior_body.velocity
	velocity -= outward * minf(0.0, velocity.dot(outward))
	if exterior_body.grounded:
		exterior_body.place_on_ground(planet, corrected_world, exterior_body.heading)
	else:
		exterior_body.position = corrected_world
	exterior_body.velocity = velocity


## Radial distance of the deployed ramp's surface above a planet-frame point, or -1 if the point is not over the ramp
## or is too far below its surface to step onto it (then the ground under the ramp is the floor, and its sides walls).
func _ramp_floor_distance(point_x: float, point_y: float, point_z: float) -> float:
	if ship == null or systems == null or not systems.walkway.is_deployed():
		return -1.0
	var layout := systems.layout
	var local := ShipFrame.local_from_world(ship.state, WorldPos.new(ship.state.position.frame_id, point_x, point_y, point_z))
	# The walker stands on the ramp while any part of its body is over it (its centre may be just past the edge); it
	# steps off only once clear, so it never drops beside the ramp still overlapping its side.
	if not layout.ramp_rect.grow_individual(OUTSIDE_RADIUS, 0.0, OUTSIDE_RADIUS, 0.0).has_point(Vector2(local.x, local.z)):
		return -1.0
	var surface_y := layout.ramp_height_at(local.z)
	if local.y < surface_y - RAMP_STEP_UP:
		return -1.0
	var surface := ShipFrame.world_from_local(ship.state, Vector3(local.x, surface_y, local.z))
	return planet.distance_from_center(surface)


## Shows a short message in the prompt line.
func say(text: String) -> void:
	_say(text)


func _say(text: String, seconds: float = 2.5) -> void:
	message = text
	message_seconds_left = seconds


## Puts the session into a saved mode. Interior/exterior bodies and ship state must already be set.
func restore_mode(saved_mode: int) -> void:
	_end_gunner_station()
	var seat_position: Vector3 = systems.layout.seats[PILOT_SEAT]["position"]
	ship.controller.release_control(pilot_source)
	systems.seats.reset()
	message = ""
	message_seconds_left = 0.0
	match saved_mode:
		Mode.SEATED:
			mode = Mode.SEATED
			player_state.restore(PlayerState.Posture.SEATED, PlayerState.Location.INTERIOR, PlayerState.Authority.PILOT)
			systems.seats.try_sit(ACTOR, PILOT_SEAT)
			systems.seats.update(SeatManager.SIT_SECONDS)
			interior_body.position = seat_position
			ship.controller.request_control(pilot_source, PILOT_SEAT)
		Mode.OUTSIDE:
			mode = Mode.OUTSIDE
			player_state.restore(PlayerState.Posture.STANDING, PlayerState.Location.EXTERIOR, PlayerState.Authority.NONE)
		_:
			mode = Mode.INSIDE
			player_state.restore(PlayerState.Posture.STANDING, PlayerState.Location.INTERIOR, PlayerState.Authority.NONE)


## Discover any POI within reach of a person on foot outside the ship. Call once per tick with the
## POIs that are currently known; each fires its discovery once.
func check_discovery(known_pois: Array) -> void:
	if mode != Mode.OUTSIDE:
		return
	for instance in known_pois:
		if discovery_log.is_discovered(instance.id):
			continue
		if instance.position.distance_to(exterior_body.position) <= PoiDefinition.DISCOVER_RADIUS:
			if discovery_log.try_discover(instance):
				_say("Discovered: " + instance.display_name)


## Forward direction of the player in the planet frame (for pointing at things).
func forward_vector() -> Vector3:
	match mode:
		Mode.OUTSIDE:
			return exterior_body.heading
		Mode.INSIDE, Mode.SITTING:
			return ship.state.basis * interior_body.forward()
	return -ship.state.basis.z


## Push the walker out of solid POI props (wrecks, buildings, beacon bases). Call once per tick with the
## POIs near the player; only POIs close enough to matter are examined.
func apply_poi_blockers(near_pois: Array) -> void:
	if mode != Mode.OUTSIDE:
		return
	for instance in near_pois:
		var offset := exterior_body.position.vector_from(instance.position)
		if offset.length() > 120.0:
			continue
		var frame := PoiBuilder.frame_basis(instance)
		var local_x := offset.dot(frame.x)
		var local_z := offset.dot(frame.z)
		for circle in PoiBuilder.blockers(instance):
			var away := Vector2(local_x - circle.x, local_z - circle.y)
			var limit := circle.z + 0.4
			if away.length() < limit:
				var pushed := (away.normalized() if away.length() > 1e-4 else Vector2.RIGHT) * limit
				var correction := frame.x * (circle.x + pushed.x - local_x) + frame.z * (circle.y + pushed.y - local_z)
				exterior_body.place_on_ground(planet, exterior_body.position.offset_by(correction), exterior_body.heading)
				local_x = offset.dot(frame.x) + correction.dot(frame.x)
				local_z = offset.dot(frame.z) + correction.dot(frame.z)


func _toggle_repair() -> String:
	if repairing:
		repairing = false
		return ""
	if not ship.state.landed:
		return "Land before repairing"
	if ship.state.hull >= 1.0 and systems.subsystems.is_undamaged():
		return "Nothing to repair"
	repairing = true
	return ""


func _update_repair(delta: float) -> void:
	if not repairing:
		return
	if not ship.state.landed:
		repairing = false
		return
	ship.state.hull = minf(1.0, ship.state.hull + ShipDamage.REPAIR_PER_SECOND * delta)
	systems.subsystems.repair_worst(ShipDamage.REPAIR_PER_SECOND * delta)
	if ship.state.hull >= 1.0 and systems.subsystems.is_undamaged():
		repairing = false
		_say("Ship repaired")


## The ship room the player is in; &"" when outside.
func player_room() -> StringName:
	match mode:
		Mode.SEATED, Mode.SITTING:
			return &"cockpit"
		Mode.INSIDE:
			return systems.layout.room_at(interior_body.position.x, interior_body.position.z)
	return &""


## One line for the HUD when the ship is in trouble, "" otherwise.
func alert_text() -> String:
	var burning := systems.hazards.burning_rooms()
	if not burning.is_empty():
		return "FIRE in " + ", ".join(burning.map(func(room): return String(room).replace("_", " ")))
	if systems.power.is_shut_down():
		return "REACTOR SHUTDOWN - cooling down"
	return ""


func _update_suit(delta: float) -> void:
	var breathable := true
	var room := player_room()
	if room != &"" and systems.hazards.has_room(room):
		breathable = systems.hazards.is_breathable(room)
		var heat := systems.hazards.fire_in(room)
		if heat >= 0.5:
			suit.burn(0.05 * heat * delta)
	match mode:
		Mode.OUTSIDE:
			breathable = in_building or (planet != null and planet.breathable)
		Mode.INSIDE:
			breathable = breathable and not (room == &"airlock" and systems.airlock_pressure < 0.5)
	suit.update(delta, breathable, mode == Mode.OUTSIDE and exterior_body.jetpack_burning, mode != Mode.OUTSIDE or exterior_body.grounded)


const CRATE_REACH := 3.2

## The closest unlooted crate within reach of the walker: {poi, index, id} or {}.
func _nearest_crate() -> Dictionary:
	if mode != Mode.OUTSIDE:
		return {}
	var best := {}
	var best_distance := CRATE_REACH
	for instance in nearby_pois:
		var offset := exterior_body.position.vector_from(instance.position)
		if offset.length() > 80.0:
			continue
		var frame := PoiBuilder.frame_basis(instance)
		var here := Vector2(offset.dot(frame.x), offset.dot(frame.z))
		var crate_index := 0
		for crate_position in PoiBuilder.crate_positions(instance):
			var crate_id := PoiBuilder.crate_id(instance, crate_index)
			var distance := here.distance_to(crate_position)
			if distance < best_distance and not loot_log.is_looted(crate_id):
				best = {"poi": instance, "index": crate_index, "id": crate_id}
				best_distance = distance
			crate_index += 1
	return best


func _try_open_crate() -> bool:
	var crate := _nearest_crate()
	if crate.is_empty():
		return false
	var instance: PoiInstance = crate["poi"]
	var contents := LootTable.roll(instance.seed_value, instance.type, crate["index"])
	if instance.id == ProgressTracker.BEACON_ID and crate["index"] == 0:
		contents.append({"item": ItemDefinition.ENGINE_COUPLING, "count": 1})
	for entry in contents:
		if not inventory.can_fit(entry["item"], entry["count"]):
			_say("Inventory full - make room first")
			return true
	var found: Array[String] = []
	for entry in contents:
		inventory.add(entry["item"], entry["count"])
		found.append("%d %s" % [entry["count"], ItemDefinition.display_name(entry["item"])])
	loot_log.mark_looted(crate["id"])
	var result := String(PoiDefinition.RESULT_LABELS[instance.type]) + ": " + ", ".join(found)
	if PoiDefinition.is_minor(instance.type):
		result += "\n" + PoiDefinition.finding_text(instance.type, instance.seed_value)
	_say(result, 6.0 if PoiDefinition.is_minor(instance.type) else 2.5)
	return true


## Sends a scanner pulse from wherever the player is (flying, inside or on foot): every site within PoiScanner.RANGE of the
## POIs the scene knows about becomes a remembered contact. Returns the contacts nearest first ([] while recharging).
func scan_pulse() -> Array[Dictionary]:
	if scan_cooldown > 0.0:
		_say("Scanner recharging")
		return []
	scan_cooldown = PoiScanner.COOLDOWN_SECONDS
	scan_readout_seconds = PoiScanner.READOUT_SECONDS
	var contacts := PoiScanner.pulse(player_world_position(), forward_vector(), nearby_pois, discovery_log, loot_log)
	if contacts.is_empty():
		_say("Scan complete: no signals in range")
	else:
		_say("Scan: %d signal%s in range" % [contacts.size(), "" if contacts.size() == 1 else "s"])
	return contacts


## The scanner lines under the prompt: remembered contacts and unfinished sites, nearest first, with live distance and direction.
func scan_text() -> String:
	if scan_readout_seconds <= 0.0 or nearby_pois.is_empty():
		return ""
	return PoiScanner.readout(PoiScanner.live_contacts(player_world_position(), forward_vector(), nearby_pois, discovery_log, loot_log))


## Use one item from the inventory. Returns the message shown to the player.
func use_item(item_id: StringName) -> String:
	if inventory.count(item_id) <= 0:
		return "You do not have that"
	var near_ship := player_world_position().distance_to(ship.state.position) <= 15.0
	var message_text := ""
	match item_id:
		ItemDefinition.OXYGEN_TANK:
			if suit.oxygen >= 0.99:
				return "Your suit is already full"
			suit.oxygen = 1.0
			message_text = "Suit oxygen refilled"
		ItemDefinition.REPAIR_KIT:
			if not near_ship:
				return "Get closer to the ship"
			if ship.state.hull >= 1.0 and systems.subsystems.is_undamaged():
				return "Nothing to repair"
			ship.state.hull = minf(1.0, ship.state.hull + 0.5)
			systems.subsystems.repair_worst(0.5)
			message_text = "Ship repaired"
		ItemDefinition.FUEL_CELL:
			if not near_ship:
				return "Get closer to the ship"
			if ship.state.fuel >= 0.99:
				return "Tank is full"
			ship.state.fuel = minf(1.0, ship.state.fuel + 0.5)
			message_text = "Refuelled"
		ItemDefinition.WARP_COIL:
			if not near_ship:
				return "Get closer to the ship"
			var install_message := progress.install_warp_coil(self)
			_say(install_message)
			return install_message
		_:
			return "That cannot be used"
	inventory.remove(item_id, 1)
	_say(message_text)
	return message_text


## Fire the pistol (on foot only) along a unit direction in the planet frame.
func player_fire(aim_direction: Vector3) -> void:
	if mode != Mode.OUTSIDE or suit.health <= 0.0:
		return
	var muzzle := exterior_body.position.offset_by(Vector3(exterior_body.position.x, exterior_body.position.y, exterior_body.position.z).normalized() * 1.5)
	pistol.try_fire(projectiles, muzzle, aim_direction, exterior_body.velocity, 0, self)


## Floor radius under a point if it is on the deployed ramp or inside an outpost depot, else -1 (use the terrain).
func _floor_override(point_x: float, point_y: float, point_z: float) -> float:
	var ramp_floor := _ramp_floor_distance(point_x, point_y, point_z)
	if ramp_floor >= 0.0:
		return ramp_floor
	for instance in nearby_pois:
		if instance.type != PoiDefinition.Type.OUTPOST:
			continue
		var point := WorldPos.new(instance.position.frame_id, point_x, point_y, point_z)
		var offset := point.vector_from(instance.position)
		if offset.length() > 150.0:
			continue
		var frame := PoiBuilder.frame_basis(instance)
		if PoiBuilder.is_in_depot(instance, offset.dot(frame.x), offset.dot(frame.z)):
			return planet.distance_from_center(instance.position) + PoiBuilder.depot_floor_height(planet, instance)
	return -1.0


## Keep the walker inside depot walls, and tell the suit when it is indoors. Call once per tick.
func apply_building_walls() -> void:
	in_building = false
	if mode != Mode.OUTSIDE:
		return
	for instance in nearby_pois:
		if instance.type != PoiDefinition.Type.OUTPOST:
			continue
		var offset := exterior_body.position.vector_from(instance.position)
		if offset.length() > 150.0:
			continue
		var frame := PoiBuilder.frame_basis(instance)
		var local_point := Vector2(offset.dot(frame.x), offset.dot(frame.z))
		if not PoiBuilder.is_in_depot(instance, local_point.x, local_point.y, 2.0):
			continue
		var building: PoiBuilding = instance.building()
		var building_point: Vector2 = local_point - PoiBuilder.DEPOT_ORIGIN
		var corrected: Vector2 = building.push_out_of_walls(building_point, 0.45)
		if corrected != building_point:
			var shift: Vector3 = frame.x * (corrected.x - building_point.x) + frame.z * (corrected.y - building_point.y)
			exterior_body.position = exterior_body.position.offset_by(shift)
		in_building = building.room_index_at(corrected) >= 0 and PoiBuilder.is_in_depot(instance, local_point.x, local_point.y)
		return


func buy_upgrade(upgrade_id: StringName) -> String:
	var problem := ship.upgrades.buy(upgrade_id, inventory)
	if problem == "":
		suit.oxygen_duration_multiplier = ship.upgrades.oxygen_duration_multiplier()
		_say("Installed: " + ShipUpgrades.CATALOG[upgrade_id]["name"])
	return problem
