# dec_ship_damage

Procedural, original (no third-party input). 8 decals, one file set each (not an atlas: Godot's `Decal` has no region/UV-rect
property [V: property list of `Decal` in Godot 4.7.2]). **Integration table: `decals.csv`** (size in metres, depth, maps,
`albedo_mix`, placement). Files: `dec_ship_damage_<name>_{albedo,normal,orm}.png` where the csv `maps` column lists them.

- **Bake:** `lookdev/bake/bake_ship_damage.gd` (headless, deterministic seeds 101-103, 201-202, 301-302, 401).
  `godot --headless --path lookdev -s res://bake/bake_ship_damage.gd`
- **Validate:** `godot --headless --path lookdev -s res://validate/check_decal.gd -- dec_ship_damage`
- **Scale:** 512 px/m (dents ~530). Scorch 1.0 m (03: 1.5 x 1.0 m, plume rises toward the image top), scratches 0.5 x 0.25 m,
  dents 0.3 / 0.5 m, cracked panel 0.5 m.
- **Maps:** `_albedo.png` RGBA8 sRGB, alpha = mask, alpha 0 within 3 px of every edge; `_normal.png` RGB8 linear OpenGL Y+ from a
  height field via `HeightOps.height_to_normal` (flat 128,128,255 away from the mask; the 1 px ring touching the mask may slope);
  `_orm.png` linear, metallic strictly 0 or 255 (255 only inside scratches and flaked paint, roughness 0.4 there).
- **Scorch:** dark warm grey (~50 sRGB, never below 30), roughness 0.85, metal 0, no glow, no orange (ART_DIRECTION §11).
- **Dents are normal-only:** set `Decal.albedo_mix = 0`; the albedo PNG only carries the mask in alpha (rgb 128 grey).
- **Lookdev spike (2026-10-18, `lookdev/tools/decal_spike.gd`, `SPIKE PASS`):** (a) an albedo decal renders (mean luminance
  change 0.043 over the decal area); (b) with `albedo_mix = 0` an alpha-masked normal-only decal changes the wall (upper half
  +0.007, lower half -0.009 luminance vs no decal: **real but subtle**); (c) a raised dome lit from above is brighter on its
  upper half (0.4735 vs 0.4560), so the Y+ convention holds for decals. No fallback was needed. Dents are therefore subtle by
  design; if Ariel wants them more visible, raise `depth` in `_dent()` (normal strength), not the albedo.
- **Validation (2026-10-18):** `check_decal` PASS for all 8 (RGBA, size multiple of 4 and equal to csv, border clear, visible
  luminance 30-240, normals unit length and flat outside the mask, metallic binary).
- **Review shots:** `lookdev/shots/dec_ship_damage_{sheet,game_light,proposed_light}.png` (sheet: all 8 on a paint wall; the room
  shots place them on the cockpit's east/nose walls, partly at the frame edge).
- **Concerns (claude only, stills):** soot reads cloud-like/blotchy up close; the crack network is thin and small (about 0.4 m);
  dents are very subtle under the game's flat room light.
- **Status:** review. Not seen by a human.
