# Performance results

Measured with `tools/perf_run.gd` on the Mac mini M4 (Apple M4 GPU, Metal), Godot 4.7.2, 1152x648 window,
Forward+, no vsync override. Scripted descent from 300 km orbit to touchdown. Frame time includes everything
(terrain chunk upload, POIs, audio, HUD). The average is pinned at 10.0 ms: the display/engine appears to cap
at 100 fps, so the average says "at least 100 fps", the p95/worst columns are the informative ones.

| Date | Phase | Frames | Avg ms | p95 ms | Worst ms | Min fps |
|---|---|---|---|---|---|---|
| 2026-10-18 | orbit to atmosphere | 2339 | 10.00 | 12.01 | 14.27 | 70 |
| 2026-10-18 | low descent (chunk streaming) | 9468 | 10.00 | 12.56 | 23.35 | 43 |
| 2026-10-18 | landed on ground | 181 | 10.01 | 12.97 | 14.78 | 68 |

Budget (ARCHITECTURE §11): 60 fps minimum. The worst single frame during descent (23 ms) is one chunk-upload
spike; 1440p was not measured. Not measured: memory (budget 4 GB), draw calls, physics tick time.


## Phase 2 baseline (after N6), 1920x942 window

`tools/perf_run.gd -- 2560x1440` on the Mac mini M4 (Metal 4.0, Forward+, Godot 4.7.2). The requested 2560x1440 window was clamped by macOS to
1920x942: this machine's display is 1920x1080, so true 1440p was **not** measured. Scripted descent from 300 km orbit, with the six-room ship,
two crew, fire/power systems and POIs running. Ship interior and fire were not in view during this run.

| Phase | Frames | Avg ms | p95 ms | Worst ms | Min fps |
|---|---|---|---|---|---|
| orbit to atmosphere | 2333 | 10.03 | 11.62 | 84.85 | 12 |
| low descent (chunk streaming) | 9817 | 10.00 | 12.48 | 15.15 | 66 |
| landed on ground | 181 | 10.00 | 12.58 | 13.56 | 74 |

Other readings (maxima over the run): 371 draw calls, 490,208 primitives, physics tick 3.75 ms, script process 60.63 ms (a one-off spike, same
frame family as the 85 ms worst frame near the start of the orbit phase). Memory: static 111 MB (peak 111 MB), video RAM 205 MB. The texture-memory
monitor returned a nonsense value and is ignored. All within the ARCHITECTURE §11 budgets (60 fps, 2000 draw calls, 4 GB) except the one-off start-of-run spikes,
which are not investigated. Draw calls with the interior in view, and fires/lights, were not measured (N8).
