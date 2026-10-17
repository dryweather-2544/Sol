# 10 — Open Questions, Uncertainties, and Further Work

**Purpose:** record exactly what could not be confirmed, why, and what would resolve it. This prevents later agents from mistaking an inference for a fact or from repeating work.

**Confidence tags:** `C` confirmed, `I` inferred, `U` unknown, `A` absent.

---

## 1. Access and scope

| # | Question | Current state | What would resolve it |
|---|---|---|---|
| A1 | Is there any source beyond the extracted 1.6.2 install? | We inspected `/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/` and the saved archive. No engine source, design docs, or save samples were present. | Provide engine source, a debug build, or official modding documentation |
| A2 | Was the extracted tree complete? | 2,282 files, ~250 MB (244 MiB); `Rodina.exe`/DLLs present. No `.pdb`, no editor project, no savegames. | Compare a Steam install manifest or provide the original install |
| A3 | Are there other versions with readable source? | Only 1.6.2 was inspected. Later/earlier versions could differ, especially the disabled AI/airlock code. | Provide another version (static comparison only) |
| A4 | Are the shipped Lua files actually the compiled/active ones? | The game can load `.lua` directly (`EGCore.lua:144-164`); no `.egs` bytecode files are present under `Scripts/`, so the `.lua` are likely the active source, but load order/selection is engine-side. | Engine logs or a manifest of loaded scripts |
| A5 | Does the engine load `Scripts/Render/*` in gameplay? | `RenderMain.lua` defines a duplicate `PlanetDef` with no superclass (`:50-52`), which would conflict with `EGPlanet.lua` if loaded after. No load-order file exists. | Engine script manifest or logs |

---

## 2. Engine-side systems with no readable implementation

These are the biggest gaps. They are not omissions in the archive; they live in `Rodina.exe`/DLLs and were not run or disassembled.

| # | System | What is known | What is missing | Impact on Starfall |
|---|---|---|---|---|
| E1 | Terrain mesh/LOD/collision | Data (`TerrainLOD*`, `HiDetailAltitude`, `TerrainDetailAltitude`); height shader; height query API | Chunk topology, tessellation, collision mesh generation, LOD selection, seam handling | High for planet fidelity, but Starfall already has its own quadtree; not blocking |
| E2 | Origin shifting / precision | `EGPreciseVector`, planet-local positions, nested worldspaces, shader `length(WorldPos)` LOD | When the origin shifts, float/double split, camera-relative transform propagation | Medium; Starfall has its own shift; revisit at multi-planet scale |
| E3 | Engine mover (ActionMove) | Field vocabulary and setter calls; sensors | Pathfinding, avoidance, orbit math, formation, speed authority, brake model | High for AI; Starfall should own its navigation instead |
| E4 | Room pressure simulation | Per-room scalar API, decompression force API, `RoomPressure` component | Leak/equalisation rates, door sealing model, vacuum damage, fire interaction | High for airlock fidelity; Starfall should implement its own |
| E5 | Airlock runtime interlock | Menu flags; disabled Lua implementation; `SetExteriorDoorsClosed` API | Who actually enforces the interlock, whether flags are read by the engine | High; assume engine-side or no enforcement |
| E6 | Seating | `ForceSitInChair`, `GetCurrentChair`, `IsChair` flags | How a character is placed, animated, and detached; whether piloting seats the character | Medium; Starfall has its own seat design |
| E7 | Boarding trigger | `MakeEntranceBounds(entrance.egi)`, `EntrancePath` | Trigger shape, prompt, teleport/spawn transform, authority checks | High; Starfall needs its own boarding controller |
| E8 | Camera | `SetCameraFollow`, `SetFOV`, `SetFreeLookVelocity`, control/camera actor flags | Camera collision, spring model, first-person eye placement, view blending | Medium; Starfall's ChaseCamera is independent |
| E9 | Menu stack | `EGMenuSystem.lua` is fully commented; engine API calls (`Open`, `GetOpen`, `IsMenuMode`, cursor/freeze modes) | Stack ownership, input routing, offscreen targets, pause semantics | Low for Starfall; use Godot UI |
| E10 | Particle rendering | Data schema, `AttachParticles` calls | Emitter simulation on GPU/CPU, sorting, lighting, pooling | Low/medium; Starfall can use GPUParticles |
| E11 | Save container | Version 38, keyed buffer + positional stream, `System.SaveGame` | Actual container layout, compression, checksums, section order, entity graph | High; Starfall will design its own |
| E12 | Model/physics loading | `.egm` text schema, physics basis references | Runtime mesh/material/physics creation, unit conversion, LOD | Low; do not import assets |

---

## 3. Disabled, incomplete, or contradictory Lua logic

| # | Finding | Evidence | Why it matters |
|---|---|---|---|
| D1 | Airlock interlock body is commented out | `EGDataItems.lua:353-403` | The rules are intent, not confirmed runtime; do not cite as working |
| D2 | AI Travel transitions are commented out | `EGBehaviorTravel.lua:116-176` | Travel is a single initial order, not a working multi-state behaviour |
| D3 | AI Orbit transitions are commented out | `EGBehaviorOrbit.lua:95-117` | Same |
| D4 | AI Follow gear-copy is commented out | `EGBehaviorFollow.lua:50-61` | Followers do not match leader gear |
| D5 | Investigate `LOOKAT` calls `error()` | `EGBehaviorInvestigate.lua:67-74` | The behaviour is a stub and may crash if used |
| D6 | Combat has unreachable `CLOSE`/`REVERSE`/`LOOKAT` paths | `EGBehaviorCombat.lua:105-106`; `EGBehaviorInvestigate.lua:67-74` | Do not treat every `EnterState` branch as reachable |
| D7 | `Combat.CheckReverse` always returns false | `EGBehaviorCombat.lua:437-439` | REVERSE state is effectively unused |
| D8 | `EGVehicle:Encode` child-list loop uses `[childCount]` instead of `[i]` | `EGVehicle.lua:240-247` | Save format has a bug; do not copy |
| D9 | `Encode` stores `FaceVector` from `TurnVector` | `EGVehicle.lua:255-262` | Same; decode fields are asymmetric |
| D10 | `EGGetSaveFiles` appends undefined `data` | `EGUtility.lua:390` | Utility is broken/unreferenced |
| D11 | `EGCharacterActor` `ChildrenList` is commented in `Encode` but live in `Load` | `EGCharacterActor.lua:591-665` | Old saves can contain data new saves never write |
| D12 | `EGPlanet.Load` reads `DebrisSaved`/`EnemiesSaved` positions never written by `Encode` | `EGPlanet.lua:689-767` | Legacy format asymmetry |
| D13 | `EGInterior` fire encode/decode is commented; stream reads and discards | `EGInterior.lua:41-89` | Fire is not persistent |
| D14 | `EGRoom` has no serialization | `EGRoom.lua:16-21` | Room state is engine-owned or lost |
| D15 | `EGMenuSystem.lua` is entirely commented | `EGMenuSystem.lua:3-400` | It is a reference implementation, not live code |
| D16 | `PlanetDef` is defined in both `EGPlanet.lua` and `RenderMain.lua` | `EGPlanet.lua:869-871`; `Render/RenderMain.lua:50-52` | Load order determines which wins; Render may be tooling-only |
| D17 | `ScienceTank.Tages` typo | `EGDataDecorationGen.lua:401` | Science tank tags are dropped; placement may fail |
| D18 | Several `Generation.*` classes have empty `Tags` but are requested by grammar | `EGDataDecorationGen.lua:514`; `XenoBuildingDecorationProductions.rsl:20-25` | Decoration resolution is inconsistent |
| D19 | `EGRandom:GetRandomDebrisID` is described in-source as a "garbage algorithm" | `EGPlanet.lua:181-205` | Do not use as a model for weighted selection |
| D20 | `EGPlanet:GetLocalToGeo` has a `z + z` bug instead of `z*z` | `EGPlanet.lua:452-455` | Altitude/geo conversion can be wrong; do not copy |
| D21 | `EGVehicle:FireWeapon` body is entirely commented out | `EGVehicle.lua:1660-1736` | Ship weapons are engine-driven; do not treat the Lua as a working firing pipeline |
| D22 | Robot bodies are seeded from `self.Seed` but `Init` re-randomizes `Seed` | `EGDataCharacterRobot.lua:21,104` | Robot body generation is not reproducible across sessions |
| D23 | Xeno body parts use global `math.random` | `EGXenoBody.lua:20-28` | Character assembly is not deterministic for co-op |
| D24 | Projectile team logic is hardcoded player-vs-not-player | `EGProjectile.lua:106-112` | No real teams/factions; co-op friendly fire would be wrong |
| D25 | `Generation.Loot` / `Generation.RewardLoot` are referenced but undefined in Lua | `EGDataItems.lua:758,1467` | Engine-side/unknown; do not assume a readable loot grammar |
| D26 | `Items.ShipLight` / `Items.PlayerLight` have no model `Path` | `EGDataItems.lua:1132,1160` | They are invisible logic entities; not a general item pattern |

**Policy:** if a later task depends on one of these, re-read the file and decide whether the code is reachable. Do not “fix” Rodina logic in the reference library; describe it.

---

## 4. Binary and opaque formats

| # | Format | Known | Unknown | Resolution |
|---|---|---|---|---|
| B1 | `DefaultMap.egi` | string table, key names, room/item names, approximate record start | full schema, field widths, coordinate encoding, writer version | engine writer/source or a legitimate spec; do not guess |
| B2 | `.egu` music | 24 files, high entropy, no magic, names match table | codec, encryption, channels, loop metadata, streaming | engine audio code or official asset release |
| B3 | `.egs` shader cache | uint32 length + `DXBC`; `RDEF` names; permutation tokens | `SHEX` bytecode, exact macro mapping, cache invalidation | DXBC disassembler (build tool) or engine source; not attempted |
| B4 | `.spritefont` | binary `DXTKfont`; `MakeSpriteFont.exe` present | glyph table schema, atlas format | DirectXTK documentation; low value |
| B5 | `.egs` savegames | version 38; field order from `Load`; two protocols | container header, compression, checksums, entity graph | a save sample + engine reader |
| B6 | `.egm` versions | token vocabulary, exporter v20, 6 versions shipped | semantic differences 0/1/2/5/16/20 | diff many files + engine loader; low value (do not import) |
| B7 | `Rodina.exe`/DLLs | strings, imports, shader token blob | all runtime logic | out of scope; not disassembled |

**No binary was reverse-engineered by trial and error.** This is deliberate: guessing a proprietary format produces unreliable documentation and risks false confidence.

---

## 5. Gameplay behaviour that cannot be confirmed statically

| # | Question | What the source suggests | Why unresolved |
|---|---|---|---|
| G1 | Does the airlock actually prevent both doors opening? | Intended rules exist but are commented out | Engine may enforce; no readable code |
| G2 | Does the `AirPressure` field update at runtime? | Only assigned in disabled Lua; menu reads it | Engine may write it; no evidence |
| G3 | Is there vacuum damage? | No Lua rule; only decompression force | Engine may apply; unknown |
| G4 | What happens if the ship takes off with someone outside? | No Lua guard; outside actor is not parented to ship | Consequence inferred from parenting, not observed |
| G5 | What happens if someone is in the airlock when it cycles? | Lua checks open factors only; no occupancy | Engine may check; unknown |
| G6 | Is the pilot visually seated at the station? | `PilotStation.OnGrab` does not call `ForceSitInChair`; `PilotChair` is separate | Engine camera/character placement unknown |
| G7 | Does first-person pilot place the camera at the player's eye or a station marker? | `EGPlayer.CameraOffset = (0,0,1.65)`; `PlayerOrientation` saved | Engine camera composition unknown |
| G8 | Do AI Travel ships ever change gear/phase? | Transition `Update` commented; base Gear 2 | Engine mover may still satisfy the order; no evidence of Lua phase changes |
| G9 | Does Follow keep formation under acceleration? | Formation offset is the current relative position; `Update` commented | Engine mover behaviour unknown |
| G10 | Does Investigate ever run without error? | `LOOKAT` calls `error()` | Maybe unreachable in normal play; unknown |
| G11 | Does the ship auto-close the outer airlock on takeoff? | Disabled Lua intended it; no engine evidence | Unknown |
| G12 | Does the walkway animate to terrain, or only rotate? | `EG_MOTION_ANIMATED_WALKWAY` + 32.4 m extent; engine motion type | Motion implementation unknown |
| G13 | Is there a real landing snap/assist? | No Lua; contact-relative check only | Engine collision may add behaviour; unknown |
| G14 | Does the player character take damage in vacuum? | No Lua rule | Engine component may apply; unknown |
| G15 | Are there factions/teams beyond player vs xeno? | `IsPlayerControlled` checks; `IsEnemy` flag | No faction system visible; likely binary |
| G16 | Do NPC ships use the same `PilotInterface` in practice? | Code fills it, but AI motor authority may be the mover | `ApplyMovement` is called for high-process AI; `DesiredVelocity` used in low process; exact split unknown |

---

## 6. Questions about specific numbers and conventions

| # | Question | Current interpretation | Risk |
|---|---|---|---|
| N1 | What is the interior cell size in metres? | `.egi` header has six numbers; tilesets are 2×3/3×3 model grids; no Lua constant | Medium; do not claim Starfall's 4 m matches Rodina |
| N2 | What do the `.egi` per-cell fields mean? | Observed order: x,y,z,height,wall?,tileset,a,b | High; several fields undocumented |
| N3 | What does `TerrainLODMult`/`Exp` actually control? | Engine-side; values vary 0.15–1000 | Medium; do not map directly to Starfall LOD |
| N4 | What is the exact `EGRandom` algorithm? | Engine-provided; usage only | High for “same layout” claims; do not promise |
| N5 | What does `priority` mean in EGSL? | Specificity ladder inferred; no definition | High for grammar reimplementation |
| N6 | Which `let` predicates are conditions vs assertions? | No syntax distinction; `IsXenoMine` is both | High for grammar reimplementation |
| N7 | What is `IsPathConnection(room, edge)`? | 21 uses, no definition | Medium |
| N8 | What does the second `SetPlayerControlled` bool mean? | Inferred `(isCamera, isControl)` | Medium; affects camera/pilot reasoning |
| N9 | What is the ship's collision shape for AI ships? | `Basis` mesh + `ShapeType = "Mesh"` for player; AI values present | Low; do not import |
| N10 | Is the light count 15 or 200? | `Lights[200]` cbuffer; rendering notes infer 15 selected | Low |
| N11 | What is the exact atmosphere transmission model? | Analytic angular ramps + exp2 fog; 10-sample terminator | Low/medium; documented as non-physical |
| N12 | Is the terminator per-vertex? | `standard.h` computes lighting in VS under `VERTLIT` | Medium; affects visual fidelity expectations |

---

## 7. Subsystems that received only partial or delegated inspection

The library covers all major subsystems, but not every line of every file. These are the largest remaining unread/partially read areas:

| File(s) | Size | What we have | What remains |
|---|---|---|---|
| `Scripts/Data/EGEditorData.lua` | 11,143 lines | Persistence profiles, physics effects, some terrain data | Full item/room/tileset/editor tables; not needed for Starfall core, but could refine POI/interior data |
| `EGDataParticles.lua` | 4,973 lines | Schema and categories via item/particles agent | Every effect definition; not needed |
| `EGMenuHUD.lua` | 1,756 lines | HUD architecture, modes, channels | Every widget/offset; not needed |
| `EGMenuShipLayout.lua` | 1,176 lines | Editor modes, save/load delegation | Full editing semantics; not needed |
| `EGMenuOptions.lua` | 1,030 lines | Option list and defaults via agent | Every row/help text; not needed |
| `EGDataItems.lua` | 2,079 lines | Interactive items, doors, seats, airlock, resources | All item classes/fields; items agent covers |
| `EGDataWeapons.lua` | 993 lines | Weapon schema and examples | Every weapon/projectile; items agent covers |
| `EGDataProgress.lua` | 1,153 lines | Stages, AddDebris, story gating | Every stage transition; low value for Starfall |
| `EGSceneEditor.lua` | 1,153 lines | Interior map save/load, room APIs | Full editor internals; low value |
| `Render/MenuGen.*` | ~1,700 lines | Menu texture generation concept | Every pass; low value |
| `Shaders/*` | 72 sources | Terrain/atmosphere/planet/lighting/post | Some effect shaders; rendering agent covers |
| `Data/Documents/*` | 162 files | Format and sample | Narrative content; proprietary, not needed |
| `Data/Models/*` | 546 files | Format and sample | Per-model breakdown; not needed |

These are **not** claimed as fully inspected. The inventory (`01`) marks inspection status.

---

## 8. Things that would change the conclusions

If any of these become available, re-verify the relevant findings:

1. **Engine source or a debug build** — would resolve E1–E12, G1–G14, N1–N8.
2. **A savegame sample** — would confirm the version-38 container and entity graph.
3. **A second Rodina version** — would show whether the disabled AI/airlock/interlock code is intentional or a regression.
4. **Official modding docs** — would clarify `.egm`/`.egi`/`.rsl` formats and licence.
5. **A recorded play session** — would answer the behavioural questions without running the game in this environment (but do not execute the game here).
6. **The Starfall project owner’s intent** — co-op scale (2 players vs 8), target planet count, whether ship interiors are hand-authored or procedural. These change the priority order in `08`.

---

## 9. Questions that are deliberately out of scope

- Cracking, DRM, Steam integration, registration, demo expiry.
- Network protocol reverse engineering (Rodina has none).
- Binary disassembly of `Rodina.exe`/DLLs.
- Reusing or converting proprietary assets.
- Emulating Rodina’s exact flight/terrain feel.

The goal is **independent Starfall improvements informed by concepts**, not a Rodina clone.

---

## 10. Progress and coverage summary

| Metric | Value |
|---|---|
| Files in source tree | 2,282 |
| Total size | ~250 MB (244 MiB) |
| Lua scripts | 161 (2.3 MB) |
| Lua class definitions | 439 |
| `.rsl` grammar files | 10 (~3,625 lines) |
| Shader sources read | 72 `.fx`/`.h` (plus 1,079 `.egs` headers) |
| Models inventoried | 546 `.egm` (versions 0/1/2/5/16/20) |
| Interior maps inventoried | 11 `.egi` (v1/v14–17/binary) |
| Documents inventoried | 162 `.txt` |
| Audio inventoried | 62 `.wav`, 24 `.egu` |
| Major subsystems covered | 8: flight/piloting, interiors/airlocks, planets/terrain, procedural content, AI, formats/assets, persistence, UI/audio |
| Files fully read | Core flight/vehicle, planet, interior, proxy, persistence, grammar, UI/audio and shader analyses; exact count not separately tracked; see `01` inspection table |
| Explicit gaps | Engine-side systems (E1–E12), binary formats (B1–B7), disabled logic (D1–D26), behavioural unknowns (G1–G16) |

This is a **broad but not exhaustive** inspection. It is sufficient for Starfall’s current scope; it is not a complete reverse engineering of Rodina.
