# Visual pass — 2026-10-18

Branch: `visual/n9-art-pass` (based on `n9-art-audio` at `c968598`; not committed or pushed).
Target: Godot 4.7.2, Forward+, macOS Apple M4 / 16 GB.

## What was actually wrong

1. The local `user://settings.cfg` had all five N9 art switches off. The game was running with
   placeholder materials, no terrain detail, no decals and no starfield. This alone explains much
   of the "primitive" look.
2. The player ship exterior was assembled from flat boxes. It had no coherent nose, canopy, engine
   silhouette or rear face.
3. The cockpit had a single huge glass wall, no dashboard frame and a bright console slab.
4. The HUD was the old debug text dump, with no hierarchy or visual relationship to the cockpit.
5. The sky/fog grade was pale and flat; the terrain had little macro colour variation and no
   ground clutter; the atmosphere limb was invisible from 300 km.

## What changed

- **Settings migration** (`GameSettings`): a legacy settings file without a version is repaired
  once to art-on. Later saves keep the player's explicit choices.
- **New hull shell** (`ShipHullShell`): nine-point loft with a raised centre ridge, nose chin,
  canopy bubble, swept delta wings with a lighter top skin, box engine cowls, canted tail fins,
  rear access door, panel seams, RCS pods and landing gear. Visual only; collision, interior,
  landing and flight are untouched.
- **Cockpit**: framed windshield, dark dashboard, raised MFDs with data strokes, side consoles,
  centre stick, throttle, overhead switch row and instrument lighting.
- **Interior**: panel trim, wall ribs, ceiling luminaires, floor accents, engineering conduits,
  cargo lockers, warmer/cooler room lights, reflection probe and decals restored.
- **HUD** (`DebugOverlay` + `FlightReticle`): compact status card, power strip, objective/signal
  card, centred prompt, alert card, faded help, and a subtle flight reticle. The old debug dump is
  gone; the information is still present.
- **Environment**: ACES grade, exposure/contrast, SSAO, restrained glow, directional shadows,
  warmer sun, new sky gradient/sun/cloud bands, per-room fog, terrain detail fade extended to
  1.2 km, stronger macro colour variation, darkened Aurelia palette, visible atmosphere limb from
  300 km, and a deterministic visual-only rock scatter around the player.
- **Camera**: chase view moved to a slight 3/4 angle with a soft camera-side fill so the rear hull
  is not a silhouette. Cockpit view remains a separate fixed camera.

## Verification

- 276 tests / 96,293 assertions / 2 failures, both pre-existing audio tests:
  `test_loops_loop_over_the_whole_sample` (sample length) and
  `test_audio_service_emits_cue_started_and_steals_by_priority` (service can be added to tree).
  All flight, landing, interior, airlock, save/load, mission and network-independent scenario tests
  pass when `HOME` points at a writable workspace directory. The default `user://` path is blocked
  by this session's file sandbox, which is why the first run reported save failures.
- Performance at 1600×900: 120 fps average, p95 10.6 ms, worst 44 ms (one chunk-build hitch),
  max 1,181 draw calls, max physics 4.58 ms, ~876 MB video memory.
- No game executable or installer was run; only the built project.

## Remaining weaknesses (ranked)

1. The ship still reads as a boxy industrial shuttle rather than a Rodina-level hero ship. The
   silhouette and surface break-up are better, but the model is code-built from primitives.
2. The cockpit MFDs are graphic bars, not real instrument readouts. They need a proper UI texture
   or `SubViewport` content.
3. The terrain at 100–300 m is still smooth and low-contrast; rock scatter helps but there are no
   authored geological features or vegetation.
4. The sky/cloud grade is subtle; at ground level it still looks clean and empty rather than
   weather-beaten.
5. The atmosphere limb is a thin blue band, not volumetric scattering; it is only convincing at
   high altitude.
6. The interior is brighter and more detailed but still corridor-like; no bespoke props or
   character animation pass.
