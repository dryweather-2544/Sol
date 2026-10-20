class_name TerrainProfile
extends Resource
## Everything that defines one world's terrain shape. Same profile + same seed = same planet.

@export var radius := 6000000.0
@export var terrain_seed := 1234
## Broad continents/basins (unit-sphere noise).
@export var macro_amplitude := 2500.0
@export var macro_scale := 2.5
## Ridged mountains, only where the macro noise says "land".
@export var mountain_amplitude := 3500.0
@export var mountain_scale := 8.0
## Metre-scale detail: wavelength in metres and amplitude in metres.
@export var hill_wavelength := 300.0
@export var hill_amplitude := 8.0
@export var rough_wavelength := 70.0
@export var rough_amplitude := 1.5
## Kilometre-scale rolling relief so a landing area is not a flat plain: wavelength and amplitude in metres.
@export var mid_wavelength := 4000.0
@export var mid_amplitude := 180.0
@export var large_wavelength := 20000.0
@export var large_amplitude := 500.0

## Surface palette (vertex colours): lowland, midland, highland, snow/ice, bare rock. snow_height is where
## snow starts at the equator; it drops toward the poles (latitude mask).
@export var palette_low := Color(0.28, 0.36, 0.2)
@export var palette_mid := Color(0.45, 0.4, 0.28)
@export var palette_high := Color(0.5, 0.5, 0.5)
@export var palette_snow := Color(0.95, 0.96, 1.0)
@export var palette_rock := Color(0.38, 0.36, 0.34)
@export var snow_height := 4200.0

## Rodina-profile broad colour fields. Kept separate from the Sol palette so switching styles does not
## mutate the original terrain definition (and Sol screenshots remain unchanged).
@export var rodina_palette_low := Color(0.24, 0.15, 0.09)
@export var rodina_palette_mid := Color(0.42, 0.27, 0.16)
@export var rodina_palette_high := Color(0.58, 0.40, 0.27)
@export var rodina_palette_snow := Color(0.68, 0.72, 0.77)
@export var rodina_palette_rock := Color(0.20, 0.16, 0.13)
