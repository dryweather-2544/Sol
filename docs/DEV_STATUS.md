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
1. Terrain material masks (M7); POI interiors with a room-template expander (M9); interior layout editor / ship customization (M11).
2. A humanoid avatar + third-person on-foot camera (needs a vetted CC0 model or a hand-built primitive one).
3. Tuning from the user's play feedback: flight handling, landing assist, enemy damage/aim, oxygen/jetpack numbers.
4. M12: export build, 1440p/memory perf numbers, real (not simulated) long play test.
