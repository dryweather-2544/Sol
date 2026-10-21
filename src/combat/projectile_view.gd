class_name ProjectileView
extends Node3D
## Draws the projectiles of a ProjectileSim as small glowing bolts. Reads only.

var sim: ProjectileSim
var render_origin := WorldPos.new(&"planet")
var _pool: Array[MeshInstance3D] = []
var _material := StandardMaterial3D.new()
var _mesh := BoxMesh.new()


func _init() -> void:
	name = "ProjectileView"
	_mesh.size = Vector3(0.3, 0.3, 4.0)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(1.0, 0.8, 0.3)
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.55, 0.1)
	_material.emission_energy_multiplier = 3.0


func _ready() -> void:
	add_to_group("origin_shift")


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func _process(_delta: float) -> void:
	var count := sim.projectiles.size()
	while _pool.size() < count:
		var node := MeshInstance3D.new()
		node.mesh = _mesh
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_pool.append(node)
	for index in _pool.size():
		var node := _pool[index]
		node.visible = index < count
		if index < count:
			var projectile := sim.projectiles[index]
			var direction := projectile.velocity.normalized() if projectile.velocity.length() > 0.01 else Vector3.FORWARD
			var up_hint := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			node.transform = Transform3D(Basis.looking_at(direction, up_hint), projectile.position.to_local_vector3(render_origin))
