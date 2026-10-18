class_name GameSession
extends RefCounted
## The director: owns the player's whole situation (seated / inside / outside), ties the ship,
## its interior systems and the player's bodies together, and performs every transition
## (stand up, sit, airlock, walkway, walk out, walk in) as a continuous change of frame, never a
## teleport. Scenes only feed it commands and draw the result, so the full loop is testable headless.

enum Mode { SEATED, SITTING, INSIDE, OUTSIDE }

const ACTOR := &"player"
const PILOT_SEAT := &"pilot_seat"
## How far past the ramp's last metre before the walker is considered outside.
## The walker's body stops RADIUS short of the ramp's end, so "reached the end" means within this margin of that.
const RAMP_EXIT_MARGIN := 0.1
## How far onto the ramp an outside walker must be before counting as boarded.
const RAMP_ENTER_DEPTH := 0.8
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
var discovery_log := DiscoveryLog.new()
var suit := SuitState.new()
var progress := ProgressTracker.new()
var inventory := Inventory.new()
var loot_log := LootLog.new()
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
## The player used the reactor panel; the scene opens the reactor screen.
signal reactor_requested
## Sprays left in the carried fire extinguisher (refilled at the locker in engineering).
const EXTINGUISHER_CHARGES := 6
const EXTINGUISHER_STRENGTH := 0.35
var extinguisher_charges := 0
var _burning_room_count := 0
var mode := Mode.SEATED
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
	ship.auto_tick = false
	systems.seats.seat_occupied.connect(_on_seat_occupied)
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
	systems.walkway.occupied = _is_anyone_on_ramp()
	for portal_id in systems.layout.portals:
		systems.occupied_portals[portal_id] = _is_in_doorway(systems.layout.portals[portal_id])
	systems.ambient_pressure = 1.0 if planet != null and planet.breathable and ship.state.atmosphere_ratio < 1.0 else 0.0
	exterior_body.jetpack_fuel_available = suit.has_fuel()
	ship.simulate_tick(delta)
	systems.update(delta, ship.state)
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


func prompt() -> String:
	if message_seconds_left > 0.0:
		return message
	match mode:
		Mode.SEATED:
			return "F: stand up"
		Mode.SITTING:
			return "Sitting down...  (F to cancel)"
		Mode.INSIDE:
			if systems.hazards.fire_in(player_room()) > 0.0 and extinguisher_charges > 0:
				return "F: spray the fire (%d sprays left)" % extinguisher_charges
			var nearest := systems.layout.nearest_interaction(interior_body.position)
			match nearest:
				&"pilot_seat": return "F: sit in the pilot seat"
				&"cockpit_door", &"engineering_door", &"turret_door", &"cargo_door": return "F: door"
				&"reactor_panel": return "F: reactor panel"
				&"extinguisher_locker": return "F: take the fire extinguisher"
				&"engine_station", &"gunner_seat": return "F: " + STATION_NAMES[nearest]
				&"airlock_inner": return "F: inner airlock door"
				&"airlock_outer": return "F: outer door / walkway"
				&"workbench": return "F: workbench (upgrades)"
				&"repair_panel": return "F: repair hull" if not repairing else "F: stop repairing"
		Mode.OUTSIDE:
			if not _nearest_crate().is_empty():
				return "F: open crate"
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
			if ship.controller.current_source != pilot_source or not systems.seats.is_seated(ACTOR):
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
	return ""


func _seat_local_position() -> Vector3:
	return systems.layout.seats[PILOT_SEAT]["position"]


func _stand_up() -> void:
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


func _on_seat_occupied(_seat_id: StringName, _actor_id: StringName) -> void:
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


func _interact_inside() -> void:
	var point := systems.layout.nearest_interaction(interior_body.position)
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
		&"cockpit_door", &"engineering_door", &"turret_door", &"cargo_door":
			failure = systems.toggle_door(point)
		&"reactor_panel":
			reactor_requested.emit()
		&"extinguisher_locker":
			extinguisher_charges = EXTINGUISHER_CHARGES
			_say("Extinguisher ready (%d sprays)" % extinguisher_charges)
		&"engine_station", &"gunner_seat":
			failure = STATION_NAMES[point] + " is not connected yet"
		&"airlock_inner":
			failure = systems.toggle_inner_door()
		&"workbench":
			workbench_requested.emit()
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


## Inside -> outside once the walker reaches the far end of the ramp.
func _maybe_walk_out() -> void:
	var ramp := systems.layout.ramp_rect
	if not systems.layout.ramp_walkable or interior_body.position.z < ramp.end.y - InteriorBody.RADIUS - RAMP_EXIT_MARGIN:
		return
	if not player_state.try_go_outside().ok():
		return
	var feet_world := ShipFrame.world_from_local(ship.state, interior_body.position)
	var heading := ship.state.basis * interior_body.forward()
	exterior_body.place_on_ground(planet, feet_world, heading)
	exterior_body.velocity = ship.state.basis * Vector3(interior_body.velocity.x, 0.0, interior_body.velocity.y)
	mode = Mode.OUTSIDE


## Outside -> inside when the walker steps onto the deployed ramp's far end.
func _maybe_walk_in() -> void:
	if not systems.walkway.is_deployed():
		return
	var local := ShipFrame.local_from_world(ship.state, exterior_body.position)
	var ramp := systems.layout.ramp_rect
	var on_ramp_end := absf(local.x) < ramp.size.x * 0.5 and local.z < ramp.end.y - RAMP_ENTER_DEPTH and local.z > ramp.position.y
	if not on_ramp_end or not player_state.try_go_inside().ok():
		return
	var facing_local := ship.state.basis.transposed() * exterior_body.heading
	var yaw := atan2(-facing_local.x, -facing_local.z)
	interior_body.place(Vector3(local.x, systems.layout.floor_height_at(local.x, local.z), local.z), yaw)
	mode = Mode.INSIDE


func _keep_outside_body_out_of_hull() -> void:
	var local := ShipFrame.local_from_world(ship.state, exterior_body.position)
	var corrected := ShipHullCollision.push_out(local, 0.4, systems.layout.ramp_rect, systems.walkway.progress > 0.0)
	if corrected != local:
		var corrected_world := ShipFrame.world_from_local(ship.state, corrected)
		if exterior_body.grounded:
			exterior_body.place_on_ground(planet, corrected_world, exterior_body.heading)
		else:
			exterior_body.position = corrected_world
			exterior_body.velocity = Vector3.ZERO


## Shows a short message in the prompt line.
func say(text: String) -> void:
	_say(text)


func _say(text: String) -> void:
	message = text
	message_seconds_left = 2.5


## Puts the session into a saved mode. Interior/exterior bodies and ship state must already be set.
func restore_mode(saved_mode: int) -> void:
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
	for entry in contents:
		if not inventory.can_fit(entry["item"], entry["count"]):
			_say("Inventory full - make room first")
			return true
	var found: Array[String] = []
	for entry in contents:
		inventory.add(entry["item"], entry["count"])
		found.append("%d %s" % [entry["count"], ItemDefinition.display_name(entry["item"])])
	loot_log.mark_looted(crate["id"])
	_say("Found: " + ", ".join(found))
	return true


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


## Floor radius under a point if it is inside an outpost depot, else -1 (use the terrain).
func _floor_override(point_x: float, point_y: float, point_z: float) -> float:
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
