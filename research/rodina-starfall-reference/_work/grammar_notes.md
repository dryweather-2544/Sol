# Rodina 1.6.2 — EGSL Production Grammar & Interior Generation (static analysis)

Source root: `Rodina.v1.6.2/Rodina.v1.6.2`. Line numbers refer to that tree.
Read-only inspection; no executable, DLL, or script was run.
**[EV]** = directly evidenced at cited line; **[INF]** = inference, not stated anywhere.

---

## 1. What EGSL is

The `.rsl` files are written in **EGSL**, a name the developers use themselves:
`-- Oh god, EGSL has no recursion :(` (`ProductionTestCore.rsl:15`) **[EV]**. It is a declarative
production language describing how to expand one interior into a graph of rooms, then how to dress
those rooms with tilesets, lights, fog, doors, decorations and enemies. Changelog entries confirm
intent and arrival: "New Feature: Procedural Interiors - EGSL Productions" (`README.txt:307`, under
1.3.0), "Improvement: EGSL for room lights, loot, and door types" (`README.txt:244`, 1.3.2),
"Improvement: Generator EGSL now allows loot and NPCs" (`README.txt:287`) **[EV]**.

Ten `.rsl` files ship, 3,625 lines total, holding **~338 productions**, 89 `concept` declarations,
582 `let` and 555 `produce` statements.

| File | Lines | `production` | `let` | `produce` | `weight` | `priority` | `concept` |
|---|---|---|---|---|---|---|---|
| `XenoMineProductions.rsl` | 356 | 24 | 83 | 30 | 15 | 10 | 14 |
| `XenoMineEnemyProductions.rsl` | 382 | 55 | 34 | 58 | 9 | 6 | 0 |
| `XenoMineDecorationProductions.rsl` | 336 | 36 | 38 | 97 | 13 | 17 | 0 |
| `XenoBuildingProductions.rsl` | 670 | 52 | 90 | 160 | 10 | 9 | 43 |
| `XenoBuildingEnemyProductions.rsl` | 320 | 46 | 27 | 50 | 8 | 5 | 0 |
| `XenoBuildingDecorationProductions.rsl` | 268 | 32 | 45 | 46 | 19 | 7 | 0 |
| `ProductionTestCore.rsl` | 675 | 37 | 124 | 30 | 7 | 26 | 0 |
| `ProductionTest.rsl` | 418 | 25 | 90 | 52 | 25 | 0 | 32 |
| `DebrisLootProductions.rsl` | 117 | 18 | 25 | 16 | 11 | 0 | 0 |
| `VanguardEnemyProductions.rsl` | 83 | 13 | 11 | 8 | 2 | 1 | 0 |

`ProductionTest*.rsl` are misnamed: they carry live shipped data, including every Vanguard interior
and every room-shape and decoration rule for the Vanguard Ruins (`ProductionTest.rsl:341-418`) **[EV]**.

## 2. Grammar

A file is a flat sequence of declarations separated by `--` comments and `-----` dividers. There is
no header, import, or module scoping: all files share one global namespace, evidenced by
`XenoBuildingProductions.rsl` producing `Room`, which `ProductionTestCore.rsl` declares
**[EV for the cross-reference; INF for the shared namespace]**.

### 2.1 Productions

`production <Name>( <params> )` … bare `end` (`XenoMineProductions.rsl:17-31`). The minimal example
is the default xeno-mine room shape (`:17-31`): `weight 1`, `priority 3`, one gating fact, six `let`
facts.

**Overloading is by name *and* arity.** `XenoOutpostWingNode` is declared three times with 2, 3 and
4 parameters (`XenoMineProductions.rsl:127`, `:138`, `:149`); the engine selects by argument count.
This is how a node with 0, 1 or 2 outgoing edges is expressed **[EV for the declarations; INF for the
selection rule]**.

### 2.2 `weight`

Integer (`weight 10`, `XenoMineProductions.rsl:18`), often omitted (`XenoMineEnemyProductions.rsl:2-7`).
Among same-signature alternatives it is relative probability; the default is 1, inferred because bare
pairs like `MakeMineEnemiesBoss1` must be distinguishable **[INF]**.

It shapes real odds. `MakeTurret` has three alternatives: `weight 1` + ceiling turret, `weight 1` +
floor turret, and **`weight 10` with an empty body** (`XenoBuildingDecorationProductions.rsl:3-15`).
The empty body is the "spawn nothing" branch — roughly 1-in-6 odds of a turret. The same idiom gives
crate piles of 3/2/1 at weights 2/1/1 (`:34-51`).

### 2.3 `priority`

Integer, sometimes with `weight` (`XenoMineProductions.rsl:18-19`), sometimes alone
(`ProductionTestCore.rsl:384`). Usage suggests it orders *which* alternative is considered first, so
a higher-priority production pre-empts lower ones instead of competing with them: `RoomShape` has a
`priority 3` generic default, `priority 4` for storage rooms and arenas, `priority 5` for asteroid
arenas (`XenoMineProductions.rsl:62`, `:82`) — a specificity ladder where the most specific variant
wins regardless of weight **[INF — priority is never defined in Lua or documented in the files]**.

### 2.4 `let`

Two roles share one keyword, and this is the language's most important subtlety:

- **condition (precondition):** `let IsXenoMine( node )` (`XenoMineProductions.rsl:130`) constrains
  when the production applies.
- **assertion (postcondition):** `let Radius( room, 4 )` (`:21`) produces a value for an attribute
  the engine later reads.

Nothing in the syntax distinguishes them; the engine must decide per-predicate whether it is a query
or a generator. Supporting evidence: the same predicate appears in both roles — `IsXenoMine` is a
condition at `:20` and an assertion at `:288` — while `Fog`, `HasLight` and `Tileset` only ever
appear as assertions **[INF, high confidence]**. A third case is `let IsNode( a, node )` (`:186-188`),
which records graph structure directly.

### 2.5 `concept` and `produce`

`concept a, b, c` declares fresh concept variables — new graph nodes or new edges
(`XenoMineProductions.rsl:274-275`). Concepts are **untyped**: `edgeAB` and `a` are declared
identically, and the only thing making one an edge is its **position** in a later `produce` call
(`:180-182`). Convention (not syntax) is node concepts first, then edge concepts, with `concept`
preceding the `produce` lines that use them.

`produce <Production>( <args> )` expands a child production, passing concept variables and inherited
edge variables positionally (`:180-182`). `produce` may appear zero times — leaf content productions
are all facts, no children (`XenoMineEnemyProductions.rsl:2-7`).

### 2.6 `rule` and `variable`

`ProductionTestCore.rsl` adds a second declaration form. `rule Name( params )` is a base fact with an
empty body (`:1-12`) or a derived predicate whose body is a conjunctive query of fact calls
(`:17-19`). `variable p` introduces existentially-quantified intermediate concepts (`:21-24`):

```
rule IsAncestor( node, a )
    variable p1, p2
    IsNode( node, p1 )
    IsNode( p1, p2 )
    IsNode( p2, a )
end
```

47 `rule` declarations and 22 `variable` statements live in that one file. Because EGSL has no
recursion, transitive ancestry is **manually unrolled to depth 6** — seven `IsAncestor` rules with
0–6 intermediate variables (`:15-73`), the last one branching (`IsNode( p4, p5 )` and
`IsNode( p4, p6 )`). The author's frustration is recorded verbatim at line 15. `rule` appears in
exactly one of ten files; the other nine use `production` only **[EV]**.

### 2.7 Literals

Integers, floats, double-quoted strings and 2-element range tables, all at
`XenoMineProductions.rsl:21-29` (`{ 0.1, 0.3 }` for `GrowthChanceRange`). No boolean type: truth is
presence, and `true` appears only as a bare argument (`ProductionTest.rsl:355`).

## 3. Fact vocabulary

49 distinct predicates. Frequencies are statement-leading occurrences across all ten files.

**Graph and context (gating):** `IsNode` (94), `IsPlanetType` (49), `IsXenoBuilding` (42),
`IsXenoMine` (41), `IsArena` (29), `IsPathConnection` (21), `IsVanguardInterior` (18), `IsInterior`
(16), `IsDoorType` (14), `IsDefaultHallwayMergeable` (12), `IsStorageRoom` (11), `IsRoom` (6),
`IsBedroom` (6), `IsBathroom` (6), `IsEngineering` (5), `IsCorridor` (5), `IsMedical` (4),
`IsLootStorageRoom` (4), `IsGarage` (4), `IsDebrisStorageRoom` (4), `IsScienceArea` (3),
`IsInstallation` (3), `IsHangar` (3), `IsLivingArea` (2), `IsCommandArea` (2), `IsCloset` (2),
`IsCargoArea` (2), `IsShieldRoom` (1), `IsAncestor` (1).

**Room shape:** `Radius` (16), `Shape` (8), `SizeRangeY` (8), `SizeRangeX` (8), `Height` (7),
`AngledCornerChance` (9), `GrowthRange` (6), `GrowthDecayRange` (6), `GrowthChanceRange` (6),
`GrowthBeginRange` (6), `Symmetry` (6), `GrowthUniform` (1).

`Shape` values: `"Oval"` (7), `"Box"` (1). `Symmetry`: `"X"` (4), `"XY"` (2). `Radius` spans 1–10
with one fractional `3.5` (`ProductionTestCore.rsl:390`). Every `GrowthBeginRange` in shipped data is
`{ 1.0, 1.0 }` — effectively a no-op left in the schema **[EV]**.

**Surface and ambience:** `Tileset` (13), `HasLight` (7), `HasWallPattern` (4), `Fog` (8),
`IsDefaultHallwayTileset` (3), `IsDefaultHallwayAngledCorners` (7).

Tileset values are drawn from exactly the tilesets Lua registers via `System.Interior.RegisterTileset`
(`EGDataTilesets.lua:3-157`): `"Xeno Mine"`, `"Xeno Ice Mine"`, `"Xeno Building"`, `"Bridge"`,
`"Bathroom"`, `"Living Area"`, `"Engineering"`, `"Corridor"`, `"Medical"`, `"Installation"`,
`"Hallway"`, `"Hanger"`, `"Holoscreen"`, `"Holoscreen (Full)"`. That the two vocabularies coincide
exactly is the strongest evidence the engine, not Lua, binds the systems together **[EV for both
lists; INF for the binding]**.

Fog is seven `XenoFog*` variants, all registered in `EGEditorData.lua:143-…`: `XenoFogGreen`,
`XenoFogGreenThick`, `XenoFogGreenThin`, `XenoFogYellow`, `XenoFogYellowThin`, `XenoFogBrown`,
`XenoFogBrownExtraThick`. Weighted choice is expressed as one production per type —
`XenoBuildingFogTypes` carries weights 20/10/10/10/10/5 across six alternatives
(`XenoBuildingProductions.rsl:3-36`).

**Doors:** only `IsDoorType( <concept>, "<type>" )`. Values: `"XenoDoor"` (7, always on the interior
concept) and `"DoorAirlock"` (4, on Vanguard nodes). There is **no `door`, `edge`, `node` or `light`
keyword** — zero statement-leading occurrences of each; the graph and ambience are expressed entirely
as facts **[EV]**.

**Content spawning:** `HasDecoration` (164, the most frequent predicate) and `HasCharacter` (72).
Character values are class names resolvable by `EGGetClass`: `EGXenoReplete` (18),
`EGXenoIncinerator` (13), `EGXenoScrapper` (11), `EGXenoFlier` (8), `EGXenoPoacher` (7),
`EGXenoTrooper` (6), `EGXenoCharacter` (5), `EGXenoHelmetless` (4), `EGXenoSoldier1/2`. Decoration
values resolve against the schema in §8: `RocketAmmo` (18), `Barrel` (12), `Crate` (11), `GravBike`
(8), plus `XenoCrate`, `ThermalGel`, `Rock1`…`Rock3`, `XenoTurret`, `XenoWallScreen`, `XenoBigScreen`,
`MissileCrate`, `HousePlant`, `Desk`, `Bed`, `Toilet`, `Sink`, `Rug`, `Document`, `ShipStatus`,
`HealthResource15`, `ProxyInteriorDebris`.

Quantity is expressed by repeating an identical `let`: `MakeThermalGel` at `weight 3` emits
`HasDecoration( room, "ThermalGel" )` three times
(`XenoBuildingDecorationProductions.rsl:20-25`), and `MakeCrates` variants emit 3, 2 or 1 (`:34-51`)
**[EV]**.

## 4. The room graph model

A top-level production receives two engine-supplied concepts and builds everything beneath them.
`XenoOutpostInterior` (`XenoMineProductions.rsl:271-300`) is the clearest case:

- Parameters `interior, entrancePath` are **not** declared with `concept` — the engine passes them,
  `interior` being the interior under generation and `entrancePath` the entrance hallway (`:271`).
- It declares `concept mainChain, boss_room, reward_room` plus `concept e0, e1` (`:274-275`) and
  chains them: `produce XenoOutpostWingNode2( mainChain, entrancePath, e0 )`,
  `produce Room( boss_room, e0, e1 )`, `produce XenoMineDebrisRoom( reward_room, e1 )` (`:278-280`).
- It mixes in ambience productions taking the *whole interior* rather than a node:
  `produce DefaultHallwayTileset( interior )`, `produce LightTypes( interior )`, and
  `produce XenoMineFogTypes( mainChain )` (`:282-291`).
- It writes interior-level facts: `IsInterior`, `IsXenoMine`, `IsNode` per concept, and the
  interior-wide `IsDefaultHallwayAngledCorners( interior, true )`,
  `IsDefaultHallwayMergeable( interior, true )`, `IsDoorType( interior, "XenoDoor" )` (`:285-299`).

So: **concepts are opaque IDs; edges are concepts passed positionally; the only structural predicate
is `IsNode( child, parent )`, a directed parent relation.** Recursion is re-entering the same family
with fresh concepts — `XenoOutpostWingNode2` produces two `XenoOutpostWingNode1`s, each producing
three `XenoOutpostWingNode`s (`:167-182`, `:216-232`). Depth is bounded only by which weighted
alternatives are chosen, since every branch bottoms out at a leaf `produce Room(...)` **[INF — no
depth counter exists anywhere in the files]**.

`IsPathConnection( room, e0 )` appears 21 times and seems to relate a node to the edge leaving it
(`ProductionTest.rsl:13-16` uses it beside `IsNode`), but I could not establish more than that
**[INF, low confidence]**.

## 5. How `.rsl` is consumed — engine-side

**There is no Lua reader for `.rsl` in this tree.** The evidence:

1. No Lua file contains the string `rsl` or `EGSL` at all (case-insensitive search over all 161
   `.lua` files) **[EV]**, and none parses `production`, `weight`, `priority`, `concept`, `produce`
   or `let` as syntax **[EV]**.
2. The only Lua-side links are the `ProductionName` string on eight classes
   (`EGDataInteriorGen.lua:5-66`) and `InteriorGenerator` names on buildings
   (`EGDataBuildings.lua:14-118`, `EGDataShipVanguardChunk.lua:12`, `EGBuilding.lua:8`) **[EV]**.
3. Everything else about interiors is an engine API called *from* Lua:
   `System.Interior.RegisterTileset` (`EGDataTilesets.lua:3`), `RegisterEntityType`
   (`EGDataItems.lua:29`), `MakeBounds` (`EGDataBuildings.lua:47`), `SaveMap`/`LoadMap`
   (`EGSceneEditor.lua:1004-1009`).

Note carefully what is *not* the .rsl interpreter: `Scripts/Gameplay/EGRandomGenerator.lua` defines
`EGContextFreeGrammar` with a recursive `Generate` (`:65-103`), fed by `EGMakeGenerator{Name=...,
Expressions={{chance,{symbols}}}}` tables in `EGDataGenerateXenos.lua`, `EGDataGenerateDebris.lua`,
`EGDataGenerateShips.lua` and `EGDataGenerateLoot.lua`. That system selects **flat lists of class
names** (enemy groups, debris contents) by weighted chance and resolves them with `EGGetClass`
(`:91`). It never reads a file, has no facts, no concepts and no graph.

> **INFERRED:** the `.rsl` interpreter is compiled into the engine's interior generator, keyed by
> the `ProductionName` string, and the Lua layer only supplies the entry-point name and seed.

---

## 6. Which production generates which building

The chain is: building class -> `InteriorGenerator` (Lua class name) -> that class's
`ProductionName` -> top-level `.rsl` production.

| Building / vehicle class | `InteriorGenerator` | `ProductionName` | Top-level production | RSL site |
|---|---|---|---|---|
| `EGBuildings.XenoMine` | `EGXenoOutpostInteriorGen` | `XenoOutpostInterior` | `XenoOutpostInterior` | `XenoMineProductions.rsl:271` |
| `EGBuildings.XenoMineIce` | inherited | inherited | same | `EGDataBuildings.lua:24` |
| `EGBuildings.XenoBuilding{3x3,5x5,V,T,Cross,CrossWide}` | `…InteriorGen{5x5,V,T,Cross,CrossWide}` | `XenoBuildingInterior{5,V,T,Cross,CrossWide}` | same names | `XenoBuildingProductions.rsl:440`, `:469`, `:497`, `:533`, `:566`, `:599` |
| `EGShipVanguardChunk` | `EGVanguardInteriorGen` | `VanguardInterior` | `VanguardInterior` (4 variants) | `ProductionTest.rsl:341`, `:360`, `:382`, `:404` |

Lua side: `EGDataBuildings.lua:14`, `:35`, `:54`, `:70`, `:86`, `:102`, `:118`;
`EGDataShipVanguardChunk.lua:12`; `EGDataInteriorGen.lua:5-66`.

The multi-shape buildings differ only in outer mesh and entrance geometry, not in their production
family: `XenoBuildingInterior`, `…Interior5`, `…InteriorV`, `…InteriorT`, `…InteriorCross`,
`…InteriorCrossWide` all eventually produce `XenoBuildingWingNode*` and `XenoBuildingRoom`, and all
share `DefaultHallwayTileset`, `LightTypes`, `XenoBuildingFogTypes`, `IsDoorType "XenoDoor"`
(`XenoBuildingProductions.rsl:440-466`). Variants differ in chain shape and count
(`:469`, `:497`, `:533`, `:566`, `:599`).

`DebrisLootProductions.rsl` is a separate family with no building: `DebrisLoot( room )`
(`:69-117`) is the loot table for ship debris, invoked by the debris generator rather than an
interior **[INF — no `ProductionName` or `InteriorGenerator` in Lua names it]**.

---

## 7. Deterministic seeding

Two seeds gate generated content.

**`InteriorGenSeed`** is per building instance, created randomly at `Init` —
`math.random( 343434, 9898838 )` (`EGBuilding.lua:28`, `EGDataShipVanguardChunk.lua:52`) from C
`math.random` seeded once at game start (`GameplayMain.lua:9-13`) — then **persisted**: buffer key
`InteriorGenSeed` (`EGBuilding.lua:109`, `EGVehicle.lua:236`) and stream fields gated at >=37 for
buildings (`EGBuilding.lua:120`) and >=26 for vehicles (`EGVehicle.lua:376`). Because the seed
survives save/load, a building regenerates identically after loading **[EV]**. That is the point:
`README.txt:230` records "Bugfix: Make sure productions don't reuse production seed and end up with
identical results" **[EV]**.

**`EGRandom`** is the PRNG used inside generation and is **engine-provided** — there is no
`function EGRandom` anywhere in Lua; the nearby `EGRandomChance`, `EGRandomCubeVector` and
`EGRandomFloat` (`EGUtility.lua:44-59`) are unrelated helpers. It is called but never defined, at 29
sites, always treating it as a global returning an object with numeric methods.

Two call shapes appear:

- `EGRandom( seed )` — one stream from one seed (`EGDataPlanets.lua:1042`, `:1296`, `:1397`;
  `EGAsteroidBelt.lua:38`; `EGRobotVoice.lua:18`).
- `EGRandom( seed, index )` — a salted stream, letting one parent seed spawn many independent
  deterministic sub-streams: `EGPlanet.lua:212` `EGRandom( self.Seed, aIndex )`; `:314`
  `EGRandom( self.Seed + 427, enemyIndex )`; `:378` `EGRandom( self.Seed + 90787, aEntityIndex )`;
  `EGDataPlanets.lua:776` `EGRandom( aParentSeed, aChildSeed )`; `EGDataCharacterRobot.lua:21`
  `EGRandom( self.Seed, 29909 )`; `EGAsteroidBelt.lua:18` `EGRandom( 978980, aBucket )` **[EV]**.

Only one consumer method is visible in Lua: `aRandom:NextFloat( aFrom, aTo )`
(`EGRandomGenerator.lua:67`).

> **INFERRED:** the exact sequence is **not exposed**. Whatever algorithm sits behind `EGRandom` —
> state size, next-value transform, how a second argument salts the stream — is inside the binary.
> Nothing in Lua can reproduce a stream, and no `.rsl` file contains a seed. The same holds for how
> the engine seeds the EGSL chooser from `InteriorGenSeed`; the only observable contract is that
> identical seeds must yield identical interiors, since persistence depends on it.

## 8. Decoration placement schema (`EGDataDecorationGen.lua`)

33 `Generation.*` classes, each a plain Lua table with no validation.

**Per-class fields:** `Tags` (32 classes), `Placement` (33), plus optional light tuning — `Radius`
(6), `WallAvoidRadiusMult` (5), `WallAvoidFactor` (5), `ExcludeFactor` (5), `Parents` (3, always
`nil`), `DoorAttraction` (3) — and `BoundsExpand` (3) for meshes whose bounds are wrong
(`Generation.ScienceTank` `:402`, `Generation.XenoStation` `:413`).

**`Placement` is an array of alternative placement rules:**

| Field | Count | Meaning |
|---|---|---|
| `Parent` | 62 | attach target: `"Wall"`, `"Float"`, `"Random"`, or another tag |
| `Offset` | 27 | `EGVector` offset from parent |
| `Weight` | 19 | relative chance among alternatives |
| `Slot` | 18 | always `"Side"` — parent-relative attachment slot |
| `Rotation` / `RotationRange` | 16 / 16 | fixed rotation / random jitter |
| `Radius` | 6 | minimum spacing |
| `Priority` | 3 | ordering among alternatives |
| `Avoid` | 3 | tags to keep away from, e.g. `{ "Light" }` |

`Parent` values are tag names, which is what makes `Tags` load-bearing. `Generation.EndTable` chains:
either side of a `Bed` at ±1.5 offset, **or** fall back to `Wall` (`:97-115`). `Generation.RockMedium`
chains to `RockLarge` at three radii, then falls back to `Random` and `Wall` (`:236-272`).
`Generation.RockChild` chains only to `RockLarge` or `RockMedium` (`:274-297`) — a small object that
exists solely as a satellite.

Lights are purely tag-driven: `Tags = { "Light", "CeilingItem" }`, `Radius = 6`, and `Avoid = { "Light" }`
so lights repel each other (`:167-215`). `XenoLightLarge` raises `Radius` to 12 and `WallAvoidFactor`
to 1 (`:201-215`), keeping further from walls than the small variant — the mechanism behind
"Fix wall distances in generated interiors to reduce lights ending up behind walls" (`README.txt:227`)
**[INF but well-supported]**.

**Two genuine schema bugs**, both consequences of unvalidated plain tables:

- `Generation.ScienceTank.Tages = { "ScienceTank" }` (`:401`) — misspelled key, so the class has no
  `Tags` at all and the intended tag is never registered.
- `Generation.ThermalGel`, `Generation.XenoTurret` and `Generation.XenoWallScreen` have `Tags = { }`
  (`:480`, `:514`, `:559`) while the RSL asks for them by name (`HasDecoration( room, "ThermalGel" )`
  x3, `XenoBuildingDecorationProductions.rsl:20-25`).

That last point exposes the key unknown: whether a `HasDecoration` name is matched as a **tag**, as a
**`Generation.*` class name**, or as a free-form name handled by the engine's item registry. Names
like `HealthResource15`, `Document`, `ShipStatus` and `ProxyInteriorDebris` have no `Generation.*`
class here, which favours the third reading with the `Generation.*` tables acting as an optional
placement-hint layer **[INF]**.

## 9. Conceptual model of expansion and dressing

**1. Expansion.** The engine instantiates the top-level production named by `ProductionName`, binding
engine-supplied concepts (`interior`, `entrancePath`). For each production it picks among
same-name/same-arity alternatives by `priority` then `weight`, checks preconditions against the
accumulated fact set, then runs the body: `concept` creates fresh IDs, `produce` recurses, `let`
appends facts. Output is room concepts plus facts — not geometry.

**2. Shape.** Per room, `RoomShape` selects the most specific alternative (priority ladder 3/4/5,
`XenoMineProductions.rsl:62/82`) and emits `Radius`, `Shape`, `Height`, `Symmetry`,
`AngledCornerChance` and the `Growth*` ranges. Those drive a separate growth stage turning radius
plus growth parameters into a floor plan; `AngledCornerChance` alone shows the shape is not a simple
disc **[INF — the growth engine is not in Lua]**.

**3. Surface and ambience.** `RoomTileset` picks a tileset with a planet-type override
(`XenoMineProductions.rsl:344-356` — Morena gets `"Xeno Ice Mine"` and an ice wall pattern);
`DefaultHallwayTileset` does the same for corridors (`:326-342`); `LightTypes` and
`XenoMineFogTypes`/`XenoBuildingFogTypes` add lights and fog by weighted choice; `IsDoorType` sets
the door style.

**4. Content.** `MakeRoomEnemies` fans out into `Make{Mine,Building,Vanguard}Enemies*`, gated by
planet type and room role — an asteroid arena gets a boss, a storage room gets nothing (`priority 10`
plus empty body, `XenoMineEnemyProductions.rsl:236-240`) **[EV]**. A second pass through
`Decoration`/`Make*` productions emits `HasDecoration` facts.

**5. Placement.** The engine walks the emitted decoration facts, resolves each to a `Generation.*`
rule set, and chooses a `Placement` entry by `Weight`/`Priority`, honouring `Parent`/`Slot`/`Offset`
and rejecting candidates that violate `Avoid`/`Radius` spacing or wall clearance. Chained parents
(`EndTable`→`Bed`, `RockChild`→`RockLarge`) resolve in dependency order so a child is placed only
after its parent exists **[INF]**.

## 10. Evidence table

| Claim | Evidence | Confidence |
|---|---|---|
| Language is EGSL; no recursion, ancestry unrolled to depth 6 | `ProductionTestCore.rsl:15-73` | **[EV]** |
| Production syntax `production N(p) ... end` | `XenoMineProductions.rsl:17-31` | **[EV]** |
| `weight` is relative probability | `XenoBuildingDecorationProductions.rsl:3-15` | **[EV]** (mechanism **[INF]**) |
| `priority` is a specificity ladder | `XenoMineProductions.rsl:62`, `:82` | **[INF]** |
| `let` is both precondition and assertion | `IsXenoMine` at `:20` vs assertion `:288` | **[INF, high]** |
| `concept` declares untyped IDs; edges are positional | `XenoMineProductions.rsl:274-280` | **[EV]** |
| Overloading by name+arity | `XenoOutpostWingNode` at `:127`, `:138`, `:149` | **[EV]** |
| Graph is concepts + `IsNode(child,parent)` only; no `edge`/`door`/`node`/`light` keyword | 0 statement-leading keyword occurrences | **[EV]** |
| 49 distinct fact predicates | frequency extraction over all 10 files | **[EV]** |
| Tileset vocabulary matches Lua registrations exactly | `EGDataTilesets.lua:3-157` vs RSL values | **[EV]** |
| No Lua `.rsl` loader; interpreter is engine-side | no `rsl`/`EGSL` string in any `.lua`; §5 | **[EV] / [INF]** |
| `EGRandomGenerator.lua` is a different, flat CFG system | `EGRandomGenerator.lua:65-103`, `EGDataGenerateXenos.lua:4-13` | **[EV]** |
| `EGRandom` is engine-provided | 29 call sites, no definition | **[EV]** |
| Two-arg `EGRandom` salts a sub-stream | `EGPlanet.lua:212`, `:314`, `:378` | **[INF]** |
| `InteriorGenSeed` is persisted, so interiors regenerate | `EGBuilding.lua:28`, `:109`, `:120` | **[EV]** |
| Vanguard productions live in "ProductionTest" files | `ProductionTest.rsl:341-418` | **[EV]** |
| Decoration placements are weighted parent rules | `EGDataDecorationGen.lua:97-115`, `:236-297` | **[EV]** |
| `Tages` typo drops ScienceTank's tags | `EGDataDecorationGen.lua:401` | **[EV]** |
| Empty `Tags` vs RSL requests is an inconsistency | `:514` vs `XenoBuildingDecorationProductions.rsl:20-25` | **[INF]** |

## 11. Residual uncertainties

1. **`priority` vs `weight` interaction** — never defined; could be "first match wins" or a
   multiplier. Affects any reimplementation.
2. **`let` polarity** — which predicates are queries and which are generators is unmarked; `IsXenoMine`
   is provably both.
3. **`IsPathConnection( room, edge )`** semantics — 21 uses, no definition, no Lua reference.
4. **`IsAncestor` depth cap of 6** — deep interiors would silently lose ancestry facts; whether the
   engine has a native fallback is unknown.
5. **Decoration name resolution** — tag, class name, or engine registry (§8); determines the
   significance of the empty-`Tags` classes.
6. **`EGRandom`'s algorithm** — unexposed; deterministic generation cannot be reproduced from Lua.
7. **Which production the engine starts from for debris loot** — `DebrisLoot` has no `ProductionName`
   binding anywhere in Lua (§6).
