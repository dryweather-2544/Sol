# 00 — Master Index

**Project:** Rodina 1.6.2 static source analysis for **Starfall** (Godot 4.7.2 Forward+).
**Purpose:** give a later AI coding agent (Claude Code) a reliable, evidence-backed reference so it does not have to repeat this research.
**Research date:** 2026-10-17.
**Analysis type:** read-only static inspection. No game executable, DLL, script, or build tool was run. No Rodina asset or code is proposed for reuse.

---

## 1. Where everything is

**Rodina source root (extracted, read-only):**

```
/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/
```

**Archive (verbatim copy):**

```
/Users/arielbowyer/.dsh/attachments/v1/files/fb/fba64a7dd90f900e6bb9cccf41e231428c40f45d7bafa659a6e88cf98c67d33e/Rodina.v1.6.2.rar
```

**Starfall project (read-only for this research):**

```
/Users/arielbowyer/starfall/
```

**This library:**

```
/Users/arielbowyer/Documents/Deepseek workspace/rodina-starfall-reference/
```

The Starfall project was **not modified**. Research files are outside both source trees.

---

## 2. Read this first (routing for Claude)

If you only have time for three files:

1. **[08_STARFALL_IMPLEMENTATION_GUIDE.md](08_STARFALL_IMPLEMENTATION_GUIDE.md)** — the actionable plan, ordered by priority, grounded in Starfall’s current scripts.
2. **[09_SOURCE_EVIDENCE_INDEX.md](09_SOURCE_EVIDENCE_INDEX.md)** — every major claim with file/line and confidence; use it to cite or verify.
3. **[02_SPACESHIP_AND_PILOTING.md](02_SPACESHIP_AND_PILOTING.md)** and **[03_INTERIORS_AND_AIRLOCKS.md](03_INTERIORS_AND_AIRLOCKS.md)** — the two subsystems most likely to be touched first.

Suggested full order:

```text
00  (this file)
 └── 08  implementation guide
      ├── 02  flight/piloting      (for PilotCommand/PilotController)
      ├── 03  interiors/airlocks   (for PlayerState/Seat/Airlock)
      ├── 04  planets/terrain      (for landing/terrain variety)
      ├── 05  procedural content   (for POIs/saves)
      ├── 06  AI/navigation        (for crew AI)
      ├── 07  formats/assets       (what not to import)
      ├── 09  evidence index       (citations)
      └── 10  open questions       (what is not known)
```

**Do not read all 12 files sequentially before acting.** Read `08` and `09`, then only the subsystem report you need. The reports are deliberately cross-linked.

### What Claude should do with this library

- Treat `C` (confirmed) findings as safe to build on.
- Treat `I` (inferred) findings as design guidance, not fact; verify against source if the change is risky.
- Treat `U`/`A` as unknown or absent; do not build a critical feature on them without a fallback.
- Preserve Starfall’s existing flight model, kinematic on-foot controller, cabin, and planet addon. The guide is additive.
- Do not copy Rodina code/assets. The library describes concepts and evidence, not implementations.

---

## 3. Directory map

| File | What it is | Read when |
|---|---|---|
| [00_MASTER_INDEX.md](00_MASTER_INDEX.md) | This entry point, key findings, gaps, progress | First |
| [01_COMPLETE_FILE_INVENTORY.md](01_COMPLETE_FILE_INVENTORY.md) | 2,282-file inventory, script tables, asset counts, inspection status | You need to know what exists / what was read |
| [02_SPACESHIP_AND_PILOTING.md](02_SPACESHIP_AND_PILOTING.md) | Ship classes, shared pilot interface, gears, relative time, atmosphere, landing, cameras, AI control | Touching flight, piloting, cameras |
| [03_INTERIORS_AND_AIRLOCKS.md](03_INTERIORS_AND_AIRLOCKS.md) | Interior entity/space, `.egi` formats, rooms, doors, seats, airlock, walkway, boarding, transitions | Touching cabin, seats, doors, airlock, boarding |
| [04_PLANETS_AND_TERRAIN.md](04_PLANETS_AND_TERRAIN.md) | Planet data, units, orbits, height-field algorithms, LOD, atmosphere, gravity, landing, precision | Touching planets, terrain, atmosphere, landing |
| [05_PROCEDURAL_CONTENT.md](05_PROCEDURAL_CONTENT.md) | Seeds, proxies, spawn/discover radii, capacities, buildings, asteroid belt, EGSL grammar, persistence | Touching POIs, procedural content, discovery, seeds |
| [06_AI_AND_NAVIGATION.md](06_AI_AND_NAVIGATION.md) | Behaviour framework, combat FSM, travel/orbit/follow, character AI, sensors, group coordination | Touching AI, crew, navigation |
| [07_DATA_FORMATS_AND_ASSETS.md](07_DATA_FORMATS_AND_ASSETS.md) | Lua, `.egm`, `.egi`, `.rsl`, `.fx/.egs`, `.egu`, audio, fonts, docs, exporter, limitations | Any format/asset question |
| [08_STARFALL_IMPLEMENTATION_GUIDE.md](08_STARFALL_IMPLEMENTATION_GUIDE.md) | Priority-ordered independent implementation brief with nodes/scripts/resources/signals/tests | Planning or coding |
| [09_SOURCE_EVIDENCE_INDEX.md](09_SOURCE_EVIDENCE_INDEX.md) | Searchable finding → file:line → confidence table | Verifying or citing |
| [10_OPEN_QUESTIONS.md](10_OPEN_QUESTIONS.md) | Unknowns, disabled logic, binary formats, engine-side gaps, partial inspections | When something is not in the source |
| [11_QUALITY_CHECK.md](11_QUALITY_CHECK.md) | Verification log: citation audit, corrections, contradictions, coverage | Auditing confidence |
| [CLAUDE_CODE_PROMPT.md](CLAUDE_CODE_PROMPT.md) | Ready-to-paste implementation prompt for Claude Code | Starting work |
| [99_FILE_MANIFEST.csv](99_FILE_MANIFEST.csv) | Complete machine-readable manifest (path, ext, bytes, category) | Auditing inventory |
| [_work/rendering_notes.md](_work/rendering_notes.md) | Deep shader/terrain/atmosphere analysis | Rendering detail |
| [_work/ui_audio_notes.md](_work/ui_audio_notes.md) | Deep UI/input/audio/options analysis | UI/audio detail |
| [_work/persistence_notes.md](_work/persistence_notes.md) | Deep save/load protocol analysis | Save-system detail |
| [_work/grammar_notes.md](_work/grammar_notes.md) | Deep EGSL grammar analysis | Grammar detail |
| [_work/items_combat_notes.md](_work/items_combat_notes.md) | Deep items/weapons/particles/characters/buildings analysis | Item/combat detail |

`_work/` is source material, not the polished reference. Prefer the numbered reports for decisions; use `_work` for depth.

---

## 4. The most important confirmed discoveries

These are the findings with the highest architectural value. Each is confirmed in readable Lua/shader/data unless marked.

1. **Human and AI pilots share one interface.** `EGBehaviorPlayer` and every **ship** AI behaviour fill the same `PilotInterface` (gear, move, moveLock, face/turn, clutch, desiredVelocity, lockLinear), and `EGVehicle:ApplyMovement` is the only consumer (`EGBehavior.lua:57-83`, `EGBehaviorPlayer.lua:206-237`, `EGVehicle.lua:594-620`). This is the single best pattern in the archive for Starfall.

2. **Control authority is separate from camera target.** `SetPlayerControlled` call sites imply `(isCamera, isControl)`: in first-person piloting the ship still receives control while the player entity owns the camera (`EGGame.lua:250-284`, `EGGame.lua:875-887`, `EGVehicle.lua:2217-2222`, `EGMenuHUD.lua:173-178`). This is what makes cockpit view, remote piloting, and AI takeover composable.

3. **The player persists while piloting.** `StartPilotingVehicle` reuses the existing character and parents it to the ship interior; first/third person only swaps flags (`EGGame.lua:237-262`, `:315-350`). “Piloting” is a control/camera mode, not a new entity and not a readable seated animation.

4. **Landing is contact-relative, not altitude-relative.** The ship is “landed” when `surfaceDistance <= lastTerrainContactDistance + 1 m` and speed `< 4 m/s` (`EGVehicle.lua:736-737`, `:2009-2047`). This is robust on slopes and cheap; Starfall’s support-point method is a stronger version of the same idea.

5. **Planet POIs are lightweight seeded proxies with three rings.** Spawn detailed content at `< 10 km`, finalize a story object at `< 3.5 km` (on foot), discover at `< 100 m` (on foot); proxy flags/list are saved (`EGProxyItem.lua:53-98`, `:244-311`). Planet debris is seeded by `EGRandom(planetSeed, index)` (`EGPlanet.lua:208-224`).

6. **Interiors have three incompatible encodings.** `.egi` v1 ASCII grid, v14–17 structured ASCII, and the player-ship `DefaultMap.egi` binary string-table format. The player ship interior is **not** fully readable (`03`, `07`).

7. **Airlock interlock Lua is disabled.** `Items.Airlock:Update` is entirely inside a long comment (`EGDataItems.lua:353-403`). The menu still writes `CloseAirlock/OpenAirlockIn/OpenAirlockOut`; pressure/fire are engine components (`EGInterior.lua:7`). Treat the interlock rules as intent, not confirmed runtime.

8. **Several AI behaviours are stubs.** `Travel`, `Orbit`, and `Follow` have their `Update()` transition bodies commented out (`EGBehaviorTravel.lua:116-176`, `EGBehaviorOrbit.lua:95-117`, `EGBehaviorFollow.lua:51-61`); `Investigate` calls `error("LOOKAT")` (`EGBehaviorInvestigate.lua:67-74`). Ship navigation is delegated to the engine mover. Do not describe these as working multi-state AI.

9. **Save/load is two protocols, version 38.** Keyed `Encode/Decode` buffers and positional versioned `Load` streams coexist; no class has the buffer path without the legacy path (`GameplayMain.lua:57-70`; `_work/persistence_notes.md`). The real gate set includes 4,7,17,21,22,23,28,29,31,33,35; there is no `>=38` *stream* gate (`EGGame.lua:501` is buffer-era).

10. **Planet height is a cubesphere bake with a four-channel feature grammar.** Domain-warped Perlin + Voronoi base + plateau/mountain/holes masks, then a weighted sum (`PlanetPerun.h:52-150`); materials blend with six multiplicative gates and distance-widened bands (`RodinaTerrain.fx:40-75`). Mesh LOD/collision are engine-side.

11. **`.egs` is a three-way extension collision.** Savegames, compiled Lua bytecode, and shader cache all use `.egs` (`EGGame.lua:420`, `EGCore.lua:430`, `Shaders/ShaderCache`). Never dispatch on extension alone.

12. **The interior grammar is EGSL, and two semantics are undefined.** `.rsl` uses `production/weight/priority/let/concept/produce/rule`; `let` is both precondition and assertion, and `priority` is never defined (`ProductionTestCore.rsl:15-222`; `_work/grammar_notes.md`). A faithful reimplementation is not possible from the files alone; build a smaller typed system instead.

---

## 5. Highest-value applications for Starfall

Ordered by leverage. Full detail and tests in `08`.

| # | Application | Why it matters | Rodina evidence | Starfall starting point | Priority |
|---|---|---|---|---|---|
| 1 | **`PilotCommand` + `PilotSource` + `PilotController`** | One path for player, AI, remote, scripted, and future crew; unlocks everything else | `02` §3 | `scripts/ship.gd` reads input directly; add adapter, keep math | **Now** |
| 2 | **Explicit player state: posture / location / authority** | Prevents softlocks, duplicated seats, camera/authority bugs; foundation for crew/co-op | `02` §4, `03` §7 | `scripts/pilot.gd` single enum; split it | **Now** |
| 3 | **Room/portal/occupancy + airlock state machine** | Reliable doors, pressure, boarding, takeoff interlocks; co-op safe | `03` §6-§9 | `scripts/ship_cabin.gd` has rect rooms + interlock; evolve it | **Now** |
| 4 | **Slope-aware landing controller** | Uneven terrain is Starfall’s signature; current landing is close but can jitter/sink | `02` §6, `04` §4 | `Ship.ground_gap()` + feet; add plane alignment | **Now** |
| 5 | **Seeded POI instances + streaming rings** | Gives Starfall exploration content without loading a planet of scenes | `05` §4-§9 | none; new system | Next |
| 6 | **Versioned save/load (player, ship, doors, POIs, discoveries)** | Without it, POIs and progression are meaningless | `_work/persistence_notes.md` | none | Next |
| 7 | **Terrain profiles + feature masks + pads** | Planet/landing-zone variety | `04` §3-§9 | `TerrainNoise` single profile | Later |
| 8 | **Crew roles/stations + authority + one crew AI** | Future co-op and ship feel; needs 1-3 first | `06` §7 | none | Later |
| 9 | **Terrain material blending (altitude/latitude/normal masks)** | Big visual variety for low cost | `RodinaTerrain.fx:40-75` | `terrain.tres` shader | Later |
| 10 | **Atmosphere horizon/sunset palette + DOF coupling** | Better atmospheric look; optional physical upgrade later | `_atmosphere.h`; `_work/rendering_notes.md` | planet atmosphere shader | Later |

**Do not start with AI or crew.** Rodina’s own AI is partly disabled; Starfall’s first win is a trustworthy control/authority/state layer.

---

## 6. Verified numbers worth remembering

| Fact | Value | Source |
|---|---|---|
| Source files / size | 2,282 / ~250 MB (244 MiB) | `99_FILE_MANIFEST.csv` |
| Lua files | 160 | `find` |
| Lua class definitions | 439 | extraction |
| `.rsl` grammar files / lines | 10 / ~3,625 | `_work/grammar_notes.md` |
| `.egm` models / versions | 546 / 0,1,2,5,16,20 (351 v5) | header scan |
| `.egi` interiors | 11 (8 + 3 legacy maps) | `Data/Interiors`, `Data/Models` |
| Shader sources | 72 `.fx`/`.h` | `Shaders/` |
| Compiled shaders | 1,079 `.egs` | `ShaderCache/` |
| Audio | 62 `.wav`, 24 `.egu` | `Data/Sounds`, `Data/Music` |
| Documents | 162 `.txt` | `Data/Documents` |
| Game save version | 38 | `EGGame.lua:5` |
| Game AU | 7.5e9 m | `EGConstants.lua:4` |
| Player ship mass / hull | 5000 / mesh | `EGDataShipPlayer.lua:26-38` |
| Player ship speed by gear | 100 / 500 / 5–10k / 30k m/s | `EGDataShipPlayer.lua:131-233` |
| Landing threshold | contact + 1 m, speed < 4 | `EGVehicle.lua:2020` |
| POI rings | 10 km / 3.5 km / 100 m | `EGProxyItem.lua:68,74,78` |
| Walkway hysteresis | 75 / 500 speed² | `EGDataShipPlayer.lua:468,478` |
| Airlock pressure threshold (intent) | > 0.99 | `EGDataItems.lua:390` |
| Atmosphere entry timer | 4 s | `EGVehicle.lua:5` |
| Terrain distance bands | 500/5k/50k/2M m; 50/750/750/18,000 km | `RodinaTerrain.fx:21-37` |

---

## 7. What is not known / inaccessible

Full detail in `10_OPEN_QUESTIONS.md`. The short list:

- **Engine source is absent.** Terrain mesh/LOD/collision, origin shifting, ActionMove navigation, room pressure equalisation, airlock runtime, seating, boarding triggers, camera spring, menu stack, particle simulation, and save container are C++.
- **Binary/opaque formats:** `DefaultMap.egi`, `.egu` music, `.egs` shader bytecode, `.spritefont`, savegames, `.egm` version semantics.
- **Disabled/incomplete Lua:** airlock interlock, Travel/Orbit/Follow transitions, Investigate `LOOKAT`, several save fields, interior fire persistence.
- **Behavioural unknowns:** what happens with a player outside during takeoff, vacuum damage, whether the pilot is visually seated, whether the engine enforces door interlocks, AI gear/phase authority.
- **Partial inspections:** `EGEditorData.lua` (11k lines), `EGDataParticles.lua` (5k), `EGMenuHUD.lua` (1.7k), `EGSceneEditor.lua`, `EGDataItems.lua` full inventory, `EGDataProgress.lua` every transition, some UI/render files. See `01` §5.
- **No save sample**, no design docs, no official format spec, no multiplayer code.

Do not fill these gaps with guesses. Mark them and design a fallback.

---

## 8. Research progress summary

| Metric | Value |
|---|---|
| Files inventoried | **2,282 / 2,282** |
| Scripts inventoried | **171 / 171** (160 Lua, 10 `.rsl`, 1 `.py`) |
| Major subsystems covered | **8** (flight, interiors, planets, procedural, AI, formats, persistence, UI/audio) |
| Lua files read fully or in depth | **68 / 160** (36 Full, 32 Partial) |
| Lua files analysed via delegated reports | **10** (items/weapons/particles/characters/HUD/audio/options) |
| Lua files inventoried only | **82 / 160** (mostly menus, editor, render tools) |
| `.rsl` grammars analysed | **10 / 10** (delegated) |
| Shader sources analysed | 72, plus 1,079 cache headers |
| Models/interiors/audio/docs inventoried | 546 / 11 / 86 / 162 |
| Binary formats documented as limited | 7 |
| Engine-side systems documented as gaps | 12 |
| Reports produced | 12 numbered + 5 deep `_work` reports + CSV manifest |

**Honest assessment:** this is a broad, evidence-based pass over every major subsystem and all files, not a line-by-line reverse engineering of the entire game. It is sufficient to guide Starfall’s current scope. It is not sufficient to reproduce Rodina’s exact runtime, formats, or assets — and it should not try.

---

## 9. Quick answers to likely questions

**“Can we use Rodina’s ship interior in Starfall?”**
No. The player map is a binary `.egi`, the geometry is proprietary, and the coordinate/room semantics are Rodina-specific. Build Starfall’s own `InteriorLayout` resource (`08` §4).

**“Can we copy the flight model?”**
Don’t. Starfall’s 6DOF model works and is tuned. Add a `PilotCommand` adapter; do not replace `ship.gd` (`08` §2).

**“Can we reproduce Rodina’s POI layouts?”**
No. `EGRandom` is engine-side and the exact sequence is not exposed. Implement Starfall’s own stable seed/hash and generation version (`05` §9, `08` §6).

**“Does Rodina have multiplayer?”**
No evidence of networking. The control/camera/authority split is nevertheless a good foundation for co-op (`08` §9).

**“What is the single most useful file to read?”**
`08_STARFALL_IMPLEMENTATION_GUIDE.md`, then `09_SOURCE_EVIDENCE_INDEX.md` for the exact citations.

**“What should Claude not do?”**
Do not import `.egm`/`.egi`/`.rsl`/`.egu`/`.egs`; do not port shader code line-for-line; do not rewrite working Starfall systems; do not claim engine-side behaviour as confirmed (`00` §2, `08` §13).

---

## 10. Provenance and ethics

- The archive is an unofficial distribution (IGG-GAMES/PCGAMESTORRENTS URLs beside it). It was inspected read-only and never executed.
- No Rodina code, model, texture, sound, music, font, or document is reproduced in this library beyond short factual quotations needed for analysis (function names, numeric constants, short rule snippets).
- All implementation guidance is independent and conceptual. Starfall should use its own art, audio, code, and data.
- If you need to verify a claim, use [09_SOURCE_EVIDENCE_INDEX.md](09_SOURCE_EVIDENCE_INDEX.md) and the original files, not this summary.
