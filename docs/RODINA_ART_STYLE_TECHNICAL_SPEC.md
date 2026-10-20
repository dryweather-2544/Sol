# Rodina art style: technical specification for Sol

Status: Stage 1 of the Rodina visual mission, written in a cloud session (Godot 4.7.2, branch
`claude/sol-vtol-ship-overhaul-9eglhk` on top of `n9-art-audio`). Read the evidence limits first.

## 0. Evidence limits (read first)

| What the brief expected | What was actually available here |
|---|---|
| The canonical Mac checkout (`~/Developer/Sol-n9-test`, `Sol-canonical-merge`) | Not on this machine. |
| Commit `4fcc3b7` with `src/world/visual_style.gd` | Not on any GitHub branch of `dryweather-2544/Sol` (all five checked). Not in `Sol-Assets`. |
| `RODINA_VISUAL_*.md`, `RODINA_VS_SOL_VISUAL_AUDIT.md`, `rodina-visual-research/`, contact sheets, reference frames | Not in Sol, not in any `Sol-Assets` branch, not on disk. |
| Extracted `.fx` / `.h` shaders, `EGOptions.lua` | Not on disk. |
| Rodina website, Steam page, Steam guide, video sites | Blocked by this environment's network policy (proxy 403 / DNS failure). |
| **Available:** `research/rodina-starfall-reference/` (static analysis of the shipped Rodina 1.6.2 tree, with file:line citations) | Read in full for planets (`04`) and rendering (`_work/rendering_notes.md`). |

Consequences, applied throughout:

- **No Rodina image or footage was inspected in this session.** No colour was sampled. Every colour value Sol uses
  for the Rodina profile is a **design inference**, labelled `[INF]`, chosen to express a technique or family that
  the text evidence establishes. Re-sample them against real frames when the reference archive is available.
- File:line citations below are **second-hand**: they come from the research documents, which cite the shipped
  Rodina files. They were not re-verified against the files themselves (the files are not here).
- `CLAUDE.md` forbids copying Rodina code, assets or data. Sol re-implements the *techniques* in its own shader
  code with its own constants. Where the research quotes a Rodina constant, Sol does not reuse it; it picks its
  own value and says so.
- Because the Mac `visual_style.gd` is unreachable, this branch introduces its own `src/world/visual_style.gd`.
  **It will need merging with `4fcc3b7`.** It keeps the same public surface the brief describes (sol|rodina,
  saved in settings, `SOL_VISUAL_STYLE` override) to make that merge mechanical.

Tags: `[C]` confirmed in shipped source per the research, `[INF]` inference, `[U]` unknown.

## 1. Rendering techniques Rodina uses (evidence) and Sol's response

### 1.1 Lighting
| Rodina | Evidence | Sol (rodina profile) |
|---|---|---|
| Lambert diffuse, linear point attenuation, Blinn specular | `_lighting.h:19-64` `[C]` | Godot's default lighting is kept (no custom light model). |
| **Backside term** `(1 - N·L) × Backside` lights faces turned away from the star: the night-side / contact fill | `_lighting.h:72-74,128` `[C]` | A weak, shadowless directional **back light** opposite the sun, tinted per planet. Same intent, Sol's own numbers. |
| Global `Ambient` used when no star is in range | `_lighting.h:107-110` `[C]` | Ambient lowered and tinted per planet (Sol: blue-grey fill 0.6). |
| Fresnel-boosted emissive (×2 at grazing angles) | `_lighting.h:118-120` `[C]` | Not reproduced globally; noted for the effects pass. |
| **No shadows of any kind** | byte-level absence across all 72 sources `[C]` | Sol already has `shadow_enabled = false` on the sun. Kept. |
| **No tonemap, gamma pass, exposure or LUT**; bloom adds in the same space, highlights clip | absence across all sources `[C]` | Rodina profile switches the tonemapper from Filmic to Linear and turns on additive glow. |
| Terminator: per-planet begin/end around N·L, smoothed | `_lighting.h:148-166` `[C]` | Sol already fades daylight with sun height; per-planet sun tint added. |
| Star light tinted toward the planet's filter colour by atmosphere density | `_lighting.h:169-189` `[C]` | Sun colour per planet family `[INF]`. |

### 1.2 Atmosphere
| Rodina | Evidence | Sol (rodina profile) |
|---|---|---|
| Not a scattering model: analytic angular ramps from one angle seen from the planet centre | `_atmosphere.h` `[C]` | Sol's sky is already a gradient, not scattering. Kept simple. |
| Two authored colour pairs per planet (`AtmosphereScatterColor1/2`, `AtmosphereFilterColor1/2`) blended by horizon and sunset factors | `_atmosphere.h:86-103`, `standard.h:144-147` `[C]` (values `[U]`) | Per-planet **zenith / horizon / sunset** colours drive the sky, fog and rim `[INF values]`. Sol had one blue sky for every world. |
| A fixed ground band under the horizon (~38°) | `_atmosphere.h:41` `[C]` | The horizon colour reaches well below the horizon line (own band width). |
| Sun halo, squared falloff, **widens through sunset** | `_atmosphere.h:74-77` `[C]` | Sky shader: squared halo whose width grows as the sun nears the horizon (own constants). |
| Sunset only on the star-facing side | `_atmosphere.h:79` `[C]` | Sunset tint weighted by facing the sun. |
| `AtmosphereDensity` > 1 means a thick, star-occluding atmosphere | `_atmosphere.h:8-17` `[C]`; Perun 1.5, Veles 2.0, Jarilo 0.75, Morena 1.2 `[C]` | Per-family haze density `[INF mapping]`. |
| Terrain gets grazing-angle haze; objects get distance haze only | `_atmosphere.h:177-216` `[C]` | Godot fog is distance-based; per-family fog colour = horizon colour. |
| Horizon drives depth-of-field blur | `_atmosphere.h:364-378`, `RodinaAtmosphereBlur.fx` `[C]` | Not reproduced (camera DOF far blur would blur the ship). Listed as remaining work. |

### 1.3 Sky and stars
| Rodina | Evidence | Sol (rodina profile) |
|---|---|---|
| Galaxy cube-map bake: milky-way band, dust, Voronoi star fields | `PlanetSkybox.fx:42-147` `[C]` | Sol keeps its own Sol-Assets starfield panorama (no Rodina asset). |
| A coloured, near-black **purple** base under the stars | `RodinaSkybox.fx:33` `[C]` (constant not reused) | Space base colour is a near-black violet chosen independently `[INF value]`. Sol: near-black blue. |
| Stars deliberately **over-bright and blue-shifted** so they bloom | `RodinaSkybox.fx:34` `[C]` | Stars brightened with a blue bias; glow on. |
| Dust **subtracts** light (dark lanes), not added glow | `RodinaSkybox.fx:36` `[C]` | Sol's panorama is darkened in its dimmer, dusty areas (contrast curve), own approach. |
| Twinkle computed but disabled | `RodinaSkybox.fx:40` `[C]` | No twinkle (Sol has none either). |

### 1.4 Terrain surface
| Rodina | Evidence | Sol (rodina profile) |
|---|---|---|
| Up to 8 authored material features per planet, each gated by **altitude × latitude × slope × 4 feature masks** (multiplicative AND), composited painter-style | `RodinaTerrain.fx:40-75,195-298` `[C]` | ChunkMesher colouring becomes a per-family **ordered feature list** with altitude, latitude, slope and noise-mask gates, first-match-wins coverage. |
| Bands widen up to 4× with distance (cheap anti-aliasing) | `RodinaTerrain.fx:45` `[C]` | Vertex colours are already smooth per vertex; the detail shader fades over a long range instead. |
| Texture tiers at 500 m / 5 km / 50 km / 2,000 km: large-scale texture, no metre-scale grit | `RodinaTerrain.fx:21-37` `[C]` | Detail texture tiles enlarged (Sol: 4 m / 6 m / 29 m) and its contrast lowered; this is the main cause of Sol's "high-frequency" look. |
| Base colour cross-fades from a ground hue to a **space hue** with the viewer's altitude | `RodinaTerrain.fx:202-204` `[C]` | Terrain shader mixes toward the family's orbit colour with viewer altitude. |
| Triplanar sharpness 10 | `_textureMap.h:127` `[C]` | Sol uses 4; raised in the Rodina profile. |

### 1.5 Effects
| Rodina | Evidence | Sol |
|---|---|---|
| 104 particle materials; each style has colour/alpha/size keys over lifetime, a blend style, decay | `07` §8.5.4 `[C]` | Exhaust and fire effects get colour-over-life ramps and additive blend in the Rodina profile. |
| "Stepped/pixelated" particles, RetroMode | **Not in the available research.** `[U]` | Not implemented; no global pixelation (as the brief requires). |

### 1.6 Ships and interiors
The available research describes ship *systems*, not their colours. Ship colour targets are `[U]`. The Rodina
profile applies a darker, cooler hull tint through the style switch only (the brief reports Sol's hull reads
brighter and more yellow than Rodina's). That premise itself is unverified here.

## 2. Architecture in Sol

- `src/world/visual_style.gd` — `VisualStyle`: the active profile (`sol` or `rodina`), chosen by
  `SOL_VISUAL_STYLE` (environment, wins), else `GameSettings.visual_style`. Holds the global look (tonemap,
  ambient scale, glow, space colour, star tint) and returns one `PlanetLook` per body id.
- `src/world/planet_look.gd` — `PlanetLook`: everything visual for one world: terrain features (palette and
  gates), detail texture scale/contrast, sky zenith/horizon/sunset colours, fog, sun tint, back light,
  atmosphere rim colour. The `sol` profile builds its looks **from the existing BodyDef/TerrainProfile values**,
  so Sol renders exactly as before.
- Geometry is never in the style: `HeightFunction`, collision, landing, POIs and saves are untouched by a switch.
  Switching rebuilds terrain chunks (colours are baked into vertices) and re-applies the environment.

## 3. Out of scope for a visual style, and why

Rodina's landforms come from per-planet height grammars (warped Voronoi cells, plateaus, craters, dunes, cracked
plates; `PlanetPerun/Veles/Jarilo/Morena/Asteroid.h` `[C]`). In Sol the height function is the single source of
truth for the mesh, ship ground contact, walking and POI placement. A style switch that changed it would change
collision and could put a saved ship underground, which the brief forbids. Recreating those landforms is a
**world-generation change** (new terrain profiles, POI re-validation, save-version decision) and needs a separate
decision. See `docs/RODINA_PLANET_TYPES.md` §4.
