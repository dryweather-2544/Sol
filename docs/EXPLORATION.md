# Exploration and salvage loop

Written 2026-10-22. **Status: implemented but NOT run** - the session that wrote it had no Godot (Mac-only), so no test
has been executed. First thing to do: `./tools/run_tests.sh`, then `./tools/run_tests.sh -- exploration`.

## The loop
1. Fly or walk toward a planet's surface and press **N**: a scanner pulse (4 s recharge). Every site within 3 km becomes a
   remembered *contact*, shown under the prompt for 25 s as `signal class   distance   direction   (status)`. Until you reach
   a site you only learn its class of signal ("Dense mineral reading", "Faint telemetry", "Unclassified energy", ...).
   Beacons and outposts still have their long-range beams; wrecks and the new small sites do not, so the scanner is the way.
2. Land nearby, leave the ship, walk to within 120 m (existing `DISCOVER_RADIUS`): the site is discovered and named.
3. Walk to its glowing stake and press **F** (crates for wrecks/beacons/outposts, as before). Each pays out once.
4. **J** opens the exploration log: name, type, location (lat/long), investigated or not, the research text and what was
   recovered, and how many scanner signals are still unidentified.

## What was added
- `PoiDefinition.Type` gained `PROBE`, `DEPOSIT`, `ANOMALY` (appended, so old numbers are unchanged). They use the existing
  crate/loot machinery: one interaction point (crate index 0), seeded loot in `LootTable`, state in the existing `LootLog`.
  Rewards: probe -> data chips (+scrap), deposit -> scrap (+fuel cell), anomaly -> data chips (+oxygen tank). All are existing items.
- `PoiPlanner.minor_density` (default 0, so the golden region hash and every original POI are untouched; `scenes/main.gd`
  sets 0.45). One optional site per cell, id `site_<i>_<j>_<k>`, own seed stream, only on ground with slope <= 0.35 and
  >= 250 m from the cell's large POI; otherwise no site.
- `PoiScanner` (pure functions, no new autoload, no per-frame world scan), `ExplorationLog` (rows for the screen),
  `ExplorationMenu` (J), `DiscoveryLog` now also stores type/seed/position/crate count and the scanner contacts.
- `GameSession.scan_pulse()`, `scan_text()`; prompt shows the scan readout under the contextual prompt.
- Inputs: `scan` = N, `journal` = J (checked against project.godot: both were free).

## Save format
No version bump. `pois.discovered` entries gained optional `type`, `seed`, `crates`, `position`; `pois.scanned` is a new
optional list. Everything defaults when absent, so v1-v11 saves load unchanged (old entries show status "visited").
Investigation state is the existing `pois.looted` list; research text and rewards are re-derived from the seed.

## Known limits
- Discovery still only happens on foot (existing rule); flying low over a site does not discover it.
- Placeholder primitives only; no licence-sensitive assets.
- Deposits are single-use (no repeatable mining).
