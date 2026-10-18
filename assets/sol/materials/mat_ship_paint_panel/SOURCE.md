# mat_ship_paint_panel

Procedural, original (no third-party input). Painted wall/ceiling panels, `hull_paint` #B9B6AD (ART_DIRECTION §2.2).

- **Bake:** `lookdev/bake/bake_paint_panel.gd` (deterministic; noise seeds 11–14, `FastNoiseLite` seamless images).
  Rebuild + validate: `lookdev/tools/build_material.sh mat_ship_paint_panel 2.0`
- **Scale:** 1024² = 2.0 m tile (512 px/m). Panels 1.0 × 0.5 m, groove ≈3 px (~6 mm), fasteners every 250 mm,
  27 mm inset from the seam. Seams sit on the tile border so the tile wraps.
- **Maps:** `_albedo.png` sRGB (de-lit; luminance 128–186); `_normal.png` linear, OpenGL (Y+) from a real height
  field (groove, edge pooling, fastener bumps, paint peel) with `HeightOps.height_to_normal`, strength 2.2;
  `_orm.png` linear R=AO, G=roughness (≈0.62 paint, ≈0.40–0.50 worn/fastener), B=metallic (1 only on edge-wear
  chips and fastener heads, 0 elsewhere).
- **Material:** `mat_ship_paint_panel.tres` = ORMMaterial3D, `uv1_triplanar` (object space), `uv1_scale` 0.5.
  Written by `lookdev/tools/make_material.gd`.
- **Variants planned:** primer green-grey tint = same .tres with `albedo_color` multiplied (package A2).
- **Validation (2026-10-18):** `CHECK PASS` — see commit message for the quoted output. Self-tests confirm normal
  orientation (ramp right → R<128, ramp toward top → G<128, flat → 128,128,255) and that the tiling check rejects a
  gradient and accepts a sine.
- **Lookdev findings / decisions:**
  1. First bake had too much edge wear (read as black dashed seam lines from a distance: metal in a dark environment
     reflects almost nothing). Wear thresholds raised, grime and groove AO reduced. Edge wear is now sparse.
  2. **Integration note:** bare-metal chips only look right if the interior has something to reflect (a
     ReflectionProbe or sky ambient). Without one they render near-black. Listed under I2 in the integration guide.
  3. In the lookdev "game" light (white omni, energy 1.6) the paint reads as near-white; under the proposed warm
     light (`#FFE3C4`) it reads as the intended warm off-white. Light colour matters more than albedo here.
  4. Seam ratio uses a symmetric local-max metric (a groove centred on the wrap line made a naive metric fail).
- **Review shots:** `lookdev/shots/mat_ship_paint_panel_{tile,scale,game_light,proposed_light}.png`.
- **Status:** review (awaiting Ariel's direction check: seam scale, wear amount, colour).
