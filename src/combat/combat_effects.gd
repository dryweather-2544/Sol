class_name CombatEffects
extends Node3D
## Short-lived impact flashes for projectile hits. The reference's combat frames use bright stepped
## sparks at the hit point; Sol previously removed the projectile silently. Fixed pool, no allocation
## per shot, and rendering-only (the simulation owns damage).

const POOL_SIZE := 16
const LIFE := 0.32

var render_origin := WorldPos.new(&"planet")
var _pool: Array[CPUParticles3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_times: Array[float] = []


func _ready() -> void:
	name = "CombatEffects"
	add_to_group("origin_shift")
	for index in POOL_SIZE:
		var flare := CPUParticles3D.new()
		flare.name = "Impact_%d" % index
		flare.emitting = false
		flare.one_shot = true
		flare.amount = 14
		flare.lifetime = LIFE
		flare.explosiveness = 1.0
		flare.local_coords = false
		flare.mesh = _square()
		flare.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
		flare.spread = 180.0
		flare.gravity = Vector3.ZERO
		flare.initial_velocity_min = 8.0
		flare.initial_velocity_max = 22.0
		flare.scale_amount_min = 0.8
		flare.scale_amount_max = 2.2
		flare.color_ramp = _ramp([[0.0, Color(1.0, 0.9, 0.6, 1.0)], [0.25, Color(1.0, 0.45, 0.1, 0.9)], [0.7, Color(0.4, 0.15, 0.8, 0.45)], [1.0, Color(0.1, 0.0, 0.2, 0.0)]])
		add_child(flare)
		_pool.append(flare)
	var flash_mesh := QuadMesh.new()
	flash_mesh.size = Vector2(1.8, 1.8)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.62, 0.2, 0.8)
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flash_mesh.material = flash_material
	for index in POOL_SIZE:
		var flash := MeshInstance3D.new()
		flash.mesh = flash_mesh
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		add_child(flash)
		_flashes.append(flash)
		_flash_times.append(0.0)


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func flash(world_position: WorldPos) -> void:
	# Keep the original Sol presentation unchanged; the stepped hit flare belongs to the Rodina style.
	if not VisualStyle.is_rodina():
		return
	var flare: CPUParticles3D = null
	for candidate in _pool:
		if not candidate.emitting:
			flare = candidate
			break
	if flare == null:
		return
	flare.position = world_position.to_local_vector3(render_origin)
	flare.restart()
	flare.emitting = true
	var local := flare.position
	for index in _flashes.size():
		if _flash_times[index] <= 0.0:
			var flash := _flashes[index]
			flash.position = local
			flash.visible = true
			_flash_times[index] = 0.12
			break


func _process(delta: float) -> void:
	for index in _flashes.size():
		if _flash_times[index] > 0.0:
			_flash_times[index] = maxf(0.0, _flash_times[index] - delta)
			_flashes[index].visible = _flash_times[index] > 0.0


func _square() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = material
	return quad


func _ramp(stops: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(stop: Array) -> float: return stop[0]))
	gradient.colors = PackedColorArray(stops.map(func(stop: Array) -> Color: return stop[1]))
	return gradient
