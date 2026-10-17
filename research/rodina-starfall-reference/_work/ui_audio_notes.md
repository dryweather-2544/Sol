# Rodina 1.6.2 — UI / HUD / Menus / Input / Audio / Options

Static, read-only inspection of the extracted install at `/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2`. No executable, DLL, script or build tool was run; Lua sources are uncompiled `.lua` under `Scripts/`, and all line numbers refer to those files.
Tags: **C** = CONFIRMED in source, **I** = INFERRED (behaviour is engine-side C++, not shipped as source), **U** = UNKNOWN.

## 1. UI architecture

### 1.1 The tile tree (`EGTile`)

Everything drawable — menus, HUD, world markers — is one class, `EGTile` (`Gameplay/EGTile.lua:3`), created through the engine: `System.CreateTile` is the bottom of every constructor (`EGTile.lua:16-21`, `EGTileUtil.lua:10-18`). Lua `EGTile` forwards to `self.SystemTile` (render style/param/font `140-152`; position/size `201-231`). Layout is anchor-relative, never pixel-absolute: `SetParentAnchor` / `SetOriginAnchor` / `SetPositionRelative` / `SetSizeRelative` (`176-231`) with string anchors (`"CENTER"`, `"UPPER_CENTER"`, `"LOWER_LEFT"`, `"CENTER_RIGHT"`).

- **World-space tiles** — a tile can be created from an entity's engine (`self.Engine:CreateTile(EGTile)`, `EGPlanet.lua:515`), so it tracks a 3D object and is projected. This is how planet donuts work (§2).
- **Projection helpers** — `GetWorldLowerLeft/UpperRight` (`EGTile.lua:280-287`) for layout and gamepad navigation; camera-side `GetScreenBox` / `GetScreenPosForLocalDir` for target frames and reticles (`EGMenuHUD.lua:1614`, `462`, `1722`).
- **Depth / ignore-depth / keep-onscreen** (`EGTile.lua:196-198`, `300-307`): HUD overlays at depth 5–10 (`EGMenuHUD.lua:357`, `660`, `718`); targeted planet markers at depth 0 + `SetIgnoreDepth(true)` (`EGPlanet.lua:527`, `566`). `SetDistanceAlphaRange` (`EGTile.lua:295-297`) fades markers by range.
- **Scroll + virtualised lists** — `AddScrollOffset` / `SetScrollLimits` (`265-267`, `341-343`), and `SetScrollTable(array,rowHeight,displayFn)` + `UpdateScrollTable` (`346-400`): computes the visible index band from offset/height, creates rows via callback, destroys rows that scrolled out (`377-397`). The only list virtualisation in the UI.
- **Text and click handling** — `SetAsDocument` / `SetDocumentFile` (`166-173`), `SetFormatText("%1%",arg)` (`326-333`, used `EGMenuHUD.lua:668`, `1697`), `SetAcceptingTextInput` (`270-272`), and `SetBlockClickCancel` (`234-241`), which is what makes sliders survive the cursor leaving the tile.

Despite the "immediate-mode" reputation this is a **retained 3D scene-graph tile tree** with a per-frame state machine on top: menus build tiles once in `Setup()` and mutate them in `Update()`.

### 1.2 Widget library and state protocol

`Gameplay/EGTileUtil.lua` — plain functions returning configured tiles: `CreateTile` / `CreateTextTile` (`10-30`, the latter `MENU_RENDER_STYLE_NONE` + centred), `CreateSmallButton` (`33-77`, 200×40 `MenuGen.Button`), `EGCreateCleanButton` (`80-123`, flat `FillCleanBorder`), `EGCreateToggle` (`127-215`, 30×30 border + 16×16 light, `OnTurnOn/OnTurnOff`, `GetToggleState`), `CreateTextLink` / `HACKCreateDifferentTextLink` /
`CreateClippedTextLink` (`219-306`; "HACK" is the author's name), `CreateTilesetButton` (`309-335`), `EGCreateSliderTile` (`338-418`; cursor → `EGAnalogue`, `Granularity` snap, `SetValueFunc`).

All widgets implement `SetState(self, state)` over one vocabulary: `NORMAL`, `HIGHLIGHT`, `DEPRESSED`, `ENABLED`, `DISABLED` (`50-76`) plus `ON`/`OFF` (`177-184`); disabled = `SetTouchable(false)` + alpha .2 (`70-74`). `EGTile.lua:35-88` keeps an older *method* copy of the small-button style — evidence of styles migrating from imperative setters into construction tables.

### 1.3 `EGMenu` — base class

`Gameplay/EGMenu.lua`. Mostly **class-level flags** consumed by the engine menu system (`5-14`): `SIZE 100×100`, `ScrollRate 24`, `IsMenu`, `MenuMode=true`, `CapturesInput=true`, `IsClosable=true`.

- `Create()` no longer builds; it calls `SystemTile:CreateMenu(...)` (`23-27`). The original construction survives commented out (`29-51`) as documentation: root tile sized `SIZE`, upper-left anchored, depth `StackPos*10000`, `Setup()`, then `ScrollTile:AddScrollOffset(0)` to force the scissor rect. **C**
- `Setup()` is the build hook (`55-57`); concrete menus destroy/recreate content there (`EGMenuOperations.lua:26-34`, `EGMenuPilot.lua:12-34`). `Close()` → `SystemTile:Close()` (`64-66`); `Destroy()` is now an error — menus are engine-owned (`69-78`).
- `GetTouchedTile` / `GetTileInDirection` / `IsPosOnMenu` (`86-98`) are ray casts; `GetBlocksInput()` returns true (`101-103`) so a top menu stops the hit-test walk.
- `InputEvent(event, targetTile, position)` (`106-144`) is the single pointer entry point. Vocabulary (`EGMenuSystem.lua:6-17`): `INPUT_CLICK_START/MOVE/COMPLETE/CANCEL`, `INPUT_SCROLL`, `INPUT_LEAVE`, `INPUT_MOVE`, `INPUT_ENTER`, `INPUT_CONTEXT`. Base impl scrolls, maps enter→HIGHLIGHT / leave→NORMAL / click-start→DEPRESSED / cancel→NORMAL / complete→HIGHLIGHT + `target.OnClick(pos)` (`113-143`).
- `OnClose()` (`60-61`) commits/tears down, e.g. radial selection (`EGMenuQuickSelection.lua:275-278`).

### 1.4 `EGMenuSystem` — dead Lua, live engine API

**Key negative finding:** `Gameplay/EGMenuSystem.lua` is *entirely commented out* — a Lua long comment opened at line 3 (`--[=[`), closed at line 400 (`--]=]`). It is a preserved reference implementation; the real system is engine-side. **C**

Live API used by scripts: `MenuSystem:Open(Class, cInfo)` (`GameplayMain.lua:27-30`, `EGDataItems.lua:343`), `:GetOpen(Class)` (`EGMenuHUD.lua:162-167`), `:CloseMenu/:CloseTopMenu`, `:SetDefaultButtonPos()` (`EGMenuMain.lua:148`), `:IsMenuCursorMode()`, `:IsMenuMode()`, `:IsMenuFreezePlayerMode()` (`EGSceneSolar.lua:52`, `56`, `EGCharacterActor.lua:174`). Accessor `EGGetMenuSystem()` → `System.GetCurrentScene().MenuSystem` (`EGDataProgress.lua:125-127`).

The commented code is the best spec of intent (**I**): top-down stack hit test stopping at the first menu reporting a hit *and* `GetBlocksInput()` (`331-348`); identical walks for direction (`351-368`) and default button (`371-388`); `Open` closes the click target, injects `MenuSystem`, pushes, `Create(#stack)` (`47-58`); `CloseMenu` pops until target then pops it (`99-107`); `UpdateInput` closes the top menu on
`CANCEL_MENU`/`MENU` when `IsClosable` (`118-133`); `Update(dt)` runs the mouse-vs-controller machine then calls `menu:Update(dt, active)`, where `active` is true only for the top menu *and* only when the window has focus (`285-292`) — the contract HUD widgets rely on (`EGMenuHUD.lua:159`, `EGMenuHUDStatus.lua:42`).

### 1.5 Render styles: `MenuStyle`, `MenuGen.*`, textures

`RenderStyle` is a string resolved by the engine in three families:

1. **Engine enums** — `MENU_RENDER_STYLE_DEFAULT/SOLID/NONE`, aliased in `Gameplay/MenuStyle.lua:5-7`. `Solid` = flat colour quad (damage overlays, `EGMenuHUD.lua:712`); `NONE` = text-only (`1058`).
2. **Texture filenames** — `"white.png"`, `"corner_LL.png"`, `"altimeter.png"`, `"HUDEquipmentBG.png"`, `"QuestionMark.png"`, `"colorblind_planets_zorica.png"` (`EGMenuHUD.lua:1485`, `1659`; `EGMenuHUDStatus.lua:69`; `EGPlanet.lua:658-667`).
3. **Procedural generators** — `MenuGen.Button`, `.ButtonHighlighted`, `.ButtonDepressed`, `.FillBG`, `.FillCleanBorder`, `.HudGears1..4`, `.HudPlanet`, `.HudReticle`, `.HudVanguard`, `.HudThermometer`.

`MenuGen.*` are **procedural texture generators** — an in-script shader graph (`Render/TextureGen.lua:3-16`, `RenderMain.lua:22-47`). A generator returns ordered passes (`GetPasses`), each a nested `GeneratorType` or a typed pass (`TextureGen.lua:36-83`); pass types live in `Render/TextureGenPasses.lua` (`PassPerlin`, `PassVoronoi`, `PassBlur`, `PassNormals`, `PassDistort`, `PassMultiply`, `PassAdd`, `PassMax`, `PassMask`,
`PassBlend`, `PassColorize`, `PassCircle`, `PassRect`, `PassTriangles`, `PassConvex`, `PassSine`, `PassLight`, `PassTransform`). Output is uploaded by name: `System.SetTexture(self.Name, self:GetResult())` (`TextureGen.lua:120-125`); tile-side params via `SetRenderParam` (`EGTile.lua:145-147`; planet `Thickness`/`Width`, `EGPlanet.lua:520-521`). Resolution order (enum → texture → generator) is **I**, but the generator path is
explicit in `RenderMain.lua:31-47`, which parses `"Namespace.Name"`.

- `MenuGen.Button` (`MenuGen.Button.lua:3-30`): `Color1 {.4,.7,.7}`, `Alpha .85`, `ScanlineFactor .75`, `EdgeRadius 6`, one nested pass into `FillBG`. `ButtonDepressed` (`NormalFactor -1`, `33-38`) and `ButtonHighlighted` (`41-43`) are *separate registered styles*, not shader uniforms.
- `FillBG` (`MenuGen.FillBG.lua:3-35`): rounded `PassRect` inset by `EdgeRadius`, then `Background`. `Background` (`MenuGen.Background.lua:22-92`) is the "glass panel" stack — normals → colour multiply+alpha → mask → lighting (light `{0,1,.2}`, shadow, specular, hardness 5) → alpha multiply → add black → second specular at `{-0.5,1,-0.2}` → colourize → mask → final add; nine passes per panel.
- `FillCleanBorder` (`MenuGen.FillBG.lua:39-115`): outline/border/interior rects blended; `OutlineWidth 1`, `BorderWidth 2`, outline `{.05,.15,.25}`, border `{.2,.35,.5}`. Used by sliders, target frame (`EGMenuHUD.lua:1541`), altimeter (`1670`), inventory (`EGMenuInventory.lua:191`).
- `HudGears1..4` (`MenuGen.HudGears.lua:127-220`): `PassConvex` with a hardcoded polygon per gear + `Background` — four shapes, not sprites. `HudPlanet` (`439-469`): `PassCircle` with four colour keys producing an **annulus** (transparent / white ring / transparent), params `Thickness .89`, `Width .9`.
- `HudVanguard` (`472+`): cross + ring `PassMax`. `HudThermometer(+Shell)` (`3-125`): circle + `PassConvex` stem + `PassMax`, `TempHeight` param. HUD chrome colours: `EGMenuStyle.lua:5-6` — `HUDColor {.5,.75,1}`, `HUDColorTargetFrame {1,1,1}` (used `EGMenuHUD.lua:1492-1522`).

### 1.6 Fonts

`Render/MenuFonts.lua` is a flat list of 75 `System.CreateFont{...}` declarations — `FontFace`, `Size`, `Color`, `Alpha`, `Bold`, `Italic`, `VerticleAlign`, `HorizontalAlign`, `WordWrap`, sometimes `FixedWidth` (`355-368`). Nothing loads from Lua; the engine owns the atlas. Faces: Orbitron (UI/buttons/HUD numbers), Quantico (documents/dialogue), Michroma (titles), Audiowide (warnings), Fira Mono (dense readouts), Jura (small buttons), Fixedsys Excelsior 3.01 (monospace), Verdana (debug).

Naming is role-based and role implies layout: `DiscoveryFont` 50 (`5-16`), `WarningFont` 24 red (`47-59`), `NotificationFont` 20 (`75-88`), `AmmoFont`/`AmmoFontDepleted` right-aligned 20 (`90-118`), `HUDTargetFontTitle` 12 / `HUDTargetFont` 11 / `HUDAltimeterFont` 11 (`135-179`), `YouDiedFont` 50 (`181-192`), `HUDEquipmentAmmoLeft/Right/Hint` (`194-235`), `AmmoCountFont` 30 (`237-250`), `ButtonFont` 18 / `ButtonFontMedium` 14
/ `...Depressed` 13 / `ButtonFontSmall` 12 (`267-353`), document family `DocumentFont*` 13 Quantico (`415-543`), eight per-speaker dialogue colours `DocumentFontConversation1..8` (`597-699`), per-character header fonts (`761-958`), `QuickSelectionFont` 18 (`999-1010`), `ContextTitleFont`/`ContextFont` (`1012-1038`).

`.spritefont` files in `Data/Fonts/FontCache/` are **pre-baked bitmap atlases**, not font definitions: magic `DXTKfont` (DirectX Tool Kit sprite-font binary), filename `Face_Size(_b/_i)`. 32 cache files for 75 declared fonts, shared across identical (face,size,bold,italic) tuples — `Orbitron_14.spritefont` ↔ `ButtonFontMedium`, `Michroma_50.spritefont` ↔ `YouDiedFont`, `Fira Mono_11.spritefont` ↔ `HUDTargetFont`. **C** format / **I** runtime use (no Lua references the path).

### 1.7 Open/close, input routing, cursor, pause, freeze

**Open** — context-aware scripts call `MenuSystem:Open`: startup `EGMenuLoading` → `EGMenuMain` via `OnLoadComplete` (`GameplayMain.lua:27-30`); main-menu "start" closes itself and opens `EGMenuHUD` (`EGMenuMain.lua:378-383`); ship computers open `EGMenuAirlock` / `EGMenuOperations` / `EGMenuScanners` (`EGDataItems.lua:343`, `538`, `524`); the pause menu opens from the scene on `MENU` or focus loss with `PauseOnLoseFocus` (`EGSceneSolar.lua:100-102`).

**Close** — `Close()` → `SystemTile:Close()`, or implicit close on `CANCEL_MENU`/`MENU` when `IsClosable` (`EGMenuSystem.lua:127-130`). `IsClosable=false` is deliberate where dismissal must be explicit: `EGMenuMain`, `EGMenuLoading`, `EGMenuRegister`, `EGMenuStartGame`, `EGMenuShipLayout`, `EGMenuContext`, `EGMenuEditLights`, `EGMenuKeybindPopup`.

**Input routing** — two layers. Scene-level `EGScene.Control` is an `EGControl` (`EGScene.lua:8`) enabled per frame (`36-38`), read via `Control:GetAction(...)`. Menu-level, the engine ray-casts the pointer into the tile tree and delivers `INPUT_*` to the owning menu's `InputEvent`, which calls `EGMenu.InputEvent` then switches on `aTargetTile:GetName()` (`EGMenuPilot.lua:93-127`, `EGMenuOperations.lua:358-396`,
`EGMenuOptions.lua:992-1025`). **Tile names are button IDs**, so names must be unique per menu. `EngineHandlesInput=true` (`EGMenuInventory.lua:12`, `EGMenuQuickSelection.lua:12`, `EGMenuDocument.lua:20`) opts into engine-side handling (grid drag, radial) — **I** from the flag plus those menus implementing their own drag/analog logic (`EGMenuInventory.lua:25-88`, `EGMenuQuickSelection.lua:178-253`).

**Cursor mode** — per-menu `CursorMode`: true only on inventory (`EGMenuInventory.lua:16`), explicitly false on quick-select (`EGMenuQuickSelection.lua:15`). The scene pushes it to the OS cursor each frame: `System.GetInput():SetMouseModeCursor(cursorMode)` (`EGSceneSolar.lua:52-53`, `76-77`); in gameplay the cursor is hidden unless `Options.ShowCursorDuringGameplay` (`95-98`). `SaveCursorPosition=true` (`EGMenuInventory.lua:13`) restores the prior position.

**Pause vs freeze** — three independent concepts:

- `System.SetPaused(true)` whenever `IsMenuMode()` (`EGSceneSolar.lua:73-74`), released when menus close (`56-65`). Any `MenuMode` menu pauses.
- `MenuMode=false` on the HUD family (`EGMenuHUD.lua:8`, `EGMenuHUDStatus.lua:6`, `EGMenuHUDEquipment.lua:6`) and quick-select (`EGMenuQuickSelection.lua:14`), so those overlay a running world. `IsMenuMode()` therefore means "is any open menu in menu mode", not "is any menu open" — **I** from those flags plus the `EGSceneSolar.lua:56` comment.
- `FreezePlayerMode=true` (`EGMenuInventory.lua:18`, `EGMenuQuickSelection.lua:17`) freezes *player input*, not the world: the actor reads `MenuSystem:IsMenuFreezePlayerMode()` and zeroes rotation/velocity, suppressing movement (`EGCharacterActor.lua:174`, `184`).

The HUD is itself a small menu family: `EGMenuHUD:Update` opens `EGMenuHUDEquipment` and `EGMenuHUDStatus` once the progress stage `"EnableHUD"` occurs (`EGMenuHUD.lua:161-169`).

## 2. HUD

`Gameplay/EGMenuHUD.lua` (1756 lines) is the HUD root: a menu with all interaction flags off (`MenuMode/CapturesInput/IsClosable=false`, size 1×1, `7-10`) and a **global singleton** — `HUD = self` in `Init` (`17`), read by `EGCharacterActor`, `EGPlanet`, `EGSceneSolar`. Opened from `EGMenuMain:Start` (`EGMenuMain.lua:383`) or lazily by the scene when `HUD` is nil (`EGSceneSolar.lua:79-81`). `Setup()` builds only persistent chrome — gears, ammo, gear notice, notifications, tutorial, reticle, planet discovery (`145-156`); transient widgets are created on demand and destroyed.

**Tick (`159-214`)** — ensure child HUDs → derive mode from `System.GetPlayerControlActor()` vs player/vehicle (`176-180`) → screenshot mode hides the HUD via alpha (`183-185`) → with a camera: reticle, gears, tutorial, gear notice, warning, notifications, pain, heal, jetpack, solar charge, pregnancy, solar flash, powerup, planet discovery, character reticle; **and only when not paused** ammo, target UI, altimeter (`205-209`); death overlay always (`210`). A clean split of cosmetic-always vs gameplay-coupled HUD.

**Health** is a child menu, `EGMenuHUDStatus.lua` (125 lines): 350×170 lower-left panel, offscreen-rendered to `HUDStatusTarget.png` (`5-9`), background `HUDStatusBG.png` (`69`), rebuilt when weapon/tool changes (`56-124`), and each frame rescales two bars — `STATUS HEALTH BAR` (red) by `HUD.PlayerHealthPercent`, `STATUS SHIP BAR` by `HUD.VehicleHealthPercent` (`42-53`). Values arrive via `SetPlayerHealth`/`SetVehicleHealth`
(`EGMenuHUD.lua:676-686`), the former arming the pain overlay on a drop (`682-685`). Pain = full-screen `MenuStyle.Solid` red tile at depth 10, alpha from an `EGAnalogue` ramp on health and time-since-hit (`689-732`); heal is the same in blue (`740-777`); both suppressed when the camera is not the player (`704-706`, `750-752`) — no red flash while piloting in third person.

**Channels** — four, all single-tile and transient:

- *Warning* — one `MenuGen.Button` tile, `WarningFont`, `"WARNING: %1%"`, upper-centre at 30% height, depth 10 (`648-673`). Blinks via thresholded `cos(t·7)` (`231-236`), expires 0.25 s after the last warning (`667`, `239-245`), and is audible: `PlaySound("MissileAlarm",1)` + `SetSoundPitch("MissileAlarm", pitch)` (`670-671`).
- *Notification* — a **queue**: `AddNotification(msg, disallowDuplicates)` dedupes against queue and shown message (`629-645`); one per 3 s with an `EGAnalogue` fade (`249-266`); `MenuGen.Button` + `NotificationFont`, upper-centre at 15% (`921-936`). Also used for input-mode changes (`EGActionBindings.lua:372-378`).
- *Tutorial* — `SetTutorialText(text,timer)` (`586-590`, `571-583`); tile is `MenuStyle.FillBG`, `NotificationFont`, 600×160, lower-centre, and **`SetAsDocument()`** (`960-977`) — tutorial copy goes through the document renderer, so it carries rich text.
- *Gear notice* — `NotificationFont`, upper-centre at 7.5%, 1 s fade (`217-225`, `980-995`). *Planet discovery* — `DiscoveryFont` 50, upper-centre at 17.5%, 10 s two-stage fade (`598-604`, `304-320`, `939-957`), fired from `EGPlanet:OnDiscovered` with the arrival music cue (`EGPlanet.lua:638-646`).

A `local ShowAllHUD` debug switch (`EGMenuHUD.lua:12`) forces every channel to alpha 1 and fakes gear 4 / full ammo; each updater has an `if ShowAllHUD then alpha = 1 end` branch (`222`, `263`, `316`, `578`).

**Gears** — four tiles upper-right, `MenuGen.HudGears1..4`, at 12.5/37.5/62.5/87.5% of a 300×200 container (`998-1048`). `UpdateGears` colours from the vehicle gear: at-or-below current = alpha 1 white; the gear being shifted *to* = brighter; current below target = dim; rest invisible (`512-568`). `SetGear` labels 1 `DOCKING SPEED`, 2 `COMBAT SPEED`, 3 `CRUISING SPEED`, 4 `LIMNAL DRIVE` (`607-626`) — a 4-speed transmission metaphor. `WeaponCruiseWarningTimer` pulses gear 3 red when weapons are hot in cruise (`593-595`, `549-566`). Hidden in character mode (`417-418`, `432-433`).

**Ammo/weapon** — `SetupAmmo` (`1051-1087`), `UpdateAmmo` (`269-301`): weapon name + round count, right-aligned, count looked up from inventory by ammo class honouring `UsesSeparateAmmo`/`AmmoType` (`273-282`). At zero *and* fire held, both tiles swap to the `...Depleted` fonts (`292-298`) — the empty state is a **font swap**, not a colour setter. Active weapon pushed by `SetWeaponType` (`1753-1755`).

**Planet donuts** — tiles owned by the planet, created with `self.Engine:CreateTile(EGTile)` (`EGPlanet.lua:509-539`): 35×35, `MenuGen.HudPlanet`, depth 0, relative position `(0.2,-0.4)`, tinted by `GetHUDColor` (`675-681`), ring params via `SetRenderParam` (`520-521`). Behaviour (`550-606`): base alpha from *facing* — fades near screen centre at close range and when behind the camera (`617-635`); targeted planet pulses scale
via `SetIndicatorScale(sin·2..3)` with `IgnoreDepth(true)` + `KeepOnscreen(true)` (`561-574`); range fade over `radius·1.25…1.5` for the current planet else `10 AU…20 AU` (`541-545`, `569-586`); hidden before stage `"ShowPlanets"`, while `EGMenuMain` is open, in character mode (`ShowInCharacterMode=false`), when `Options.ShowPlanetDonuts` is false, or in screenshot mode (`588-596`). Discovery swaps the render style:
undiscovered → `QuestionMark.png`, discovered/star/asteroid → `MenuGen.HudPlanet`, and with `ColorBlind` → per-planet letter textures `colorblind_planets_<name>.png` (`649-672`; data keys `EGDataPlanets.lua:32,254,414,523,699,962,1223`). The same primitives serve actor and vehicle markers (`EGTargetProxy.lua:79`, `EGGravBike.lua:128`, `EGVehicle.lua:1931`).

**Target frame** — `UpdateTargetUI` (`1459-1641`) builds once: four 14×14 corner textures tinted `HUDColorTargetFrame`, a 260×80 `FillCleanBorder` frame at alpha .8, a title, a 1 px separator, two readout lines (`1470-1593`). Per frame it asks the camera for the target's projected screen box and places each corner at the matching box corner (`1614-1618`) — the frame is the **projected AABB of the 3D object**, not a fixed reticle. Text from `GetDisplayName` / `GetDistanceBetween` / `GetTargetInfo` (`1621-1634`); an offscreen `EGTargetProxy` parks corners at `(100,100)` (`1605-1611`).

**Altimeter** — `UpdateAltimeter` (`1644-1750`): `altimeter.png` 25×25 marker plus a `FillCleanBorder` readout `"Altitude: %1%"` sized from string length × 11 px (`1657-1698`), distance `GetLocalVectorTo(target):Length() - 17` (`1690-1692`). *Floating* projects the marker, forces Y ≥ 1, clamps to `±.485/±.475` via `EGLimitScreenPos` (`1438-1457`) and slides the label inward (`1712-1731`); *locked* pins it to `CENTER_RIGHT` `(25,80)` and offsets the label by half its width (`1732-1738`). Alpha fades inside 5 units, outside the planet, or outside the vehicle interior (`1700-1710`).

**Other widgets** — `SetupReticle`/`UpdateReticle` (`1351-1373`, `444-484`): two reticles at `ReticleDistanceClose` 200 / `ReticleDistanceFar` 100000 from a `ReticleOffset` barrel point, projected with `GetScreenPosForLocalDir`, hidden in cockpit view unless the camera actor is the vehicle; `UpdateCharacterReticle` (`1374-1437`) is the first-person variant. Also `UpdatePowerup` (`1088`), `UpdatePregnant` (`1146`),
`UpdateSolarCharge` (`1199`, `GetCurrentItem` `1260`), `UpdateJetpack` (`1280`), `UpdateSolarFlash` (`780`), `UpdatePowerBar` (`829`, commented out at `200`), `SetLookInfo` (`884`), `SetTemperature` (`487`, effectively disabled). Death overlay (`323-404`) shows `YOU DIED` / `SHIP DIED` / `SHIP CRASHED` plus "Press <USE_RIGHT key> to reload" built from the live binding name (`368`), loading the recent autosave on confirm
(`387-394`).

`EGMenuHUDEquipment.lua` (309 lines) is the second HUD child: 350×170 lower-left panel (`5-9`, offscreen `HUDEquipmentTarget.png`), rebuilt when scope/weapon/tool/gamepad-mode changes (`58-100`), showing a cross layout of equipped items (`HUDEquipmentBG.png` / `QuickSelectionCross.png` / `HUDEquipmentCircle(.Small).png`, `110-210`) with per-item ammo counts (`73-89`) and inventory icons (`151`, `206`).

## 3. Gameplay menus (one paragraph each)

**`EGMenuPilot`** (128) — pilot-mode overlay, 100×300 centred, no background (`5-31`): four buttons for 1st/3rd person toggle, altimeter cycle Float → Locked → Off, cancel pilot mode, close (`37-84`). Data source is `gGame` altimeter state; actions are `SwitchPilotFirstPerson`, `SetAltimeterShowing/Floating`, `StopPilotingVehicle` (`99-125`). It is the UI half of "get out of the seat" and where the two altimeter modes are chosen.

**`EGMenuAirlock`** (233) — airlock/computer terminal, 600×320, constructed with `{Vehicle, Computer}` (`5-19`), plays `OpenComputer` on init (`14`). Content: a numeric air-pressure bar whose colour interpolates red→green and whose width *is* the pressure fraction (`56-90`), then `OPEN AIRLOCK IN`, `CLOSE AIRLOCK`, `OPEN AIRLOCK OUT`, `LAYOUT MENU`, `REMOTE PILOT`, `CLOSE` (`160-213`). Data source is
`self.Computer.AirPressure` plus door state; notable interactions are `ChoosePilotShip` (`214`) — remote-piloting another ship from a terminal — and the layout button, which enters the ship editor.

**`EGMenuOperations`** (396) — ship systems console, 780×350, `{Vehicle, Computer}`, `Tab = "WEAPONS" | "SHIP"` (`5-18`). Tabs work by re-running `Setup()` (`373-381`): WEAPONS lists each weapon with an alt-weapon selector writing `GetPlayerInfo():SetAltWeaponName(...)` (`389-391`); SHIP exposes toggle-all doors via `GetAllDoorsOpen`/`SetAllDoorsOpen` (`309-322`, `383-387`) and closes after applying. Reusable patterns: *tab = state field + re-Setup* and *toggle-all derived from a scan*.

**`EGMenuScanners`** (476) — navigation/science screen, 800×560 split into a 500×500 map and a 280×500 index (`5-7`). `CreateScannerObjects` makes one tile per planet/asteroid/player, gated by stages `"ShowPlanets"`, `"ShowAsteroids"`, `"GetLastSurvivor"` (`307-348`), positioned (`350-362`) and updated as the player moves (`363-395`). The index (`CreateTextMenu`, `101+`) is a collapsible tree — `* Objects`, `* Astronomy`, `*
Goals`, `* Resources`, `* Data` — from progress stage, goals, planets and `GetOwnedDocuments()` filtered by `IsRadioDoc`/`HideFromScanners` (`280-300`); tabs are `OBJECTS`/`PLANETS`/`GOALS`/`RESOURCES`/`DATA` plus `CLOSE_BUTTON` (`439-457`). Selecting a document highlights its planet (`429`).

**`EGMenuInventory`** (652) — grid inventory + equipment, full-screen, `CursorMode=true`, `FreezePlayerMode=true`, `CapturesInput=false`, `EngineHandlesInput=true`, `SaveCursorPosition=true` (`5-18`). 30 px cells/icons with snapping helpers and `GetClosestPlacementCoord` (`20-40`); panes `SetupInventory`/`SetupEquipment` (`173-280`) built by `MakeInventoryGrid` (`281-503`) and `CreateItems` (`504+`), rendering each item's
`Icon`/`BackgroundIcon` as tile render styles (`638`, `649`). Drag-and-drop is script-side on top of `EngineHandlesInput`; closing plays `InventoryClose` (`106`). The world keeps simulating while the player is frozen.

**`EGMenuQuickSelection`** (451) — radial weapon/tool/camera/equipment wheel, 500×500, `MenuMode=false`, `CursorMode=false`, `FreezePlayerMode=true`, `EngineHandlesInput=true` (`5-17`). `Init` takes `SelectionType` (`32-44`); items come from `EGGetPlayerEquipment(player.Engine)` (`52-60`); opens with `QuickWheelOpen`, closes with `QuickWheelClose` (`54`, `277`). A 2D guide vector driven by right stick or relative mouse motion
is clamped to 20 units with edge slowdown; angle → index by `round(angle / (2π/n))` (`178-253`). It **closes on key release**, not on click: each frame it checks `GetAction("SWITCH WEAPON"|"SWITCH CAMERA"|"SWITCH TOOL"|"SWITCH EQUIPMENT")` and closes at 0 (`255-271`), then `OnClose` commits `SetCurrentItem()` (`275-278`). One implementation serves four item types because the type also selects the hold key.

**`EGMenuShipLayout`** (1176) — in-game ship/room editor, full-screen, `CapturesInput=false`, `IsClosable=false` (`5-14`). A tool palette beside the live 3D view with state fields `State="PAINT"`, `RoomFunction="SMEAR"`, `StyleFloor`, `CurrentTileset`, `CurrentEntityType/Function` (`17-35`) and windows for modes (`126`), entity list/categories (`184`, `322`), map/room buttons (`339`, `372`), style (`436`), file (`572`), floor
(`647`), tilesets (`707`); plus undo state (`791`), per-frame target highlight (`1020`) and save/load/new-room hooks (`1142`, `1150`, `1158`). Data comes from the tileset/entity catalog (`DataGameplay/EGDataTilesets.lua`) and the live room — an editor mode wearing the menu stack.

## 4. Input

**Three files.** `Gameplay/EGActionBindings.lua` (384) is the mechanism: static maps `GamepadControlMap`, `KeyboardMouseControlMap`, `InputActions`, `InputNames`, `GamepadMode` (`5-10`), `AddInputName` (`13-19`), `AddAction` (`28-39`), `MapAction` (`88-109`), lookups (`60-85`), plus the per-frame query object `EGControl` (`112-382`) with `GetAction` (`296-340`), `GetCompoundAction` (`144-269`), `GetSpecialAction` (`272-293`),
`ClaimPress` (`343-361`) and device auto-detection (`364-382`). `DataGameplay/EGDataActionBindings.lua` (175) holds **declarations and defaults**: 54 `AddAction(name, displayName, style)` calls (`3-59`), `EGSetDefaultKeyBindings()` (`63-152`), then `EGSetProfileKeyBindings()` (`156-174`) overlaying the user's saved bindings from `System.Profile.GetKeyBindings()` / `GetGamepadBindings()`.
`DataGameplay/EGDataActionBindingKeys.lua` (148) is the **name table**: every physical control mapped to a localisable label — mouse (`3-13`), keyboard (`15-120`), gamepad buttons/triggers/shoulders/dpad (`122-137`), stick axes (`139-148`); each passes through `System.CheckLocalizedString` (`EGActionBindings.lua:15`).

**Canonical actions by context.**

- *Shared primitives* — `MOVE_FORWARD/BACK/LEFT/RIGHT/UP/DOWN` (`23-28`); `LOOK_FORWARD/BACK/LEFT/RIGHT/ROLL_LEFT/ROLL_RIGHT` (`30-35`).
- *Walking / interaction* — `RUN` ("Walk", Hold), `TOGGLE_RUN`, `JUMP`, `ACTIVATE`, `CANCEL`, `FOCUS`, `CLUTCH`, `ALT_WEAPON`, `USE_RIGHT`, `USE_LEFT`, `SWITCH WEAPON`, `SWITCH CAMERA`, `SWITCH TOOL`, `SWITCH EQUIPMENT`, `FREE_LOOK`, `OPEN INVENTORY` (`3-21`).
- *Ship* — no ship-exclusive names; reuses `MOVE_*`/`LOOK_*` plus `SHIFT UP`, `SHIFT DOWN` (gears, `19-20`) and `CLUTCH` (`9`). Ship feel differs only in compound interpretation and the `GamepadSwapShip*` / `InvertShip*` options.
- *Menus* — `MENU` (`18`), `MENU_ACTIVATE`, `MENU_ACTIVATE_CONTROLLER`, `MENU_CONTEXT`, `MENU_SCROLL_VERT`, `MENU_SCROLL_UP/DOWN`, `MENU_SCROLL_PAGEUP/PAGEDOWN`, `MENU_SCROLL_UP_CONT/DOWN_CONT` (`42-51`). `MENU_ACTIVATE` = mouse-left, `MENU_CONTEXT` = mouse-right (`81-82`), `MENU_ACTIVATE_CONTROLLER` = pad A (`126`); context arrives as `INPUT_CONTEXT` (`EGMenuSystem.lua:261-263`).
- *Debug / editor* — `CONSOLE` (`~`), `SCREENSHOT MODE` (F1), `DEBUG MODE` (F11), `QUICKSAVE` (F5), `QUICKLOAD` (declared `41`, unbound; handler commented out at `EGSceneSolar.lua:113-117`), and `EDITOR_DRAG/MOVE/ROTATE/ZOOM/ZOOM_IN/ZOOM_OUT/FLOOR_UP/FLOOR_DOWN` (`52-59`, defaults `89-96`).

**Compound actions.** `GetCompoundAction` (`144-269`) turns scalars into vectors:

| Compound | Source | Result |
|---|---|---|
| `MOVE_GAMEPAD` / `MOVE_MOUSE` | six `MOVE_*`, per device | `(right-left, forward-back, up-down)` (`152-168`) |
| `LOOK_GAMEPAD` / `LOOK_MOUSE` | four `LOOK_*` + roll; mouse pitch/yaw ×0.075 | `(right-left, forward-back, rollR-rollL)` (`170-186`) |
| `MENU_SCROLL` | wheel ×2, tap ×2, page ×50·dt, continuous ×0.2 | `(0,-sum,0)` (`188-202`) |
| `MOVE_SHIP` / `MOVE_CHARACTER` | dispatch on `GamepadMode` | gamepad→`MOVE_GAMEPAD`, else `MOVE_MOUSE` (`212-224`) |
| `LOOK_SHIP` / `LOOK_CHARACTER` | dispatch on `GamepadMode` | gamepad→`LOOK_GAMEPAD`, else `LOOK_MOUSE` (`226-260`) |

Per-device feel is injected only in the `LOOK_*` compound: `GamepadSwapShipSticks` (`233-237`), per-context invert-Y for gamepad (`239-243`) or mouse (`255-259`), `GamepadSwapShipRollYaw` swapping X/Z (`245-250`), then X negated for all look compounds (`262`). `MOVE_SHIP` also honours `GamepadSwapShipSticks` by overwriting X/Y from the look stick (`217-221`).

**Gamepad mode** is automatic and per-frame: `CheckGamepadMode` (`364-382`) compares summed gamepad vs mouse compound magnitudes, flips `GamepadMode`, logs, and pushes a HUD notification. Menu gamepad navigation is **synthetic mouse movement** — controller use is detected by watching mouse pixel motion, then the OS cursor is moved to the focused tile (`EGMenuSystem.lua:145-196`). **I**

**Tap vs hold** is declared per action in `AddAction`'s third argument: `GetAction` routes `Tap` → `GameInput:GetTap(action, name)` and `Hold` → `GameInput:GetPress(action)` (`314-318` gamepad, `328-332` keyboard/mouse), so Tap = edge/one-shot, Hold = analog/level; tapped controller repeat is tuned by `ControllerTapRepeatMin/Max/SpeedMin/SpeedMax` (`113-116`). `GetAction(..., claimPress)` consumes a press so it isn't seen twice (`319-321`, `334-336`); `ClaimPress` (`343-361`) always does.

**Cancel special case** — `GetSpecialAction("CANCEL_MENU")` deliberately uses gamepad `CANCEL` (B) vs keyboard `MENU` (Esc), because Tab is already `CANCEL`/`OPEN INVENTORY` in gameplay (`272-293`, comment `281-283`). **Enabled gate** — a disabled control returns 0 / zero vector (`148-150`, `300-302`), driven by `EGScene:Update`'s `aEnableInput` (`EGScene.lua:36-38`).

## 5. Audio

**Script vs engine.** `Gameplay/EGAudio.lua` (889) has **no playback implementation**: 58 `System.Audio.LoadSound{...}` blocks (`5-707`) plus the `Music` table (`709-889`). Mixing, 3D attenuation, streaming and synthesis are engine-side. The Lua-visible API is small (grep-counted): `LoadSound` (58 uses), `PlaySound(name, volume, entity?)` (58), `SetSoundPitch(name, pitch)` (5), `PlaySoundKeys(name, keys, vol, entity?)` (2),
`QueueMusic` (4), `FadeMusic(target, seconds)` (5), `IsMusicPlaying` (1). No `StopSound`, listener API, mixer groups, categories or ducking exposed to Lua — **U** internally.

**Definition schema.** `Name`, optional `Filename` (defaults to `Name`), `Loop`, `Volume`, `UpSpeed`, `DownSpeed`, `MinDistance`, `Attenuation`, occasionally `IgnoreTimescale` (`5-14`, `16-26`, `686-695`). Idioms: engines are slow-ramped loops (`WarpEngine` vol 1, Up 5 / Down 1, MinDistance 50, Attenuation .25, `16-26`); one-shots use `math.huge` for both ramps as "no fade" (`74-84`); close foley uses small `MinDistance`
(`DoorOpen` .5, `317-327`); `MissileAlarm` is a loop with no distance params (`64-72`) because it is a 2D UI alarm whose pitch is set at runtime. Reuse is deliberate: `rod_atmosentry` backs `DeathFire`/`AtmosphereFire`/`Fire` (`268-290`), `rod_wind_super` backs `AtmosphereWind`/`RoomAirDepressurize` (`292-315`), `AirBlow` backs `Airlock`/`Jetpack`/`FireExtinguisher` (`52-62`, `582`).

**Name → file mapping (C).** `Filename` maps verbatim to `Data/Sounds/<Filename>.wav`, backslashes as separators, spaces and punctuation preserved: `"Blaster\\Single Shot 1"` ↔ `Data/Sounds/Blaster/Single Shot 1.wav`; `"Inventory\\QuickWheelOpen"` ↔ `Data/Sounds/Inventory/QuickWheelOpen.wav`; `"Xeno Blaster\\XENO - Charge - Loop"` ↔ `Data/Sounds/Xeno Blaster/XENO - Charge - Loop.wav`; `"rod_warp1_v1"` ↔ `Data/Sounds/rod_warp1_v1.wav`. The folder holds 46 top-level entries (41 wav + 5 subfolders; 62 wav recursively) for 58 declared sounds.

**Positional vs 2D.** The third `PlaySound` argument is an entity/engine handle: passing it makes a 3D source attached to that entity; omitting it makes a 2D UI/global sound. Call sites split ~29 positional / ~25 2D, with a clean convention (**C** usage, **I** semantics). *Positional*: ship engines and atmosphere fire/wind (`EGDataShipPlayer.lua:423-432`, `447-448`), `DeathFire` (`EGDataShipBattleship.lua:153`), jetpack and
depressurisation (`EGCharacterActor.lua:279`, `366`), light activation (`482-485`), pickups (`EGDataItems.lua:18`, `1084`), airlock hiss (`376`), extinguisher (`1345`), grav-bike (`EGDataWeapons.lua:344`), robot/xeno voice (`EGDataCharacterRobot.lua:151`). *2D*: every menu and UI sound (`EGMenuHUD.lua:670`, `EGMenuInventory.lua:106`, `EGMenuQuickSelection.lua:54`, `EGMenuAirlock.lua:14`, `EGMenuOperations.lua:17`), input-mode
notices (`EGActionBindings.lua:372-378`). Menu highlight/unhighlight sounds are declared (`EGAudio.lua:364-392`) but their calls are commented out (`EGTile.lua:50`, `55`) — highlighting is silent.

**Music.** `Music` is plain `{Filename, Loop, Volume}` data (`709-717`) in two shapes: **per planet with four states** — `Orbit`, `Entry`, `EntryComplete`, `Surface` (`Perun` `720-749`, `Veles` `753-782`, `Jarilo` `785-814`, `Morena` `817-846`) — and **pools**: `Music.Explore` (4 tracks with differing volumes, `848-870`), `Music.Combat` (3, `872-889`), plus `Music.RodinaTheme` (`712-717`). Playback is single-track with a
fade-out/queue-in handshake from `Gameplay/EGSceneSolar.lua`: `UpdateMusic` (`160-173`) treats `IsMusicPlaying()==false` as "track finished" (no end callback); `SetMusicExplore`/`SetMusicCombat` (`194-222`) pick randomly, `FadeMusic(0, 4)` / `(0, .5)`, then `QueueMusic`; `SetMusicPlanet` (`225-255`) maps state → descriptor with per-state fades (4 s default, 0.75 s Entry/Arrival, 2 s EntryComplete); `CheckCurrentMusic` (`258+`)
prefers the menu theme, then gear-4 explore, then combat timer, then planet state. A hard `FadeMusic(0, 0.1)` exists on the music-off path (`EGDataProgress.lua:567`).

`.egu` files in `Data/Music/` (24) are **opaque**: `file` reports `data`, headers are high-entropy with no ASCII magic (`Rodina Main Titles.egu` starts `01 c8 a7 b2 f6 d9 75 60 …`) — compressed and/or encrypted. Table track names match filenames exactly (spaces and dashes). Codec, channels, sample rate, loop metadata and streaming are **U**; treat `.egu` as engine-private.

**Procedural voice.** Robot and xeno speech is **synthesised, not sampled**: `Gameplay/EGRobotVoice.lua` (and `EGXenoVoice.lua`) generate phrase arrays of note events (`NoteStart`, `NoteEnd`, `WaveType`, `SquareWaveDuty`, `Tremelo`, `TremeloFrequency`, `Vibrato`, `VibratoFrequency`; `13-60`), with a per-character pitch offset and seed-chosen waveform (`13-29`), plus love/chatter/music/panic generators (`62`, `95`, `139`,
`222`), performed via `System.Audio.PlaySoundKeys("Robot Voice", phraseKeys, 1, self.Engine)` (`EGDataCharacterRobot.lua:151`, `EGDataCharacterXeno.lua:150`). The `"Robot Voice"` declaration has **no `Filename`** and no matching file (`EGAudio.lua:5-14`) — **I** that it is a synthesiser preset. The idea: alien speech as a deterministic function of a character seed, so it is unbounded, cheap and per-character consistent.

## 6. Options

**Two files.** `DataGameplay/EGOptions.lua` (192) holds `DefaultOptions` (`5-152`), `EGBuildCurrentOptions()` which copies defaults, overlays the saved profile, pushes every primitive via `System.UpdateOption(k,v)` and applies FOV (`155-179`), plus `EGSetOption`/`EGGetOption` (`184-192`). `Gameplay/EGMenuOptions.lua` (1030) is the UI: a flat `AvailableOptions` list (`12+`) of rows `{Name, Key|Keys, Type, Range, Granularity,
Choices, ValueToString, FormatValueDisplay, RequiresRestart, HelpText, OnClick}`, rendered by `EGOptionsMenu` (650×550, `5-10`) at 28 px pitch with a clickable `"?"` when `HelpText` exists, re-reading values each frame (`873-989`). A click runs `OnClick` or opens `EGOptionPopupMenu` (`992-1011`); `"?"` opens `EGMenuPrompt` (`1013-1019`); closing calls `System.Profile.OnUpdate()` then `EGMenu.Close` (`1028-1030`).

| Option key | Default | UI exposure / effect |
|---|---|---|
| `CombatDifficulty` | `1` | "Combat Difficulty" 0–1 step .1 (`134-141`): damage taken, fire spread |
| `FPSCombatDifficulty` | `1` | "FPS Combat Difficulty" 0–1 (`126-133`): on-foot damage |
| `MovementDifficulty` | `1` | "Movement Difficulty" 0–1 (`142-149`): crash/burn, atmo entry, Limnal |
| `AtmosphereEntryPush` | `1` | "Atmospheric Entry Difficulty" 0–1 (`150-157`); scales push via `kAtmospherePushMult * MovementDifficulty * AtmosphereEntryPush` (`EGVehicle.lua:1128`) |
| `CameraShake` | `1` | "Camera Shake" 0–1 step .1 (`158-165`) |
| `CameraFOV` | `60` | "Camera FOV" 20–150 step 5 (`533-539`); applied at load (`EGOptions.lua:175-178`) |
| `CameraForwardOffset` | `0.0` | profile-only |
| `CharacterLookSpeed` | `1.5` | "Character Turn Speed" .15–10 step .05 (`254-262`) |
| `ShipLookSpeed` | `1.25` | "Ship Turn Speed" .15–3 step .05 (`290-298`) |
| `ShipRollSpeed` | `1` | "Ship Roll Speed" .1–1 step .1 (`313-322`) |
| `MouseSensitivity` | `0.075` | deprecated row; help says keep 0.075 (`829+`) |
| `MouseSmoothingFactor` | `.5` | "Mouse Smoothing" (`378+`) |
| `InvertCharacterY` / `InvertShipY` | `false` | "… Invert Mouse" (`263-275`, `324-337`) |
| `InvertCharacterControllerY` / `InvertShipControllerY` | `false` | "… Invert Controller" (`276-288`, `337-350`) |
| `GamepadSwapShipSticks` | `false` | "Ship Swap Controller Sticks" (`350-364`) |
| `GamepadSwapShipRollYaw` | `false` | "Ship Swap Controller Yaw/Roll" (`364-377`) |
| `GamepadSensitivityCharacter X/Y/Z` | `.4 / .3 / 1.0` | profile-only |
| `GamepadSensitivityShip X/Y/Z` | `1.2 / 1.2 / 1.2` | profile-only |
| `ControllerDeadZone` | `.2` | profile-only |
| `AutoAimAiming` / `AutoAimTracking` | `1.0 / 1.0` | "Gamepad Aim Assist (Aiming)/(Tracking)" (`397-416`) |
| `ShipHorizonRollStrength` | `1.0` | "Ship Horizon Levelling" (`387-396`) |
| `Autosave` | `true` | "Autosave" bool (`112-125`) |
| `AutosaveTimeLimit` | `20` | **not exposed**: seconds cooldown, read `EGGame.lua:409`, compared to `self.AutosaveTime` (`415`) |
| `AtmosphereEntryHintTime` | `60` | profile-only |
| `PauseOnLoseFocus` | `true` | "Pause on Window Losing Focus" (`214-226`) |
| `ShowCursorDuringGameplay` | `false` | profile-only; `EGSceneSolar.lua:96` |
| `CursorCustom`/`CursorPath`/`CursorLimitToWindow` | `true` / `.\Data\Cursor3.cur` / `false` | profile-only |
| `ShowPlanetDonuts`/`ShowVehicleDonuts`/`ShowActorDonuts`/`ShowDebrisUI` | all `true` | profile-only; `EGPlanet.lua:593`, `EGGravBike.lua:128`, `EGVehicle.lua:1931`, `EGTargetProxy.lua:79` |
| `ColorBlind` | `false` | "Colorblind Mode", `RequiresRestart=true` (`763-777`); swaps donuts for letter textures |
| `MusicVolume` / `SoundVolume` | `.5 / .5` | 0–1 step .01, shown ×100 (`88-107`) |
| `MaxSoundCount` | `40` | profile-only |
| `DisableMusic` | `false` | "[Debug] disable music" (`792-806`) |
| `Subtitle*` | — | **no subtitle option or system in `Scripts/`** (grep `Subtitle` = 0); dialogue is documents + voice. Engine CC is **U** |
| `ReticleDistanceClose` / `Far` | `200` / `100000` | profile-only; reticle projection (`EGMenuHUD.lua:453-454`) |
| `RetroMode` / `RetroModePixelSize` | `false` / `4.5` | exposed (`228-249`) |
| `MaxFramerate` / `VSync` | `90.0` / `false` | exposed (`743-762`) |
| `GlobalParticleRateMult` | `1.0` | "Particle Rate" (`735-742`) |
| `RelaxCPUUsage` / `DisableGPUTiming` | `true` / `false` | exposed (`778-826`) |
| `ConsoleEnabled` | `false` | "Console" (`36-49`) |
| `AllowFires` / `RespawnEnemies` / `RespawnVanguardEnemies` | `true` / `false` / `false` | rows commented out (`166-213`) |

Two structural points: many gameplay-feel knobs exist only in `DefaultOptions`, so the menu is a *curated subset* rather than a mirror (`AutosaveTimeLimit`, donut visibility, `ShowCursorDuringGameplay` are profile-only); and difficulty is three normalised `0..1` multipliers applied directly to formula terms, not named presets.

## 7. Evidence table

| # | Finding | File : lines | |
|---|---|---|---|
| 1 | All UI is one `EGTile` node type with engine-backed state | `EGTile.lua:3`, `16-21` | C |
| 2 | Retained tree (built in `Setup`, mutated in `Update`), not IMGUI | `EGMenu.lua:55-57`, `EGMenuOperations.lua:26-34` | C |
| 3 | State protocol NORMAL/HIGHLIGHT/DEPRESSED/ENABLED/DISABLED/ON/OFF | `EGTileUtil.lua:50-76`, `177-184` | C |
| 4 | `EGMenuSystem.lua` entirely commented out; engine owns the stack | `EGMenuSystem.lua:3`, `400` | C |
| 5 | Menu API is `Open/GetOpen/CloseMenu/SetDefaultButtonPos` | `GameplayMain.lua:27-30`, `EGMenuHUD.lua:162-167` | C |
| 6 | Top-down stack hit test stopping at `GetBlocksInput` | `EGMenuSystem.lua:331-348` (reference) | I |
| 7 | `Update(dt, active)`; active = top menu *and* focused window | `EGMenuSystem.lua:285-292`, `EGMenuHUD.lua:159` | I |
| 8 | `INPUT_*` vocabulary + base state dispatch | `EGMenu.lua:106-144`, `EGMenuSystem.lua:6-17` | C |
| 9 | Tile names double as button IDs | `EGMenuPilot.lua:93-127`, `EGMenuOperations.lua:366-391` | C |
| 10 | Render style = enum, texture name, or `MenuGen` generator | `MenuStyle.lua:5-7`, `EGMenuHUD.lua:1485`, `EGMenuInventory.lua:191` | C |
| 11 | `MenuGen` = procedural pass graph uploaded via `System.SetTexture` | `TextureGen.lua:28-83`, `120-125`, `RenderMain.lua:31-47` | C |
| 12 | 19 pass types (rect/circle/convex/light/mask/blend/perlin/…) | `TextureGenPasses.lua:16-452` | C |
| 13 | Panel look is a 9-pass lighting stack | `MenuGen.Background.lua:22-92` | C |
| 14 | 75 role-named font declarations (face+size+align) | `MenuFonts.lua:5-1038` | C |
| 15 | `.spritefont` = pre-baked DXTK atlas named `Face_Size` | `Data/Fonts/FontCache/*`, magic `DXTKfont` | C format / I use |
| 16 | Any `MenuMode` menu pauses the sim | `EGSceneSolar.lua:73-74`, `EGMenu.lua:8` | C |
| 17 | HUD family is `MenuMode=false` (overlay without pause) | `EGMenuHUD.lua:8-10`, `EGMenuHUDStatus.lua:6-8` | C |
| 18 | `CursorMode` drives the OS cursor | `EGSceneSolar.lua:52-53`, `76-77`, `EGMenuInventory.lua:16` | C |
| 19 | `FreezePlayerMode` freezes player input, not the world | `EGMenuInventory.lua:18`, `EGCharacterActor.lua:174`, `184` | C |
| 20 | HUD is a singleton `HUD`, opened by `EGMenuMain:Start` | `EGMenuHUD.lua:15-18`, `EGMenuMain.lua:378-383` | C |
| 21 | HUD opens child menus at progress stage `EnableHUD` | `EGMenuHUD.lua:161-169` | C |
| 22 | HUD children render to offscreen targets | `EGMenuHUDStatus.lua:9`, `EGMenuHUDEquipment.lua:9` | C |
| 23 | Health bars are rescaled tiles (175 px × percent) | `EGMenuHUDStatus.lua:42-53` | C |
| 24 | Damage/heal = full-screen `Solid` overlays at depth 10 | `EGMenuHUD.lua:689-732`, `740-777` | C |
| 25 | Warning blinks and plays `MissileAlarm` with runtime pitch | `EGMenuHUD.lua:648-673`, `228-247` | C |
| 26 | Notification channel is a dedup queue at 3 s each | `EGMenuHUD.lua:249-266`, `629-645` | C |
| 27 | Tutorial text uses the document renderer (`SetAsDocument`) | `EGMenuHUD.lua:960-977` | C |
| 28 | Gears 1–4 = Docking/Combat/Cruising/Limnal | `EGMenuHUD.lua:607-626`, `998-1048` | C |
| 29 | Gear marks are four `PassConvex` polygons | `MenuGen.HudGears.lua:127-220` | C |
| 30 | Ammo "depleted" is a font swap | `EGMenuHUD.lua:269-301` | C |
| 31 | Planet donuts are entity-owned tiles with facing/distance alpha | `EGPlanet.lua:509-539`, `550-635` | C |
| 32 | Colourblind swaps donuts for letter textures | `EGPlanet.lua:649-672`, `EGDataPlanets.lua:32` | C |
| 33 | Target frame = projected screen box of the 3D entity | `EGMenuHUD.lua:1459-1641`, esp. `1614-1618` | C |
| 34 | Altimeter has floating (clamped) and locked modes | `EGMenuHUD.lua:1644-1750`, `EGMenuPilot.lua:103-117` | C |
| 35 | Actions declare `Tap`/`Hold`, default-bound, profile-overlaid | `EGDataActionBindings.lua:3-59`, `63-174` | C |
| 36 | Compounds synthesise vectors; ship swap/invert lives there | `EGActionBindings.lua:144-269` | C |
| 37 | Gamepad mode auto-detected by compound magnitude comparison | `EGActionBindings.lua:364-382` | C |
| 38 | Menu gamepad nav moves the OS cursor to the focused tile | `EGMenuSystem.lua:145-196` (reference) | I |
| 39 | `CANCEL_MENU` device-special-cased (pad B vs Esc) | `EGActionBindings.lua:272-293` | C |
| 40 | 58 `LoadSound` blocks with ramp/loop/attenuation fields | `EGAudio.lua:5-707` | C |
| 41 | `Filename` → `Data/Sounds/<path>.wav`, backslash separators | `EGAudio.lua:74-84` + `Data/Sounds/*` | C |
| 42 | Third `PlaySound` arg = entity → positional; omitted → 2D | `EGDataShipPlayer.lua:423-432` vs `EGMenuHUD.lua:670` | C usage / I meaning |
| 43 | Only 5 pitch calls exist (alarm + engine loops) | grep `SetSoundPitch` | C |
| 44 | Music is data keyed by planet/state plus Explore/Combat pools | `EGAudio.lua:709-889` | C |
| 45 | Transition = `FadeMusic(0,t)` then `QueueMusic`; end is polled | `EGSceneSolar.lua:160-173`, `194-255` | C |
| 46 | `.egu` opaque high-entropy container; names match track table | `Data/Music/*.egu` header bytes | C opaque / U codec |
| 47 | Robot/xeno voice = seed-driven procedural pitch envelopes | `EGRobotVoice.lua:13-60`, `EGDataCharacterRobot.lua:151` | C |
| 48 | `"Robot Voice"` has no Filename and no file → synth preset | `EGAudio.lua:5-14` | I |
| 49 | Defaults in `DefaultOptions`, profile overlaid, pushed to engine | `EGOptions.lua:5-179` | C |
| 50 | Options UI = flat 28 px rows, `?` help popup, popup editor | `EGMenuOptions.lua:873-1025` | C |
| 51 | `AutosaveTimeLimit=20` exists but is not menu-exposed | `EGOptions.lua:119`, `EGGame.lua:409` | C |
| 52 | No subtitle option or subtitle system in `Scripts/` | grep `Subtitle` → 0 | C absence |
| 53 | Difficulty = three 0–1 multipliers, not presets | `EGOptions.lua:58-60`, `EGVehicle.lua:1128` | C |
| 54 | `EGMenuShipLayout` is an editor mode inside the menu stack | `EGMenuShipLayout.lua:5-25`, `707-790` | C |
| 55 | Radial commits on key release; one impl for four item types | `EGMenuQuickSelection.lua:255-278` | C |
| 56 | Airlock = pressure bar + doors + remote-pilot terminal | `EGMenuAirlock.lua:56-90`, `160-213` | C |
| 57 | Scanners content gated by progress stages and owned documents | `EGMenuScanners.lua:280-348` | C |
| 58 | Menu highlight sounds declared but calls commented out | `EGAudio.lua:364-392`, `EGTile.lua:50`, `55` | C |

## 8. Reusable conceptually for a Godot 4 game

Not code and not asset formats — the ideas, restated in Godot terms.

1. **One node type, style from a registry** — `EGTile` + `RenderStyle` string → one `Control` scene whose look comes from `Theme`/`StyleBox` types; keep state names as the contract and let the theme resolve them.
2. **State protocol over per-widget code** — a fixed `SetState(name)` vocabulary lets button, toggle, link and slider share one input driver (one `_set_state()` virtual in Godot).
3. **Anchors and fractions, never pixels** — Rodina's HUD survives 4:3 → ultrawide because everything is anchor + relative size; use Godot anchor presets and container size flags the same way.
4. **Split pause / cursor / input-lock into three flags** — a `UILayer` with `pauses_tree`, `shows_cursor`, `locks_player_input` plus a stack routing input top-down and honouring `blocks_input` beats a single `paused`.
5. **HUD as several small overlay scenes** opened by a progress gate — composed `CanvasLayer`/`Control` scenes, panels optionally in `SubViewport`s (Rodina's offscreen targets).
6. **Virtualised lists via a scroll table** — the transferable detail is *row height as the only layout parameter*, which keeps windowing maths trivial.
7. **Transient channels replace by default; queue only where order matters** — warning (blink + expire), gear notice (1 s), tutorial (rich text), discovery (10 s fade), one dedup queue (notifications, 3 s).
8. **World markers as scene nodes** — entity-owned tiles with facing/range alpha and keep-onscreen clamping; in Godot `unproject_position()` per frame, visibility from a dot product, clamped position rather than hiding off-screen markers.
9. **Target frame = projected AABB** — corners at the min/max of unprojected `AABB` corners; more robust than a fixed reticle for varying-size objects.
10. **Actions with declared Tap/Hold plus compound synthesis** — declare `{name, display, style}`, bind per device, tap = just-pressed edge, hold = analog level, build `move`/`look` compounds from scalars, apply device remaps (stick swap, invert, roll/yaw) *in the compound*, auto-detect gamepad vs mouse by magnitude.
11. **Device-special-cased cancel** (pad B / Esc for menus, independent of gameplay cancel) prevents a class of "menu won't close" bugs.
12. **Hold-to-open radial, release-to-commit** — one scene parameterised by an exported `SelectionType`, emitting `selected(item)` on close.
13. **Grid inventory with delegated dragging** — engine owns pointer capture, script owns placement rules; in Godot `_get_drag_data`/`_can_drop_data`/`_drop_data` over a fixed-cell grid.
14. **Sound definitions as data with ramp and attenuation** — separate *how it starts/stops* (`UpSpeed`/`DownSpeed`) from *how it attenuates* (`MinDistance`/`Attenuation`); tween `volume_db`.
15. **Positional by construction** — one `Sfx.Play(name, {at = node})` facade choosing `AudioStreamPlayer3D` vs `AudioStreamPlayer` keeps UI sounds deliberately 2D.
16. **Music as a data-driven state machine** — per-planet state sets + pools + `fade(t)` → `queue(track)` + a "finished" poll; the per-state fade times (0.75 s entry, 4 s orbit) are what make transitions feel scored.
17. **Procedural voice from a seed** — `AudioStreamGenerator` or a generated `AudioStreamWAV` keyed by `(character_seed, phrase_type)` gives unlimited variety with tiny assets.
18. **Options as data rows plus one defaults table** — a flat `{Key, Type, Range, Granularity, Choices, ValueToString, RequiresRestart, HelpText, OnClick}` list generates sliders/steppers/toggles/actions; overlay the profile on one authoritative defaults table, expecting a curated menu to drift from it.
19. **Normalised difficulty multipliers instead of presets** — three `0..1` floats on formula terms is trivially tunable and composable.
20. **What not to port** — the `MenuGen` pass graph (Godot `StyleBox` + shaders do it with far less machinery), synthetic-mouse-cursor gamepad navigation (`FocusMode`/`focus_neighbor_*`), and "tile name is the button ID" string matching (use signals or bound metadata).

### Open questions (not determinable statically)

- Engine menu internals: stack ownership, `IsMenuMode`/`IsMenuCursorMode`/`IsMenuFreezePlayerMode`, `CreateMenu`, offscreen-target compositing.
- `.egu` codec, channels, loop metadata, streaming vs preload.
- Whether sound categories, ducking or voice limits exist internally (`MaxSoundCount=40` is only a soft option).
- Whether any subtitle/closed-caption system exists (nothing in Lua suggests one).
- The exact `RenderStyle` resolution order (enum → texture → `MenuGen` generator) is inferred from the three value families and `RenderMain.GenerateTexture`, not observed.

