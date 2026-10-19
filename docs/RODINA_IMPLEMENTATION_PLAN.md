# Rodina implementation plan

This plan is ranked by correctness first, then fidelity, dependency/risk, impact and regression risk.
It is a working plan; implementation status is updated as work lands.

## Baseline

- Canonical worktree: a workspace clone of `~/Developer/Sol-n9-test`, branch `play-combined`.
- The canonical checkout's untracked `lookdev/` assets were not modified.
- Merge base: `c968598` (shared origin/n9-art-audio).
- Canonical branch adds cargo exterior hull, cloud layer, scattering atmosphere and the fast ascent.
- Flight branch adds atmospheric entry, visual pass, orientation/6DOF/camera work and probes.
- Merged result is one branch; the merge commit is local only (not pushed).

## Priority 1 — trustworthy baseline (done)

- Run the canonical test suite before merge; verify current failures and the Godot command.
- Run the merged suite; record any failures.
- Preserve the existing `lookdev/` files and both source checkouts.
- Verification: full suite, scripted full loop, entry test, flight demo.

## Priority 2 — orientation and axes (done)

Root causes found:

1. Chase camera had a 3.8 m lateral offset, producing a rear-quarter/sideways composition.
2. Startup basis used world-up, which made roll depend on the spawn point.
3. No visual-model transform error was found: controller, hull, cockpit, muzzle and interior already
   use Sol's (−Z forward, +Y up) convention.

Changes:

- Centred camera; no lateral offset; stiffness-based orientation.
- Planet-local tangent up hint at spawn, with a polar fallback.
- Explicit Rodina→Sol axis mapping in the pilot source and state comments.
- Regression test for camera centring/right-axis alignment.

Verification: `orientation_probe.gd`, before/after screenshots, `orientation_test.gd`.

## Priority 3 — flight model (largely done)

Evidence: Rodina gear table/strengths, inertia rotation, facing control.

Implemented:

- Per-gear axis strengths.
- COMBAT acceleration 1000 m/s².
- Player rotation inertia, hardness, vacuum coasting, atmospheric friction.
- Direct `face_direction` path for AI.
- Cruise coast damping 0.01×; explicit brake.
- Velocity remains world-space; thrust is local.

Remaining:

- Validate the feel in the merged cargo-hull build and tune only with measured evidence.
- Test braking from multiple angles and speeds; add player-facing telemetry if needed.
- Decide whether DOCK rotation hardness 0.35 is too sluggish in practice.

## Priority 4 — camera (done, with a gap)

- Centred position, stiffness 5 orientation, FOV pull, restrained shake.
- Verify yaw/pitch/roll in the actual merged game.
- **Gap:** the engine camera filter/roll rule cannot be recovered from Lua. Do not claim exact
  camera parity.

## Priority 5 — atmospheric entry (done + continue)

Implemented:

- Actual velocity angle/density, drag, heat, damage, corridor/warning, recovery.
- Entry effects/shader and HUD.
- Merge with canonical clouds/scattering atmosphere.
- Controlled full-loop entry.

Next evidence-based work:

- Reconcile the richer heat model with Rodina's 4-second entry state/resistance semantics.
- Tune damage so a combat-speed entry is safe (community observation) while a steep/fast entry is
  hazardous.
- Verify entry visuals in the merged cargo build.
- Add a controlled pathological-entry test and a safe-entry test in the canonical scene.

## Priority 6 — planetary movement and transitions (verify)

Canonical has planet-frame/floating-origin, gravity, clouds and fast ascent. The merged full loop
passes. Remaining:

- Re-run floating-origin and long-duration stability with the merged speed/entry changes.
- Verify takeoff from the cargo hull.
- Check performance at 1600×900.

## Priority 7 — wider systems

Preserve canonical systems: cargo exterior, clouds, atmosphere scattering, combat, crew, interiors,
save/load, power.

Do not add a second physics path or replace the shared `PilotCommand` flow.

## Verification commands

```bash
# from the merged canonical clone
HOME="/Users/arielbowyer/Documents/Deepseek workspace/sol_home" \
  /Users/arielbowyer/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --path . -s res://tests/run_tests.gd

# flight telemetry
... -s res://tools/flight_feel_probe.gd

# actual scene camera/orientation
... --resolution 1280x720 -s res://tools/orientation_probe.gd
... --resolution 1280x720 -s res://tools/flight_demo.gd

# entry probe
... --resolution 1280x720 -s res://tools/entry_probe.gd -- 6000 -30 artifacts/entry_controlled
```

## Definition of done for this pass

- Full suite passes (or remaining failures are isolated and explained).
- Orientation/camera/6DOF tests pass.
- Full loop passes with entry and takeoff.
- Actual game run and screenshots inspected.
- Performance measured.
- Research and plan committed; no remote push.

## Current merged status (this pass)

- Merge completed into the workspace clone of the known checkout; canonical `lookdev/` untouched.
- Full suite after merge: **300 tests, 98,903 assertions, 0 failures**.
- Controlled full-loop pass: orbit → controlled entry → landing → airlock/walk → takeoff → space;
  hull preserved.
- Merged entry probe 6 km/s/-30° still runs; controlled entry costs hull (peak heat ~0.91,
  hull 0.678 at 2 km) and shows the cargo hull / cloud layer / plasma effects.
- Performance at 1600×900: orbit 100 fps avg (p95 11.98 ms), low descent 81 fps (p95 18.66 ms,
  worst 41.6 ms), ground 99 fps; max 297 draw calls, 861k primitives, 2.95 ms physics.
- Remaining high-value work: tune the entry heat/damage so a combat-speed entry stays safe and a
  steep/fast one remains dangerous; improve the plasma envelope; verify camera feel by hand in the
  merged cargo build; resolve the unrecoverable engine-camera filter.
