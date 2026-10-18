# mat_ship_rubber_mat

Procedural, original (no third-party input). Baked by `lookdev/bake/bake_ship_rubber_mat.gd`; deterministic (noise seeds 201-203).
Rebuild + validate: `lookdev/tools/build_material.sh mat_ship_rubber_mat 1.0 --dielectric`. 512² = 1.0 m tile (512 px/m); object-space triplanar ORMMaterial3D (`uv1_scale` 1.0).
Ribs run along V, **128 per tile = 7.8 mm pitch = 4 px**. The library says 8 mm, which is 4.1 px and would not tile; changed on purpose. Boot-worn patches flatten the ribs (low-frequency noise); dust collects in the grooves (albedo up to ~0.27 in grooves). Base albedo 0.155 (sRGB ~#2A), so no pixel is below 30 (ART_DIRECTION `rubber #1F1F20` is 31; matching it exactly would sit on the limit). Roughness mean 0.88; metallic 0.
Validation 2026-10-18: CHECK PASS (albedo luminance 34..65, metallic 0, unit normals, wrap-seam ratios 0.70 / 0.86 / 0.80).
Lookdev: ribs are visible on the cube in the room shots, but at the 1 m tile shot (about 5 px per rib) they alias to near-flat grey; mipmaps fade them with distance.
Integration (I4): airlock and cargo floors, seat pads. Review shots: `lookdev/shots/mat_ship_rubber_mat_{tile,scale,game_light,proposed_light}.png`.
Status: review. **Not seen by a human.**
