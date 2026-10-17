# Sol — development status

Read this first when resuming. Keep it short and current; update it with every milestone commit.

## Where things are
- **Branches:** `claude/eager-cannon-mrod2z` (pushed; M0-M5 verified). `m6-solar-system` (worktree `../Sol-m6`) holds M6 (solar system, travel); merge it into the main branch once the suite is green.
- **Run tests:** `tools/run_tests.sh` (imports first; filter with `-- name_substring`). Godot: `~/Downloads/Godot.app/Contents/MacOS/Godot` (4.7.2).
- **Visual checks without a human:** `tools/screenshot.gd` (ground/interior/POI views) and `tools/travel_shots.gd` (interplanetary), both need a display.

## Implemented
M0 foundation, M1 planet/landing, M2 on foot, M3 ship interior + airlock + seat (full scripted loop passes headless), M4 saves (v3 now), M5 POIs + discovery, M6 solar system (see MILESTONES.md for per-item detail and what is *not* done).

## Tests (last actual run, Godot 4.7.2 on the Mac)
114 tests, 45,902 assertions, 0 failures (on `m6-solar-system`). Includes full_loop, interior_moving, transition_fuzz, airlock fuzz, frame_switch (planet -> open space -> moon -> landed).

## Never checked by a human
Everything about *feel*: flight handling, mouse sensitivity, camera lag, walking speed, interior size, the look of POI props up close. Only screenshots and headless tests have been used. The user said they would play it; no feedback received yet.

## Known issues / limits
- Placeholder graphics everywhere (primitives); no humanoid avatar, no audio, no menus (pause/settings), no sky/atmosphere beyond a simple gradient.
- Props (POIs) have no colliders: the player walks through buildings and wrecks.
- Ship hull nose/tail contact points only; wings are not solid. Landing on slopes steeper than ~25 deg is awkward.
- Parked ship in the air keeps drifting/falls (gravity applies while coasting).
- No 4 s atmosphere-entry timer, no reentry damage, no ship damage at all.
- `docs/ARCHITECTURE.md` text predates ADRs 0002-0004; the ADRs win.

## Next steps (in order)
1. Merge M6 branch into the main branch after a full green run; push.
2. M7 presentation: atmosphere/sky shader polish, terrain material masks, audio buses + cues, main menu / pause / settings, loading screen. (Audio needs licensed or self-made sounds: generate simple synthesized tones in code if no CC0 files can be vetted.)
3. M8 ship systems depth (pressure, suit oxygen + jetpack, damage/repair).
4. M9 POI interiors, items, inventory, loot.
5. M10 AI pilots (`AIPilotSource` through `PilotCommand`), ground NPCs, weapons with `team_id`.
6. M11 progression + warp; M12 release quality (macOS export, 2-hour soak, perf budgets).
