# N13 — Rodina graphics port: source map, what was ported, what was checked

Branch `n13-graphics-port`, started from `origin/n12-render-flicker` (d780f3b), the newest state (it holds the
VTOL/physics branch, N10 warp, N11 audio and N12). Everything here is in the **rodina** visual style only
(`SOL_VISUAL_STYLE=rodina`, or Settings → visual style); the **sol** style looks exactly as before.

Labels: **PORT** = Rodina's formula and numbers, re-expressed in GDScript; **DATA** = Rodina's numbers transcribed
mechanically; **ADAPT** = Rodina's behaviour with an integration change Sol needs; **INFER** = engine-side meaning not
in the recovered files, chosen from how the data is used; **NOT PORTED** = said why.

## 0. What was available

- Rodina 1.6.2 **Lua scripts** (the owner's private `rodina` repo: `Scripts/`), read directly. All formulas below come
  from them, with line numbers.
- **Not available in this session:** the shader sources (`Shaders/*.fx`, `_atmosphere.h`), meshes, textures and
  any Rodina image or video. Those are on the Mac only. The shader behaviour is known only through the research
  summary (`research/rodina-starfall-reference/_work/rendering_notes.md`), so no shader was ported line for line.
- No Rodina reference footage, so **no side-by-side comparison with Rodina frames was possible**. "Matches" below
  always means "matches Rodina's code and data", never "looks the same as a Rodina screenshot".

## 1. Source-to-Sol map

| Effect | Rodina source | Sol before | Sol now | Kind |
|---|---|---|---|---|
| Warp clocks: LimnalTimer, LimnalSpacewarp, LimnalActivation | `EGDataShipPlayer.lua:296-313` (`SetMovementEffects`), `LimnalStartTime = 1.8` (:45) | none (WARP was a speed gear only) | `src/camera/limnal_warp_view.gd` | PORT |
| Warp FOV: base → min(175, base+30) | `EGDataShipPlayer.lua:315-316, 344-346` | fixed FOV | `LimnalWarpView.field_of_view`, `scenes/main.gd:_apply_field_of_view` | PORT |
| Chase distance 200→125, angle 10→15°, stiffness 5 | `EGDataShipPlayer.lua:317-318, 336, 348`; `EGVehicle.lua:40-43` | 17 m / 11° fixed | `ChaseCamera.follow_distance/angle`, × `SHIP_SCALE` | ADAPT (scaled) |
| Camera shake modules (named, held while re-set, 0.25 s fade, Perlin, ×3×factor³) | `EGWorldObject.lua:226-256`, `EGEffect.lua` `EGEffectUpdate` | none | `src/camera/camera_vibration.gd` | PORT + INFER (units) |
| Warp shake 0.0125 × activation at (125, 100) | `EGBehaviorPlayer.lua:162-172` | none | `LimnalWarpView.update` | PORT |
| Atmosphere shake 0.075 × resistance at 18 | `EGVehicle.lua:533-543` | none | `LimnalWarpView.update` | PORT |
| Firing shake 0.002 at (125, 100) | `EGVehicle.lua:1673-1675` | none | `LimnalWarpView.update` | PORT |
| Warp drift (random turn added to steering) | `EGBehaviorPlayer.lua:174-179` | — | — | NOT PORTED: it changes how the ship steers (flight behaviour, not graphics) |
| Warp particles: Startup Ring → Drive, Pink Air, Ship Blur | `EGDataShipPlayer.lua:361-369`; materials `EGDataParticles.lua:2073-2289` | none | `src/flight/ship_effects.gd`, `rodina_emitter.gd`, `rodina_particle_defs.gd` | PORT + DATA |
| Main engine per gear (DockAir / CombatEngineMain / CruiseEngineMain) at forward-thrust strength | `EGDataShipPlayer.lua:370-386`; `EGDataParticles.lua:995-1298` | Sol's own guessed plumes | same files | ADAPT: at each of Sol's two pod nozzles, along the nozzle axis |
| 12 thruster jets (back/up/down×0.75/left/right) | `EGDataShipPlayer.lua:252-283, 388-405` | none | `ShipEffects._JETS` | PORT, positions × `SHIP_SCALE` |
| Cruise inertia streaks, EGAnalogue(timeFactor, 1, 30, 0, 1) | `EGDataShipPlayer.lua:408-417`; `EGDataParticles.lua:1090` | none | `ShipEffects` | ADAPT: timeFactor = speed / 10 km/s (Sol has no relative time) |
| Atmospheric entry flames + shockwave (cockpit variants) | `EGVehicle.lua:514-532`, `EGDataShipPlayer.lua:432-444`; `EGDataParticles.lua:1490-1659` | Sol's guessed heat sheath + sparks | `ShipEffects` | PORT + DATA |
| Coasting "Wing" trails | `EGDataShipPlayer.lua:355-359` | — | — | NOT PORTED: needs Rodina's clutch, which Sol does not have |
| Sky, sunset, limb and haze colours | `EGDataPlanets.lua` Jarilo :503-506, Veles :386-390, Zosia :111-114 | Sol's guessed colours | `VisualStyle.RODINA_ATMOSPHERES` | DATA + INFER (which colour is zenith/horizon) |
| Horizon/density/sunset/halo maths, 10-sample terminator | `_atmosphere.h` (research summary only) | Sol's two-colour gradient sky | unchanged | NOT PORTED: shader source not available here |
| No tonemap / exposure / gamma, additive bloom | research `rendering_notes.md` §6.6 | already in the rodina style (linear tonemap, glow) | unchanged | — (already done) |
| Depth of field driven by the horizon, FXAA preset 12 | research §4.6, §6.6 | none | none | NOT PORTED (no source here; would need a post pass) |

Helpers ported line for line: `EGAnalogue`, `EGInterpolate`, `EGApproach`, `EGDeltaTo`, `EGHueSaturateValue`
(`EGUtility.lua:90-273`) → `src/core/rodina_math.gd`.

## 2. The warp sequence as ported

- **Entering:** the gear becomes WARP (Sol's own gating: open space and an installed drive). LimnalTimer starts.
  Activation = timer / 1.8 s. Blend = max(blend, EGApproach(timer, 0.95, 0.25)): 0.11 at 0.5 s, 0.29 at 1.8 s,
  0.48 at 4 s, 0.68 at 10 s; it never reaches 0.95. Rodina's own code makes "blend = 1" unreachable (it tests an
  undefined variable), which is kept.
- **Warm-up (0–1.8 s):** "Limnal Startup Ring" at strength = activation, "Limnal Drive Air". Engines and jets off.
  Warp shake grows with activation.
- **Sustained:** "Limnal Drive", "Limnal Pink Air", "LimnalShipBlur". FOV widens toward base + 30, camera closes in
  and rises.
- **Exit / losing the gear** (pilot shifts down, the drive is lost, the gear is refused): the timer resets at once,
  the warp effects stop, the blend decays by 1.5 per second (EGInterpolate). Re-entering restarts the 1.8 s warm-up.
- Save/load: nothing is saved (Rodina saves none of this); loading resets the camera to rest.

## 3. In-game checks (cloud container, software renderer)

Tool: `tools/n13_graphics_check.gd`, which flies the real main scene through the real flight model:
```
SOL_VISUAL_STYLE=rodina N13_SCENE=<combat|cruise|warp|entry|low> N13_OUT=<dir> \
  xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 -s res://tools/n13_graphics_check.gd
```
Shots are in `docs/n13_shots/`. Measured values from the logs:

| Scenario | Game time | FOV | Blend | Chase distance | Live effects (strength) |
|---|---|---|---|---|---|
| Cruise before warp (open space, 10.7 Mm/s) | 1.1 s | 75.0 | 0 | 54.0 m | CruiseEngineMain ×2 (1.0), CruiseEngineInertia (1.0) |
| Warp +0.5 s | 1.7 s | 77.6 | 0.112 | 51.7 m | Startup Ring (0.22), Drive Air (1.0) |
| Warp +1.8 s | 2.9 s | 83.1 | 0.287 | 48.2 m | Startup Ring (0.89), Drive Air |
| Warp +4 s | 5.2 s | 89.0 | 0.475 | 44.4 m | Limnal Drive, Pink Air, Ship Blur |
| Warp +10 s | 11.2 s | 95.3 | 0.679 | 40.3 m | same |
| Exit +0.5 s | 11.7 s | 86.1 | 0.302 | 47.9 m | cruise engines + inertia |
| Exit +2 s | 13.2 s | 76.2 | 0.033 | 53.3 m | same |
| Exit +5 s | 16.3 s | 75.0 | 0.0003 | 54.0 m | same |
| Combat, 300 km over Aurelia, full thrust | 1.1 s | 75 | 0 | 54 m | CombatEngineMain ×2 (1.0) |
| Combat, thrust up + forward 0.6 | 2.1 s | 75 | 0 | 54 m | CombatEngineMain ×2 (0.6), CombatEngineSmall ×3 (0.6) |
| Cruise climb, 300→334 km | 1 / 4 / 8 s | 75 | 0 | 54 m | inertia streaks 0.11 / 0.28 / 0.31 as speed rises 48→100 km/s |
| Entry, 110 km, 4 km/s nose-down | 0.6 / 2 / 4 s | 75 | 0 | 54 m | AtmosphereEntry 0.85–0.88, Shockwave 1.0; shake up to 0.05 rad |
| Low, 900 m over Aurelia, 250 m/s | 1 / 3 s | 75 | 0 | 54 m | CombatEngineMain ×2 (0.5), faint Shockwave (0.13) |

Found and fixed by these runs:
1. **Camera inside the hull in sustained warp.** Scaling Sol's 17 m camera by Rodina's 0.625 put it inside the
   ship. Fix: use Rodina's own distances (200 → 125 m) scaled to Sol's hull (54 → 34 m).
2. **Shake stuck at zero.** Godot's Perlin is 0 at whole numbers and Sol's fixed 60 Hz tick lands Rodina's noise
   arguments on whole numbers every 2nd/8th tick (a 30 Hz buzz on a real machine). Fix: the noise is read just off
   the lattice; the formula is unchanged. Test `test_warp_shake_is_never_stuck_at_zero_on_the_fixed_tick`.
3. **Entry flames invisible in later shots.** A test-machine artefact: at ~1 frame/s, particles living a quarter of a
   second die between frames. The tool now slows time for 25 frames before each shot.

Sky: `docs/n13_shots/sky/<world>/` from `tools/style_shots.gd` (orbit, approach, low, ground views).

Regression checks: full suite 339 tests, 104,405 assertions, 0 failures (baseline before N13: 322 / 0). The
whole-loop bot `tools/playthrough.gd` (headless) lands and walks out, then sticks walking back to the ramp (step 12)
in both styles. It sticks at the same place on the untouched starting commit d780f3b, so the cause is in
N10–N12 or the bot, not N13. It is not fixed here.

**Not checked:** anything on the Mac, performance on real hardware (the container renders at ~1 frame per second,
mean frame 0.6–1.6 s, which says nothing about the Mac), the cockpit-view variants on screen, and any comparison
with real Rodina frames.

## 4. Inferred meanings (please check on the Mac against Rodina)

Rodina's particle engine is C++. The data was read this way, chosen so that **every one of Rodina's 104 materials**
comes out a sensible size (checked over the whole file):
- `Size` = radius of the sphere particles are born in; key `Size` = sprite diameter in metres. The other reading
  (`Size` scales the keys) makes the hand-gun bolts 2 mm wide and every `Size = 0` thruster invisible.
- The emitter's +Y is the `AttachParticles` direction, turned by the shortest arc *in Rodina's axes*
  (x right, y forward, z up). This puts the warp ring's Offset (−1000, 0, 0) ahead of the ship.
- `normal` = outward from the spawn sphere's centre; `VelocityRange` is ± per axis; acceleration is constant.
- `Yaw`/`Pitch` are not used (read as sprite spin, invisible on a round sprite; read as direction spread they
  would scatter the straight warp streams).
- Missing `BlendStyle` = alpha blend; missing `OrientationType` = follows the ship's position, keeps world rotation.
- Colours are treated as display (sRGB) values because Rodina has no gamma pass; dense additive overlaps still
  differ (Rodina adds in display space, Godot in linear).
- `SHIP_SCALE = 0.27`: Sol's ~20 m hull over the ~75 m between Rodina's rearmost and foremost emitter positions.
  Rodina's mesh is not here to measure.
- Sky colour roles: ScatterColor1 = zenith and orbit limb, ScatterColor2 = horizon and haze, FilterColor2 = sunset.

The visible result of the first reading: Rodina's combat engine is a cloud of 1.5 m cyan sparks around the engine,
not a solid flame. If real Rodina footage shows a solid flame, the `Size` reading is the thing to change
(`data/shaders/rodina_particle.gdshader`, `start()`).

## 5. Files

New: `src/core/rodina_math.gd`, `src/camera/limnal_warp_view.gd`, `src/camera/camera_vibration.gd`,
`src/flight/rodina_emitter.gd`, `src/flight/rodina_particle_defs.gd`, `data/shaders/rodina_particle.gdshader`,
`tools/n13_graphics_check.gd`, `tests/unit/limnal_warp_view_test.gd`, `tests/unit/rodina_ship_effects_test.gd`,
`docs/decisions/0011-rodina-graphics-port.md`, this file, `docs/n13_shots/`.
Changed: `scenes/main.gd`, `src/camera/chase_camera.gd`, `src/flight/ship_effects.gd` (Sol's guessed plumes, heat
sheath and sparks replaced), `src/world/visual_style.gd`, `tests/unit/visual_style_test.gd`, `ATTRIBUTION.md`,
`docs/ARCHITECTURE.md`. Removed: `data/shaders/entry_heat.gdshader` (only the replaced heat sheath used it).

## 6. Licensing

The particle tables, constants and colours are Rodina's (Elliptic Games). They are recorded in `ATTRIBUTION.md` as
owner-authorised local reference use, like the N11 audio. **The Sol GitHub repository is public**, so this branch
should not be pushed there unless the repository is made private first.

## 7. Second pass: calibrated against the owner's Rodina screenshots

The owner supplied nine Rodina 1.6.2 screenshots (Jarilo ground, Perun and Jarilo from orbit, an icy world with a green
sky, cockpit and interior views, combat). They confirm the data reading: the sky is the atmosphere's ScatterColor
(peach Jarilo, purple Perun, green Morena), and the star seen through the air takes its FilterColor (blue on Jarilo,
cyan on Perun, red on Morena). Changed to match (rodina style only):
- **Default style is now `rodina`** (GameSettings.visual_style). The owner was playing in the `sol` style and saw
  none of the earlier work. A saved settings file that already says `sol` keeps `sol`.
- **Sun in the air:** a ~9-degree disc of FilterColor1 inside a wide FilterColor2 halo (measured on the Jarilo
  shot); the fogged world-space star sphere is hidden inside the air so it no longer covers it. In space the star
  is unchanged.
- **Sky strength:** the scatter colours are laid over Rodina's space base at saturate(AtmosphereDensity); Jarilo's
  0.75 matches the screenshot (its sky is ~77% of the raw colour).
- **Haze:** fog 6e-5 per m in the air colour, so ridges sink into the sky within tens of km.
- **From orbit:** a soft, wide limb in the pale ScatterColor2 plus a faint haze over the lit disc (rim power 2.5,
  haze 0.15), instead of the thin bright Sol rim.
- **Engines:** a blue flame cone and glow per nozzle replace the CombatEngineMain/CruiseEngineMain sparks (owner
  request). Combat: Rodina's cyan to blue, 2-12 m long with thrust; cruise: blue-violet, 3-21 m.
Shots: `docs/n13_shots/v2/`. Still different: Rodina's landforms (tall snowy peaks, ice canyons) are terrain
generation, not a style, and are not changed here.

## 8. Lighting pass (rodina style)

From Rodina's planet data and lighting model (rendering_notes §6.1-6.3) and the owner's screenshots:
- Sunlight tinted toward the atmosphere's FilterColor2 (GetPlanetStarLight). The blend factor is not in the research;
  the full tint made whole scenes one colour (`docs/n13_shots/v3/`), so it is 0.3 × saturate(AtmosphereDensity),
  judged against the Jarilo screenshot (warm ground, bluish snow) (`docs/n13_shots/v4/`).
- Shade: Jarilo's own SurfaceAmbientColor HSV(32, .2, .25) for Aurelia; other worlds a quarter of their horizon
  colour (inferred).
- No back light: Jarilo's StarBacksideColor is black, and only Morena sets one.
- Sunlight fades through TerminatorBegin..End (Jarilo .2/-.2, Veles and Zosia .2/-.5) by the sun's height.
- Engine nozzle glow follows forward thrust only; reverse and strafe fire the thruster jets, as in Rodina.

## 9. Rodina's atmosphere model in the sky and from orbit (rodina style)

`data/shaders/rodina_atmosphere.gdshaderinc` rebuilds `_atmosphere.h` step by step from the audit
(rendering_notes §4.1-4.6, line numbers in the file): the view-angle horizon factors with the 0.66 rad band,
`color` blending Scatter1/2 and Filter1/2, `Approach` depth and the altitude-ratio density, the squared halo that
widens through sunset, the sun-side sunset term, the 10-sample terminator shading, tint = saturate(D) and
transmittance 1 - saturate(D - 1) * alpha (stars show through Jarilo's thin air, as in the screenshot). Each world's
StarHalo, SunsetStarHalo, SunsetStarAngleBuffer and SunsetHorizonLimit come from its PlanetDef.
- Sky (`space_sky.gdshader`): replaces the Sol two-colour gradient in the rodina style when in a planet's air.
- From space (`rodina_atmosphere_shell.gdshader`): the same maths on a sphere the size of the atmosphere, added over
  the scene with Rodina's transmittance. Over the ground the scatter is scaled to 0.35 (inferred, calibrated on the
  owner's orbit screenshot: full strength washed the planet out to a flat disc).
- Fog thins with altitude again (the shader does the high-altitude haze).
Not in the audit, so inferred: EaseOutSin's input clamp, which factor the halo/sunset use as the horizon term, and the
shade samples' range. Shots: `docs/n13_shots/v5` (first pass), `v6`, `v7` (orbit calibrated).
