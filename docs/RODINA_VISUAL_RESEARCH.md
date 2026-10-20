# Rodina visual identity — research dossier

Status: evidence-led visual study for Sol. This is **not** a generic “make it retro” brief and not a
claim that Sol must become a pixel-art game. It records what Rodina's released screenshots, video
and actual extracted shader/options files show, how the current merged Sol build differs, and which
changes would move Sol toward the same visual identity.

No visual rewrite was started before this dossier. The reference library is intentionally local and
not shipped with Sol.

## 1. Method and reference corpus

### What was actually inspected

- **13 official Steam screenshots** for Rodina (app 314230), downloaded from the Steam appdetails
  API. These are the strongest released-build reference.
- **Steam 1.4.2 trailer**, full 124 s, sampled every 3 s (41 frames). Used for flight, entry, fire,
  interiors and combat.
- **15 images from the Steam “Ultimate Rodina Guide”**, including planet, cockpit, terrain and
  interior shots. One image was corrupt and excluded.
- **5 gameplay videos**, downloaded at ≤480p with yt-dlp and sampled:
  - `T90Pw7FcJx8` — 38:20 gameplay, 30 s samples.
  - `RdXAbinofDE` — 13:54 gameplay, 20 s samples.
  - `oVyZD1wo0vs` — 63:31 showcase, 60 s samples.
  - `0Idoe7EjOZU` — 18:23 gameplay, 20 s samples.
  - `yLfsaJK63wo` — 20:52 recent gameplay, 25 s samples; facecam-heavy, used sparingly.
- **Actual extracted Rodina 1.6.2 files** for technical corroboration:
  `Shaders/PlanetJarilo.fx`, `Planet_Common.h`, `RodinaTerrain.fx`, `_atmosphere.h`,
  `RodinaAtmosphereFilter.fx`, `RodinaImageBloomBegin/End.fx`, `RodinaParticles.fx`,
  `_lighting.h`, `RodinaSkybox.fx`, `PlanetSkybox.fx`, and `Scripts/DataGameplay/EGOptions.lua`.

Local library:
`~/Documents/Deepseek workspace/rodina-visual-research/`

- 32 selected Rodina frames by category.
- 11 current merged Sol frames under comparable orbit/atmosphere/ground/interior conditions.
- Contact sheets and four direct Rodina-vs-Sol comparison sheets.
- `sources.csv` with source URL/timestamp for every selected frame.
- `palette_report.csv` with approximate sampled mean/HSV/dominant colours.

### What was not available

- No direct, frame-exact 1.6.x capture of every planet/lighting state. Steam screenshots are a mix of
  official captures, likely at different settings/builds; YouTube footage is compressed and some is
  older.
- No engine renderer binary/decompilation. Shader/option evidence is direct, but the exact engine
  post chain and platform-specific gamma are not fully reconstructable.
- No identical scene comparison between Rodina and Sol (different planets, cameras, times). Palette
  measurements are approximate, not colour-managed comparisons.

Contact sheets (local):
`rodina-visual-research/contact_sheets/rodina_master.jpg`,
`compare_space.jpg`, `compare_surface.jpg`, `compare_interior.jpg`, `compare_entry_effects.jpg`,
`sol_current.jpg`.

## 2. The visual identity in one paragraph

Rodina looks like a **small, hand-built, brightly coloured 2000s space sim** rather than a modern
physically based space game. Space is almost black but tinted purple; stars are crisp points and the
Milky Way is a painted/procedural band. Planets are large, simple, highly saturated colour fields —
ochre, salmon, cyan ice, lavender — with broad low-frequency mountains and a thin atmospheric limb.
Daylight skies are flat two-colour gradients (salmon/cyan, green/pink, lavender/blue), with a hard
sun disc and visible stars even in daylight. Ships are mostly **black silhouettes** with a few
coloured emissive details. Interiors are dark grey/green boxes with strong, simple coloured lights
and low-resolution detail. Effects are chunky, stepped, pixelated sprites and screen tints. The
interface is a cyan/blue angular bitmap HUD. Nothing is glossy, volumetric or global-illuminated;
the look comes from **strong colour, negative space, silhouettes and low-detail geometry**, not from
texture density.

## 3. Colour palette

Approximate sampled values from `palette_report.csv`. These are JPEG/photo measurements, not
authoritative engine values; use them as targets and verify in-game.

| Context | Rodina sampled dominant colours | Observation |
|---|---|---|
| Space/orbit (official screenshot 6) | `#0a0311` `#140d1a` `#7e5837` `#d4a065` | near-black purple space; ochre planet; no blue atmospheric veil |
| Cyan-sun horizon (screenshot 12) | `#0f0917` `#525b86` `#58939c` `#50efe0` | huge cyan sun; lavender/blue sky; black mountain/ship silhouettes |
| Salmon daylight (screenshot 1) | `#ae7b70` `#2b1808` `#ba9996` `#4c3422` | salmon sky; dark brown mountains; cyan-white sun; snow blue-grey |
| Purple surface (screenshot 3) | `#543b6d` `#5f457d` `#684c86` `#2d1f37` | saturated lavender ground and sky; black ship; warm red trails |
| Cyan ice (screenshot 7) | `#2b80ab` `#439ab9` `#77b696` `#97c4a5` | green-cyan sky; electric blue ice; red sun |
| Fire/interior (screenshot 5) | `#790301` `#b91f03` `#3b1011` | near-monochrome red room; pixelated fire and smoke |
| Green interior (screenshot 4) | `#0f180f` `#152012` `#192a18` | very dark green-grey interior; cyan/orange practicals |
| Plain interior (screenshots 8/11) | `#1a1818` `#3e3e3e` `#050505` | dark grey; bright white window/sun contrast |
| Combat effects (screenshot 9) | `#544a81` `#36195c` `#57acaf` | purple/blue space; cyan-green trails; orange explosions |

Current merged Sol (from `palette_report.csv`):

| Context | Sol sampled dominant colours | Difference |
|---|---|---|
| Orbit | `#000000` `#b6c5d7` `#444b54` | blue-white atmospheric veil and white clouds; much lower saturation |
| 50 km | `#a7b5cd` `#99abc9` `#d2e1ec` | pale blue/white haze; almost no colour identity |
| 5 km/ground | `#697c76` `#92acc7` `#58623d` | desaturated green/blue; bright ambient fill |
| Cockpit | `#434d4e` `#96aec7` | grey/blue; modern clean panels |
| Interior | `#736e5d` `#8b877e` `#0b1217` | far brighter and warmer than Rodina's dark interiors |

Quantitative tendency across the selected frames: Rodina's mean saturation is commonly 0.3–0.9
(strongly coloured planets/skies; interiors dark but still tinted), while Sol's comparable views are
commonly 0.10–0.22. Rodina has a bimodal palette: near-black negative space plus one or two
saturated body colours. Sol currently averages those into a bright, low-saturation blue-green haze.

## 4. Lighting and shading

### Direct evidence from extracted shaders

- `_lighting.h` implements a simple material model: ambient + diffuse + optional specular and
  backside, plus emissive. No PBR metallic/roughness workflow, no image-based lighting, no SSAO/GI.
- `standard.h` passes `StarLightColor`, `StarAmbientColor`, a sun direction, and a small per-instance
  light array. There is no screen-space global illumination.
- Planet day/night is a **terminator function** on the planet normal, with ambient derived from
  `PlanetAmbientColor` and star light; the terminator and planet ambient are data-driven.
- The atmosphere filter is a **two-colour altitude/horizon blend**, not a physically integrated
  Rayleigh/Mie simulation. `GetAtmosphereFilterColor`/`GetAtmosphereScatterColor` lerp
  `AtmosphereFilterColor1/2` and `AtmosphereScatterColor1/2`; density/horizon determine the mix.
- Sun/sky is a simple star disc/halo plus procedural skybox, not a volumetric sun/atmosphere system.

### What the frames show

- Strong directional light and large unlit shadow sides. Mountains become near-black silhouettes.
- Ambient is low; shadows are not lifted to a blue-grey fill. Interiors are genuinely dark.
- Specular highlights are sparse and hard; no broad glossy reflections on ships or rocks.
- The sun is a large, flat disc with a coloured halo. It can be cyan, red, orange or white; it does
  not obey a single physically white star.
- Stars remain visible in daylight and twilight skies; there is no thick atmospheric extinction.
- Interiors use strong cyan/orange/red practical lights, often emitted by a single fixture, with
  almost no fill light. The result is graphic, not photographic.
- Planet night sides are very dark, often black; city/probe markers are tiny points of colour.

## 5. Atmosphere, sky, clouds and space

- Rodina's surface sky is a flat gradient with a hard sun, a horizon haze band and visible stars.
  It changes hue by planet (salmon, lavender, green, cyan) and by sun elevation.
- From orbit, planet limbs are thin and coloured, not thick and white. No broad volumetric cloud
  decks are visible in the inspected released screenshots. Some planets have surface haze/snow, but
  the defining look is the flat coloured disc and thin limb.
- The star field is high-contrast and graphic, with a painted Milky Way band. It is not a modern
  HDR starfield with bloom-heavy nebulosity.
- The current Sol build uses a physical atmosphere shell (Rayleigh/Mie), a separate cloud shell,
  screen-space SSAO, ACES tonemapping, ambient fill and fog. That produces a materially different
  visual language: soft white-blue limb, volumetric-looking clouds, washed contrast, fewer visible
  stars, and a lower-saturation sky.

## 6. Terrain, scale and composition

- Terrain is built from broad, low-frequency shapes: plateaus, ridges, crater/hole fields, dunes.
  Individual rocks and vegetation are sparse; the silhouette of the landform carries the scene.
- Terrain textures are triplanar/distance-blended detail textures, blended toward a small set of
  feature colours. Up close there are textures, but the dominant read is still geometric colour.
- The surface is not covered in grass, pebble scatter or high-frequency micro-detail. Rodina uses
  large colour fields and a few props.
- The horizon is close and readable. The planet feels large because the ground curves and fills the
  frame, not because of high-detail texture noise.
- Ships are small in the frame relative to the planet and terrain, reinforcing scale. Sol's cargo
  hull is large, bright and highly detailed, which makes the scene read as a ship showcase rather
  than a tiny craft in a huge world.
- Rodina's composition often leaves large areas of flat sky/space around the ship; the ship is a
  dark shape near the centre. Sol's high-contrast yellow/black hull competes with the background.

## 7. Ship exterior, interiors and HUD

### Ship exterior

- The player ship is a **black/low-value silhouette** in most external shots, with a few cyan,
  orange or red emissive accents. Hull panel detail is present but mostly lost in darkness.
- It reads as a compact wedge/insect shape, not a colourful cargo freighter. The current Sol cargo
  hull is a detailed yellow/black PBR model with strong edge highlights, visible panel variation and
  a large readable silhouette.
- Rodina's ship is often seen against a saturated planet, so the silhouette is the point. Sol's
  material/scale pulls attention to the ship.

### Interiors

- Dark grey/green metal boxes; simple bevels; flat panels; visible large-scale normal/roughness
  variation is minimal; local coloured lights (cyan screens, orange/red fire) carry the mood.
- Sparse furniture and props; large negative space. Ceiling/floor panels repeat at a readable scale.
- The current Sol interior is bright cream/grey with clean PBR materials, dense sci-fi props,
  blue/orange MFDs and strong ambient fill. It reads as a modern, well-lit spacecraft rather than
  Rodina's dark, improvised industrial interior.

### HUD / interface

- Rodina uses a cyan/blue angular bitmap look: stepped corners, blocky bars, small pixel font,
  high-contrast white/cyan text, overlays with little transparency. It is intentionally low-res.
- The current Sol HUD is clean dark cards with a modern sans-serif font, soft rounded/rectangular
  panels, and detailed subsystem telemetry. It is more legible and modern, but not visually Rodina.
- `EGOptions.lua` confirms low-res inventory (`InventoryPixelSize=2`), optional `RetroMode` at
  `RetroModePixelSize=4.5`, a 60° default FOV, FXAA, bloom radius `.03`, skybox resolution 1024.
  RetroMode is **optional and default false**; the pixel character of effects/UI does not require
  claiming the whole game is rendered at 4.5× pixel scale.

## 8. Effects and post-processing

- Particles are simple camera-facing quads with keyframed colour/size and emissive bloom; effects
  appear as chunky blocks and stepped alpha, especially fire, smoke and projectile trails.
- Bloom is a simple additive/downsample pass (`RodinaImageBloom*`), not a modern multi-scale
  physically based bloom. It is applied to emissive sprites, sun and HUD, producing hard halos.
- Fire/entry is a **screen-filling coloured overlay plus large pixel sprites**, not a smooth
  refractive plasma shell. The trailer shows orange/purple blocky fire around the silhouette.
- Combat trails and explosions use stepped colour/alpha and visible pixel edges. There is no
  cinematic motion blur or volumetric smoke.
- Rodina's default options include bloom but no SSAO/GI/volumetric fog. `AllowBlur` is an optional
  DOF/atmosphere effect, not modern screen-space blur by default.

## 9. How the current Sol build differs

The merged Sol build is technically more advanced in exactly the areas that erase Rodina's identity:

- **Physical atmosphere** (`atmosphere_scatter.gdshader`) vs Rodina's two-colour filter.
- **Cloud shell and atmospheric cloud layer** vs Rodina's flat skies/thin limbs.
- **ACES tonemapping, SSAO, ambient fill, soft fog and modern bloom** vs Rodina's low-ambient,
  high-contrast, simple post stack.
- **PBR cargo hull** vs Rodina's dark silhouette ship.
- **High-frequency terrain detail, grass/rock scatter and dense props** vs low-frequency coloured
  terrain.
- **Modern HUD/font and detailed telemetry** vs cyan angular bitmap HUD.
- **Smooth translucent plasma envelope** vs stepped pixel fire/overlay.
- **High native resolution with smooth edges** vs low-res UI/effects (and optional RetroMode).

The most important point: Sol's rendering is not “broken”. It is producing a **different art
direction** — bright, smooth, physically based, blue-green and detail-dense. Changing a few colours
will not recreate Rodina; the atmosphere, lighting model, ship value, terrain frequency and UI all
push in the same opposite direction.

## 10. Confidence and gaps

High confidence:

- Released screenshots and actual trailer/video show the palette, silhouette, terrain and UI.
- Extracted shaders prove the simple lighting, two-colour atmosphere, simple bloom and particle
  model.
- Current Sol screenshots/code show the opposing physical/PBR/detail direction.

Medium confidence:

- Relative colour measurements across different captures/monitors; not colour-managed.
- Which footage corresponds exactly to 1.6.2 vs older builds; Steam screenshots are treated as the
  released baseline.
- The exact amount of `RetroMode` used in official screenshots (option exists but likely off).

Unknown:

- Exact engine camera/renderer post-stack and gamma on the developer's monitor.
- Full planet-by-planet data values; Rodina stores atmosphere/filter/feature colours in data, not
  in one universal palette.
- Whether some Rodina shots use custom mods or debug settings.

## P1 implementation audit

P0/P1 was implemented after this research. The profile is reversible via the pause-menu setting or
`SOL_VISUAL_STYLE`; see `RODINA_VISUAL_P1_RESULTS.md` for the implementation and comparisons.

Actual results that improved fidelity:

- near-black purple space with visible stars;
- flat salmon/teal sky instead of the physical blue-white atmosphere;
- a hard cyan sun disc and much lower ambient/SSAO/ACES contribution;
- clouds hidden in the alternate profile;
- a simple cool two-colour orbital limb instead of the thick scattering shell;
- distinct authored sky/sun palettes for Aurelia, Cinder, Verdant and airless bodies.

Changes that did not improve the result and were rejected:

- keeping the physical scattering shader and only recolouring it: the limb remained too thick and
  made the orbit read as Sol with a tint;
- retaining the existing cloud shell: it dominates the sky and hides the reference's flat horizon;
- a wide additive atmosphere rim: it produced a brown/tan band over the green terrain; the final
  version uses a much tighter rim and a cool limb colour.
- a global saturation multiplier: not used; the visible colour changes come from per-body authored
  palettes and a warmer per-body sun light.

Still visibly wrong after P1: terrain is green and detail-dense, the cargo hull is bright and large,
the HUD is modern, and entry effects remain smooth. Those are P2/P3/P4/P5 work, not P1 failures.

## P2/P3 implementation audit

P2/P3 added a dark material override and far camera framing for the cargo hull, plus separate
per-body terrain palettes, plain vertex-colour terrain (no high-frequency detail texture) and a
35% rock-scatter density for Rodina mode. The Sol profile remains unchanged.

What improved: the yellow cargo hull now reads as a small dark silhouette; terrain is brown/ochre
instead of green and loses the grass-like detail; per-body palette data is distinct.

What did not: a 200 m camera reduced the ship to a dot; the current 100 m framing is a compromise.
Retaining the bright emissive maps left a white canopy, so emission was reduced. The local captures
sit on a low-relief plain, so the large mountain silhouettes seen in the references still need a
dedicated terrain-location capture. The far camera costs low-descent performance (Rodina ~64 fps vs
Sol ~79 fps at 1600x900), which needs a follow-up LOD/performance pass.
