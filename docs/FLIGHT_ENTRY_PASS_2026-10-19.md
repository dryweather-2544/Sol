# Flight and atmospheric-entry pass — 2026-10-19

Branch: **`flight/entry-pass`** (continues the uncommitted visual pass; no commit, no push).
Engine: Godot 4.7.2, Forward+, macOS Apple M4.

## What was wrong before

- Cruise acceleration was effectively instant because `acceleration = max(acceleration, max_speed)`.
  At 300 km the old altitude-scaled limit reached 90 km/s, so the ship teleported up to speed and
  the planet did not have time to read as distance.
- No-thrust damping was strong in every gear. The ship stopped like a car instead of carrying
  momentum.
- The atmosphere only changed the sky/fog and applied a coarse speed cap. There was no velocity-
  vector flight-path angle, no drag, no thermal load, and no entry feedback.
- `ShipDamage.heating_rate()` only looked at speed and whether the ship was anywhere inside the
  atmosphere. It could not distinguish shallow, controlled, steep, or too-fast entries.
- There were no entry effects, warnings, camera response, or entry audio.

## Implemented

### Flight

- Cruise acceleration is a sustained burn (`max(base, limit * 0.10)`), not a teleport. With a
  12 km/s limit the ship reaches the cap in about 5 s.
- Cruise coast damping is 0.12× the normal assist, so releasing thrust carries momentum; brake
  remains full strength and is perceptible.
- Atmospheric drag acts on the actual velocity vector. It is the main entry decelerator and it
  replaces the old invisible speed snap when the gear is forced down near the ground.
- High interplanetary cruise is gated behind the existing warp drive. Without it, the ship is
  limited to 12 km/s near a world; with it, the distance-scaled limit returns. This preserves the
  frame-switch test and makes the warp installation meaningful.
- Chase camera FOV and restrained shake respond to speed and heat. A vacuum speed trail and
  atmospheric streak particles give the ship motion without blur.
- The HUD shows km/s above 1 km/s and adds an entry corridor/heat line.

### Entry model (`AtmosphericEntry`)

- Uses **actual velocity**, not nose direction:
  - `vertical_speed = velocity · local_up`
  - `horizontal_speed = sqrt(v² − vertical²)`
  - `flight_path_angle = atan2(vertical, horizontal)` in degrees.
- Density proxy: `(1 − atmosphere_ratio)^1.8`.
- Drag: `density · v² / 90,000`, capped at 420 m/s².
- Heat rate: density, speed above 1 km/s, and descent factor; cooling depends on density.
- Corridors: `SPACE`, `SHALLOW`, `CONTROLLED`, `STEEP`, `TOO_FAST`.
- Thermal load persists and cools. Damage begins above 0.75 heat and uses the existing hull
  and subsystem health path (reactor/engines), not a second health bar.
- Landed ships cool quickly and take no further thermal damage.

### Entry presentation

- Original `entry_plasma.gdshader` additive envelope, driven by heat/density.
- 72 airflow streaks; 46 vacuum speed-trail particles.
- `entry_vignette.gdshader` screen heat vignette.
- Camera shake/FOV and cockpit shake.
- Entry roar synthesized by `SoundSynth.EntryVoice`; warning cue on heat/steep/too-fast edges.
- HUD warning plus concise telemetry; no simulator instrumentation.

## Verified behaviour

`tools/flight_feel_probe.gd` (pure, no rendering):

```
accelerate 1s: 2500 m/s (2.5 km/s)
accelerate 3s: 7500 m/s (7.5 km/s)
accelerate 5s: 12000 m/s (12.0 km/s)
cruise cap: 12000 m/s
coast 10s from cap: 7200 m/s
brake to 1 m/s: 0.90 s
```

`tools/entry_probe.gd -- 6000 -30` (controlled but unpowered coast):

- enters the atmosphere around 180 km;
- heat rises through 35% to ~90%;
- drag reduces 6.0 km/s to 2.33 km/s by 2 km altitude;
- ends at hull 67.8% with `HULL HEATING` / `CRITICAL HEAT` warnings and reactor/engine damage;
- still controllable: the player can brake or pull up; cooling is implemented and tested.

`tools/entry_probe.gd -- 12000 -70` (deliberate failure):

- `ENTRY TOO FAST` at 11.5 km/s;
- heat reaches 150%, hull 0%, reactor/engine power 0;
- ship destroyed around 10.7 km altitude, with the normal “restoring your last save” path.

`tools/entry_probe.gd -- 6000 -30 ... recover` (recovery):
- starts the same controlled entry, then applies full brake above 55% heat;
- heat falls to 0%, hull stays 100%, and the ship crosses 2.3 km altitude at 1.5 km/s.
  This is the intended recoverable path: the player can arrest a marginal entry rather than being
  locked into a scripted death.

`tools/entry_probe.gd -- 8000 -2` (too shallow):

- stays above 265 km after 180 s; no heating because it never enters the dense atmosphere. Near the
  top of the atmosphere the HUD/corridor reports `SHALLOW APPROACH - MAY SKIP`.

Full-loop scenario uses a controlled entry (brakes above 4 km/s) and passes: orbit → entry →
landing → interior/airlock/walk → takeoff → space, with hull > 80%.

## Reproduce

```bash
# pure handling numbers
HOME="$PWD/../sol_home" "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --headless --path . -s res://tools/flight_feel_probe.gd

# controlled, recovery, and steep entries; review frames under artifacts/
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot" tools/run_entry_scenario.sh
# optional recovery probe:
#   ... -s res://tools/entry_probe.gd -- 6000 -30 artifacts/entry_recovery recover
```

The probe uses `lock_linear` coast so the trajectory is deterministic; the player's actual controls
add thrust/brake and can therefore recover.

## Tests and performance

- 56 test files, 279 tests, 96,303 assertions, **2 failures**, both existing audio-test issues:
  sample-length expectation (`178496` vs 10 s) and adding `AudioService` to the tree in headless.
  The entry, flight, descent, full-loop, frame-switch, combat and replay tests pass.
- 1600×900: 100 fps average, p95 ~12 ms, max draw calls 1,068, physics 3.06 ms.
  One ground-phase script hitch of ~486 ms was observed; it is a one-frame load/compile hitch and
  is not acceptable for a final build. It needs a prewarm/instrumentation pass.
- No game executable or installer was used.

## Remaining weaknesses

1. The plasma envelope still reads as a translucent bubble/ring rather than a turbulent sheath.
   It needs a better mesh/shader (flow-aligned ribbons, shock cap) in the next pass.
2. Entry heat/damage values are tuned by probe, not by a wide human playtest. The controlled
   6 km/s/-30 coast loses 32% hull; that may be too punitive once players are actually braking.
3. The HUD is still text-first for entry. A compact heat bar and corridor gate would read faster.
4. The atmosphere is a stylised density/fog model, not volumetric scattering; the horizon/limb
   remains a band rather than a physically convincing atmosphere.
5. The ground-phase hitch needs profiling; particle/shader first-use is the current suspect.
6. Entry audio was implemented and wired, but not auditioned on speakers in this session.
