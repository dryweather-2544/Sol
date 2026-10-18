class_name ShipCrew
extends RefCounted
## The AI crew aboard: walks them between stations, opens doors on the way, sits them in seats. They never
## teleport and never leave the ship (they are ship-local, so flight, landing and frame changes cannot move them).
## Doors and seats are used through the same ShipSystems calls the player uses, so a person in a doorway keeps
## a door open and one seat has one occupant. Behaviour that *chooses* stations is CrewBrain (N6).

const ARRIVE_DISTANCE := 0.2
const DOOR_OPEN_DISTANCE := 1.3
const GIVE_UP_SECONDS := 6.0
const DOOR_RETRY_SECONDS := 1.0

var members: Array[CrewMember] = []


func member(member_id: StringName) -> CrewMember:
	for candidate in members:
		if candidate.id == member_id:
			return candidate
	return null


## Puts a person at a station (seated if it is a seat) without walking, for starting a game or restoring a save.
func add_member(systems: ShipSystems, member_id: StringName, role: StringName, station_id: StringName) -> CrewMember:
	var person := CrewMember.new(member_id, role)
	var layout := systems.layout
	if layout.seats.has(station_id):
		var seat: Dictionary = layout.seats[station_id]
		person.body.place(seat["position"], seat["facing_yaw"])
		if systems.seats.try_sit(member_id, station_id):
			person.seat_id = station_id
	else:
		var spot := layout.standing_spot_for(station_id)
		person.body.place(Vector3(spot.x, layout.floor_y, spot.y), PI if station_id == &"reactor_panel" else 0.0)
	person.station_id = station_id
	members.append(person)
	return person


## Send a person to a station. Returns "" or why not.
func order_to_station(systems: ShipSystems, member_id: StringName, station_id: StringName) -> String:
	var person := member(member_id)
	if person == null:
		return "no such crew member"
	var layout := systems.layout
	var target := Vector2.INF
	if layout.seats.has(station_id):
		var seat: Dictionary = layout.seats[station_id]
		if systems.seats.occupant_of(station_id) != &"" and systems.seats.occupant_of(station_id) != member_id:
			return "seat is taken"
		target = Vector2(seat["exit_position"].x, seat["exit_position"].z)
	else:
		target = layout.standing_spot_for(station_id)
	if target == Vector2.INF:
		return "no such station"
	if person.seat_id == station_id:
		return "" # already sitting there
	if person.seat_id != &"":
		systems.seats.stand(member_id)
		systems.seats.cancel_sit(member_id)
		var seat: Dictionary = layout.seats[person.seat_id]
		person.body.place(seat["exit_position"], person.body.yaw)
		person.seat_id = &""
	return _send(systems, person, target, station_id)


## Send a person to any floor spot (ship-local x, z), not a station. Returns "" or why not.
func order_to_spot(systems: ShipSystems, member_id: StringName, spot: Vector2) -> String:
	var person := member(member_id)
	if person == null:
		return "no such crew member"
	if person.seat_id != &"":
		systems.seats.stand(member_id)
		var seat: Dictionary = systems.layout.seats[person.seat_id]
		person.body.place(seat["exit_position"], person.body.yaw)
		person.seat_id = &""
	return _send(systems, person, spot, &"")


func _send(systems: ShipSystems, person: CrewMember, target: Vector2, station_id: StringName) -> String:
	var layout := systems.layout
	var here := Vector2(person.body.position.x, person.body.position.z)
	var route := CrewNavigator.route(layout, here, target)
	if route.is_empty() and CrewNavigator.room_near(layout, here) != CrewNavigator.room_near(layout, target):
		return "no route"
	person.path = route
	person.station_id = station_id
	person.arrived = false
	person.blocked_seconds = 0.0
	return ""


func update(delta: float, systems: ShipSystems) -> void:
	for person in members:
		_update_person(person, delta, systems)


## Marks every doorway a crew member is standing in, so the door cannot close on them.
func mark_occupied(systems: ShipSystems) -> void:
	for person in members:
		for portal_id in systems.layout.portals:
			var portal: Portal = systems.layout.portals[portal_id]
			if portal.opening.grow(0.5).has_point(Vector2(person.body.position.x, person.body.position.z)):
				systems.occupied_portals[portal_id] = true


func _update_person(person: CrewMember, delta: float, systems: ShipSystems) -> void:
	person.door_cooldown = maxf(0.0, person.door_cooldown - delta)
	if person.seat_id != &"":
		person.speed = 0.0
		return
	var layout := systems.layout
	if person.path.is_empty():
		person.speed = 0.0
		if not person.arrived:
			_arrive(person, systems)
		return
	var here := Vector2(person.body.position.x, person.body.position.z)
	var waypoint: Dictionary = person.path[0]
	var target: Vector2 = waypoint["position"]
	var door_id: StringName = waypoint["door"]
	var distance := here.distance_to(target)
	if door_id != &"":
		var portal: Portal = layout.portals[door_id]
		if distance < DOOR_OPEN_DISTANCE and not portal.target_open and person.door_cooldown <= 0.0:
			systems.toggle_door(door_id)
			person.door_cooldown = DOOR_RETRY_SECONDS
		if distance < ARRIVE_DISTANCE * 2.0 and not portal.is_passable():
			person.speed = 0.0 # wait at the door until it has opened
			return
	if distance < ARRIVE_DISTANCE:
		person.path.pop_front()
		person.blocked_seconds = 0.0
		return
	var to_target := target - here
	person.body.yaw = atan2(-to_target.x, -to_target.y)
	var command := OnFootCommand.new()
	command.move = Vector2(0.0, 1.0)
	var before := person.body.position
	person.body.step(command, layout, delta)
	person.speed = before.distance_to(person.body.position) / maxf(delta, 1e-6)
	if person.speed < 0.2:
		person.blocked_seconds += delta
		if person.blocked_seconds > GIVE_UP_SECONDS:
			person.path.clear()
			person.arrived = true
	else:
		person.blocked_seconds = 0.0


func _arrive(person: CrewMember, systems: ShipSystems) -> void:
	person.arrived = true
	if systems.layout.seats.has(person.station_id):
		if systems.seats.try_sit(person.id, person.station_id):
			var seat: Dictionary = systems.layout.seats[person.station_id]
			person.seat_id = person.station_id
			person.body.place(seat["position"], seat["facing_yaw"])


func to_array() -> Array:
	var saved: Array = []
	for person in members:
		saved.append({"id": String(person.id), "role": String(person.role), "position": [person.body.position.x, person.body.position.y, person.body.position.z],
			"yaw": person.body.yaw, "seat": String(person.seat_id), "station": String(person.station_id), "charges": person.extinguisher_charges})
	return saved


func restore(systems: ShipSystems, saved: Array) -> void:
	members.clear()
	for entry in saved:
		var person := CrewMember.new(StringName(entry["id"]), StringName(entry["role"]))
		var position: Array = entry["position"]
		person.body.place(Vector3(float(position[0]), float(position[1]), float(position[2])), float(entry["yaw"]))
		person.station_id = StringName(entry["station"])
		person.extinguisher_charges = int(entry.get("charges", 0))
		var saved_seat := StringName(entry["seat"])
		if saved_seat != &"" and systems.seats.try_sit(person.id, saved_seat):
			person.seat_id = saved_seat
		if not systems.layout.is_position_walkable(person.body.position.x, person.body.position.z, 0.0) and person.seat_id == &"":
			var spot := systems.layout.standing_spot_for(person.station_id)
			if spot != Vector2.INF:
				person.body.place(Vector3(spot.x, systems.layout.floor_y, spot.y), person.body.yaw)
		members.append(person)
	systems.seats.update(SeatManager.SIT_SECONDS) # restored sitters are already sitting
