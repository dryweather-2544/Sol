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

PLACEHOLDER_SOL_INTACT

## 4. Ship

PLACEHOLDER_SHIP

## 5. Regression checks

- Full suite `tools/run_tests.sh`: 267 tests, 6 failures. The same 6 fail on the commit before this work (`0646350`,
  run in a separate checkout: 261 tests, same 6): `audio_library_test.gd` does not load ("reset_warnings" not found)
  and 5 assertions in `ship_screens_decals_test` (duplicate decal names renamed `@Decal@N`). The 6 new
  `visual_style_test.gd` tests pass.
- `tools/playthrough.gd`: PLAYTHROUGH OK in both `SOL_VISUAL_STYLE=sol` and `rodina` (0 script errors).
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
