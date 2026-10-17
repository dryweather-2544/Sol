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


func team_id() -> int:
	return team


func apply_damage(amount: float, _source: Object) -> void:
	if ship.state.hull <= 0.0:
		return
	ship.state.hull = maxf(0.0, ship.state.hull - amount)
	if ship.state.hull <= 0.0:
		ship.destroyed.emit()


func is_alive() -> bool:
	return ship.state.hull > 0.0
