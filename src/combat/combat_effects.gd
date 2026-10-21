class_name CombatEffects
extends Node3D
## Short-lived impact flashes for projectile hits. The reference's combat frames use bright stepped
## sparks at the hit point; Sol previously removed the projectile silently. Fixed pool, no allocation
## per shot, and rendering-only (the simulation owns damage).

const POOL_SIZE := 16
const LIFE := 0.32

var render_origin := WorldPos.new(&"planet")
var _pool: Array[CPUParticles3D] = []


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
		flare.scale_amount_min = 0.35
		flare.scale_amount_max = 0.9
		flare.color_ramp = _ramp([[0.0, Color(1.0, 0.9, 0.6, 1.0)], [0.25, Color(1.0, 0.45, 0.1, 0.9)], [0.7, Color(0.4, 0.15, 0.8, 0.45)], [1.0, Color(0.1, 0.0, 0.2, 0.0)]])
		add_child(flare)
		_pool.append(flare)


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)


func flash(world_position: WorldPos) -> void:
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


func _square() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
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
