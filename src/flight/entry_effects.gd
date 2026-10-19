class_name EntryEffects
extends Node3D
## Exterior plasma envelope and airflow streaks for atmospheric entry. Pure presentation:
## all decisions come from ShipState.entry_heat/density/speed.

var ship: Ship
var _shell: MeshInstance3D
var _shell_material: ShaderMaterial
var _streaks: CPUParticles3D
var _speed_trail: CPUParticles3D
var _light: OmniLight3D
var _glow_material: StandardMaterial3D


func _ready() -> void:
	name = "EntryEffects"
	_shell_material = ShaderMaterial.new()
	_shell_material.shader = load("res://data/shaders/entry_plasma.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_shell = MeshInstance3D.new()
	_shell.name = "PlasmaEnvelope"
	_shell.mesh = sphere
	_shell.material_override = _shell_material
	_shell.position = Vector3(0.0, 0.1, 1.4)
	_shell.scale = Vector3(5.9, 2.9, 11.4)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.extra_cull_margin = 24.0
	add_child(_shell)

	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color(1.0, 0.36, 0.08)
	_glow_material.emission_enabled = true
	_glow_material.emission = Color(1.0, 0.26, 0.04)
	_glow_material.emission_energy_multiplier = 4.0
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_streaks = CPUParticles3D.new()
	_streaks.name = "EntryStreaks"
	_streaks.amount = 72
	_streaks.lifetime = 0.7
	_streaks.local_coords = true
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_streaks.emission_sphere_radius = 5.0
	_streaks.direction = Vector3(0.0, 0.0, -1.0)
	_streaks.spread = 180.0
	_streaks.initial_velocity_min = 18.0
	_streaks.initial_velocity_max = 55.0
	_streaks.gravity = Vector3.ZERO
	_streaks.scale_amount_min = 0.5
	_streaks.scale_amount_max = 1.6
	var streak := BoxMesh.new()
	streak.size = Vector3(0.035, 0.035, 1.35)
	_streaks.mesh = streak
	_streaks.material_override = _glow_material
	_streaks.emitting = false
	add_child(_streaks)

	# A short engine/speed trail outside the atmosphere. It is what makes a fast pass read as
	# motion when there is no air to carry streak particles.
	_speed_trail = CPUParticles3D.new()
	_speed_trail.name = "SpeedTrail"
	_speed_trail.amount = 46
	_speed_trail.lifetime = 0.45
	_speed_trail.local_coords = true
	_speed_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_speed_trail.emission_sphere_radius = 1.1
	_speed_trail.direction = Vector3(0.0, 0.0, 1.0)
	_speed_trail.spread = 12.0
	_speed_trail.initial_velocity_min = 12.0
	_speed_trail.initial_velocity_max = 34.0
	_speed_trail.gravity = Vector3.ZERO
	_speed_trail.scale_amount_min = 0.35
	_speed_trail.scale_amount_max = 1.0
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(0.025, 0.025, 0.9)
	_speed_trail.mesh = trail_mesh
	_speed_trail.material_override = _glow_material
	_speed_trail.position = Vector3(0.0, -0.1, 10.3)
	_speed_trail.emitting = false
	add_child(_speed_trail)

	_light = OmniLight3D.new()
	_light.name = "PlasmaGlow"
	_light.position = Vector3(0.0, 0.7, 0.0)
	_light.omni_range = 20.0
	_light.light_color = Color(1.0, 0.32, 0.06)
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _process(_delta: float) -> void:
	if ship == null:
		return
	var heat := clampf(ship.state.entry_heat, 0.0, 1.5)
	var density := clampf(ship.state.entry_density, 0.0, 1.0)
	var speed_factor := clampf(ship.state.entry_speed / 10000.0, 0.0, 1.2)
	var intensity := clampf(maxf(heat * 1.05, density * speed_factor * 0.55), 0.0, 1.0)
	visible = intensity > 0.01
	_shell_material.set_shader_parameter("intensity", intensity)
	_streaks.emitting = intensity > 0.04
	_streaks.initial_velocity_min = 18.0 + heat * 42.0
	_streaks.initial_velocity_max = 55.0 + heat * 75.0
	_light.light_energy = intensity * 2.4
	_light.omni_range = 12.0 + intensity * 12.0
	var speed_intensity := clampf(ship.state.speed() / 12000.0, 0.0, 1.0)
	_speed_trail.emitting = speed_intensity > 0.08 and ship.state.entry_density <= 0.01
	_speed_trail.scale_amount_max = 0.6 + speed_intensity * 1.6
	_speed_trail.initial_velocity_max = 22.0 + speed_intensity * 48.0
