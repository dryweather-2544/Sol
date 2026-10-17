# Rodina 1.6.2 — Items, Weapons, Combat, Particles, Characters, Buildings (static analysis)

Source root: `Rodina.v1.6.2/Rodina.v1.6.2` (extracted). Line numbers refer to that tree.
Read-only inspection of Lua data + gameplay scripts. No executable, DLL, `.rsl`, or build tool was run.
**[EV]** = evidenced at cited line · **[INF]** = inference · **[UNK]** = engine-side, not in the tree.

---

## 0. Wiring

`EGMakeClass(fullName, superName)` (`Scripts/EGCore.lua:35`) builds a Lua class table keyed by a
dotted name (`"Items.Door"` → global `Items.Door`), subclasses by table inheritance, then registers
with the engine. Fields are plain keys set after class creation and read natively at spawn time —
no schema, no validation, so typos fail silently. **[EV]**

| Call | Role | Evidence |
|---|---|---|
| `System.Interior.RegisterEntityType(cls)` | makes a class placeable/savable in interiors + ship-layout editor | 106 calls in `EGDataItems.lua`; palette filter `EGMenuShipLayout.lua:200` |
| `System.Interior.MakeBounds(...)` / `MakeEntranceBounds(".egi")` | interior grid bounds, entrance-interior binding | `EGDataItems.lua:2074-2079` |

---

## 1. `EGDataItems.lua` — 2,079 lines, 125 classes

### 1.1 Class pattern

Every item has the same shape (`:23-34`, Barrel): `EGMakeClass("Items.X", parent)` → `Name` / optional
`DisplayName` → `MenuCategory` → `Path` (`.egm`) → `ShowInfo` → `Generation` →
`System.Interior.RegisterEntityType` → optional `Physics`, `OnGrab`, `Update`. Loot instead shares
`DebrisGrabFunction` (`:12-20`): add `FullName` to the player's count ledger, play `ItemPickup`,
destroy; classes needing a special grant override `OnCollectDebris` (`:800`, `:868`, `:943`, …). **[EV]**

### 1.2 Categories (declared)

| `MenuCategory` | n | Classes |
|---|---|---|
| `"Furniture"` | 19 + Holoscreen | Barrel 23, Bed 37, Crate 46, Desk 55, DeskChair 64, Dresser 75, EndTable 84, HousePlant 93, PilotChair 102, Rug 113, Shelves 122, ShowerHead 131, ShowerWall 139, Sink 148, Stairs2 157, StairsWide 170, StorageTable 183, StorageCloset 192, Toilet 201; Holoscreen 471 is miscategorised here |
| `"Lights"` | 4 + 2 | CeilingLight1-4 212-253; Emergency 256, Flashing 263 inherit CeilingLight1 |
| `"Machines"` | 10 | Airlock 332, AmmoniaTank 406, Archives 416, BatteryArray 428, FTL_Radio 436, Generator 463, LimnalDrive 480, PilotStation 488, Scanners 516, ShipStatus 528 |
| `"Doors"` | 1 + 7 | Door 542; DoorAngled 603, DoorAirlock 611, DoorAirlockIn 639, DoorAirlockOut 657, XenoDoor 684, XenoDoorWide 716 |
| `"Items"` / `""` | 2 / 2 | GunBlasterMounted 1175, FireExtinguisherWall 1251; XenoDoor 687, XenoDoorWide 720 (deliberately palette-hidden) |

~87 classes declare no category: loot, gibs, rocks, xeno machinery, ship hardware — spawned, not
placed. 125 classes vs 106 registrations because logic/pickup classes are never registered
(`Items.FireExtinguisher:1315`, `Items.Blaster:747`). **[EV]**

### 1.3 Classes, grouped

| Group | Classes (line) | Purpose |
|---|---|---|
| Set dressing | the 19 Furniture classes | non-interactive; each maps to a `Generation.*` placement rule (`DataGeneration/EGDataDecorationGen.lua:3-566`; e.g. `Generation.DeskChair` parents to `Desk` with a rotation range) |
| Chairs / lighting | DeskChair 64, PilotChair 102, Toilet 201; CeilingLight1-4 212-253, Emergency 256, Flashing 263, XenoLight1 313, XenoLightLarge 322 | `IsChair` (+`ChairBackwards` on all three); `LightAddon`, Flashing strobes via `Update` (`:267-310`) |
| Ship machines | Airlock 332, Archives 416, FTL_Radio 436, PilotStation 488, Scanners 516, ShipStatus 528, Holoscreen 471, LimnalDrive 480, Generator 463, BatteryArray 428 | flavor + menu launchers (§1.4) |
| Doors / props | Door 542, DoorAngled 603, DoorAirlock 611, In 639, Out 657, XenoDoor 684, XenoDoorWide 716; AmmoniaTank 406, ShowerHead 131, ShowerWall 139, ShipWalkway 1148, DebrisWall1 1065, Stairs 157/170, Storage 183/192 | part-translation animation + autoclose; mesh/box collision |
| Story pickups | StoryDebris1 762, StoryDataVault 767, StoryFabricator 772, StoryDebris2 777, StoryScreen 782, StoryBosonicSubstrate 787, Diaconium 1020, Document 924, Communication 961, FinalStoryLine 993 | share base `GenericStoryUpgrade` 753 (`DebrisNoRotate`, `Generation.Loot`, `OnGrab=DebrisGrabFunction`) |
| Equipment pickups | GrappleHook 792, GunLaser 805, TargetScope 823, HeadlampFlashlight 841 | `OnCollectDebris` inserts the *runtime* class (`EGGrappleHook`, `EGGunLaser`, `EGTargetScope`, `EGHeadlampFlashlight`) into the item component (`:801`, `:819`, `:837`, `:855`) |
| Upgrades / ammo | Blaster 747, CruiseEngine 859, Heater 883, AcidShield 902, PlanetScanners 878; AmmoCrate 1073, MissileCrate1 1094, MissileCrate 1101, RingBlasterCrate 1108, HailBlasterCrate 1116, MegaBlasterCrate 1124 | progression flags + story prompts; `WeaponName`+`WeaponCount`, also `Discover`s the weapon (`:1082-1091`) |
| Wall racks / tool | GunBlasterMounted 1175, Repeating 1235, Rocket 1243, FireExtinguisherWall 1251, FireExtinguisher 1315 | 60 s respawn, hidden while collected, persisted `CollectedTimer`; the tool carries `AmmoType`, `PlayerHoldLocation`, `ParticlePos`, `CanBeInventoryDestroyed` |
| Consumables | GenericResource 1407, RocketAmmo 1461, HealthResource5/15/50 1481-1506, FirePowerup 1509 | auto-pickup at 2 m (`:1421`); heal + count + optional `PowerupClass` |
| Gibs / vehicles | ExplosionDebrisGeneric 1540, GunMissileDebris 1565, PlasmaChargedDebris 1569, ProxyInteriorDebris 1603; GravBike 1576, EGXenoJetpack 1584 | debris motion, lifetime 0.5-2 s; bike `EntityType="Actor"`, `IsChair` |
| Rocks | Rock1/2/3 1608/1635/1663 + Large/Small 1623-1684 + Ice 1691-1727 | 27 classes from 3 meshes (scale 1.7 / 0.35 variants) |
| Xeno machinery | XenoBigScreen 1733, XenoWallScreen 1749, XenoControlStation 1765, ThermalGel 1780, XenoCrate 1818, XenoTurret 1833, XenoTurretGun 1892, TurretCeiling 1984, XenoShieldGenerator 1996, Gimbal 2032, XenoScienceTank 2058 | destructible/functional props (§1.4) |

### 1.4 Interactive items

There is no interface — "does the table have `OnGrab`?" is the contract. ACTIVATE is dispatched blind
(`EGCharacterActor.lua:339-342` calls `lookingAt:OnGrab(self)`); hover naming uses `ShowInfo` →
`GetDisplayName()` (`:388-393`); the HUD separately calls `GetTargetInfo()` (`EGMenuHUD.lua:1625-1628`).

| Item | Line | Behavior | Notable |
|---|---|---|---|
| Airlock computer | 332 | opens `EGMenuAirlock {Vehicle, Computer}` | per-instance flags `CloseAirlock/OpenAirlockIn/OpenAirlockOut/AirPressure` (`:346-350`) mutated by the doors |
| Archives / Scanners / Operations | 416 / 516 / 528 | open `EGMenuArchives` / `EGMenuScanners` / `EGMenuOperations` | `PlanetScanners` 878 inherits Scanners wholesale; Operations sets `Generation.Operations` |
| FTL Radio | 436 | opens `EGMenuRadio` | `Update` polls 4 doc ids and repeats `FTLRadioIncoming` + `AttachParticles("FTL Signal",…)` while unread (`:449-460`) |
| Pilot Station | 488 | `StartPilotingVehicle` + autosave | refuses if ship dead (`:498`) or any door open (`:504`); sets `AllowFirstPersonPilot` (`:509`) |
| Door / all variants | 542 | `OpenDoor(actor)` | `OpenForActor` range-gates at `ActorOpenLimit` (`:585-592`) |
| DoorAirlockIn/Out | 639/657 | flips the computer's in/out flags; Out also calls `vehicleOwner:OnOpenAirlock()` when fully closed (`:673-679`) | finds the computer by name `"Airlock Computer"` (`:650`) |
| GunBlasterMounted / FireExtinguisherWall | 1175 / 1251 | add weapon or tool to the item component; wall tool also sets count to 100 (`:1290`) | 60 s `CollectedTimer`, persisted via `Encode/Decode` |
| XenoTurret / TurretGun | 1833 / 1892 | no `OnGrab`; base spawns its gun at `GunOffset` (`:1862-1865`) and forwards damage (`:1870`) | gun `MaxHealth=40`, room-triggered burst (`:1930-1945`), `BlowUp` → `RocketExplosion` (`:1974`) |
| XenoShieldGenerator / ThermalGel | 1996 / 1780 | — | gimbal + injected `ShieldTypeName` shield (`:2008-2026`); gel `MaxHealth=8`, death → `ThermalGelExplosion` (`:1800-1808`) |
| GravBike | 1576 | mount | engine `ForceSitInChair` (`EGGravBike.lua:94`) |

### 1.5 Fields that matter

| Field | Meaning | Evidence |
|---|---|---|
| `ShowInfo` | look-at label + "Press <ACTIVATE>" hint | `EGCharacterActor.lua:388-393` |
| `Path` / `Scale` / `GeometryScale` / `Offset3D` | model, per-axis scale/offset | `:795-796`, `:607` |
| `Physics` | `ShapeType` (Box/Convex/Mesh/Sphere/Ragdoll), `ExtentLow/High`, `Radius`, `Path`, `MotionType`, `Mass`, `Friction`, `Restitution` | Door `:560-565`; walkway `EG_MOTION_ANIMATED_WALKWAY` `:1154`; gibs `EG_MOTION_DEBRIS` `:1544` |
| `Generation` / `LightAddon` | decor placement rule (33 distinct values); `{Target, Type="Point", Color, Radius}` or a string naming an existing light part | `EGDataDecorationGen.lua`; `:217`, `:1133` |
| `IsChair` / `ChairBackwards` / `ChairTypeSidesOnly` | engine seating; backwards = faces −Y | `:69`, `EGGravBike.lua:8-9` |
| `IsDoor` / `IsAirlockDoor` | AI pathing; airlock doors excluded from NPC door use | `EGCharBehaviorWander.lua:253`, `:272` |
| `Autoclose` / `ActorOpenLimit` / `ActorAutoCloseDist` | door policy | `:553`, `:557-558`, `:642` |
| `DoorSize` / `OpenSpeed` / `OpenMult` | 1 = single, 2 = bulkhead; rate and travel multiplier | `:550-552`, `:616-618` |
| `DepressurizeParticles` / `OpenSound` / `CloseSound` | room-venting VFX, one-shot audio | `:554-556`, `:622` |
| `LockEditorPlacement` / `IgnoreNPCVision` | hidden from palette; invisible to NPC perception | `:338`, `:219`; `EGMenuShipLayout.lua:200` |
| `PersistenceProfile` / `CanBeInventoryDestroyed` / `HACKTargetable` / `DebrisNoRotate` | save-policy bucket, destroy action, ship targetability, no loot tumble | `:1412`, `:1324`, `:1580`, `:757` |

---

## 2. Inventory & equipment

### 2.1 Two ledgers (key architectural seam)

| Ledger | Key | API | Holds |
|---|---|---|---|
| Item component (`EGGetInventory(engine)`) | class name + grid coords | `Add`, `AddEquipment`, `GetItem`, `GetItems(ctx)`, `Place`, `RemoveItem`, `GetCanBePlaced` | physical placeable gear; drives UI and slots |
| `PlayerInfo` counts | plain string (`"Items.RocketAmmo"`, `"MainStoryline"`) | `GetInventoryCount`, `AddInventoryItem`, `SetInventoryCount`, `SetInventoryMinimum` | ammo, consumables, documents, story flags |

`EGPlayerInfo.lua:56-80`; `EGMenuInventory.lua:180-224`; starting loadout populates both
(`GameplayMain.lua:41-55`); some flows must check both (`EGDataItems.lua:1282-1290`). **[EV]**

### 2.2 Spatial inventory

The item component is a **grid** in two contexts, `"INVENTORY"` (backpack) and `"EQUIPMENT"` (rig),
sized by the engine (`GetWidth/GetHeight/GetMinX/GetMinY/GetMaxX/GetMaxY`, `EGMenuInventory.lua:181-182`,
`236-237`, `284-290`). Items carry `Width`/`Height` in cells, `CoordX`/`CoordY`, `ID`, `TypeName`
(`:513-527`). Drag-drop quantizes to 30 px cells and scans a 3×3 neighbourhood for the nearest legal
slot (`:40-87`), legality via `inventory:GetCanBePlaced(...)` (`:591`). Feedback is color-only: yellow
= installed-but-inactive, red = illegal (`:532-547`, `:592-596`). **[EV]**

### 2.3 Equipment slots

No enum in Lua; slots are bare strings:

| Slot | Contents | Evidence |
|---|---|---|
| `HEAD` | scopes/cameras (TargetScope, Headlamp) | `EGMenuHUDEquipment.lua:60`; camera→HEAD `EGMenuQuickSelection.lua:61-63` |
| `WEAPON` | right hand | `:61` |
| `TOOL` | left hand (extinguisher, grapple) | `:62` |
| `BODY` | passive suit upgrades | `EGMenuQuickSelection.lua:70-71` |

Native `PlayerEquipment` API called from Lua: `GetEquipment(slot)`, `GetUsedEquipmentID(slot)`,
`UseEquipment(id, slot)` (`EGMenuQuickSelection.lua:318`), `IsEquipmentActive(id)`
(`EGMenuInventory.lua:539`), `IsEquipmentTypeActive` / `IsUsingEquipmentType(class)`
(`EGDataProgress.lua:333,342`). Entry `ItemType` is the item's class full name (`EGMenuHUD.lua:1270`).
Equipping does not consume; a separate active flag toggles. **[EV]**

### 2.4 Held items

`HoldingData` on the *character* declares slots and attach transforms; the *item* declares its offset
inside the slot. Player: `WEAPON` and `TOOL` both parented to `"Player Camera"`, mirrored ±0.175 X
(`EGPlayer.lua:25-29`). Xeno: `RIGHT`/`LEFT` at ±0.2 X, Z 1.5 (`EGDataCharacterXeno.lua:22-26`). Item
side: `PlayerHoldLocation`, `PlayerHoldRotation`, `ParticlePos` (`EGDataWeapons.lua:254-256`, `290-292`).
`SetHeldItem(type, slot, id)` → native `ItemHolding` (`EGCharacterActor.lua:540-547`), read back via
`GetHeldType`/`GetHeldItem` (`:532-537`, `:584-588`), re-parented each full update by
`PositionHeldItem` (`:94`, `:736`); xenos recompute from the right-arm module + behavior wobble every
frame (`EGDataCharacterXeno.lua:238-295`, `298-324`). A character is "using" an item only if its
behavior says so — `IsUsingHeldItem` delegates to `CurrentBehavior:IsUsingHeldItem(heldType, useType)`
(`EGCharacterActor.lua:688-720`), implemented from `self.FireWeapon` / `self.ChargeWeapon`
(`EGCharBehaviorXenoCombat.lua:457-465`). That single hook unifies player and AI weapon code. **[EV]**

### 2.5 Ammo and powerups

Ammo lives in the count ledger under the weapon's `AmmoType` (`EGGunMissileBlaster` → `"Items.RocketAmmo"`,
`EGDataWeapons.lua:543`); the HUD reads `tool.AmmoType` → `GetInventoryCount` (`EGMenuHUDEquipment.lua:73-89`).
Ammo is debited **only for the player-controlled actor** (`EGWeaponGun.lua:192-205`); zero ammo disables
fire and charge (`:64-68`) and zeroes the gun's emissive ready-factor (`EGDataWeapons.lua:563-565`).
Tools reuse the weapon path (`EGDataItems.lua:1327-1348`); grapple and laser are separate native
components (`Components = {"GrappleHook"}` / `{"LaserWeapon"}`, `EGDataWeapons.lua:284`, `:307`).
Powerups are a 10-line data file — `EGFirePowerup {HUDColor, Time=30, HealthBoost=25,
WeaponType="EGGunFirePowerup"}` (`EGDataPowerups.lua:4-9`) — applied by setting a timer, healing, and
clearing the right hand (`EGPlayerInfo.lua:223-245`). `GetPowerupWeapon()` exists (`:266`) but its only
caller is commented out (`EGCharacterActor.lua:565-567`), so substitution is native. **[EV]/[INF]**

---

## 3. Weapons — `EGDataWeapons.lua`, 42 classes, 993 lines

### 3.1 Runtime hierarchy

`EGWorldObject` → `EGWeaponGun` (held model that spawns projectiles, `EGWeaponGun.lua:3`),
`EGWeaponBullet` (fast projectile, `EGWeaponBullet.lua:3`), `EGWeaponMissile` (homing,
`EGWeaponMissile.lua:3`), `EGProjectile` (slow body with optional explosion, `EGProjectile.lua:3`;
subclassed by `EGProjectileBomb` / `EGProjectileFireball`). A gun is *not* a projectile.

### 3.2 Field schema

| Field | Meaning | Example |
|---|---|---|
| `Damage` / `ChargeDamage` / `ChargeFactor` / `ChargedSize` | base and fully-charged damage; 0-1 charge scales both damage and model scale | `:10`; `EGProjectile.lua:39-43`, `:199-202` |
| `Speed`, `Lifetime`, `Range`, `InheritOwnerVelocity` | kinematics; `Range` defaults to infinity; owner velocity added to muzzle velocity | `EGProjectile.lua:9-13`, `:527`, `:66-71` |
| `CooldownTime` / `SoundCooldownTime` / `SpreadX` / `SpreadY` | shot pacing, separate audio gate, random cone applied as ExtraRotation | `:12-14`; `EGWeaponGun.lua:19-20`, `:180-182` |
| `NumProjectiles` / `ProjectileClassname` → `ProjectileClass` | pellets per shot and what to spawn | `:7`, `:233`; resolved `EGWeaponGun.lua:48` |
| `BarrelTypeName` | owner table of barrel markers (`GunBarrels`, `MissileBarrel`) | `EGWeaponBullet.lua:11`; `EGShipPlayer.lua:40-41`; `EGVehicle.lua:1698` |
| `AmmoType` / `FireStyle` | count-ledger key (`nil` = unlimited); `SINGLE SHOT` / `CONTINUOUS` / `CHARGE` / `CHARGE BURST` / `BURST` | `:242` vs `:543`; `EGWeaponGun.lua:23` |
| `FlareParticleName`, `FlareTime`, `ChargeParticleName`, `ChargeBegin/EndTime`, `FireSound`, `ChargeSound`, `ChargeFireSound` | muzzle/charge VFX timing and audio ids | `:234-240` |
| `ImpactParticles`, `ChargedImpactParticles`, `ImpactSound`, `ImpactSoundDamage` | impact VFX/SFX split by "did it hurt" | `EGProjectile.lua:16-19`, `:122-128` |
| `ExplosionType` / `ExplosionTypeCharged`, `ImpactDebrisName` / `…Count` (+Charged) | engine "physics effect" name; gib class and count | `:589-591`; `EGExplosion.lua:18`, `EGProjectile.lua:146-177` |
| `IsPlasma` / `IsMagneticShield` / `PhysicsWhileHeld` | reflect rules; held shield | `EGWeaponBullet.lua:71`; `:646-653` |
| `CanBeDefault` / `AltWeapon` / `InventoryType` / `Palette` | default-slot eligibility, secondary fire, icon, skin | `:231`, `:243`, `:245`, `:551` |

### 3.3 Hitscan vs projectile

**No hitscan exists.** `EGWeaponBullet` is a projectile with a very large collision radius: speed
1,000-10,000, `Physics.Radius` 20-100, lifetime 2-5 s (`EGDataWeapons.lua:8-11`; `EGWeaponBullet.lua:8-21`).
Three archetypes: **bullet** (fast, no gravity, reflects off `IsMagneticShield`, `EGWeaponBullet.lua:68-76`);
**`EGProjectile`** (slow 15-200, optional explosion, charge scaling, impact gibs, plus `ShipMode`
multiplying scale ×15 and speed ×30 when the gunner's target is a `Vehicle`, `EGProjectile.lua:46-55`,
gated at `EGWeaponGun.lua:172`); **`EGWeaponMissile`** (homing: `TargetRange=100000`,
`ClosingRadius0/1=600/1000`, `ClosingSpeedOffset`, `RotationSpeed=1.25`, `MinSpeed=300`, lifetime pinned
to 30 s, `EGWeaponMissile.lua:12-24`, `:44`).

### 3.4 Firing pipeline (`EGWeaponGun.lua:52-160`)

1. Decrement cooldown and sound cooldown, normalized by their periods (`:54-56`).
2. Ask the owner if it is firing/charging (`:58-62`); gate on ammo (`:64-68`).
3. `FireStyle` state machine (`:70-116`): `BURST` latches; `CHARGE` fires on release only past
   `ChargeBeginTime`; `CHARGE BURST` converts a long hold into a burst; `CONTINUOUS` fires while the
   alt input is held; `SINGLE SHOT` requires a release between shots.
4. Require `IsValidWeaponPos(weaponEngine, ParticlePos)` before any VFX or spawn (`:129`).
5. `Fire()` spawns `ProjectileCount` projectiles, each with its own random `ExtraRotation`,
   `Position = ParticlePos`, `OwnerEntity = owner.Engine`, as a sibling of the gun (`:178-190`).
6. Player only: charge-scaled camera shake and ammo decrement (`:192-205`).
7. Flare emitter decays via `FlareCountdown`; charge emitter intensity = normalized charge and the
   charge sound pitch-bends with it (`:140-158`).

### 3.5 Ownership and team

`OwnerID` is copied from the spawning actor (`EGProjectile.lua:59-62`, `EGWeaponBullet.lua:24-29`).
Friendly fire is a **hardcoded two-team check**: a projectile whose owner is not the player passes
through any `CharacterActor` that is also not the player (`EGProjectile.lua:106-112`). There is no team
field — only "player vs not-player" — so xeno shots cannot hurt xenos. Magnetic shields reflect
`IsPlasma` projectiles (`:114-116`; `EGWeaponBullet.lua:71-73`) and flash via `OnReflect`
(`EGDataBuildings.lua:172-174`). Missile targeting branches on owner: if the owner *is* the player
vehicle it uses the current target or an angle/distance heuristic over local vehicles, otherwise it
simply targets the player (`EGWeaponMissile.lua:94-147`, esp. `:139-141`).

### 3.6 AI vs player

| Aspect | Player | AI |
|---|---|---|
| Trigger | input actions via behavior | `FireWeapon`/`ChargeWeapon` flags (`EGCharBehaviorXenoCombat.lua:457-465`) |
| Ammo | decremented, gated at 0 | ignored (`EGWeaponGun.lua:192-205`) |
| Camera shake | yes, charge-scaled (`:196-200`) | none |
| Target | reticle / `gGame:GetTargetEntity()` | behavior `GetFocusEntity()`; turret uses `PredictLocalVectorTo` (`EGDataItems.lua:1948`) |
| Weapon | inventory + quick wheel | `WeaponType` on the character class (`EGDataCharacterXeno.lua:10`) |

`EGVehicle:FireWeapon`'s body is entirely commented out (`EGVehicle.lua:1661-1729`) — ship guns are
engine-driven and `BarrelTypeName` survives only as data. **[EV]**

---

## 4. Particles — `EGDataParticles.lua`, 4,973 lines, 104 materials

### 4.1 Schema

One top-level `System.CreateParticleMaterial { … }` per effect. No class, no registry — `Name` *is* the
id, resolved by string from gameplay.

```
CreateParticleMaterial {
  Name, Loop, BlendStyle("Add"|"Alpha"), OrientationType, MaxParticles, Recycle,
  DecayRate, DecayDelay, EmitBloom, PrecreationTime,
  Styles = { { Rate, Size, Offset, VelocityBase, VelocityRange,
               VelocityNormalBase, VelocityNormalRange,
               Acceleration, AccelerationNormal, AccelerationGravity,
               VelocityGravity, Drag, DragThreshold, Yaw, Pitch, Lifetime,
               Keys = { {Time, Color, Alpha, Size}, … } }, … }
}
```

| Layer | Fields | Stats |
|---|---|---|
| Material | `Name`, `Loop`, `BlendStyle`, `OrientationType`, `MaxParticles`, `Recycle`, `DecayRate`, `DecayDelay`, `EmitBloom`, `PrecreationTime` | all 104 declare `Loop` (79 true / 25 false); 13 set `MaxParticles`; 56 `"Add"`, 17 `"Alpha"`, rest default |
| Style (emitter) | `Rate` (particles/sec), `Size`, `Offset`, `Lifetime`, velocity/acceleration terms, `Yaw`/`Pitch` jitter | 100 materials have exactly one style; 4 have two (`Volcano`, `ScoutEngine`, `BattleshipEngine`, `FTL Radio Signal`) |
| Key (over lifetime) | `Time` 0-1, `Color`, `Alpha`, `Size` | 2-5 keys per style (313 keys across 108 styles ≈ 2.9) |

`OrientationType`: `…_LOCAL` (26), `…_WORLD_ROTATION` (51), `…_WORLD` (17). **No `Texture` field exists
anywhere**, and none of the 89 images in `Data/Textures` is a particle atlas — the sprite is
engine-supplied, likely `white.png` or a built-in soft billboard. **[EV]/[INF]** `FogMult` default 0.66
is documented only in a file comment (`:4`). **[EV]**

### 4.2 Named effects, grouped (all 104)

| Category | Names |
|---|---|
| Environment / air | `Fire`, `VolcanoSmoke`, `Volcano`, `Sparks`, `Air`, `Smoke`, `Contrail{,2,3}`, `Starfire`, `VelesWind`, `AirlockAir`, `AirlockDoorAir`, `RoomAirDepressurize{,Big}`, `DockAir{,Down}` |
| Ship engines / drive | `Wing`, `CruiseEngineMain/Small/Inertia`, `CombatEngineMain/Small`, `MissileEngine`, `ScoutEngine`, `BettleshipEngine` (sic); `Limnal Startup Ring`, `LimnalShipBlur`, `Limnal Drive`, `Limnal Drive Air`, `Limnal Pink Air` |
| Atmosphere entry | `AtmosphereEntry`, `AtmosphereShockwave`, `…Cockpit`, `…Battleship`, `Veles/Morena/ZoricaAtmosphereDamage` |
| Explosions / impacts | `MissileExplosion`, `MissileDebris`, `ShipExplosion{,Continuous,ContinuousLarge,ContinuousHuge}`, `ShipDebris`, `GunMissileExplosion`, `XenoBombExplosion`, `ThermalGelExplosion`, `GroundPoundExplosion`; `BlasterImpact`, `RingBlasterImpact`, `MegaBlasterImpact`, `ShipImpact{,Crash}`, `ImpactDust{,Large}`, `GunBlasterImpact{,Charged,ChargedImpactDebris}`, `XenoBlasterImpact{,Charged}`, `IncineratorImpact`, `Xeno{Replete,Soldier1,Poacher}Impact`, `FireExtinguishImpact`, `LaserGunImpact`, `FirePowerupImpact` |
| Muzzle / charge | `GunFlare`, `GunBlasterFlare`, `GunBlasterCharge`, `XenoBlasterFlare`, `XenoBlasterCharge`, `IncineratorFlare`, `Xeno{Poacher,Replete,Soldier1}Flare`, `GunMissileFlare`, `GrappleHookFlare` |
| Projectile bodies | `GunBlaster`, `XenoBlaster`, `XenoReplete`, `XenoSoldier1`, `ShipBlasterPlasma`, `Laserblaster`, `Megablaster`, `FirePowerupProjectile`, `XenoPoacherProjectile{,Trail}`, `GunMissile{,Engine,Trail,DebrisTrail}`, `IncineratorBomb`, `XenoBombFuse`, `Missile Trail`, `XenoJetpack`, `XenoFlierMissile{Engine,Trail}` |
| Firefighting / signals | `FireExtinguishProjectile`, `ExtinguishLinger`, `FTL Radio Signal`, `FlareShipSignal`, `XenoDeath` |

### 4.3 How code requests them

`Engine:AttachParticles( slot, materialName, amount, localPos, localDir )` — 118 call sites; argument 2
is a `Name` from this file. `slot` is a *handle*: re-driving the same slot each frame updates one live
emitter while distinct slots stack (`EGDataShipPlayer.lua:383-406` drives 15 for one ship); `""` creates
an unnamed one-shot (`EGPlanet.lua:792`); `amount` is a 0-1 intensity routinely used as a fade
(`1 - time` at `EGDataItems.lua:1560`); position/direction are in host space and the direction seeds
`VelocityNormal*`. Densest users: `EGDataShipPlayer.lua` (28), `EGDataWeapons.lua` (20),
`EGDataShipBattleship.lua` (14), `EGVehicle.lua` (11). **[EV]**

---

## 5. Characters: bodies, xeno and robot

### 5.1 Assembly model

Characters never build themselves in Lua. They return `GetModuleEntities()` — an ordered list of
`{Name, Class, Parent, Slot, GeometryScale, Scale, Palette}` — and native code instantiates each part
onto the named parent at the *slot transform declared on the part class*. Data side:
`EGDataCharacterXeno.lua:38-58`, `EGDataCharacterRobot.lua:19-66`, plus the archetypes
`EGDataXeno{Trooper:27, Scrapper:32, Replete:31, Incinerator:64, Poacher:30, Jetpack:81, Helmetless:8}`.
Slot transforms live on the part: `TorsoPos/TorsoSlot`, `NeckSlot`, `HeadSlot`, `EyeLeft/Middle/RightSlot`,
`LegRightSlot`, `ArmRightSlot`, `BackpackSlot`, `GogglesSlot`, each `{Pos, Rotate}`
(`EGDataBodyParts.lua:9-12`, `29-30`, `63-64`, `81-86`, `173-175`, `204-207`, `244-246`). Parts remain
addressable via `GetChildModule("EyeRight")` (`EGRobotBody.lua:228-229`) and
`GetChildEntity("ArmRight")` (`EGDataCharacterXeno.lua:240`). **[EV]**

### 5.2 Part registries

| Registry | Add / Get | Selection |
|---|---|---|
| `EGRobotPartList` | keyed by `BodyPartType`; `GetPart(type, seed)` = `seed mod count` (`EGRobotBody.lua:8-28`) | **deterministic from seed** |
| `EGXenoPartList` | same shape; `GetPart(type)` uses `math.random` (`EGXenoBody.lua:7-28`) | **global random**, not per-character |

Robot types: `Base`, `Body`, `Neck`, `Head`, `Eyes`, `EyeSingle` (`EGRobotBody.lua:85-204`). Xeno types:
`Pelvis`, `Torso`, `Head`, `Leg{Left,Right}`, `Arm{Left,Right}`, `Eyes`, `Goggle` (`EGXenoBody.lua:35-120`;
`EGDataBodyParts.lua:170-266`). Right-side limbs are `MakeModelMirror(..., "X")` of the left mesh
(`EGDataBodyParts.lua:192`, `:231`); armour variants subclass the bare part and swap only `Path`
(`:184-187`, `:210-213`, `:250-253`).

### 5.3 Variation per character

- **Robot**: derives five sub-seeds plus a 20 % bool from `EGRandom(self.Seed, 29909)`, picks each part
  by seed, and chooses a single mid-eye or a left/right pair (`EGDataCharacterRobot.lua:21-64`); also
  randomizes `Scale` 0.666-1.1 (`:105`), which pitches the voice (`:113`).
- **Xeno**: fixed armour loadout per archetype with optional width/height knobs (`HeadSize`,
  `PelvisWidth`, `TorsoWidth`, `ArmWidth`, `LegWidth`) feeding per-part `GeometryScale`
  (`EGDataCharacterXeno.lua:40-56`); `Init` reseeds `math.random(100000)` (`:97`).

### 5.4 Class tree and AI selection

```
EGCharacterActor   CharacterPhysics, HoldingData, Components={ItemHolding}
├─ EGPlayer         MaxHealth 100, Components += Inventory/PlayerEquipment/PlayerEnergy/AutoAim   EGPlayer.lua:3-11
├─ EGRobotCharacter MaxHealth 15, IsRobot,  Behavior=EGCharBehaviorWander                        EGDataCharacterRobot.lua:3-16
└─ EGXenoCharacter  MaxHealth 20, IsEnemy,  Behavior=EGCharBehaviorXenoCombat, Weapon=EGGunXenoBlaster
   ├─ XenoSoldier1/2/3  15/20/35     EGDataXenoSoldier.lua:3-38      ├─ XenoIncinerator 55   EGDataXenoIncinerator.lua:3-26
   ├─ XenoTrooper       25           EGDataXenoTrooper.lua:3-24      ├─ XenoPoacher     50   EGDataXenoPoacher.lua:3-26
   ├─ XenoScrapper      50           EGDataXenoScrapper.lua:3-27     ├─ XenoFlier       40   EGDataXenoJetpack.lua:3-99
   ├─ XenoReplete       10           EGDataXenoReplete.lua:3-27      └─ XenoHelmetless  —    EGDataXenoHelmetless.lua:3-27
```

AI selection is two string fields on the character: `BehviorTypes = {Wander = <behavior>}` (typo is in
the source) and `WeaponType` (`EGDataCharacterXeno.lua:10`, `:16-19`). A behavior may be a table
reference (`EGCharBehaviorXenoCombat`, `:18`) or a string (`"EGCharBehaviorXenoCombatSoldier1"`,
`EGDataXenoSoldier.lua:12`) — both work. Group composition lives separately in grammar data
(`EGDataGenerateXenos.lua:3-73`: `XenoJarilo`, `XenoPerun`, `XenoMorena`, `XenoVeles`, …).

### 5.5 Health, hit zones, loot, voice

- **No per-part health, no hit zones.** Damage lands on the actor: `EGActor:DamageHealth` applies
  difficulty scaling for the player only, sets `DamageTimer`, and notifies the behavior
  (`EGActor.lua:142-172`). Body parts are visual/animation only; destructible *machines* implement their
  own `DamageHealth` (`EGDataItems.lua:1811`, `:1870`, `:1960`). **[EV]**
- **Death**: 0.2 s `XenoDeath` particles, then destruction plus loot with a small random impulse
  (`EGCharacterActor.lua:104-129`).
- **Loot** = weighted grammar generators: `LootType` names an `EGMakeGenerator` block whose
  `Expressions` are `{weight, {class names…}}` (`EGDataGenerateLoot.lua:3-110`; consumed
  `EGCharacterActor.lua:112-116`). Tables may reference other tables (`LootIncinerator` →
  `LootHealth15`), one nesting level deep.
- **Voice**: `EGXenoVoice`/`EGRobotVoice` built from `{Seed, Scale}` where scale derives from body scale
  (`EGDataCharacterXeno.lua:104-108`). `Speak(type, phrase)` hashes the phrase into a seed, generates a
  phrase via `EGAudioGenerateRobot{Chatter,Love,Panic,Music}`, applies the voice, and plays the
  `"Robot Voice"` sound with keyed parameters (`:132-151`). Xenos use the *same* robot generators —
  their speech is procedural, not recorded. **[EV]**

---

## 6. Buildings — `EGDataBuildings.lua`, 179 lines, 8 + 4 classes

| Class | Line | Exterior | Interior generator | Entrance | Flatten inner/outer |
|---|---|---|---|---|---|
| `XenoMine` | 5 | `XenoBuildings.Mine.egm` | `EGXenoOutpostInteriorGen` | `OutpostEntrance.egi` (backup `…2x3.egi`) | 15 / 150 |
| `XenoMineIce` | 24 | inherits | inherits | `OutpostEntranceIce.egi` + `XenoMineIcePalette` | inherits |
| `XenoBuilding3x3` | 29 | `Building3x3.egm` | `EGXenoBuildingInteriorGen` | `XenoBuildingEntrance.egi` | 60 / 350 |
| `…5x5` / `…T` | 52 / 68 | `Building5x5.egm` / `BuildingT.egm` | `…Gen5x5` / `…GenT` | inherits | 100 / 350; 150 / 350 |
| `…Cross` / `…CrossWide` | 84 / 100 | `BuildingCross.egm` / `…CrossWide.egm` | `…GenCross` / `…GenCrossWide` | inherits | 150 / 350 |
| `…V` | 116 | `BuildingV.egm` | `…GenV` | inherits | 200 / 350 |
| `EGShieldMagnetic` (+`100/150/200`) | 132, 160-169 | `MagneticShield.egm` | — | — | — |

**Contract** (`EGBuilding.lua`): `Path` exterior; `Physics` mesh with `MotionType="EG_MOTION_DRIVEN_LOCKED"`
(`:18-22`); `Components={"Building","FlattenTerrain"}` (`:23`); `EntrancePath` / `EntrancePathBackupSize`
for the airlock-side `.egi` (`:9-10`); `InteriorGenerator` + `InteriorGenSeed` (`:8`, `:11`);
`ShowExteriorWhileInside` (`:14`); `CollectInteriorPastEntrance` (`EGDataBuildings.lua:18`);
`FlattenTerrainInner/OuterRadius` (full flatten inside, blend outside, `:15-16`); `IndicatorName` +
`IndicatorDistLow/High` icon fade (`:9-11`, consumed `EGBuilding.lua:47-54`); `ShieldTypeName`
(`EGDataBuildings.lua:40`, used `EGDataItems.lua:2019`); `HACKTargetable`; `XenoCount` persisted census.

**Seed handling.** `EGBuilding:Init` *overwrites* the class default with `math.random(343434, 9898838)`
(`EGBuilding.lua:26-29`), so the authored `InteriorGenSeed = 0` only matters when a caller sets one
explicitly — e.g. the console helper `MakeBuildingClass` assigns `object.InteriorGenSeed = aSeed`
(`GameplayMain.lua:296-303`); load restores the saved seed (`EGBuilding.lua:107-122`). Reproducibility is
therefore per-instance and lazy, not positional. **[EV]**

**Interior generators** are tiny data classes: `ProductionName` (which `.rsl` production set runs) plus
`EntranceAgent {Coord, SoftEntranceCoords}` telling generation where to leave a doorway
(`DataGeneration/EGDataInteriorGen.lua:3-66`); the five variants differ only by `ProductionName`.
**Xeno census** is not a generator field: every frame `EGGame:CountXenosInInterior` walks the interior's
actors, counts `IsEnemy`, and pushes the number to `interiorOwner:OnCountXenos` (`EGGame.lua:124-139`);
`EGBuilding:GetTargetInfo` renders "Status: N Xenos" / "Cleared" (`EGBuilding.lua:96-104`) — cleared is
derived, never stored. **[EV]** Shields are separate child entities scaled 100/150/200 with
`MotionType="EG_MOTION_SHIELD"`, a pulsing `Update`, and an `OnReflect` flash reset
(`EGDataBuildings.lua:132-178`).

---

## 7. Evidence table

| # | Finding | File:line | Status |
|---|---|---|---|
| 1 | Item classes are plain tables; no schema or validation; 125 classes vs 106 registrations | `EGCore.lua:35`; `EGDataItems.lua:23-34` | CONFIRMED |
| 2 | Interaction == presence of `OnGrab`; ACTIVATE dispatched blind; `ShowInfo` drives label + hint | `EGCharacterActor.lua:339-342`, `:388-393` | CONFIRMED |
| 3 | Chairs seated by native code; Lua only sets `IsChair` | `EGGravBike.lua:58-96` | CONFIRMED (call) / INFERRED (all chairs) |
| 4 | Two ledgers: class-items vs string-counts | `EGMenuInventory.lua:180-224`; `EGPlayerInfo.lua:56-80` | CONFIRMED |
| 5 | Inventory is a 2-context spatial grid with `Place`/`GetCanBePlaced` | `EGMenuInventory.lua:281-410` | CONFIRMED |
| 6 | Equipment slots are HEAD/WEAPON/TOOL/BODY strings | `EGMenuHUDEquipment.lua:60-62`; `EGMenuQuickSelection.lua:61-71` | CONFIRMED |
| 7 | Ammo debited only for the player; free for AI | `EGWeaponGun.lua:192-205` | CONFIRMED |
| 8 | Friendly fire is "player vs not-player"; no team field | `EGProjectile.lua:106-112` | CONFIRMED |
| 9 | No hitscan; bullets are fast large-radius projectiles | `EGWeaponBullet.lua:8-21` | CONFIRMED |
| 10 | NPC missiles always target the player | `EGWeaponMissile.lua:94-147` (`:139-141`) | CONFIRMED |
| 11 | Fire gated on `IsValidWeaponPos` + behavior flags | `EGWeaponGun.lua:129`, `:60-62` | CONFIRMED |
| 12 | Ship `FireWeapon` body commented out → engine-driven | `EGVehicle.lua:1661-1729` | CONFIRMED |
| 13 | 104 particle materials, 1-2 styles each, no texture field | `EGDataParticles.lua` (parsed) | CONFIRMED |
| 14 | Particles requested by name via `AttachParticles(slot,name,amount,pos,dir)` | `EGDataShipPlayer.lua:358-406`; `EGWeaponGun.lua:143` | CONFIRMED |
| 15 | Bodies assembled from `GetModuleEntities()` records; parts addressable by name | `EGDataCharacterXeno.lua:38-58`; `EGDataCharacterRobot.lua:19-66`; `EGRobotBody.lua:228` | CONFIRMED (data) / INFERRED (native build) |
| 16 | Robot parts seed-selected; xeno parts random | `EGRobotBody.lua:20-28`; `EGXenoBody.lua:20-28` | CONFIRMED |
| 17 | No per-part health or hit zones in Lua | `EGActor.lua:142-172` | CONFIRMED |
| 18 | Loot = weighted grammar tables, one nesting level; xenos use robot voice generators | `EGDataGenerateLoot.lua:3-110`; `EGDataCharacterXeno.lua:132-151` | CONFIRMED |
| 19 | Building seed randomized per instance, not positional; xeno count polled per frame | `EGBuilding.lua:26-29`; `GameplayMain.lua:296-303`; `EGGame.lua:124-139` | CONFIRMED |
| 20 | Interior generator = `ProductionName` + `EntranceAgent` only | `EGDataInteriorGen.lua:3-66` | CONFIRMED |
| 21 | `Generation.Loot` / `Generation.RewardLoot` referenced, never defined in Lua | `EGDataItems.lua:758`, `:1467` | UNKNOWN (engine-side) |
| 22 | Explosion ids resolve to engine physics effects, absent from Lua/.rsl | `EGExplosion.lua:18` | UNKNOWN |
| 23 | Particle sprite texture | none in `Data/Textures` | UNKNOWN (likely built-in) |
| 24 | Powerup weapon substitution happens outside Lua | `EGPlayerInfo.lua:266`; caller commented | INFERRED |

---

## 8. Lessons for a Godot 4 co-op space game

*No code copied; these are design translations.*

1. **Items as typed `Resource`s, still name-keyed.** The flat dotted namespace plus optional fields read
   by name is why one data file covers 125 item kinds. In Godot: `ItemDef extends Resource` with typed
   exports, subclasses (`FurnitureDef`, `DoorDef`, `MachineDef`, `PickupDef`, `GibDef`), one `.tres` per
   item, and an `ItemDatabase` autoload mapping `StringName` → `ItemDef`. You keep the authoring
   ergonomics and gain the validation Rodina lacks.
2. **Interactable as an explicit contract.** "Has `OnGrab`?" works for one offline player; co-op needs
   `class_name Interactable` with `get_prompt(peer)`, `can_interact(peer)`, and an
   `@rpc("any_peer","call_local","reliable") interact(peer)` validated on the server. Keep the two-tier
   text split (`ShowInfo` label vs `GetTargetInfo` detail) — it maps to a two-line reticle.
3. **One weapon resource, three projectile flavours.** Port the *decomposition*: `fire_style`, `cooldown`,
   `spread`, `projectile_count`, `projectile: ProjectileDef`, `ammo_type: ItemDef?` (null = unlimited),
   `muzzle_slot`, flare/charge/impact refs, `inherit_owner_velocity`. Then fast bullet / arcing body /
   homing missile scenes driven by that resource. Replace the hardcoded player-vs-not-player rule with a
   real `team: int` and an `is_friendly()` check before shipping co-op, or friendly fire will be wrong.
4. **Server-authoritative inventory, one store.** The count-ledger vs spatial-item split is a useful
   distinction (stackables vs placeable gear) but two sources of truth is a desync generator. Keep one
   server-owned `InventoryComponent` of `{def: ItemDef, count: int, grid_pos: Vector2i, slot: Slot}` and
   replicate it with a `MultiplayerSynchronizer`; clients send intents, never mutations.
5. **Modular characters from named slot markers.** `GetModuleEntities()` is effectively a scene-tree
   recipe: `{name, part_class, parent_name, slot_name, scale}`. Build a `CharacterRig` scene with named
   `Marker3D`s (`TorsoSlot`, `HeadSlot`, `ArmRightSlot`), let each `BodyPartDef` declare its own marker
   offsets, and assemble with `RandomNumberGenerator.seed = character_seed`. Determinism is mandatory for
   co-op — avoid Rodina's global-`math.random` xeno part picker (`EGXenoBody.lua:20-28`) and always
   thread the seed. Its `MakeModelMirror` trick (one mesh, mirrored limb) is a cheap variety win worth
   reproducing with a negative X scale.
6. **Particle effects as name-keyed resources with attach handles.** Model
   `ParticleEffectDef extends Resource` around `GPUParticles3D` process-material params plus a
   gradient/curve for the `Keys`. Keep two properties: the effect id is a `StringName` so weapon/item
   resources can reference it and hot-reload; and the API is
   `attach_effect(slot: StringName, def, intensity: float, xform)` — the `(slot, amount)` handle makes
   engines, muzzle flares and charge-up a single code path. Ships need many small emitters (Rodina drives
   15 per hull), so budget for that instead of one giant system.
7. **Buildings split three ways.** Exterior `PackedScene` + mesh collision, an entrance interior scene,
   and a seeded interior generator resource
   (`BuildingDef {exterior, entrance, generator, seed_range, flatten_inner, flatten_outer, icon, shield}`).
   Generate interiors on the server only and replicate the seed, never the tiles. Keep the habit of
   *deriving* status — "Cleared" from a live actor count — because a stored `is_cleared` flag breaks the
   moment a late joiner arrives (`EGBuilding.lua:91-104`, `EGGame.lua:124-139`).
8. **Cheap variety multipliers.** Mirrored limbs, one rock mesh × 3 scales × 9 classes, `Generation.*`
   decor rules that parent chairs to desks with a rotation range, armour variants that swap only a
   `Path`. All small-team friendly.

---

## 9. Residual uncertainty

- Native components (`ItemHolding`, `PlayerEquipment`, `Inventory`, `Building`, `FlattenTerrain`,
  `WalkController`, arm/leg/pelvis animation modules) are never defined in Lua; their behavior is
  inferred from call sites. **[UNK]**
- `Generation.Loot` / `Generation.RewardLoot` rules and the explosion physics-effect ids are resolved by
  the engine and are not in the extracted tree. **[UNK]**
- Whether non-bike `IsChair` objects use the same `ForceSitInChair` path is assumed from the single
  GravBike consumer. **[INF]**
- Two data oddities are reported, not explained: `Items.ShipLight` / `Items.PlayerLight` have no `Path`
  (invisible logic entities that only drive a light), and `Items.XenoTurret:Init` is empty (`:1850-1851`).
- `EGDataCharacterRobot.lua:21` seeds from `self.Seed`, but `Init` sets `self.Seed = math.random(100000)`
  (`:104`) — robot bodies are therefore *not* reproducible across sessions despite the seed machinery.
  Reads as a bug. **[EV]**
