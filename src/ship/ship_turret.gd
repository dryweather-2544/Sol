class_name ShipTurret
extends RefCounted
## The dorsal gun, worked from the gunner seat. Aims on its own at the nearest hostile in range (leading a moving
## target) and fires through the shared ProjectileSim; the weapons conduit powers it like the ship's nose gun.
## Pure logic. Aim is kept ship-local too so the visual barrel can follow it.

var weapon := Weapon.ship_gun()
var muzzle_offset := Vector3(0, 1.9, 4.5)
var fire_range := 1100.0
## Radians of random error on each shot; the gunner is good but not perfect.
var aim_error := 0.02
var target: ProjectileSim.Target
## Ship-local direction the barrel points (for the visual); the nose direction when idle.
var aim_local := Vector3(0, 0, -1)
var firing := false
var _rng := SeedRng.new(41)


func _init() -> void:
	weapon.shots_per_second = 4.0
	weapon.damage = 0.04


## The nearest alive target on another team within range, or null.
func pick_target(ship: Ship, targets: Array) -> ProjectileSim.Target:
	var best: ProjectileSim.Target = null
	var best_distance := fire_range
	for candidate in targets:
		var enemy: ProjectileSim.Target = candidate
		if enemy.team_id() == ship.team_id or not enemy.is_alive():
			continue
		var distance := enemy.combat_position().vector_from(ship.state.position).length()
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


func update(delta: float, ship: Ship, targets: Array, manned: bool, power_factor: float, projectiles: ProjectileSim) -> void:
	weapon.update(delta)
	firing = false
	target = null
	if not manned or power_factor <= 0.0 or ship.state.hull <= 0.0:
		return
	target = pick_target(ship, targets)
	if target == null:
		return
	var muzzle := ship.state.position.offset_by(ship.state.basis * muzzle_offset)
	var offset := target.combat_position().vector_from(muzzle)
	var distance := maxf(offset.length(), 0.001)
	var relative_velocity := target.combat_velocity() - ship.state.velocity
	var aim := (offset + relative_velocity * (distance / weapon.projectile_speed)).normalized()
	aim = (aim + Vector3(_rng.next_float() - 0.5, _rng.next_float() - 0.5, _rng.next_float() - 0.5) * aim_error * 2.0).normalized()
	aim_local = ship.state.basis.transposed() * aim
	firing = weapon.try_fire(projectiles, muzzle, aim, ship.state.velocity, ship.team_id, ship, power_factor)
