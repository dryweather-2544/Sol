# N10 — WARP gear and flight regression repairs

Status: implemented on branch `n10-warp`, based on the latest GitHub work
`origin/claude/sol-vtol-ship-overhaul-9eglhk` @ `143ca6e` (2026-10-20 16:11 UTC).

The earlier local `n9-flight-recovery` branch was intentionally not used: it was based on
`n1-ship-power` @ `ab3cdac` and had already been superseded by the remote flight/physics overhaul.

## Implemented

### A. Fourth gear: WARP / Limnal

- `PilotCommand.GEAR_WARP = 3`, above PRECISION (0), COMBAT (1) and CRUISE (2).
- `ShipTuning` gains the fourth row of its per-gear tables:
  - 100,000 km/s nominal ceiling (capped by the distance-scaled open-space environment);
  - 0.2 acceleration factor, no engine drag/deceleration in vacuum;
  - weak lateral/vertical/reverse authority like cruise;
  - no station keeping; limnal rotation hardness.
- `FlightModel` caps WARP at `environment.cruise_speed_limit * 6.7` and applies the same
  high-speed excess decay as cruise. Sol's cruise is already distance-scaled, so Rodina's 209.7
  relative-time multiplier is not applied literally.
- `SystemNavigator` allows WARP only when the warp drive is installed (`warp_factor >= 0.5`) and
  the ship is in open space. Planet frames still cap at COMBAT/CRUISE, so WARP cannot be used in
  an atmosphere or near a surface.
- `PlayerPilotSource` now allows the player to shift from CRUISE to WARP (the initial integration
  gap: the model existed but the binder still clamped at CRUISE).
- WARP burns `0.01` fuel/s while thrusting versus `0.002` for cruise.
- HUD lists WARP, shows its environment-limited top speed, and keeps the selected-gear feedback.
- Save schema is unchanged; gear and selected gear already round-trip. A new test covers WARP.

### B. Pre-existing test regressions repaired

- `AudioLibrary.frame_count()` now uses the decoded length for compressed WAVs (IMA ADPCM/QOA);
  counting compressed bytes made the 10 s idle loop report 4.05 s.
- The audio service test runs `_ready()` explicitly because the test harness executes during
  `SceneTree._initialize`, before the root window receives ENTER_TREE.
- Added the missing `AudioLibrary.reset_warnings()` helper.
- Decal nodes store their catalogue set/name in metadata. Duplicate sibling names (two hazard
  stripes, repeated scorch variants) were auto-renamed by Godot to `@Decal@…`, which made the
  catalogue test fail even though the source entry was correct.

### C. Data-driven planet content

- Added `PlanetDefinition extends Resource` (identity, physical/orbital values, atmosphere, colour
  and terrain profile) with validation and BodyDef conversion.
- Generated `data/planets/{sol,aurelia,selene,cinder,verdant,pebble}.tres` from the existing
  runtime values, preserving every body id used by saves.
- `StarSystem.default_system()` now overlays those definitions on the original in-code bodies and
  falls back to the in-code body if a resource is missing or invalid. Runtime `BodyDef` remains
  unchanged.
- Added ADR 0009 and an architecture note.

## Tests

```text
Godot 4.7.2 | files 60 | tests 318 | assertions 96,602 | failures 0
```

Run with `tools/run_tests.sh`. Real-scene headless check `tools/gear_check.gd` also ran
successfully: it starts the actual `main.tscn`, shifts PRECISION → COMBAT → CRUISE and reports
speed/fuel over 500 frames (0.6 → 500.6 → 37,390 m/s). It does not yet drive the ship into the
system frame, so WARP is covered by unit tests rather than that tool.

## Limits / remaining

- WARP is a fourth **speed gear**, not a separate bounded-local-velocity + `RelativeTime` scalar.
  A future travel-feel pass may replace the distance-scaled cap with that model.
- No graphical warp effect, sound, camera FOV shift or human playtest of WARP.
- The existing flight model still has open engine-side questions (collision restitution and
  control authority) documented in `docs/RODINA_PHYSICS_AUDIT.md`.
- Planet content now has a typed `.tres` layer for all six bodies; visual-style families and
  terrain-shader parameters remain in code. A future pass can move those presentation parameters
  into per-body resources too.
