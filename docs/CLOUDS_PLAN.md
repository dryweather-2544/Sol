# Planet atmosphere and clouds: findings and plan (2026-10-18)

Branch `planet-clouds` (from `n9-art-audio` @ `8e5e2f1`). Nothing built yet; this is what was checked and what I would build.

## What the game has today (read from the code, seen in `tests/visual/out/clouds_base/`)
- No clouds anywhere. Sky = a flat blue gradient in `space_sky.gdshader` plus a little distance fog (`SpaceEnvironment.set_daylight`).
- Atmosphere = `AtmosphereShell`: a sphere with a thin additive rim glow (`atmosphere_rim.gdshader`), no scattering. Impostor planets (other bodies seen from far) are flat-coloured spheres.
- Worlds: Aurelia (6000 km radius, 200 km atmosphere), Cinder (4200 km, 60 km, toxic), a 300 km-atmosphere outer world, airless Selene and an asteroid.
- Baseline looks: at 9000 km the real terrain already reads as a coloured globe with a blue rim; at 60 km altitude the ground and sky are flat; nothing has depth or weather.

## Why my earlier atmosphere test failed, and what fixes it (confirmed by reading code, not yet run in Sol)
A Sol planet is 6,000,000 m radius, and float32 shaders cannot subtract two squared numbers that large (a naive ray-sphere test gives noise). Zylann's addon assumes small units; I never found the exact failing line.
[cuberact's atmosphere shader](https://github.com/cuberact/godot-cuberact-planet-chunked-lod) (MIT, Sean O'Neil GPU Gems 2 scattering, Godot 4.6, Earth-radius planet, orbit to ground) avoids it: the sphere mesh itself supplies the far end of each ray, the near end is only solved when the camera is outside, heights come from `length()` and are scaled by the atmosphere thickness. It runs 4 samples per pixel on the shell only.
It matches how Sol already draws atmospheres (a shell mesh per planet), so it is close to a drop-in for `AtmosphereShell`.

## Candidate code (licences read from the repositories' API/LICENSE; none downloaded)
| Project | Licence | Use for Sol |
|---|---|---|
| [cuberact planet atmosphere.gdshader](https://github.com/cuberact/godot-cuberact-planet-chunked-lod) | MIT | **Base for scattering** (orbit to ground, cheap) |
| [Zylann atmosphere](https://github.com/Zylann/godot_atmosphere_shader) | MIT | Already in the cargo-hull branch's look-dev; keep as reference for cloud-coverage cubemaps (`NoiseCubemap`) |
| [voithos/godot-precomputed-atmosphere](https://github.com/voithos/godot-precomputed-atmosphere) | MIT | Hillaire LUT sky (compute shaders, Godot 4.4). States it does not implement space views, and has no clouds; an option only if the O'Neil look is not enough on the ground |
| [remijean/godot-3d-planet-generator](https://github.com/remijean/godot-3d-planet-generator) | MIT | Planet-body cloud shader to read for the from-space look (not inspected yet) |
| [Bonkahe/SunshineClouds2](https://github.com/Bonkahe/SunshineClouds2) | MIT | Good clouds but a flat layer with no planet curvature: not usable between orbit and ground |
| [MMqd nishita sky + volumetric clouds](https://github.com/MMqd/godot-nishita-sky-with-volumetric-clouds) | MIT | Sky-shader clouds for Godot 4.0 (2023); reference only |
Techniques to follow: Schneider, Horizon Zero Dawn volumetric clouds (SIGGRAPH 2015, Nubis 2017/2023); Hillaire 2020 for the atmosphere; O'Neil 2004 for the cheap version.

## What I would build, in order (each step playable and measured before the next)
1. **Scattering atmosphere** (replace the rim shell): adapt the cuberact shader into `AtmosphereShell`; per-world colours (Aurelia blue, Cinder orange); fade the sky gradient into it as you descend. Cost: 4 samples per pixel on the shell.
2. **Cloud layer, from space**: a second shell at about 3 to 9 km altitude with coverage from a seamless noise cubemap (weather map) plus 2 to 3 sun-ward samples for self-shadowing; cheap enough to run everywhere.
3. **Cloud layer, from inside the atmosphere**: ray-march the slab between the cloud base and top (24 to 48 steps, jittered) through a baked 3D Worley-Perlin texture (128^3, about 8 MB), Beer-powder lighting and a Henyey-Greenstein phase. The slab intersection uses `t = q / (B + sqrt(B^2 + q))` with altitude from the CPU in double precision, which stays accurate at 6000 km radius.
4. **Cloud shadows on terrain**: the terrain shader samples the same coverage along the sun direction (one 2D lookup), and the sun's light dims under clouds.
5. **Per-world weather**: coverage, colour and altitude per `BodyDef` (thick ochre deck on Cinder, thin wisps on Aurelia, none on airless worlds).

## Cost and risks (not measured yet)
- Budget: keep the N9 gate, asset-on p95 <= 1.15x the baseline at 1152x648 and 1920x1080. The ray-march in step 3 is the expensive part (every sky pixel); fallbacks are fewer steps, blue-noise jitter and rendering the clouds at a reduced resolution.
- Transparent shells sort against the ship and terrain: needs a look at depth and the existing far plane (3e7 m), and at floating-origin rebases.
- Cloud look cannot be judged from numbers; each step needs eyes on renders (orbit, descent through the layer, ground) and your call.
- New third-party code needs an ATTRIBUTION row and its licence header kept (cuberact: MIT plus the O'Neil credit in the shader header).
