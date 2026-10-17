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

var planet: PlanetBody
var ship: Ship
var systems: ShipSystems
var player_state := PlayerState.new()
var interior_body := InteriorBody.new()
var exterior_body := OnFootBody.new()
var pilot_source: PilotSource
var discovery_log := DiscoveryLog.new()
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
	ship.controller.request_control(pilot_source, PILOT_SEAT)
	systems.seats.try_sit(ACTOR, PILOT_SEAT)
	systems.seats.update(SeatManager.SIT_SECONDS) # start the game already seated


## Advance one physics tick. foot_command drives whichever body is walking.
func tick(delta: float, foot_command: OnFootCommand) -> void:
	message_seconds_left = maxf(0.0, message_seconds_left - delta)
	systems.walkway.occupied = _is_anyone_on_ramp()
	for portal_id in systems.layout.portals:
		systems.occupied_portals[portal_id] = _is_in_doorway(systems.layout.portals[portal_id])
	ship.simulate_tick(delta)
	systems.update(delta, ship.state)
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
			match systems.layout.nearest_interaction(interior_body.position):
				&"pilot_seat": return "F: sit in the pilot seat"
				&"cockpit_door": return "F: cockpit door"
				&"airlock_inner": return "F: inner airlock door"
				&"airlock_outer": return "F: outer door / walkway"
		Mode.OUTSIDE:
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
		&"cockpit_door":
			failure = systems.toggle_cockpit_door()
		&"airlock_inner":
			failure = systems.toggle_inner_door()
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
