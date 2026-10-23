# Sol handoff (2026-10-22, ship interior overhaul)

Godot 4.7.2 recreation of Rodina, in `~/Dev/Sol`, branch `n14-rodina-parity`. Last commit `2f9b74e`; this session's work
is uncommitted in the working tree (see "Files"). Run tests with `./tools/run_tests.sh`: 477 tests, 0 failures in the cloud
(Linux Godot 4.7.2) after this work.

## Fighters (2026-10-22, written in a later session; NOT run: no Godot was available, run `./tools/run_tests.sh` first)
- 9 small fighters from `~/Downloads/3D_spaceships_pack.zip` (GLB, nose at +z in the file, scaled to `FighterDef.size`, turned to -z by `FighterModel`)
  in `assets/fighters/` (git-ignored, licence unknown; see ATTRIBUTION.md). Open the project in the editor once so Godot imports them.
- New: `src/combat/fighter_def.gd`, `fighter_catalog.gd`, `src/flight/fighter_model.gd`, `tests/unit/fighter_catalog_test.gd`.
  Changed: `Ship` (`fighter`, `configure_fighter`, `barrel_x` var instead of `BARREL_X`), `ShipCombatant` (toughness), `EnemyDirector`
  (guards/raider are fighters; `spawn_skirmish`; scripted encounters drop when all dead or 8 km away), `scenes/main.gd` (B = skirmish), PLAYING.md.
- Check by eye: nose direction (if a fighter flies tail-first flip `FighterModel.MODEL_YAW`), sizes, that the heavies are slower to kill and the
  waves are fair, and that the textures look right under Forward+ lighting. Destroyed hostile fighters vanish (no wreck effect yet).

## Fighter hangar, redone as separate ships (same session, also NOT run)
- **Y** at the helm, on foot or in a fighter opens `HangarMenu` (list, turntable preview, stats, Spawn / Return). Spawn creates a real second `Ship`
  (`player_controlled`, `configure_fighter`) via `main.gd::_on_fighter_spawn`: 45 m ahead of the mothership with its velocity, or hovering ahead of the
  walker. `GameSession.board_fighter` sets `Mode.FIGHTER` + `fighter_craft`; `active_ship()` is what camera, floating origin, HUD, audio, effects and
  enemy aim follow (`main.gd::_retarget`). The mothership is held by an idle `AIPilotSource` (`_parked_ai`) unless landed; turret and crew carry on.
- `return_to_mothership` / `lose_fighter` / `climb_out_of_fighter` (F on the ground) / `fighter_in_reach` (F on foot beside a parked one) / `abandon_fighter` (load).
  `mode_before_fighter` (SEATED or OUTSIDE) is what a save records; the fighter itself is not saved. `main.gd::_sync_fighter` frees the node.
- No interior: `FighterEngineFlames` (src/flight/fighter_engine_flames.gd, CPUParticles3D at `FighterDef.engines`, strength from throttle/boost/gear) and a
  cockpit `Camera3D` at `FighterDef.cockpit` (V toggles chase/canopy). **Both positions were measured from the mesh and are approximate: check by eye.**
- `WorldRuntime` converts and recentres both ships on frame changes and keys the frame off the flown ship.
- Check: spawn from the helm and on foot, flames and canopy view per model, F climb-out/boarding, Y > Return, destroyed fighter, load while in a fighter,
  and that enemies shoot at the fighter. Tests: new ones in `fighter_catalog_test.gd` replace the old form test.

## Fighter cockpit (built from the owner's reference pictures, NOT run)
- `FighterCockpit` (src/flight/fighter_cockpit.gd) + `FighterRadar` (fighter_radar.gd, drawn in a SubViewport onto the hex screen): procedural boxes/screens in the
  graphite / warm metal / interior grey / amber / cyan palette; child of the player's fighter at `FighterDef.cockpit`, on render layer 10 (`LAYER_MASK`), which only
  the fighter's cockpit camera includes (`main.gd` sets that mask). Shown, and the hull model hidden, while that camera is current. `Ship.radar_contacts` (set by `main.gd`)
  feeds the radar. Scale is `size / 11` (0.75-1.4).
- Check by eye: framing from `FighterDef.cockpit` per model (dash height, struts), Label3D text legibility and orientation, the radar texture (flip/mirror), light levels
  (the cockpit has two omni lights on its own layer), and the stick's tilt direction.

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

## Fighters, big ships and cockpits (overnight + follow-ups)
- 30 fighters (`FighterCatalog`) with cockpit interiors; models load from .glb at runtime (`FighterModel._instantiate`, GLTFDocument
  fallback when not imported). Licences unconfirmed: `assets/fighters/`, `assets/cockpit/`, `assets/ships/` are git-ignored.
- 5 big ships in `src/bigship/` (data from `tools/gen_big_ships.py`), walkable in first person (bridge, captain's bay, corridors, airlock).
  Menu entry "Big ships" in the title/pause menu. 4 hulls are CC-BY-4.0: credit lines in `big_ship_catalog.gd` and ATTRIBUTION.md.
- Cockpit fixes: readout plates pulled in and squared to the dash; the grey "InteriorFill" wall mesh now only for the X-Wing set
  (`_spec.legacy`), other interiors carry their own walls.
- Ground contact: a fighter's support points now come from its loaded model's real extents (`FighterModel` stores `half_extents`,
  `Ship._fit_support_points_to_model`), so hulls no longer sink into terrain. Verified numerically on the Talon; Valkyrie/Stinger models
  are not in the cloud copy, so check landing on the Mac.
- Player gun per fighter: damage/rate scaled from the fighter's stats (`Ship.configure_fighter`).

## OPEN: planet clips / vanishes in cockpit views at some altitudes
- Not fixed. Cause (best understanding): one planet is drawn three ways (terrain chunks cut by the far plane, `planet_backdrop` sphere
  that reads the depth buffer, squeezed impostor sphere) and the handoff altitudes depend on the camera far plane. The fighter cockpit
  camera has near 0.1 m, so `CameraRange` caps its far at ~400 km (chase ~2,000 km): handoffs differ per view and each is a seam
  (straight terrain cut, backdrop colour differs from terrain, depth reconstruction imprecise at far/near ~4e6).
- Tried and reverted (could not test on Vulkan; cloud has only GL compatibility): comparing the depth buffer against the projection's own
  depth instead of the inverse projection; pinning the backdrop's depth in the vertex stage. In GL the pinned depth rounds to 1.0 and draws nothing.
- Proposed fix: a second "sky" camera (own near/far scaled to planet distance) that draws only planets/moons behind the main view, so the
  main camera needs only a short far plane; blend terrain into the planet colour at the horizon. Touches `scenes/main.gd` and
  `src/world/body_impostors.gd`. Needs checking on the Mac renderer.
- Also unverified in a running game: atmosphere-entry effects for the new fighters, per-model muzzle positions.
