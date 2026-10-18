# N9 — art and audio integration: status

Branch `n9-art-audio`, created from `origin/n1-ship-power` @ `ab3cdac` (the PR #1 head; `main` holds no game). **Unpushed; no PR.**
Plan: `docs/N9_BRIEF.md` in Sol-Assets (branch `a6-b2-combined`). Asset source: Sol-Assets `a6-b2-combined` (commit recorded in `assets/sol/SOURCE.txt`).
Every Sol-Assets manifest row is still `review`; nothing here approves anything.

**Authoring environment:** a Linux cloud session with no Godot, no display and no audio device. Nothing below was run under Godot unless a
row says so. What *was* run here: `gdparse` (syntax), `tools/asset_usage_check.py`, `tools/import_assets.py`. Everything else needs the Mac:
`tools/n9_verify.sh` runs it all and writes one report.

Deferred: sfx_radio_open, sfx_radio_close

## Steps
| Step | Commit | What | Run here | Needs the Mac |
|---|---|---|---|---|
| S1 scaffold | see `git log` | copy tool, `AssetLibrary`, 5 settings switches, asset checker | gdparse, asset checker with planted faults | `tools/run_tests.sh` |
