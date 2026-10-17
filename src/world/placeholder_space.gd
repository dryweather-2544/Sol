class_name PlaceholderSpace
extends Node3D
## Sun light, star sky and a seeded scatter of rocks plus one big moon, so there is something
## to fly past. Throwaway: replaced by real planets in M1.

const WORLD_SEED := 42
const ROCK_COUNT := 160
const SCATTER_RADIUS := 5000.0
const CLEAR_RADIUS_AROUND_START := 150.0


func _ready() -> void:
	add_to_group("origin_shift")
	_add_environment()
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.45, 0.4, 0.36)
	rock_material.roughness = 1.0
	var rng := SeedRng.new(SeedHash.derive(WORLD_SEED, "placeholder_rocks"))
	for rock_index in ROCK_COUNT:
		var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
		var distance := CLEAR_RADIUS_AROUND_START + rng.next_float() * (SCATTER_RADIUS - CLEAR_RADIUS_AROUND_START)
		var size := 10.0 + rng.next_float() * 140.0
		_add_rock(direction * distance, Vector3(size, size * (0.5 + rng.next_float() * 0.6), size * (0.6 + rng.next_float() * 0.6)), rock_material)
	var moon_material := StandardMaterial3D.new()
	moon_material.albedo_color = Color(0.7, 0.72, 0.78)
	moon_material.roughness = 1.0
	_add_rock(Vector3(2500.0, 600.0, -9000.0), Vector3.ONE * 2500.0, moon_material)


func _add_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://data/shaders/space_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.14, 0.2)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.6
	add_child(sun)


func _add_rock(position_value: Vector3, scale_value: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	instance.scale = scale_value
	add_child(instance)


func apply_origin_shift(shift: Vector3) -> void:
	position -= shift
	reset_physics_interpolation()
