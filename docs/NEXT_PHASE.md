# Sol — Next phase plan (Phase 2: "The ship is a place where things go wrong")

Written 2026-10-18 against `claude/eager-cannon-mrod2z` @ `3887850`. Draft for review; nothing here is implemented.
Labels: **[V]** verified in this session (how), **[I]** inferred from reading code/docs, **[?]** unknown.

---

## 1. Current state (audited, not taken from the status docs)

### 1.1 Verified facts

| Claim | Status | How checked |
|---|---|---|
| Latest commit `ae35dd2` | **[V] outdated by one**: HEAD is `3887850` (New-game button fix, 2 files). `ae35dd2` is checked out in the `Sol-wt` worktree (`open-work`). | `git log`, `git worktree list` |
| Headless suite: 164 tests / 64,144 assertions | **[V] true**: `files 39 | tests 164 | assertions 64144 | failures 0`, 40 s. Exit prints 4,892 leaked ObjectDB instances + 38 resources in use (warnings, exit 0). | ran `tools/run_tests.sh` |
| Automated playthrough completes the loop | **[V] true, with caveats**: `PLAYTHROUGH OK` in the real main scene. The bot sets the ship's orientation directly during descent (not via flight controls), and spends **13 frames** outside before walking back in. It proves transitions, not exploration or hand-flying. The headless `full_loop_scenario_test` walks 50 m outside. | ran `tools/playthrough.gd`, read its source |
| "M0–M12 completed" | **[V] false for M12**: export blocked (no export templates), 1440p/memory never measured, no real 2-hour play test. M7 partial (no sunset/scattering). | `docs/MILESTONES.md` |
| Milestones tagged | **[V] no tags exist** although the rules require `m<N>-complete`. | `git tag` (empty) |
| `main` contains the game | **[V] no**: `main` = `7e6d95b` (research only). All 30 game commits are on `claude/eager-cannon-mrod2z`. | `git branch -vv` |
| Manual checks | **[V] none ticked**; DEV_STATUS: "no feedback received yet". Nobody has hand-flown, walked, or listened to the game. | MILESTONES, DEV_STATUS |
| DEV_STATUS "Known issues" | **[V] stale**: says no avatar/audio/menus and props without colliders; code has `humanoid_avatar.gd`, `audio_service.gd`, `pause_menu.gd`, and solid-prop push-out in `game_session.gd:366`. | grep/ls |
| Hardware | **[V]** Apple M4, 17,179,869,184 bytes (16 GB). Godot `4.7.2.stable.official.ed1daf0bf`, Metal 4.0 Forward+. | `sysctl`, Godot banner |

### 1.2 What exists and works together [V by tests + playthrough; I for the "how"]

- **Space ↔ planet ↔ foot ↔ interior loop**, continuous frames, no teleports (`GameSession`, ADR 0003 ship-local walking).
- **Flight**: `PilotCommand` → `PilotController` → `FlightModel`; gears DOCK/COMBAT/CRUISE; AI pilots use the same command.
- **Planets**: 5 bodies + star, CPU height function, quadtree LOD, height-query contact (ADR 0002), vertex-colour masks.
- **Interior**: 3 rooms (cockpit, cabin, airlock) on one deck, ~13 m ship; airlock with pressure, walkway, one pilot seat, repair panel, workbench.
- **Survival/combat/progress**: hull scalar + impact/reentry damage, suit O2 + jetpack, fuel scalar, ship gun + pistol, guard ships + drones at outposts, 5 items, 4 upgrades, 5 hard-coded story objectives, save v8 with migrations from v1.
- **Size** [V]: 86 GDScript files in `src/`, ~6.6k lines. No `assets/`, no `addons/`, no `.tres` content — every mesh is a primitive, every table is in code.

### 1.3 Stubs, placeholders, unverified

| Area | State |
|---|---|
| Visuals | All primitives. Atmosphere rim + gradient sky; no scattering/sunset; no textures. Never judged by a human. |
| Audio | Synthesised cues; never heard by a human. No music. |
| Feel | Flight, landing assist, walking, camera, combat difficulty: **unjudged** (no human input). |
| Crew | **None.** `GameSession.ACTOR := &"player"` — one actor, one seat, one interior body, hard-wired. |
| Ship systems | Hull and fuel are single floats. No power, heat, subsystems, shields, fire, per-room atmosphere (only the airlock has pressure). |
| Missions | 5-step linear checklist in `ProgressTracker`; no mission data, no events/emergencies. |
| Perf | Measured only at 1152×648: worst frame 23 ms (43 fps) during chunk streaming, p95 ≈ 12.6 ms. 1440p, memory, draw calls, physics time: **not measured**. |
| Release | No export build (templates not installed). |

---

## 2. The three biggest gaps

1. **The PULSAR half does not exist.** The ship is a vehicle with a health bar, not a system-of-systems. No power/heat trade-offs, no subsystems, no fire, no stations — so there is nothing to *do* inside the ship except walk to the seat.
2. **Nobody else is aboard.** Crew roles need multiple actors; the session director is built around exactly one. This is an architectural gap, not a content gap.
3. **Nothing makes a moment.** The game has a loop but no situations: objectives are a checklist, combat is "guards at outposts", and nothing ever goes wrong *inside* the ship. Combined with placeholder art and zero human feel-testing, there is not yet anything that shows what Sol *is*.

(Visual quality is real but fourth: it can be fixed on top of a stable layout; it cannot be fixed before one.)

---

## 3. What to prioritise, in order

1. **Ship systems & engineering first** (power, heat, subsystems, fire). It is the identity gap, it is pure logic that tests headless, and it reuses `ShipSystems`, `ShipDamage`, `ShipUpgrades`, `SuitState`, `Portal`.
2. **Then a bigger walkable ship and stations** — systems need rooms to live in; this is where Rodina's walkable ship and PULSAR's stations meet.
3. **Then AI crew** (single-player co-op: you are captain/pilot; AI fills engineer and gunner). Real netcode is *not* in this phase (see risk R1).
4. **Then one authored mission** that forces all of it to interact (the vertical slice).
5. **Then a presentation pass scoped to the slice's spaces** (ship interior, alert lighting, one landing site). Art earlier would be redone when the ship layout changes in step 2.

Diegetic feedback (alarm light, warning sound, HUD line) ships *with* each system milestone, not in the art pass — feedback is gameplay.

---

## 4. Vertical slice: "Mayday on Selene" (target 10–15 minutes)

You captain a small crewed ship. Two AI crew: **Engineer** and **Gunner**.

1. **Orbit of Aurelia.** A distress beacon is received from Selene (vacuum moon). You walk to the cockpit, sit, plot the target (existing nav target + warp gating).
2. **Ambush on approach.** One guard ship (existing `AIPilotSource`) intercepts. The Gunner mans the turret seat; you fly. You choose a power split at the reactor (or order the Engineer to): **Engines / Weapons / Life support**.
3. **Something breaks.** A hit damages the engine subsystem and starts a fire in Engineering. Fire spreads through open doors and burns room oxygen. The Engineer fights it (or you do — stand up, walk there, extinguish). Thrust is reduced until repaired; the reactor runs hot if you over-draw.
4. **Damaged landing on Selene.** Reduced thrust makes the landing hard but possible. Suit oxygen matters outside (existing).
5. **On foot to the derelict.** Walk to the beacon wreck (existing POI depot, placed deterministically at the beacon), retrieve an **engine coupling** from a crate.
6. **Repair and leave.** Back aboard, install the part at the engine station; thrust restored. Take off, return to Aurelia orbit. Mission complete; save.

Proves: seamless space→planet→foot→ship (Rodina), functional systems + engineering + emergency + crew roles + mission (PULSAR), on the *same* ship you walk around. Explicitly **out**: shields, sensors/science, missiles, boarding, galaxy, economy, multiplayer.

---

## 5. Milestones (each independently testable; Sonnet-sized)

Rules carried over from MILESTONES.md: all earlier tests stay green; run `tools/run_tests.sh` and quote the real result; "not run" if not run; one milestone per commit series; save version bumps come with a migration and a fixture.
**Human playtesting never blocks a milestone.** Each milestone lists an automated check (blocking) and a "look at it" step (non-blocking, for Ariel when convenient).

### N0 — Baseline and truth (small, do first or in parallel)
- **Deliverable:** `tools/perf_run.gd` also records `Performance.MEMORY_STATIC`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `TIME_PHYSICS_PROCESS`, and accepts a resolution arg; a 2560×1440 row in `tests/perf/results.md`. DEV_STATUS "Known issues/Implemented" corrected to match the code.
- **Acceptance:** results.md has 1440p frame time + memory + draw calls; DEV_STATUS no longer claims avatar/audio/menus/prop collision are missing.
- **Tests:** existing suite green.
- **Inspect:** read results.md.
- **Needs Ariel (non-blocking):** merge `claude/eager-cannon-mrod2z` → `main`, and whether to add `m0..m11-complete` tags.

### N1 — Reactor, conduits, heat (pure logic, not yet wired)
- **Deliverable:** `src/ship/ship_power.gd` (`RefCounted`): reactor output, 3 conduits (ENGINES, WEAPONS, LIFE_SUPPORT) with 0..1 limits, per-consumer request, heat in/out, coolant reserve, safety shutdown + restart. Model per PULSAR `05` §10.1–10.2 (formulas are a clean-room proposal; tune, don't copy numbers). Constants in one place.
- **Acceptance / tests** (`tests/unit/ship_power_test.gd`): delivered ≤ limit × output ≤ output for random inputs (1,000 seeded cases); temperature rises monotonically under constant over-draw and falls with coolant; shutdown at threshold zeroes output; restart only below the restart threshold; same inputs → same state after 10,000 ticks.
- **Inspect:** one debug-overlay line (`PWR E/W/L  T°  coolant`) fed by a `ShipPower` instance owned by `ShipSystems` but affecting nothing yet.

### N2 — DONE. Subsystems and consequences (wire power + damage into flight/weapons)
- **Deliverable:** subsystem health (ENGINES, WEAPONS, REACTOR, LIFE_SUPPORT) in `ShipSystems`. Incoming hull damage is split into a subsystem by hit direction/room. Effects: engine power×health scales thrust/acceleration; weapon power×health gates fire rate; reactor health scales output; life support drives cabin O2 (N4). Existing repair panel repairs the most-damaged subsystem. Save v9 + migration + v8 fixture.
- **Acceptance / tests:** flight replay with engines at 50 % reaches ≤ 55 % of the baseline speed change; weapons at 0 never fire; v8 fixture loads with full health; save round-trip preserves subsystem health and power state; full_loop + playthrough still pass.
- **Inspect:** debug overlay; damage the ship with a debug key and fly.

### N3 — DONE. Ship layout v2 and stations (Opus review of R2/R3 first)
- **Deliverable:** `InteriorLayout.player_ship()` grows to ~6 rooms on one deck: cockpit, corridor/cabin, engineering (reactor), turret room (gunner seat), cargo, airlock. Stations become authored interact points with roles (`reactor_panel`, `engine_station`, `turret_seat`, `extinguisher_locker`). `ShipVisuals` already builds from the layout; exterior hull, ground-contact points, walkway and `ship_hull_collision` follow the new footprint.
- **Acceptance / tests:** room graph is connected through portals (BFS test); every station point is walkable and reachable from the pilot seat; `airlock_invariant`, `interior_moving`, `transition_fuzz`, `full_loop`, `frame_switch` pass unchanged; playthrough waypoints updated and `PLAYTHROUGH OK`.
- **Inspect:** `tools/screenshot.gd inside` at each station (add the coordinates to a list in the tool); one top-down frame.

### N4 — DONE. Stations you use + fire + room air
- **Deliverable:** reactor panel UI (reuse the `WorkbenchMenu` pattern): set conduit limits, vent coolant, restart reactor. Per-room fire (seeded ignition from damage), spread only through open portals, burns room O2 and damages the subsystem in that room; extinguisher item (hold F). Per-room O2 generalises the airlock pressure; a player in a low-O2 room drains suit O2 (existing `SuitState`). Alert feedback: red room light + synth alarm + HUD line.
- **Acceptance / tests:** closed doors contain fire; fire in a sealed room stops at O2 = 0; extinguishing clears it within the stated time; ignition is deterministic per seed; all mutations go through `ShipSystems.request_*(actor_id, …)` (see R1) and return a result; save round-trip mid-fire.
- **Inspect:** screenshot of engineering on fire; overlay per-room O2/fire.

### N5 — DONE. Crew bodies (multi-actor session; Opus ADR R2 first)
- **Deliverable:** N crew actors inside the ship, each with posture/location like the player (`PlayerState` per actor), reusing `InteriorBody` and `HumanoidAvatar`. Path = BFS over rooms + door waypoints (the layout is rectangles and portals; no navmesh needed). Crew open doors via the same request API, take seats, stand at stations. Crew stay aboard (ship-local), so frame switches don't touch them.
- **Acceptance / tests:** a crew member reaches every station from every room in ≤ N s; doors never close on anyone; airlock invariant holds with crew (extend the 10,000-step fuzz); seat contention player vs crew resolves to exactly one; `transition_fuzz` with 2 crew; save/load restores crew positions.
- **Inspect:** screenshot inside showing two crew at stations.

### N6 — Crew roles, orders, turret
- **Deliverable:** small utility AI (`PULSAR 10` §8: score a fixed goal list, act at 5–10 Hz, not 60): Engineer goals = extinguish, repair worst subsystem, keep reactor under temperature (auto power policy); Gunner goals = man turret, shoot the nearest hostile. A turret weapon on the ship aimed independently (reuse `Weapon` + `ProjectileSim` + `AIPilotSource` lead-aim maths). Captain orders via hotkeys: power preset (Engines/Weapons/Balanced), "fix X", "man turret". Overlay shows each crew's goal + score.
- **Acceptance / tests (headless scenarios):** fire in engineering → engineer extinguishes it within T s; engines at 30 % → repaired within T s; gunner destroys a scripted target drone within T s; an order overrides the utility choice until done; no goal oscillation (goal changes ≤ K per minute in a 10-minute soak).
- **Inspect:** overlay + screenshot; a short real-scene run.

### N7 — Mission data + the slice
- **Deliverable:** generalise `ProgressTracker` into typed objectives (REACH_BODY, REACH_POI, RETRIEVE_ITEM, INSTALL_PART, RETURN) driven by a small data dict; keep the existing 5-step story as one mission. Author "Mayday on Selene": beacon POI forced at a fixed Selene site, scripted ambush via `EnemyDirector`, a guaranteed engine-damage + engineering fire on first hit, the coupling item, install at `engine_station`. Save v10.
- **Acceptance / tests:** `slice_scenario_test` (headless): scripted pilot + scripted player + AI crew complete the mission; ends in a legal state; no teleports; save/load at each beat resumes. Existing story mission still completes. `tools/playthrough.gd slice` passes in the real scene.
- **Inspect:** playthrough log + `tools/screenshot.gd` at each beat (5–6 images) committed to `tests/perf/` or a `docs/slice_shots/` folder.

### N8 — Presentation pass for the slice spaces
- **Deliverable:** interior lighting per room (non-shadowed omni lights; ≤ 4 shadowed), emissive station screens, alert-state lighting, fire particles, reactor hum tied to heat, exterior silhouette improved. Atmosphere sunset/scattering. Optional CC0 kit (Quaternius/Kenney, already named in ARCHITECTURE §13) — **only with Ariel's go-ahead and an `ATTRIBUTION.md` row per file**.
- **Acceptance:** perf at 1440p within budget (≥ 60 fps p95, worst frame noted) on the slice playthrough; screenshot set regenerated.
- **Inspect:** the screenshot set — this is the first milestone where Ariel's eye genuinely matters, but it still doesn't block.

### Human playtest track (parallel, never blocking)
Playable builds after **N2** (damaged flight), **N4** (fire inside), **N7** (the slice). Feedback becomes tuning tasks in a `docs/TUNING.md` queue that Sonnet works between milestones. One cheap high-value ask now: 15 minutes with `docs/PLAYING.md` **before N3**, because N3 fixes walking scale and room sizes.

---

## 6. Risks that need Opus-level reasoning before implementation

| # | Risk | Why it is hard | Decide before |
|---|---|---|---|
| **R1** | **Single-player AI crew vs. networked co-op.** **Decided by Ariel 2026-10-18: AI crew this phase; keep the `request_*(actor_id)` seam so netcode stays possible.** The seam sits on `ShipSystems` (N4); `ShipPower` (N1) is owned logic behind it. | PULSAR's identity is human co-op. Retrofitting Godot multiplayer onto floating origin + per-peer `WorldPos` + a `GameSession` that mutates state directly is expensive, and gets more expensive with every system added. Recommendation to evaluate: no netcode this phase, but every ship mutation goes through `request_*(actor_id, …) → result` on one owner and one tick order (the seam a host-authoritative layer would use). Opus should confirm that seam is enough or say what else must be fixed now. Ariel decides whether online co-op is in scope at all. | N1 (API shape), hard gate before N4 |
| **R2** | **Multi-actor `GameSession`.** | `Mode`, `interior_body`, `exterior_body`, seats and authority are per-player singletons. Crew needs per-actor posture/location, and the player can be outside while crew stay aboard. A wrong split leaks into saves (v11+) and the fuzz tests. Needs an ADR. | N5 (ADR can be written during N1–N4) |
| **R3** | **Layout v2 vs. ADR 0003.** | A bigger ship moves ground-contact support points, walkway/ramp fit, hull collision for on-foot, landing on slopes, and the airlock's place in the exterior. Is single-deck rect-room still enough (turret placement, engineering size)? | N3 |
| **R4** | **Save schema for dynamic state.** | Fires, crew goals, reactor temperature, mission beat: what is saved vs. recomputed, and autosave must never land mid-emergency in an unrecoverable state (today autosave is suppressed only mid-sit). | N2 (first bump) |
| R5 | Ship simulation while the player is away (on foot 1 km out, or in another frame). Keep ticking? Freeze? Fire spreading while you explore is dramatic but can feel unfair. Design call, cheap to decide. | N4 |

---

## 7. Performance on Apple M4 / 16 GB with Godot 4.7.2

- **Measured [V]:** 1152×648, scripted descent: p95 ≈ 12–13 ms, worst 23 ms (chunk upload). Average pinned at 10 ms (100 fps cap). Nothing else measured.
- **Unknown [?]:** 1440p cost, process memory, draw calls, physics time. N0 measures them before anything is added.
- **Expected cost of this phase [I]:** power/fire/subsystems are a few hundred float ops per tick — negligible. Crew AI at 2–3 actors and 5–10 Hz decisions is negligible in GDScript. The real risks are rendering: shadowed omni lights in a multi-room interior (keep ≤ 4 shadowed), transparent fire/smoke particles, and any switch to SDFGI/volumetric fog — none of these have been measured on this machine, so N8 gates them on a 1440p perf run rather than guesses.
- **Memory [I]:** 16 GB unified memory is shared with the GPU; the 4 GB process budget in ARCHITECTURE §11 is realistic for primitives + a CC0 kit, but unverified.
- **Budget rule (existing):** > 15 % regression on the perf scenario blocks the milestone; add the slice playthrough as a second perf scenario at N7.

---

## 8. Reuse map (don't rewrite these)

| Need | Reuse |
|---|---|
| Station/menu UI | `WorkbenchMenu`, `InventoryMenu` pattern |
| Room air | `ShipSystems.airlock_pressure` logic → per room |
| Damage | `ShipDamage`, `ProjectileSim` (teams, swept hits), `ShipUpgrades` multipliers |
| Crew bodies | `InteriorBody`, `HumanoidAvatar`, `PlayerState`, `SeatManager` (already multi-actor) |
| Turret aim | `AIPilotSource` lead-aim |
| Ambush | `EnemyDirector`, guard ships |
| Wreck to explore | `PoiBuilder`/`PoiBuilding` depot rooms + crates + `LootTable` |
| Mission | `ProgressTracker` (generalise, don't replace) |
| Feedback | `AudioService`/`SoundSynth`, `DebugOverlay` |
| Checks | `tools/playthrough.gd`, `tools/screenshot.gd`, `tools/perf_run.gd`, `soak_test` |

Not doing: content in `.tres` (ARCHITECTURE asks for it, but code tables work and conversion buys nothing for the slice), CameraRig unification, interior layout editor, shields, sensors/science, boarding, galaxy, netcode.

---

## 9. Recommended first task for Sonnet

**N1 — `ShipPower` pure logic + tests + one overlay line.** Branch `n1-ship-power` from `claude/eager-cannon-mrod2z` (or `main` once merged).

1. Read PULSAR `05_SHIP_SYSTEMS_AND_POWER.md` §1, §2, §9, §10 (path: `~/Documents/Deepseek workspace/pulsar-research/pulsar-reference/`). Concepts only; no numbers, names or text copied.
2. Write `src/ship/ship_power.gd` (`class_name ShipPower extends RefCounted`): conduits ENGINES/WEAPONS/LIFE_SUPPORT, `set_limit(conduit, 0..1)`, `set_request(conduit, units)`, `delivered(conduit)`, `temperature`, `coolant`, `vent_coolant()`, `is_shut_down()`, `request_restart() -> String`, `update(delta)`. Mutating calls return a result string ("" = OK) like `ShipSystems.toggle_*`.
3. Write `tests/unit/ship_power_test.gd` with the five tests listed under N1.
4. Own one instance in `ShipSystems` (ticked in `update`) and show one line in `DebugOverlay`. Change nothing else.
5. `tools/run_tests.sh`; quote the summary line in the commit body. Expect 164 + the new tests, 0 failures.

Done when the suite is green and the overlay line shows numbers in a running game. It needs no Opus decision (R1 only constrains the *API shape*, which step 2 already follows) and nothing it adds can break the loop.
