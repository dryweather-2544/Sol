class_name SaveGame
extends RefCounted
## Turns the live game into plain data and back. Save *state*, not scenes (research 08 §8.3):
## positions are WorldPos (frame + doubles), doors and walkway by authored id. Everything
## written is JSON-safe (numbers, strings, bools, arrays, dictionaries).

const SAVE_VERSION := 11
const GAME_VERSION := "0.1"


static func capture(session: GameSession, world_seed: int, game_time_seconds: float = 0.0) -> Dictionary:
	var ship_state := session.ship.state
	var systems := session.systems
	var portals := {}
	for portal_id in systems.layout.portals:
		var portal: Portal = systems.layout.portals[portal_id]
		portals[String(portal_id)] = {"target_open": portal.target_open, "open_factor": portal.open_factor}
	var saved_mode := session.mode
	if saved_mode == GameSession.Mode.SITTING:
		saved_mode = GameSession.Mode.INSIDE # sitting down is transient; resume standing at the seat
	var interior_position := session.interior_body.position
	if session.mode == GameSession.Mode.SITTING:
		interior_position = session._sit_start_position
	return {
		"save_version": SAVE_VERSION,
		"game_version": GAME_VERSION,
		"world_seed": world_seed,
		"world": {"time": game_time_seconds, "frame": String(session.ship.state.position.frame_id)},
		"ship": {
			"position": ship_state.position.to_dictionary(),
			"velocity": _vector_to_array(ship_state.velocity),
			"orientation": _quaternion_to_array(Quaternion(ship_state.basis)),
			"angular_velocity": _vector_to_array(ship_state.angular_velocity),
			"gear": ship_state.gear,
			"landed": ship_state.landed,
			"hull": ship_state.hull,
			"fuel": ship_state.fuel,
		},
		"interior": {
			"portals": portals,
			"walkway": {"state": systems.walkway.state, "progress": systems.walkway.progress},
			"ramp_end_y": systems.layout.ramp_end_y,
		},
		"systems": {"subsystems": systems.subsystems.to_array(), "power": systems.power.to_dictionary(), "hazards": systems.hazards.to_dictionary(),
			"caps": systems.subsystems.caps_to_array(), "ambush_armed": systems.ambush_armed},
		"player": {
			"mode": saved_mode,
			"interior_position": _vector_to_array(interior_position),
			"interior_yaw": session.interior_body.yaw,
			"extinguisher": session.extinguisher_charges,
			"suit": {"oxygen": session.suit.oxygen, "fuel": session.suit.fuel, "health": session.suit.health},
			"exterior": {
				"position": session.exterior_body.position.to_dictionary(),
				"heading": _vector_to_array(session.exterior_body.heading),
				"velocity": _vector_to_array(session.exterior_body.velocity),
				"vertical_speed": session.exterior_body.vertical_speed,
				"grounded": session.exterior_body.grounded,
			},
		},
		"pois": {
			"generation_version": PoiPlanner.GENERATION_VERSION,
			"discovered": session.discovery_log.to_array(),
			"looted": session.loot_log.to_array(),
			"cleared": session.cleared_log.to_array(),
		},
		"crew": session.crew.to_array(),
		"inventory": session.inventory.to_dictionary(),
		"upgrades": session.ship.upgrades.to_array(),
		"progress": {"objective": session.progress.current, "warp_installed": session.progress.warp_installed, "coupling_installed": session.progress.coupling_installed,
			"ambush_started": session.progress.ambush_started, "beacon_direction": _vector_to_array(session.progress.beacon_direction)},
	}


## Applies saved data to a (fresh or running) session. Returns "" on success or an error message.
static func restore(session: GameSession, data: Dictionary) -> String:
	if not data.has("ship") or not data.has("player") or not data.has("interior"):
		return "save data is missing sections"
	var ship_data: Dictionary = data["ship"]
	var ship_state := session.ship.state
	ship_state.position = WorldPos.from_dictionary(ship_data["position"])
	ship_state.velocity = _array_to_vector(ship_data["velocity"])
	ship_state.basis = Basis(_array_to_quaternion(ship_data["orientation"]).normalized())
	ship_state.angular_velocity = _array_to_vector(ship_data["angular_velocity"])
	ship_state.gear = int(ship_data["gear"])
	ship_state.landed = bool(ship_data["landed"])
	ship_state.hull = float(ship_data.get("hull", 1.0))
	ship_state.fuel = float(ship_data.get("fuel", 1.0))

	var systems := session.systems
	var interior_data: Dictionary = data["interior"]
	for portal_key in interior_data["portals"]:
		var portal: Portal = systems.layout.portals[StringName(portal_key)]
		portal.target_open = bool(interior_data["portals"][portal_key]["target_open"])
		portal.open_factor = float(interior_data["portals"][portal_key]["open_factor"])
	systems.walkway.state = int(interior_data["walkway"]["state"])
	systems.walkway.progress = float(interior_data["walkway"]["progress"])
	systems.walkway.occupied = false
	var systems_data: Dictionary = data.get("systems", {})
	systems.subsystems.restore(systems_data.get("subsystems", []))
	systems.power.restore(systems_data.get("power", {}))
	systems.hazards.restore(systems_data.get("hazards", {}))
	systems.subsystems.restore_caps(systems_data.get("caps", []))
	systems.ambush_armed = bool(systems_data.get("ambush_armed", false))
	systems.layout.ramp_end_y = float(interior_data["ramp_end_y"])
	systems.layout.ramp_walkable = systems.walkway.is_deployed()
	systems.airlock.reset_cycle()
	systems.reset_pending_actions()

	var player_data: Dictionary = data["player"]
	var mode := int(player_data["mode"])
	var exterior: Dictionary = player_data["exterior"]
	var saved_interior_position := _array_to_vector(player_data["interior_position"])
	var saved_ramp_position_ok := systems.layout.ramp_walkable and systems.layout.ramp_rect.has_point(Vector2(saved_interior_position.x, saved_interior_position.z))
	if not saved_ramp_position_ok and not systems.layout.is_position_walkable(saved_interior_position.x, saved_interior_position.z, 0.0):
		# A save from an older layout can leave someone inside a wall; put them at the pilot seat instead.
		saved_interior_position = systems.layout.seats[&"pilot_seat"]["exit_position"]
	session.interior_body.place(saved_interior_position, float(player_data["interior_yaw"]))
	session.exterior_body.position = WorldPos.from_dictionary(exterior["position"])
	session.exterior_body.heading = _array_to_vector(exterior["heading"])
	session.exterior_body.velocity = _array_to_vector(exterior["velocity"])
	session.exterior_body.vertical_speed = float(exterior["vertical_speed"])
	session.exterior_body.grounded = bool(exterior["grounded"])
	var suit_data: Dictionary = player_data.get("suit", {})
	session.suit.oxygen = float(suit_data.get("oxygen", 1.0))
	session.suit.fuel = float(suit_data.get("fuel", 1.0))
	session.suit.health = float(suit_data.get("health", 1.0))
	session.repairing = false
	session.extinguisher_charges = int(player_data.get("extinguisher", 0))
	session.restore_mode(mode)
	var poi_data: Dictionary = data.get("pois", {})
	session.discovery_log.restore(poi_data.get("discovered", []))
	session.loot_log.restore(poi_data.get("looted", []))
	session.cleared_log.restore(poi_data.get("cleared", []))
	session.projectiles.clear()
	session.ship.upgrades.restore(data.get("upgrades", []))
	session.suit.oxygen_duration_multiplier = session.ship.upgrades.oxygen_duration_multiplier()
	var progress_data: Dictionary = data.get("progress", {})
	session.progress.current = int(progress_data.get("objective", 0))
	session.progress.warp_installed = bool(progress_data.get("warp_installed", false))
	session.progress.coupling_installed = bool(progress_data.get("coupling_installed", false))
	session.progress.ambush_started = bool(progress_data.get("ambush_started", false))
	var saved_beacon: Array = progress_data.get("beacon_direction", [0.0, 0.0, 0.0])
	session.progress.beacon_direction = _array_to_vector(saved_beacon)
	if data.has("crew"): # older saves have none: keep whoever the game started with
		session.crew.restore(session.systems, data["crew"])
	session.inventory.restore(data.get("inventory", {"oxygen_tank": 1, "repair_kit": 1}))
	return ""


static func _vector_to_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]


static func _array_to_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _quaternion_to_array(quaternion: Quaternion) -> Array:
	return [quaternion.x, quaternion.y, quaternion.z, quaternion.w]


static func _array_to_quaternion(values: Array) -> Quaternion:
	return Quaternion(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
