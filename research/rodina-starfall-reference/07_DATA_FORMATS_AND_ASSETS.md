# 07 — Data Formats, Assets, Exporters, and What Is Actually Readable

**Scope:** what the Rodina 1.6.2 archive contains, which formats can be read, which require missing tools, and what the limitations mean for any Starfall work. Static analysis only. No asset is proposed for reuse.

**Confidence tags:** `[C]` verified by opening files, `[I]` inferred from consistent evidence, `[U]` unknown/engine-private.

---

## 1. Readability at a glance

| Format | Count | Size | Readable? | Role | Notes |
|---|---|---|---|---|---|
| `.lua` | 161 | ~2.3 MB | **Yes** | gameplay/data scripts | plain text, Lua 5.1-era |
| `.rsl` | 10 | ~3,600 lines | **Yes** | EGSL interior grammars | engine-interpreted |
| `.fx` / `.h` | 51 / 21 | ~336 KB | **Yes** | HLSL shader sources | some CP1252 |
| `.egm` | 546 | ~37.3 MB | **Yes (text)** | models + physics meshes | EGG text format, versions 0–20 |
| `.egi` | 11 | <1 MB | **Mixed** | interior maps | v1/v14–17 ASCII; player map binary |
| `.egs` | 1,079 | ~15.4 MB | **Mostly no** | compiled shaders | uint32 + DXBC; reflection chunk readable, bytecode not |
| `.wav` | 62 | ~35.7 MB | **Container yes** | SFX | PCM 16-bit mono, typically 96 kHz |
| `.egu` | 24 | ~82.4 MB | **No** | music | high-entropy, no magic; codec unknown |
| `.png` / `.jpg` | 59 / 24 | ~34 MB | **Yes (images)** | textures/UI | proprietary art; do not reuse |
| `.ttf` | 17 | ~2.5 MB | **Yes** | fonts | third-party families |
| `.spritefont` | 31 | ~1.1 MB | **No (binary)** | pre-baked font atlases | starts `DXTKfont`, DirectXTK |
| `.txt` | 162 | ~0.5 MB | **Yes** | documents/localization | often CP1252, HTML entities |
| `.csv` | 1 | 32 KB | **Yes** | localization table | quoted CSV |
| `.py` | 1 | 19 KB | **Yes** | Blender exporter | Blender 2.91-era |
| `.exe` / `.dll` | 10 | ~37 MB | **No** | game/binaries | not executed or analysed beyond static strings |

The complete 2,282-file manifest with path, extension, size, and category is `99_FILE_MANIFEST.csv`.

---

## 2. Lua: the real source of truth

### 2.1 Class system

`EGCore.lua` implements a prototype/class system on plain Lua tables:

- `EGMakeClass(fullName, superName, prototype)` creates or reuses a class table, installs `New`, `Name`, `ClassName`, `FullName`, and sets `__index = superClass` (`EGCore.lua:35-76`).
- `EGNewObject` sets the instance metatable to itself with `__index = class` and calls `EGInitRecursive` up the chain (`:79-102`).
- `EGInitRecursive` calls each class's `Init` once, super-first (`:90-102`).
- Data scripts are loaded into a separate environment or staged globals; `EGLoadLuaDataFile` uses `setfenv` (`:255-268`).
- The compile process is optional; `loadfile` is the default, and bytecode caching writes `<script>.egs` via `string.dump` (`:398-476`).

This is why the archive is readable: the shipped game includes uncompiled `.lua` source, and the engine can load it directly.

### 2.2 Data-script pattern

There are 439 `EGMakeClass` sites. Typical data class:

```lua
EGMakeClass("EGShipScout", "EGVehicle")
EGShipScout.DisplayName = "Xeno Scout"
EGShipScout.MaxHealth = 30
EGShipScout.Path = "Ship1.Scout1.egm"
EGShipScout.VehiclePhysics = { Basis = "...", ShapeType = "Mesh", Mass = 500, ... }
EGShipScout.BehviorTypes = { Player = EGBehaviorPlayer, Combat = EGBehaviorCombat, ... }
```

This is an **inheritance + prototype constants** format, not JSON. It offers computed values, comments, loops, helper functions, and cross-class references (e.g. `ShipHorizonRollStrength` option). The tradeoff is that data and code are the same language; there is no schema, no validation, and a typo can throw at load time.

**Starfall translation:** use Godot `Resource` classes with typed `@export` fields and `.tres` files, or a `Resource` + JSON schema. Keep the *data-driven* property (ships, weapons, planets, POIs are data), not the prototype-in-Lua mechanism.

### 2.3 Load order and engine boundary

No file in the archive defines the compile/load order. `EGFinalizeCompile` exists (`EGCore.lua:478-502`) but the engine chooses the order. This matters because `PlanetDef` appears in both `EGPlanet.lua` (subclass of `EGPlanet`) and `Render/RenderMain.lua` (no superclass) (`RenderMain.lua:50-52`); whichever loads last wins. The Render folder is likely tooling-only, but this is not stated `[U]`. Flag duplicate globals as a reason not to treat Lua load order as a reliable spec.

---

## 3. `.egm` — the model/mesh format

### 3.1 Envelope

```
EGG
<version>
START OBJECT
...
END OBJECT
```

Version distribution across 546 files (measured):

| Version | Files |
|---|---|
| 0 | 3 |
| 1 | 16 |
| 2 | 19 |
| 5 | **351** |
| 16 | 129 |
| 20 | 28 |

All sampled files share the same structural token vocabulary. Version differences were not exhaustively diffed; treat the version number as a **writer revision**, not a guaranteed schema, and do not build a converter on the assumption that v5 and v20 differ only cosmetically `[I]`.

### 3.2 Object hierarchy

Each object:

```
START OBJECT
GEOMETRY            (or 3DOBJECT for an empty/transform-only node)
VERTICES
<n>
VERTEX 0
<px> <py> <pz>
<nx> <ny> <nz>
<u> <v>
<materialIndex>
...
INDICES
<count>
<index>...
MATERIALS
<count>
MATERIAL0
<name>
<diffuse r> <g> <b>
<specular r> <g> <b>
<roughness>
<alpha>
<emit r> <g> <b> <a>
<emitStrength>
<mapDiffuse or "None">
<mapDiffuseFactor>
<mapNormal or "None">
<mapNormalFactor>
<mapEmissive or "None">
<mapEmissiveFactor>
...
NAME
<name>
TRANSLATE
<x> <y> <z>
ROTATE
<rotation mode, e.g. XYZ>
<rx> <ry> <rz>
SCALE
<sx> <sy> <sz>
CHILDREN
<n>
<child objects...>
END OBJECT
```

Confirmed against `EllipticExport.py:34-127`, `Ship1.ShipOpen.egm`, `Machines.PilotStation.egm`, `Furniture.DoorRegular.egm`. Vertices are **duplicated per face vertex** where position/normal/UV/material differ (the exporter dedups by exact tuple and has a bug that never reuses vertex 0, `EllipticExport.py:324-333`). Materials reference textures by path/name, not embedded data.

A model can be a deep hierarchy of named parts. This is how door animation works: `Items.Door:SetAnimation` translates parts named `Left`, `MidLeft`, `MidRight`, `Right` (`EGDataItems.lua:594-600`); the airlock door translates `DoorAirlock` (`:633-636`). There is no skinning/skeleton data in the format.

Physics meshes use the same format (`Ship1.ShipOpen.Physics.egm`, 1,380 lines) and are referenced by `VehiclePhysics.Basis`. A `ShapeType = "Mesh"` physics object uses the geometry directly; simpler props use `Box`/`Convex` with extents or a `Path`.

### 3.3 What the exporter proves

`Scripts/EllipticExport.py` is a Blender 2.91 add-on that writes version 20:

- Header `EGG` + `20` (`:17-18`, `:392-395`).
- One `.egm` per root object; filename is `<file>.<object>.egm`.
- Triangulates meshes, extracts material colours/roughness/alpha/emission and texture slots, writes child hierarchy and local transforms.
- Rotation is written as Euler + `object.rotation_mode`.
- Materials are extracted from named Blender nodes (`Diffuse BSDF`, `Specular`, `Glossy BSDF`, `Glass BSDF`, `Emission`) (`:239-261`).

Limitations for any outside use:

- Blender 2.9 APIs (`bpy.context.evaluated_depsgraph_get`, `texture_paint_slots`) are removed/changed in modern Blender; the add-on will not run unmodified.
- It is an **export-only** tool. There is no importer.
- It writes `None` for unsupported values and has no schema/version negotiation.
- The shipped assets are proprietary. **Do not import or redistribute them in Starfall.**

### 3.4 Why not use `.egm` in Starfall

- Legal: Rodina's models are proprietary. The archive is an unofficial distribution.
- Technical: no robust importer; material model is simpler than Godot's; no skeleton/animation; normals/UVs are baked per-face; units and orientation conventions are Rodina-specific.
- The *format idea* worth noting is plain-text meshes with named parts and a separate physics mesh. Starfall should use glTF (`CSG`/`ArrayMesh` for runtime, glTF for authored) and Godot physics shapes.

---

## 4. `.egi` — interior maps

Three encodings are present (detailed structure in `03_INTERIORS_AND_AIRLOCKS.md`):

1. **v1 ASCII grid** — `EGG / 1 / INTERIOR / width / ASCII rows / TILESETS / DECORATIONS / DOORS / ENTITIES`. Used by `EmptyMap.egi`, `Old Default Map.egi`, `map1-3.egi`. Readable, legacy.
2. **v14–17 structured ASCII** — header dimensions/origin, `ROOMS` (each with coords, walls, interior walls, doors, open connections), `GENERATOR`, `DOORS`, `CUSTOM LIGHTS`, `ENTITIES`, `TILESETS`. Used by `Airlock.egi`, `OutpostEntrance*.egi`, `XenoBuildingEntrance.egi`. Partially decoded; some fields are undocumented.
3. **Binary** — `DefaultMap.egi`, the player ship. Starts with a length-prefixed string table (`GridWidth`, `RoomInteriorWalls`, room names, item names), followed by binary records. Readable as strings; **not** fully parseable without the engine writer.

`System.Interior.SaveMap` / `LoadMap` (`EGSceneEditor.lua:1003-1010`) and `System.Interior.MakeBounds` / `MakeEntranceBounds` are engine APIs. No Lua parser exists.

**Do not attempt to convert these maps into Starfall scenes.** The coordinates, room semantics and entity IDs are Rodina-specific; the binary format is not documented; and the content is proprietary.

**Transferable idea:** a versioned text interior format with explicit header dimensions, room records, door records and entity records is a good choice for Starfall's own editor. Keep it one format, versioned, with a parser you own.

---

## 5. `.rsl` — EGSL grammar

Ten plain-text files, 3,625 lines, ~338 productions. The syntax and semantics are covered in `05_PROCEDURAL_CONTENT.md` and `_work/grammar_notes.md`. Key format facts:

- Flat global namespace, no imports.
- `production Name(params) … end`, `weight`, `priority`, `let`, `concept`, `produce`, `rule`, `variable`, `property`.
- Overloading by name + arity.
- No recursion; `IsAncestor` unrolled to depth 6 (`ProductionTestCore.rsl:15-87`).
- `let` is both precondition and assertion; `priority` semantics undefined. These are real blockers to a faithful reimplementation.
- The interpreter is engine-side; no Lua loader or `.rsl` string appears in any `.lua` file. `EGDataInteriorGen.lua` only binds `ProductionName` and entrance coordinates.

**Transferable idea:** declarative room-graph expansion with weighted alternatives and fact assertions is powerful. Starfall should implement a *small, typed* version (e.g. `RoomTemplate` resources + a graph expander) rather than a general EGSL clone.

---

## 6. Shaders: `.fx` / `.h` / `.egs`

### 6.1 Sources

72 readable source files (`51 .fx`, `21 .h`), ~9,650 lines. `standard.h` has the shared cbuffers and VS/PS framework; `_atmosphere.h`, `_perlin.h`, `_textureMap.h`, `_utility.h`, `_lighting.h`, `_terrain_constants.h`, `Planet_Common.h` are the load-bearing headers. `_Fxaa3_11.h` is vendored NVIDIA FXAA.

The readable sources reveal:

- Terrain material blending, planet height/normal bakes, atmosphere ramps, skybox/star, particles, bloom/DOF/FXAA.
- Shared constant buffers: `PerFrameConstants`, `PerObjectConstants`, `PlanetConstants`, `PlanetGenConstants[1024]`, `VoronoiPoints[1024]`, `Lights[200]` (`standard.h`).
- MRT outputs: colour, linear depth, emissive, blur/DOF control.
- Per-pixel logarithmic depth (`SV_Depth`), no shadow maps, no tonemap/gamma/exposure pass.

### 6.2 Compiled cache

`Shaders/ShaderCache/*.egs` are **not opaque blobs**. Each is:

```
uint32 little-endian length
"DXBC" container
  RDEF reflection chunk (ASCII names)
  SHEX bytecode (opaque)
  STAT, etc.
```

Verified across all 1,079 files: every one begins with a 4-byte length then `DXBC`. The `RDEF` chunk leaks cbuffer names, members, types, resource bindings, and `STAT`; the `SHEX` instruction stream requires a DXBC disassembler (a build tool) and was not decoded. No source was reconstructed.

The filename grammar is `{fx}-{profile}-{entry}[-TOKEN-VALUE]*`, e.g. `RodinaTerrain-ps_5_0-PS-DEP-1-TPL-1-TVD-1-TDI-1-TMD-1-TDE-1.egs`. Tokens (`VERTLIT`, `LOGDEP`, `DEP`, `EMIT`, `DIFF`, `NORM`, `TPL`, `TVD`, `TDI`, `TMD`, `TDE`, `PORSUR`, `INST-50`, …) act as a demand journal of shipped permutations. The token→macro mapping is inferred from the source macros; the exact mapping table lives in the executable. The cache contains stale/duplicate permutations (an orphan `PORDEP` token and an empty token), so it is not a clean specification.

**Transferable ideas:** cache shader permutations under a closed token vocabulary; key the cache on a hash of preprocessed source + toolchain version; prefer Godot's `ShaderMaterial`/`shader_include` and `Texture2DArray` over 32 explicit samplers; do not copy Rodina shaders.

### 6.3 “.egs” is a three-way extension collision

The same extension is used by:

1. **Compiled Lua bytecode**: `EGCompileFileBytecode` writes `<script>.egs` via `string.dump` (`EGCore.lua:430-445`).
2. **Savegames**: `EGGame:Autosave` writes `Auto-<player> <context>.egs`; `Quicksave.egs` (`EGGame.lua:406-445`).
3. **Shader cache**: all 1,079 files in `Shaders/ShaderCache`.

The extension is **never a type discriminator**; only the directory and the header distinguish them. This is a cautionary tale for Starfall: use distinct extensions for savegames, compiled scripts, and shader caches.

---

## 7. Audio: `.wav` and `.egu`

- **SFX**: 62 WAV files, 35.7 MB, mostly Microsoft PCM 16-bit mono 96 kHz. Subfolders group sources by weapon/creature. The `Sound` table in `EGAudio.lua` maps a logical name to a `Filename` and playback parameters (`Volume`, `Loop`, `UpSpeed`, `DownSpeed`, `MinDistance`, `Attenuation`, `IgnoreTimescale`) (`EGAudio.lua:5-707`). The `Filename` maps verbatim to `Data/Sounds/<path>.wav`, with backslashes as separators.
- **Music**: 24 `.egu` files, 82.4 MB. `file` reports `data`; headers are high-entropy with no ASCII magic (e.g. `01 c8 a7 b2 f6 d9 75 60 …`). Codec, channels, sample rate, loop metadata, and whether it is encrypted/compressed are **unknown**. Treat as engine-private and unusable.
- **Procedural voice**: `EGRobotVoice.lua`/`EGXenoVoice.lua` generate note-event arrays (wave type, duty, tremolo, vibrato, pitch) performed via `PlaySoundKeys`; this is synthesis, not sampled audio. A useful independent idea for Starfall (`AudioStreamGenerator`), not a format to copy.

Do not reuse any Rodina audio in Starfall. The formats are readable enough to confirm provenance, not licensed for reuse.

---

## 8. Textures, fonts, documents, localization

- **Textures**: 59 PNG, 24 JPG, 6 `.orig` backups (skybox originals). PNGs include UI atlases (`InventoryGrid_1.png`, `colorblind_planets_*.png`), planet textures, skybox faces, reticles. JPGs are terrain/rock/soil photo textures. All proprietary art.
- **Fonts**: 17 TTF families (Jura, Orbitron, Michroma, Quantico, FiraMono, Audiowide, FSEX300) plus 31 `.spritefont` pre-baked atlases. `.spritefont` files are **binary DirectXTK** (start `DXTKfont`), not Microsoft XNA XML; `MakeSpriteFont.exe` is shipped in `Data/Fonts/FontCache`. The TTFs are third-party fonts with their own licences; do not assume they are redistributable with a game.
- **Documents**: 162 `.txt`, mostly CP1252/“non-ISO extended ASCII”, with HTML entities (`&quot;`, `<em>`) and CRLF. `EGDataDocuments.lua` indexes them as `{Name, Font, Files[]}`; page count = `#Files`. `EGPlayerInfo` stores read counts per document ID and inventory counts for ownership.
- **Localization**: `Data/Localization/Localization.csv`, a quoted CSV with a source string and translation column. Many strings are HTML-escaped. No engine parser is visible; it is likely loaded by the engine or a tool.

---

## 8.5 Item, weapon, character, and particle data schemas

These are the data formats a Starfall designer is most likely to imitate conceptually. Details and the full class tables are in `_work/items_combat_notes.md`; the format-level points are:

### 8.5.1 Items

`Scripts/DataGameplay/EGDataItems.lua` is 2,079 lines and declares ~125 classes. The pattern is a class + optional prototype fields:

```lua
EGMakeClass("Items.Door", "EGWorldObject")
Items.Door.Name = "Door"; Items.Door.MenuCategory = "Doors"
Items.Door.Path = "Furniture.DoorRegular.egm"
Items.Door.IsDoor = true
Items.Door.Autoclose = true
Items.Door.Physics = { ShapeType = "Box", ExtentLow = ..., ExtentHigh = ... }
System.Interior.RegisterEntityType(Items.Door)
function Items.Door:OnGrab() ... end
```

There is **no schema and no interface**. An item is interactive if it happens to define `OnGrab(self)`; the character controller calls `lookingAt:OnGrab(self)` blindly (`EGCharacterActor.lua:339-342`). Hover text is `ShowInfo` → `GetDisplayName()`. Fields that matter for format design: `Path`, `Scale`, `GeometryScale`, `Offset3D`, `Physics` (`ShapeType` = Box/Convex/Mesh/Sphere/Ragdoll, extents, `MotionType`, mass, friction, restitution), `LightAddon`, `Generation` (a `Generation.*` decoration rule), `IsChair`/`ChairBackwards`, `IsDoor`/`IsAirlockDoor`, `Autoclose`/`ActorOpenLimit`, `DoorSize`/`OpenSpeed`/`OpenMult`, `DepressurizeParticles`, `LockEditorPlacement`, `IgnoreNPCVision`, `PersistenceProfile`.

This is a compact, low-ceremony authoring format. Starfall should keep the *data-driven* property but replace the implicit `OnGrab` duck-typing with an explicit `Interactable` contract, and replace stringly typed module names with `StringName` constants or typed resources.

### 8.5.2 Inventory

Rodina keeps **two ledgers**:

1. A spatial item component (`EGGetInventory(engine)`) with grid coordinates, item size (`Width`/`Height`), `CoordX`/`CoordY`, `ID`, and equipment slots (`HEAD`, `WEAPON`, `TOOL`, `BODY`). Used by the inventory/equipment UI.
2. `EGPlayerInfo.Inventory` counts keyed by class name (e.g. `"Items.RocketAmmo"`, `"MainStoryline"`). Used by ammo, consumables, documents, story gates.

The seam is visible: some flows check both; ammo is debited only for the player (`EGWeaponGun.lua:192-205`); equipment has an active flag separate from occupancy. The pattern is flexible but a desync generator for co-op. Starfall should use **one server-authoritative inventory** with item definitions, counts, grid positions, and slots in the same record.

### 8.5.3 Weapons and projectiles

`EGDataWeapons.lua` is 993 lines and 42 classes. There is **no hitscan** in Rodina: all guns spawn projectiles. Three archetypes:

- **`EGWeaponBullet`** — fast projectile (1,000–10,000 speed), collision radius 20–100, no gravity, reflects off magnetic shields.
- **`EGProjectile`** — slow body (15–200 speed), optional explosion, charge scaling, impact gibs; `ShipMode` multiplies scale/speed when the target is a vehicle.
- **`EGWeaponMissile`** — homing, target range 100,000, closing radii 600/1,000, rotation speed 1.25, min speed 300, 30 s lifetime.

Fields: `Damage`/`ChargeDamage`, `Speed`, `Lifetime`, `Range`, `CooldownTime`, `SoundCooldownTime`, `SpreadX/Y`, `NumProjectiles`/`ProjectileCount`, `ProjectileClassname`, `BarrelTypeName`, `AmmoType`, `FireStyle` (`SINGLE SHOT`, `CONTINUOUS`, `CHARGE`, `CHARGE BURST`, `BURST`), flare/charge particles and timings, sounds, impact particles/sounds, `ExplosionType`, impact debris class/count, `ChargeFactor`/`ChargedSize`, `InheritOwnerVelocity`, `IsPlasma`, `IsMagneticShield`, `CanBeDefault`, `AltWeapon`, `InventoryType`, `Palette`.

**Team handling is a hardcoded player-vs-not-player check**, not a team field: a projectile owned by a non-player passes through any `CharacterActor` that is also not the player (`EGProjectile.lua:106-112`). Xeno shots cannot hurt xenos. Missile targeting is similarly player-centric (`EGWeaponMissile.lua:94-147`). Starfall must add a real `team_id` and a friendly-fire policy before co-op.

`EGVehicle:FireWeapon` is entirely commented out in 1.6.2 (`EGVehicle.lua:1660-1736`); ship guns are engine-driven, and `BarrelTypeName` survives as data. Do not infer a working Lua ship-weapon pipeline.

### 8.5.4 Characters, bodies, and particles

- Characters are **modular assemblies**: a list of `{name, part_class, parent_name, slot_name, scale}` records (`GetModuleEntities`), with native arm/leg/pelvis animation modules. Robot parts are seed-selected; xeno parts are `math.random`-selected. There are no per-part hit zones or health in Lua (`EGActor.lua:142-172`).
- Loot is a weighted grammar table, one nesting level (`EGDataGenerateLoot.lua`, `EGCharacterActor.lua:112-116`).
- Particle effects are `System.CreateParticleMaterial{Name, BlendStyle, Loop, DecayRate, DecayDelay, Styles[]}` where each style has `Rate`, `Size`, `Offset`, `VelocityBase/Range`, `VelocityNormalBase/Range`, `Acceleration`, `AccelerationNormal`, `AccelerationGravity`, `Yaw`/`Pitch`, `Lifetime`, and `Keys[]` (`Color`, `Alpha`, `Time`, `Size`). 104 materials, 1–2 styles each. Requested by name via `AttachParticles(slot, name, amount, position, direction)`.
- `Generation.Loot` and `Generation.RewardLoot` are referenced but never defined in Lua; the engine resolves them `[U]`.

---

## 9. Binaries and compiled files

| File | Size | Status |
|---|---|---|
| `Rodina.exe` / `Rodina_Steam.exe` | 13.2 MB each | not executed; static strings only |
| `d3dcompiler_47.dll` | 3.5 MB | Microsoft D3D compiler |
| `openal32.dll`, `sfml-audio-2.dll`, `sfml-system-2.dll` | 0.04–0.87 MB | audio/runtime libraries |
| `steam_api.dll` | 1.4 MB | Steam integration |
| `_Redist/*.exe` | 5.9 MB | VC runtime/OpenAL/DXWeb installers |
| `Data/Fonts/FontCache/MakeSpriteFont.exe` | 31 KB | DirectXTK font baker |

None were run or disassembled. They are listed for completeness and flagged as out of scope. Any behaviour attributed to them in this library is marked `[U]` or `[I]`.

---

## 10. `EllipticExport.py` in detail

| Aspect | Finding | Line |
|---|---|---|
| Target | Blender 2.91.2, add-on `Elliptic Games Exporter` v1.1.6 | 1-10 |
| Output | One `.egm` per root selected/visible object, `<file>.<object>.egm` | 358-400 |
| Version | Always `"20"` | 17-18 |
| Geometry | Triangulates via bmesh, dedups exact position/normal/UV/material tuples | 216-340 |
| Materials | Diffuse/specular/roughness/alpha/emission + diffuse/normal/emissive maps | 228-280 |
| Hierarchy | Children written recursively with local translate/rotate/scale | 32-65 |
| Rotation | Euler + Blender `rotation_mode` | 149-155 |
| Bugs | `matchingVertexIndex > 0` never reuses vertex 0; UVs forced to `None` in this revision | 304-333 |

It is useful as **format documentation** and as evidence of how the developers authored models. It is not a usable pipeline today (Blender API drift) and not a licence to reuse assets.

---

## 11. Formats that cannot be safely or reliably interpreted

| Format | Why |
|---|---|
| `DefaultMap.egi` (binary) | no schema; engine writer only |
| `.egu` music | unknown codec/encryption; high entropy |
| `.egs` shader bytecode | `SHEX` needs a DXBC disassembler; not attempted |
| `.spritefont` | binary DirectXTK; tool shipped but not run |
| `.exe`/`.dll` | compiled; not analysed beyond strings |
| Savegames `.egs` | engine binary; version 38; no sample in the archive |

For each, the library documents the limitation rather than guessing. If a future task needs one of these, the correct next step is to obtain the engine's writer/reader or a legitimate specification, not to reverse-engineer the binary by trial and error.

---

## 12. Rules for Starfall

1. **Do not import Rodina assets.** Models, textures, audio, fonts (unless separately licensed), maps, and code are proprietary. Use the archive for understanding, then build or license independent assets.
2. **Do not port Rodina shaders line-for-line.** Use the concepts: feature-mask terrain blending, distance band widening, analytic atmosphere ramps, MRT blur control, two-stage DOF. Implement in Godot shaders with your own code.
3. **Do not use `.egm`, `.egi`, `.rsl`, `.egu`, or `.egs` as runtime formats.** They are either proprietary, undocumented, or both.
4. **Do use the data-model lessons:** resource-driven ships/weapons/planets, stable seed + generation version, one versioned interior format, a separate physics mesh, named model parts for mechanical animation.
5. **Keep savegame, bytecode, and shader-cache extensions distinct.** Rodina's `.egs` collision is a cautionary example.
6. **Record provenance.** If a future contributor asks “where did this number come from?”, the evidence index (`09`) should answer with a file and line.

---

## 13. Evidence summary

| Claim | Evidence | Confidence |
|---|---|---|
| 2,282 files; counts by type | `99_FILE_MANIFEST.csv`; `find`/`du` | C |
| Lua class system and data scripts | `EGCore.lua:35-102`; 439 class sites | C |
| `.egm` structure and versions | `Ship1.ShipOpen.egm`; `PilotStation.egm`; `EllipticExport.py` | C |
| 546 `.egm`; 351 v5, 129 v16, 28 v20, 19 v2, 16 v1, 3 v0 | measured headers | C |
| `.egm` has named parts and no skeleton | door part animation `EGDataItems.lua:594-600`; exporter | C |
| Exporter writes version 20 and is Blender 2.91 | `EllipticExport.py:1-18` | C |
| `.egi` three encodings | file inspection; `03` | C |
| `.rsl` engine-interpreted, no Lua loader | no `rsl` string in Lua; `EGDataInteriorGen` | C/I |
| `.egs` cache is DXBC | all 1,079 start `DXBC` after uint32 length | C |
| `.egu` opaque | high-entropy headers, `file` = data | C |
| WAV is PCM 16-bit mono 96 kHz | `file` on sample | C |
| `.spritefont` is binary DXTK | header `DXTKfont`; `MakeSpriteFont.exe` | C |
| `.egs` extension collision | `EGCore.lua:430`; `EGGame.lua:420`; `ShaderCache/` | C |
| No importer for `.egm` | only exporter present | C |
| Engine/binary internals | not analysed | U |

---

## 14. Cross-references

- Interior map structure and runtime: `03_INTERIORS_AND_AIRLOCKS.md`
- Shader algorithms and render pipeline: `04_PLANETS_AND_TERRAIN.md`, `_work/rendering_notes.md`
- Grammar format: `05_PROCEDURAL_CONTENT.md`, `_work/grammar_notes.md`
- UI styles/fonts/audio: `_work/ui_audio_notes.md`
- Save format: `_work/persistence_notes.md`
- Full manifest: `99_FILE_MANIFEST.csv`
