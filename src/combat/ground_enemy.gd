class_name GroundEnemy
extends RefCounted
## A hostile walking drone. Pure logic: it idles until the player comes within AGGRO_RANGE, then
## walks toward them over the real terrain (same OnFootBody as the player, so it follows slopes and
## cannot fall through the ground), stops at keep-off range and shoots projectiles (team 1).

const AGGRO_RANGE := 90.0
const KEEP_DISTANCE := 22.0
const FIRE_RANGE := 45.0
const WALK_SPEED_FRACTION := 0.7

var body := OnFootBody.new()
var health := 1.0
var team := 1
var weapon := Weapon.new()
var home: WorldPos
var _rng: SeedRng


func _init(planet: PlanetBody, spawn_position: WorldPos, seed_value: int) -> void:
	home = spawn_position
	_rng = SeedRng.new(seed_value)
	body.place_on_ground(planet, spawn_position, Vector3(1, 0, 0))
	weapon.shots_per_second = 0.9
	weapon.projectile_speed = 110.0
	weapon.damage = 0.09
	weapon.projectile_lifetime = 1.5


func is_alive() -> bool:
	return health > 0.0


func step(delta: float, player_position: WorldPos, planet: PlanetBody, projectiles: ProjectileSim) -> void:
	if not is_alive():
		return
	weapon.update(delta)
	var to_player := player_position.vector_from(body.position)
	var up := planet.up_at(body.position)
	var flat := to_player - up * to_player.dot(up)
	var distance := flat.length()
	var command := OnFootCommand.new()
	if distance < AGGRO_RANGE and distance > 0.01:
		body.heading = flat.normalized()
		if distance > KEEP_DISTANCE:
			command.move = Vector2(0, WALK_SPEED_FRACTION)
		if distance < FIRE_RANGE:
			_shoot(player_position, to_player, projectiles)
	body.step(command, planet, delta)


func _shoot(player_position: WorldPos, to_player: Vector3, projectiles: ProjectileSim) -> void:
	var distance := to_player.length()
	var spread := Vector3(_rng.next_float() - 0.5, _rng.next_float() - 0.5, _rng.next_float() - 0.5) * 0.07 * distance
	var direction := (to_player + spread).normalized()
	var muzzle := body.position.offset_by(Vector3(body.position.x, body.position.y, body.position.z).normalized() * 1.2)
	weapon.try_fire(projectiles, muzzle, direction, Vector3.ZERO, team, self)
