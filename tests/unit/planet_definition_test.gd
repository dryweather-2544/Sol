extends "res://tests/test_case.gd"


func test_aurelia_loads_from_the_typed_definition_with_its_existing_identity() -> void:
	var system := StarSystem.default_system()
	var body: BodyDef = system.bodies[&"planet"]
	assert_eq(body.id, &"planet", "save identity is unchanged")
	assert_eq(body.display_name, "Aurelia")
	assert_near(body.radius, 6.0e6, 1e-6)
	assert_near(body.surface_gravity, 12.0, 1e-9)
	assert_near(body.atmosphere_height, 200000.0, 1e-9)
	assert_true(body.terrain_profile != null)


func test_definition_round_trip_preserves_body_fields() -> void:
	var body := BodyDef.new()
	body.id = &"test_world"
	body.display_name = "Test World"
	body.radius = 123456.0
	body.surface_gravity = 4.2
	body.atmosphere_friction = 0.5
	body.terrain_profile = TerrainProfile.new()
	body.terrain_profile.terrain_seed = 77
	var definition := PlanetDefinition.from_body_def(body)
	assert_eq(definition.validation_error(), "")
	var restored := definition.to_body_def()
	assert_eq(restored.id, body.id)
	assert_eq(restored.display_name, body.display_name)
	assert_near(restored.radius, body.radius, 1e-9)
	assert_near(restored.atmosphere_friction, 0.5, 1e-9)
	assert_eq(restored.terrain_profile.terrain_seed, 77)


func test_every_shipped_body_has_a_valid_definition_resource() -> void:
	var system := StarSystem.default_system()
	assert_eq(system.bodies.size(), StarSystem.BODY_DEFINITIONS.size(), "definitions cover every body")
	for body_id in StarSystem.BODY_DEFINITIONS:
		assert_true(system.bodies.has(body_id), "%s is in the runtime system" % body_id)
		var body: BodyDef = system.bodies[body_id]
		assert_eq(body.id, body_id, "%s keeps its identity" % body_id)
		if not body.is_star:
			assert_true(body.terrain_profile != null, "%s has terrain" % body_id)
