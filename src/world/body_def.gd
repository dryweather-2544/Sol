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
var atmosphere_color := Color(0.29, 0.48, 1.0) # default: Earth-like Rayleigh blue (ratio of 1 / wavelength^4 at 0.65 / 0.57 / 0.475 um)

## Rodina presentation palette. These are deliberately separate from the physical atmosphere/terrain
## colours so the Rodina profile can use flat, saturated skies without changing the Sol profile or
## the terrain surfaces. Values are authored as sRGB and converted by source_color shader uniforms.
var rodina_space_color := Color(0.040, 0.012, 0.070)
var rodina_sky_zenith := Color(0.10, 0.18, 0.24)
var rodina_sky_horizon := Color(0.72, 0.50, 0.44)
var rodina_sun_color := Color(0.35, 0.92, 0.92)
## Sunlight used on surfaces in Rodina profile; can be warmer than the visible disc.
var rodina_light_color := Color(1.0, 0.90, 0.78)
var rodina_ambient_color := Color(0.045, 0.035, 0.055)
## Colour used for the body's distant impostor sphere in Rodina profile.
var rodina_color := Color(0.55, 0.50, 0.42)


## Distance within which this body's own frame takes over (research PRC-01: 10 x radius).
func sphere_of_influence() -> float:
	return radius * 10.0
## Cloud layer: coverage 0 = none (airless worlds), up to 1 = overcast; altitude in metres above the surface.
var cloud_coverage := 0.0
var cloud_color := Color(1.0, 1.0, 1.0)
var cloud_altitude := 10000.0
