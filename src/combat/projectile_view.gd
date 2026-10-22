class_name ProjectileView
extends Node3D
## Draws the projectiles of a ProjectileSim. Reads only.
##
## Each shot is a white-hot bolt: a long thin bright core with a faint warm glow around it, stretched along its flight path.
## No flare, smoke or trail.

const MAX_PROJECTILES := 400
const BOLT_LENGTH := 16.0 # metres
const CORE_WIDTH := 0.4
const GLOW_WIDTH := 1.1
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const GLOW_COLOR := Color(1.0, 0.82, 0.55, 0.28)

var sim: ProjectileSim
var render_origin := WorldPos.new(&"planet")
var _core := MultiMesh.new()
var _glow := MultiMesh.new()


func _init() -> void:
	name = "ProjectileView"
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = CORE_COLOR
	core_material.emission_enabled = true
	core_material.emission = CORE_COLOR
	core_material.emission_energy_multiplier = 3.0 # hot enough to bloom where the environment glows
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.albedo_color = GLOW_COLOR
	glow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_add_layer(_core, core_material)
	_add_layer(_glow, glow_material)


func _add_layer(multimesh: MultiMesh, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	box.material = material
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = MAX_PROJECTILES
	multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3.ONE * -1.0e5, Vector3.ONE * 2.0e5)
	add_child(instance)


func _ready() -> void:
	add_to_group("origin_shift")


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func _process(_delta: float) -> void:
	var count := mini(sim.projectiles.size(), MAX_PROJECTILES)
	var used := 0
	for index in count:
		var projectile := sim.projectiles[index]
		var speed := projectile.velocity.length()
		if speed < 0.01:
			continue
		var direction := projectile.velocity / speed
		var up_hint := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var axis_x := up_hint.cross(direction).normalized()
		var axis_y := direction.cross(axis_x)
		var origin := projectile.position.to_local_vector3(render_origin)
		# The bolt never reaches back past the barrel it left (it grows out of the muzzle), so nothing is drawn inside the ship.
		var length := minf(BOLT_LENGTH, speed * projectile.age)
		if length < 1.0:
			continue
		# Centred half a bolt behind the shot's position, so the bright end leads.
		var centre := origin - direction * (length * 0.5)
		_core.set_instance_transform(used, Transform3D(Basis(axis_x * CORE_WIDTH, axis_y * CORE_WIDTH, direction * length), centre))
		_glow.set_instance_transform(used, Transform3D(Basis(axis_x * GLOW_WIDTH, axis_y * GLOW_WIDTH, direction * length * 1.1), centre))
		used += 1
	_core.visible_instance_count = used
	_glow.visible_instance_count = used
