# N9 — art and audio integration: status

Branch `n9-art-audio`, created from `origin/n1-ship-power` @ `ab3cdac` (the PR #1 head; `main` holds no game). **Unpushed; no PR.**
Plan: `docs/N9_BRIEF.md` in Sol-Assets (branch `a6-b2-combined`). Asset source: Sol-Assets `a6-b2-combined` (commit recorded in `assets/sol/SOURCE.txt`).
Every Sol-Assets manifest row is still `review`; nothing here approves anything.

**Authoring environment:** a Linux cloud session with no Godot, no display and no audio device. Nothing below was run under Godot unless a
row says so. What *was* run here: `gdparse` (syntax), `tools/asset_usage_check.py`, `tools/import_assets.py`. Everything else needs the Mac:
`tools/n9_verify.sh` runs it all and writes one report.

Deferred: sfx_radio_open, sfx_radio_close, mat_ship_paint_panel_primer, mat_hull_plating_primer

## Steps
| Step | Commit | What | Run here | Needs the Mac |
|---|---|---|---|---|
| S1 scaffold | see `git log` | copy tool, `AssetLibrary`, 5 settings switches, asset checker | gdparse, asset checker with planted faults | `tools/run_tests.sh` |
| S2 ship materials | see `git log` | floors/walls/ceilings/doors/console/gear/ramp/glass/wings use `assets/sol` materials (airlock + cargo floors rubber), nacelles use the nozzle + emissive exhaust disc, interior reflection probe | gdparse, asset checker (8 of 11 materials referenced, 0 integrity problems) | `tools/run_tests.sh` (`ship_materials_test`), V1-V9 screenshots, perf gate |
