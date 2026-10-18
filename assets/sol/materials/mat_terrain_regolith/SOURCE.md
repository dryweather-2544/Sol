# mat_terrain_regolith

Procedural, original (no third-party input; no photo-scan was downloaded, so no licence rows). Baked by `lookdev/bake/bake_terrain_regolith.gd`, deterministic.
Fine dust with pebbles (1-4 cm, 7000) and scattered stones (5-20 cm, 160), neutral grey albedo (mean linear luminance 0.2148, shader uniform flat_mean_linear). 1024² = 4.0 m (256 px/m). Per-stone value variation is softened so stones do not read as flat stickers. Also ships an 8-bit _height.png (R8) for future height-blending.
Used through `lookdev/shaders/terrain_detail.gdshader` (prototype): the albedo is a NEUTRAL detail that is divided by its mean and multiplied onto the world's vertex colour, so one set serves every world. Dielectric (metallic 0, checked with --dielectric).
Rebuild + validate: `lookdev/tools/build_material.sh mat_terrain_regolith 4.0 --dielectric`. Terrain scene checks: `lookdev/tools/shoot_terrain.gd`, `check_terrain_normals.gd`.
Review shots: `lookdev/shots/terrain_{selene,aurelia}_{1.7,20,200}m.png`. Status: review (not yet seen by Ariel).
