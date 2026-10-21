# Session state

- Canonical local checkout: `/Users/arielbowyer/Dev/Sol` (macOS, outside iCloud), independent APFS-cloned `git`.
- Branch: `n14-rodina-parity`; latest setup commits: `6934f6a` (source-faithful Jarilo port), `1f202b0` (Godot import normalization), followed by the fast-pass/canonical-workflow commit. `origin` is the public Sol GitHub repo; do not push proprietary Rodina assets without an explicit distribution decision.
- The pre-existing source-faithful Jarilo/noise changes and Godot import rewrite are now committed. No original working copy was deleted; backups are in `/Users/arielbowyer/Dev/Sol-local-backups/20261021-canonical-setup/`.
- Tests (canonical, macOS, run alone): **381 tests / 107,031 assertions / 0 failures**. Do not run two Godot test suites concurrently; they share `user://` save slots and can produce false soak failures.
- Bench (M4, headless): Jarilo height sample **12.3 us**; full 32x32 chunk **~17.5 ms**.
- Real Mac fast-pass: `tests/visual/out/fastpass/2026-10-21T19-09-23/` (97 PNG + `fastpass.log`). All phases `holes=none`; near-full detail is high at cruise/landing, while 10 km/s low flight still shows previews/fillers. Plan/upload/visibility maxima were 34.8/15.2/18.5 ms.
- Godot: `/Users/arielbowyer/Downloads/Godot.app/Contents/MacOS/Godot` (4.7.2). Test: `tools/run_tests.sh`. Fast pass: run `tools/n14_fast_pass.tscn` from the editor or with `--path . res://tools/n14_fast_pass.tscn`.
- Claude Code: installed at `/opt/homebrew/bin/claude` (2.1.224), but **logged out**. Run `cd ~/Dev/Sol && claude` and sign in once.
- Rodina source files `_perlin.h`, `PlanetJarilo.h`, `_voronoi.h` are present in `/Users/arielbowyer/Downloads/rodina-repo/Shaders/` (and the recovery tree); the earlier “missing” note was stale.
- Next: inspect/fix the low-altitude preview seam/throughput work, then continue source-faithful Rodina terrain.
