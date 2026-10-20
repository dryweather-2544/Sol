class_name ShipEffects
extends Node3D
## Rodina-style ship effects, shown only while the rodina VisualStyle is active (the sol style shows none of this, so
## its look is unchanged). Evidence for the approach: Rodina particle effects are colour/alpha/size keys over each
## particle's life with a per-effect blend style (research 07 §8.5.4); entry effects run during atmospheric entry
## (research 02 §5). Colours, sizes and rates here are Sol's own inferences: no Rodina frame was available.
## - Engine plumes: additive sprites from each nozzle, white-hot to cyan to nothing, rate following thrust demand.
## - Entry heating: an additive sheath round the nose and hot streaks blown aft, driven by the atmospheric resistance
##   of the entry (ShipState.atmosphere_resistance): it builds as resistance rises and is full where the hull burns.

var _plumes: Array[CPUParticles3D] = []
var _nacelles: Array[MeshInstance3D] = []
var _trail_mesh := ImmediateMesh.new()
var _trail_instance := MeshInstance3D.new()
var _trail_material := StandardMaterial3D.new()
var _streaks := CPUParticles3D.new()
var _sheath := MeshInstance3D.new()
var _sheath_material := ShaderMaterial.new()
var _heat := 0.0


## nacelles: the nozzle nodes (cylinder +y is the exhaust direction); each gets a plume.
func setup(nacelles: Array[MeshInstance3D]) -> void:
	name = "ShipEffects"
	# Plumes are this node's children (a nozzle must keep exactly one child, its exhaust disc) and follow the nozzles,
	# which tilt with the pods, every frame.
	_nacelles = nacelles
	for nacelle in nacelles:
		var plume := _make_plume()
		add_child(plume)
		_plumes.append(plume)
	_build_trails()
	_build_heat()


func update_effects(ship: Ship, delta: float) -> void:
	var active := VisualStyle.is_rodina()
	visible = active
	var demand := 1.0 if ship.last_command.boost else minf(ship.last_command.thrust.length(), 1.0)
	var speed := ship.state.speed()
	for index in _plumes.size():
		var plume := _plumes[index]
		plume.transform = _nacelles[index].transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)) # nozzle exit
		plume.emitting = active and demand > 0.1
		plume.speed_scale = 0.6 + 0.6 * demand
	_update_trails(ship, active)
	var state := ship.state
	var target := clampf(state.atmosphere_resistance / ShipDamage.ENTRY_DAMAGE_START, 0.0, 1.0) if active else 0.0
	_heat = move_toward(_heat, target, delta * 1.5)
	_sheath.visible = _heat > 0.01
	_sheath_material.set_shader_parameter("heat", _heat)
	_streaks.emitting = _heat > 0.15
	if state.velocity.length() > 1.0:
		# Streaks stream away from the direction of travel, in ship space.
		_streaks.direction = (state.basis.transposed() * -state.velocity.normalized())
	_streaks.speed_scale = 0.5 + _heat


## Reference evidence (trailer CRUISE SPEED): two long, dotted lime trails persist behind the ship.
## They only make sense once the ship is moving; precision/low-speed flight keeps the short plume.
static func trails_should_emit(speed: float, gear: int) -> bool:
	return gear >= PilotCommand.GEAR_COMBAT and speed > 180.0


static func _additive_sprite(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = material
	return quad


## A round dot, bright in the middle and fading to nothing at the edge, so sprites are not hard squares.
static func _soft_dot() -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	texture.gradient = _ramp([[0.0, Color(1, 1, 1, 1)], [0.35, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]])
	return texture


static func _ramp(stops: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(stop: Array) -> float: return stop[0]))
	gradient.colors = PackedColorArray(stops.map(func(stop: Array) -> Color: return stop[1]))
	return gradient


## Two camera-facing ribbons from the nacelles. ImmediateMesh is rebuilt in ship-local space
## every render frame; the camera-facing width keeps the trail visible from the chase view and the
## alternating segments reproduce the dotted lime trail seen at CRUISE SPEED.
func _build_trails() -> void:
	_trail_instance.name = "SpeedTrails"
	_trail_instance.mesh = _trail_mesh
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_trail_instance.material_override = _trail_material
	_trail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_instance)


func _update_trails(ship: Ship, active: bool) -> void:
	_trail_mesh.clear_surfaces()
	var speed := ship.state.speed()
	if not active or not trails_should_emit(speed, ship.state.gear):
		return
	var out := Vector3(0, 0, 1)
	if speed > 1.0:
		out = ship.state.basis.transposed() * (-ship.state.velocity / speed)
	var camera_local := Vector3(0.0, 6.0, 26.0)
	if is_inside_tree() and get_viewport().get_camera_3d() != null:
		camera_local = ship.global_transform.affine_inverse() * get_viewport().get_camera_3d().global_position
	var length := clampf(speed * 0.12, 18.0, 260.0)
	var warp := ship.state.gear == PilotCommand.GEAR_WARP
	var start_color := Color(0.85, 1.0, 0.18, 0.95) if not warp else Color(0.8, 0.92, 1.0, 0.95)
	var end_color := Color(0.08, 0.42, 0.01, 0.0) if not warp else Color(0.04, 0.12, 0.55, 0.0)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_material)
	for nacelle in _nacelles:
		var lateral := signf((nacelle as Node3D).position.x)
		var start: Vector3 = (nacelle as Node3D).position + out * 0.8 + Vector3(lateral * 2.0, lateral * 1.0, 0)
		var finish := start + out * length + Vector3(lateral * 18.0, lateral * 5.0, 0)
		var dots := 48
		for index in dots:
			var t := (float(index) + 0.5) / float(dots)
			var centre := start.lerp(finish, t)
			var normal := (camera_local - centre).normalized()
			var side := out.cross(normal)
			if side.length() < 0.001:
				side = out.cross(Vector3.UP)
			side = side.normalized() * 0.36
			var up := normal.cross(side).normalized() * 0.36
			var colour := start_color.lerp(end_color, t)
			# Dotted path: the quads are separated along the path by their spacing.
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre - side - up)
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre + side - up)
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre + side + up)
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre - side - up)
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre + side + up)
			_trail_mesh.surface_set_color(colour)
			_trail_mesh.surface_add_vertex(centre - side + up)
	_trail_mesh.surface_end()


func _make_plume() -> CPUParticles3D:
	var plume := CPUParticles3D.new()
	plume.name = "Plume"
	plume.amount = 28
	plume.lifetime = 0.45
	# Ship-relative: at entry speeds the ship covers ~150 m per frame, so world-space particles would be left behind.
	plume.local_coords = true
	plume.mesh = _additive_sprite(0.9)
	plume.direction = Vector3(0, 1, 0)
	plume.spread = 5.0
	plume.gravity = Vector3.ZERO
	plume.initial_velocity_min = 16.0
	plume.initial_velocity_max = 24.0
	plume.scale_amount_min = 0.7
	plume.scale_amount_max = 1.1
	plume.scale_amount_curve = Curve.new()
	plume.scale_amount_curve.add_point(Vector2(0.0, 1.0))
	plume.scale_amount_curve.add_point(Vector2(1.0, 0.35))
	plume.color_ramp = _ramp([[0.0, Color(1.0, 0.97, 0.92, 0.9)], [0.25, Color(0.55, 0.9, 1.0, 0.7)], [0.7, Color(0.2, 0.45, 1.0, 0.3)], [1.0, Color(0.1, 0.2, 0.6, 0.0)]])
	plume.emitting = false
	return plume


func _build_heat() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_sheath.mesh = sphere
	_sheath.name = "HeatSheath"
	_sheath_material.shader = load("res://data/shaders/entry_heat.gdshader")
	_sheath.material_override = _sheath_material
	_sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Wrapped round the forward hull and nose (the hull spans x +-3.8, y -1.3..2.8, z -9.3..11).
	_sheath.scale = Vector3(4.6, 2.6, 9.0)
	_sheath.position = Vector3(0.0, 0.6, -3.0)
	_sheath.visible = false
	add_child(_sheath)
	_streaks.name = "EntryStreaks"
	_streaks.amount = 160
	_streaks.lifetime = 0.6
	_streaks.local_coords = true
	_streaks.mesh = _additive_sprite(0.55)
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(3.2, 1.6, 0.5)
	_streaks.position = Vector3(0.0, 0.4, -9.0)
	_streaks.spread = 10.0
	_streaks.gravity = Vector3.ZERO
	_streaks.initial_velocity_min = 30.0
	_streaks.initial_velocity_max = 55.0
	_streaks.color_ramp = _ramp([[0.0, Color(1.0, 0.75, 0.4, 0.9)], [0.3, Color(1.0, 0.5, 0.15, 0.75)], [0.75, Color(0.9, 0.2, 0.05, 0.35)], [1.0, Color(0.4, 0.05, 0.0, 0.0)]])
	_streaks.emitting = false
	add_child(_streaks)
