class_name Weapon
extends RefCounted
## A gun: fire rate, projectile speed and damage. Used by ships (fired through PilotCommand.fire) and by
## people on foot. Pure logic: it spawns projectiles into a ProjectileSim.

var shots_per_second := 6.0
var projectile_speed := 900.0
var damage := 0.05
var projectile_lifetime := 3.0
var shots_fired := 0 ## observer only: the audio service plays a shot sound whenever this goes up
var _cooldown := 0.0


static func ship_gun() -> Weapon:
	var weapon := Weapon.new()
	# Rodina's ship blaster (EGWeaponBlaster): 10 000 m/s plasma fired in a rapid stream (scout cooldown 0.025 s, two
	# barrels), 2 s lifetime. Sol fires 20 a second alternating its two barrels, with the old gun's damage per second.
	weapon.projectile_speed = 10000.0
	weapon.projectile_lifetime = 1.0
	weapon.shots_per_second = 20.0
	weapon.damage = 0.015
	return weapon


static func pistol() -> Weapon:
	var weapon := Weapon.new()
	weapon.shots_per_second = 2.5
	weapon.projectile_speed = 160.0
	weapon.damage = 0.34
	weapon.projectile_lifetime = 1.5
	return weapon


func update(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


## Fire if ready. direction must be a unit vector in the planet frame; muzzle_velocity_base is the
## shooter's own velocity (added so shots inherit it). Returns true if a shot was spawned.
func try_fire(sim: ProjectileSim, muzzle: WorldPos, direction: Vector3, shooter_velocity: Vector3, team: int, source: Object, rate_scale: float = 1.0) -> bool:
	if _cooldown > 0.0 or rate_scale <= 0.0:
		return false
	_cooldown = 1.0 / (shots_per_second * rate_scale)
	sim.spawn(muzzle, direction * projectile_speed + shooter_velocity, team, damage, source, projectile_lifetime)
	shots_fired += 1
	return true
