# Rodina visual fidelity — prioritized implementation roadmap

This is the implementation plan derived from `RODINA_VISUAL_RESEARCH.md`. No broad rewrite was
started before the research. The goal is a **Rodina visual mode** that reproduces the observed
identity without destroying the working modern Sol look, cargo hull, clouds or gameplay systems.

## Guiding rules

1. **Do not chase generic realism or generic retro.** The target is Rodina's specific graphic
   language: dark negative space, saturated body colours, flat skies, thin limbs, silhouettes,
   chunky effects, cyan bitmap UI.
2. **Do not delete the modern presentation.** Add an explicit `visual_style` profile; default can be
   switched after A/B review. This keeps all existing systems and allows regression comparisons.
3. **Colour and value first, geometry second.** Most of the identity is palette/contrast/silhouette,
   not polygon count. Change global look before replacing assets.
4. **Preserve gameplay readability.** Rodina's HUD is graphic but sparse; do not hide speed, heat,
   targets or landing information in the name of fidelity.
5. **Use per-body data.** Rodina's palette is planet-specific. Store a Rodina palette resource per
   body (space/sky/horizon/sun/ground/feature colours) rather than a single global LUT.
6. **Measure against references.** Every milestone gets an A/B screenshot set under the same
   altitude, sun angle, camera and planet palette; no “looks closer” without evidence.

## Proposed architecture

Add a `VisualStyle`/`RodinaLook` profile selected in `GameSettings` (e.g. `visual_style = "sol"` /
`"rodina"`). The profile owns:

- environment/post settings (tonemap, exposure, ambient, glow, SSAO/fog toggles);
- sky/atmosphere material variant;
- per-body palette resource;
- terrain/material overrides and detail-scatter budget;
- ship/interior material overrides;
- HUD theme and bitmap font;
- effects/post pixel treatment and optional retro scale.

Do **not** fork the gameplay scene or physics. Existing `SpaceEnvironment`, `AtmosphereShell`,
`CloudShell`, `TerrainProfile`, `ExteriorHull` and HUD remain the systems; the profile supplies
appearance parameters and, where necessary, alternate shader paths.

## Priority 0 — visual harness and baseline (1 day)

- Add a screenshot harness extension that sets: body palette, sun elevation, altitude, camera mode,
  visual style, and output pairs.
- Re-capture current Sol at orbit/50 km/5 km/500 m/ground/cockpit/interior/entry under fixed sun
  angles. The current `visual_ref` frames are the first baseline.
- Create the Rodina-mode toggle and a **no-op** profile; verify it does not change existing tests or
  rendering.
- Acceptance: identical Sol screenshots with profile off; test suite still passes.

## Priority 1 — colour grade, sky and space (highest impact, lowest risk)

**Goal:** the first side-by-side should immediately read as Rodina before touching geometry.

- Replace ACES/white-point/bright ambient for Rodina mode with a flatter tone curve and lower
  exposure/ambient; retain highlight roll-off only enough for the sun.
- Add a per-body **Rodina palette**: space `#0a0311`/`#05030d`; body feature colours (ochre,
  salmon, cyan, lavender); sky/horizon/sun colours; ambient/terminator tint. Use sampled reference
  values as starting points, then verify.
- Replace the physical scattering sky for Rodina mode with a two-colour/simple analytical gradient
  + horizon haze + stars. Keep the existing scattering mode available.
- Make stars visible in daylight/twilight; add a painted/procedural Milky Way band with crisp
  star points (reference skybox resolution 1024 is acceptable/authentic).
- Make the sun a distinct disc with a soft/stepped halo in the reference colour (cyan/red/orange/
  white per body), not a white overexposed blob.
- Remove or heavily reduce cloud shells in Rodina mode by default; keep a per-body optional thin
  cloud band only if a reference supports it.

Acceptance: orbit, 50 km, 5 km and ground A/B frames show Rodina's saturated sky and black space
contrast; no pale blue/white atmospheric veil; stars visible where the reference shows them.

## Priority 2 — lighting, materials and ship value

- Rodina mode: low ambient, direct sun + simple diffuse/backside/emissive; disable SSAO and
  screen-space GI; use hard/compact shadows; reduce/disable glossy PBR response.
- Ship exterior: render the cargo hull with a dark neutral override and minimal specular; suppress
  bright trim / decals / detailed greebles at chase distance. Keep collision and support points.
  Optionally provide a simplified Rodina-style hull shell as a separate visual mesh, not a physics
  change.
- Interiors: dark grey/green base materials, flat panel response, strong local cyan/orange/red
  practicals, fewer bright fill lights. Reduce prop density/trim visibility in Rodina mode.
- Terrain/rock materials: flatten roughness/specular, reduce normal-map strength, use broad colour
  blocks with low-frequency detail.

Acceptance: ship and interior values match the reference's dark silhouette/grey-box character;
no glossy cargo-highlight read in the chase frame.

## Priority 3 — terrain silhouette, scale and ground composition

- Reduce high-frequency terrain detail/grass/rock scatter in Rodina mode; keep broad landform
  silhouettes and large colour fields. Reference terrain reads as plateaus/ridges/craters, not
  grass.
- Drive ground colours from per-body feature colours (base/plateau/mountain/rock) with a small
  number of broad blends; avoid dense micro-texture noise.
- Use distance-based texture blending only where it supports the silhouette; reduce detail budget
  for performance and readability.
- Adjust fog to a flat coloured horizon band, not a white atmospheric depth wash.
- Keep the ship small in the frame; review chase distance/FOV. Rodina default FOV is 60°; Sol uses a
  wider modern view. A Rodina profile should start near 60° and a more distant, smaller ship.
- Verify horizon curvature/scale at 5 km and ground; the planet should dominate, not the ship.

Acceptance: surface A/B frames show Rodina-like salmon/cyan/purple ground, dark mountain
silhouettes, flat coloured horizon and a smaller ship.

## Priority 4 — HUD, fonts and UI

- Introduce a bitmap/pixel UI theme: cyan/blue angular panels, stepped corners, 1–2 px outlines,
  small block font, sparse telemetry. Keep essential flight/entry/landing information readable.
- Apply the theme to flight HUD, entry warnings, speed/heat, target markers and menus; avoid modern
  drop shadows/rounded cards.
- Use pixel scale deliberately (integer scale for UI; optional `RetroModePixelSize`-like global
  effect, not mandatory).
- Preserve accessibility/legibility and colour-blind cues.

Acceptance: a screenshot at 1080p shows the reference cyan/block HUD, not the current modern cards;
all critical data remains visible.

## Priority 5 — effects, entry and particles

- Replace the smooth translucent plasma envelope in Rodina mode with a stepped/pixelated
  fire/overlay + large additive sprites around the silhouette; screen colour tint on severe entry.
- Quantise/step particle alpha/size and use simple quads; remove volumetric/smooth smoke.
- Use a simple additive bloom/halo pass; no modern multi-scale bloom or screen-space blur.
- Keep entry gameplay/warnings/damage unchanged; only the presentation changes in Rodina mode.
- Reproduce the reference's blocky projectile trails and strong red/orange fire-room overlay.

Acceptance: entry and combat A/B frames show stepped orange/purple fire and pixel trails, not a
smooth bubble.

## Priority 6 — optional retro presentation and polish

- Optional integer pixel scale (Rodina has `RetroMode`, default off; treat as a player option, not
  the default identity).
- FXAA or nearest filtering choices; avoid TAA smear.
- Per-body palettes for all planets, moons and asteroid fields; verify no palette collision that
  destroys target readability.
- Final performance budget: no new expensive volumetric passes; target ≥60 fps at 1600×900 with
  the existing M4 16 GB machine. Measure before/after.

## Regression and verification plan

For each milestone:

1. Capture matching Rodina/Sol frames at fixed camera/altitude/sun angle.
2. Record palette statistics and visual observations; compare with
   `rodina-visual-research/palette_report.csv`.
3. Run full Godot suite; no gameplay changes should fail.
4. Run full loop, entry, frame switch and floating-origin scenarios.
5. Check HUD readability and target/landing cues in actual play.
6. Measure frame time; keep Rodina mode within budget.
7. Commit a milestone only after screenshots and tests.

## What not to do

- Do not replace Sol's physics/entry with visual hacks.
- Do not delete the cargo hull, clouds or modern rendering outright; keep them behind the style
  profile until the Rodina mode is proven.
- Do not globally pixelate the game because Rodina has an optional RetroMode; the released look is
  low-detail geometry/UI/effects, not necessarily a 4.5 px whole-screen filter.
- Do not copy Rodina's proprietary shader/model/texture assets into Sol. The reference is
  behavioural/visual evidence.

## P0/P1 status

P0 and P1 are implemented and validated in the reversible profile. See
`RODINA_VISUAL_P1_RESULTS.md` for screenshots, tests and performance. P2/P3 are the next
priorities: ship silhouette/material value, then terrain colour/detail/framing.

## Immediate next step (after P1)

Implement Priority 0 + 1 as a reversible `rodina` visual profile: capture the current baseline,
then change only the sky/space palette, exposure/ambient and sun/limb. Review the orbit and 50 km
A/B before touching terrain, ship or UI.
