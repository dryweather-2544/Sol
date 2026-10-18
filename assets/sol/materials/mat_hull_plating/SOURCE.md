# mat_hull_plating
Procedural, original. Baked by `lookdev/bake/bake_hull_plating.gd` (deterministic). 2048² = 8.0 m (256 px/m): plates 2.0 × 1.0 m, 3 px seams,
fasteners every 250 mm, ~one plate in five has a 0.6 × 0.4 m access hatch (outline groove + 4 corner bolts), 220 shallow micrometeorite pits,
sparse edge chips (metallic only on chips and bolt heads). `hull_paint` #B9B6AD. Object-space triplanar ORMMaterial3D (`uv1_scale` 0.125).
Variants (tint via albedo_color, written by `make_param_materials.gd`): `_primer.tres` (hull_primer #5E6A60), `_derelict.tres` (albedo ×0.75).
Validation: CHECK PASS (albedo 128–188, metallic mid-range 0.68 %, wrap seam ratios 1.06 / 0.98 / 0.38 — albedo is close to the 1.30 limit).
Not done / limits: no exhaust soot or per-plate colour panels; 1:1 look at 150 m (mip aliasing of seams) was not checked in a distance shot.
Review shots: `lookdev/shots/mat_hull_plating_*.png`. Status: review (not yet seen by Ariel).
