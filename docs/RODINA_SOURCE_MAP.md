# Rodina source map for the current Sol tree

Private source checkout used for this pass:

```
/Users/arielbowyer/Downloads/rodina-repo
  8d4abe2 is Sol's remote graphics branch; the Rodina source repo is at f3a340b
  Scripts/Gameplay/EGVehicle.lua
  Scripts/Gameplay/EGBehaviorPlayer.lua
  Scripts/Gameplay/EGPlanet.lua
  Scripts/DataGameplay/EGDataPlanets.lua
  Scripts/DataGameplay/EGDataParticles.lua
  Scripts/DataGameplay/EGDataItems.lua
  Scripts/Gameplay/EGAudio.lua
  Scripts/Gameplay/EGGame.lua
  Scripts/Gameplay/EGCharacterActor.lua
  Scripts/Render/...
  Shaders/PlanetPerun.h, PlanetJarilo.h, PlanetVeles.h, PlanetMorena.h, PlanetAsteroid.h
  Shaders/_perlin.h, _voronoi.h, _fractal.h, Planet_Common.h, _atmosphere.h
```

Local recovery/reference material:

- `/Users/arielbowyer/Documents/Deepseek workspace/rodina-recovery/game-reference/` — full installed 1.6.2
  game tree, including `Shaders/`, `Data/Models`, textures, sounds and fonts.
- `/Users/arielbowyer/Documents/Deepseek workspace/rodina-visual-research/` — trailer, five gameplay videos,
  Steam/guide screenshots, selected frames, contact sheets, palette CSVs.
- `/Users/arielbowyer/Documents/Sol-n14/docs/n13_shots/` — N13 graphical captures.
- `/Users/arielbowyer/Documents/Sol-n14/docs/rodina_reference/` — copied reference frames/palette analysis used by
  the N13 graphics port.
- `/Users/arielbowyer/Documents/Deepseek workspace/rodina-recovery/game-reference/Data/Models/` —
  original EGM models including `Ship1.ShipOpen.egm` and its physics mesh, not integrated.

## Terrain source-to-code links

| Source symbol | Sol destination | Notes |
|---|---|---|
| `PlanetPerun.h:GetPlanetFeatures/GetPlanetHeight` | `HeightFunction._perun_height` | GenerationVars 1–17/100–112 transcribed for Cinder |
| `PlanetJarilo.h:GetPlanetFeatures/GetPlanetHeight` | `HeightFunction._jarilo_height` | dune + plateau + holes; Aurelia |
| `PlanetVeles.h:GetPlanetFeatures/GetPlanetHeight` | `HeightFunction._veles_height` | Verdant |
| `PlanetMorena.h` | `HeightFunction._morena_height` | placeholder pending a real Morena-style Sol world |
| `PlanetAsteroid.h` | `HeightFunction._asteroid_height` | partial; not enabled on Selene/Pebble yet |
| `_perlin.h:FractalPerlin` | `HeightFunction._fractal` | FastNoiseLite C++ Perlin replacement; shape preserved, exact noise hash not |
| `_perlin.h:FractalPerlinDerivative` | `HeightFunction._warp` | finite-difference direction, explicit ADAPT |
| `_voronoi.h` / `VoronoiPoints` | `HeightFunction._voronoi_base` | **ADAPT**: GPU constant-buffer points unavailable; cellular field used |
| `GenerationVars` in `EGDataPlanets.lua` | `HeightFunction` constants and `TerrainProfile.grammar` | numeric source values; planets map by atmosphere/orbit evidence |
| `Planet_Common.h` cubesphere bake | not ported | Sol generates its own chunked sphere; keep Sol mesh/LOD |

## Correction to stale research claims

Earlier N13 text says no Rodina images/video were available. That was true for the earlier session, but is now
false: the trailer, five gameplay videos, selected frames, contact sheets and palette reports exist in
`rodina-visual-research`, and N13 has captured Sol comparisons in `docs/n13_shots/`. The N13 parity document is
the later, corrected reference for visual evidence.
