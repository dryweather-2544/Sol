# Rodina 1.6.2 — Rendering / Shader Subsystem Analysis

Static-only reverse engineering of the shipped tree (`Rodina.v1.6.2/Rodina.v1.6.2/`). No executable,
DLL, script or build tool was run; no `.egs` was decompiled. **CONFIRMED** = literal text at the cited
line. **INFERRED** = consistent across artifacts but the deciding code is in C++. **UNKNOWN** = no
static evidence. Anything marked "engine-side" is the C++ boundary (`Rodina.exe` / `EGRenderGroup` /
`EGRenderer`), not visible to us.

`Shaders/` holds 51 `.fx` + 21 `.h` = 72 sources, 336,011 B / 9,650 lines. `_Fxaa3_11.h` (87,927 B) is
vendored NVIDIA FXAA 3.11, so first-party HLSL is ≈248 KB / ≈7,900 lines.

---

## 1. Inventory

### 1.1 Sources by purpose

| Bucket | n | Bytes | Contents |
|---|---|---|---|
| Terrain surface | 1 | 13,817 | `RodinaTerrain.fx` — by far the most complex shader here |
| Planet generation | 6 | 9,473 | `Planet_Common.h` pipeline + Perun/Veles/Jarilo/Morena/Asteroid + `PlanetSkybox.fx` |
| Atmosphere | 3 | 1,933 | scatter / filter / blur full-screen passes |
| Skybox + star | 3 | 4,245 | `RodinaSkybox`, `RodinaSkyboxRGB`, `RodinaStar` |
| Particles / FX | 4 | 15,388 | `RodinaParticles`, `RodinaBeam`, `RodinaGlow`, `RodinaEye` |
| Post-process | 8 | 18,392 | bloom ×3, separable blur, DOF ×2, FXAA, copy |
| Menu / UI | 4 | 7,387 | `RodinaMenu`, `RodinaMenuHUD`, `RodinaMenuWorld`, `EGImgui` (ImGui backend) |
| Debug | 1 | 439 | `RodinaWireframe` — flat white, 16 lines |
| Scene core | 1 | 2,220 | `Rodina.fx` — the generic opaque-material shader |
| Script/canvas filters | 20 | 34,149 | `Script*.fx` — offscreen 2D image operators, not scene passes |
| **`.fx` total** | **51** | **107,443** | |
| **`.h` total** | **21** | **228,568** | |

Load-bearing headers: `standard.h` 14,540 B (all cbuffers + the VS/PS framework), `_atmosphere.h` 13,318,
`_perlin.h` 12,025, `_textureMap.h` 11,111, `_utility.h` 10,392, `_lighting.h` 7,213, `_terrain_constants.h`
5,273, `Planet_Common.h` 6,458. `_utility.h` and `utility.h` are near-duplicates (15-byte delta: an older
`Scanline()` reading a global `Timer`); `_utility.h` is CP1252, not UTF-8, and had to be re-encoded to read.

### 1.2 The compiled-only side: `ShaderCache/*.egs` — 1,079 files, 15.4 MB

These are **not** opaque blobs. Each is a 4-byte little-endian length + a raw `DXBC` container
(measured, no tool: `RodinaTerrain-…-TDE-1.egs` is 51,032 B = 4 + 0x0000C754, byte 4 = `DXBC`, then the
16-byte container hash). What that gives us:

* **Readable (CONFIRMED):** the `RDEF` reflection chunk is plain ASCII and leaks every cbuffer name,
  member name, type and resource binding, plus `STAT`. From the terrain blob: `PerFrameConstants`,
  `PerObjectConstants`, `PlanetConstants`, `PlanetTextureConstants`, all 37 textures
  (`PlanetFeatures`, `TexturePlanet`, `PortalDepthTexture`, `PerlinMap`, `Texture0…Texture7` ×
  {``,`Distant`,`Detail`,`VeryDistant`}), `Lights[200]` and its `EGLight` members.
* **Opaque (CONFIRMED):** the `SHEX` bytecode stream. Reading it needs a DXBC disassembler — a build-tool
  invocation — so no bytecode was decoded and no source was reconstructed.

So the cache is genuinely useful evidence about *which permutations the shipping build executed*, and
partially useful about *buffer layout*, but not about instruction selection.

Nine `.fx` have **zero** cache entries: `ScriptBlur`, `ScriptDistort`, `ScriptGradient`, `ScriptPerlin`,
`ScriptPerlinMask`, `ScriptSine`, `ScriptTransform`, `ScriptTriangles`, `ScriptVoronoi` — the heavier
procedural texture generators, so presumably compiled by the texture path, or dead in 1.6.2 (UNKNOWN).
Conversely no cached name lacks a `.fx`.

---

## 2. The `.egs` filename grammar and the permutation set

### 2.1 Grammar

`{Source}-{Profile}-{EntryPoint}[-{TOKEN}-{VALUE}]*.egs`

| Field | Example | Meaning |
|---|---|---|
| 1 Source | `RodinaTerrain` | `.fx` basename, the compilation unit. 42 distinct, all matching a `.fx` (CONFIRMED) |
| 2 Profile | `ps_5_0` | D3D profile. Also `ps`/`vs` with **no** model (311+204 files, a legacy path) and `ps_4_0`/`vs_4_0` for `EGImgui` only (CONFIRMED) |
| 3 Entry | `PS` | 15 distinct: `PS`, `VS`, `VS_TERRAIN`, `ATMOSPHERE_VS`, `VS_COPY`, `PARTICLE_VS`, `BEAM_VS`, `PSPlanetColors`, `PSPlanetHeights`, `DefaultVS`, `DefaultScriptVS`, `VS_WORLDMENU`, `VS_MENU`, `mainVS`, `mainPS` |
| 4+ Flags | `-TPL-1-TVD-1` | One pair per **enabled** macro; `-1` = defined. The only non-boolean value in all 1,079 files is `INST-50` (32×) = `EG_INSTANCING_COUNT 50` |

Zero flags ⇒ no trailing fields (`RodinaWireframe-ps-PS.egs`), so pairs are appended, never padded.

### 2.2 The authoritative token table

Stored as a string blob in `Rodina.exe` at ≈0x8BD4D8, between the define-name list and the cache error
strings (CONFIRMED, verbatim order): `NOCOL NOLIT CLRDEP UNLIT DIFF NORM VERTLIT INST LOGDEP TEX0 TEX1
DEP EMIT PORSUR TPL TVD TDI TMD TDE BLURV BLURH MMF` — 22 tokens. The token→define pairing is
**INFERRED** (name + usage), because the blob keeps names and tokens as two separate runs:

| Token | Define | Where it acts | Files |
|---|---|---|---|
| `LOGDEP` | `EG_SHADER_PIXEL_LOGARITHMIC_DEPTH` | writes `SV_Depth` (`standard.h:262,277`) | 459 |
| `VERTLIT` | `EG_SHADER_VERTEX_LIGHTING` | shade in VS; PS multiplies baked light (`standard.h:362`, `RodinaTerrain.fx:321`) | 414 |
| `DIFF` | `EG_SHADER_DIFFUSE_MAP` | sample albedo (`Rodina.fx:12`) | 214 |
| `EMIT` | `EG_SHADER_WRITE_EMISSIVE` | bind RT2 `EmitBuffer` + RT3 `BlurBuffer` (`standard.h:257`) | 205 |
| `DEP` | `EG_SHADER_WRITE_DEPTH_BUFFER` | linear depth → RT1 (`standard.h:253`) | 196 |
| `TVD/TDI/TMD/TDE/TPL` | `EG_TERRAIN_TEXTURE_{VERY_DISTANT,DISTANT,MID,DETAIL,PLANET}` | terrain tiers (`RodinaTerrain.fx:208,230,248,266,157`) | 176/140/104/69/89 |
| `NORM` | `EG_SHADER_NORMAL_MAP` | normal-map sample (`Rodina.fx:8`) | 112 |
| `UNLIT` | `EG_SHADER_UNLIT` | bypass lighting (`Rodina.fx:39`) | 109 |
| `INST` | `EG_INSTANCING_COUNT` | counted, not boolean → `-50` | 32 |
| `NOLIT` | `EG_SHADER_NO_LIGHTING` | strips lighting entirely (`standard.h:200`) | 30 |
| `TEX0/TEX1` | `TEXTURE_INPUT_0/_1` | script-filter inputs (`Script_Common.h:8-13`) | 28/20 |
| `PORSUR` | `EG_SHADER_PORTAL_SURFACE` | portal = pure fog (`standard.h:330,348`) | 15 |
| `NOCOL` | `EG_SHADER_DISABLE_PIXEL_OUT_COLOR1` | omit `SV_Target0` (`standard.h:245`) | 15 |
| `CLRDEP` | `EG_SHADER_CLEAR_DEPTH` | force depth 1.0 (`standard.h:265,293`) | 15 |
| `BLURV/BLURH` | `EG_BLUR_VERTICAL/_HORIZONTAL` | separable axis (`RodinaImageBlur.fx:66,69`) | 8/8 |
| `MMF` | `EG_SHADER_MINMAX_FILTERING_SUPPORT` | `RodinaImageBlurDOFBegin` only | 2 |

Note `EG_SHADER_NORMALS`, used at `Rodina.fx:30`, is **absent from the binary's define list** (byte grep
= 0 in both exes) — that block is dead code, and `Rodina.fx:31` says so: *"TODO: This probably isn't
working at all."*

### 2.3 Scale: a demand journal, not a prebake

Populations (CONFIRMED): `Rodina` 420 (= 206 SM5 + 214 legacy), `RodinaTerrain` 203, `RodinaEye` 63,
`RodinaGlow` 57, then 28 each for skybox/particles/beam, 2 for `PlanetSkybox`/`EGImgui`. Globally 311
legacy `ps` vs 350 `ps_5_0`, 204 legacy `vs` vs 212 `vs_5_0` — two feature-level generations coexist in
one directory (cause UNKNOWN).

Terrain's theoretical PS space is 2⁵ tiers × 2 `VERTLIT` × 2 `LOGDEP` × 3 depth modes × 2 `EMIT` ≈ 768;
only **99** SM5 PS entries exist. `Rodina`'s space is an order of magnitude larger with 206. So the cache
records the permutations a packaging playthrough actually hit. That is exactly why it is better evidence
than a compile matrix: it is a trace of the real render graph.

### 2.4 Three filename defects, and what they prove

**(a) `PORDEP` is an orphan.** 153 filenames use `-PORDEP-1` (e.g.
`RodinaTerrain-ps_5_0-PS-PORDEP-1-TVD-1.egs`), but the token appears **zero** times in `Rodina.exe`,
`Rodina_Steam.exe`, or any `.fx`/`.h`, and it is not in the 22-token table. CONFIRMED absence, UNKNOWN cause.

**(b) The empty token `--1` is the same slot.** 135 filenames carry a token that is the empty string
(`Rodina-ps_5_0-PS--1-DIFF-1-LOGDEP-1.egs`). Normalising both defects to `@` and re-grouping the `Rodina`
SM5 PS entries shows **every** `-@-1…` pattern appearing **exactly twice** (once `PORDEP`, once empty) and
every other pattern exactly once. That is a fingerprint of **one permutation dimension serialised under
two unresolvable token strings**. It touches only the three sources that sample `PortalDepthTexture` —
`Rodina` (79), `RodinaTerrain` (42), `RodinaEye` (14) — and `PORDEP` never co-occurs with `DEP` in any of
the 1,079 files, consistent with both claiming `SV_Target1`. The engine's own error string,
**`Encoding shader cache filename. Macro unrecognized: `**, is the smoking gun.

**(c) The cache is stale relative to the shipped sources.** The terrain `RDEF` lists a
`PerFrameConstants` member **`sadfsadf3`** directly after `StarLightIndex`; that identifier is nowhere in
the shipped sources, and the shipped member `DoBlurOut` (`standard.h:62`) is nowhere in the blob
(CONFIRMED both directions). So the bitcode was compiled against an earlier `standard.h`. Consequence:
treat `RDEF` names as unreliable, but the shipped `#define` structure, bindings and arithmetic as
authoritative — those do agree with the blob.

---

## 3. Terrain / planet material — `RodinaTerrain.fx`, `_terrain_constants.h`

### 3.1 Texture budget

`TerrainFeature` (`_terrain_constants.h:104-161`) is 92 floats (~368 B); the cbuffer holds
`TerrainFeatures[EG_PLANET_TERRAIN_MAX]` with `EG_PLANET_TERRAIN_MAX (8)` set at `RodinaTerrain.fx:17`
before the include. Each feature owns **four** tiers, so terrain binds 8 × 4 = 32 albedo SRVs (`t5…t36`,
`_terrain_constants.h:9-40`) plus `PlanetFeatures` t0 (4-channel RGBA mask), `TexturePlanet` t1,
`PortalDepthTexture` t2, `PerlinMap` t4. A worst-case terrain draw is 37 SRVs and a 3,040-byte `b3`.
`t3`/`NonRepeatMap` and the whole `MapTextureTriplanarNoRepeat` path (`_textureMap.h:9-120`) are retired —
stochastic tiling was abandoned. The shipped typo `int TerrainFreaturesCount` (line 166) is in both source
and blob.

### 3.2 Distance constants (verbatim, `RodinaTerrain.fx:21-37`)

`// HACK: These values mirrored in EGRenderGroup.cpp` — then `TexDistDetail 500.0`, `TexDist 5000.0`,
`TexDistDistance 50000.0`, `TexDistVeryDistant 2000000.0`, `TexDistVeryDistantClose 200000.0`,
`TexDistVeryDistantFar 100000.0`; planet-scale bands `PlanetNear 50k / Near2 750k / Far 750k / Far2 18,000k`
and a second set `50k / 200k / 350k / 1,000k`.

Three consequences. (i) The comment is an explicit admission of a **duplicated constant table in C++** —
shader and CPU LOD must be edited in lockstep, a live desync hazard. (ii) The 18,000,000 far band is why
depth is logarithmic (§6.4). (iii) The tiers are not a geometric progression, and the very-distant tier is
*inverted* (weights keyed 100k → 200k, far → near). Note `aInput.Distance` (`standard.h:411`) is
`length(WorldPos)` — distance from the **world origin** — used as both terrain LOD metric and atmospheric
path length, which only makes sense in a camera-relative floating-origin world (INFERRED, but a 18M-unit
world cannot survive FP32 absolute coordinates).

### 3.3 Feature blending — a six-way multiplicative AND, painter-ordered

`GetTerrainBlend` (`RodinaTerrain.fx:40-75`) gates each feature on six independent criteria:

1. **Altitude** — `length(WorldPos - PlanetCenter)` (145), band `HeightEdge ± HeightFade·fadeMult`,
   offset by `HeightNoiseMult · altitudeNoise`.
2. **Latitude** — `abs(dot(fromCenter, (0,0,1)))` (147) then `asin()` (51), so the band is in radians;
   `LatitudeEdge ± LatitudeFade·fadeMult` plus `LatitudeNoiseMult`.
3. **Normal** — `dot(fromCenter, normalWorld)` (148) → `acos` (58) →
   `Analogue(angle, min, max, NormalTargetLow, NormalTargetHigh)`, so a feature can deliberately target
   flat ground *or* cliffs by inverting its targets.
4. **Four feature masks** — `FeaturesEdge.xyzw ± FeaturesFade.xyzw·fadeMult`, one `GetRatioClamp` each (64-70).

`blend = altitudeBlend · latitudeBlend · normalBlend · fx · fy · fz · fw` (72-73): no weights, no
normalisation, every criterion must hold. That is what makes authored features read as discrete
geological rules rather than a paint mix.

Two details carry the look. **`fadeMult = Analogue(aDistance, 1000, 100000, 1, 4.0)`** (45) inflates every
band 1→4 with distance — deliberate band-widening as antialiasing, the cheapest meaningful LOD idea in
the file. And **painter accumulation** (195-298): `terrainBlend` starts at 1, each accepted feature scales
by the remainder and `terrainBlend -= blendFactor` (295), with early-out at `terrainBlend > 0.0` (195). So
authored array order *is* compositing order — coverage-greedy, first match wins, not an average.

Base colour is `lerp(planetColor, DiffuseColor, lerp(ColorBlendGround, ColorBlendSpace, saturate(AltitudeRatio)))`
(202-204) — the same material reads ground-hued from the surface and space-hued from orbit. `Specular`,
`BacksideColor` and `EmitValue` accumulate with the same weight (291-293), so emissive terrain is
supported and exercised (`EMIT` on 46 terrain entries).

### 3.4 Per-tier compositing, and the planet-scale inversion

`BlendTerrain` (101-108): `texBlend = saturate((aDistance - aDepth) / (aDistance * 0.5))` — 0 at the tier's
near edge, 1 at half its range — then adds `(triplanar - textureColor) · texBlend · blend`. The
very-distant tier instead ramps far→near: `Analogue(depth, 100k, 200k, BlendLow, BlendHigh)` (211).

`BlendPlanet` (89-98) is the inverse trick: `smoothstep(Near, Near2, EyeAltitude)` *below* `Near2`, else
`smoothstep(Far2, Far, EyeAltitude)` (descending). The planet-scale albedo therefore appears when hugging
the ground **and** from interplanetary distance, and fades out in the mid band where terrain features carry
detail. Two independent instances (`PlanetTexture`, `PlanetTexture2`, 157-190) let a second layer bleed through.

### 3.5 Triplanar mapping and its documented weakness

`MapTextureTriplanar` (`_textureMap.h:123-173`): axis UVs `pos.zy/scale`, `pos.xz/scale`, `pos.xy/scale`;
weights `pow(abs(normal), 10.0)` normalised to sum 1 (127, 162-165). Sharpness 10 is high, so cliffs read
crisply. The flaw is admitted in-file: the `SampleGrad` variants are commented out (137-139) with
*"these ddx / ddy values aren't really working. Not totally sure what values to use here."* All reads
therefore use implicit derivatives, whose per-axis discontinuities on a sphere guarantee grazing-angle
aliasing. `RodinaTerrain.fx:141-142` computes `worldDDX/worldDDY` and threads them through every `Blend*`
call purely to feed the disabled path — live dead arguments, and a ready-made fix-up for anyone porting.

Lighting (321-345): under `VERTLIT` the PS multiplies baked light; otherwise it builds a full
`EGLightingInfo`/`EGMaterial` and calls `Shade()`, so terrain shares specular/backside/emissive with every
other material. Then atmosphere compositing (350-354) and the MRT block (356-363: optional linear depth →
RT1, emissive → RT2, DOF control → RT3).

---

## 4. Atmosphere — `_atmosphere.h`, `RodinaAtmosphere{Scatter,Filter,Blur}.fx`

### 4.1 Not a scattering model

There is no Rayleigh/Mie phase function, no extinction integral, no optical-depth accumulation and no
multi-scatter term in these 380 lines (CONFIRMED). `AtmosphereDensity` is one authored float packing two
meanings: `saturate(AtmosphereDensity)` (8-11) is tint strength, while
`saturate(AtmosphereDensity - 1)` (14-17) is the "thick atmosphere" dial — so the parameter lives in
[0,2) and values >1 mean a Venus-like world that occludes its star through the limb. The effect is a set
of analytic angular ramps plus an `exp2` distance fog.

### 4.2 Horizon math

Everything derives from one angle, `pointAngle = acos(dot(normalize(WorldPos), -PlanetToCameraDir))`
(20-34): the angle from the planet's centre as seen from the eye. Then
`outHorizonFactor = GetRatioNoClamp(pointAngle, PlanetRadiusAngle, AtmosphereRadiusAngle)` after an
`EaseOutSin` (37-38) — 0 at the limb, 1 at the outer shell. Three constants define the look:

* `inHorizonFactor = (pointAngle - PlanetRadiusAngle) / 0.66` (41) — a fixed **0.66 rad ≈ 37.8°** band under the horizon.
* `color = saturate(1 - Analogue(AltitudeRatio, 0.25, 1.0, inHorizonFactor, outHorizonFactor))` (43) — one
  expression blending ground-side and space-side over `AltitudeRatio ∈ [0.25, 1.0]`.
* `depthFactor = Approach(aDepth / AtmosphereAltitude, 1.0, 5.0)` (46), where
  `Approach(x,L,m) = L - (L/m)/(x + (L/m)/L)` (`_utility.h:24-29`) is a rectangular hyperbola saturating to 1.
* `densityFactor = Analogue(AltitudeRatio, 0.5, 1.0, depthFactor, color)` (48) — inside the atmosphere trust
  path length, above half-altitude trust the angular term.

Returned as `(densityFactor, color)`: x → alpha, y → palette blend between `AtmosphereScatterColor1/2` and
`AtmosphereFilterColor1/2` (86-103; the colours are `PlanetConstants` members, `standard.h:144-147`).

### 4.3 Sunset and halo — the only light interaction

`GetAtmosphereFilterFactor` (58-83) is where dusk lives. `starHorizonFactor = abs(PlanetRadiusAngle -
starPlanetAngle)` remapped by `Analogue(…, StarRadiusAngle + SunsetStarAngleBuffer, 0, 0, 1)` (71-72) is 1
when the star sits at or just below the limb inside an authored buffer. `haloAngleMax = cos(StarRadiusAngle)`
and `haloAngleMin = Analogue(starHorizonFactor, 0, 1, haloAngleMax - StarHalo, haloAngleMax -
SunsetStarHalo)` (74-75) let the halo *grow* through sunset; `halo = Analogue(starAngle, min, max, 0, 1)`
then **`halo *= halo`** (76-77) gives a tight squared falloff. `sunset = aPosHorizonFactor ·
starHorizonFactor · Analogue(starAngle, SunsetHorizonLimit, 1, 0, 1)` (79) keeps the glow only on the
star-facing side. `result = saturate(sunset + halo)` then drives the lerp from scatter to filter colour
(162). The whole red/orange shift is one blend between two authored colours driven by two angular
products — there is no wavelength-dependent extinction, so sunsets cannot vary correctly with view angle.

### 4.4 Two entry points chosen by a macro

`GroundAtmosphereAt` (169-194), terrain: `edgeFactor = 1 - saturate(dot(planetToWorld, worldToCamera))`
raised to `pow(…, 1.5)` (177-178) so grazing ground is denser, remapped into
`[Analogue(thickness,0,1,.4,.635), 1]` (179); `minDepth = Analogue(thickness,0,1,0,0.25)` (183) floors
thick atmospheres; depth goes through `Approach(…, 1.0, AtmosphereGroundDistance)` (185).
`ObjectAtmosphereAt` (197-216) is identical except the angular term becomes a flat `0` (209), i.e. objects
get distance haze only, never grazing density. The choice is a compile-time branch at
`standard.h:390-395` on `EG_SHADER_TERRAIN` — which is precisely why `EG_SHADER_TERRAIN` is a define and
not a uniform.

### 4.5 The 10-sample terminator (the whole "scattering" budget)

`ShadeAtmosphere` (284-335) marches with `BLEND_ATMOSPHERE_COUNT 10.0f` (280) from the fragment to the
atmosphere's **front** intersection (`GetAtmosphereFront` 263-277 via the quadratic sphere solve 234-260),
averaging `GetAtmosphereDayBrightness` per step (309-327), where the terminator is one fixed smoothstep:
`smoothstep(-0.2, 0.2, dot(toStarDir, normalize(WorldPos - PlanetCenter)))` (223). Ten uniform samples
(`sampleRatio = i/10`, 315; an `EaseInSin` variant is commented at 314) soften the shell's lit edge and
that is all. It exists because the per-vertex terminator (§6.2) is too coarse on a large shell.

### 4.6 The three post passes

* `RodinaAtmosphereScatter.fx` (14-20) writes `GetAtmosphereColor × ShadeAtmosphere`, plus
  `Color2 = 1 - GetAtmosphereThickness() * Color.a` — an explicit **transmittance** channel so a thick
  atmosphere occludes the sky behind it (comment at 19: *"Bring this number down for thick atmospheres
  that block external light"*).
* `RodinaAtmosphereFilter.fx` (11-18): `filterFactor = Analogue(lighting, 0, 1, a, a*3)` then
  `lerp(white, atmosphere.rgb, filterFactor)` — the screen-space veil.
* `RodinaAtmosphereBlur.fx` (15-18) writes `GetAtmosphereBlur`, which is the horizon factor `max`'d with
  `ForceBlur` (374-375), into the **DOF control**. So the atmosphere horizon directly drives depth of
  field: looking at a limb blurs it. Cheap substitute for aerial-perspective blur, and the most reusable
  single idea in the subsystem.

---

## 5. Planet surface generation

### 5.1 Cubesphere

`PlanetCubeToUnitSphere` (`Planet_Common.h:99-112`) is the standard cube→sphere warp
(`x·sqrt(1 - y²/2 - z²/2 + y²z²/3)` per axis, then `normalize`) over six faces whose quad bases come from
the CPU in `PlanetCoordConstants` (`LowerLeft/LowerRight/UpperLeft/UpperRight`, 19-33).
`GetUnitPlanetCoord` (115-132) adds the half-texel offset (`-0.5`, 118) and divides by `TargetSize - 1`
(122) so the bake reaches the exact face edge — the classic off-by-one, and they got it right.

### 5.2 Height pass

`PSPlanetHeights` (135-147) evaluates `GetPlanetHeight` at the pixel centre and writes it to **RGB**,
`a = 1`. The comment at 142 — *"Should just be using R value - probably OK as is?"* — means three channels
carry one scalar: 3× bandwidth for nothing (12 MB vs 4 MB at 2048²).

### 5.3 Normal pass

`PSPlanetNormals` (161-211) is a 5-tap finite difference **on the cube face**, not the sphere: `delta` is
the constant `0.00015` (165) added straight to the face coordinate along `FaceRight`/`FaceUp`; each of the
five points is warped to the sphere and scaled by `(height + Radius)` (185-189); four cross products from
centre to neighbours are averaged and normalised (196-201). Consequences: five full height evaluations per
normal texel (a 2048² × 6-face bake = 5 × 25 M evaluations at up to 12 Perlin octaves each — the dominant
generation cost), and a fixed face-space epsilon so effective world epsilon varies with planet radius, a
real inaccuracy for small bodies. `GetPlanetFaceCoord` (150-158) is the unwarped variant this pass uses.
Data channels: `PlanetGenConstants[1024]` and `VoronoiPoints[1024]` (36-46).

### 5.4 `GetPlanetHeight` — five worlds, one interface

All five declare `float GetPlanetHeight(float3)` / `float4 GetPlanetFeatures(float3)` against the forward
declarations at `Planet_Common.h:9`. The structure splits in two.

**Data-driven (Perun, Jarilo, Asteroid)** build a feature vector in four conceptual steps, then collapse it:

1. **Domain warp** — two or three derivative-noise fields (`FractalPerlinDerivative`) are subtracted from the
   sphere position and re-normalised, producing *separate* warped coordinates for masks, bases and mountains
   (`PlanetPerun.h:52-59`). Warping the domain rather than the value is what yields continental outlines
   instead of blobs.
2. **Base layer** — `Voronoi2(warpedCoord, float2(scale, jitter), strength)` (61): a jittered cellular field,
   giving plate-like lowlands rather than Perlin mush.
3. **Layered masks** — plateau and mountain masks via `FractalPerlin` → `Analogue`, the mountain mask
   multiplied into a second mountain field, and a 4-branch `holes` classifier that carves basins with
   smooth rims (64-89).
4. **Composition** — `(base, plateau, mountainMask·mountains, holes)` (91-94), then in `GetPlanetHeight`
   (103-150) each channel is remapped by `Analogue`/`EaseOutInSin2`, cross-faded
   (`base = lerp(base, 0, plateau)`, `lerp(base, 0, mountains)`, `mountains = lerp(mountains, 0, holes)`),
   and summed as three weighted fractal components so each band gets its own roughness.

The differences are parameter topology, not structure: Jarilo adds a plateau domain warp plus dune and
hole-override blocks (`PlanetJarilo.h:111-126`); Asteroid adds `PlanetGenConstants[104] radiusOffset` as a
flat base and composes mountains additively (`PlanetAsteroid.h:219-220`) so bodies need not be spherical;
Perun is the baseline. The three files exist so an artist can tune one world without perturbing the others —
the constant indices *are* the API.

**Hardcoded (Morena, Veles)** touch no cbuffer at all. `PlanetMorena.h` is the most distinctive: a plate/crack
model where `bigCrackMask = platePerlin - cos(clamp(30·(a·crackCoord.z + b·crackCoord.y), ±8π))` (47-49)
turns a Perlin field into a periodic plate boundary; three offset iso-lines of a second field become a
small-crack network (51-54); the sign of the two big masks selects hills vs dunes (58-67). Height is
`14,000 + plateau·(±1,000 fractal) - cracks·15,000 + mountains·30,000·fractal` plus an explicit dune ripple
from a `sin(dot(duneCoord, (1,-1,-1))·1000)` carrier with two `frac`-quantised phase ramps (123-130).
`PlanetVeles.h` is the same family with a Voronoi base (42) and fixed 20,000/15,000 amplitudes (108-109).
These were forked when hand-written math beat parameter tuning.

### 5.5 `PlanetGenConstants` index map

Indices 1-17 are the **feature/mask block**, consistent across Perun/Jarilo/Asteroid: 1 mask-warp options,
2 feature-warp options, 3 mountain-warp options, 4 warp strength/mask distort, 5 base warp strength,
6 distort mult, 7 plateau octave options, 8 plateau analogue, 9 hole octave options, 10 hole thresholds,
11 mountain-mask options, 12 mountain-mask analogue, 13 mountain-value options, 14 mountain analogue,
15 Voronoi scale/jitter/strength, 16-17 seeds (x,y,z,w → four independent layers each).

Indices 100-114 are **height composition**: 100-103 mountain ramp (input remap, roughness remap, roughness
carrier, amplitude/octave), 104 radius offset (Asteroid only), 105-107 plateau ramp/amplitude, 108 hole
override (Jarilo only), 110-112 lowland ramp/amplitude, 113-114 dune filters (Jarilo only).
`PlanetSkybox.fx` reuses the same cbuffer with an unrelated layout: 1-21 galaxy/dust params, 150 star
density, 200-204 output colours. The `[1024]` worst case (38) is far beyond the ~32 slots any world uses —
cheap headroom, uploaded once per bake.

Corroboration that this is designed data, not code: `Scripts/Data/EGEditorData.lua:919` `PlanetTerrains`
holds seven authored sets — `AsteroidLargeTerrain` (3 features), `AsteroidTerrain` (3), `JariloTerrain` (6),
`MorenaTerrain` (5), `OldGenericTerrain` (2), `PerunTerrain` (5), `VelesTerrain` (5) — with keys
(`HeightEdge = -10000`, `NormalEdge = 90`, `TextureScale`, `FeaturesEdgeX…W`,
`VeryDistantTextureBlendClose/Far`) that map 1:1 onto `TerrainFeature`. The 8-feature ceiling is never
reached in 1.6.2; it is headroom.

### 5.6 The galaxy bake feeds the skybox

`PlanetSkybox.fx` (42-147) reuses the same cubesphere machinery to bake a galaxy cube map: galactic-plane
distance `|plane·pos + w| / |plane.xyz|` (82-85), a `Gaussian2` band whose width/height are shaped by a
centre-dot term (91), two Perlin layers multiplied in (93-99), a domain-warped dust layer (102-117), and
nine rotated Voronoi star fields summed at two rotations (25-39, 124-127). Output is exactly
`(milkyWay, milkyDust, stars, 1)` (143-146), and `RodinaSkybox.fx:28-31` decodes precisely those channels.
A clean bake→atlas contract between two shaders with no shared header.

---

## 6. Lighting, skybox, depth, post chain

### 6.1 Light model

`EGLight` (`standard.h:40-49`) is `{Position, Direction, Color, Radius, SpotLimit, LightType}` with
LightType 0 = point, 1 = star, and an undocumented third band at `_lighting.h:99-105` (directional:
`toLightDir = -Direction`, no attenuation, no specular). `Lights[200]` (`standard.h:90`) but each instance
carries only `LightIndices[15]` (114) and there are 15 `EGMaterial`s (121) — so a draw shades at most
**15 lights**; which 15 is chosen engine-side (UNKNOWN).

`Shade` (`_lighting.h:27-132`): Lambert with linear `1 - d/Radius` attenuation (51; a squared variant is
commented at 52), squared spot falloff (60-64), Blinn-style halfway specular with a free exponent
(`GetSpecularIntensity`, 19-24), and a **backside** `(1 - NdotL)` term scaled by `aMaterial.Backside`
(72-74, 128) — this is how Rodina gets its night-side rim cheaper than an emissive map. Emissive gets a
Fresnel boost: `glow = Analogue(dot(N,V), 1, 0, e, 2e)` (118-120), doubling at grazing angles. With no
star in the instance list, global `Ambient` substitutes (107-110).

### 6.2 The terminator is per-vertex

`GetPlanetDayLightIntensity` (148-166) splits at `angleFactor = dot(worldNormal, toLight)` into
pre-sunset (`PlanetTerminatorBegin → 0`) and post-sunset (`0 → PlanetTerminatorEnd`), both
`AnalogueSmooth`. `GetPlanetStarLight` (169-189) tints the star toward `AtmosphereFilterColor2` by
`GetAtmosphereDensity()` and fades it through the terminator; `GetPlanetAmbientStarLight` (192-197) ramps
ambient from 0.05 to `PlanetAmbientColor`. All of it runs in the **vertex shader** and is interpolated:
`StandardPackVS` computes `StarLightColor`/`StarAmbientColor`/`AtmosphereColor` per vertex
(`standard.h:420-432`) and the PS only reads them (`standard.h:369-371`, `RodinaTerrain.fx:328-330`).
So sunset gradients are as smooth as the tessellation, not the pixel grid.

### 6.3 No shadows at all

Byte-level absence across all 72 sources: the only `shadow` tokens are `ScriptLight.fx:19-21`
(`GetLightShadowColor` reading `ScriptVars[2]`) — a 2D texture-generation filter with a stylised shadow
colour. No depth-from-light target, no light matrix, no cascade, no PCF, no shadow sampler, no
`EGRenderPassShadow`. **CONFIRMED: Rodina 1.6.2 ships no shadowing of any kind.** Contact darkening is
faked entirely via `Backside` and `Ambient`.

### 6.4 Skybox, star, glow, depth

`RodinaSkybox.fx` (18-64) decodes the bake, adds `baseColor (0.025, 0, 0.05)` (33), `starColor (1, 1, 1.5)`
(34) — deliberately over-bright, so stars bloom — and `milkyDustColor (-0.6, -0.75, -1.5) * 2` (36), which
is **negative**: dust *subtracts*, carving dark lanes instead of adding glow. `ControlTexture` is sampled
(24) but the multiply is commented out (44), so the skybox ignores the atmosphere filter while
`RodinaStar.fx:24` applies it. Twinkle is computed then hard-disabled (`twinkle = 1`, 40). Skybox writes
`BlurBuffer.r = ForceBlur` (58) so the sky participates in far-field DOF. `RodinaStar.fx` (10-38) is the
star billboard: filter colour reddened toward `(1,0,0)` by filter alpha (18), plus scatter colour,
multiplied by the screen-space filter (24), exporting the filter on `Color2`. `RodinaGlow.fx` is a Fresnel
rim: `edgeFactor = Analogue(dot(toCamera, normal), 0, .75, 1, .25)` (18), alpha
`= Analogue(edgeFactor, 0, 1, 1, alpha * 0.25)` (24).

Depth has **two mutually exclusive paths**. Either log depth is written per pixel into `SV_Depth`
(`standard.h:262-263, 277-279`) as `log2(max(0.01, z + 1)) / log2(1e12 + 1)` (`_utility.h:5-15`, far plane
10¹²), or depth is written in the VS (`StandardVertexDepth`, 314-319). `LOGDEP` is the most common flag
(459/1079), so the pixel-depth path is the production default — and writing `SV_Depth` disables early-Z /
hi-Z on all opaque geometry. Separately, linear depth is *also* written as colour to RT1 (`DEP`/`PORDEP`)
so post passes can read it as a texture. Z is computed twice, by two mechanisms, both shipping.

### 6.5 MRT contract

`STANDARD_PS_OUTPUT` (`standard.h:242-269`) declares four targets: `SV_Target0` `Color` (skippable via
`NOCOL`); `SV_Target1` `DepthBuffer` **or** `Color2`, mutually exclusive (`DEP`/`PORDEP` vs
`EG_SHADER_PIXEL_OUT_COLOR2`); `SV_Target2` `EmitBuffer` (bloom source); `SV_Target3` `BlurBuffer` (`.r` is
a **signed** DOF control: >0 far field, <0 near field, `.a` coverage). `StandardDOFBlurFactor` (283-288)
maps depth through `BlurInNear/Far` or, when `DoBlurOut`, `BlurOutNear/Far`, then scales by
`max(BlurControl, ForceBlur)`.

### 6.6 Post chain — order INFERRED, contracts CONFIRMED

The engine has no per-effect class, only `EGRenderPass{,Atmosphere,Beam,Copy,Eye,Menu,Particles,Portal,
Skybox,Terrain}` + `EGRenderer` (RTTI strings), plus `EG_RENDER_DRAW_BEGIN_CLEAR_{TARGETS,DEPTHSTENCIL,
DEPTH_TEXTURE,ATMO_FILTER}` / `FILL_CBUFFER` / `VIEWPORT`. Sequence below is derived from each shader's
declared texture slots and render targets — per-shader facts are CONFIRMED, the ordering is INFERRED:

1. **Scene MRT** — terrain, `Rodina` materials, particles, beam, eye, glow, skybox all write
   Color/Depth/Emit/Blur. Portal depth (t2/t4) is sampled here to `discard` portal interiors (`Rodina.fx:44-49`).
2. **Atmosphere scatter** → own target, transmittance on `Color2` (Scatter 14-20).
3. **Atmosphere filter** → screen veil (Filter 11-18); stars and the star billboard read it afterwards (Star 24).
4. **Atmosphere blur** → writes the DOF control (Blur 15-18).
5. **DOF begin** — `RodinaImageBlurDOFBegin.fx` resamples, choosing point vs linear sampling per 3×3
   neighbourhood (56-73). Note the hard-coded `RenderTargetSize * 2` at 31 with *"HACK: Blur is sampling a
   source texture that has 2x the resolution. This will break if we change the resolutions."*
6. **Separable blur** — `RodinaImageBlur.fx`, 13-tap Gaussian (`EG_NUM_BLUR_TAPS_HQ 13`, weights 14-29,
   renormalised at runtime by the accumulated factor sum, 65/76), two passes gated by `BLURV`/`BLURH`.
   Radius comes from the **sign** of the alpha channel (95-104): positive → `BlurOutRadius`, negative →
   `BlurInRadius`. A 5-tap LQ kernel exists (31-42) but is unused.
7. **DOF end** — `RodinaImageBlurDOFEnd.fx` composites blurred vs unblurred after a min/max 3×3
   neighbourhood test (50-98) that stops background samples bleeding over foreground silhouettes.
8. **Bloom** — `Begin` downsamples with `SampleLevel(…, 0)` (26), two `RodinaImageBloom.fx` passes (same
   13-tap kernel, radius `BloomRadius`, 44-67), then `End` adds `bloom * BloomMult` (30). Script knobs
   confirm the set: `Bloom`, `BloomMult`, `BloomRadius`, `AllowBloom`.
9. **FXAA last** — `RodinaImageFXAA.fx:6-14`: `FXAA_PC 1`, **`FXAA_QUALITY__PRESET 12`** (highest quality),
   `FXAA_GREEN_AS_LUMA 1`, `FXAA_HLSL_5`/`4` chosen on `EG_SHADER_MODEL_5`.
10. **Menu / IMGUI** — `RodinaMenu` (`VS_MENU` builds clip-space quads, 26-55), `RodinaMenuWorld`
    (`VS_WORLDMENU`, world-space billboards, 64-93), `RodinaMenuHUD`, then `EGImgui` as a raw ImGui backend.

There is **no tonemap, gamma/sRGB pass, exposure or LUT** anywhere (byte grep across all 72 sources: zero
hits for `tonemap|hdr|gamma|srgb|exposure`). Bloom adds in the same numeric space as lighting, so
`starColor (1,1,1.5)` and terrain emissive clip rather than roll off; the skybox `saturate` (48) is the
only clamp in the chain. DOF and bloom are individually budgetable per scene via `AllowBlur`/`AllowBloom`
and `SetBlurIn`/`SetBlurOut`, matching `BlurIn*/BlurOut*` in `PerFrameConstants` (`standard.h:64-72`).

---

## 7. Evidence table

| # | Finding | File : lines | Status |
|---|---|---|---|
| 1 | 51 `.fx` + 21 `.h` = 336,011 B; 9 `.fx` have no cache entry | `Shaders/` | CONFIRMED |
| 2 | 1,079 `.egs`, 15.4 MB, mean 14.2 KB | `ShaderCache/` | CONFIRMED |
| 3 | `.egs` = uint32 LE length + `DXBC` blob | `…TDE-1.egs` bytes 0-3 | CONFIRMED |
| 4 | `RDEF` leaks cbuffer + 37 texture names; `SHEX` opaque | same file | CONFIRMED |
| 5 | 22-token permutation vocabulary is a string blob in the exe | `Rodina.exe` ≈0x8BD4D8 | CONFIRMED |
| 6 | Token→define pairing | `standard.h:200,245,253,257,262` | INFERRED |
| 7 | `PORDEP` in 153 filenames, 0 in both exes and all sources | byte grep | CONFIRMED |
| 8 | Empty token `--1` and `PORDEP` are the same slot (2× dupes after normalisation) | `Rodina-ps_5_0-PS-*` | CONFIRMED |
| 9 | Engine error string `Encoding shader cache filename. Macro unrecognized:` | `Rodina.exe` | CONFIRMED |
| 10 | Cache built from older `standard.h` (`sadfsadf3` vs `DoBlurOut`) | `standard.h:62` vs blob | CONFIRMED |
| 11 | Terrain LOD distances 500 / 5,000 / 50,000 / 2,000,000 | `RodinaTerrain.fx:22-27` | CONFIRMED |
| 12 | LOD constants duplicated in `EGRenderGroup.cpp` | `RodinaTerrain.fx:21` | CONFIRMED |
| 13 | Planet-scale bands to 18,000,000 units | `RodinaTerrain.fx:29-37` | CONFIRMED |
| 14 | Band widening 1→4 with distance (antialiasing) | `RodinaTerrain.fx:45` | CONFIRMED |
| 15 | Blend = product of 6 masks, unnormalised | `RodinaTerrain.fx:72-73` | CONFIRMED |
| 16 | Painter-ordered coverage accumulation, early-out | `RodinaTerrain.fx:195,289-295` | CONFIRMED |
| 17 | 8 features × 4 tiers = 32 albedo SRVs, t5-t36 | `_terrain_constants.h:9-40` | CONFIRMED |
| 18 | Triplanar sharpness 10; `SampleGrad` disabled with author note | `_textureMap.h:127,137-139,162` | CONFIRMED |
| 19 | `Distance` = `length(WorldPos)` used as LOD metric + atmospheric depth | `standard.h:411`, `_atmosphere.h:46` | value CONFIRMED; camera-relative space INFERRED |
| 20 | Atmosphere horizon band 0.66 rad | `_atmosphere.h:41` | CONFIRMED |
| 21 | Density packs tint + thickness (`saturate(D-1)`) | `_atmosphere.h:8-17` | CONFIRMED |
| 22 | Halo squared, grows through sunset | `_atmosphere.h:74-77` | CONFIRMED |
| 23 | Sunset = horizon × starHorizon × facing | `_atmosphere.h:79` | CONFIRMED |
| 24 | Ground/object atmosphere differ only in the angular term | `_atmosphere.h:187,209`; `standard.h:390-395` | CONFIRMED |
| 25 | Exactly 10 marching samples for the shell terminator | `_atmosphere.h:280,309-327` | CONFIRMED |
| 26 | No Rayleigh/Mie/extinction/multi-scatter anywhere | `_atmosphere.h` | CONFIRMED |
| 27 | Atmosphere horizon drives DOF control | `_atmosphere.h:364-378`; `AtmosphereBlur.fx:15` | CONFIRMED |
| 28 | Thick-atmosphere transmittance on `Color2` | `AtmosphereScatter.fx:20` | CONFIRMED |
| 29 | Cubesphere warp + half-texel-correct bake | `Planet_Common.h:99-132` | CONFIRMED |
| 30 | Height written to 3 channels ("probably OK as is") | `Planet_Common.h:142-144` | CONFIRMED |
| 31 | Normals: 5 taps, fixed face-space delta 0.00015 | `Planet_Common.h:165-201` | CONFIRMED |
| 32 | Perun/Jarilo/Asteroid share 1-17; 100-114 differ per world | `PlanetPerun.h:30-50,114-125` etc. | CONFIRMED |
| 33 | Morena + Veles use zero cbuffer constants | `PlanetMorena.h:35-131`; `PlanetVeles.h:42,108` | CONFIRMED |
| 34 | Asteroid adds `radiusOffset`, additive mountain compose | `PlanetAsteroid.h:219-220` | CONFIRMED |
| 35 | Galaxy bake channels consumed by skybox | `PlanetSkybox.fx:143-146` → `RodinaSkybox.fx:28-31` | CONFIRMED |
| 36 | 7 authored terrains, 2-6 features each, keys match struct | `EGEditorData.lua:919+` | CONFIRMED |
| 37 | ≤15 lights per draw from a 200-light frame buffer | `standard.h:90,114` | CONFIRMED |
| 38 | Backside `(1-NdotL)` and Fresnel-boosted emissive | `_lighting.h:72-74,118-120,128` | CONFIRMED |
| 39 | Terminator computed per-vertex, interpolated | `standard.h:420-432`; `_lighting.h:148-197` | CONFIRMED |
| 40 | No shadow mapping of any kind | all 72 sources | CONFIRMED |
| 41 | Negative dust colour, over-bright stars, disabled twinkle | `RodinaSkybox.fx:34-40` | CONFIRMED |
| 42 | Log depth per pixel, far plane 1e12 | `_utility.h:5-15`; `standard.h:262,277` | CONFIRMED |
| 43 | 4 MRT targets; target1 shared by depth and `Color2` | `standard.h:242-269` | CONFIRMED |
| 44 | 13-tap Gaussian; DOF radius from signed alpha | `RodinaImageBlur.fx:14-29,95-104` | CONFIRMED |
| 45 | DOF begin hard-codes 2× source resolution; author flags it | `RodinaImageBlurDOFBegin.fx:29-31` | CONFIRMED |
| 46 | FXAA preset 12, green-as-luma, HLSL5/4 switch | `RodinaImageFXAA.fx:6-14` | CONFIRMED |
| 47 | No tonemap / gamma / exposure / LUT | all 72 sources | CONFIRMED |
| 48 | Pass sequence (scene → atmo → DOF → bloom → FXAA → UI) | contracts across 8 files | INFERRED |
| 49 | 15-light selection, cbuffer fills, LOD/tessellation choices | C++ | UNKNOWN |
| 50 | Origin of the `PORDEP`/empty/`sadfsadf3` drift | none | UNKNOWN |
| 51 | Which 9 uncached `Script*.fx` are live in 1.6.2 | none | UNKNOWN |

---

## 8. What Starfall (Godot 4.7, Forward+) can take

**Terrain blending is the strongest idea and ports almost as-is.** Six multiplicative gates (altitude,
latitude, normal angle, four feature masks) with authored ±fade bands, a 1→4 distance-driven band-widening
multiplier, and painter-ordered coverage subtraction. In Godot this is a `ShaderMaterial` with an array of
feature uniforms (or a `Texture2DArray` of parameter rows) and a fixed-count loop guarded by
`if (remaining > 0)` — no permutation flags required. Two upgrades over Rodina: normalise accumulated
coverage so authoring order stops being a hidden dependency, and do triplanar reads with `textureGrad` and
explicit world-space derivatives. Rodina already computes `worldDDX/worldDDY` and then doesn't use them
(`RodinaTerrain.fx:141-142`, `_textureMap.h:137-139`); Godot's `textureGrad` with `dFdx/dFdy` of world
position is precisely the fix for the aliasing its author left unresolved.

**The LOD problem is a texture-array problem, not a 32-SRV problem.** Rodina binds 8 features × 4 tiers and
pays with five permutation flags (`TPL/TVD/TDI/TMD/TDE`) that recompile the shader per tier combination —
203 cached terrain permutations for one surface. Godot 4.7 offers `sampler2DArray` with explicit LOD, so
four tiers collapse into one array plus blend weights, and five flags become a loop. The loss of per-tier
specialisation is negligible; the permutation count goes from 768 theoretical to 1. Where a tier must be
skipped, gate it with a `uniform bool` so the branch stays uniform-coherent instead of recompiling.

**Atmosphere: copy the structure, then replace the interior.** Rodina's model is an angular horizon ramp, a
0.66 rad ground band, a squared halo that widens as the star crosses the limb, and an `exp2` fog. It reads
well and costs almost nothing. It is also entirely non-physical — no extinction, so a sunset cannot redden
correctly with view direction, and no optical depth, so terrain and sky can disagree at the horizon. A
Forward+ implementation can keep the *authoring surface* (same two palettes, same halo/sunset scalars, same
`AtmosphereDensity` packing trick) while replacing the interior with a proper single-scattering integral
over a spherical shell at half resolution — affordable in Forward+ because it is one full-screen pass, not
per-material. The behaviour worth preserving verbatim is coupling the horizon factor into the DOF control:
blurring the limb is a convincing aerial-perspective cue for a fraction of a volumetric pass.

**Per-vertex lighting is a trap; do the terminator per-fragment.** Rodina computes star light, ambient and
the day/night split in `StandardPackVS` and interpolates — cheap, and the reason sunsets soften with
tessellation rather than staying crisp. In Forward+ this is a handful of fragment instructions, and doing
it per-fragment also fixes large flat quads and the atmosphere shell, which Rodina has to special-case with
a 10-sample march (`_atmosphere.h:309-327`) precisely because its per-vertex value is too coarse there.

**Permutation discipline: keep the shape, fix the hygiene.** The right part is the design — a small closed
vocabulary of short tokens each mapping to one `#define`, with the token set frozen in engine code and the
filename generated from it. It is legible enough that an outsider reconstructed the whole matrix from
filenames alone, which is how §2 was written. The wrong part is hygiene: 153 files under an orphan token,
135 under an empty one, the two being the same slot serialised twice, and blobs compiled against an older
`standard.h` (`sadfsadf3`). The engine's own `Macro unrecognized` string shows the authors hit this. The
lesson is concrete: key the cache on a **hash of the preprocessed source** plus a **versioned, closed enum**
of feature bits — never on concatenated macro names — and treat an unresolvable token as a hard failure,
not a silent empty string. Godot's `ShaderRD` cache already keys on a stable hash; the discipline to add is
refusing to ship a cache produced by a different toolchain revision.

**Render-pass ordering is the cheap win and needs no new technology.** Rodina's chain — MRT scene with
Color/Depth/Emit/Blur → atmosphere scatter+filter → DOF (begin/blur/end with a 3×3 safety test) → bloom ×3 →
FXAA → UI — is a textbook forward pipeline with **no shadows, no tonemap, no HDR**, running 18-million-unit
draw distances on a per-pixel log depth buffer. The sequencing is worth mirroring, particularly the
two-stage blur (control-channel gather, then a neighbour-tested composite), which avoids the classic
foreground-bleed artifact of naive DOF, and the `BlurBuffer.a` coverage channel, which lets every material —
terrain, particles, beams, skybox — declare its own blur amount so DOF becomes a per-material artistic
control rather than a global post setting. But do not inherit the omissions: Forward+ gives clustered
lighting and a depth prepass free, and ACES-style tonemapping before bloom would let emissive and stars
exceed 1.0 legitimately instead of relying on Rodina's clamp-then-add (`RodinaSkybox.fx:46-49`).

**Do not copy:** the duplicated LOD constant table (`RodinaTerrain.fx:21` vs `EGRenderGroup.cpp`), the 3×
heightmap bandwidth (`Planet_Common.h:142-144`), the fixed face-space normal epsilon
(`Planet_Common.h:165`), the retired `NonRepeatMap` path, and the `EG_SHADER_NORMALS` block no build ever
defines. Instructive debt from a decade-long solo project, but not patterns.

---

*Method: line numbers are 1-based against the shipped files; `_utility.h` numbering is against the
CP1252→UTF-8 conversion (CRLF stripped), which preserves line count. Cbuffer fills, light selection,
LOD/tessellation and permutation choice are C++ and marked UNKNOWN. No `.egs` was decompiled — only its
container header and ASCII `RDEF` names were read.*
