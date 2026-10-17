# 0004 — POIs are planned lazily per lattice cell, not as one global list

**Context.** ARCHITECTURE §8 planned `poi_seed(planet, index)` and "generate instances as data at planet
activation". On a 6,000 km planet that means either a handful of POIs (average spacing ~1,000 km, nothing
to find) or millions planned up front.

**Decision.** The planet surface is cut by a 3D lattice of `CELL_SIZE` (4 km) cells. Each cell
deterministically decides (from `combine(combine(combine(planet_seed, i), j), k)`) whether it holds one
POI, where inside the cell, and which of a few candidate sites is flattest ("site scoring"). Cells within
the planning radius of the viewer are planned on demand and cached. A POI's seed is that cell hash; its id
is `poi_<i>_<j>_<k>`. Rings, discovery and saves work on instances exactly as in §8.

**Consequence.** POI density is uniform to within ~1.7x (cells at oblique angles to the surface clip more
area), there is no global POI count, and the same world seed always gives the same POIs. `TerrainModifier`
pads are not implemented yet (sites are chosen flat instead). Changing `CELL_SIZE`, density or
generation_version changes every POI, so those are versioned in the save (`pois.generation_version`).
