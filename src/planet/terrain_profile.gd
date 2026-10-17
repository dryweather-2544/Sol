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
