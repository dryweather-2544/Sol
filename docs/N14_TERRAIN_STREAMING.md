# N14 terrain streaming and preload

## Repro

The real main scene was moved to a 20 km altitude at 5 km/s. Before this pass a streaming probe showed:

```
desired=417 displayed=3 pending=6 queue=414 missing=417
```

The new fine chunks were requested only around the current viewer, and there was no coarse fallback;
the planet could be empty or smooth until the player stopped.

## Changes

1. `LodPlanner.select_leaves(viewer, preload_viewer)` now subdivides around both the current viewer and
   a predicted point ahead.
2. `PlanetTerrain.viewer_velocity` supplies the prediction. The lookahead is 2.5 s and capped at 25 km,
   so an enormous orbital speed cannot flood the planner.
3. The build queue prioritizes a **level-0 fallback** (six face chunks) first. A level-0 face is one
   coarse mesh, enough to keep the planet visible while the fine set streams.
4. Fine chunks are then requested ahead of the fallback; coarse faces are removed only once their
   children cover them, so there is no hole during replacement.
5. Each worker chunk builds its own `HeightFunction`; the shared grammar noise cache is no longer
   mutated concurrently. This removed a worker stall seen with the new terrain grammar.

## Evidence

- Streaming probe after the coarse fallback: six fallback faces displayed after ~1 s, with fine chunks
  continuing to arrive; the planet is no longer blank.
- Visual capture: `/tmp/n14_terrain_stream/approach_fallback.png` (real main scene, 20 km, 5 km/s).
- Existing LOD tiling/preload test: `tests/unit/lod_planner_test.gd::test_preload_viewer_requests_detail_ahead_without_overlap`.

## Remaining work

- Fine-chunk build throughput is still too low for a teleport directly to low altitude: the probe
  requests ~400 fine chunks and only a few dozen are ready after a few seconds. A normal descent can
  preload progressively, but a better budget/LOD cap or faster height sampling is needed.
- The level-0 fallback itself is visibly smooth; it is coverage, not HD terrain.
- Chunk upload/removal budgets and build time need profiling on the real Mac under a normal descent.
