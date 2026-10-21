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
