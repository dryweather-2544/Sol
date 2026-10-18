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
- **N4 done**: `ShipHazards` (per-room oxygen + fire; fire starts from accumulated subsystem damage, grows, burns air and the subsystems in its room, spreads only through open doors, starves when air runs out; life support refills air); extinguisher (locker in engineering, F sprays, 6 charges, saved); reactor panel UI (`ReactorMenu`, conduit limits / vent coolant / restart, all via `ShipSystems.request_*(actor_id, ...)`); HUD alert line, alarm cue, red room light + flame prop; low room air drains the suit tank, fire in your room hurts. Auto-restart of a tripped reactor below 20 % heat, panel restart below 50 %. No save version bump (new keys are optional with defaults). Tests: `tests/unit/ship_hazards_test.gd`. Debug: `tools/screenshot.gd ... inside x z yaw fire|reactor`.
  - Limits: hazard numbers untuned; fire has no smoke/particles (a pulsing emissive box); ship does not simulate while the player is on foot far away only because the whole session ticks every frame (R5 not decided: it does tick).
- **N5 done** (ADR 0006): `ShipCrew`/`CrewMember`/`CrewNavigator`/`CrewView`. Two crew (engineer Mara at the reactor panel, gunner Kit in the gunner seat) are added at game start by `scenes/main.gd` and drawn as coloured humanoid avatars. They walk between stations through doors (opening them), sit in seats, never end up in walls, and are saved. They do nothing on their own yet. Tests: `tests/unit/ship_crew_test.gd` (every station from every room within 40 s, door/airlock fuzz with crew, seat contention, save round trip) and crew in `transition_fuzz_test`.
- **N6 done**: `CrewBrain` (utility goals every 0.5 s with a commitment bonus; engineer: extinguish > reactor (restart/vent) > repair > idle; gunner: fight > help with fires > idle at the seat), `ShipTurret` (dorsal gun, leads targets, powered by the weapons conduit, only fires while someone sits in the gunner seat), captain hotkeys **R** fix, **G** turret, **P** cycle power split (balanced/engines/weapons), HUD CREW line, turret barrel visual. Tests: `tests/unit/crew_brain_test.gd` (fire in own room and through two doors, repair to full, reactor restart/vent, turret kill, unmanned turret silent, orders outrank scores, 10-minute no-flip-flop soak).
  - Limits: crew repair anywhere at the engine station (no part items yet), crew fight fires only inside the ship, the turret has no sound/muzzle flash, all numbers untuned, the player cannot sit in the gunner seat (still "not connected").
- **N7 done**: typed objectives in `ProgressTracker` (discover / clear_outposts / flag / land_on / have_item / orbit_of) with the Mayday mission as steps 4-7 of the story: arriving at Selene springs an ambush (raider via `EnemyDirector.spawn_ambush`, next hit on the ship forced to burn the engine coupling: engines hit, engineering fire, engines capped at 60 % until repaired with a new part) and pins a beacon 6 km below the arrival point (`PoiPlanner.pin_beacon`); its crate holds the **engine coupling**, installed at the engine station (F), which lifts the cap; then return to orbit above Aurelia. Save v11 (+ v10->v11 objective shift, fixture `v10_crew_hurt`). Tests: `tests/scenario/slice_scenario_test.gd` (ambush -> damaged landing with crew fighting fire and turret killing the raider -> coupling -> install -> takeoff, saves resumed at two beats, state legal), `tests/unit/mayday_test.gd`. Real scene: `tools/slice_check.gd` (jumps to Selene, checks raider spawns, beacon pinned, engines hit).
  - Limits: the slice test feeds the frame id and places the player at the crate (transfer and walking are tested elsewhere); no authored dialogue; the ambush has one raider; the beacon is a plain beacon prop; never played by a human.
- **N0 done (partly)**: `tools/perf_run.gd` now reports draw calls, primitives, physics/script time and memory and takes a `WxH` argument; results in `tests/perf/results.md` (1920x942 only: the display is 1080p, so no true 1440p number). Also fixed the pause menu freeing its reused status label.
- **N8 done (small)**: wall screens at the reactor panel (green to red with core heat, dark when tripped) and engine station (red to green with engine health), fire smoke particles, per-room lights and red fire lighting (from N4). Not done: sunset/atmosphere scattering, reactor hum audio, exterior silhouette, any CC0 art kit (needs your go-ahead and ATTRIBUTION rows). Interior perf: avg 10 ms, 296 draw calls (`tools/interior_perf.gd`).
- **Next:** human playtest of the slice (docs/PLAYING.md), then tuning from feedback; optional: atmosphere sunset shader, audio for alarms/hum, a second hostile at the ambush, a crew-usable gunner seat for the player. Human playtest of the slice still owed; see docs/PLAYING.md (add the new keys R/G/P and the Mayday mission there).
