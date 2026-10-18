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
