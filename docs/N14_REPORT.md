# N14 Rodina parity report

Branch: `n14-rodina-parity`, created from verified remote `origin/n13-graphics-port` = `8d4abe2`
(2026-10-21 11:13 UTC). The older local `n13-visual-fidelity` branch and the dirty `/Documents/Sol`
worktree are preserved; a file-level backup of the dirty worktree is at
`/tmp/Sol-main-uncommitted-backup`.

## Baseline

- Baseline suite before N14: **356 tests / 104,544 assertions / 0 failures**.
- Current suite: **364 tests / 105,375 assertions / 0 failures**.
- Real main scene boots and passes `tools/n13_graphics_check.gd` (cruise/combat capture), with Metal on the M4.
- Current N14 game was launched from the worktree; no push has been made.

## Implemented in this pass

### Terrain

- `TerrainProfile.Grammar`: Perun, Jarilo, Veles, Morena, Asteroid.
- Cinder → Perun; Aurelia → Jarilo; Verdant → Veles; Selene/Pebble → Asteroid feature grammar.
- Morena's cracked-plate equations are ported but intentionally unmapped (no documented Morena-like Sol body).
- Source constants from `EGDataPlanets.lua` and shader formulas from `Planet*.h` are recorded in
  `RODINA_SOURCE_MAP.md`.
- Voronoi point buffer and analytic derivative warp are explicit ADAPTs (cellular field and finite difference).
- Terrain generation revisions and ship re-seat migration for old saves; POI re-mapping remains open.
- Tests: world mapping, grammar determinism, bounded heights, continuity, save migration.

### Flight / collision

- Hull restitution 0.8 for non-landed impacts above a settling threshold.
- Rodina's `ControlTimer`/`TerrainContactTimer` authority ramp (drive rate; terrain telemetry is not applied to takeoff).
- Collision damage: 150 m/s minimum, incidence strength, speed factor, 0.25 s cooldown.
- WARP steering drift after full 1.8 s activation, deterministic twitch replacement for `math.random`.
- Source equations and uncertainties in `N14_PHYSICS_PASS.md`.

### Terrain streaming

- Predictive lookahead (`viewer_velocity`, 2.5 s capped at 25 km) and level-0 face fallback.
- Fine build queue is lookahead-first; level-0 faces keep the planet covered until fine children arrive.
- Per-worker `HeightFunction` removes a worker stall; the real-scene streaming probe is in
  `N14_TERRAIN_STREAMING.md`.

### Presentation

- Compact Rodina HUD with source fonts, gear tab, bottom telemetry and central reticle; detailed developer
  overlay retained for Sol/paused/debug.
- Hard-edged pixel engine layer over the N13 source-derived flame cone, per the owner's visual request.
- Real captures: `/tmp/n14_hud_reticle/cruise_1s.jpg`, `/tmp/n14_pixel_check/combat_thrust.jpg`,
  `/tmp/n14_terrain_aurelia2/`, `/tmp/n14_airless/`.
- Reference/source corrections: stale “no images/shaders” claims corrected in the earlier docs; distribution
  risk documented in `N14_DISTRIBUTION_RISK.md`.

## Known gaps

1. WARP relative-time model is still Sol's distance-scaled substitute; no verified replacement yet.
2. Rodina's full screen-space atmosphere filter is recovered but not ported; N13's calibrated sky desaturation remains.
3. Original `Ship1.ShipOpen.egm` + textures are present locally but not integrated (proprietary/public distribution
   and collision/interior coupling). No claim of an original-model port.
4. Morena has no Sol world mapping; POI positions after terrain revision changes are not individually re-mapped.
5. Audio has not been human-auditioned in this branch.
6. Human visual comparison of the new HUD/terrain against matched Rodina frames is still required.
