class_name BodyDef
extends RefCounted
## One star, planet, moon or asteroid: its size, orbit and terrain. Orbits are circular and
## analytic (research: Rodina has no n-body, `04` §2.3), so any body's position is a pure function
## of game time.

var id: StringName
var display_name: String
var is_star := false
## Parent body id (&"" = orbits the star's frame origin directly, i.e. the star itself at 0,0,0).
var parent_id: StringName = &""
var radius := 6.0e6
var surface_gravity := 12.0
## Atmosphere thickness in metres; 0 = airless.
var atmosphere_height := 200000.0
## Rodina AtmosphereFriction: damping of a coasting ship's spin deep in this world's air (Rodina: 1 on most worlds).
var atmosphere_friction := 1.0
## Breathable air at the surface (false: toxic or none, so a suit tank is needed outside).
var breathable := true
var orbit_radius := 0.0
var orbit_period := 1.0e6
var orbit_phase := 0.0
## Seconds for one turn of the planet under the sun (day length). Drives the sun's apparent motion.
var spin_period := 6000.0
var terrain_profile: TerrainProfile
var color := Color(0.5, 0.5, 0.5)
## Colour of the glowing rim around the atmosphere.
var atmosphere_color := Color(0.35, 0.6, 1.0)


## Distance within which this body's own frame takes over (research PRC-01: 10 x radius).
func sphere_of_influence() -> float:
	return radius * 10.0
