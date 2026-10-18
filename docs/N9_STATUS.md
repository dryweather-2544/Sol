# N9 — art and audio integration: status

Branch `n9-art-audio`, created from `origin/n1-ship-power` @ `ab3cdac` (the PR #1 head; `main` holds no game). **Unpushed; no PR.**
Plan: `docs/N9_BRIEF.md` in Sol-Assets (branch `a6-b2-combined`). Asset source: Sol-Assets `a6-b2-combined` (commit recorded in `assets/sol/SOURCE.txt`).
Every Sol-Assets manifest row is still `review`; nothing here approves anything.

**Authoring environment:** a Linux cloud session with no Godot, no display and no audio device. Nothing below was run under Godot unless a
row says so. What *was* run here: `gdparse` (syntax), `tools/asset_usage_check.py`, `tools/import_assets.py`. Everything else needs the Mac:
`tools/n9_verify.sh` runs it all and writes one report.

Deferred: sfx_radio_open, sfx_radio_close, mat_ship_paint_panel_primer, mat_hull_plating_primer, sfx_int_extinguisher_spray_loop, vo_radio_mayday_loop, sfx_scan_ping, sfx_item_crate_open

## Steps
| Step | Commit | What | Run here | Needs the Mac |
|---|---|---|---|---|
| S1 scaffold | see `git log` | copy tool, `AssetLibrary`, 5 settings switches, asset checker | gdparse, asset checker with planted faults | `tools/run_tests.sh` |
| S2 ship materials | see `git log` | floors/walls/ceilings/doors/console/gear/ramp/glass/wings use `assets/sol` materials (airlock + cargo floors rubber), nacelles use the nozzle + emissive exhaust disc, interior reflection probe | gdparse, asset checker (8 of 11 materials referenced, 0 integrity problems) | `tools/run_tests.sh` (`ship_materials_test`), V1-V9 screenshots, perf gate |
| S3 screens + decals | see `git log` | station screens use `mat_ship_screen_reactor`/`_generic` copies (offset fixed 0.42 -> 0.27: the N8 screens were buried in the wall), nav screen `mat_ship_screen_nav`, 14 fixed decals + a hidden scorch per hazard room that appears once the room burns | gdparse, asset checker | `ship_screens_decals_test`, V-screens screenshots (decal orientation and the wall offset are from geometry, NOT seen rendered) |
| S4 audio P0 | see `git log` | `AudioLibrary` (table of 30 ids, variants -> `AudioStreamRandomizer`, runtime loops), `AlarmSchedule` (fire > reactor > hull; 2 s x3 then every 8 s), buses UI/Ship/Suit/Radio, Interior low-pass 1200 Hz with samples (700 without), engine idle/thrust crossfade replaces `EngineVoice`, structure rumble replaces `WindVoice` inside, 16 one-shot voices with priority stealing, `cue_started` signal. Triggers: doors, touchdown soft/hard (hard at >= 6 m/s the frame before landing), engine start/stop, power down/up, airlock cycle, subsystem fail/restored, hull hit (ambush), O2 warnings, pickup, objective, discovery sting, footsteps (metal inside, regolith outside in vacuum), cabin air / reactor / fire loops, suit room tone + calm breath | gdparse, asset checker | `audio_library_test`, `tools/audio_check.gd`; **the dB offsets are untuned guesses, the 1200 Hz low-pass is unheard** |

S4 notes: 3D positioning (reactor, fire, doors) is S5; the reactor/fire/air loops are 2D on the Ship bus until then. The alarm now repeats on the new schedule even with samples off (it used to repeat every 2 s). New `.wav.import` and `.gd.uid` files will appear on the first Godot import on the Mac and need committing.
