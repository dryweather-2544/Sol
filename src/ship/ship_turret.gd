class_name ShipTurret
extends RefCounted
## The dorsal gun, the ship's main gun (Pulsar-style: a mounted turret, not a nose gun). The pilot's fire button shoots it
## along the nose, closing on the crosshair; whenever the pilot is not firing, a crewman in the gunner seat aims it
## on their own at the nearest hostile in range (leading a moving target). Fires through the shared ProjectileSim and
## is powered by the weapons conduit.
## Pure logic. Aim is kept ship-local too so the visual barrel can follow it.

var weapon := Weapon.ship_gun()
## The pilot's shots cross this far ahead of the nose, so a burst closes on the reticle (the camera looks along the nose).
const CONVERGENCE := 600.0
## The barrel's pivot on the barbette (matches ShipExterior.TURRET_PIVOT_Y); shots leave from the barrel tip, BARREL_LENGTH along the aim.
var muzzle_offset := Vector3(0, 2.7, 4.5)
const BARREL_LENGTH := 1.95
var fire_range := 1100.0
## Radians of random error on each shot; the gunner is good but not perfect.
var aim_error := 0.02
var target: ProjectileSim.Target
## Ship-local direction the barrel points (for the visual); the nose direction when idle.
var aim_local := Vector3(0, 0, -1)
var firing := false
## Gunner-station state (the player on the gun): free aim inside the arc, heat that forces a cool-down.
const PITCH_MIN := deg_to_rad(-60.0)
const PITCH_MAX := deg_to_rad(85.0)
const AIM_SENSITIVITY := 0.0022
const HEAT_PER_SHOT := 0.03
const COOL_PER_SECOND := 0.25
const OVERHEAT_RECOVER := 0.4
var aim_yaw := 0.0
var aim_pitch := 0.0
var heat := 0.0
var overheated := false
var _rng := SeedRng.new(41)


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


## The pilot's trigger: one shot from the roof gun along the nose, angled to close on the crosshair.
func fire_at_crosshair(ship: Ship, power_factor: float, projectiles: ProjectileSim, damage_multiplier: float = 1.0) -> bool:
	if power_factor <= 0.0 or ship.state.hull <= 0.0:
		return false
	var local_aim := (Vector3(0.0, 0.0, -CONVERGENCE) - muzzle_offset).normalized()
	var muzzle := _tip(ship, local_aim)
	var base_damage := weapon.damage
	weapon.damage = base_damage * damage_multiplier
	var fired := weapon.try_fire(projectiles, muzzle, ship.state.basis * local_aim, ship.state.velocity, ship.team_id, ship, power_factor)
	weapon.damage = base_damage
	if fired:
		aim_local = local_aim
	return fired


func update(delta: float, ship: Ship, targets: Array, manned: bool, power_factor: float, projectiles: ProjectileSim, pilot_fire: bool = false, damage_multiplier: float = 1.0) -> void:
	weapon.update(delta)
	firing = false
	target = null
	if pilot_fire:
		firing = fire_at_crosshair(ship, power_factor, projectiles, damage_multiplier)
		return # the pilot has the trigger: the gunner holds fire
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
	muzzle = _tip(ship, aim_local)
	firing = weapon.try_fire(projectiles, muzzle, aim, ship.state.velocity, ship.team_id, ship, power_factor)


## Mouse motion in pixels moves the barrel; yaw is free all round (the gun is on the roof), pitch is limited.
func add_aim(relative: Vector2) -> void:
	aim_yaw = wrapf(aim_yaw - relative.x * AIM_SENSITIVITY, -PI, PI)
	aim_pitch = clampf(aim_pitch - relative.y * AIM_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	aim_local = manual_direction()


## Ship-local direction for the current yaw and pitch (0 yaw = the nose).
func manual_direction() -> Vector3:
	return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch)).normalized()


## The player's turn on the gun: fires along the aimed direction while the trigger is held and the barrel is not overheated.
func update_manual(delta: float, ship: Ship, power_factor: float, projectiles: ProjectileSim, trigger: bool, damage_multiplier: float = 1.0) -> void:
	weapon.update(delta)
	firing = false
	target = null
	heat = maxf(0.0, heat - COOL_PER_SECOND * delta)
	if overheated and heat <= OVERHEAT_RECOVER:
		overheated = false
	aim_local = manual_direction()
	if not trigger or overheated or power_factor <= 0.0 or ship.state.hull <= 0.0:
		return
	var muzzle := _tip(ship, aim_local)
	var base_damage := weapon.damage
	weapon.damage = base_damage * damage_multiplier
	firing = weapon.try_fire(projectiles, muzzle, ship.state.basis * aim_local, ship.state.velocity, ship.team_id, ship, power_factor)
	weapon.damage = base_damage
	if firing:
		heat = minf(1.0, heat + HEAT_PER_SHOT)
		if heat >= 1.0:
			overheated = true


## World position of the barrel tip for a ship-local aim direction.
func _tip(ship: Ship, local_aim: Vector3) -> WorldPos:
	return ship.state.position.offset_by(ship.state.basis * (muzzle_offset + local_aim * BARREL_LENGTH))
