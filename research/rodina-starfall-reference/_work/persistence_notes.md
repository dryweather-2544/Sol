# Rodina 1.6.2 — Persistence Architecture (static analysis)

Source root: `Rodina.v1.6.2/Rodina.v1.6.2` (extracted). Line numbers refer to that tree.
Read-only inspection of 161 Lua files; no executable, DLL, or script was run.
**[EV]** = directly evidenced at cited line; **[INF]** = inference, not stated anywhere.

---

## 1. Scope

The Lua layer never touches save-file bytes. It defines two serialization protocols the engine
calls into, plus the policy layer (when to save, what to name it). Every actual I/O is a `System.*`
call: `System.SaveGame`, `System.LoadGame`, `System.LoadRecentGame`, `System.GetRecentSavegame`,
`System.DeleteSavegame` (`EGGame.lua:379-403`, `EGMenuSaveLoad.lua:352`).

The engine-facing entry points are globals in `Scripts/Gameplay/GameplayMain.lua`:

| Global | Line | Role |
|---|---|---|
| `EGOnStartGame()` | 5 | fresh game; `System.BeginStartGame()` then `EGGame:New()` |
| `EGOnLoadGame(aStream)` | 57 | legacy path — engine passes a versioned stream |
| `EGOnDecodeGame(aBuffer)` | 66 | current path — engine passes a keyed buffer |

Both load paths discard the old `gGame`, construct a fresh one, then delegate (`:57-70`). A fourth
callback, `EGOnBuildPersistentInfo(aData)` (`EGCore.lua:386`), writes only `aData.CurrentProfile`
with the comment "Don't need to save here. Just add the data" **[EV]** — profile metadata, not game
state. The existence of *two* load entry points is the key structural fact; §2–§5 follow from it.

---

## 2. The two mechanisms

### 2.1 Keyed buffer — `Encode(aBuffer)` / `Decode(aBuffer)`

Dictionary-like store: `aBuffer:Set(key, value)` / `aBuffer:Get(key, default)`, plus
`SetVector`/`GetVector` (`EGVehicle.lua:237`, `:278`). Two properties matter:

- **Order-independent.** Fields are addressed by key, so a missing key degrades to the caller's
  default instead of desynchronizing the stream. `EGPlayerInfo:Decode` defaults every field
  (`EGPlayerInfo.lua:308-325`).
- **Self-describing per class.** Not one of the 24 `Encode`/`Decode` pairs consults
  `GetVersion()`. Backward compatibility is achieved purely through default arguments.

Introduced in **Rodina 1.5.0**: "Encode / Decode replaces Save / Load" and "Savegame format changed
to EGON binary" (`README.txt:129-130`, under the `RODINA 1.5.0` heading at line 119) **[EV]**.

### 2.2 Versioned stream — `Load(aStream)` / `LoadFinalize()`

Positional binary stream with a version readable via `aStream:GetVersion()`. Reads are typed and
sequential: `ReadString`, `ReadInt`, `ReadNumber`, `ReadBool`, `ReadVector`, and a polymorphic
`Read` (`EGGame.lua:509-566`). Because position is implicit, every field added after a given
version needs a `GetVersion() >= N` guard, and every removed field must still be *read and
discarded* to keep the cursor aligned.

That discard pattern recurs and is strong evidence the format was edited in place over many
releases:

- `EGGame.lua:522-528` — three fields read into locals and dropped, commented "These are no longer
  needed so just get read them and ditch them", gated `>= 7`.
- `EGInterior.lua:63-72` — four `dummy*` locals, gated `>= 3`.
- `EGInterior.lua:74-85` — fire-cell loop reads four numbers per cell, discards all.
- `EGPlanet.lua:748-752`, `EGDataCharacterRobot.lua:216-218` — `dummyLockToPlanet`.
- `EGDataShipVanguardChunk.lua:190-193` — four `dummy_*` fields.

### 2.3 Where each is used

`EGGame` implements both protocols and is the only class whose `Decode` performs *migration work*.
`EGGame:Decode` (`:468-504`) reads `GameVersion` from the buffer, then sets deferred flags:

- `< 5` (`RODINA_VERSION_110_SCRIPT_VERSION`) → `ShowVersion110Message` (`:489`)
- `< 26` (`RODINA_VERSION_122_SCRIPT_VERSION`) → `ShowVersion122Message` (`:493`)
- `< 36` (`RODINA_VERSION_130_SCRIPT_VERSION`) → `EnsureVanguardExists` (`:497`)
- `< 38` (`RODINA_VERSION_162_SCRIPT_VERSION`) → `CreatePlayerStartingEquipment` (`:501`)

`EGGame:Load` sets the same first three from the *stream* version (`:568-578`) but **cannot set the
fourth** — there is no `< 38` branch in `Load`, because a version-38 save was never written as a
stream **[INF]**. The four constants are declared together at `EGGame.lua:5-9`.

The flags are consumed on the next `EGGame:Update` (`:81-100`): the doc popup, `CheckVanguardExists`
(`:154-166`), and the global `EGCreatePlayerStartingEquipment` (`GameplayMain.lua:39`). This is
migration-by-flag, not migration-by-rewrite: the save is untouched, the world is patched afterwards.

---

## 3. Save order

`EGGame:Load` fixes the order of the two top-level aggregates **[EV]**:

Sequence: `EGGame.lua:509-561` scalars -> `:565` `Progress:Load` -> `:566`
`PlayerInfo:Load`. `Encode`/`Decode` mirror that order exactly (`:460-464`, `:485-487`).
The ordering is hard-coded by call sequence; nothing declares it. `EGGame:LoadFinalize` (`:582-590`)
runs last: opens `EGMenuLoading`, and if `PlayerID` is still nil calls `CreatePlayer`.

**Scene and entity loading is not visible in Lua.** No Lua function reads a stream into a scene;
`EGScene` has no serialization methods at all (`EGScene.lua`, 61 lines). The engine owns the graph
and calls each entity's `Load`/`Decode`. Evidence is indirect but consistent: per-entity `Load`
methods cross-reference numeric IDs (`OwnerID`, `TargetID`, `MasterEyeID`, `SlaveEyeID`,
`GroupLeader`), which only resolves if the engine assigns IDs first; and `EGGame:LoadFinalize`
calls `System.GetCurrentScene()` (`:583`), presupposing a scene already exists **[INF]**.

Reconstructed order: **(1)** engine header/version, **(2)** `EGGame` scalars, **(3)**
`EGRodinaProgress`, **(4)** `EGPlayerInfo`, **(5)** engine scene + per-entity `Load`/`Decode`,
**(6)** per-entity `LoadFinalize`, **(7)** `EGGame:LoadFinalize` **[INF for 1, 5, 6]**.

---

## 4. Version gates — complete verified set

`RODINA_SCRIPT_SAVEGAME_VERSION = 38` (`EGGame.lua:5`), copied to `self.GameVersion` (`:16`) and
written as the `GameVersion` key (`:462`).

I extracted every `GetVersion()` comparison in the tree (52 total); the table is exhaustive for
numeric literals. **The task brief's list was incomplete and slightly wrong** — the real set
includes gates it omitted (4, 7, 17, 21, 22, 23, 28, 29, 31, 33, 35), and its ">=38" does not exist
as a stream gate at all.

| File | Gates | Unlocks |
|---|---|---|
| `EGGame.lua` | 2, 4, 7, 13, 14, 15, 18, 24, 38 | `:513` FreeformMode; `:518` ShowAtmosphereEntryHint; `:522` three deprecated fields (discarded); `:531` PlayerID; `:537` PreferPilot/AllowPilotFirstPerson; `:543` IsFirstPerson; `:548` ScreenshotMode; `:556` TargetEntityID + AltimeterEntityID + ShowAltimeter + FloatAltimeter; `:501` starting-equipment flag (`Decode` only) |
| `EGVehicle.lua` | 2, 6, 8, 9, 12, 16, 19, 26 | `:314` atmosphere state (InPlanetAtmostphere, EntryCompleteTimer, AltitudeRatio, Crashed); `:327` player position; `:334` LastFireTime; `:340` MakeChildren + ChildrenList; `:352` three airlock bools; `:359` PilotInterface block (8 fields); `:371` GroupLeader; `:376` InteriorGenSeed |
| `EGCharacterActor.lua` | 5, 7, 17, 31, 33 | `:629` SaveHeldName + SaveEquippedName; `:635` Health; `:640` Running; `:646` MakeChildren + ChildrenList; `:656` HeldItemID. Gate 31 also appears at `:616` inside a commented-out `Encode` draft |
| `EGInterior.lua` | 3, 5, 10 | `:64` legacy fire scalars (discarded); `:73` fire-cell grid (count + 4 numbers/cell, all discarded); `:86` AllDoorsOpen |
| `EGPlanet.lua` | 20, 25 | `:753` StoryDebrisID; `:758` HasBeenVisited |
| `EGProxyItem.lua` | 11, 20, 32 | `:292` HasDiscovered; `:299` StoryDebrisStage + PrimaryDebrisClassName + HACKForceScriptUpdate; `:305` EnemyList |
| `EGPlayerInfo.lua` | 20, 30, 34 | `:360` PregnantFactor + IsPregnant + PregnancyCompleteCount; `:368` DefaultWeapon + Powerup (name -> EGGetClass); `:376` GravBikeRecieved (dummy, dropped) |
| `EGRobotBody.lua` | 22, 28, 29, 22 | `:62` Scale; `:66` per-axis GeometryScale (supersedes uniform scale); `:78` Palette; `:342` robot-eye MasterEyeID + SlaveEyeID |
| `EGDataCharacterRobot.lua` | 21, 22, 23 | `:199` BeenNamed + DisplayName; `:205` Scale; `:209` dummyLockToPlanet (discarded) |
| `EGDataItems.lua` | 3 | `:1229`, `:1309` CollectedTimer (mounted gun / wall extinguisher) |
| `EGDataProgress.lua` | <=33, <=35, <=35 | `:171` remap ProgressFinished -> Chapter2Begin; `:175` Chapter2Complete -> Chapter3Begin; `:179` ProgressFinished -> Chapter3Begin |
| `EGXenoBody.lua` | 22 | `:284` xeno-eye MasterEyeID + SlaveEyeID |
| `EGBuilding.lua` | 37 | `:120` InteriorGenSeed |
| `EGSceneSolar.lua` | 27 | `:381` InCombatTimer |

Plus constant comparisons: `< 5`, `< 26`, `< 36` at `EGGame.lua:568-578`; `< 38` at `:501`
(Decode only).

Properties worth noting:

- Gates are increasing but **not contiguous** — 1 is absent, and 33/35 are upper bounds (`<=`). A
  version-34 save hits the `<=35` remaps but not `<=33`.
- Several gates exist only to *retire* a field, so version numbers were consumed by removals as
  well as additions. That is why 37 distinct gate values exceed the number of live fields added.
- **No gate at 38 exists in any `Load` method** (`:501` in `Decode` is the only 38 check) **[EV for
  absence]**.
- Inheritance is handled by explicit superclass calls: `EGRobotEyes:Load` calls `EGBodyPart.Load`
  first (`EGRobotBody.lua:338`), `EGShipVanguardChunk:Load` calls `EGVehicle.Load`
  (`EGDataShipVanguardChunk.lua:189`). Base-then-derived in both directions keeps the stream aligned.

---

## 5. Autosave, quicksave, backup

### 5.1 Autosave

`EGGame:Autosave(aContextName)` (`:406-428`) applies a three-way guard: `EGGetOption("Autosave")`
(default `true`, `EGOptions.lua:118`); `self.AutosaveTime > EGGetOption("AutosaveTimeLimit")`
(default **20** s, `EGOptions.lua:119`); and both player *and* player vehicle above 0 health
(`:411-415`), so no autosave while dead. `AutosaveTime` accumulates only while unpaused (`:78-79`)
and resets on every save/load (`:381`, `:387`, `:393`, `:417`).

Filename: `EG_DIR_USERDATA` + `"Auto-"` + playerName + `" "` + contextName + `".egs"` (`:419-420`).
Name comes from `GetPlayerInfo():GetPlayerName()`, so a rename starts a new autosave family **[INF]**.

Seven autosave call sites, each with a distinct context string:

| Context | Site | Trigger |
|---|---|---|
| `"is in Trouble"` | `EGSceneSolar.lua:317` | `SetInCombat()`, combat *edge* only |
| `"Pilots Ship"` | `EGDataItems.lua:511` | after `StartPilotingVehicle` from ship computer |
| `"Pilots Ship"` | `EGMenuAirlock.lua:232` | same, via airlock menu |
| `"Enters Atmo"` | `EGVehicle.lua:1006` | atmosphere entry edge, player only |
| `"Exits Limnal"` | `EGVehicle.lua:900` | `SetGear`, leaving gear 4 |
| `"Edits Ship"` | `EGSceneEditor.lua:991` | leaving ship-interior editor |
| `"Enters Interior"` | `EGGame.lua:902` | polled, interior non-nil, 0.5 s debounce |

`"Enters Interior"` is polled, not evented: `CheckAutosaveEnterInterior` (`:889-910`) runs every
frame from `EGGame:Update` (`:115`) using `IsInsideInterior`/`InsideInteriorTimer` for edge
detection. Because `IsInsideInterior` initialises to `true` (`:53`), the first interior entry after
a fresh game does not autosave; it fires only after the player has been outside and returned.

The options help text (`EGMenuOptions.lua:124`) still promises "when you enter combat, begin
atmospheric descent, or pilot your ship" — predating the interior/editor additions **[EV for text,
INF for staleness]**.

### 5.2 Quicksave

Hardcoded, single-slot, no confirmation, no naming: `"Quicksave.egs"` in `EG_DIR_USERDATA`
(`:431-438`); quickload reads the same path (`:441-445`); triggered by the pause-menu `QUICKSAVE`
button (`EGMenuPause.lua:244-246`). Unlike autosave it has **no health guard and no time limit** —
it writes whenever pressed.

### 5.3 Recent save

A separate engine-tracked pointer: `System.GetRecentSavegame()` (`:397-403`),
`System.LoadRecentGame()` (`:391-394`), used for a HUD continue affordance (`EGMenuHUD.lua:382-392`).
The engine decides what counts as recent **[INF]**.

### 5.4 Backup handling

There is **no Lua-side backup, rename, rotate, or copy of save files.** Searching `backup`, `.bak`,
`Overwrite` across the gameplay tree yields only `EGMenuSaveLoad.ShowBackups` (`:21`, `:61`,
`:192-193`, `:272-277`, `:313-315`), a UI toggle, plus false positives:
`EGBuilding.EntrancePathBackupSize` (`EGBuilding.lua:10`) is a fallback interior map, and
`EGSceneEditor.lua:1023` "Lose the oldest backups" refers to an **undo stack** capped at 500
interior snapshots, not save files.

The toggle keys off an engine-supplied boolean, `fileData.HasVersion` (`EGMenuSaveLoad.lua:54-62`):

```
if( findIndex and ( not fileData.HasVersion or self.ShowBackups ) ) then
```

Read literally, files *without* `HasVersion` show by default and files *with* it stay hidden until
the toggle is on. Nothing in Lua writes or clears that flag, so its meaning is not derivable here
**[INF, unresolved]**. Two readings fit: (a) it marks engine-created *versioned backups* hidden by
default — which suits the "Show Backups" label — or (b) it marks stale-version saves. The changelog
"Improvement: Include time / game version in savegames" (`README.txt:247`, under 1.3.2) implies
saves carry a version stamp, supporting either.

Note `System.GetFilesInDirectoryIncludingMods` (`EGMenuSaveLoad.lua:51`): the save browser scans
**mod directories as well as userdata** (`SourceDirectories`, `:61-63`), so a mod can inject saves
into the list.

### 5.5 `.egs` — a three-way collision

`.egs` denotes three unrelated things in this tree:

1. **Savegames.** `FileExtension = ".egs"` (`GameplayMain.lua:560`, `EGMenuPause.lua:191`,
   `EGMenuBuyGame.lua:164`), built as `dir..filename..extension` (`EGMenuSaveLoad.lua:341`).
2. **Compiled Lua bytecode.** `EGCore.lua:430` — `string.sub(aFilename, 1, -5)..".egs"`, i.e. a
   `.lua` path minus its extension plus `.egs`, written with `string.dump` by
   `EGCompileFileBytecode` (`:398-470`); the read path (`:452-457`) falls back to
   `loadfile(bytecodeFilename)` when source is absent.
3. **Shader cache.** All 1079 `.egs` files present on disk live in `Shaders/ShaderCache/`, e.g.
   `Rodina-ps-PS-UNLIT-1.egs` (`EGEditorData.lua:2829-3141`).

This is a real namespace collision. The extension is **not** a reliable type discriminator —
`EGGetSaveFiles` selects candidates *solely* on `fileData.Extension == ".egs"`
(`EGUtility.lua:383-406`). What actually disambiguates is the directory: savegames under
`EG_DIR_USERDATA`, bytecode next to its `.lua` under `Scripts/`, shaders under
`Shaders/ShaderCache/` **[INF]**. On this build only the shader variety exists
(`find Scripts -name "*.egs"` is empty), consistent with the bytecode cache being gated off by
`Options.ScriptLoadSaveBytecode` (`EGCore.lua:406-410`) or with this being a source-only extract
**[INF]**.

### 5.6 A latent bug in the save enumerator

`EGGetSaveFiles` (`EGUtility.lua:383-406`) appends the wrong variable: inside
`for j,fileData in ipairs(files)` it does `result[#result+1] = data`, where `data` is an undefined
global. That appends `nil`, growing `#result` while leaving holes, and the following `table.sort`
(`:403`) would compare `nil`. The function appears dead — the live browser uses its own inline loop
over `System.GetFilesInDirectoryIncludingMods` (`EGMenuSaveLoad.lua:50-72`) — so the bug is latent.
I found no caller **[EV for the bug; INF for dead-ness]**.

---

## 6. `LoadFinalize` — why a second pass exists

Eleven classes define it. In every non-empty case it resolves what the read pass could not:

| Class | Line | Work | Why deferred |
|---|---|---|---|
| `EGVehicle` | `EGVehicle.lua:382` | `SetPiloted`; push 3 airlock bools into child `"Airlock Computer"` | children do not exist during read |
| `EGCharacterActor` | `EGCharacterActor.lua:662` | `Engine:SetRunning(self.Running)` | needs live physics body |
| `EGPlanet` | `EGPlanet.lua:764` | `CheckTileDiscovered(self.Tile)` | needs engine-created tile |
| `EGInterior` | `EGInterior.lua:92` | `UpdateFireAlarm(0)` | needs room graph |
| `EGGame` | `EGGame.lua:582` | open loading menu; create player if `PlayerID` nil | last step of load |
| six others (`EGProjectile`, `EGProjectileBomb`, `EGWeaponBullet`, `EGWeaponMissile`, `EGCamera`, `EGRoom`) | see §8 | empty stubs | convention applied uniformly |

`EGVehicle` is clearest: `Encode` *derives* the airlock bools via
`GetChildEntity("Airlock Computer")` (`:246-249`), and `LoadFinalize` writes them back then nils the
temporaries (`:384-396`). Five of eleven `LoadFinalize` methods are empty stubs, implying the
convention was adopted for entity classes regardless of need.

---

## 7. What is *not* saved

### 7.1 Fire — deliberately retired

`EGInterior` still declares `OnFire`, `OnFireAmount`, `OnFireTimer`, `OnFireCount` in `Init`, but
the block is commented out in both `Encode` (`:42-47`) and `Decode` (`:53-58`), and the stream path
reads-and-discards it (`:64-85`). The live `Encode` writes exactly one field, `AllDoorsOpen` (`:48`).
So interior fire state is **not persisted at all** in the current format. The comment
`--self.FireData = EGGrid:New()` (`:72`) and the discarded fire-cell loop mark the removal. Fire
*behaviour* still runs — `LoadFinalize` calls `UpdateFireAlarm`, `Update` calls `UpdateFireDamage`
(`:92-100`) — so a loaded interior starts fire-clean and can re-ignite **[INF]**.

### 7.2 Character children — commented out on one side only

`EGCharacterActor:Encode` contains a fully commented-out `MakeChildren`/`ChildrenList` block labelled
"Version 31" (`:594-604`), mirrored in `Decode` (`:613-626`), **yet the stream `Load` has a live
`>= 31` branch that reads it** (`:646-655`). The field is therefore written by old saves, read from
old saves, and never written by new ones; the `-- Version 33` comment at `:606` marks retirement.
Practical effect: characters spawned as children of a character are not re-created from a 1.5.0+
save **[INF]**.

### 7.3 Positions of arbitrary entities

Never serialized — no generic transform/position write exists in any `Encode`/`Decode`. The
exceptions prove the rule, each being a *specific* workaround:

- `EGVehicle` writes `PlayerPos` only, the player's position inside the vehicle (`:237`), restored
  into `PlayerOrientation` (`:277-283`). The vehicle's own world position is engine-owned.
- `EGPlanet` writes `EnemiesSaved`/`DebrisSaved` as `{Index, Position}` pairs (`:730-750`) — respawn
  bookkeeping for planet-wide populations, not live transforms.
- `EGBodyPart` writes `Scale`/`GeometryScale` with no translation.

Entity world transforms are therefore engine-side and outside Lua's view **[INF, well-supported]**.

### 7.4 Other notable absences

- **`EGScene` has no serialization at all** (61 lines). Menu stack and camera state are not saved;
  `EGCamera:Load` is empty (`EGCamera.lua:28`).
- **`EGRoom` persists nothing** — `Load` and `LoadFinalize` both empty (`:16-21`); air pressure is
  read live from the engine (`:29-31`).
- **`EGTargetProxy:Load` empty** (`:53`).
- **Projectile motion** — only `ChargeFactor` (`EGProjectile.lua:74`) and bomb
  `Age`/`OwnerID`/`TargetID` (`EGProjectileBomb.lua:77-81`); velocity is recomputed.
- **`LastFireTime` defaults to `10000000000`** when absent (`EGVehicle.lua:336`) — a "never fired"
  sentinel, not a timestamp.
- **`EGShipVanguardChunk:Decode` force-resets `Health` to `MaxHealth` before the base Decode**
  (`EGDataShipVanguardChunk.lua:181`), so vanguard chunks always load at full health. The `Load`
  path explains why: "Fix for bad savegames - infinity values get loaded up as 1.0" (`:196-200`),
  and it also nulls `XenoDesiredCount` when exactly 1.
- **`DebugMode` is not saved** while `ScreenshotMode` is — compare `EGGame.lua:16-54` against the
  15 keys in `Encode`.

---

## 8. Subsystem -> saved? -> fields -> evidence

| Subsystem | Saved | Fields (buffer) | Stream extras | Evidence |
|---|---|---|---|---|
| `EGGame` root | Yes | 14 keys | `+ShowAtmosphereEntryHint`, discards 3 | `EGGame.lua:448-465`, `:507-579` |
| `EGRodinaProgress` | Yes | `StageTimer`, `Stage` | same two, by name | `EGDataProgress.lua:151-189` |
| `EGPlayerInfo` | Yes | 11 keys | `+GravBikeRecieved` dummy | `EGPlayerInfo.lua:293-378` |
| `EGVehicle` | Yes | 10 scalars, `PlayerPos`, `ChildrenList`, 3 airlock, 8 pilot | split by gates 2/6/8/9/12/16/19/26 | `EGVehicle.lua:226-396` |
| `EGShipVanguardChunk` | Partial | `+XenoCount` | reads 4, discards; health forced to max | `EGDataShipVanguardChunk.lua:174-201` |
| `EGCharacterActor` | Yes | `Health`, `Running` | `+SaveHeldName`, `+SaveEquippedName`, `+HeldItemID`, `+ChildrenList` | `EGCharacterActor.lua:591-665` |
| `EGXenoCharacter` | Yes | `+Seed` | `+Seed`, `+dummyLockToPlanet` | `EGDataCharacterXeno.lua:164-180` |
| `EGRobotCharacter` | Yes | `+RobotSeed`, `BeenNamed`, `DisplayName`, `Scale` | gates 21/22/23 | `EGDataCharacterRobot.lua:175-217` |
| `EGBodyPart` base | Yes | `Scale`, `GeometryScale` | gates 22/28/29 | `EGRobotBody.lua:47-80` |
| `EGRobotEyes` / `EGXenoEyes` | Yes | `+MasterEyeID`, `+SlaveEyeID` | gate 22 | `EGRobotBody.lua:322-349`, `EGXenoBody.lua:264-291` |
| `EGInterior` | Barely | `AllDoorsOpen` only | fire read+discarded | `EGInterior.lua:41-94` |
| `EGRoom` | **No** | — | empty | `EGRoom.lua:16-21` |
| `EGPlanet` | Yes | 7 keys incl. `DebrisIDs`/`EnemyIDs` | `+HighProcess`, `+Index`es, `+EnemiesSaved`, `+DebrisSaved`, gates 20/25 | `EGPlanet.lua:689-767` |
| `EGBuilding` | Yes | `XenoCount`, `InteriorGenSeed` | `InteriorGenSeed`, gate 37 | `EGBuilding.lua:107-123` |
| `EGProxyItem` | Yes | 9 keys | `EnemyList` gate 32 | `EGProxyItem.lua:244-311` |
| `EGProxyInteriorDebris` | Yes | `HasFinalized` | same | `EGProxyInteriorDebris.lua:71-83` |
| `EGDebrisObject` | Yes | `ItemModelName` (class name) | same | `EGDebrisObject.lua:97-121` |
| `EGProjectile`, `EGWeaponBullet`, `EGWeaponMissile` | Yes | `ChargeFactor`; `OwnerID` on both weapons | none | `EGProjectile.lua:74-90`, `EGWeaponBullet.lua:32-49`, `EGWeaponMissile.lua:54-71` |
| `EGProjectileBomb` | Yes | `Age`, `OwnerID`, `TargetID` | same | `EGProjectileBomb.lua:77-100` |
| `Items.GunBlasterMounted` | Yes | `CollectedTimer` | gate 3 | `EGDataItems.lua:1218-1232` |
| `Items.FireExtinguisherWall` | Yes | `CollectedTimer` | gate 3 | `EGDataItems.lua:1298-1312` |
| `EGSceneSolar` | Yes | `InCombatTimer` | gate 27 | `EGSceneSolar.lua:370-384` |
| `EGCamera`, `EGTargetProxy` | **No** | — | empty `Load` | `EGCamera.lua:28`, `EGTargetProxy.lua:53` |
| Inventory / docs / discoveries | Yes, all in `EGPlayerInfo` | `Inventory`, `ReadDocuments` (key+count), `Discovered` (key only) | same | `EGPlayerInfo.lua:336-353` |
| Scene / entity transforms | **No** | — | engine-owned | §7.3 |
| Interior fire | **No** | — | commented out | §7.1 |

**Totals:** 24 classes define `Encode`+`Decode`+`Load`; 3 define `Load` only (`EGCamera`, `EGRoom`,
`EGTargetProxy`); 11 define `LoadFinalize`. No class defines `Encode`/`Decode` without also defining
`Load` — the legacy path was never dropped.

---

## 9. Residual uncertainties

1. `fileData.HasVersion` semantics (§5.4) — engine-supplied, not derivable from Lua.
2. Whether the engine selects `EGOnLoadGame` or `EGOnDecodeGame` per file, or runs both against
   different parts of one EGON container (§2.3). The README says "replaces", but
   `EGBuilding:Load`'s `>= 37` gate implies at least one version-37 stream existed after the switch.
3. `EG_DIR_USERDATA` / `EG_DIR_MODDATA` physical paths — engine-side, never printed in Lua.
4. Whether `EGGetSaveFiles` (§5.6) is referenced from engine bindings.
5. `EGPlanet.HighProcess` / `EnemyIndex` / `DebrisIndex` are read by `Load` (`:713-717`) yet absent
   from both `Encode` (`:689-698`) and `Decode` (`:700-709`) — a real asymmetry between the two
   protocols, unexplained by anything in the tree.
