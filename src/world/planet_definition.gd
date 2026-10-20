class_name PlanetDefinition
extends Resource
## Authored data for one star/planet/moon. BodyDef remains the runtime view used by StarSystem,
## physics and saves; this resource is the content boundary so a body can be edited in a .tres
## without touching star-system assembly.

@export var id: StringName
@export var display_name := ""
@export var is_star := false
@export var parent_id: StringName = &""
@export var radius := 6.0e6
@export var surface_gravity := 12.0
@export var atmosphere_height := 200000.0
@export var atmosphere_friction := 1.0
@export var breathable := true
@export var orbit_radius := 0.0
@export var orbit_period := 1.0e6
@export var orbit_phase := 0.0
@export var spin_period := 6000.0
@export var terrain_profile: TerrainProfile
@export var color := Color(0.5, 0.5, 0.5)
@export var atmosphere_color := Color(0.35, 0.6, 1.0)


func to_body_def() -> BodyDef:
	var body := BodyDef.new()
	body.id = id
	body.display_name = display_name
	body.is_star = is_star
	body.parent_id = parent_id
	body.radius = radius
	body.surface_gravity = surface_gravity
	body.atmosphere_height = atmosphere_height
	body.atmosphere_friction = atmosphere_friction
	body.breathable = breathable
	body.orbit_radius = orbit_radius
	body.orbit_period = orbit_period
	body.orbit_phase = orbit_phase
	body.spin_period = spin_period
	body.terrain_profile = terrain_profile
	body.color = color
	body.atmosphere_color = atmosphere_color
	return body


static func from_body_def(body: BodyDef) -> PlanetDefinition:
	var definition := PlanetDefinition.new()
	definition.id = body.id
	definition.display_name = body.display_name
	definition.is_star = body.is_star
	definition.parent_id = body.parent_id
	definition.radius = body.radius
	definition.surface_gravity = body.surface_gravity
	definition.atmosphere_height = body.atmosphere_height
	definition.atmosphere_friction = body.atmosphere_friction
	definition.breathable = body.breathable
	definition.orbit_radius = body.orbit_radius
	definition.orbit_period = body.orbit_period
	definition.orbit_phase = body.orbit_phase
	definition.spin_period = body.spin_period
	definition.terrain_profile = body.terrain_profile
	definition.color = body.color
	definition.atmosphere_color = body.atmosphere_color
	return definition


func validation_error() -> String:
	if id == &"":
		return "planet definition has no id"
	if radius <= 0.0:
		return "planet %s has non-positive radius" % id
	if surface_gravity < 0.0:
		return "planet %s has negative gravity" % id
	if atmosphere_height < 0.0:
		return "planet %s has negative atmosphere height" % id
	if orbit_period <= 0.0 and not is_star:
		return "planet %s has non-positive orbit period" % id
	if spin_period <= 0.0:
		return "planet %s has non-positive spin period" % id
	return ""
