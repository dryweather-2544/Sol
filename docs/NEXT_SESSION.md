# Next session

Branch `n14-rodina-parity` from verified remote `8d4abe2`. Baseline: 356 tests / 104,544 assertions / 0
failures before the terrain changes; current suite must be re-run after every commit.

## Immediate work

1. Validate the new Perun/Jarilo/Veles terrain against reference framing: add a camera-matched capture at a
   lowland/ridge boundary, verify collision/landing/POI placement and add a terrain-revision save policy.
2. Morena's cracked-plate grammar is implemented but no Sol world is mapped to it; airless Selene/Pebble use
   the asteroid feature grammar. Add remaining crater/material work and decide whether a Morena-like Sol world
   is a documented design change.
3. ~~Implement Rodina hull restitution 0.8, impact damage and the `SetVelocityControl` authority ramp with tests.~~ Done in the N14 physics pass; the exact Havok meaning of `SetVelocityControl` is still an explicit ADAPT.
4. WARP steering drift is ported; coasting Wing trails still depend on Rodina's unimplemented clutch. Audit the
   N13 particle/camera port against `EGDataParticles.lua` and supplied frames; the N13 shader uses
   inferred particle semantics and must not be called exact. The pixel engine overlay is a user-design
   addition, not a source port.
5. Inspect/replace the N13 atmosphere filter calibration once the shader/filter evidence is available.
6. Human-audition audio and record findings in `RODINA_AUDIO_COMPARISONS.md`.
7. Keep the proprietary Rodina WAVs, EGM models/textures and transcribed particle tables local; do not push this
   public repository. See `N14_DISTRIBUTION_RISK.md` and the corrected `ATTRIBUTION.md`.

## Open design questions

- Whether to keep Sol's distance-scaled WARP or port Rodina's relative-time model (world-scale risk).
- Terrain generation revision is now saved and the ship is re-seated when an old save is below the new surface;
  POI/outpost position re-mapping is still open.
- Which Sol world corresponds to Morena; do not invent a new planet merely to use the grammar.
