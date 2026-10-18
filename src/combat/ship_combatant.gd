class_name ShipCombatant
extends ProjectileSim.Target
## Makes a Ship shootable: hull damage, a hit radius, and a team.

var ship: Ship
var team := 0
var radius := 9.0


func _init(target_ship: Ship, team_id_value: int, hit_radius: float = 9.0) -> void:
	ship = target_ship
	team = team_id_value
	radius = hit_radius


func combat_position() -> WorldPos:
	return ship.state.position


func combat_radius() -> float:
	return radius


func combat_velocity() -> Vector3:
	return ship.state.velocity


func team_id() -> int:
	return team


func apply_damage(amount: float, source: Object) -> void:
	if ship.state.hull <= 0.0:
		return
	if ship.systems != null:
		ship.systems.take_ambush_hit()
		var subsystems := ship.systems.subsystems
		var struck := subsystems.next_round_robin()
		if source is Ship:
			var to_attacker := ((source as Ship).state.position.vector_from(ship.state.position)).normalized()
			struck = ShipSubsystems.subsystem_for_direction(ship.state.basis.transposed() * to_attacker)
		ship.systems.damage_subsystem(struck, amount)
	ship.state.hull = maxf(0.0, ship.state.hull - amount)
	if ship.state.hull <= 0.0:
		ship.destroyed.emit()


func is_alive() -> bool:
	return ship.state.hull > 0.0
