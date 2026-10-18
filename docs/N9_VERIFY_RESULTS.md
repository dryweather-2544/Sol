# N9 — Mac verification results

Date 2026-10-18. Branch `n9-art-audio` at `c968598` plus the uncommitted fixes listed below. Godot 4.7.2 (`~/Downloads/Godot.app`), Apple M4, Metal.
Nothing committed, nothing pushed, `~/Documents/Sol`, `main` and PR #1 untouched.

## Result in one line
After four fixes the game compiles, all 276 tests pass, 53/53 sampled sounds and 9/9 synth fallbacks play, the scripted playthrough completes, and
asset-on frame times match asset-off at both resolutions. Not yet done: a human look and listen in a live session (see Limitations).

## What failed first, and the fixes
| # | Failure | Cause | Fix |
|---|---|---|---|
| 1 | Game did not compile; the screenshot run looped forever (log grew past 17 MB); tests `audio_library_test` unloadable, `ship_materials_test` "two nacelles" got 0 | Untyped `:=` on Variant values in `ship_visuals.gd:82` (`rubber_floor`) and `audio_service.gd:240` (`room_center`); the test called `AudioLibrary.reset_warnings()` (it is on `AssetLibrary`) | typed both variables; test calls `AssetLibrary` |
| 2 | Every engine/ambience loop would end after ~4 s (`loop_end` 178496 instead of 441000 frames) | WAVs import as QOA (`compress/mode=2`); `AudioLibrary.frame_count` divided the compressed byte size | `frame_count` now `roundi(get_length() * mix_rate)`; checked that a looped QOA stream wraps past 10 s |
| 3 | `ship_screens_decals_test`: five decals "not in the catalogue" | two decals with the same name make Godot rename the node to `@Decal@N`; the test looked up by node name | decals carry `catalog_name` metadata; the test reads it (game behaviour unchanged) |
| 4 | `audio_library_test` AudioService test could never run | `tests/run_tests.gd` runs in `_initialize`, where the root is not yet in the tree | runner awaits one `process_frame` first |

Tooling fixes: `tools/audio_check.gd` no longer stops the long-lived loop players (the game starts each loop once, so every loop reported "not playing");
`tools/screenshot.gd` POI mode takes an optional yaw-away argument so the ship does not hide the POI; `tools/n9_verify.sh` now runs with its own `HOME`
(see next section) and exports `GODOT` first so `run_tests.sh` still finds Godot.

## Settings file side effect (needs your decision)
`user://` for this project is `~/Library/Application Support/Godot/app_userdata/Sol`, shared with any other build named `Sol`, including `~/Documents/Sol`.
At 15:09 `settings.cfg` there was saved with all five N9 switches `false` and Effects/Ambience volume `0.0`. A screenshot from that window shows the
Settings page open, so a click in a test window followed by Back saved the in-memory "assets off" state. That made the audio check read "silent" and
invalidated one picture. I did not edit that file; its content as found is `/tmp/settings_cfg_as_found.bak`. It still holds those values, so launching
the game normally will play with effects/ambience muted and the asset switches off until you reset them (Settings sliders do not cover the switches).
Delete the `[assets]` section and set the two volumes back to 1.0, or delete the file, to get defaults.

## Pictures (looked at)
Looked at: cockpit, cabin, engineering, reactor screen, cargo/airlock, chase, ship from outside, Aurelia ground, wreck and outpost (re-shot with yaw), starfield (re-shot looking up).
- Hull plating, floors (diamond plate, rubber in airlock/cargo), walls with rivets, door, nozzles, reactor screen with its decals: render as intended; no magenta, no missing textures.
- Wreck debris and outpost buildings show the new materials; starfield panorama renders (dense, soft stars versus the old sparse white dots).
- Terrain detail is not visible from the chase distances used; only seen as softer ground. Not judged up close.
- The automatic luminance check flags 10 of 13 pictures as above 0.70 (0.71 to 0.82). The assets-off pictures are as bright, so I treated the 0.70 limit as an
  untuned threshold; interior walls do look very light.
- The cockpit windscreen shows as a frosted panel with the assets on and off; it is not something N9 introduced. The assets-on one is green-tinted.
- Not resolved: the nozzle texture's exhaust-end orientation (known risk 3); the end discs are flat opaque cyan.

## Performance (p95 frame time, warm shader cache)
| | assets on | assets off | ratio |
|---|---|---|---|
| 1152x648 descent_low / ground / orbit | 12.15 / 12.29 / 11.86 ms | 11.53 / 11.43 / 11.99 ms | 1.05 / 1.08 / 0.99 |
| 1920x1080 descent_low / ground / orbit | 11.94 / 11.70 / 12.27 ms | 12.28 / 12.57 / 11.91 ms | 0.97 / 0.93 / 1.03 |
| interior + fire 1152x648 | 11.86 ms | 11.03 ms | 1.08 |
Gate was 1.15. Video RAM is 785 to 828 MB with assets on versus 163 to 202 MB off (about 5x) — fine on this Mac, unmeasured on weaker GPUs.
Draw calls 345-349 versus 343-347. An earlier 1920x1080 run showed 1.55 to 1.66; the three reruns afterwards (on, off, on) gave 11.3 to 11.9 ms for on and off alike.
I attribute that run to a cold shader cache (the first run in a fresh `HOME`), which fits but I did not isolate it further. Nothing was disabled by default.
Expect a hitch the first time shaders compile on a new machine.

## Gameplay checks (scripted real input; not a human session)
- `tools/pause_menu_check.gd`: 17 of 17 pass (title, new game, Esc, Settings, Back, Resume, quicksave, load).
- `tools/playthrough.gd`: `PLAYTHROUGH OK` — descent, landing, stand up, walk the ship (15 waypoints), outside and back in, sit in the pilot seat, take off, back in space.
- `tools/moving_ship_check.gd`: stand still, strafe at 3.0 m/s, seat hand-off to the chase camera behave; no walking-induced thrust.
- `tools/slice_check.gd`: the Mayday ambush spawns and the guaranteed hit lands.
- No `SCRIPT ERROR` in any of these logs.

## Limitations
- No human has looked at a live session or listened to the sound. The audio PASS means a player was playing on the right bus and the bus peak rose; dB offsets and the 1200 Hz interior low-pass are still untuned guesses.
- Terrain detail, the exhaust-end orientation and decal placement were only judged from still frames at a distance.
- The 1080p slowdown explanation (cold cache) is likely, not proven. The full 25-minute run was not repeated after the last script fix; the fixed script was confirmed with `--quick`
  (tests 276/276), and the full-run numbers above come from the run just before it, whose only fault was the tests stage failing to find Godot (since fixed).
- Deferred items from `N9_STATUS.md` are unchanged.

## Proposed commit (not made)
Nine modified source, test and tool files, this report, plus the Godot-generated `.wav.import` (about 130) and `.gd.uid` files that the first import created. Message:
"Fix N9 compile errors, QOA loop length and decal lookup; isolate verify runs from player settings". Waiting for your yes before committing or pushing.
