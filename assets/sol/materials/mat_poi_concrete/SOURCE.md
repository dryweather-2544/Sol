# mat_poi_concrete

Procedural, original (no third-party input; the manifest's "CC0 photo or procedural" resolved to procedural, no licence row). Baked by `lookdev/bake/bake_poi_concrete.gd`; deterministic (seeds 301-311).
Rebuild + validate: `lookdev/tools/build_material.sh mat_poi_concrete 4.0 --dielectric`. 1024² = 4.0 m (256 px/m): 2 x 2 cast panels of 2.0 m with 3 px recessed joints, form-tie holes on a 0.5 m grid per panel, ~900 air-bubble pits, per-panel tone offset, metre-scale tone drift and vertical run stains. Neutral grey (albedo mean ~0.5), roughness mean 0.88, metallic 0. Object-space triplanar ORMMaterial3D (`uv1_scale` 0.25).
**No dust at the base** (the library row asks for it): a tiling triplanar map has no base. That belongs to a decal or to integration.
Validation 2026-10-18: CHECK PASS (albedo luminance 92..144, metallic 0, unit normals, wrap-seam ratios 0.46 / 0.57 / 0.19).
Integration (I5): outposts, depot walls, beacon base, pads. Review shots: `lookdev/shots/mat_poi_concrete_{tile,scale,game_light,proposed_light}.png`.
Status: review. **Not seen by a human.**
