# Rodina visual style: results of the in-game checks

Companion to `RODINA_ART_STYLE_TECHNICAL_SPEC.md` (evidence and techniques) and `RODINA_PLANET_TYPES.md` (families).
Photos are in `docs/rodina_style_shots/`. All were rendered in a cloud container (Godot 4.7.2, lavapipe software
Vulkan under Xvfb, about 1 frame per second) with `tools/style_shots.gd`; none were taken on the Mac.

## 0. The limit that shapes every row below

No Rodina image, video frame or game file was available in this session (see spec §0: the reference archive and
Mac checkouts are not on this machine, and the Rodina and Steam sites are blocked by the network policy). So the
column "what the original looks like" can only state what the **text research** says about Rodina's technique. It
cannot say what a Rodina frame looks like, and "closer" below means "closer to what that research describes",
**not** "measured closer to Rodina footage". Re-check every row against real frames when the archive is reachable.

## 1. How to reproduce

```
SOL_VISUAL_STYLE=sol|rodina xvfb-run -a -s "-screen 0 1280x720x24" godot --path . -s res://tools/style_shots.gd -- <out_dir> [world] [view]
```
Worlds: `planet` (Aurelia), `cinder`, `verdant`, `selene`, `pebble`. Views: `orbit`, `approach` (30 km), `low` (900 m),
`ground` (eye height beside the landed ship), and `effects` (on request only: 9,000 m/s at 40 km over Aurelia, full thrust).
`tools/style_switch_check.gd` (headless) switches styles in the live scene and checks nothing but colours changed.

## 2. Comparisons

Each row answers: (1) original, from the research; (2) Sol before (the `sol` style, identical to the old code, see §3);
(3) what is still different; (4) the cause; (5) what was changed; (6) closer?

| Situation | (1) Rodina, per the research | (2) Sol before | (3) Still different | (4) Cause | (5) Changed | (6) Closer? |
|---|---|---|---|---|---|---|
| Deep space / orbit (all `compare_*.jpg`, top row) | Near-black purple base, over-bright blue-white stars, no twinkle; planets ringed by their own atmosphere colours | Blue-grey space (hue 228°), one blue rim on every world | Star density and dust bands unknown; no subtractive dust layer | No frames to match; dust not implemented | Violet-black space (hue ~260°), brighter blue-tinted stars, per-world rims (Aurelia lavender, Cinder orange, Verdant teal-green) | Yes, against the text |
| High-altitude approach (30 km) | Two colour pairs per planet, ground band at the horizon, haze that thickens with distance | Same pale blue sky (hue ~210°) on all three air worlds; haze fades out above 2-30 km | Exact sky colours unknown | One hard-coded sky and fog for all worlds | Per-world zenith/horizon pairs: Aurelia violet-peach (hue 317°), Cinder dusty rust (14°), Verdant blue-teal (191°); distance haze kept at altitude | Yes, against the text |
| Atmospheric entry (`rodina_effects_entry.jpg`) | Entry effects during atmospheric entry; particles keyed in colour, alpha and size over life, per-effect blending | No entry visuals at all | Shape, colour and scale of Rodina's entry effect unknown | Nothing existed | Additive heat glow on the nose, orange sparks blown aft, both driven by the real heating rate; hidden in the `sol` style | Yes in kind; look not verified against Rodina |
| Low altitude (900 m) | Distance-widened bands, texture tiers at 500 m / 5 km / 50 km, ground-to-space colour blend by altitude | Green Aurelia, fine 4-6 m detail texture visible as busy noise | Only one blend tier, not three | Sol's detail shader has one near and one far layer | Larger, softer detail (12/24/120 m, contrast 0.45); ground-to-orbit colour lean with altitude | Yes, against the text |
| Ground level (`ground` row) | No shadows, no tonemap, backside fill, sun disc and halo, sunset only towards the sun | Filmic tonemap, blue sky, green ground on Aurelia | Rodina landforms (dunes, plates, Voronoi plateaus) absent | Terrain shape is gameplay data (collision, walking, POIs, saves), so a style must not change it | Linear tonemap, additive bloom, shadowless back light, per-world ground palettes | Colour yes; landforms unchanged by design (spec §3) |
| Aurelia (`compare_planet.jpg`) | Jarilo-like: research gives dunes and orbit-band atmosphere, no colour values | Green-grey plains, blue sky | Dunes; true Jarilo colours | No landforms in a style; no frames | Ochre and salmon plains, sandstone uplands, dark slopes, frosted poles; lavender rim | Yes, against the text |
| Cinder (`compare_cinder.jpg`) | Perun-like: hot inner world, Voronoi, plateaus, mountains, holes | Tan ground under the same blue sky | Landforms | As above | Rust barrens, basalt cliffs, warm dusty sky | Yes, against the text |
| Verdant (`compare_verdant.jpg`) | Veles-like: dense world, Voronoi | Mint ground, blue sky | Landforms | As above | Teal-green ground with olive moss patches; sky separated from ground by ~35° of hue (first try was ~10°, read as one flat teal) | Yes, against the text |
| Selene, Pebble (`compare_selene.jpg`, `compare_pebble.jpg`) | Airless asteroids: no atmosphere | Already airless | Pebble's ground looks greyer up close than from orbit (hard sun bleaches it) | Single sun, no air scattering | Grey and rust palettes, violet space | Yes, against the text |
| Ship exterior (`compare_ship.jpg`) | No ship-specific technique in the research beyond the shared lighting | White-grey hull | See §4 | | Hull tinted cooler grey; the same lighting changes apply | See §4 |
| Ship interior (`compare_ship.jpg`, pilot view) | Interior runtime is engine-side in Rodina (research), no colour data | Original interior | Everything Rodina-specific | No evidence | Only the shared light/tonemap changes reach it | Unknown |

Measured colours (mean of sky above / ground below the horizon, hue in degrees, saturation 0-1):

| View | Sol sky hue / sat | Rodina sky hue / sat | Sol ground hue | Rodina ground hue |
|---|---|---|---|---|
| Aurelia approach / low / ground | 210 / 0.60, 210 / 0.65, 211 / 0.36 | 317 / 0.11, 327 / 0.13, 295 / 0.08 | 108, 131, 102 | 21, 24, 25 |
| Cinder approach / low / ground | 212 / 0.29, 210 / 0.64, 211 / 0.34 | 14 / 0.32, 17 / 0.49, 18 / 0.33 | 29, 346, 341 | 17, 18, 19 |
| Verdant approach / low / ground | 210 / 0.63, 210 / 0.65, 210 / 0.51 | 191 / 0.23, 189 / 0.23, 192 / 0.19 | 163, 168, 165 | 162, 153, 153 |
| Selene approach / ground (space) | 228 / 0.33, 227 / 0.16 | 260 / 0.62, 259 / 0.45 | (grey) | (grey) |
| Pebble approach / ground (space) | 228 / 0.16, 232 / 0.07 | 276 / 0.22, 290 / 0.09 | (grey) | (grey) |
| Aurelia orbit rim | blue | first 234 / 0.59 (vivid blue), now 264 / 0.43 (lavender) | | |

## 3. The original Sol look is unchanged

Checked three ways:

1. **Code reading.** With the `sol` style, `PlanetBody.look` is null, so terrain uses the untouched original colour rule
   and the original material path. Every new shader uniform defaults to the original constant, and with those defaults
   each changed line computes the old value (`pow(n, 4)`, `mix(1, albedo, fade * 1)`, `mix(c, orbit, 0) = c`).
2. **Unit test.** `visual_style_test::test_sol_style_keeps_the_original_rules`.
3. **Pixels.** The same 20 views were rendered from the commit before this work (`0646350`, separate checkout) and
   compared with the `sol`-style renders of this branch (`/tmp/claude-0/scratch/pixel_diff.py`):

| View | Mean difference (0-255) | Pixels off by more than 8 |
|---|---|---|
| Orbit, all five worlds | 0.00 - 1.43 | 0.0 - 3.9 % |
| Approach (30 km), all five | 0.70 - 3.18 | 0.1 - 13.2 % |
| Low (900 m), all five | 2.02 - 8.62 | 2.1 - 27.6 % |
| Ground | 14.9 - 36.0 | 42 - 61 % (not comparable, see below) |

Aurelia's orbit view is pixel-identical (0.00). The remaining low-view differences sit only on the ground, never in
the sky, and are run-to-run variance: two renders of the **same** current code differed more (25.7 % of pixels at
Aurelia low) than old against new (13.1 %), because terrain streams on worker threads and the shot is taken whenever
it settles. The ground views are not a valid comparison: the photo tool picks its spot from the sun's position at
the moment the job starts, the worlds turn, and the camera ended up in a different place in each run (the ship and
the hills move in the frame); sky, light and colours look the same in each pair.

## 4. Ship

`compare_ship.jpg`: front three-quarter, beside the player, gameplay chase and pilot view, Sol original against
Rodina-inspired (`tools/ship_shots.gd`, the Rodina set with `SOL_VISUAL_STYLE=rodina`).

- Geometry is identical in both (the style only tints the hull material, `VisualStyle.hull_tint`).
- Rodina style: the hull reads a dark olive-khaki, not the cool grey the tint aims for. Cause: the cool tint
  (0.74, 0.77, 0.84) is multiplied by Aurelia's warm sun (`#fff1d6`) and lit by a peach sky, and faces turned from the
  sun get only the weak back light and 0.5 ambient, so they go dark. Whether that is closer to Rodina's ship is
  **unverified**: no Rodina frame was available. Re-check against footage before tuning it.
- Pilot view: the cockpit takes on the warm light and the violet-peach sky through the canopy; the screens are
  unchanged (emissive).
- Effects (`rodina_effects_entry.jpg`): nose heat glow, sparks blown aft and blue-white engine jets render; they are
  hidden in the `sol` style by construction (`ShipEffects.visible = VisualStyle.is_rodina()`, read in the code, not
  measured in a render). The heat now follows Rodina's entry resistance (see `RODINA_PHYSICS_AUDIT.md` §4), so it
  shows only while entering the air, not at any fast speed in it.

## 5. Regression checks

- Full suite `tools/run_tests.sh`: 267 tests, 6 failures. The same 6 fail on the commit before this work (`0646350`,
  run in a separate checkout: 261 tests, same 6): `audio_library_test.gd` does not load ("reset_warnings" not found)
  and 5 assertions in `ship_screens_decals_test` (duplicate decal names renamed `@Decal@N`). The 6 new
  `visual_style_test.gd` tests pass.
- `tools/playthrough.gd`: PLAYTHROUGH OK in both `SOL_VISUAL_STYLE=sol` and `rodina` (0 script errors), run at
  commit `9b70574`, before the later ramp and flight-model changes (`RODINA_PHYSICS_AUDIT.md`); re-run results for
  those are in `SOL_PHYSICS_IMPLEMENTATION_PLAN.md`.
- `tools/style_switch_check.gd`: PASS. Switching sol -> rodina -> sol in the live scene leaves ship position,
  orientation, velocity, landed state, gameplay mode, world and the terrain height under the ship unchanged, and the
  terrain is rebuilt and shown again.
- Unit test `test_style_changes_colours_but_never_terrain_geometry`: same heights and vertices in both styles.

## 6. Performance

**Not measured.** The cloud container renders in software at about 1 frame per second, so its timings say nothing
about the Mac. What the `rodina` style adds, by construction: one extra shadowless directional light, glow
(bloom), 2 x 28 plume particles and 160 spark particles while thrusting or heating, one 32x16 sphere for the heat
glow, and a few extra shader instructions per terrain and sky pixel. A style switch rebuilds the terrain once.
Run the perf scenario (`tools/perf_run.gd`) on the Mac in both styles to get real numbers.

## 7. Still to do

- Sample every `rodina` colour against real Rodina frames when the reference archive is reachable; until then they
  are inferences.
- Merge with the Mac branch's `src/world/visual_style.gd` (commit `4fcc3b7`, not reachable from here).
- Landforms (dunes, plates, Voronoi plateaus) as a separate world-generation decision with its own ADR.
- Not implemented: subtractive sky dust, the 3-tier distance texture blend, clouds, depth-of-field, an icy family
  (no Morena analogue in Sol).
- Performance on the Mac in both styles.
