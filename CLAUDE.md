# Sol — Agent Instructions

## Canonical local checkout

- Work in `/Users/arielbowyer/Dev/Sol` on macOS. This is the permanent outside-iCloud copy.
- Godot: `/Users/arielbowyer/Downloads/Godot.app/Contents/MacOS/Godot` (4.7.2).
- Run tests with `./tools/run_tests.sh`, sequentially; concurrent runs share `user://` save slots.
- Real fast-pass capture: run `tools/n14_fast_pass.tscn`; output goes under `tests/visual/out/fastpass/<timestamp>/`.
- Keep proprietary Rodina assets and recovered source out of the public remote.

Sol is a Godot 4.7.2 (Forward+, GDScript, Jolt) game recreating Rodina's connected
space → planet → on foot → ship interior → space loop, built independently.

Read before working:
1. `docs/ARCHITECTURE.md` — decided architecture. Do not redesign it.
2. `docs/MILESTONES.md` — ordered checklist, acceptance tests, current task, handoff rules.
3. `research/rodina-starfall-reference/` — evidence only (C/I/U/A labels). Written for a
   different project (Starfall); apply concepts, not its file names.

Hard rules:
- Never modify Starfall or any other project. Never copy Rodina code, assets, or data.
- Every third-party file gets a row in `ATTRIBUTION.md` before commit.
- Tests: run `tools/run_tests.sh` (it imports first, which new `class_name` scripts need; a bare `godot --headless --path . -s res://tests/run_tests.gd` fails with parse errors after adding one). Filter with `-- name_substring`. Godot is only available on
  the Mac, not in cloud sessions. Report tests you did not run as "not run".
- Architecture changes need an ADR in `docs/decisions/` and an `ARCHITECTURE.md` update.
- Keep `research/` read-only and separate from game code and assets.
