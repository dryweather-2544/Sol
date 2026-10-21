# Open-source Integration Research for Sol

**Status:** Research queue only. No third-party code or dependency has been added by this note.
**Baseline reviewed:** `n13-graphics-port`, commit `8d4abe2de48bd9372c8f7074094f546c8f60b93c`.
**Target runtime:** Godot 4.7.2, macOS / Apple Silicon.
**Purpose:** Identify real projects that can improve Sol without replacing systems that are already ported or breaking parity with Rodina.

## Recommendations at a glance

| Priority | Project | Licence checked | Best use in Sol | Integration risk |
|---|---|---|---|---|
| 1 — prototype | [SpatialAudio3D](https://github.com/claudehohl/SpatialAudio3D) | MIT | Interior acoustics: wall occlusion, reflections, delay and room-dependent reverb | Low–medium |
| 2 — compare | [Zylann Atmosphere Shader](https://github.com/Zylann/godot_atmosphere_shader) | MIT (`LICENSE.md`) | Study/compare atmospheric scattering and clouds; use isolated test scenes | Medium |
| 3 — benchmark | [CelestialSim](https://github.com/CelestialSim/CelestialSim) | MIT | GPU planet terrain, adaptive quadtree LOD and GPU scattering | High; major overlap with Sol terrain |
| 4 — code reference | [Cuberact Chunked LOD Planet](https://github.com/cuberact/godot-cuberact-planet-chunked-lod) | MIT | Understand GDScript chunking, LOD transitions, culling and atmosphere | Low as reference; high if replacing |
| 5 — contained prototype | [Beehave](https://github.com/bitbrain/beehave) | MIT | Higher-level enemy and crew decision-making through behavior trees | Medium |
| 6 — later content tool | [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | MIT | Branching crew dialogue, mission conversations and stateful choices | Low–medium |
| 7 — code reference | [Zylann Solar System Demo](https://github.com/Zylann/solar_system_demo) | MIT (repository licence file) | Study planet approach/landing, origin shifting and streamed terrain patterns | Medium; uses Voxel Tools/custom engine module |

An additional alternative is [Extremely Fast Atmosphere](https://github.com/fbcosentino/godot-extremely-fast-atmosphere) (MIT). It is worth a controlled performance comparison against Sol's current atmosphere, not an automatic replacement.

## 1. SpatialAudio3D — first contained test

Repository: https://github.com/claudehohl/SpatialAudio3D

The README describes a Godot 4 plugin that extends `AudioStreamPlayer3D`, uses raycasts to estimate surrounding surfaces, and supplies sound delay, reflected sound, geometry-dependent reverb, and high-frequency occlusion behind walls.

**Why it fits:** Sol already has ship-interior rooms, doors, an airlock and 3D audio events. This offers a potentially noticeable improvement without replacing flight, rendering or the interior layout.

**Proof-of-concept:** In a disposable scene, compare a sound in an open hangar, a small room, behind a closed door, and on the other side of the airlock. Profile raycast/audio cost with several simultaneous emitters. Confirm it coexists with Sol's current audio service and existing 3D impact events before adding it to production scenes.

## 2. Planet graphics candidates

### CelestialSim
Repository: https://github.com/CelestialSim/CelestialSim

The README targets Godot 4.7, calls the project beta, and describes a Rust/GDExtension-backed adaptive quadtree, GPU terrain generation/detail, a GDScript CPU path, analytic ocean support, and GPU scatter placement/culling. It advertises prebuilt Linux, Windows and macOS builds. MIT licence checked.

**Potential value:** Better GPU throughput, terrain detail by distance and large-scale object scattering.

**Main risk:** Sol already owns `src/planet/cube_sphere.gd`, `chunk_mesher.gd`, `lod_planner.gd`, `height_function.gd`, `planet_terrain.gd`, and `planet_body.gd`. A wholesale replacement would threaten the connection between the displayed mesh and the height function used by ground contact, walking, POIs and collision. Its terrain also won't inherently reproduce Rodina's planet-specific landform grammars.

**Required experiment:** Keep it outside the main scene first. Benchmark on the actual Mac M4, Godot 4.7.2. Compare frame time, memory, LOD popping/cracks, near-ground detail, and—most importantly—whether the same authoritative terrain function can supply accurate CPU collision/ground height. Do not merge based on a beautiful orbit screenshot alone.

### Cuberact Chunked LOD Planet
Repository: https://github.com/cuberact/godot-cuberact-planet-chunked-lod

Pure GDScript and shaders, described for Godot 4.6+, with chunked planetary LOD, surface detail, atmosphere and several culling/diagnostic controls. MIT licence checked.

**Use as a reference:** Compare how it splits/merges chunks, handles horizon/frustum culling and changes detail between orbit and ground. Port an isolated technique only if it measurably improves Sol's existing LOD implementation. Its generic terrain noise is not a substitute for the Rodina-derived landform work.

### Zylann Atmosphere Shader
Repository: https://github.com/Zylann/godot_atmosphere_shader

MIT licence checked in `LICENSE.md`; README says Godot 4.3+. It offers fake-colour and scattering variants, an inexpensive distant atmosphere representation, and experimental volumetric clouds. The README notes cloud quality/performance trade-offs and several known limitations.

**Use as a reference/experiment:** Make a separate scene and compare sky from orbit, atmospheric entry, low altitude, sunset and the horizon. Test cloud cost on the M4 and compare against reference imagery. Preserve Sol's calibrated Rodina profile unless the new approach is demonstrably closer.

### Extremely Fast Atmosphere
Repository: https://github.com/fbcosentino/godot-extremely-fast-atmosphere

MIT licence checked. Treat it as a low-cost alternative for profiling atmosphere-shell rendering. Validate the target Godot version, Apple Silicon renderer behaviour and visual quality locally before relying on it.

## 3. AI and narrative

### Beehave
Repository: https://github.com/bitbrain/beehave

MIT licence checked. A behavior-tree addon with editor/debugging and performance-monitoring support.

Use it only for the **decision layer**—for example, when an enemy searches, attacks, retreats, or when crew respond to a fire or damaged subsystem. Keep Sol's current ship/flight controller and Rodina-derived movement rules as the authority. Prototype one enemy or one crew emergency before deciding whether to adopt the dependency.

### Dialogue Manager
Repository: https://github.com/nathanhoad/godot_dialogue_manager

MIT licence checked. Release `v4.1.0` is identified by its publisher as a Godot 4.7 release (published 2026-09-04).

Useful later for authored dialogue, branching mission conversations, conditional choices and state changes. This does not improve flight or graphics; defer until mission/crew content is the current bottleneck.

## 4. Whole-game reference, not drop-in component

### Zylann Solar System Demo
Repository: https://github.com/Zylann/solar_system_demo

MIT licence checked. A Godot space-game demo using Voxel Tools. The repository documents a custom engine/module setup, so treat it as a technical reference rather than a ready-to-add addon. Study its planet transition, large-world/origin-shift and streaming approaches where Sol has concrete gaps.

## 5. Not approved for reuse yet

[godot-lod-planet](https://github.com/gitProject10001/godot-lod-planet) describes planetary terrain, erosion, clouds, atmosphere and surface-to-orbit flight, but no licence file was found at the repository root during this review. Do not copy or incorporate its source until its licence/permission is confirmed. A publicly visible repository is not by itself a reuse licence.

## Integration rules

1. **Do not add all of these.** Keep this document as a queue; prototype one candidate at a time on a separate branch or test scene.
2. **Measure before adopting.** Capture baseline and post-change frame time, memory, visual comparisons and relevant regression tests on the actual Mac. Cloud/software-renderer timings do not represent Mac performance.
3. **Protect source-of-truth systems.** Sol's terrain height, collision/landing/walking, ship-local coordinates, saves, flight physics and visual-style profiles must stay coherent. Never improve the visible mesh while leaving collision/navigation on a different surface.
4. **Don't overwrite the Rodina style with generic realism.** Every graphics experiment must be compared against genuine Rodina references and source/data already available to the project.
5. **Keep dependencies/licences attributed.** Preserve each project's MIT copyright and licence notice if source is reused; record the exact upstream commit/release and local modifications. Review bundled dependencies/assets separately.
6. **Keep proprietary reference material private unless redistribution rights are confirmed.** These open-source candidates do not grant rights to distribute Rodina code, models, audio, textures or other proprietary content.
7. **Check current work before integrating.** DeepSeek may already be implementing a related subsystem. Merge only a tested improvement; don't create a parallel renderer, flight model or AI controller for the sake of using a library.

## Suggested order

1. SpatialAudio3D interior test.
2. Atmosphere/cloud comparisons in an isolated scene.
3. CelestialSim benchmark versus Sol's existing terrain pipeline.
4. Beehave prototype for a single AI behaviour.
5. Dialogue Manager when mission content is ready for expansion.

The objective is not to accumulate plugins; it is to borrow proven techniques where they solve a measured problem and preserve Sol's Rodina fidelity.
