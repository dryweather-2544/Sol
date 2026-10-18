class_name ProjectileSim
extends RefCounted
## Projectiles and who they can hit. Every weapon spawns projectiles (no hitscan, research ITM-05) and
## every projectile carries a team_id: it only hurts targets on a different team (research ITM-06 notes
## Rodina's check is "player versus everyone"). Positions are 64-bit WorldPos. Pure logic.

class Projectile extends RefCounted:
	var position: WorldPos
	var velocity: Vector3
	var team_id: int
	var damage: float
	var age := 0.0
	var max_age := 3.0
	var source: Object


## Anything that can be shot. Implement these four.
class Target extends RefCounted:
	func combat_position() -> WorldPos:
		return null

	func combat_radius() -> float:
		return 1.0

	## Planet-frame velocity, for lead aiming (zero for things that stand still).
	func combat_velocity() -> Vector3:
		return Vector3.ZERO

	func team_id() -> int:
		return 0

	func apply_damage(_amount: float, _source: Object) -> void:
		pass

	func is_alive() -> bool:
		return true


signal hit(projectile: Projectile, target: Target)

var projectiles: Array[Projectile] = []


func spawn(from_position: WorldPos, velocity: Vector3, team: int, damage: float, source: Object = null, max_age: float = 3.0) -> Projectile:
	var projectile := Projectile.new()
	projectile.position = from_position.duplicate_position()
	projectile.velocity = velocity
	projectile.team_id = team
	projectile.damage = damage
	projectile.source = source
	projectile.max_age = max_age
	projectiles.append(projectile)
	return projectile


func clear() -> void:
	projectiles.clear()


## Move everything one tick; returns the number of hits (each projectile hits at most one target).
func step(delta: float, targets: Array) -> int:
	var hits := 0
	var survivors: Array[Projectile] = []
	for projectile in projectiles:
		var start := projectile.position.duplicate_position()
		projectile.position = projectile.position.offset_by(projectile.velocity * delta)
		projectile.age += delta
		var struck: Target = null
		var struck_fraction := 2.0
		for target in targets:
			if not target.is_alive() or target.team_id() == projectile.team_id:
				continue
			var fraction := _segment_hits_sphere(start, projectile.position, target.combat_position(), target.combat_radius())
			if fraction >= 0.0 and fraction < struck_fraction:
				struck = target
				struck_fraction = fraction
		if struck != null:
			struck.apply_damage(projectile.damage, projectile.source)
			hit.emit(projectile, struck)
			hits += 1
		elif projectile.age < projectile.max_age:
			survivors.append(projectile)
	projectiles = survivors
	return hits


## Fraction (0..1) along the segment where it first enters the sphere, or -1 if it misses.
static func _segment_hits_sphere(start: WorldPos, end: WorldPos, center: WorldPos, radius: float) -> float:
	var segment := end.vector_from(start)
	var to_center := center.vector_from(start)
	var length_squared := segment.length_squared()
	if length_squared < 1e-12:
		return 0.0 if to_center.length() <= radius else -1.0
	var along := clampf(to_center.dot(segment) / length_squared, 0.0, 1.0)
	var closest_distance := (segment * along - to_center).length()
	if closest_distance > radius:
		return -1.0
	var back := sqrt(maxf(radius * radius - closest_distance * closest_distance, 0.0)) / sqrt(length_squared)
	return maxf(along - back, 0.0)
