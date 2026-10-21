# Rodina planet types and their Sol counterparts

Companion to `docs/RODINA_ART_STYLE_TECHNICAL_SPEC.md` (read its §0: no images were available; colours are
inferences). Tags: `[C]` confirmed in shipped Rodina source per `research/rodina-starfall-reference/04`,
`[INF]` inference, `[U]` unknown.

## 1. What the evidence establishes per world

From `EGDataPlanets.lua` and the height shaders, as cited in research `04` §2.2, §3.3, §3.5, §5.1:

| World | Radius | Orbit | Atmos. density | Gravity | Height grammar `[C]` | Terrain features `[C]` | Colours |
|---|---|---|---|---|---|---|---|
| Perun (Zosia same data) | 10,000 km | 0.33 AU (innermost) | 1.5 (thick, >1) | 1.15 | domain-warped Voronoi lowlands, plateau mask, masked mountains, smooth-rimmed holes/craters | 5 | `[U]` |
| Veles | 5,000 km | 0.75 AU | 2.0 (thickest) | 0.9 | Voronoi base, fixed large amplitudes (20 km / 15 km) | 5 | `[U]` |
| Jarilo | 6,000 km | 1 AU | 0.75 (thin: tint only) | 1.0 | Perun grammar + plateau warp, dunes, hole override | 6 (most) | `[U]` |
| Morena | 4,000 km | 2 AU (outermost) | 1.2 | — | hand-coded cracked plates, small-crack network, hills vs dunes, quantised dune ripple | 5 | `[U]` |
| AsteroidLarge / Asteroid | ~11-17 km / ~1-3 km | belt | 0 (airless) | — | non-spherical: radius offset + additive mountains | 3 | `[U]` |
| Zorica (star) | 0.8 sun | — | 50,000 km shell, radiation damage | — | — | — | `[U]` |

Other established facts: all planets have 200 km atmospheres; every planet has its own ground-vs-orbit colour
blend, two atmosphere colour pairs, a terminator begin/end, star halo and sunset parameters (`04` §5.1 `[C]`);
the tutorial starts on an asteroid (`EGDataZoricaScene.lua:98-144` `[C]`); ice mine buildings exist
(`XenoMineIce`, `05`), but which world they sit on is not stated `[U]`.

**Not established:** any surface, sky or cloud colour; cloud layers (no cloud system is mentioned in the
rendering analysis `[U]`); surface-prop density; what the worlds look like from orbit or at ground level. The
brief's example families (ochre/salmon rocky, orange/red barren, teal/green alien, cyan/blue icy, airless dark)
could not be checked against any frame.

## 2. Sol's worlds and the family each is given

Sol has five bodies (`src/world/star_system.gd`), now defined by `data/planets/*.tres` (ADR 0009). Mapping by the evidence that does exist (orbit order,
atmosphere thickness, airlessness) `[INF]`:

| Sol body | Sol facts | Closest Rodina analogue | Family in the Rodina profile `[INF]` |
|---|---|---|---|
| Cinder | innermost, 60 km atmosphere, red/orange palette | Perun (innermost, warm) | **Ember barren**: rust and ochre rock, dusty orange-pink sky, hot white-gold sun |
| Aurelia (home) | 1 AU-like home world, 200 km atmosphere, green palette | Jarilo (1 AU, thin atmosphere, dunes) | **Ochre steppe**: salmon/ochre lowlands, pale sandstone highlands, dark rock on slopes, light blue-violet sky with a warm horizon |
| Verdant | outer, thickest atmosphere (300 km) | Veles (thickest atmosphere) | **Teal alien**: deep teal-green lowlands, mossy olive uplands, dense blue-green haze, sun filtered toward cyan |
| Selene | airless moon | Asteroid family | **Airless grey**: dark grey-brown dust, black-violet sky by day, hard white sun, almost no ambient |
| Pebble | asteroid | AsteroidLarge | **Airless rust**: dark umber rock, same airless sky |

No Sol body corresponds to Morena (outermost, cracked, possibly icy). An **icy family is defined only if a Sol
world needs it**; none does today, so none is invented.

## 3. What each family controls (Sol `PlanetLook`)

Per family: ordered terrain features (colour + altitude/latitude/slope/noise gates), ground-to-orbit colour,
detail-texture scale and contrast, sky zenith / horizon / sunset colours, fog colour and density, sun colour,
back-light colour and strength, ambient colour, atmosphere rim colour. Values live in
`src/world/visual_style.gd` (one function per family, so a new family is one function and one table entry).

## 4. Landforms (N14 changes this)

N14 has now implemented the Perun/Jarilo/Veles and airless asteroid grammars as `TerrainProfile.Grammar` values.
They intentionally change collision and saved surface positions; the generation revision and ship re-seat policy
are in `N14_TERRAIN_SAVE_MIGRATION.md`. Morena's cracked-plate grammar is still a placeholder, and the Voronoi
point buffer is an explicit ADAPT because the GPU constant buffer was not recovered.
