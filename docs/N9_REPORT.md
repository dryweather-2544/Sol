# N9 — art and audio integration: report

Branch `n9-art-audio` (from `origin/n1-ship-power` @ `ab3cdac`, the head of PR #1). **Unpushed. No PR. `main` and PR #1 untouched.**
Assets come from Sol-Assets branch `a6-b2-combined` (commit recorded in `assets/sol/SOURCE.txt`). Every Sol-Assets manifest row is still `review`.

## The important caveat
This was written in a cloud session with **no Godot, no screen and no speakers**. What was run: `gdparse` (syntax) on every changed `.gd` file,
`tools/asset_usage_check.py` (file integrity, hashes, "is every asset used by code"), and the report generator against a fake Godot.
**Not run at all:** `tools/run_tests.sh`, any picture, any sound, any frame-time measurement. Nobody has seen or heard any of this in the game.
Run `tools/n9_verify.sh` on the Mac first (`--quick` for tests only).

## What was done (one commit each)
| Step | Commit | Result |
|---|---|---|
| S1 scaffold | `d66da5d` | copy tool, `AssetLibrary` (load with fallback, warn once), five switches in `GameSettings` |
| S2 ship | `35b3091` | floors/walls/ceilings/doors/console/gear/glass/hull/nozzles use the textured materials, exhaust disc, interior reflection probe |
| S3 screens + decals | `7c11af9` | station + nav screens, 14 fixed decals, hidden scorch marks that show after a fire; N8 screen offset bug fixed |
| S4 audio P0 | `85cd993` | `AudioLibrary`, `AlarmSchedule`, new buses, engine/rumble loops, 16 voices, `cue_started` signal |
| S5 audio P1 | `fd0800f` | remaining triggers (boost, gear, RCS, guns, door deny, seals, ramp, seats, steps, hull alarm, wind, jetpack, repair, hum, damage loop) |
| S6 terrain | `881a4dd` | detail shader, regolith / dry soil / fractured rock, slope weight, per-chunk tile offset |
| S7 POIs | `d7c06d2` | wreck, beacon, outpost, depot materials |
| S8 sky | `8cfb83b` | starfield panorama in the sky shader |
| Tooling + docs | `a50213c` | `tools/n9_verify.sh`, audio/picture checks, source + import tests, ARCHITECTURE/DEV_STATUS |

Observer-only edits to game code: `Weapon.shots_fired`, `GameSession.interaction_refused`. Nothing under `src/save`, no `project.godot` change,
no gameplay constant, height, collision or save-format change (save stays v11). `ChunkMesher` changed only the colour alpha (it is now the slope weight).

## The three failing screen-material checks
Not an asset fault. The lookdev project had never imported the textures, so `load()` of the `.tres` returned null and the checker printed ".tres missing"
although the file existed. Fixed in Sol-Assets (`cd98de2`): `validate_all.sh` imports first, and the checker now says "exists but failed to load".
The game side loads the same files through its own import (`tools/run_tests.sh` imports first), covered by `ship_screens_decals_test` and `asset_library_test`.
(Not confirmed under Godot in this session; the root cause was found by reading the code, so treat it as "very likely", not "proven".)

## Deviations from the brief (and why)
- **Ship-placed sounds are 2D loops scaled by distance**, not `AudioStreamPlayer3D`: a 3D listener set-up cannot be checked without Godot. No panning.
- **Terrain palette colours not converted from sRGB**: the game already writes them as linear vertex colours; converting would darken every world.
- **Helmet seal/unseal** play on the inside<->outside mode change, not at the outer door. **Strained breath** keys on oxygen only.
- **Interior low-pass** is 1200 Hz with samples (700 without), as the brief says; unheard.
- The alarm now repeats on the new schedule (2 s x3 then 8 s) even with samples off.
- Scorch decals appear only for rooms that burned in this session (not saved: saves may not change).

## Deferred (no trigger or menu hook; listed in `docs/N9_STATUS.md`)
`sfx_radio_open/close` (no radio system), extinguisher spray/empty, mayday loop, scan ping, crate open, derelict signal, menu move/confirm/back,
order acknowledgements, `sfx_int_relay_click`, `sfx_int_switch_press` (not in the brief's table), and the two `_primer` materials.

## Known risks (all unverified)
1. Decal orientation and position (math from geometry; `ship_screens_decals_test` checks only the basis maths).
2. Station screens were buried in the wall before; the 0.27 m offset is derived, not seen.
3. Exhaust-end orientation of the nozzle texture is unresolved in the asset notes; one look at the rear fixes it (`uv1_scale.y = -1`).
4. Terrain shader cost (about 24 texture reads per pixel within 250 m) is an estimate. If `tools/n9_verify.sh` shows a p95 breach, set `terrain_detail` default false in `GameSettings`.
5. dB offsets for every sound are first guesses.
6. First Godot import will create `.wav.import` and new `.gd.uid` files; commit them.

## Public repository
`dryweather-2544/Sol` is public. Pushing this branch would publish about 100 MB of generated binary assets (61 MB materials, 37 MB audio, 1.6 MB sky, 0.8 MB decals).
All are procedural "Sol original" (no third-party rows in `ATTRIBUTION.md`). Waiting for an explicit yes before any push.
