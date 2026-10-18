# mat_terrain_soil_dry

Procedural, original (no third-party input; the manifest's "CC0 photo-scan derived" was not used, no download, no licence row). Baked by `lookdev/bake/bake_terrain_soil_dry.gd`; deterministic (seeds 401-421).
Rebuild + validate: `lookdev/tools/build_material.sh mat_terrain_soil_dry 4.0 --dielectric`. 1024² = 4.0 m (256 px/m). Terrain detail layer built like `mat_terrain_regolith`: NEUTRAL grey albedo, the world's vertex colour supplies the hue. Also ships an 8-bit `_height.png` (R8; imported lossless like the regolith one, so `set_texture_imports.py` must not be run on this folder again without restoring that).
Content: undulation, 900 clods (2-9 cm) with per-clod value, ~12,000 crumbs, shrinkage cracks (zero-crossings of a noise field; dark, recessed), 90 sparse short grass tufts (9 blades of 2-5 cm each) as **luminance (+18 %) and normal only**; no green in the albedo. Roughness mean 0.92; metallic 0.
**`flat_mean_linear` for the terrain shader = 0.2066** (printed by check_texture; regolith's default is 0.2148). Use it when this set replaces `flat_*` on Aurelia / Verdant (I3).
Validation 2026-10-18: CHECK PASS (albedo luminance 57..185, metallic 0, unit normals, wrap-seam ratios 0.48 / 0.45 / 0.42).
Lookdev: `scenes/lookdev_terrain.gd` now has `flat_material_id` / `flat_mean_linear`; `tools/shoot_terrain.gd` renders `terrain_aurelia_soil_{1.7,20,200}m.png`. Terrain invariance checks still pass (TERRAIN CHECK PASS).
Concerns (stills only): cracks read as meandering vein lines rather than a polygonal crack network; grass tufts are not visible in the 1.7 m shot. Review shots: `lookdev/shots/mat_terrain_soil_dry_{tile,scale,game_light,proposed_light}.png`, `terrain_aurelia_soil_*.png`.
Status: review. **Not seen by a human.**
