# 01 — Complete File Inventory

**Source:** Rodina 1.6.2 extracted install at `/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/`
**Archive:** `Rodina.v1.6.2.rar` (saved at `/Users/arielbowyer/.dsh/attachments/v1/files/fb/fba64a7dd90f900e6bb9cccf41e231428c40f45d7bafa659a6e88cf98c67d33e/`).
**Scope:** read-only static inventory. Nothing was executed. The complete 2,282-file manifest with size and category is `99_FILE_MANIFEST.csv`.

## 1. Totals

| Category | Files | Size | Notes |
|---|---:|---:|---|
| Lua gameplay/data/runtime | 160 | ~2.1 MB | 439 class definitions; plain text |
| EGSL grammars `.rsl` | 10 | ~101 KB | engine-interpreted |
| Blender exporter `.py` | 1 | 19 KB | export-only |
| Models `.egm` | 546 | 37.3 MB | EGG text; versions 0/1/2/5/16/20 |
| Legacy maps `.egi` in Models | 3 | 1.1 KB | v1 ASCII |
| Interiors `.egi` | 8 | 169 KB | v1/v14–17 ASCII + one binary |
| Shader sources `.fx`/`.h` | 72 | 336 KB | readable HLSL |
| Compiled shaders `.egs` | 1,079 | 15.4 MB | uint32 + DXBC; reflection readable, bytecode not |
| Textures `.png`/`.jpg`/`.orig` | 89 | 34.0 MB | proprietary art |
| Sounds `.wav` | 62 | 35.7 MB | PCM, proprietary |
| Music `.egu` | 24 | 82.4 MB | opaque/high-entropy |
| Fonts `.ttf`/`.spritefont`/`.exe` | 49 | 3.6 MB | TTFs third-party; spritefonts binary |
| Documents `.txt` | 162 | 0.5 MB | narrative/localization text |
| Document index `.lua` | 1 | 16 KB | `Data/Documents/LP/EGDataDocuments.lua` (outside Scripts) |
| Localization `.csv` | 1 | 32 KB | quoted CSV |
| Engine/binaries `.exe`/`.dll` | 10 | 37.2 MB | not executed/analysed |
| Other (README, URLs, cursor) | 5 | 33 KB | distribution metadata |
| **Total** | **2,282** | **~250 MB (244 MiB)** | |

## 2. Inspection status legend

- **Full** — read end-to-end (or equivalent line-by-line extraction).
- **Partial** — key functions/sections read; not every line.
- **Delegated** — analysed by a focused sub-report (`_work/*.md`); citations spot-checked.
- **Inventory** — counted/path-classified but not read in depth; not used for behavioural claims.

No file is marked Full unless it was actually read. The large data tables (`EGEditorData.lua`, `EGDataParticles.lua`) are intentionally Partial/Delegated; the behavioural conclusions do not depend on exhaustively reading them.

## 3. Script inventory

### 3.1 Entry points, core, and grammars — `Scripts/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `DebrisLootProductions.rsl` | 3.8 KB | EGSL interior grammar | Delegated |
| `EGConstants.lua` | 1.0 KB | Units/constants | Full |
| `EGCore.lua` | 15.2 KB | Core class system | Full |
| `EGUtility.lua` | 14.3 KB | Core math/IO helpers | Full |
| `EllipticExport.py` | 18.8 KB | Blender exporter | Partial |
| `ProductionTest.rsl` | 11.4 KB | EGSL interior grammar | Delegated |
| `ProductionTestCore.rsl` | 17.1 KB | EGSL interior grammar | Delegated |
| `VanguardEnemyProductions.rsl` | 3.1 KB | EGSL interior grammar | Delegated |
| `XenoBuildingDecorationProductions.rsl` | 7.6 KB | EGSL interior grammar | Delegated |
| `XenoBuildingEnemyProductions.rsl` | 11.5 KB | EGSL interior grammar | Delegated |
| `XenoBuildingProductions.rsl` | 20.3 KB | EGSL interior grammar | Delegated |
| `XenoMineDecorationProductions.rsl` | 10.4 KB | EGSL interior grammar | Delegated |
| `XenoMineEnemyProductions.rsl` | 13.4 KB | EGSL interior grammar | Delegated |
| `XenoMineProductions.rsl` | 10.6 KB | EGSL interior grammar | Delegated |

### 3.2 Editor data — `Scripts/Data/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `EGEditorData.lua` | 324.6 KB | Editor/game data tables | Partial |

### 3.3 Gameplay data definitions — `Scripts/DataGameplay/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `EGDataActionBindingKeys.lua` | 8.9 KB | Input/options | Inventory |
| `EGDataActionBindings.lua` | 11.5 KB | Input/options | Partial |
| `EGDataBodyParts.lua` | 13.6 KB | Character/body/voice | Delegated |
| `EGDataBuildings.lua` | 8.5 KB | Buildings/interiors | Delegated |
| `EGDataCharacterRobot.lua` | 8.4 KB | Character/body/voice | Delegated |
| `EGDataCharacterXeno.lua` | 10.8 KB | Character/body/voice | Delegated |
| `EGDataDocuments.lua` | 19.6 KB | UI/menu/documents | Partial |
| `EGDataGenerateDebris.lua` | 2.3 KB | Procedural content | Partial |
| `EGDataGenerateLoot.lua` | 2.2 KB | Procedural content | Partial |
| `EGDataGenerateShips.lua` | 4.4 KB | Procedural content | Partial |
| `EGDataGenerateXenos.lua` | 3.0 KB | Procedural content | Partial |
| `EGDataItems.lua` | 82.6 KB | Items/interactions | Delegated |
| `EGDataPalettes.lua` | 5.1 KB | Palettes/materials | Inventory |
| `EGDataParticles.lua` | 89.1 KB | Combat/weapons/particles | Delegated |
| `EGDataPlanets.lua` | 49.7 KB | Planets/space | Partial |
| `EGDataPowerups.lua` | 0.3 KB | Combat/weapons/particles | Inventory |
| `EGDataProgress.lua` | 35.2 KB | Story/progress persistence | Partial |
| `EGDataShipBattleship.lua` | 6.3 KB | Ship/flight | Full |
| `EGDataShipBomber.lua` | 4.7 KB | Ship/flight | Inventory |
| `EGDataShipFlare.lua` | 4.4 KB | Ship/flight | Inventory |
| `EGDataShipPlayer.lua` | 19.1 KB | Ship/flight | Full |
| `EGDataShipScout.lua` | 5.3 KB | Ship/flight | Full |
| `EGDataShipSphere.lua` | 4.4 KB | Ship/flight | Inventory |
| `EGDataShipVanguardChunk.lua` | 6.5 KB | Ship/flight | Full |
| `EGDataTilesets.lua` | 4.1 KB | Interior/tiles | Full |
| `EGDataWeapons.lua` | 38.0 KB | Combat/weapons/particles | Delegated |
| `EGDataXenoHelmetless.lua` | 2.0 KB | Character/body/voice | Inventory |
| `EGDataXenoIncinerator.lua` | 4.0 KB | Character/body/voice | Inventory |
| `EGDataXenoJetpack.lua` | 4.8 KB | Character/body/voice | Inventory |
| `EGDataXenoPoacher.lua` | 3.4 KB | Character/body/voice | Inventory |
| `EGDataXenoReplete.lua` | 5.2 KB | Character/body/voice | Inventory |
| `EGDataXenoScrapper.lua` | 5.2 KB | Character/body/voice | Inventory |
| `EGDataXenoSoldier.lua` | 2.1 KB | Character/body/voice | Inventory |
| `EGDataXenoTrooper.lua` | 3.1 KB | Character/body/voice | Inventory |
| `EGDataZoricaScene.lua` | 7.4 KB | Starting scene setup | Partial |
| `EGOptions.lua` | 5.0 KB | Input/options | Partial |

### 3.4 Procedural generation data — `Scripts/DataGeneration/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `EGDataDecorationGen.lua` | 12.9 KB | Procedural content | Partial |
| `EGDataInteriorGen.lua` | 2.3 KB | Procedural content | Full |

### 3.5 Render data — `Scripts/DataRender/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `EGDataEyes.lua` | 2.8 KB | Render data (eyes) | Partial |
| `EGDataSkybox.lua` | 4.2 KB | Render data (skybox) | Partial |

### 3.6 Gameplay runtime — `Scripts/Gameplay/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `EGActionBindings.lua` | 13.4 KB | Input/options | Partial |
| `EGActor.lua` | 5.5 KB | Entity/base actor | Full |
| `EGAsteroidBelt.lua` | 1.9 KB | Planets/space | Partial |
| `EGAudio.lua` | 15.0 KB | Audio | Delegated |
| `EGBehavior.lua` | 2.6 KB | AI behaviour | Full |
| `EGBehaviorCombat.lua` | 13.7 KB | AI behaviour | Full |
| `EGBehaviorCombatBattleship.lua` | 4.0 KB | AI behaviour | Partial |
| `EGBehaviorCombatSphere.lua` | 4.2 KB | AI behaviour | Partial |
| `EGBehaviorFollow.lua` | 1.9 KB | AI behaviour | Full |
| `EGBehaviorInvestigate.lua` | 3.6 KB | AI behaviour | Full |
| `EGBehaviorOrbit.lua` | 3.7 KB | AI behaviour | Full |
| `EGBehaviorPlayer.lua` | 8.4 KB | AI behaviour | Full |
| `EGBehaviorTravel.lua` | 5.6 KB | AI behaviour | Full |
| `EGBuilding.lua` | 4.0 KB | Buildings/interiors | Full |
| `EGCamera.lua` | 1.4 KB | Camera actor | Partial |
| `EGCharBehaviorWander.lua` | 11.4 KB | AI behaviour | Partial |
| `EGCharBehaviorXenoCombat.lua` | 15.3 KB | AI behaviour | Partial |
| `EGCharBehaviorXenoCombatIncinerator.lua` | 4.5 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatJetpack.lua` | 1.3 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatPoacher.lua` | 4.3 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatReplete.lua` | 4.7 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatScrapper.lua` | 2.2 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatSoldier1.lua` | 0.5 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatSoldier2.lua` | 0.2 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatSoldier3.lua` | 0.7 KB | AI behaviour | Inventory |
| `EGCharBehaviorXenoCombatTrooper.lua` | 0.7 KB | AI behaviour | Inventory |
| `EGCharacterActor.lua` | 25.3 KB | Character/body/voice | Partial |
| `EGComponents.lua` | 0.2 KB | Misc runtime/data | Inventory |
| `EGDebrisObject.lua` | 3.8 KB | Misc runtime/data | Inventory |
| `EGDocuments.lua` | 1.5 KB | UI/menu/documents | Inventory |
| `EGDownloadMgr.lua` | 1.1 KB | Misc runtime/data | Inventory |
| `EGEditorCamera.lua` | 0.8 KB | Misc runtime/data | Inventory |
| `EGEffect.lua` | 2.0 KB | Misc runtime/data | Inventory |
| `EGExplosion.lua` | 1.1 KB | Misc runtime/data | Inventory |
| `EGGame.lua` | 29.2 KB | Game root, save, pilot modes | Full |
| `EGGravBike.lua` | 3.9 KB | Character/body/voice | Full |
| `EGGrid.lua` | 4.3 KB | Misc runtime/data | Inventory |
| `EGInterior.lua` | 7.4 KB | Interior/tiles | Full |
| `EGInteriorGenZone.lua` | 0.1 KB | Interior/tiles | Inventory |
| `EGMenu.lua` | 4.4 KB | UI/menu/documents | Inventory |
| `EGMenuAirlock.lua` | 7.5 KB | UI/menu/documents | Full |
| `EGMenuArchives.lua` | 6.5 KB | UI/menu/documents | Inventory |
| `EGMenuBuyGame.lua` | 5.5 KB | UI/menu/documents | Inventory |
| `EGMenuColorPopup.lua` | 8.9 KB | UI/menu/documents | Inventory |
| `EGMenuContext.lua` | 3.8 KB | UI/menu/documents | Inventory |
| `EGMenuCredits.lua` | 3.1 KB | UI/menu/documents | Inventory |
| `EGMenuDocPopup.lua` | 2.8 KB | UI/menu/documents | Inventory |
| `EGMenuDocument.lua` | 8.0 KB | UI/menu/documents | Inventory |
| `EGMenuEditLights.lua` | 11.4 KB | UI/menu/documents | Inventory |
| `EGMenuHUD.lua` | 53.9 KB | UI/menu/documents | Delegated |
| `EGMenuHUDEquipment.lua` | 9.5 KB | UI/menu/documents | Inventory |
| `EGMenuHUDStatus.lua` | 3.5 KB | UI/menu/documents | Inventory |
| `EGMenuInventory.lua` | 20.9 KB | UI/menu/documents | Inventory |
| `EGMenuKeybind.lua` | 7.7 KB | UI/menu/documents | Inventory |
| `EGMenuKeybindPopup.lua` | 6.2 KB | UI/menu/documents | Inventory |
| `EGMenuLoading.lua` | 4.9 KB | UI/menu/documents | Inventory |
| `EGMenuMain.lua` | 12.7 KB | UI/menu/documents | Inventory |
| `EGMenuNaming.lua` | 5.2 KB | UI/menu/documents | Inventory |
| `EGMenuOperations.lua` | 13.3 KB | UI/menu/documents | Partial |
| `EGMenuOptionPopup.lua` | 11.8 KB | UI/menu/documents | Inventory |
| `EGMenuOptions.lua` | 25.5 KB | UI/menu/documents | Delegated |
| `EGMenuPause.lua` | 7.8 KB | UI/menu/documents | Inventory |
| `EGMenuPilot.lua` | 3.9 KB | UI/menu/documents | Full |
| `EGMenuPrompt.lua` | 3.6 KB | UI/menu/documents | Inventory |
| `EGMenuQuickSelection.lua` | 12.5 KB | UI/menu/documents | Inventory |
| `EGMenuRadio.lua` | 7.2 KB | UI/menu/documents | Inventory |
| `EGMenuRegister.lua` | 9.5 KB | UI/menu/documents | Inventory |
| `EGMenuSaveLoad.lua` | 11.4 KB | UI/menu/documents | Partial |
| `EGMenuScanners.lua` | 15.0 KB | UI/menu/documents | Partial |
| `EGMenuShipLayout.lua` | 36.0 KB | Interior map editor | Partial |
| `EGMenuStartGame.lua` | 10.8 KB | UI/menu/documents | Inventory |
| `EGMenuStyle.lua` | 0.2 KB | UI/menu/documents | Inventory |
| `EGMenuSystem.lua` | 11.1 KB | Menu system (commented out) | Partial |
| `EGMenuTileset.lua` | 19.7 KB | UI/menu/documents | Inventory |
| `EGPlan.lua` | 1.9 KB | Behaviour selection | Full |
| `EGPlanet.lua` | 28.3 KB | Planets/space | Full |
| `EGPlayer.lua` | 6.2 KB | Character/body/voice | Full |
| `EGPlayerInfo.lua` | 12.6 KB | Discovery/inventory persistence | Full |
| `EGProjectile.lua` | 7.1 KB | Combat/weapons/particles | Inventory |
| `EGProjectileBomb.lua` | 3.4 KB | Combat/weapons/particles | Inventory |
| `EGProjectileFireball.lua` | 0.8 KB | Combat/weapons/particles | Inventory |
| `EGProxyInteriorDebris.lua` | 2.7 KB | Procedural content | Inventory |
| `EGProxyItem.lua` | 10.0 KB | Procedural content | Full |
| `EGRandomGenerator.lua` | 2.9 KB | Procedural content | Full |
| `EGRobotBody.lua` | 11.0 KB | Character/body/voice | Inventory |
| `EGRobotVoice.lua` | 6.0 KB | Character/body/voice | Partial |
| `EGRoom.lua` | 1.1 KB | Interior/tiles | Full |
| `EGScene.lua` | 1.8 KB | Scene base | Partial |
| `EGSceneEditor.lua` | 35.9 KB | Scene/editor/space | Partial |
| `EGSceneObjectPreview.lua` | 6.8 KB | Scene/editor/space | Inventory |
| `EGSceneSolar.lua` | 11.5 KB | Solar scene/orbits/music | Full |
| `EGShipGroup.lua` | 1.5 KB | Ship group coordination | Full |
| `EGTargetProxy.lua` | 2.8 KB | Misc runtime/data | Inventory |
| `EGTile.lua` | 13.1 KB | Interior/tiles | Full |
| `EGTileUtil.lua` | 13.6 KB | Interior/tiles | Full |
| `EGVehicle.lua` | 77.3 KB | Ship/flight | Full |
| `EGWeaponBullet.lua` | 3.2 KB | Combat/weapons/particles | Inventory |
| `EGWeaponGun.lua` | 7.3 KB | Combat/weapons/particles | Inventory |
| `EGWeaponMissile.lua` | 8.3 KB | Combat/weapons/particles | Inventory |
| `EGWorldObject.lua` | 9.7 KB | Entity/base actor | Full |
| `EGXenoBody.lua` | 9.6 KB | Character/body/voice | Inventory |
| `EGXenoVoice.lua` | 6.0 KB | Character/body/voice | Partial |
| `GameplayMain.lua` | 21.4 KB | Entry points, debug console | Partial |
| `MenuStyle.lua` | 0.4 KB | UI/menu/documents | Inventory |

### 3.7 Render/UI texture tooling — `Scripts/Render/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `MenuFonts.lua` | 19.0 KB | Font declarations | Inventory |
| `MenuGen.Background.lua` | 2.7 KB | UI texture generator | Inventory |
| `MenuGen.Button.lua` | 1.7 KB | UI texture generator | Inventory |
| `MenuGen.FillBG.lua` | 3.2 KB | UI texture generator | Inventory |
| `MenuGen.HudGears.lua` | 11.7 KB | UI texture generator | Inventory |
| `RenderMain.lua` | 1.7 KB | Render tooling | Inventory |
| `RenderPass.lua` | 2.8 KB | Render tooling | Inventory |
| `TextureGen.lua` | 3.3 KB | Procedural texture generator | Inventory |
| `TextureGenPasses.lua` | 11.5 KB | Procedural texture generator | Inventory |

### 3.8 Legacy render experiments — `Scripts/Render/old/`

| File | Size | Subsystem | Inspection |
|---|---:|---|---|
| `Desert.lua` | 3.0 KB | Render tooling | Inventory |
| `Mars.lua` | 4.1 KB | Render tooling | Inventory |
| `PlanetGen.Perun.lua` | 3.7 KB | Render tooling | Inventory |
## 4. Data asset inventory

### 4.1 Models — `Data/Models/` (549 files, 37.3 MB)

- **546 `.egm`** — text EGG models. Version distribution measured from headers: **351 v5, 129 v16, 28 v20, 19 v2, 16 v1, 3 v0**.
- **3 `.egi`** — `map1.egi`, `map2.egi`, `map3.egi`, ASCII v1 legacy maps.
- Naming conventions: `Ship1.*`, `Tileset<Name>.*`, `Furniture.*`, `Machines.*`, `Items.*`, `Weapons.*`, `XenoBuildings.*`, `XenoMachines.*`, `XenoParts.*`, `Projectile.*`, `RobotParts.*`, `Vehicle.*`.
- Important files: `Ship1.ShipOpen.egm` (player hull), `Ship1.ShipOpen.Physics.egm` (player collision mesh), `Ship1.Scout1.egm`, `Ship1.Battleship.egm`, `Ship1.VanguardChunk01.egm`, `Machines.PilotStation.egm`, `Machines.Airlock.egm`, `Furniture.DoorRegular.egm`, `Furniture.DoorAirlock.egm`, `Ship1.ShipWalkway.egm`, all `Tileset*.egm`.
- Format notes: `07_DATA_FORMATS_AND_ASSETS.md` §3.

### 4.2 Interiors — `Data/Interiors/` (8 files, 169 KB)

| File | Version | Rooms | Door records | Entities | Notes |
|---|---:|---:|---:|---:|---|
| `Airlock.egi` | 14 | 1 | 2 | 2 | ship/building entrance map |
| `DefaultMap.egi` | binary | — | — | — | player ship interior; binary string table |
| `EmptyMap.egi` | 1 | 0 | 0 | 1 | ASCII grid |
| `Old Default Map.egi` | 5 | 0 | 0 | 104 | ASCII grid; Vanguard interior |
| `OutpostEntrance.egi` | 15 | 4 | 0 | 2 | xeno mine entrance |
| `OutpostEntrance2x3.egi` | 14 | 3 | 0 | 2 | backup entrance |
| `OutpostEntranceIce.egi` | 15 | 4 | 0 | 2 | ice mine entrance |
| `XenoBuildingEntrance.egi` | 17 | 2 | 1 | 2 | xeno building entrance |


### 4.3 Shaders — `Shaders/` (1,151 files, 15.7 MB)

- **72 readable sources**: 51 `.fx`, 21 `.h`. Key files: `RodinaTerrain.fx`, `Rodina.fx`, `standard.h`, `_terrain_constants.h`, `Planet_Common.h`, `_atmosphere.h`, `_perlin.h`, `_voronoi.h`, `_fractal.h`, `_textureMap.h`, `_lighting.h`, `PlanetPerun/Veles/Jarilo/Morena/Asteroid.*`, `RodinaAtmosphere{Scatter,Filter,Blur}.fx`, `RodinaSkybox.fx`, `PlanetSkybox.fx`, `RodinaParticles.fx`, `RodinaImage*.fx`, `Script*.fx`.
- **1,079 `.egs`** in `ShaderCache/` — compiled DXBC blobs; all start with a 4-byte length then `DXBC`. Filenames encode source/profile/entry/permutation tokens.
- `_Fxaa3_11.h` is vendored NVIDIA FXAA; not first-party.
- Analysis: `04`, `_work/rendering_notes.md`.

### 4.4 Textures — `Data/Textures/` (89 files, 34.0 MB)

- 59 `.png` (UI atlases, planet textures, skybox faces, reticles, colorblind variants).
- 24 `.jpg` (soil/rock/sand detail textures).
- 6 `.orig` (skybox backups).
- All proprietary art; do not import.

### 4.5 Audio — `Data/Sounds/` and `Data/Music/`

- 62 `.wav`, 35.7 MB, PCM 16-bit mono (sample 96 kHz). 46 top-level entries (41 WAV + 5 folders), nested weapon/creature folders.
- 24 `.egu`, 82.4 MB, opaque high-entropy music. Codec unknown.
- Logical names → filenames in `Scripts/Gameplay/EGAudio.lua`; procedural voice in `EGRobotVoice.lua`/`EGXenoVoice.lua`.

### 4.6 Fonts — `Data/Fonts/` (49 files, 3.6 MB)

- 17 `.ttf`: Jura, Orbitron, Michroma, Quantico, FiraMono, Audiowide, FSEX300, etc.
- 31 `.spritefont` binary DirectXTK atlases under `FontCache/`.
- `FontCache/MakeSpriteFont.exe` (31 KB) DirectXTK tool; not run.
- Font role declarations in `Scripts/Render/MenuFonts.lua` (75 `CreateFont` blocks).

### 4.7 Documents and localization — `Data/Documents/`, `Data/Localization/`

- 162 `.txt` documents in `LP/` and `ms/`, plus `Data/Documents/LP/EGDataDocuments.lua` (duplicate index).
- Plain text with CRLF, CP1252-ish encoding, HTML entities (`&quot;`, `<em>`).
- `Localization.csv` (32 KB) quoted CSV.
- Do not reproduce narrative content; it is proprietary.

### 4.8 Engine and binaries (root, 10 files, 37.2 MB)

| File | Size | Note |
|---|---:|---|
| `Rodina.exe` | 13,188,608 B | not run/disassembled |
| `Rodina_Steam.exe` | 13,191,168 B | not run/disassembled |
| `steam_api.dll` | 1,429,504 B | Steam integration |
| `d3dcompiler_47.dll` | 3,466,856 B | Microsoft D3D compiler |
| `openal32.dll` | 423,936 B | OpenAL |
| `sfml-audio-2.dll` | 871,424 B | SFML audio |
| `sfml-system-2.dll` | 43,520 B | SFML system |
| `_Redist/*` | 5.9 MB | VC runtime/OpenAL/DXWeb installers |
| `Icon.ico`, `README.txt`, URLs | small | distribution metadata |

## 5. Important files not fully read

These are the highest-value files that were only partially read, delegated, or inventoried. None of the reports depends on an unverified claim from them, but a future deep dive should start here.

| File | Why it matters | Current coverage |
|---|---|---|
| `Scripts/Data/EGEditorData.lua` | 11,143 lines of editor tables: item categories, physics effects, terrain feature sets, persistence profiles, palettes | Persistence profiles and physics effects read; rest inventoried |
| `Scripts/DataGameplay/EGDataParticles.lua` | 4,973 lines of particle effect definitions | Schema and categories via delegated report; not every effect |
| `Scripts/Gameplay/EGMenuHUD.lua` | 1,756 lines; full HUD layout/behaviour | Architecture/modes/channels read; every widget not |
| `Scripts/Gameplay/EGMenuShipLayout.lua` | 1,176 lines; in-game interior editor | Modes and save/load read; full editing semantics not |
| `Scripts/Gameplay/EGMenuOptions.lua` | 1,030 lines; all option rows | Option list/defaults via delegated report |
| `Scripts/Gameplay/EGSceneEditor.lua` | 1,153 lines; interior map editor | Map save/load and room APIs read; rest not |
| `Scripts/DataGameplay/EGDataItems.lua` | 2,079 lines; ~100 item classes | Interactive items/doors/seats/airlock read; full item list delegated |
| `Scripts/DataGameplay/EGDataWeapons.lua` | 993 lines; weapons/projectiles | Schema/examples read; full weapon list delegated |
| `Scripts/DataGameplay/EGDataProgress.lua` | 1,153 lines; story/POI gating | Stage list, AddDebris, document gates read; every transition not |
| `Scripts/DataGameplay/EGDataDocuments.lua` | 659 lines; document index | Format/sample read; not all 162 entries |
| `Scripts/Render/MenuGen.*` | ~1,700 lines; procedural UI textures | Concept understood; every pass not |
| `Shaders/*` (non-core) | 72 sources | Terrain/atmosphere/planet/lighting/post analysed; some effect shaders not line-by-line |
| `Data/Documents/*` | 162 narrative files | Format and samples only; proprietary |
| `Data/Models/*` | 546 models | Format and selected models; not per-model |

## 6. Coverage summary

| Subsystem | Files analysed | Depth | Main report |
|---|---|---|---|
| Core/class system/entry | 8 | Full/partial | 02, 07, 09 |
| Flight/piloting/cameras | 12 | Full | 02 |
| Interiors/airlocks/seats/tiles | 14 | Full/partial | 03 |
| Planets/terrain/atmosphere | 12 + shaders | Full/partial | 04 |
| Procedural content/grammar/seeds | 15 + 10 `.rsl` | Full/partial/delegated | 05 |
| AI/behaviours/navigation | 20 | Full/partial | 06 |
| Data formats/assets/models | 1,800+ files | Inventory + format analysis | 07 |
| Persistence/save | 25 | Full/delegated | `_work/persistence_notes.md` |
| UI/input/audio/options | 30 | Delegated/partial | `_work/ui_audio_notes.md` |
| Items/weapons/particles/bodies | 12 | Delegated/partial | `_work/items_combat_notes.md` (when present) |
| Rendering/shaders | 72 + 1,079 headers | Delegated/partial | `_work/rendering_notes.md` |

**Bottom line:** all 2,282 files are inventoried and categorised; all major behavioural subsystems have been inspected to the depth needed for Starfall’s current scope. The remaining gaps are engine-side implementation, binary formats, and the specific files listed in §5.
