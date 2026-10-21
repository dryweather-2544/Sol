# N14 terrain streaming

## Bug
Fast flight over Aurelia (20 km, 5 km/s) showed large smooth or missing rectangular patches that only
filled in after stopping.

## Causes found (measured)
1. **Height sampling was ~90% string formatting.** `HeightFunction._grammar_noise` formatted a string key
   on every call (~30 calls per Jarilo sample). Jarilo sample: ~100 us; full 32x32 chunk: 120-170 ms.
2. **Fallback rebuild loop (first N14 WIP).** The removal rule dropped any chunk with a displayed ancestor,
   so level 1/2 fallbacks were removed as soon as level 0 showed and were queued again: in 20 s of the
   cold20 probe 1,958 builds finished, 11 of them real detail. The same rule removed fine terrain behind the
   ship whenever the level-0 face existed, which showed the smooth face: the reported patches.
3. Coarse grids put the normal ring at u = -1.5 where the spherified-cube map took sqrt(<0): NaN samples.

## Design (src/planet/planet_terrain.gd)
- Desired leaves from `LodPlanner.select_leaves(viewer, corridor)`; the corridor is 3 points along the
  velocity, lookahead 3-8 s from the measured request-to-screen latency, capped at 60 km.
- Every uploaded chunk is *available*. Per desired leaf the visibility pass shows the best cover: the leaf
  at full grid > finer chunks that fully cover it > the leaf's 8x8 preview > nearest ancestor as a
  *filler* (sunk by half its quad spacing). Everything else is hidden in a bounded LRU
  (48 MiB / 768 chunks) and reused on return.
- Levels 0-2: pinned small-grid backstop (12/10/8 quads), built once, never rebuilt.
- Queue: backstop level 0 > previews for leaves >= 2 levels under-covered > full grids > refining
  already-covered areas; distance-ordered, ahead work weighted 1.35x. Leaves always use 32x32.
- Workers = cores - 2 (8 on the M4), pooled per-thread HeightFunction, tasks reaped.
- Main thread: replan every 0.2 s; visibility pass at most every 0.1 s and never in the replan frame;
  <= 12 uploads / 4 ms per frame. Collision still uses HeightFunction directly (ADR 0002).

## Results
Probe: `godot --headless --path . -s res://tools/n14_stream_probe_cli.gd -- all planet out.json`.
"near" = desired leaves within max(8 km, 3 x altitude) shown at full detail; "ahead" = leaves wanted
3 s later already at full detail; deficit = worst LOD levels missing near the ship.

Cloud, 2 cores (2 workers), before (DeepSeek WIP) -> after:

| scenario | near % | ahead % | worst deficit | holes |
|---|---|---|---|---|
| cold20 | 0 -> 70 | 0 -> 71 | 11 -> 11 (first 2 s) | 11 -> 0 |
| cruise20 (20 km, 5 km/s) | 9 -> 99 | 6 -> 99 | 11 -> 1 | 0 -> 0 |
| low10 (5 km, 10 km/s) | 0.4 -> 19 | 0 -> 6 | 14 -> 2 | 0 -> 0 |
| brake_turn | 10 -> 99 | 8 -> 99 | 11 -> 1 | 0 -> 0 |
| approach | 24 -> 98 | 15 -> 82 | 10 -> 1 | 0 -> 0 |
| landing | 6 -> 74 | 5 -> 57 | 18 -> 4 | 0 -> 0 |

Mac mini M4 (8 workers, real renderer, before the throttle commit): no holes in any scenario; near %
cold20 90 (full near detail 2.3 s after a cold teleport), cruise20 99.3, low10 85.5, brake_turn 99.5,
approach 99.2, landing 96.2. Full chunk build median 32-36 ms per worker.

Main thread (cloud, low10): replan mean 8 ms, visibility mean 6 ms (separate frames), upload <= 4 ms.

## Tests
`tests/unit/terrain_streaming_test.gd` (16 tests): backstop coverage, parent kept until four children
show, coarsening keeps fine chunks until the coarser leaf is ready, backstop never re-queued,
preview -> full, filler sinking, cache reuse, cache bounds, corridor direction/bounds, finite normals at
face edges, neighbour edge seams, and a 60-step random-jump fuzz (no holes, no unsunk double layers).
Full suite in the cloud: 381 tests / 107,031 assertions / 0 failures.

## Remaining
- low10 on 2 cores and landing "ahead" readiness are throughput-bound; next lever: reuse parent
  lattice samples or cut GDScript overhead per sample (~19 us).
- No in-game visual capture yet: cloud software rendering was too slow to boot the main scene. Run
  `tools/n14_fast_pass.tscn` (Run Current Scene) on the Mac; frames go to `tests/visual/out/fastpass/<time>/`.
- Running the test suite *inside* a scene (n14_mac_runner) fails `audio_library_test` only because
  `_ready()` then runs twice; the headless runner passes it.


## Mac fast-pass verification (2026-10-21)

Real Metal run from the canonical checkout:

- capture: `tests/visual/out/fastpass/2026-10-21T19-09-23/` (97 frames + `fastpass.log`)
- every sampled phase reported `holes=none`
- cruise/landing were effectively fully populated near the ship; low-altitude 10 km/s remained
  preview/filler-covered rather than fully detailed (60-80% full near leaves)
- frame rate was ~100-145 FPS; plan/visibility/upload maxima were 34.8/18.5/15.2 ms
- the harness now sets `PROCESS_MODE_ALWAYS` and clears the title pause, otherwise direct scene runs
  waited forever on the paused title screen

The fast-pass output is local review material and is ignored by Git.


## Streaming rework (2026-10-21, after the GPU-height flights)

Owner report: far chunks loaded as huge blocks, morphed and glitched as smaller ones formed near the ship, and flying
stuttered. Measured before the rework (fast pass above): plan 34.8 ms, visibility 18.5 ms, upload 15.2 ms on the main thread.

What changed (all in `src/planet/`):

- **One layer only.** The planner returns a tree (leaves plus split nodes). A split node shows its four children only when
  all four can be shown; otherwise it shows itself. No overlap, so no sunk "filler" layer, no depth fighting, no preview
  grids. Levels 0-2 stay a pinned backstop built first.
- **Top-down builds.** Every node of the tree is built (not just the leaves), ordered by how near the ship is or will be,
  ancestors before descendants. A region refines one level at a time.
- **Geomorph.** Each vertex carries (CUSTOM0) the offset to where it sits on the parent chunk. A chunk that replaces its
  parent starts at morph 1 (the parent's exact shape) and eases to 0 in 0.7 s (`morph` instance uniform in
  `terrain_detail.gdshader`). Replacing a parent therefore does not pop.
- **Finer detail.** `LodPlanner.SPLIT_RATIO` 2 -> 3 (about 8 px per quad at the near edge of a chunk's range, 4 px at the far
  edge); a chunk that was split merges back only at 1.15 times that distance (no flip-flopping). The finest chunk is about
  72-96 m across (`PlanetBody.FINEST_CHUNK_EDGE_METRES`, 2.2 m vertex spacing) instead of 40 m / 1 m: below that the surface only
  showed float32 rounding noise (the "corrugation").
- **Main-thread cost.** Planning (tree, build order, what to show) runs on its own thread (`threaded_planning`, set by
  `scenes/main.gd`); the main thread applies only the difference. The planner no longer queries terrain height (centres use the
  height of the nearest built chunk). Workers build the `ArrayMesh` themselves. All chunk nodes sit under one root, so a
  floating-origin shift moves one node instead of re-placing every chunk.
- **Diagnostics.** Debug runs print a `terrain:` line every five seconds with the worst plan / show-hide / upload times.

Tuning knobs: `LodPlanner.SPLIT_RATIO`, `MERGE_HYSTERESIS`, `PlanetBody.FINEST_CHUNK_EDGE_METRES`, `PlanetTerrain.MORPH_SECONDS`,
`PLAN_INTERVAL_SECONDS`. Not yet verified on the Mac: frame times and the look of the morph (written without a Godot binary).
