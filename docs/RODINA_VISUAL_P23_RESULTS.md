# Rodina visual profile — P2/P3 results

Status: P2 (ship silhouette/material/composition) and P3 (terrain colour/detail) implemented on the
reversible style profile. P4 (HUD) and P5 (entry effects) were not started.

## Baseline and final tests

Historical baseline before this pass: **310 tests / 98,934 assertions / 0 failures**.

Final after P2/P3: **313 tests / 98,944 assertions / 0 failures**.

The added tests cover:

- the dark Rodina cargo-hull material and its restoration to the imported materials;
- the separate Rodina terrain palette and plain (no high-frequency detail) terrain material;
- distinct warm/teal terrain palettes for Aurelia/Verdant rather than a global tint.

Full command:

```bash
HOME="/Users/arielbowyer/Documents/Deepseek workspace/sol_home" \
  /Users/arielbowyer/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s res://tests/run_tests.gd
```

## P2 — ship silhouette, materials and framing

### Changes

- `ExteriorHull.apply_visual_style(rodina)` applies per-surface material overrides to the existing
  cargo hull. No mesh, collision, support points, weapon alignment or flight code is changed.
- The Rodina override:
  - dark neutral albedo (0.16, 0.17, 0.19);
  - roughness 0.84, metallic 0.22;
  - keeps the original normal/AO detail;
  - keeps the original emissive maps but reduces emission energy to 2%, removing the large white
    canopy/panel glow while retaining tiny accents.
- The Sol profile restores the imported surface overrides exactly. This is covered by a test.
- Rodina camera framing now uses:
  - chase distance ≈100 m, 10° elevation;
  - 60° base FOV;
  - no speed FOV pull;
  - a longer-range chase fill so the dark hull still shows a silhouette.
- Sol camera/framing/FOV remain original. No ship geometry was changed.

### Why 100 m rather than the original 22 m

Reference screenshots show the ship as a small silhouette rather than a large hero object. A test at
200 m made the ship a barely readable dot; 100 m keeps a small but legible silhouette while matching
the reference scale better. This is a presentation compromise, not a physics change.

### Observed result

- The yellow/black cargo hull becomes a dark silhouette with only very faint cockpit/trim accents.
- The ship is much smaller in frame; the planet/terrain dominates as in the references.
- Sol mode remains the original large bright cargo presentation.

## P3 — terrain colour, detail and props

### Changes

- Added `rodina_palette_low/mid/high/snow/rock` to `TerrainProfile`.
- Authored distinct fields:
  - Aurelia: brown/ochre midlands, pale grey snow, dark rock.
  - Cinder: dark red-brown through orange.
  - Verdant: teal/dark-green fields.
  - Selene/airless: grey-violet regolith.
  - Pebble/asteroid: grey-brown rock.
- `ChunkMesher` selects the Rodina palette when the profile is active; Sol mode still uses the
  existing green/brown/grey Sol palettes.
- In Rodina mode `PlanetTerrain` uses the plain vertex-colour material, disabling the high-frequency
  soil/rock detail shader. The generator and collision remain unchanged.
- Rock scatter density is reduced to 35% in Rodina mode; Sol remains 100%.
- `PlanetTerrain.set_visual_style` rebuilds displayed chunks when the style changes, because vertex
  colours are baked at build time. This is a visible one-time load/pop when switching in the pause
  menu; it does not change the generator or saves.

### Observed result

- Ground and high-altitude terrain become broad brown/ochre fields instead of green grass.
- Fine texture noise is greatly reduced; the terrain reads at a larger scale.
- The local test site is a low-relief plain, so the reference's mountain silhouettes are not
  demonstrated by these particular captures. The existing broad landforms are unchanged; a
  mountain/ridge location still needs a dedicated capture.
- Sol terrain remains green/detailed.

## Comparison material

Local research contact sheets (not redistributed):

- `rodina-visual-research/contact_sheets/p23_ship_final.jpg`
- `rodina-visual-research/contact_sheets/p23_terrain_final.jpg`

A/B captures committed under `artifacts/visual_style_p23/`:

- Sol: orbit, high, low, ground.
- Rodina: orbit, high, low, ground.

## Performance

1600×900, full merged build. Final run after the P2/P3 changes:

| Phase | Sol | Rodina |
|---|---|---|
| Orbit/atmosphere | 100 fps avg, p95 12.1 ms | 100 fps avg, p95 12.9 ms |
| Low descent | 79 fps avg, p95 19.3 ms | 64 fps avg, p95 40.8 ms |
| Ground | 99 fps avg, p95 12.1 ms | 96 fps avg, p95 15.3 ms |
| Max draw calls | 293 | 260 |
| Max primitives | 856k | 614k |

Rodina mode has fewer primitives and draw calls but a worse low-descent tail. The far chase camera
sees more terrain/LOD work and the style switch can coincide with terrain chunk rebuilding. This is
a performance regression compared with Sol mode and should be investigated before shipping:
options are a closer Rodina camera, a lower terrain LOD budget in Rodina mode, or a gentler
style-switch rebuild. Ground and orbit remain near 100 fps.

## Changes that did not improve fidelity

- **Rodina camera at 200 m:** the ship became too small to read as a vehicle. 100 m is the current
  compromise.
- **Keeping the cargo hull's bright emissive maps:** the canopy/panels read as a white highlight,
  unlike the reference's black silhouette. Emission was reduced to 2%.
- **Only tinting the existing Sol terrain material:** a green vertex palette tinted orange still
  reads as olive/green. Separate authored palettes were required.
- **Keeping the high-frequency terrain detail shader:** it continued to look grass-like at ground
  level. Disabling it in Rodina mode was the smallest effective change.

## Known discrepancies / limitations

- The cargo hull is still a cargo shape, not Rodina's compact wedge. Only materials/framing were in
  scope; the model, collision and support points were preserved.
- The Rodina ship is very dark and very small; this matches the references but reduces gameplay
  readability. A small emissive accent system (not a whole-surface emission) is a likely P2 follow-up.
- Terrain large landforms are unchanged and the current screenshots happen to be on a flat site.
  Per-planet captures (especially mountains/ridges) are still needed.
- Cinder and Verdant palettes are authored but not visually captured in-game; they remain
  approximations until a body-transition probe exists.
- HUD/font and entry effects remain Sol-style; those are P4/P5.
- Style switching rebuilds terrain and may produce a short hitch; it is not yet a seamless swap.
- The low-descent Rodina p95 regression needs a follow-up performance pass.

## Files changed

- `src/flight/exterior_hull.gd`
- `src/camera/chase_camera.gd`
- `src/planet/terrain_profile.gd`
- `src/planet/chunk_mesher.gd`
- `src/planet/planet_terrain.gd`
- `src/planet/rock_scatter.gd`
- `src/world/star_system.gd`
- `scenes/main.gd`
- `tools/screenshot.gd` (pause-menu-proof harness)
- `tests/unit/visual_style_test.gd`
- `tests/unit/exterior_hull_test.gd`
- `docs/RODINA_VISUAL_P23_RESULTS.md`

## Git state

- Workspace clone: `Sol-canonical-merge`
- Branch: `play-combined`
- P2/P3 implementation commit: **`0713f1e`**
- This report/audit update is committed immediately after it; the current hash is in the session
  hand-off and in `~/Developer/Sol-n9-test` branch `flight/canonical-rodina`.
- No remote push.

## Recommended next steps

1. Add a Rodina terrain/shoreline probe at a mountainous long/lat and capture Cinder/Verdant once a
   body-transition tool exists.
2. Add a small dedicated emissive accent treatment to the dark ship (cyan/orange lights), without
   restoring broad white emission.
3. Profile the Rodina low-descent tail; test a closer camera/LOD budget before changing content.
4. Proceed to P4 HUD and P5 entry effects only after the terrain/ship presentation is accepted.
