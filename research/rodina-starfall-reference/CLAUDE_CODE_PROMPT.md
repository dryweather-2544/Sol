# Claude Code Prompt — Apply the Rodina Reference to Starfall

Copy the fenced prompt below into Claude Code. It assumes the reference library is at the absolute path shown and Starfall is at `/Users/arielbowyer/starfall`.

---

```text
You are Claude Code working on Starfall, a Godot 4.7.2 Forward+ space game at:
/Users/arielbowyer/starfall

A completed Rodina 1.6.2 static-analysis reference library is at:
/Users/arielbowyer/Documents/Deepseek workspace/rodina-starfall-reference/

READ FIRST, in this order:
1. 00_MASTER_INDEX.md
2. 08_STARFALL_IMPLEMENTATION_GUIDE.md
3. 09_SOURCE_EVIDENCE_INDEX.md
Then read only the subsystem report you need:
- 02_SPACESHIP_AND_PILOTING.md
- 03_INTERIORS_AND_AIRLOCKS.md
- 04_PLANETS_AND_TERRAIN.md
- 05_PROCEDURAL_CONTENT.md
- 06_AI_AND_NAVIGATION.md
- 07_DATA_FORMATS_AND_ASSETS.md
- 10_OPEN_QUESTIONS.md
- 11_QUALITY_CHECK.md (what was verified, what is inference)

CONTEXT AND CONSTRAINTS:
- Rodina was inspected read-only. Do not run Rodina, load its DLLs, or execute its Lua.
- Rodina code, models, textures, audio, fonts, and maps are proprietary. Do not import or copy them.
- Starfall already has working 6DOF flight (scripts/ship.gd), a kinematic on-foot pilot (scripts/pilot.gd), a walkable cabin with airlock/walkway (scripts/ship_cabin.gd), a chase/cockpit camera (scripts/chase_camera.gd), and a Cuberact chunked planet (addons/cuberact_planet). Preserve these. Do not rewrite them wholesale.
- The reference guide is additive and priority-ordered. The goal is to improve Starfall, not to clone Rodina.
- Never claim a Rodina behaviour is confirmed when the library marks it I (inferred), U (unknown), or A (absent).

YOUR TASK:
Implement the highest-priority improvements from 08, one milestone at a time. Do not skip ahead.

M0 — Baseline (no gameplay change):
- Read scripts/ship.gd, pilot.gd, ship_cabin.gd, chase_camera.gd, scenes/main.tscn, project.godot.
- Record a baseline: 10 s of representative flight input, a landing on a slope, and a walk from seat to exterior.
- Capture positions/velocities/screenshots or numbers as regression fixtures.

M1 — Shared pilot command interface:
- Add PilotCommand, PilotSource, PlayerPilotSource, PilotController.
- Make Ship consume a PilotCommand while preserving its existing _apply_thrust/_assist_landing/_apply_rotation/_collide_with_terrain math.
- Add a compatibility path when no controller is active.
- Add an AIPilotSource stub that can hold a target point and produce thrust/facing commands.
- Tests: replay baseline commands; positions/velocities match within tolerance; mid-flight source swap; parked behavior; control denial.

M2 — Player state and seating:
- Split the player's single Mode into posture (standing/sitting/seated), location (exterior/interior), and authority (none/pilot/ai/remote/passenger).
- Add Seat, SeatManager, and explicit transition methods with animation locks and cancel.
- Make the pilot seat the first Seat; add a passenger seat only after the pilot flow is stable.
- Tests: sit/stand cancel; two actors cannot occupy one seat; ship movement while seated; blocked exit point; camera/authority consistency.

M3 — Interior/airlock state:
- Add InteriorLayout, InteriorRoom, InteriorPortal, Occupancy, AirlockController, BoardingController, WalkwayController.
- Keep the current cabin working; move it behind the new data model with parity tests.
- Implement per-room pressure as a scalar; add venting/decompression force after the interlock has parity.
- Add takeoff interlocks: no takeoff with walkway occupied/outer door open; no outer-door opening while moving fast.
- Tests: both doors never open; no closing on an occupant; pressure does not leak through closed doors; save/load mid-airlock yields a legal state.

M4 — Landing controller:
- Add slope-aware support-plane alignment on gentle slopes, a max landing slope with clear blocking, and takeoff release.
- Preserve ground_gap() and existing collision; add probes/normals only as needed.
- Tests: 15/25/35 degree slopes, cliff edge, boulder, high-speed touchdown, takeoff immediately after landing.

M5 — Save/load:
- Add a versioned SaveGame/SaveManager with atomic write + backup + migrations.
- Save player mode/location, ship planet-local transform/velocity, seat/authority, door/pressure/walkway state, planet seeds, discoveries, and POI instances.
- Do not save every prop transform; regenerate from seeds unless the player moved it.
- Tests: roundtrip in all modes; corrupt file fails safely; save during transition defers; origin-shifted position survives.

Do not start POIs, crew AI, or networking until M1–M5 are stable and tested.

RULES OF ENGAGEMENT:
- Before editing a file, read it and state which existing behavior you are preserving.
- Cite an evidence ID or report section for each design choice.
- Prefer adapters/small new classes over rewrites of working systems.
- Add tests/regression checks with every milestone.
- Keep savegame, shader-cache, and compiled-script extensions distinct.
- Do not use Rodina .egm/.egi/.rsl/.egu/.egs files or assets.
- Do not use global randf/math.random for procedural content; use a stable per-POI seed and generation_version.
- If a Rodina behavior is engine-side or disabled, implement Starfall's own explicit behavior; do not assume it works.
- Keep changes reviewable: one milestone per branch/commit series, with a short summary of what changed and what was tested.

START:
Produce a short change plan for M1 only: files, classes, signals, data structures, integration points, tests, risks. Then wait for approval before coding.
```

---

## Notes for the human operator

- If Claude Code has no access to `/Users/arielbowyer/Documents/Deepseek workspace/`, copy `rodina-starfall-reference/` into the Starfall repo or a sibling directory and update the path in the prompt.
- If Claude Code asks for engine-side details, point it to `10_OPEN_QUESTIONS.md`; do not let it invent them.
- M1 is the gate. If flight-parity tests fail, stop and fix the adapter before touching seats/interiors.
