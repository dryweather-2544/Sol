# N14 — Terrain Streaming Progress and Next Actions

**Date:** 2026-10-21  
**Purpose:** Track the fast-flight terrain-loading bug, the streaming investigation so far, and the remaining implementation/verification work.  
**Remote baseline audited:** `n13-graphics-port` at `8a46be86d6d241816d96bb1b03551298c3df2fd3`.  
**Important branch note:** The developer's current DeepSeek session reports that it is working in a *local* branch named `n14-rodina-parity`. That branch was not present in the GitHub branch list at the time of this document. Details attributed to that local session are therefore recorded as worklog-reported, not as verified code already present in this remote branch. Do not reset, overwrite or assume the remote branch contains the latest local changes.

## 1. Reported player-facing problem

During fast flight near or over Aurelia, large regions of terrain become smooth, blank, or appear as rectangular patches while the ship continues moving. The missing/high-detail surface seems to fill in only after the player slows down or stops. The owner supplied screenshots and a short screen recording on 2026-10-21.

This is both a visual-coverage issue and a throughput/scheduling problem. A purely visual material adjustment will not fix it.

## 2. What is verified in the current GitHub baseline

Files inspected at `n13-graphics-port`:

- `src/planet/planet_terrain.gd`
- `src/planet/lod_planner.gd`
- `src/planet/chunk_mesher.gd`
- `src/planet/height_function.gd`
- `scenes/main.gd`
- `tests/unit/lod_planner_test.gd`
- `docs/decisions/0002-height-query-collision.md`

### Current streaming behaviour in the remote baseline

- The terrain planner replans every **0.2 seconds** (`PLAN_INTERVAL_SECONDS`).
- A maximum of **6 builds** may be in flight (`MAX_BUILDS_IN_FLIGHT`).
- Up to **4 completed chunks per frame** are attached to the scene tree (`CHUNKS_ADDED_PER_FRAME`).
- The LOD planner selects a complete set of leaves intended to cover the planet.
- The terrain code attempts to keep old chunks until displayed children cover their area, via `_remove_obsolete_chunks()`, `_children_covered()`, and `_displayed_prefixes`.
- Chunk mesh construction uses a **fixed 32 × 32 quad grid for every LOD level** (`ChunkMesher.GRID`).
- `main.gd` updates the terrain viewer to the current actor position, but the inspected version has no velocity-driven predictive viewer, forward-path prefetch, or ready-mesh cache.
- `_replan()` replaces `_build_queue` with the currently desired unbuilt chunks every plan interval.
- `_collect_finished_builds()` only displays a completed result when its key is currently in `_desired`; other results are discarded rather than retained for later use.
- `is_settled()` waits for every currently desired chunk to be displayed. It should not be used as the only measure of responsiveness when the desired set is large.
- Terrain collision and on-foot ground queries use the same `HeightFunction` as the mesh, rather than generated chunk collision meshes. Preserve this source-of-truth arrangement during streaming optimisation.

These behaviours explain several plausible causes of slow refinement: fixed mesh work even for very coarse tiles, no predictive lead time, no reusable ready-mesh cache, queue churn when the desired set changes, and limited build/scene-add throughput. The rectangular patches in the supplied captures still need to be reproduced and traced to the specific coverage transition or mesh result that causes them; the baseline code's comments alone do not prove coverage is correct in every transition.

## 3. Probe figures reported by the earlier local session

The previous streaming worklog reported the following measurements. They are **historical observations**, not independently re-run on this documentation change:

| Probe | Reported observation | Interpretation |
|---|---|---|
| Fast jump at around 20 km altitude and 5 km/s | Desired set reached about 417 chunks; early probe showed only 3 displayed after 1 second | On-demand refinement falls far behind the viewer |
| Later fallback probe | 6 chunks displayed after 1 second and 54 after 6 seconds | Coarse coverage was being assembled, but coverage/detail arrived progressively |
| Later concurrency experiment | 24 tasks in flight still yielded roughly 25 displayed after 4 seconds | Increasing concurrency alone did not provide the expected throughput improvement |
| Parallel mesher profile | 8 chunk builds took about 603 ms in aggregate | Around 13 builds/second at that measured point; confirm under the same conditions before comparing |

The earlier probe also produced an approach screenshot where the planet was continuously covered by a smooth, low-detail surface. That is a useful fallback result, but it does **not** demonstrate that high-detail terrain will arrive fast enough during a 5–10 km/s pass.

## 4. Changes reported in the local N14 worklog — verify before relying on them

The developer-provided DeepSeek worklog describes prior work in the local `n14-rodina-parity` tree:

- Predictive look-ahead planning was added to prioritise terrain ahead of the moving viewer.
- Hierarchical fallback was introduced: six LOD-0 face chunks, then progressively finer coverage.
- A thread-safety issue around shared height-function/noise state was investigated; the worklog says worker builds were changed to use separate height-function instances.
- Greater build concurrency was tested and then reduced/reverted because it did not improve effective throughput sufficiently.
- The previous-session note says target HUD brackets were also committed locally while doing other work; that is unrelated to terrain performance.
- A more detailed profiling/optimisation pass was beginning, with **LOD-aware mesh grids in `ChunkMesher`** called out as the next item.

Those items are not all present in the remote `n13-graphics-port` code inspected for this note. Before changing anything, DeepSeek should inspect `git status`, `git diff`, `git log`, and the active branch on the actual Mac, then continue from its actual current working tree without discarding changes.

## 5. Required next work, in priority order

### A. Prove complete coarse coverage

Verify actual displayed geometry at every transition. Do not assume the ancestor bookkeeping is correct simply because the helpers exist.

- Display the six coarse faces as quickly as practical.
- Keep fallback ancestors on screen until displayed descendants cover all four child regions recursively.
- Check mesh placement, normals, seams and overlapping parent/child surfaces.
- Add a deterministic coverage test that moves the viewer sharply and asserts that every visible region remains covered while builds are incomplete.
- The target is an unbroken coarse planet immediately, not instant high detail everywhere.

### B. Reduce mesh build cost

- Implement LOD-aware grid density: very coarse LODs should use small grids; detail should increase toward the viewer.
- Profile height evaluation separately from vertex/index generation.
- Preserve a common and authoritative height function for rendered terrain and ground-contact queries.
- Validate silhouette, normals, material sampling and seams after changing resolution.
- Preserve worker-thread safety. Do not pass mutable `FastNoiseLite` instances across worker threads if they are not safe for concurrent use.
- Benchmark sensible worker concurrency on the actual Mac; don't equate more in-flight tasks with more completed chunks.

### C. Finish predictive preloading

- Feed terrain a reliable viewer velocity while in ship mode, and use a safe movement estimate on foot.
- Predict a bounded point or corridor ahead of the ship's flight path. Adapt look-ahead distance to speed and measured chunk-build latency, with upper bounds.
- Prioritise missing coverage, then the current view, then the upcoming flight corridor, then background refinement.
- Keep speculative jobs from starving chunks near the actual viewer.
- Ensure queued work does not churn unnecessarily when the viewer moves or the desired set is replanned.

### D. Cache useful completed work

- Keep completed meshes even if they are not in the current desired leaf set, within a capped memory budget.
- Reuse cached chunks when the viewer approaches them.
- Avoid duplicate work for chunks that are already displayed, pending, queued or cached.
- Evict stale low-value speculative results by an explicit policy.
- Build the cache only after coverage and throughput are measured so it does not hide a slower underlying mesher.

### E. Re-run representative probes and a real flight pass

Use repeatable scenarios and record results before/after each meaningful change:

1. Planet created at high orbit.
2. Approach at approximately 20 km and 5 km/s.
3. Low-altitude pass around 10 km/s.
4. Brake, turn around, and retrace the route.
5. Approach the surface, land, and walk.

Record desired/displayed/pending/queued/cached counts by LOD, median and p95 build durations, completed chunks per second, time to first complete coarse coverage, time to detailed coverage around the viewer, amount of high-detail terrain ready ahead of the ship, and peak cache memory. Capture a new fast-pass recording and visually compare it with the supplied 2026-10-21 recording.

Run the full Godot 4.7.2 headless suite and launch the actual Mac build for visual verification. A passing LOD planner unit test is not proof of streaming continuity.

## 6. Acceptance criteria

- No exposed blank rectangles or missing terrain areas while moving at the test speeds.
- Complete coarse coverage appears quickly and remains visible during refinement.
- High-detail terrain is generated ahead of the ship often enough to materially reduce the load-behind effect.
- Completed prefetched chunks are reused instead of repeatedly discarded and rebuilt.
- LOD seams and transitions remain stable; terrain colour/material and planet-specific landforms are preserved.
- No change to flight physics is used to hide the loading problem.
- Existing landing, ground contact, walking, save/load and planet-specific terrain tests still pass.
- The final report includes comparable before/after metrics and a fast-flight capture; unresolved limitations are reported explicitly.

## 7. Working-model note

For the repeated edit–run–profile loop, the team chose to keep **DeepSeek-V4.1-Flash 1017** selected in the active agent UI, and reserve V4-Pro for a targeted second opinion/review if a specific reasoning issue persists. This is a workflow choice, not a substitute for measurements or test evidence.

## 8. References

- [Current terrain streamer](../src/planet/planet_terrain.gd)
- [Current LOD planner](../src/planet/lod_planner.gd)
- [Current chunk mesher](../src/planet/chunk_mesher.gd)
- [Height function](../src/planet/height_function.gd)
- [Ground-contact/collision decision](decisions/0002-height-query-collision.md)
- [N13 graphics port report](N13_GRAPHICS_PORT.md)
- Owner-supplied Rodina visual references: [Sol-Assets visual reference guide](https://github.com/dryweather-2544/Sol-Assets/blob/a6-remaining-materials/reference/rodina/README.md)
