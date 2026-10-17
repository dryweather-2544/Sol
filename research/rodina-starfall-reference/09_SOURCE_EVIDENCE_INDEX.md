# 09 — Source Evidence Index

**How to use this file:** this is the citation backbone for the whole library. Each row maps a finding to a concrete source location and a confidence level. Use it when you need to verify a claim, find the exact function to read, or decide whether a statement is safe to act on.

**Source root:** `/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/`
**Version:** Rodina 1.6.2 (script save version 38).
**Line numbers** are 1-based for the shipped files. They can drift if files are edited; the function/class names are the stable anchors.

**Confidence:**
- `C` — directly confirmed in readable source (text, data, or shader).
- `I` — inferred from multiple call sites or API shape; engine implementation not visible.
- `U` — unverified/engine-private.
- `A` — confirmed absence (searched and not found).

---

## 1. Core runtime and scripting

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| CORE-01 | Custom Lua class system with prototype inheritance | `Scripts/EGCore.lua:35-76` | C | 01, 07 |
| CORE-02 | Instances call `Init` super-first | `Scripts/EGCore.lua:79-102` | C | 01, 07 |
| CORE-03 | Data scripts loaded through `setfenv` | `Scripts/EGCore.lua:255-268` | C | 07 |
| CORE-04 | Optional bytecode cache writes `<script>.egs` via `string.dump` | `Scripts/EGCore.lua:398-476` (write at 430-445) | C | 07 |
| CORE-05 | `EGSaveLuaDataFile` writes via temp + rename | `Scripts/EGCore.lua:271-293` | C | 07 |
| CORE-06 | `EGGetSaveFiles` appends undefined global `data` (bug) | `Scripts/EGUtility.lua:382-400` (line 390) | C | 10 |
| CORE-07 | Game units: AU = 7.5e9 m, SunRadius = 7e8 m | `Scripts/EGConstants.lua:4-5` | C | 04 |
| CORE-08 | Savegame version 38; prior milestone versions 5/26/36 | `Scripts/Gameplay/EGGame.lua:5-9` | C | 02, 09 |
| CORE-09 | 439 `EGMakeClass` sites across Lua | extraction over 161 `.lua` | C | 01, 07 |

---

## 2. Flight, piloting, and cameras

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| FLY-01 | `PilotInterface` fields are gear, move, moveLock, face, turn, clutch, lockLinear, desiredVelocity | `Scripts/Gameplay/EGBehavior.lua:57-83`; `Scripts/Gameplay/EGVehicle.lua:594-620` | C | 02 |
| FLY-02 | AI fills the interface from the engine mover | `Scripts/Gameplay/EGBehavior.lua:68-82` | C | 02, 06 |
| FLY-03 | Player fills the same interface from `MOVE_SHIP`/`LOOK_SHIP` | `Scripts/Gameplay/EGBehaviorPlayer.lua:206-237` | C | 02 |
| FLY-04 | `ApplyMovement` is the single consumer | `Scripts/Gameplay/EGVehicle.lua:594-620` | C | 02 |
| FLY-05 | Movement uses relative time and gear-dependent speed | `Scripts/Gameplay/EGVehicle.lua:1390-1568` | C | 02 |
| FLY-06 | Gear 4 (Limnal) forces forward velocity `(0, MoveSpeed, 0)` | `Scripts/Gameplay/EGVehicle.lua:1437-1441` | C | 02 |
| FLY-07 | Drag applies when speed > `DragSpeed` | `Scripts/Gameplay/EGVehicle.lua:1471-1477` | C | 02 |
| FLY-08 | Per-axis `MoveStrengths` scale lateral/vertical input unless braking | `Scripts/Gameplay/EGVehicle.lua:1482-1492` | C | 02 |
| FLY-09 | `MoveLock` can force exact target velocity | `Scripts/Gameplay/EGVehicle.lua:1508-1517` | C | 02 |
| FLY-10 | Limnal atmosphere collision sweep sphere-tests atmosphere radius | `Scripts/Gameplay/EGVehicle.lua:1638-1657` | C | 02, 04 |
| FLY-11 | Gravity added as local acceleration scaled by 9.8*3.5 | `Scripts/Gameplay/EGVehicle.lua:1548-1554`; constant at `:8` | C | 02, 04 |
| FLY-12 | Gear table for player ship (1=100, 2=500, 3=5–10k, 4=30k) | `Scripts/DataGameplay/EGDataShipPlayer.lua:131-233` | C | 02 |
| FLY-13 | Gear 4 requires Diaconium and Limnal viability | `Scripts/DataGameplay/EGDataShipPlayer.lua:52-81` | C | 02 |
| FLY-14 | Cruise relative-time power law uses CruiseExponent/Mult/Max | `Scripts/DataGameplay/EGDataShipPlayer.lua:180-195`; planet defaults `EGDataPlanets.lua:38-40` | C | 02, 04 |
| FLY-15 | Ship starts piloting via `StartPilotingVehicle` | `Scripts/Gameplay/EGGame.lua:237-262` | C | 02 |
| FLY-16 | Player actor persists and is parented to interior | `Scripts/Gameplay/EGGame.lua:315-350` (parent at 335-341) | C | 02, 03 |
| FLY-17 | Control/camera flags split between vehicle and player | `Scripts/Gameplay/EGGame.lua:250,258,280-284` | I (strong) | 02 |
| FLY-18 | Cancel piloting via `OPEN INVENTORY` | `Scripts/Gameplay/EGGame.lua:875-887` | C | 02 |
| FLY-19 | Stop piloting restores player control/physics | `Scripts/Gameplay/EGGame.lua:294-312` | C | 02 |
| FLY-20 | First/third toggle via `SwitchPilotFirstPerson` | `Scripts/Gameplay/EGGame.lua:266-291` | C | 02 |
| FLY-21 | Camera follow distance/angle/stiffness defaults 200/10/5 | `Scripts/Gameplay/EGVehicle.lua:40-43`; `EGDataShipPlayer.lua:344-348` | C | 02 |
| FLY-22 | FOV/chase warp values 200→125, angle 10→15, FOV +30 | `Scripts/DataGameplay/EGDataShipPlayer.lua:315-318` | C | 02 |
| FLY-23 | Player eye offset (0,0,1.65) | `Scripts/Gameplay/EGPlayer.lua:5` | C | 02 |
| FLY-24 | First-person detection requires player == camera actor | `Scripts/Gameplay/EGVehicle.lua:2217-2222` | C | 02 |
| FLY-25 | HUD chooses Ship mode by control actor, not camera | `Scripts/Gameplay/EGMenuHUD.lua:173-178` | C | 02 |
| FLY-26 | Landing is contact-relative + speed < 4 | `Scripts/Gameplay/EGVehicle.lua:736-737`, `:2009-2047` | C | 02, 04 |
| FLY-27 | Atmosphere states and 4 s entry timer | `Scripts/Gameplay/EGVehicle.lua:5`, `:977-1037` | C | 02, 04 |
| FLY-28 | Auto-level is roll-only, gravity-scaled | `Scripts/Gameplay/EGVehicle.lua:1152-1198` | C | 02, 04 |
| FLY-29 | Player ship uses mesh hull for collision | `Scripts/DataGameplay/EGDataShipPlayer.lua:26-38` | C | 02 |
| FLY-30 | Impact damage formula from incidence/speed/difficulty | `Scripts/Gameplay/EGVehicle.lua:759-789` | C | 02 |
| FLY-31 | Walkway spawns <75 speed², removes >500 or piloted | `Scripts/DataGameplay/EGDataShipPlayer.lua:452-485` | C | 02, 03 |
| FLY-32 | Player-ship gear 1 near Vanguard forces drag 0 / decel .5 | `Scripts/DataGameplay/EGDataShipPlayer.lua:142-147` | C | 02 |
| FLY-33 | Limnal exit autosaves "Exits Limnal" | `Scripts/Gameplay/EGVehicle.lua:899-903` | C | 02, 09 |

---

## 3. Interiors, airlocks, and seats

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| INT-01 | Interior is a vehicle-owned entity; player parented to it | `Scripts/Gameplay/EGGame.lua:333-342` | C | 03 |
| INT-02 | Player orientation is saved interior-local | `Scripts/Gameplay/EGVehicle.lua:237,277-282,1790-1805` | C | 03 |
| INT-03 | Interior root transform exposed for walkway | `Scripts/Gameplay/EGVehicle.lua` / `EGDataShipPlayer.lua:470-474` | C | 03 |
| INT-04 | Interior components are `InteriorFire` and `RoomPressure` | `Scripts/Gameplay/EGInterior.lua:7` | C | 03 |
| INT-05 | Room pressure/force delegated to engine | `Scripts/Gameplay/EGRoom.lua:28-35` | C | 03 |
| INT-06 | Pressure rates 10 and .33 are declared but unused | `Scripts/Gameplay/EGRoom.lua:8-9` (no references) | C | 03 |
| INT-07 | Decompression force only when `AllDoorsOpen` | `Scripts/Gameplay/EGCharacterActor.lua:350-379` | C | 03 |
| INT-08 | `AllDoorsOpen` saved and toggled by Operations | `Scripts/Gameplay/EGInterior.lua:35,48,59,85-87,174-180`; `EGMenuOperations.lua:240-257,384-386` | C | 03 |
| INT-09 | Airlock computer fields Close/OpenIn/OpenOut | `Scripts/DataGameplay/EGDataItems.lua:346-348` | C | 03 |
| INT-10 | Airlock menu writes those flags | `Scripts/Gameplay/EGMenuAirlock.lua:167-190` | C | 03 |
| INT-11 | Airlock interlock body is commented out | `Scripts/DataGameplay/EGDataItems.lua:353-403` (delimiters 354/401) | C | 03, 10 |
| INT-12 | Intended rules: inner opens only after outer closed + pressure > .99 | same block, lines 388-398 | C (intent) | 03 |
| INT-13 | Piloting forces outer door closed (intended) | `Scripts/DataGameplay/EGDataItems.lua:379-382` | C (intent) | 03 |
| INT-14 | Interior publishes exterior-door-closed flag (disabled) | `Scripts/DataGameplay/EGDataItems.lua:366` | C (intent) | 03 |
| INT-15 | Engine exposes `GetExteriorDoorsClosed` | `Scripts/DataGameplay/EGDataShipPlayer.lua:465` | C | 03 |
| INT-16 | PilotStation checks dead/all-doors, starts piloting, autosaves | `Scripts/DataGameplay/EGDataItems.lua:495-513` | C | 02, 03 |
| INT-17 | Remote pilot via airlock sets AllowFirstPersonPilot=false | `Scripts/Gameplay/EGMenuAirlock.lua:198-232` | C | 02, 03 |
| INT-18 | Chairs are engine-seated via `ForceSitInChair`/`GetCurrentChair` | `Scripts/Gameplay/EGGravBike.lua:58-99` | C | 03 |
| INT-19 | PilotChair is not referenced by piloting code | absence in pilot flow; `EGDataItems.lua:102-110` | A | 03 |
| INT-20 | Door animation uses named parts Left/MidLeft/MidRight/Right | `Scripts/DataGameplay/EGDataItems.lua:594-600` | C | 03, 07 |
| INT-21 | Airlock door animation uses part `DoorAirlock` | `Scripts/DataGameplay/EGDataItems.lua:633-636` | C | 03, 07 |
| INT-22 | Walkway has special animated motion type and 32.4 m extent | `Scripts/DataGameplay/EGDataItems.lua:1148-1157` | C | 03 |
| INT-23 | Entrance bounds generated from entrance `.egi` | `Scripts/DataGameplay/EGDataItems.lua:2076-2079` | C | 03 |
| INT-24 | Ship entrance map is `Airlock.egi` | `Scripts/DataGameplay/EGDataShipPlayer.lua:9` | C | 03 |
| INT-25 | Fire damage/reaction and light override | `Scripts/Gameplay/EGInterior.lua:105-143` | C | 03 |
| INT-26 | Fire state not saved (commented out) | `Scripts/Gameplay/EGInterior.lua:41-89` | C | 03, 10 |
| INT-27 | Building flatten radii 15/150 default; 100–200/350 per type | `Scripts/Gameplay/EGBuilding.lua:15-23`; `EGDataBuildings.lua:19-120` | C | 03, 04 |
| INT-28 | Tilesets 2×3 or 3×3 model grids | `Scripts/DataGameplay/EGDataTilesets.lua:3-164` | C | 03 |
| INT-29 | `.egi` v1 ASCII grid vs v14–17 structured ASCII vs binary player map | `Data/Interiors/*.egi`; `Data/Models/map*.egi` | C | 03, 07 |
| INT-30 | `DefaultMap.egi` is binary with a readable string table | `Data/Interiors/DefaultMap.egi` (header inspection) | C | 03, 07 |
| INT-31 | Interior edition/save delegated to engine | `Scripts/Gameplay/EGSceneEditor.lua:1003-1010`; `EGMenuShipLayout.lua:1142-1155` | C | 03, 07 |
| INT-32 | Character AI excludes airlock doors from casual opening | `Scripts/Gameplay/EGCharBehaviorWander.lua:251-253,272-274` | C | 03, 06 |
| INT-33 | Vacuum damage is not implemented in Lua | absence; only decompression force | A/U | 03, 10 |

---

## 4. Planets and terrain

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| PLN-01 | 11 `PlanetDef` entries; 5 active in starting scene | `Scripts/DataGameplay/EGDataPlanets.lua`; `EGDataZoricaScene.lua:7-12` | C | 04 |
| PLN-02 | Planet radii 4,000–10,000 km; atmospheres 200 km | `Scripts/DataGameplay/EGDataPlanets.lua` per def | C | 04 |
| PLN-03 | Orbit/rotation driven by time deltas 10 h/30 min | `Scripts/Gameplay/EGSceneSolar.lua:5-7,83-84` | C | 04 |
| PLN-04 | Height/normal bake shaders and cubesphere warp | `Shaders/Planet_Common.h:99-211` | C | 04 |
| PLN-05 | `GetPlanetFeatures` returns base/plateau/mountain/holes | `Shaders/PlanetPerun.h:30-94` | C | 04 |
| PLN-06 | Domain warp + Voronoi + fBm composition | `Shaders/PlanetPerun.h:52-150` | C | 04 |
| PLN-07 | Morena uses hand-coded plate/crack model | `Shaders/PlanetMorena.h:47-130` | C | 04 |
| PLN-08 | Veles uses Voronoi base and fixed amplitudes | `Shaders/PlanetVeles.h:42,108-109` | C | 04 |
| PLN-09 | `GenerationVars` indices 1–17/100–112 map to shader constants | `Shaders/PlanetPerun.h`; `EGDataPlanets.lua:165-203` | C | 04 |
| PLN-10 | Six-gate terrain material blend | `Shaders/RodinaTerrain.fx:40-75` | C | 04 |
| PLN-11 | Distance band widening 1→4 over 1–100 km | `Shaders/RodinaTerrain.fx:45` | C | 04 |
| PLN-12 | Distance constants 500/5k/50k/2M m; 50/750/750/18,000 km | `Shaders/RodinaTerrain.fx:21-37` | C | 04 |
| PLN-13 | LOD values per planet (.15–1000, exp 3/4) | `EGDataPlanets.lua:143-150,264-271,424-427,533-536,709-712,974-978,1235-1239` | C | 04 |
| PLN-14 | Height query `GetHeightAtLocalPos` used once | `Scripts/Gameplay/EGPlanet.lua:387` | C | 04 |
| PLN-15 | `GetSurfacePosition` returns `EGPreciseVector` | `Scripts/Gameplay/EGProxyItem.lua:104,197`; `EGGame.lua:826` | C | 04 |
| PLN-16 | Nested worldspace chain via `GetParentWorldspace` | `Scripts/Gameplay/EGWorldObject.lua:285-293` | C | 04 |
| PLN-17 | Gravity = `SurfaceGravity / ratio²` toward centre | `Scripts/Gameplay/EGPlanet.lua:150-158` | C | 04 |
| PLN-18 | Character ground/air constants (GroundGravity −250, AirGravity −40) | `Scripts/Gameplay/EGPlayer.lua:31-74`; `EGDataCharacterXeno.lua:70-90` | C | 04 |
| PLN-19 | Planet atmosphere pressure is a separate altitude remap | `Scripts/Gameplay/EGPlanet.lua:140-147` | C | 04 |
| PLN-20 | Atmosphere shader is analytic, not a scattering integral | `Shaders/_atmosphere.h:1-379` | C | 04 |
| PLN-21 | Atmosphere horizon band = 0.66 rad | `Shaders/_atmosphere.h:41` | C | 04 |
| PLN-22 | Three atmosphere passes scatter/filter/blur | `Shaders/RodinaAtmosphere*.fx` | C | 04 |
| PLN-23 | No shadows/tonemap/gamma/exposure in shader sources | all 72 sources | C (absence) | 04 |
| PLN-24 | Per-pixel logarithmic depth used in 459/1079 permutations | `standard.h:262-277`; cache names | C | 04 |
| PLN-25 | Asteroid generation deterministic from seed/bucket | `Scripts/DataGameplay/EGDataPlanets.lua:1295-1342`; `EGAsteroidBelt.lua:18-30` | C | 04, 05 |
| PLN-26 | Terrain mesh LOD/collision is engine-side | no mesh code in Lua/shader | U | 04, 10 |

---

## 5. Procedural content and persistence

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| PRC-01 | Planet active within `Radius * 10` | `Scripts/Gameplay/EGPlanet.lua:12,63` | C | 05 |
| PRC-02 | Debris capacity 15 default; one proxy per update | `Scripts/Gameplay/EGPlanet.lua:19,256-291` | C | 05 |
| PRC-03 | Enemy capacity 150 default; one group per update | `Scripts/Gameplay/EGPlanet.lua:16,294-366` | C | 05 |
| PRC-04 | Debris location/list seeded by `EGRandom(seed,index)` | `Scripts/Gameplay/EGPlanet.lua:208-224` | C | 05 |
| PRC-05 | Proxy spawn 10 km / finalize 3.5 km / discover 100 m | `Scripts/Gameplay/EGProxyItem.lua:68,74,78` | C | 05 |
| PRC-06 | Detailed debris offsets use `math.random` | `Scripts/Gameplay/EGProxyItem.lua:112-115`; `EGUtility.lua:50-56` | C | 05 |
| PRC-07 | Proxy saves ItemList/flags/Spawned IDs | `Scripts/Gameplay/EGProxyItem.lua:244-311` | C | 05, 09 |
| PRC-08 | Proxy discovery is per-instance boolean | `Scripts/Gameplay/EGProxyItem.lua:18,78-80,249` | C | 05 |
| PRC-09 | Player discovery keyed by ClassName | `Scripts/Gameplay/EGPlayerInfo.lua:128-162` | C | 05, 10 |
| PRC-10 | Building seeds are random at creation and persisted | `Scripts/Gameplay/EGBuilding.lua:28,107-123` | C | 05 |
| PRC-11 | Buildings placed with fixed seeds and `RandomCube` positions | `Scripts/DataGameplay/EGDataPlanets.lua:335-350,447-465` | C | 05 |
| PRC-12 | Asteroid seed uses `GetChildSeed(index)` | `Scripts/Gameplay/EGAsteroidBelt.lua:18-30` | C | 05 |
| PRC-13 | `EGRandom` API exists only as engine calls | 29 call sites; no definition | C/U | 05 |
| PRC-14 | EGSL grammar: 10 files, ~338 productions, no recursion | `Scripts/*.rsl`; `ProductionTestCore.rsl:15` | C | 05 |
| PRC-15 | Overloading by name+arity | `XenoMineProductions.rsl:127,138,149` | C | 05 |
| PRC-16 | `let` is both precondition and assertion | `XenoMineProductions.rsl:20` vs `:288` | C (syntax), U (semantics) | 05, 10 |
| PRC-17 | `priority` semantics undefined | all `.rsl`; no Lua/docs | U | 05, 10 |
| PRC-18 | No Lua `.rsl` loader; `ProductionName` is the bridge | no `rsl`/`EGSL` strings in Lua; `EGDataInteriorGen.lua:5-66` | C/I | 05, 07 |
| PRC-19 | Decoration placement uses Parent/Slot/Offset/Weight/Avoid | `Scripts/DataGeneration/EGDataDecorationGen.lua:3-566` | C | 05 |
| PRC-20 | `ScienceTank.Tages` typo drops tags | `EGDataDecorationGen.lua:401` | C | 05, 10 |
| PRC-21 | Save is keyed `Encode/Decode` plus versioned `Load` | `Scripts/Gameplay/GameplayMain.lua:57-70`; all Encode/Load classes | C | 05, 09 |
| PRC-22 | Savegame version 38; real stream gates include 4,7,17,21,22,23,28,29,31,33,35 (no >=38 stream) | `_work/persistence_notes.md`; `EGGame.lua:501` | C | 05, 09 |
| PRC-23 | Autosave contexts: pilot, atmo entry, limnal exit, combat, interior, edit | `EGVehicle.lua:899-903`; `EGGame.lua:406-428`; `EGMenuAirlock.lua:232`; `EGDataItems.lua:511`; `EGSceneSolar.lua:315-321` | C | 05, 09 |
| PRC-24 | Planet saves IDs/counts; `DebrisSaved` positions read but never written | `Scripts/Gameplay/EGPlanet.lua:689-767` | C | 05, 10 |
| PRC-25 | Persistence profiles define load scope/storage | `Scripts/Data/EGEditorData.lua:617-780` | C | 05, 09 |
| PRC-26 | `.egs` is used for saves, bytecode, and shader cache | `EGGame.lua:420`; `EGCore.lua:430`; `Shaders/ShaderCache` | C | 07 |

---

## 6. AI and navigation

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| AI-01 | One active behaviour, switched by `GetBehaviorFunc` | `Scripts/Gameplay/EGActor.lua:57-93`; `EGPlan.lua:5-65` | C | 06 |
| AI-02 | Behaviour selection order: Combat > Follow > Travel | `Scripts/Gameplay/EGPlan.lua:5-34` | C | 06 |
| AI-03 | Sensors: avoidance 200 @ +300, proximity 200, attention 1000 | `Scripts/Gameplay/EGBehavior.lua:62-64` | C | 06 |
| AI-04 | Combat FSM states and transitions | `Scripts/Gameplay/EGBehaviorCombat.lua:57-467` | C | 06 |
| AI-05 | Combat fires missiles >4 km, guns in front/pinned | `Scripts/Gameplay/EGBehaviorCombat.lua:253-262` | C | 06 |
| AI-06 | Combat target lock/fear/immune logic | `Scripts/Gameplay/EGBehaviorCombat.lua:216-234,419-434` | C | 06 |
| AI-07 | Combat sphere uses ORBIT_STRAFE 3–5 km | `Scripts/Gameplay/EGBehaviorCombatSphere.lua:30-50` | C | 06 |
| AI-08 | Battleship uses AIM_FIRE_MISSILES/AIM | `Scripts/Gameplay/EGBehaviorCombatBattleship.lua:20-58` | C | 06 |
| AI-09 | Travel `Update` body commented out | `Scripts/Gameplay/EGBehaviorTravel.lua:116-176` | C | 06 |
| AI-10 | Orbit `Update` body commented out | `Scripts/Gameplay/EGBehaviorOrbit.lua:95-117` | C | 06 |
| AI-11 | Follow `Update` body commented out | `Scripts/Gameplay/EGBehaviorFollow.lua:50-61` | C | 06 |
| AI-12 | Investigate `LOOKAT` calls `error()` | `Scripts/Gameplay/EGBehaviorInvestigate.lua:67-74` | C | 06 |
| AI-13 | Investigate approach offset/radii | `Scripts/Gameplay/EGBehaviorInvestigate.lua:51-66` | C | 06 |
| AI-14 | Character AI uses `SetMoveState`, not `PilotInterface` | `Scripts/Gameplay/EGCharBehaviorWander.lua:114`; `EGCharBehaviorXenoCombat.lua:58-128` | C | 06 |
| AI-15 | Character states and door/room logic | `Scripts/Gameplay/EGCharBehaviorWander.lua:187-335`; `EGCharBehaviorXenoCombat.lua:284-409` | C | 06 |
| AI-16 | Xeno random attack/dodge probabilities | `Scripts/Gameplay/EGCharBehaviorXenoCombat.lua:306-322` | C | 06 |
| AI-17 | Ship group is flat set + leader + shared target | `Scripts/Gameplay/EGShipGroup.lua:3-52` | C | 06 |
| AI-18 | Leader death destroys group | `Scripts/Gameplay/EGVehicle.lua:194-210` | C | 06 |
| AI-19 | No Lua pathfinding/raycast; engine mover handles navigation | absence; actionMove API | A/U | 06 |

---

## 7. UI, input, audio, options

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| UI-01 | One retained 3D tile class `EGTile`; not IMGUI | `Scripts/Gameplay/EGTile.lua:3,140-307` | C | 07 |
| UI-02 | `EGMenuSystem.lua` is fully commented out; engine owns menus | `Scripts/Gameplay/EGMenuSystem.lua:3-400` | C | 03, 07 |
| UI-03 | Menu flags: `MenuMode`, cursor, freeze are separate | `Scripts/Gameplay/EGMenu.lua:5-14`; UI notes §1 | C | 07 |
| UI-04 | HUD is `HUD` + status + equipment menus | `Scripts/Gameplay/EGMenuHUD.lua:15-145`; `EGMenuHUDStatus.lua`; `EGMenuHUDEquipment.lua` | C | 07 |
| UI-05 | HUD mode derives from control actor | `Scripts/Gameplay/EGMenuHUD.lua:173-178,407-443` | C | 02 |
| UI-06 | 54 declared actions with Tap/Hold; compounds per device | `Scripts/DataGameplay/EGDataActionBindings.lua:3-59`; `EGActionBindings.lua:144-269` | C | 08 |
| UI-07 | Audio is declaration-only; 58 `LoadSound` blocks | `Scripts/Gameplay/EGAudio.lua:5-707` | C | 07 |
| UI-08 | Sound `Filename` maps to `Data/Sounds/<path>.wav` | `EGAudio.lua`; `_work/ui_audio_notes.md` §5 | C | 07 |
| UI-09 | 3rd `PlaySound` arg = entity (3D) vs omitted (2D) | ~29 positional / ~25 2D call sites | C (usage), I (semantics) | 07 |
| UI-10 | Music state tables + fade/queue + poll | `EGAudio.lua:709-889`; `EGSceneSolar.lua:160-312` | C | 07 |
| UI-11 | `.egu` music is opaque/high-entropy | 24 files; `file`=data | C | 07 |
| UI-12 | Procedural robot/xeno voice via `PlaySoundKeys` | `EGRobotVoice.lua:13-60`; `EGXenoVoice.lua`; `EGDataCharacterRobot.lua:151` | C | 07 |
| UI-13 | Options defaults vs curated menu; AutosaveTimeLimit=20 | `EGOptions.lua:5-152`; `EGMenuOptions.lua`; `EGGame.lua:409` | C | 08 |
| UI-14 | No subtitle system in Lua | grep `Subtitle` = 0 | A | 10 |
| UI-15 | Difficulty = three 0..1 multipliers, not presets | `EGOptions.lua`; `EGVehicle.lua:1049-1063`; `EGActor.lua:150-154` | C | 07, 08 |

---

## 7.5 Items, weapons, characters, buildings

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| ITM-01 | ~125 item classes; 106 registered as interior entity types | `Scripts/DataGameplay/EGDataItems.lua` (2,079 lines) | C | 07, 08 |
| ITM-02 | Interactivity is duck-typed: item is usable if it defines `OnGrab` | `EGCharacterActor.lua:339-342`; item classes | C | 07 |
| ITM-03 | Two inventory ledgers: spatial grid + count map | `EGPlayerInfo.lua:56-80`; `EGMenuInventory.lua:180-224` | C | 07, 08 |
| ITM-04 | Equipment slots are bare strings HEAD/WEAPON/TOOL/BODY | `EGMenuHUDEquipment.lua:60-62`; `EGMenuQuickSelection.lua:61-71` | C | 07 |
| ITM-05 | No hitscan; all weapons spawn projectiles | `EGWeaponBullet.lua`; `EGWeaponGun.lua:178-190` | C | 07 |
| ITM-06 | Projectile team check is player-vs-not-player, no team field | `EGProjectile.lua:106-112` | C | 07, 08 |
| ITM-07 | Missile targeting is player-centric | `EGWeaponMissile.lua:94-147` | C | 07, 08 |
| ITM-08 | `EGVehicle:FireWeapon` body is commented out | `EGVehicle.lua:1660-1736` | C | 07, 10 |
| ITM-09 | 104 particle materials; name-keyed `AttachParticles` | `EGDataParticles.lua`; `EGDataShipPlayer.lua:358-406` | C | 07 |
| ITM-10 | Modular bodies via `GetModuleEntities`; no per-part hit zones | `EGDataCharacterXeno.lua:38-58`; `EGActor.lua:142-172` | C | 07, 08 |
| ITM-11 | Robot `Seed` re-randomized in `Init`, so bodies are not reproducible | `EGDataCharacterRobot.lua:21,104` | C | 10 |
| ITM-12 | Xeno parts use global `math.random` | `EGXenoBody.lua:20-28` | C | 08, 10 |
| ITM-13 | Loot is a weighted grammar, one nesting level | `EGDataGenerateLoot.lua:3-110`; `EGCharacterActor.lua:112-116` | C | 07 |
| ITM-14 | 7 building classes + 4 shields; seeds random per instance | `EGDataBuildings.lua`; `EGBuilding.lua:26-29` | C | 05, 07 |
| ITM-15 | Building xeno count is derived from live actors, not stored | `EGBuilding.lua:91-104`; `EGGame.lua:124-139` | C | 08 |
| ITM-16 | `Generation.Loot`/`RewardLoot` undefined in Lua | `EGDataItems.lua:758,1467` | U | 10 |
| ITM-17 | Ship/player lights have no model `Path` | `EGDataItems.lua:1132,1160` | C | 10 |

---

## 8. Formats and assets

| ID | Finding | Source | Conf. | Report |
|---|---|---|---|---|
| FMT-01 | 2,282 files, 2282 manifest entries | `99_FILE_MANIFEST.csv` | C | 01, 07 |
| FMT-02 | 546 `.egm`; versions 0/1/2/5/16/20; 351 v5 | header scan | C | 07 |
| FMT-03 | EGG text model structure and named parts | `Ship1.ShipOpen.egm`; `Furniture.DoorRegular.egm`; `EllipticExport.py` | C | 07 |
| FMT-04 | Physics meshes are separate `.egm` files | `Ship1.ShipOpen.Physics.egm`; `EGDataShipPlayer.lua:28` | C | 07 |
| FMT-05 | No skeleton/animation in `.egm`; parts animated by name | `EGDataItems.lua:594-600` | C | 07 |
| FMT-06 | Exporter is Blender 2.91, writes v20, export-only | `Scripts/EllipticExport.py:1-18,358-400` | C | 07 |
| FMT-07 | `.egi` v1 ASCII grid; v14–17 structured; binary player map | `Data/Interiors/*`; `Data/Models/map*.egi` | C | 03, 07 |
| FMT-08 | `.rsl` is plain-text EGSL; engine-interpreted | `Scripts/*.rsl`; no Lua loader | C/I | 05, 07 |
| FMT-09 | `.egs` cache = uint32 + DXBC; all 1,079 | header scan | C | 07 |
| FMT-10 | `.egs` cache filenames encode permutations | `Shaders/ShaderCache/*` | C | 07 |
| FMT-11 | `.egu` music is high-entropy/opaque | `Data/Music/*.egu` | C | 07 |
| FMT-12 | WAV is PCM 16-bit mono 96 kHz (sample) | `Data/Sounds/Missile/explosion_large_01.wav` | C | 07 |
| FMT-13 | `.spritefont` is binary DXTK | `Data/Fonts/FontCache/*.spritefont` | C | 07 |
| FMT-14 | 162 docs are CP1252-ish text with HTML entities | `Data/Documents`; `EGDataDocuments.lua` | C | 07 |
| FMT-15 | Localization CSV is quoted and HTML-escaped | `Data/Localization/Localization.csv` | C | 07 |
| FMT-16 | `.egs` save/bytecode/shader-cache extension collision | `EGCore.lua:430`; `EGGame.lua:420`; `ShaderCache` | C | 07 |

---

## 9. Contradictions and traps (read before trusting earlier notes)

| ID | Issue | Evidence | Consequence |
|---|---|---|---|
| TRAP-01 | Prior summary said `.egi` is plain text; the player ship map is binary | `DefaultMap.egi` header; `file` reports data | Do not build a text-only `.egi` parser |
| TRAP-02 | Prior summary treated Travel/Orbit AI as active; their `Update` bodies are commented | `EGBehaviorTravel.lua:116-176`; `EGBehaviorOrbit.lua:95-117` | Do not model them as working multi-state AI |
| TRAP-03 | Prior summary said airlock interlock is implemented; it is commented out | `EGDataItems.lua:353-403` | Treat runtime interlock as engine-side/unconfirmed |
| TRAP-04 | `.egs` means save, bytecode, and shader cache | `EGGame.lua:420`; `EGCore.lua:430`; `Shaders/ShaderCache` | Never dispatch on extension alone |
| TRAP-05 | `.egm` versions are not a documented schema | 546 headers, 6 versions; exporter writes 20 | Do not assume v5↔v20 differences are trivial |
| TRAP-06 | `EGMenuSystem.lua` looks like a menu implementation but is entirely commented | `EGMenuSystem.lua:3-400` | Do not cite it as live code |
| TRAP-07 | `EGRandom` is engine-side; exact sequence not reproducible | 29 call sites, no definition | Do not promise Rodina-identical layouts |
| TRAP-08 | `priority`/`let` semantics in EGSL are undefined | all `.rsl` | Do not claim a faithful grammar reimplementation |
| TRAP-09 | Discovery by `ClassName` collides for multiple `EGProxyItem`s | `EGPlayerInfo.lua:128-162`; `EGProxyItem.lua` | Use per-instance IDs in Starfall |
| TRAP-10 | Fire state is not saved | `EGInterior.lua:41-89` | Reload is not a full state restore |
| TRAP-11 | `EGPlanet` reads `DebrisSaved` positions it never writes | `EGPlanet.lua:689-767` | Do not copy that asymmetry |
| TRAP-12 | Some files are duplicated class definitions (`PlanetDef` in Gameplay and Render) | `EGPlanet.lua:869-871`; `RenderMain.lua:50-52` | Load order matters; Render may be tooling |

---

## 10. Evidence gaps (what this index cannot cite)

| Gap | Why |
|---|---|
| Engine `SetPlayerControlled` argument semantics | C++ only; inferred from call sites |
| Engine ActionMove navigation/avoidance | C++ only |
| Terrain mesh LOD, collision, height query implementation | C++ only |
| Origin-shift implementation | C++ only; inferred from precision types and shader LOD |
| Room pressure equalisation/leak rates | C++ only; Lua constants dead |
| Airlock runtime interlock | Lua disabled; engine-side unconfirmed |
| `.egu` codec | encrypted/compressed; no magic |
| `.egs` bytecode algorithm | DXBC `SHEX`; not disassembled |
| `DefaultMap.egi` full schema | binary; string table only |
| Savegame sample | none in archive |
| Subtitle/closed-caption system | absent from Lua; engine unknown |
| Multiplayer/networking | Rodina is single-player; no code |

---

## 11. Search recipe

When you need to find a claim:

1. Search `04`/`05`/`06` for the subsystem, then use the evidence ID here.
2. In the source root, use the function/class name from the row, not the line number (lines drift).
3. If a row is marked `I`/`U`, do not upgrade it to `C` without new evidence.
4. If two reports disagree, `TRAP-*` and `10_OPEN_QUESTIONS.md` win until re-verified against source.

Useful `rg` patterns (conceptual; `rg` is not required):

```text
function EGVehicle:ApplyMovement
function EGGame:StartPilotingVehicle
function Items.Airlock:Update
function EGProxyItem:Update
function EGPlanet:CreateDebrisClass
function EGBehaviorCombat:EnterState
function EGCharBehaviorXenoCombat:UpdateState
EGMakeClass( "EGShipPlayer"
System.Interior.RegisterTileset
---[[
```

The `---[[` pattern is especially useful: it finds the disabled AI/interlock blocks that are easy to mistake for live code.
