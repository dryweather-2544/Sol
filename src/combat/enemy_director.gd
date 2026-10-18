class_name EnemyDirector
extends Node
## Spawns and removes the guards of outposts as the player approaches. Guards (two hostile ships
## hovering over the pad and two ground drones) exist only while the outpost is in the content ring,
## and only until they are destroyed: clearing an outpost is saved and it stays clear. Ships fly
## through the same AIPilotSource/PilotCommand as the player; drones use the player's walking body.

const SHIP_ALERT_RANGE := 1500.0
const SHIPS_PER_OUTPOST := 2
const DRONES_PER_OUTPOST := 2
const UPDATE_INTERVAL_SECONDS := 0.5

var session: GameSession
var planet: PlanetBody
var poi_manager: PoiManager
var render_origin := WorldPos.new(&"planet")

class Encounter extends RefCounted:
	var poi: PoiInstance
	var ships: Array[Ship] = []
	var drones: Array[GroundEnemy] = []
	var drone_nodes: Array[MeshInstance3D] = []
	var targets: Array = []


var _encounters := {} # poi id -> Encounter
var _seconds := UPDATE_INTERVAL_SECONDS


func _ready() -> void:
	add_to_group("origin_shift")


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func active_encounter_count() -> int:
	return _encounters.size()


func _physics_process(delta: float) -> void:
	if session == null or planet == null:
		return
	var player_position := session.player_world_position()
	for encounter in _encounters.values():
		for drone_index in encounter.drones.size():
			var drone: GroundEnemy = encounter.drones[drone_index]
			drone.step(delta, player_position, planet, session.projectiles)
			var node: MeshInstance3D = encounter.drone_nodes[drone_index]
			node.visible = drone.is_alive()
			node.position = drone.body.position.to_local_vector3(render_origin) + drone.body.position_up_offset(0.9)
	_seconds += delta
	if _seconds >= UPDATE_INTERVAL_SECONDS:
		_seconds = 0.0
		_refresh(player_position)


func clear_all() -> void:
	for poi_id in _encounters.keys():
		_remove_encounter(poi_id)
	session.enemy_targets.clear()
	session.projectiles.clear()


func _refresh(player_position: WorldPos) -> void:
	for instance in poi_manager.known_instances():
		if instance.type != PoiDefinition.Type.OUTPOST or session.cleared_log.is_cleared(instance.id):
			continue
		var distance := instance.position.distance_to(player_position)
		if distance < PoiRings.CONTENT_ENTER and not _encounters.has(instance.id):
			_spawn(instance)
	for poi_id in _encounters.keys():
		var encounter: Encounter = _encounters[poi_id]
		if encounter.poi == null: # the scripted ambush: gone once the raider is dead
			if encounter.ships[0].state.hull <= 0.0:
				_remove_encounter(poi_id)
			continue
		if encounter.poi.position.distance_to(player_position) > PoiRings.CONTENT_EXIT:
			_remove_encounter(poi_id)
			continue
		var anyone_alive := false
		for ship in encounter.ships:
			anyone_alive = anyone_alive or ship.state.hull > 0.0
		for drone in encounter.drones:
			anyone_alive = anyone_alive or drone.is_alive()
		if not anyone_alive:
			session.cleared_log.mark_looted(encounter.poi.id)
			session.inventory.add(ItemDefinition.SCRAP, 4)
			var found_coil := session.inventory.count(ItemDefinition.WARP_COIL) == 0 and not session.progress.warp_installed and session.inventory.add(ItemDefinition.WARP_COIL, 1)
			session.say("Outpost cleared - salvaged 4 scrap%s" % (" and a WARP COIL" if found_coil else ""))
			_remove_encounter(poi_id)


func _spawn(instance: PoiInstance) -> void:
	var encounter := Encounter.new()
	encounter.poi = instance
	var rng := SeedRng.new(SeedHash.combine(instance.seed_value, SeedHash.string_hash("guards")))
	var frame := PoiBuilder.frame_basis(instance)
	for ship_index in SHIPS_PER_OUTPOST:
		var hover_position := instance.position.offset_by(frame.y * 140.0 + frame.x * (ship_index * 60.0 - 30.0) + frame.z * 40.0)
		var ship := _make_hostile_ship("Guard%d" % ship_index, hover_position, Basis.looking_at(frame.x, frame.y), func():
			var player_position := session.player_world_position()
			return player_position if player_position.distance_to(hover_position) < SHIP_ALERT_RANGE else instance.position.offset_by(frame.y * 140.0))
		ship.destroyed.connect(func(): session.say("Guard ship destroyed"))
		add_child(ship)
		encounter.ships.append(ship)
		encounter.targets.append(ShipCombatant.new(ship, 1))
	for drone_index in DRONES_PER_OUTPOST:
		var angle := rng.next_float() * TAU
		var drone_position := instance.position.offset_by(frame.x * cos(angle) * 12.0 + frame.z * sin(angle) * 12.0)
		var drone := GroundEnemy.new(planet, drone_position, rng.next_u32())
		encounter.drones.append(drone)
		encounter.targets.append(CombatTargets.GroundEnemyTarget.new(drone))
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.45
		mesh.height = 1.8
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.15, 0.1)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.2, 0.1)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		add_child(node)
		encounter.drone_nodes.append(node)
	session.enemy_targets.append_array(encounter.targets)
	_encounters[instance.id] = encounter


## A hostile ship flown by an AIPilotSource that attacks whatever target_provider returns (not yet added to the tree).
func _make_hostile_ship(ship_name: String, hover_position: WorldPos, facing: Basis, target_provider: Callable) -> Ship:
	var ship := Ship.new()
	ship.name = ship_name
	ship.planet = planet
	ship.team_id = 1
	ship.hull_color = Color(0.75, 0.15, 0.12)
	ship.weapon.damage = 0.012 # hostiles are a nuisance, not an instant kill
	ship.weapon.shots_per_second = 4.0
	ship.projectiles = session.projectiles
	ship.state.position = hover_position
	ship.state.basis = facing
	ship.render_origin = render_origin.duplicate_position()
	var ai := AIPilotSource.new(AIPilotSource.Mode.ATTACK)
	ai.target_provider = target_provider
	ai.target_velocity_provider = func(): return session.ship.state.velocity if session.mode != GameSession.Mode.OUTSIDE else session.exterior_body.velocity
	ship.controller.request_control(ai, &"hostile_ai")
	return ship


## The Mayday ambush: one raider comes in from ahead and above the player's ship and attacks it.
func spawn_ambush() -> void:
	var player_ship := session.ship.state
	var start := player_ship.position.offset_by(-player_ship.basis.z * 800.0 + player_ship.basis.y * 150.0)
	var raider := _make_hostile_ship("Raider", start, Basis.looking_at(player_ship.basis.z, player_ship.basis.y), func(): return session.ship.state.position)
	raider.destroyed.connect(func(): session.say("Raider destroyed"))
	add_child(raider)
	var encounter := Encounter.new()
	encounter.poi = null
	encounter.ships.append(raider)
	encounter.targets.append(ShipCombatant.new(raider, 1))
	session.enemy_targets.append_array(encounter.targets)
	_encounters[&"ambush"] = encounter


func _remove_encounter(poi_id: StringName) -> void:
	var encounter: Encounter = _encounters[poi_id]
	for target in encounter.targets:
		session.enemy_targets.erase(target)
	for ship in encounter.ships:
		ship.queue_free()
	for node in encounter.drone_nodes:
		node.queue_free()
	_encounters.erase(poi_id)
