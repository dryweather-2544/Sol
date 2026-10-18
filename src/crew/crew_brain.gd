class_name CrewBrain
extends RefCounted
## What the AI crew decide to do (research: PULSAR 10 §8, utility layer over simple actions). Every
## DECISION_SECONDS each person scores a short list of goals from a blackboard (fires, the worst damaged
## subsystem, reactor heat, hostiles) and commits to the best; the goal they already have gets a bonus so
## they do not flip-flop. A captain's order (from the player) outranks every score until it is done.
## Actions use the same ShipSystems requests the player uses. Pure logic.

enum Goal { IDLE, EXTINGUISH, REPAIR, POWER, FIGHT, ORDER_FIX, ORDER_TURRET }

const DECISION_SECONDS := 0.5
const COMMITMENT_BONUS := 15.0
const ORDER_SCORE := 1000.0
const CREW_REPAIR_PER_SECOND := 0.03
const REPAIR_BELOW := 0.7
const SPRAY_SECONDS := 1.2
const VENT_COOLDOWN_SECONDS := 8.0
const OVERHEAT := 0.8
const HOSTILE_RANGE := 1500.0
const PRESETS := {"balanced": [1.0, 1.0, 1.0], "engines": [1.0, 0.5, 1.0], "weapons": [0.6, 1.0, 1.0]}
const PRESET_ORDER := ["balanced", "engines", "weapons"]

var goals := {}        # member id -> Goal
var scores := {}       # member id -> score of the chosen goal
var orders := {}       # member id -> Goal (ORDER_*)
var goal_changes := {} # member id -> how many times the goal changed
var preset_index := 0
var _clock := 0.0
var _spray_clock := {}
var _vent_clock := 0.0
var _heading_for := {} # member id -> room being walked to (so the order is not re-sent every decision)


static func goal_name(goal: int) -> String:
	return ["idle", "extinguish", "repair", "reactor", "fight", "ORDER fix", "ORDER turret"][goal]


func update(delta: float, crew: ShipCrew, systems: ShipSystems, ship: Ship, targets: Array) -> void:
	_clock += delta
	_vent_clock = maxf(0.0, _vent_clock - delta)
	var decide := _clock >= DECISION_SECONDS
	if decide:
		_clock = 0.0
	var board := _blackboard(systems, ship, targets)
	for person in crew.members:
		if decide:
			_decide(person, board, crew, systems)
		_act(person, delta, crew, systems)


func _blackboard(systems: ShipSystems, ship: Ship, targets: Array) -> Dictionary:
	var hostile_close := false
	for candidate in targets:
		var enemy: ProjectileSim.Target = candidate
		if enemy.team_id() != ship.team_id and enemy.is_alive() and enemy.combat_position().vector_from(ship.state.position).length() < HOSTILE_RANGE:
			hostile_close = true
			break
	var worst := systems.subsystems.worst_id()
	return {"fires": systems.hazards.burning_rooms(), "worst_value": systems.subsystems.value(worst) / maxf(systems.subsystems.cap[worst], 0.01), "hostile": hostile_close,
		"reactor_needs_attention": (systems.power.is_shut_down() and systems.power.temperature < ShipPower.RESTART_BELOW_TEMPERATURE) \
			or (systems.power.temperature > OVERHEAT and systems.power.coolant >= ShipPower.COOLANT_PER_VENT)}


func _candidates(person: CrewMember, board: Dictionary, current: int) -> Dictionary:
	var scored := {Goal.IDLE: 10.0}
	match person.role:
		&"engineer":
			if not (board["fires"] as Array).is_empty():
				scored[Goal.EXTINGUISH] = 100.0
			if board["reactor_needs_attention"]:
				scored[Goal.POWER] = 70.0
			# Start repairing when something is badly damaged, and keep going until it is all fixed.
			if board["worst_value"] < (0.999 if current == Goal.REPAIR else REPAIR_BELOW):
				scored[Goal.REPAIR] = 60.0
		&"gunner":
			if board["hostile"]:
				scored[Goal.FIGHT] = 80.0
			elif not (board["fires"] as Array).is_empty():
				scored[Goal.EXTINGUISH] = 50.0
	if orders.has(person.id):
		scored[orders[person.id]] = ORDER_SCORE
	return scored


func _decide(person: CrewMember, board: Dictionary, crew: ShipCrew, systems: ShipSystems) -> void:
	var current: int = goals.get(person.id, -1)
	var scored := _candidates(person, board, current)
	var best_goal: int = Goal.IDLE
	var best_score := -INF
	for goal in scored:
		var score: float = scored[goal] + (COMMITMENT_BONUS if goal == current else 0.0)
		if score > best_score:
			best_score = score
			best_goal = goal
	scores[person.id] = scored[best_goal]
	if best_goal == current:
		return
	goals[person.id] = best_goal
	goal_changes[person.id] = goal_changes.get(person.id, 0) + 1
	_heading_for.erase(person.id)
	match best_goal:
		Goal.REPAIR, Goal.ORDER_FIX:
			crew.order_to_station(systems, person.id, &"engine_station")
		Goal.POWER:
			crew.order_to_station(systems, person.id, &"reactor_panel")
		Goal.FIGHT, Goal.ORDER_TURRET:
			crew.order_to_station(systems, person.id, &"gunner_seat")
		Goal.IDLE:
			crew.order_to_station(systems, person.id, &"gunner_seat" if person.role == &"gunner" else &"reactor_panel")


func _act(person: CrewMember, delta: float, crew: ShipCrew, systems: ShipSystems) -> void:
	var settled := person.path.is_empty() and person.arrived
	match goals.get(person.id, Goal.IDLE):
		Goal.EXTINGUISH:
			_fight_fire(person, delta, crew, systems, settled)
		Goal.REPAIR, Goal.ORDER_FIX:
			if settled and systems.layout.nearest_interaction(person.body.position) == &"engine_station":
				systems.subsystems.repair_worst(CREW_REPAIR_PER_SECOND * delta)
				if goals[person.id] == Goal.ORDER_FIX and systems.subsystems.is_undamaged():
					orders.erase(person.id)
		Goal.POWER:
			if settled and systems.layout.nearest_interaction(person.body.position) == &"reactor_panel":
				if systems.power.is_shut_down():
					systems.request_restart_reactor(person.id)
				elif systems.power.temperature > OVERHEAT and _vent_clock <= 0.0:
					if systems.request_vent_coolant(person.id) == "":
						_vent_clock = VENT_COOLDOWN_SECONDS


func _fight_fire(person: CrewMember, delta: float, crew: ShipCrew, systems: ShipSystems, settled: bool) -> void:
	var burning := systems.hazards.burning_rooms()
	if burning.is_empty():
		return
	if person.extinguisher_charges <= 0:
		if settled and systems.layout.nearest_interaction(person.body.position) == &"extinguisher_locker":
			person.extinguisher_charges = GameSession.EXTINGUISHER_CHARGES
		elif settled or _heading_for.get(person.id, &"") != &"locker":
			crew.order_to_station(systems, person.id, &"extinguisher_locker")
			_heading_for[person.id] = &"locker"
		return
	var room: StringName = burning[0]
	if systems.layout.room_at(person.body.position.x, person.body.position.z) != room:
		if _heading_for.get(person.id, &"") != room:
			var centre := (systems.layout.rooms[room] as Rect2).get_center()
			crew.order_to_spot(systems, person.id, centre)
			_heading_for[person.id] = room
		return
	_spray_clock[person.id] = _spray_clock.get(person.id, 0.0) - delta
	if _spray_clock[person.id] <= 0.0:
		_spray_clock[person.id] = SPRAY_SECONDS
		person.extinguisher_charges -= 1
		systems.hazards.extinguish(room, GameSession.EXTINGUISHER_STRENGTH)
	_heading_for.erase(person.id)


## Captain's orders (from the player's hotkeys). Pressing again cancels.
func toggle_order(role: StringName, goal: int, crew: ShipCrew) -> String:
	var ordered := false
	for person in crew.members:
		if person.role != role:
			continue
		if orders.get(person.id, -1) == goal:
			orders.erase(person.id)
		else:
			orders[person.id] = goal
			ordered = true
	return "Order given: " + goal_name(goal) if ordered else "Order cancelled"


## Cycles the reactor's power split through the presets, as the captain's call. Returns the preset name.
func cycle_power_preset(systems: ShipSystems, captain_id: StringName) -> String:
	preset_index = (preset_index + 1) % PRESET_ORDER.size()
	var preset_name: String = PRESET_ORDER[preset_index]
	var limits: Array = PRESETS[preset_name]
	for conduit in 3:
		systems.request_set_limit(captain_id, conduit, limits[conduit])
	return preset_name
