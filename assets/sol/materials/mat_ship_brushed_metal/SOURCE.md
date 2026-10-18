# mat_ship_brushed_metal

Procedural, original (no third-party input). Baked by `lookdev/bake/bake_ship_brushed_metal.gd`; deterministic (fixed noise seeds).
Rebuild + validate: `lookdev/tools/build_material.sh mat_ship_brushed_metal 2.0 `. 1024² = 2.0 m tile (512 px/m); object-space triplanar ORMMaterial3D (`uv1_scale` 0.5).
Brushed steel (#8C8F93 reflectance), metallic 1 everywhere; streaks are in roughness (0.34–0.52) plus faint micro-relief, never in albedo; 12 shallow dings. Needs something to reflect (see INTEGRATION_GUIDE I2b): in the lookdev 'game' environment it renders dark apart from the omni highlight.
Validation 2026-10-18: CHECK PASS (albedo luminance 30..240, metallic mid-range <5%, unit normals, wrap-seam ratio <1.3).
Review shots: `lookdev/shots/mat_ship_brushed_metal_{tile,scale,game_light,proposed_light}.png` and `dressed_cockpit_*.png`. Status: review (not yet seen by Ariel).
