# mat_ship_floor_plate

Procedural, original (no third-party input). Baked by `lookdev/bake/bake_ship_floor_plate.gd`; deterministic (fixed noise seeds).
Rebuild + validate: `lookdev/tools/build_material.sh mat_ship_floor_plate 2.0 `. 1024² = 2.0 m tile (512 px/m); object-space triplanar ORMMaterial3D (`uv1_scale` 0.5).
Dark composite deck plates 0.5 m with bolts at corners; one plate column (x 256..511) is a diamond-tread aluminium strip (metallic 1 on tread tops and bolt heads only); vertical scuffs fade out away from the walkway column. Known weakness: scuffs read slightly like fine rain streaks at close range.
Validation 2026-10-18: CHECK PASS (albedo luminance 30..240, metallic mid-range <5%, unit normals, wrap-seam ratio <1.3).
Review shots: `lookdev/shots/mat_ship_floor_plate_{tile,scale,game_light,proposed_light}.png` and `dressed_cockpit_*.png`. Status: review (not yet seen by Ariel).

**Material-quality pass (2026-10-18, branch checkpoint-review):** scuff streaks were ~3 px (6 mm) wide (noise sampled every 6th column): they sparkled close up and vanished in the mipmaps. Now sampled every 2nd column (~10 px), a second wide wear swath (`wear_noise`) added, scuff albedo lifted (0.34 -> 0.40 grey, weight 0.45 -> 0.42), scuffed roughness 0.50 -> 0.36 (polished). Albedo and ORM changed; the normal map is unchanged. Before/after: `review/material_pass/compare/mat_ship_floor_plate_*`. Remaining: the floor is still very dark in the game's room light; scuff strength was tuned by eye on stills only. Status: review.
