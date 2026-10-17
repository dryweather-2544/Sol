class_name SaveGame
extends RefCounted
## Turns the live game into plain data and back. Save *state*, not scenes (research 08 §8.3):
## positions are WorldPos (frame + doubles), doors and walkway by authored id. Everything
## written is JSON-safe (numbers, strings, bools, arrays, dictionaries).

const SAVE_VERSION := 4
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
		},
		"interior": {
			"portals": portals,
			"walkway": {"state": systems.walkway.state, "progress": systems.walkway.progress},
			"ramp_end_y": systems.layout.ramp_end_y,
		},
		"player": {
			"mode": saved_mode,
			"interior_position": _vector_to_array(interior_position),
			"interior_yaw": session.interior_body.yaw,
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
		},
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

	var systems := session.systems
	var interior_data: Dictionary = data["interior"]
	for portal_key in interior_data["portals"]:
		var portal: Portal = systems.layout.portals[StringName(portal_key)]
		portal.target_open = bool(interior_data["portals"][portal_key]["target_open"])
		portal.open_factor = float(interior_data["portals"][portal_key]["open_factor"])
	systems.walkway.state = int(interior_data["walkway"]["state"])
	systems.walkway.progress = float(interior_data["walkway"]["progress"])
	systems.walkway.occupied = false
	systems.layout.ramp_end_y = float(interior_data["ramp_end_y"])
	systems.layout.ramp_walkable = systems.walkway.is_deployed()
	systems.airlock.reset_cycle()
	systems.reset_pending_actions()

	var player_data: Dictionary = data["player"]
	var mode := int(player_data["mode"])
	var exterior: Dictionary = player_data["exterior"]
	session.interior_body.place(_array_to_vector(player_data["interior_position"]), float(player_data["interior_yaw"]))
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
	session.restore_mode(mode)
	var poi_data: Dictionary = data.get("pois", {})
	session.discovery_log.restore(poi_data.get("discovered", []))
	return ""


static func _vector_to_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]


static func _array_to_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _quaternion_to_array(quaternion: Quaternion) -> Array:
	return [quaternion.x, quaternion.y, quaternion.z, quaternion.w]


static func _array_to_quaternion(values: Array) -> Quaternion:
	return Quaternion(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
