# tex_sky_starfield

Procedural, original, seeded (`SEED 20261018`). `sky/tex_sky_starfield.png`: 4096 x 2048, 8-bit RGB sRGB, equirectangular.

- **Bake:** `godot --headless --path lookdev -s res://bake/bake_sky_starfield.gd` (~6 s). Then import, `python3 tools/set_texture_imports.py sky`, import again.
- **Mapping (the convention for I7; self-defined, NOT verified against Godot's `PanoramaSkyMaterial`):**
  `u = 0.5 + atan2(x, -z) / TAU`, `v = 0.5 - asin(y) / PI`: u 0.5 = -Z (Godot forward), +X = u 0.75, +Y = top row. Ecliptic = the XZ plane.
  `lookdev/shaders/space_sky_starfield.gdshader` implements it with `EYEDIR` (not `SKY_COORDS`) and the game's uniform names
  `daylight`, `sun_direction`; it is a proposal for I7 and is not used by the game.
- **Content:** background exactly `#05070C`; 9,000 stars uniform on the sphere (peak `#E9ECF2`, 25% faintly blue, 25% faintly amber,
  brightness `0.12 + 0.88 r^5`), Gaussian splats widened by 1/cos(latitude) (capped 20x) so they are round on screen at the poles;
  a dim dusty band along a great circle at 60 degrees to the ecliptic (normal (0.866, 0.5, 0), sigma 12 degrees, +6 sRGB levels
  at most, faintly warm, with dark dust lanes). No nebula colour. 3,019 stars have a peak >= 60 (the rest are fainter).
- **Resolution [E]:** a 75 degree FOV at 1920 px spans ~9,200 px per 360 degrees, so 4096 is magnified ~2.25x; stars are 1-2 texels
  wide, so they are soft on screen (see shots).
- **Import (differs from materials on purpose):** VRAM compressed (`compress/mode=2`, high quality) with **mipmaps OFF**
  (always magnified; mipmaps would also draw a seam at the atan wrap). Applied by `tools/set_texture_imports.py` (it special-cases
  `sky`); `check_imports -- sky` expects 0 mip levels. ~8 MiB VRAM [E: 4096 x 2048 x 1 byte].
- **Validation (2026-10-18), `validate/check_sky.gd`:** size; horizontal wrap seam ratio 0.46 (limit 1.30, horizontal-only flag added
  to `check_texture.tile_seam_ratio`); channel medians 5/7/12 = `#05070C`; no pixel below background or above starlight; no
  pixel > 25% saturated (value > 60); 3,019 stars; compression: worst peak loss over the 100 brightest stars 7.6% (limit 10%).
  **Deviation from the brief:** the "pole rows <= 3x equator run length" criterion contradicts the brief's own 1/cos widening
  (stars at the pole are meant to be hundreds of px wide). The check instead requires the 70-75 degree run length to be within 1.5x
  of the expected 1/cos widening: measured 3.21x vs expected 3.33x, limit 4.99x. Self-test: a hard-seam image is rejected.
- **Shots:** `lookdev/shots/tex_sky_starfield_{band_horizon,zenith,away_from_band,seam,band_daylight_half}.png` (1920 x 1080,
  FOV 75, filmic). Compared against `PanoramaSkyMaterial`: mean difference ~0.007 for every view because the sky is mostly black;
  **inconclusive**, so panorama orientation is unverified (irrelevant if I7 uses the shader's own mapping).
- **Concerns (claude only, stills):** the band is very faint (as intended: "dim") and its dust lanes are blotchy at close range;
  star density/brightness balance was judged from stills only; no check at the real game's exposure.
- **Status:** review. Not seen by a human.
