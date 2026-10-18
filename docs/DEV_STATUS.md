# Sol — development status

Read this first when resuming. Keep it short and current; update it with every milestone commit.

## Where things are
- **Branches:** `claude/eager-cannon-mrod2z` (pushed; M0-M5 verified). M6 is merged into it.
- **Run tests:** `tools/run_tests.sh` (imports first; filter with `-- name_substring`). Godot: `~/Downloads/Godot.app/Contents/MacOS/Godot` (4.7.2).
- **Visual checks without a human:** `tools/screenshot.gd` (ground/interior/POI views) and `tools/travel_shots.gd` (interplanetary), both need a display.

## Implemented
M0 foundation, M1 planet/landing, M2 on foot, M3 ship interior + airlock + seat (full scripted loop passes headless), M4 saves (v3 now), M5 POIs + discovery, M6 solar system, M7 (audio/menus/settings; atmosphere shader + terrain masks still open), M8 damage/suit/pressure, M9 items/loot/fuel, M10 combat (see MILESTONES.md for per-item detail and what is *not* done).

## Tests (last actual run, Godot 4.7.2 on the Mac)
see the latest commit message; last full run 0 failures. Includes full_loop, interior_moving, transition_fuzz, airlock fuzz, frame_switch (planet -> open space -> moon -> landed).

## Never checked by a human
Everything about *feel*: flight handling, mouse sensitivity, camera lag, walking speed, interior size, the look of POI props up close. Only screenshots and headless tests have been used. The user said they would play it; no feedback received yet.

## Known issues / limits
- Placeholder graphics everywhere (primitives); no humanoid avatar, no audio, no menus (pause/settings), no sky/atmosphere beyond a simple gradient.
- Props (POIs) have no colliders: the player walks through buildings and wrecks.
- Ship hull nose/tail contact points only; wings are not solid. Landing on slopes steeper than ~25 deg is awkward.
- Parked ship in the air keeps drifting/falls (gravity applies while coasting).
- No 4 s atmosphere-entry timer, no reentry damage, no ship damage at all.
- `docs/ARCHITECTURE.md` text predates ADRs 0002-0004; the ADRs win.

## Tools (need a display unless noted)
- `tools/playthrough.gd`: plays the whole loop through the real main scene with real input events (land, stand, doors, airlock, ramp, outside, back in, sit, take off to space). Last run: OK.
- `tools/perf_run.gd`: frame times through a scripted descent (results in tests/perf/results.md).
- `tools/screenshot.gd`, `tools/travel_shots.gd`: pictures of ground/interior/POI/interplanetary views.

## Blocked / needs the user
- **Manual play test** (docs/PLAYING.md has the checklist). Feel, balance and sound are all unjudged.
- **macOS export**: no export templates installed (Editor > Manage Export Templates, ~1 GB). I did not download them without permission.

## Open work, in order
1. (done) terrain masks, outpost depots. Ship upgrades done too. Interior layout editor deliberately skipped.
2. (done) primitive humanoid avatar + third-person on foot (V).
3. Tuning from the user's play feedback: flight handling, landing assist, enemy damage/aim, oxygen/jetpack numbers.
4. M12: export build, 1440p/memory perf numbers, real (not simulated) long play test.

## Phase 2 (docs/NEXT_PHASE.md) - branch `n1-ship-power`
- **N1 done** (ac3fb50): `ShipPower` reactor/conduits/heat.
- **N2 done**: `ShipSubsystems` (engines/weapons/reactor/life support health). Hits split into a subsystem by direction (round-robin for unknown sources); touchdown shocks hit engines, reentry heat the reactor. Reactor health scales output; flight thrust and gun fire rate scale with power satisfaction x health (engines floor at 15 % "emergency thrust"). Repair panel and repair kit fix the worst subsystem as well as the hull. Save v9 (+ v8->v9 migration, fixture `v8_landed_damaged`). Tests: `tests/unit/ship_subsystems_test.gd`.
  - Limits: a tripped reactor restarts itself once cooled (stand-in until the N4 reactor panel); life support health does nothing yet (N4); demand numbers (idle 15/5, thrust 35, boost 20, fire 25 of 100) and 80 % passive cooling are untuned guesses; only the player ship has `ShipSystems`, enemy ships are unaffected.
- **N3 done**: six-room ship (ADR 0005), stations as interact points with roles, gunner seat, generic wall builder, save v10 (+ v9->v10 position migration). Stations are walkable/promptable but inert until N4/N6. Tests: `interior_layout_test` (room graph connected, every station reachable from the pilot seat), full-loop test and `tools/playthrough.gd` now walk through 5 doors.
- **Next:** N4 (reactor panel UI, fire, per-room air).
