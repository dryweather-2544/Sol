class_name ProjectileView
extends Node3D
## Draws the projectiles of a ProjectileSim. Reads only.
##
## Rodina's ship blaster is a fast plasma bolt fired in a rapid stream from two barrels, with a muzzle flare (EGVehicle
## FireWeapon, EGWeaponBlaster). Matched to the owner's footage, drawn from hard-edged warm-white squares: the bolt is a
## bright square with a couple of specks, and each shot throws a small spray of squares forward from its barrel that
## stays where it was thrown while the ship flies on, so a burst of fire leaves a streak behind the ship.

const HEAD_SIZES: Array[float] = [2.2, 0.8, 0.6] # metres: the bolt and two specks riding it
const MAX_PROJECTILES := 300
const FLARE_SQUARES := 16 # per shot
const FLARE_LIFE := 0.35 # seconds
const FLARE_SIZES: Array[float] = [0.6, 0.4, 0.3, 0.2, 0.15, 0.1]
const FLARE_REACH := 7.0 # metres the spray reaches ahead of the barrel
const FLARE_CONE := 0.25 # metres of sideways scatter per metre of reach
const MAX_FLARE := 2500
const COLOR := Color(1.0, 0.96, 0.82)

class Square extends RefCounted:
	var position: WorldPos
	var size: float
	var born: float

var sim: ProjectileSim
var render_origin := WorldPos.new(&"planet")
var _multimesh := MultiMesh.new()
var _instance := MultiMeshInstance3D.new()
var _clock := 0.0
var _flare: Array[Square] = [] # oldest first
var _seen := {} # projectile id -> true once its muzzle flare was thrown
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "ProjectileView"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	quad.material = material
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_PROJECTILES * HEAD_SIZES.size() + MAX_FLARE
	_multimesh.visible_instance_count = 0
	_instance.multimesh = _multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = AABB(Vector3.ONE * -1.0e5, Vector3.ONE * 2.0e5)
	add_child(_instance)
	_rng.seed = 7


func _ready() -> void:
	add_to_group("origin_shift")


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func _process(delta: float) -> void:
	_clock += delta
	var count := mini(sim.projectiles.size(), MAX_PROJECTILES)
	var live := {}
	for index in count:
		var projectile := sim.projectiles[index]
		var id := projectile.get_instance_id()
		live[id] = true
		if not _seen.has(id):
			_seen[id] = true
			_throw_flare(projectile)
	for id in _seen.keys():
		if not live.has(id):
			_seen.erase(id)
	while not _flare.is_empty() and _clock - _flare[0].born > FLARE_LIFE:
		_flare.pop_front()
	while _flare.size() > MAX_FLARE:
		_flare.pop_front()
	var used := 0
	for index in count:
		var projectile := sim.projectiles[index]
		var origin := projectile.position.to_local_vector3(render_origin)
		var rng := RandomNumberGenerator.new()
		rng.seed = projectile.get_instance_id()
		for square in HEAD_SIZES.size():
			var edge := HEAD_SIZES[square]
			var jitter := Vector3.ZERO if square == 0 else Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			_multimesh.set_instance_transform(used, Transform3D(Basis.from_scale(Vector3(edge, edge, edge)), origin + jitter))
			used += 1
	for square in _flare:
		var fade := 1.0 - (_clock - square.born) / FLARE_LIFE
		var edge := square.size * clampf(fade, 0.0, 1.0)
		_multimesh.set_instance_transform(used, Transform3D(Basis.from_scale(Vector3(edge, edge, edge)), square.position.to_local_vector3(render_origin)))
		used += 1
	_multimesh.visible_instance_count = used


## The muzzle flare: a spray of squares thrown forward from where the shot left its barrel.
func _throw_flare(projectile: ProjectileSim.Projectile) -> void:
	var speed := projectile.velocity.length()
	if speed < 0.01:
		return
	var direction := projectile.velocity / speed
	# The sim has already moved the shot once this tick: step back to the barrel.
	var barrel := projectile.position.offset_by(-projectile.velocity * projectile.age)
	var up_hint := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var side := direction.cross(up_hint).normalized()
	var lift := side.cross(direction)
	for index in FLARE_SQUARES:
		var reach := _rng.randf() * FLARE_REACH
		var spread := reach * FLARE_CONE + 0.1
		var square := Square.new()
		square.position = barrel.offset_by(direction * reach + side * _rng.randf_range(-spread, spread) + lift * _rng.randf_range(-spread, spread))
		square.size = FLARE_SIZES[_rng.randi() % FLARE_SIZES.size()]
		square.born = _clock
		_flare.append(square)
