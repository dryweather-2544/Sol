# Next session

Branch `n14-rodina-parity` from verified remote `8d4abe2`. Baseline: 356 tests / 104,544 assertions / 0
failures before the terrain changes; current suite must be re-run after every commit.

## Immediate work

1. Validate the new Perun/Jarilo/Veles terrain against reference framing: add a camera-matched capture at a
   lowland/ridge boundary, verify collision/landing/POI placement and add a terrain-revision save policy.
2. Port the remaining terrain grammars (Morena cracked plates and the asteroid grammar) or explicitly leave
   their Sol profiles on LEGACY; do not ship placeholder heights.
3. ~~Implement Rodina hull restitution 0.8 and the `SetVelocityControl` authority ramp with tests.~~ Done in the N14 physics pass; the exact Havok meaning of `SetVelocityControl` is still an explicit ADAPT.
4. Audit the N13 particle/camera port against `EGDataParticles.lua` and supplied frames; the N13 shader uses
   inferred particle semantics and must not be called exact.
5. Inspect/replace the N13 atmosphere filter calibration once the shader/filter evidence is available.
6. Human-audition audio and record findings in `RODINA_AUDIO_COMPARISONS.md`.
7. Keep the proprietary Rodina WAVs and transcribed particle tables local; do not push this public repository.

## Open design questions

- Whether to keep Sol's distance-scaled WARP or port Rodina's relative-time model (world-scale risk).
- Terrain generation revision is now saved and the ship is re-seated when an old save is below the new surface;
  POI/outpost position re-mapping is still open.
- Which Sol world corresponds to Morena; do not invent a new planet merely to use the grammar.
