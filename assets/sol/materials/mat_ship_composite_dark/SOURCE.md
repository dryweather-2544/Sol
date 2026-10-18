# mat_ship_composite_dark

Procedural, original (no third-party input). Baked by `lookdev/bake/bake_ship_composite_dark.gd`; deterministic (fixed noise seeds).
Rebuild + validate: `lookdev/tools/build_material.sh mat_ship_composite_dark 2.0 --dielectric`. 1024² = 2.0 m tile (512 px/m); object-space triplanar ORMMaterial3D (`uv1_scale` 0.5).
Moulded composite: orange-peel relief, soft mottling, a few light scuffs. Dielectric only (metallic 0, checked with --dielectric). Albedo #2A2D30 (luminance 42–62): reads nearly black under the game's dim light, as intended for console bodies.
Validation 2026-10-18: CHECK PASS (albedo luminance 30..240, metallic mid-range <5%, unit normals, wrap-seam ratio <1.3).
Review shots: `lookdev/shots/mat_ship_composite_dark_{tile,scale,game_light,proposed_light}.png` and `dressed_cockpit_*.png`. Status: review (not yet seen by Ariel).
