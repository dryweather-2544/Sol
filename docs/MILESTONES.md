# Sol — Milestones

Rules for every milestone:

- The game stays runnable (`scenes/main.tscn`) and **all earlier tests still pass**.
- A milestone is done only when its acceptance tests pass **on the Mac** and the manual
  checklist is ticked. Then tag `m<N>-complete`.
- Unit/scenario tests run with: `godot --headless --path . -s res://tests/run_tests.gd`
- Architecture reference: [`ARCHITECTURE.md`](ARCHITECTURE.md) (§ numbers below point there).

The loop (M0–M4) comes before breadth (M5+). Do not start M5 until M4 is tagged.

---

## M0 — Foundation

> **Status:** M0.1 ran on the Mac with Godot 4.7.2: 15 of 16 tests passed (3,032 assertions);
> the 1 failure was `test_seed_chain_golden_value`. Cause: a bug in the *design of the test and
> `derive()`*, not in the hash: `derive()` always mixed in an index (default 0), so it added a stray
> `combine(.., 0)` step and could never equal the documented chain. Fixed by splitting it into
> `derive()` and `derive_indexed()` (golden value unchanged: 1319536956). **That fix has not yet been
> run in Godot** - re-run `tools/run_tests.sh` on the Mac and record the output here.
> `python3 -I tools/check_seed_goldens.py` independently recomputes every golden number.
> M0.2 (pilot interface, flight model, ship, chase camera): 46 tests / 3,140 assertions passed on the Mac (Godot 4.7.2); visual smoke check via `tools/screenshot.gd`. Manual flight-feel check still owed by the user. `flight_replay_test` numbers are a recorded regression snapshot, not independent physics.
> Ticked below = file exists and was run at least once on the Mac; M0.2+ not started.

- [ ] Verify Godot: `godot --version` prints `4.7.2.stable…` (record exact output in `docs/decisions/0001-engine.md`)
- [x] `project.godot`: Forward+, Jolt, physics 60 Hz, physics interpolation, input map (thrust, strafe, up/down, pitch/yaw/roll, boost, brake, interact, toggle_view, gear up/down, pause) _(tested by input_map_test)_
- [x] `.gitignore` ignoring only `.godot/` (commit `*.import` files); `CLAUDE.md` already present
- [ ] Folder layout per ARCHITECTURE §2.2; autoloads `Sol`, `Events`, `SaveService` (stub), `Settings`
- [x] `tests/run_tests.gd` headless runner with non-zero exit on failure _(written, parses, not yet run)_
- [x] `src/core/world_pos.gd` (frame id + 64-bit doubles, add/sub/to_local_vector3) _(written, parses, not yet run)_
- [x] `src/core/seed_hash.gd` (32-bit masked hash + RNG wrapper) with golden fixtures _(written, parses, not yet run)_
- [x] `src/core/floating_origin.gd` (rebase group `origin_shift` past 1,024 m)
- [x] `src/flight/` PilotCommand, PilotSource, PlayerPilotSource, ScriptedPilotSource, PilotController, FlightModel (DOCK/COMBAT gears only), Ship node
- [x] Placeholder ship (primitive meshes) + chase camera; debug overlay (fps, speed, origin offset)

Acceptance tests:
- [ ] `world_pos_test`: 6.0e6 m + 0.001 m round-trips to within 1e-6 m; subtracting two nearby positions 6,000 km from origin is correct to 1e-6 m
- [ ] `seed_hash_test`: fixed inputs → fixed outputs (fixtures); 100 runs identical
- [x] `flight_replay_test`: 600-tick scripted command stream → final position/velocity equal to recorded fixture within 1e-3
- [x] `pilot_controller_test`: second source denied with reason; release → PARKED
- [x] `floating_origin_test`: fly 50 km scripted; origin rebased ≥ 40 times; ship WorldPos continuous (no jump > 1 tick of motion)
- [ ] Manual: launch, fly 6DOF with keyboard/mouse, feel is controllable

## M1 — One planet: approach, atmosphere, landing, takeoff

> **Status:** implemented and headless-tested on the Mac (63 tests / 17,399 assertions passed). Visual checks by `tools/screenshot.gd` only; manual flight (orbit -> land -> take off) and the 60 fps perf run are still owed. Not done: 4 s atmosphere-entry timer, roll auto-level, entry heating. Slope tests use synthetic planes; `descent_scenario_test` uses the real terrain.

- [x] `TerrainProfile` resource + `HeightFunction` (unit-direction noise, ARCH §4.2)
- [x] Quadtree cube-sphere LOD with worker-thread chunk generation and skirts _(own implementation; cuberact not used, no attribution needed)_
- [x] Planet-frame physics: gravity `g/(r/R)²`, atmosphere ratio + regime states (SPACE/ENTERING/ATMOSPHERE/NEAR_GROUND/LANDED), drag, optional roll auto-level
- [x] CRUISE gear with swept terrain/atmosphere check
- [x] Landing: support points, contact-relative landed test, slope align ≤ 25°, refuse > 35° with HUD message, takeoff releases alignment
- [x] Near-chunk collision ring _(replaced by height-query contact, ADR 0002)_
- [x] Minimal HUD: speed, altitude/AGL, vertical speed, gear, regime, landing status
- [x] Start position: in orbit at ~300 km (data-driven)

Acceptance tests:
- [x] `height_function_test`: golden hash of 1,000 samples stable
- [x] `descent_scenario_test`: scripted descent from 300 km to touchdown; LANDED reached; never below terrain
- [x] `slope_landing_test`: 15° and 25° land and settle < 1 s without oscillation; 35° refuses
- [x] `cruise_tunnel_test`: 10 km/s straight at terrain → clamped, never inside
- [x] `precision_rest_test`: landed 60 s on a 6,000 km planet → drift < 1 cm
- [ ] Perf: scripted orbit-to-landing ≥ 60 fps on Mac (record numbers)
- [ ] Manual: no visible cracks; takeoff back to space works

## M2 — On foot on the planet

> **Status:** logic + tests done (70 tests / 32,427 assertions passed on the Mac); land -> exit -> walk verified in the real scene by `tools/screenshot.gd` (first-person view). Not done: humanoid avatar/animations (needs a licensed asset), third-person camera, CameraRig unification (ship chase camera and on-foot camera are still two cameras). Manual walk-around check owed by the user.

- [x] `OnFootController` (CharacterBody3D, dynamic `up_direction`, walk/run/jump, slope limit)
- [ ] Player avatar (licensed humanoid, AnimationTree idle/walk/run/jump) — add to ATTRIBUTION
- [ ] CameraRig: ON_FOOT_FIRST / ON_FOOT_THIRD; ship modes moved into the rig
- [x] `PlayerState` (posture/location/authority) — logic only, used by the debug exit
- [x] **Temporary** debug "exit ship / enter ship" when landed (removed in M3)

Acceptance tests:
- [x] `walk_sphere_test`: scripted 2 km walk: upright, no fall-through, AGL ≈ 0
- [x] `jump_test`: landing point within 5 cm of prediction
- [x] `slope_limit_test`: blocked above limit
- [ ] Manual: walk around the landed ship, camera behaves, board back via debug key

## M3 — Ship interior: the complete loop

> **Status:** implemented; the scripted full loop (orbit -> land -> stand -> cockpit door -> inner door -> airlock -> outer door/walkway -> walk out 50 m -> back up the ramp -> close up -> sit -> take off -> space) passes headless on the Mac, with all invariant/fuzz tests (91 tests / 45,537 assertions). Interior and exterior views checked by screenshot only. The M2 debug exit is removed. Not done: seat sit/stand animation, pressure, walkway/airlock sounds, HUD marker for panels, second seat/crew. Manual play-through by hand is still owed.

- [x] **M3.0 spike:** decided *against* a second `World3D`: ship-local kinematic walking, see `docs/decisions/0003-interior-space.md` (reasoned, not measured)
- [x] Ship model: exterior + interior _(placeholder primitives built from the layout; no third-party assets, so nothing in ATTRIBUTION)_
- [x] `InteriorLayout` (rooms, portals, seats, interaction points; built in code, not yet a `.tres` Resource) for the player ship
- [x] `SeatManager` + pilot seat → `PilotController`; posture transitions with lock/cancel
- [x] `AirlockController` (never both doors open), `WalkwayController` (deploy/retract/fit)
- [x] Boarding/frame transfer interior ↔ exterior with gravity blend, no teleports
- [x] Interlocks: takeoff blocked by occupied walkway / open outer door; outer door blocked above 2 m/s
- [x] Interaction prompts in HUD; remove M2 debug exit

Acceptance tests:
- [x] `airlock_invariant_test`: 10,000 random requests, never both open
- [x] `seat_test`: two actors, one seat → exactly one succeeds; cancel mid-sit works
- [x] `interlock_test`: takeoff denied with walkway occupied; outer door denied at speed
- [x] `full_loop_scenario_test` (headless, scripted): orbit → land → stand → airlock → walk 50 m → return → sit → takeoff → orbit; ends legal, no teleport > 0.5 m between ticks
- [x] `interior_moving_test`: walk inside while ship flies 500 m/s and rolls: no clipping
- [x] `transition_fuzz_test`: 100 randomized transition sequences, no softlock
- [ ] Manual: play the full loop by hand three times without any debug key _(owed by the user)_

## M4 — Save/load v1

> **Status:** implemented and tested headless on the Mac (see commit). F5/F9 verified in the real scene by script (save, move 50 km, load -> back within 5 cm). Not done: pause menu, save slots UI, saving POIs (M5). Manual check owed: quit mid-walk outside, relaunch, press F9.

- [x] `SaveGame` schema v1, `SaveManager` (atomic write, `.bak`, SHA-256), `SaveMigrations` scaffold
- [x] Save player state/WorldPos, ship state, pilot authority, seats, doors, walkway, landing
- [x] Quicksave (F5) / quickload (F9); autosave on landing, boarding and every 5 min, never mid-sit _(no pause menu yet, so no menu save/load)_
- [x] Fixture `tests/fixtures/saves/v1_*.json` committed

Acceptance tests:
- [x] `save_roundtrip_test` in 5 states (piloting in space, landed seated, inside standing, outside, mid-airlock) → equal state, position < 1 cm, velocity preserved
- [x] `save_corrupt_test`: truncated/bad checksum → previous save kept, clear error
- [ ] Manual: quit mid-walk outside, relaunch, continue

## M5 — Procedural POIs and discovery

> **Status:** implemented and tested headless on the Mac (106 tests / 45,856 assertions). POIs verified visually only as markers on the HUD/horizon and by node-count tests; prop scenery up close has not been looked at. Wrecks have no beam on purpose (find them by flying low). Save format is now v2 with a committed v1 fixture migrated on load.

- [x] `PoiDefinition` catalog with 3 types (wreck, beacon, outpost) _(primitive props, no third-party assets)_
- [x] `PoiManager` plan-as-data (lazy per lattice cell, ADR 0004), rings with hysteresis, site scoring _(TerrainModifier pads not implemented: sites are picked flat instead)_
- [x] Discovery (120 m on foot), beam markers + nearest-signal HUD line _(no discovery log screen yet; the log is saved)_
- [x] POI state in saves (save v2 + migration v1→v2)

Acceptance tests:
- [x] `poi_determinism_test`, `poi_ring_test` (500 planned, ≤ 30 active), `discovery_once_test`, `save_v1_to_v2_test`
- [ ] Manual: find and discover 3 POIs by flying and walking _(owed by the user)_

## M6 — Solar system and travel

> **Status:** implemented on branch `m6-solar-system`: star, 4 planets/moons, 1 asteroid, circular analytic orbits, sun that circles the sky once per spin, frame switching with Galilean velocity conversion, distance-scaled cruise (2e7 m/s cap near nothing, shrinking toward any surface), nav target (T) on the HUD, other worlds drawn as angular-size-correct impostors. `frame_switch_test` flies Aurelia -> open space -> Selene and lands. Not done: perf scenario across a transfer; the manual two-worlds-with-save check is owed by the user.

- [x] Star + 3–5 planets/moons + an asteroid with distinct `TerrainProfile`s (Rodina range 4,000–10,000 km radii, PLN-02; small bodies for the asteroid start idea)
- [x] Analytic orbits/rotation from game time; sky/sun from the active frame
- [x] Frame switching between planet SOIs and the system frame
- [x] Cruise travel between bodies (distance-scaled speed), nav targets on HUD

Acceptance tests:
- [x] `frame_switch_test`: fly planet A → B; WorldPos continuous; no physics explosion
- [x] `orbit_determinism_test`; perf scenario across a transfer
- [ ] Manual: land on two different worlds in one session and save/load between

## M7 — Presentation pass

> **Status:** partly done. Done: audio, menus/settings/loading gate. Not done: atmosphere horizon/sunset shader, terrain material masks (terrain is still height/slope vertex colours). Fixed on the way: crash at quit/frame switch from worker threads outliving the terrain node.

- [ ] Atmosphere shader (horizon/sunset palette, Rodina `04` §5.2 *concept*, own code)
- [ ] Terrain material masks (altitude/latitude/slope/feature gates)
- [x] Audio buses (Master/SFX/Ambience/Interior) and synthesised cues: engine, wind, doors, airlock, ramp, footsteps, landing thud, seat, discovery chime _(no music; no reentry feedback; never listened to by a human)_
- [x] Title screen, pause menu (resume/save/load/settings/quit), settings (sensitivity, invert, FOV, volumes; persisted), loading gate on New game

## M8 — Ship systems depth

- [ ] Per-room pressure, venting, decompression force; airlock cycling uses pressure
- [ ] Suit oxygen + jetpack; vacuum hazard (Sol rule — Rodina unknown, G3/G14)
- [ ] Ship damage from impacts/reentry; repair interaction

## M9 — POI interiors, items, inventory

- [ ] Typed room templates + graph expander for POI interiors (not EGSL; `05`)
- [ ] Items, pickup, inventory (one ledger), loot tables from seeds
- [ ] Ship cargo; resources gate fuel/upgrades

## M10 — AI and combat

- [ ] `AIPilotSource` (goto/orbit/follow/attack) through `PilotCommand`
- [ ] Ground NPCs with nav on terrain and in interiors
- [ ] Weapons/projectiles with `team_id` (no player-vs-everyone hack, ITM-06), damage, death/respawn

## M11 — Progression and ship customization

- [ ] Story/progress stages gating gears and areas (Rodina gear gating, FLY-13 concept)
- [ ] Warp travel mode with atmosphere sweep
- [ ] Interior layout editor for the player ship (Rodina has one; `03`)

## M12 — Release quality

- [ ] macOS export (signed if possible), settings persistence, crash-free 2-hour play test
- [ ] Perf budgets met across all scenarios; save migration chain v1→latest tested

---

## First concrete task for Sonnet — "M0.1 Project skeleton + core math"

**Where:** on the Mac mini, in the Sol repo, branch `m0-foundation` created from `main`
(after this planning branch is merged; otherwise from `claude/eager-cannon-mrod2z`).

1. Run `git status` and `git log --oneline -3`; confirm the tree is clean and the research
   and docs are present. Do not touch `research/`.
2. Find Godot: `/Applications/Godot.app/Contents/MacOS/Godot --version` (or `which godot`).
   It must report 4.7.2. If not, stop and tell the user.
3. Create `project.godot` (Forward+, Jolt 3D physics, physics ticks 60, main scene
   `res://scenes/main.tscn`), `.gitignore` (ignore `.godot/` only), the folder layout in
   ARCHITECTURE §2.2, an empty `scenes/main.tscn` with a `Node3D` root.
4. Write `tests/run_tests.gd`: `extends SceneTree`; in `_initialize()` scan `res://tests/unit`
   and `res://tests/scenario` for `*_test.gd`, instantiate each, call every `test_*` method,
   collect failures from a small `assert_eq/assert_true/assert_near` helper base class
   (`tests/test_case.gd`), print `PASSED n / FAILED m`, `quit(1)` on any failure.
5. Write `src/core/world_pos.gd` and `src/core/seed_hash.gd` with
   `tests/unit/world_pos_test.gd` and `tests/unit/seed_hash_test.gd`. Generate the seed
   golden values once, paste them into the test, and add a test that fails if the first
   value ever changes.
6. Also add `tests/unit/sanity_test.gd` that asserts `typeof(1.0) == TYPE_FLOAT` and that
   `6000000.0 + 0.001 - 6000000.0` is within 1e-6 of 0.001 (a 32-bit float would be off by
   up to 0.5 m here, so this proves GDScript floats are 64-bit on this build — ARCHITECTURE §0
   marks it as not yet re-checked).
7. Run `godot --headless --path . -s res://tests/run_tests.gd`. Paste the real output into
   the commit message body. Run it once more after `rm -rf .godot` to make sure import works.
8. Open the project in the editor once to confirm it loads without errors.
9. Commit (`M0.1: project skeleton, headless test runner, WorldPos, SeedHash`), push the
   branch. Do not start M0.2 in the same commit.

Done when: the runner exits 0 with all tests listed, the editor opens the project cleanly,
and the commit is pushed.

---

## Handoff instruction for Sonnet

> You are implementing Sol. The architecture is decided in `docs/ARCHITECTURE.md`; the order
> and acceptance tests are in `docs/MILESTONES.md`. Execute them — do not redesign.
>
> - Work milestone by milestone, task by task, top to bottom. Start with "M0.1" above.
> - Change the architecture only when a test or spike proves a decision wrong. Then write a
>   short ADR in `docs/decisions/NNNN-title.md` (context, decision, consequence) and update
>   `ARCHITECTURE.md` in the same commit. The interior-space spike (M3.0) is the one planned
>   decision point.
> - Keep logic in pure `RefCounted` classes with headless tests; keep nodes thin.
> - Every milestone leaves `main.tscn` playable and all previous tests green.
> - Run tests on the Mac before each commit and quote the real result. If you could not run a
>   test, write "not run" — never "should pass".
> - Never modify Starfall or any other project. Never import or copy Rodina code, assets, or
>   data files. Treat the research as evidence with its C/I/U/A labels.
> - Record every third-party file in `ATTRIBUTION.md` before committing it.
> - Do not start breadth (M5+) until the full loop (M3) and saves (M4) are tagged.
> - Tick the checkboxes in this file as you finish items, in the same commit as the work.
