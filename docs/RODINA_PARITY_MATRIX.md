# Rodina → Sol parity matrix (N14 working source of truth)

Baseline: branch `n14-rodina-parity`, created from verified remote `origin/n13-graphics-port` = `8d4abe2`
(2026-10-21 11:13 UTC). The older local `n13-visual-fidelity` work is preserved on its own branch; it is not
silently merged. Recovery source: `/Users/arielbowyer/Downloads/rodina-repo` (private `dryweather-2544/rodina`,
commit `f3a340b`) plus `/Users/arielbowyer/Documents/Deepseek workspace/rodina-recovery`.

Status meanings: **PORT** = source formula/data ported; **ADAPT** = source behaviour with an integration
change; **INFER** = engine-side meaning inferred; **GAP** = not implemented; **VERIFY** = implemented but not
yet visually/behaviourally checked against reference.

| Area | Rodina source | Sol implementation | Status | Evidence / next test |
|---|---|---|---|---|
| Flight translation, gears, gravity, entry push, roll levelling | `Gameplay/EGVehicle.lua`, `DataGameplay/EGDataShipPlayer.lua` | `src/flight/flight_model.gd`, `ship_tuning.gd`, `planet_body.gd` | PORT / ADAPT | `tests/unit/flight_model_test.gd`, physics telemetry; hover is still an open Havok question |
| WARP/Limnal gear and activation | `EGDataShipPlayer.lua:296-369`, `EGBehaviorPlayer.lua:162-179` | `src/camera/limnal_warp_view.gd`, `ship_effects.gd`, flight model | PORT / ADAPT | `limnal_warp_view_test`, `warp_rules_test`; WARP steering drift is now ported with a deterministic twitch so replays stay reproducible; relative-time model is still Sol-specific |
| Collision restitution 0.8 + `SetVelocityControl` ramp | `EGVehicle.lua:736-884`, `EGDataShipPlayer.lua:26-38` | `ground_contact.gd`, `flight_model.gd`, `ship_state.gd` | **PORT + ADAPT** | `ground_contact_test::test_hull_impact_restitution_matches_rodina`; `flight_model_test::test_control_authority_ramps_after_a_collision`; Havok engine semantics remain inferred |
| AI MoveLock | `EGBehavior.lua:57-83` | `ai_pilot_source.gd`, `move_lock` | PORT | AI facing / slice tests |
| Chase/cockpit camera, FOV, shake, WARP camera | `EGDataShipPlayer.lua:296-369`, `EGWorldObject.lua:226-256` | `chase_camera.gd`, `cockpit_camera.gd`, `limnal_warp_view.gd`, `camera_vibration.gd` | PORT / VERIFY | `n13_graphics_check`, visual comparisons |
| Ship particles, engine trails, entry fire, thruster jets | `EGDataParticles.lua`, `EGDataShipPlayer.lua:252-444` | `ship_effects.gd`, `rodina_emitter.gd`, `rodina_particle_defs.gd` | PORT / ADAPT / VERIFY | `rodina_ship_effects_test`; owner-requested hard pixel layer sits over the source-derived flame cone |
| Sky/atmosphere model | `_atmosphere.h`, `RodinaAtmosphere*` | `rodina_atmosphere.gdshaderinc`, `space_sky.gdshader`, atmosphere shell | PORT / INFER / VERIFY | N13 shots + measured palette; filter pass is approximated |
| Terrain height grammar | `Shaders/PlanetPerun.h`, `PlanetJarilo.h`, `PlanetVeles.h`, `PlanetMorena.h`, `PlanetAsteroid.h`; `EGDataPlanets.lua` GenerationVars | `src/planet/height_function.gd`, `terrain_profile.gd`, `data/planets/*.tres` | **PARTIAL PORT** | Perun/Jarilo/Veles plus the airless Asteroid feature grammar are enabled; Voronoi point buffer and derivative warp are explicit ADAPTs; Morena remains a typed placeholder and no Sol body is assigned to it |
| Terrain material blending / texture tiers | `RodinaTerrain.fx`, `EGEditorData.lua` | `PlanetLook`, terrain shader, palette system | ADAPT / GAP | Texture tiers and six-gate features remain follow-up |
| Ship exterior/interior geometry | `EGDataShipPlayer.lua:7-9`, meshes (not recovered) | `ship_exterior.gd`, `interior_layout.gd`, ADR 0012 | ADAPT (custom) | Original mesh absent; reference-based recreation only |
| Audio effects | authored Rodina WAVs | `AudioService` / `audio_library.gd` | PORT / VERIFY | N11 inventory; human listening still required |
| HUD fonts/colours | `Render/MenuFonts.lua` | N13 HUD fonts / UI | PORT / VERIFY | HUD style tests; compare against supplied frames |
| Items, damage, projectiles, AI, missions | `EGDataItems.lua`, combat scripts | existing Sol systems | ADAPT / GAP | Follow Stage 8; do not replace working systems |

## Known hard blockers / uncertainties

1. Rodina's particle renderer and terrain collision are engine-side; the recovered Lua/shader data gives formulas
   but not every runtime semantic.
2. The GPU `VoronoiPoints[1024]` buffer is not present in the recovered shader sources. The current terrain port
   uses a deterministic cellular field as an explicit ADAPT; this must be labelled in visual comparisons.
3. The original ship mesh/textures are absent; do not claim a mesh port.
4. The Rodina public repo is **public**. N11 audio and N13 particle/table material are proprietary local-reference
   assets and must not be pushed. See `ATTRIBUTION.md` and `docs/N11_REPORT.md`.
5. Existing saves that land on a world whose height grammar changed need an explicit migration or a deliberate,
   documented reset. The terrain change is gameplay data, not a visual-style toggle.
