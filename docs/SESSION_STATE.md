# Session state (keep short)

- Branch: `n14-rodina-parity`. Mac worktree `~/Documents/Sol-n14`: HEAD `f72fcd7` (previous agent's
  streaming WIP, committed as found), N14 streaming files applied but **uncommitted**.
  Cloud checkout has the same work as 3 commits on top of that tree; patches:
  `n14_patches/0001..0003` (apply on the Mac with `git am` after discarding the uncommitted copies).
- Tests (cloud, Godot 4.7.2 headless): 381 / 107,031 assertions / 0 failures.
- Perf: Jarilo height sample ~19 us (was ~100); full chunk ~28 ms. Streaming results: docs/N14_TERRAIN_STREAMING.md.
- Tools: tools/n14_terrain_bench.gd, tools/n14_height_breakdown.gd, tools/n14_stream_probe_cli.gd,
  tools/n14_mac_runner.tscn, tools/n14_fast_pass.tscn.
- Open: in-game visual verification on the Mac (fast-pass scene); low-altitude 10 km/s detail on few cores.
- Next: cut per-sample GDScript cost in the Jarilo grammar, then Priority 3 (Rodina terrain grammars vs source).
