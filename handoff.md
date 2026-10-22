# Sol handoff (2026-10-22, ship interior overhaul)

Godot 4.7.2 recreation of Rodina, in `~/Dev/Sol`, branch `n14-rodina-parity`. Last commit `2f9b74e`; this session's work
is uncommitted in the working tree (see "Files"). Run tests with `./tools/run_tests.sh`: 477 tests, 0 failures in the cloud
(Linux Godot 4.7.2) after this work.

## Open problems (start here)
1. **Confirm the invisible-interior fix on the Mac.** Root cause found and fixed (ADR 0013): near 0.05 m with the
   flight far plane (up to 4,000 km) made Godot's float32 projection degenerate, and frustum culling dropped every mesh.
   Reproduced in the cloud renderer before the fix and gone after it. To see it with Forward+: open
   `tools/interior_tour.tscn` in the editor, Run Current Scene (F6); pictures and `progress.log` go to
   `tests/visual/out/interior_tour/`.
2. Layout decision (owner's call) unchanged: compact single deck with the bigger-on-the-inside pocket (ADR 0012) vs
   Rodina's real two-deck map. Rodina's wiki says Rodina's interior is *not* bigger on the inside.

## Done this session
- `CameraRange` (src/camera/camera_range.gd): every camera keeps far / near <= 4e6; the walking camera's near rises to at
  most 0.25 m so its far plane can reach the horizon from orbit (planet visible through the pocket windows).
- ADR 0013: pocket on layer 2, hull 3, cockpit/airlock shells 4/5; `ShipVisuals.cull_mask_for`; `main.gd` sets every
  camera's mask each physics tick. Pocket lamps do not light the hull. No ship node is hidden any more for inside/outside.
- F on every plain door (living, med bay and bathroom doors used to answer "Nothing to use here"). Prompts read
  "F — Open door" / "F — Close door"; door deny sound for any door.
- Gunner seat moved off the turret room's centre line (it blocked looking at the cargo door) to a tactical console on the
  tail wall; the console screen and F read the real `ShipTurret` (safe / armed in combat gear / overheated, heat).
- Engineering: reactor core column (aft starboard corner, solid), colour/brightness from `ShipPower` temperature and
  output, dark when tripped, amber pulse on battery; floor power bus to the reactor panel; plinth read-out.
- Live text on screens (Label3D, 4 Hz): ops (hull, fuel, reactor), scanners (pulse ready/recharging), radio, battery,
  limnal drive, tactical, airlock pressure, cockpit dash (gear, speed, fuel, hull).
- Visual research: `LOCAL_RODINA_REFERENCE/SHIP_INTERIOR_VISUAL_RESEARCH.md` (Rodina + PULSAR references inspected).
- `tools/interior_tour.tscn`: real-camera walkthrough (fixed views, walking with W and F at doors, optional landed and
  walk-out/walk-in round trip). CLI: `godot --path . res://tools/interior_tour.tscn -- out_dir [orbit|landed] [view filter]
  [nowalk] [roundtrip] [lowtick]`.

## Files
docs/ARCHITECTURE.md, docs/KNOWN_ISSUES.md, src/camera/camera_range.gd(.uid), src/camera/cockpit_camera.gd,
tests/unit/camera_range_test.gd, docs/decisions/0013-interior-render-layers.md, handoff.md, scenes/main.gd,
src/audio/audio_service.gd, src/flight/ship_visuals.gd, src/game/game_session.gd, src/interior/interior_layout.gd,
tests/scenario/slice_scenario_test.gd, tests/unit/bigger_inside_test.gd, tests/unit/interior_layout_test.gd,
tools/interior_tour.gd(.uid), tools/interior_tour.tscn.

## Gotchas
- In the cloud shell `.git/config` has `core.worktree=/Users/arielbowyer/Dev/Sol`; use `git -c core.worktree=$PWD`.
- The cloud can run Linux Godot 4.7.2 (download from GitHub releases) headless for tests and under Xvfb with
  `--rendering-method gl_compatibility --rendering-driver opengl3` for pictures. No Vulkan there, so no Forward+.
- `pkill -f`/`pgrep -f` with "Godot" or "interior_tour" in the pattern also matches the calling shell; use `pgrep -x`.
- `test_failures.txt` in the repo root is an empty scratch file, not committed.

## Not done / ideas
- Scanner/radio menus are still plain text menus; the tactical console only reports (firing stays at the helm, H).
- No new sounds: doors, airlock and machine hums use the existing cues.
- Hull windows: the exterior hull has no window openings matching the pocket windows (pocket rooms are bigger than the hull).
