# mat_poi_rusted_metal
Procedural, original (no photo-scan downloaded, so no licence rows). Baked by `lookdev/bake/bake_poi_rusted_metal.gd`. 1024² = 4.0 m (256 px/m): plates 1.0 × 2.0 m
with rivet lines; faded primer-green paint (#5E6A60) breaking away over rust (≈45–55 % rust), rust gathers at seams and rivets, sparse bare-steel glints at flake edges
(metallic 1 there only; rust and paint are dielectric). Rust colours deliberately muted (first version was too orange/saturated, against ART_DIRECTION §11).
Validation: CHECK PASS after narrowing the bare-steel mask (first bake had metallic mid-range 8 % > 5 % limit).
Weakness: the rust pattern is a threshold of noise, so blotch shapes are uniform; at close range it reads busy. A photo-scan blend (CC0) was in the plan and is NOT done.
Review shots: `lookdev/shots/mat_poi_rusted_metal_*.png`. Status: review (not yet seen by Ariel).

**Material-quality pass (2026-10-18, branch checkpoint-review):** now 2048² = 8.0 m (8 x 4 plates; `.tres` uv scale 0.125). The same blotch pattern used to come round every 4 m; added a very-low-frequency field (rustier / cleaner regions) and a per-plate coverage and paint-tone offset (`HeightOps.hash01(plate_column, plate_row)`). Before/after renders: `review/material_pass/compare/mat_poi_rusted_metal_*`. Still repeats every 8 m, and the plate grid itself is regular; rust colours were not changed. Status: review.
