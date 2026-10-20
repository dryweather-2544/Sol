# Rodina physics audit (flight, atmosphere, gravity, ramp) and how Sol now follows it

Sources, all read in full for the functions cited: the extracted Rodina 1.6.2 scripts in the private repo
`dryweather-2544/rodina` (commit `eb8c6f1`, "Add Rodina Lua scripts"; 160 `.lua` files under `Scripts/`):
`Gameplay/EGVehicle.lua` (2288 lines), `DataGameplay/EGDataShipPlayer.lua`, `Gameplay/EGBehaviorPlayer.lua`,
`Gameplay/EGBehavior.lua`, `Gameplay/EGPlanet.lua`, `DataGameplay/EGDataPlanets.lua`, `DataGameplay/EGOptions.lua`,
`Gameplay/EGMenuOptions.lua`, `Gameplay/EGActionBindings.lua`, `DataGameplay/EGDataItems.lua`, `EGUtility.lua`.
They were read as evidence of behaviour only (CLAUDE.md: no Rodina code is copied into Sol).
`research/rodina-starfall-reference/02_SPACESHIP_AND_PILOTING.md` summarised the same code; where it differs from the
code, the code wins (two differences are noted below).

Tags: **[C]** read in the Lua; **[E]** engine-side (C++), only the call is visible; **[I]** Sol's inference.
`EGAnalogue(x, a, b, c, d)` = map x from a..b to c..d, clamped (`EGUtility.lua:126`); `EGDeltaTo` = move toward a
target by at most a step (`:259`).

## 1. Shared interface and update order

| Rule | Source | Tag |
|---|---|---|
| Player and AI fill one pilot interface: gear, MoveVector (local x right, y forward, z up), MoveLock, FaceVector or TurnVector, Clutch, LockLinearMovement | `EGBehaviorPlayer.lua:206-235`, `EGBehavior.lua:57-83`, `EGVehicle.lua:594-620` | C |
| Per update: ApplyMovement, collision damage, movement control, roll levelling, atmosphere movement, walkway | `EGVehicle.lua:560-569` | C |
| Movement and rotation use the physics time step | `EGVehicle.lua:1249-1251, 1393-1397` | C |
| The engine integrates `SetMovementVelocity`, `AddLocalAcceleration`, `SetRotationVelocity`, `AddRotationVelocity` (Havok, `PHYSICS_DRIVEN`) | `EGVehicle.lua:1540-1554`, `:646-662` | E |
| Player rotation axes: TurnVector x yaw, y pitch, z roll (mouse x is negated) | `EGActionBindings.lua:226-262`; `EGVehicle.lua:1340-1360` | C |

**Sol mapping [I]:** Sol's ship-local axes are x right, y up, -z forward; turn is x pitch (+ nose up), y yaw (+ nose
left), z roll (+ right wing up). Rodina's move x/y/z = Sol x / -z / y; Rodina turn x/y/z = Sol y / x / z. The rules
below are written in Sol's axes in `src/flight/flight_model.gd`.

## 2. Linear movement (`SetDesiredMovement`, `EGVehicle.lua:1390-1568`)

| Rule | Source | Tag |
|---|---|---|
| Velocity steps toward `target = input x MoveSpeed` by at most `Acceleration x MoveSpeed x strength x dt` (`strength` = length of the scaled input) | `:1493-1517` | C |
| **No input: strength 0, so no change at all** - the ship keeps its momentum | `:1503-1517` | C |
| Braking over MoveSpeed (input against the motion, speed > MoveSpeed): rate `max(Acceleration, Deceleration) x speed` | `:1496-1501` | C |
| Sideways and vertical input scaled by MoveStrengths x/z, and backward input by y, **only while not braking** | `:1480-1492` | C |
| Engine drag only above DragSpeed: `-velocity x min(1, Deceleration)` applied to the inertia and again as an engine acceleration | `:1471-1477` | C (double application: C; its effect in Havok: E) |
| MoveLock 0..1 lifts the acceleration limit to match the target exactly | `:1511-1515` | C |
| Clutch (or dead): velocity kept, no drive | `:1443-1454` | C |
| Gravity added every update: planet gravity x `GravityMult x 9.8 x 3.5`, with a 0.33 g floor on SurfaceGravity | `:1546-1554`, constants `:8-9`; `EGPlanet.lua:150-158` | C |
| Gear 4 (Limnal) and relative time (cruise multiplier) | `:1437-1441, 1462-1469, 1526-1538` | C (not used by Sol) |

Player-ship gear table, `EGShipPlayer:UpdateGearSettings` (`EGDataShipPlayer.lua:131-177`) [C]:

| Rodina gear (Sol) | MoveSpeed | DragSpeed | Accel | Decel | MoveStrengths x,y,z | Hardness | RotationFriction |
|---|---|---|---|---|---|---|---|
| 1 dock (0) | 100 | 1500 | 0.66 | 0.9 | 0.3, 0.3, 1.0 | 0.35 | AtmosphereFriction at ratio <= 0.5, 0 at >= 1 |
| 2 combat (1) | 500 | 1500 | 2.0 | 0.75 | 0.3, 0.6, 0.3 | 0.7 | same |
| 3 cruise (2) | 5000-10000 by surface distance | 1.25 x MoveSpeed | 0.5 | 0 | 0.3, 0.6, 0.3 | 0.7 | AtmosphereFriction at <= 0.4, 0 at >= 1 |

The research summary called Deceleration "the braking rate"; in the code it is only used above MoveSpeed (braking)
and for the DragSpeed drag. MoveStrengths y applies to **backward** input only; forward is always full (the summary
said "lateral/vertical").

## 3. Rotation

| Rule | Source | Tag |
|---|---|---|
| Player: turn input is **angular acceleration** `input x ShipLookSpeed(1.25) x Hardness x RotationSpeed x dt` (pitch, yaw) | `EGVehicle.lua:1335-1352`; `EGOptions.lua:100` | C |
| Roll: `input x min(2, Hardness) x BarrelRollFactor x 3 x RotationSpeed x dt`; BarrelRollFactor rises 0 to 1 over 1 s while roll is held | `:1292-1298, 1346` | C |
| Pitch+yaw capped together at RotationSpeed (2.5 rad/s, player ship); roll at 2 x | `:1353-1360`; `EGDataShipPlayer.lua:11` | C |
| Small input squared (vector x its length) | `:1317-1324` | C |
| Friction `RotationFriction x dt x (1 - strength)^2` multiplies the spin down: only while coasting | `:1270-1291` | C |
| RotationFriction is 0 in space, the planet's AtmosphereFriction deep in the air (most worlds 1, Veles 1.5) | `EGDataShipPlayer.lua:139,157,177`; `EGDataPlanets.lua` | C |
| Acceleration boost timer exists but its result is overwritten with 1 | `:1300-1315` | C |
| AI: `SetDesiredFacing` sets the rotation velocity directly (angles to the target x RotationSpeed, 0.1 arrival), no inertia | `:1212-1244` | C |
| Gravity look (nose pulled toward a planet) only in Limnal gear | `:1372-1385`; `EGDataShipPlayer.lua:86, 222` | C (not used by Sol) |

## 4. Atmosphere

| Rule | Source | Tag |
|---|---|---|
| States: entering below ratio 1; "in" below 0.5, which starts a 4 s entry timer; both cleared above 1 | `EGVehicle.lua:977-1037`, `:5` | C |
| Resistance only while entering (ratio < 1 and not yet "in", or timer running): `into x strength x speed factor`, into = dot(velocity dir, to planet) mapped -0.5..0.75 to 0..1, strength = ratio 1..0.9 mapped 0..1 (x timer fraction), speed factor = speed 0..10000 mapped 0..2 | `:1077-1103` | C |
| Damage (player) above resistance 0.85: up to 15% MaxHealth/s x MovementDifficulty (1); "STEEP REENTRY" warning | `:1105-1118`; `EGOptions.lua:59` | C |
| The air pushes the nose toward "up": angles x resistance x 0.005 x difficulty x AtmosphereEntryPush (1) added to the spin each update | `:1121-1131`; `EGOptions.lua:113` | C |
| **No speed drag, no lift, no aerodynamic stability** in the scripts | absence in `:1077-1139` and all callers | C (absence) |
| Roll levelling: only while "in" the atmosphere and the option > 0; roll only; rate limit `0.6 pi x levelFactor x altitudeFactor x gravityFactor x option` (levelFactor fades to 0 at a pitch of 1.2..0.7 rad, altitudeFactor 1 at ratio 0.25 to 0.1 at 1, gravityFactor 0.2..1 by surface g); applied as angular acceleration `(rate - roll spin) x AutoLevelFactor x 3`; during the entry timer the rate is `roll / timer` | `:1152-1198` | C |
| Option `ShipHorizonRollStrength` default 1.0 ("Ship Horizon Levelling") | `EGOptions.lua:133` | C |
| AutoLevelFactor = 1 - block; rolling by hand raises the block, which fades at 1/s | `EGBehaviorPlayer.lua:34-41` | C |
| **No pitch levelling and no altitude threshold** anywhere | absence in `UpdateLevel` and all callers | C (absence) |

## 5. Contact, landing, ramp

| Rule | Source | Tag |
|---|---|---|
| Player hull: mesh, mass 5000, friction 0.4, restitution 0.8, no linear/angular damping | `EGDataShipPlayer.lua:26-38` | C (values); E (Havok response) |
| Landed when within 1 m of the last terrain contact and slower than 4 m/s | `EGVehicle.lua:2009-2047` | C |
| Control authority ramps back over 0.5-1.5 s after a collision and 0-0.2 s after terrain contact | `:847-884` | C (values); E (meaning) |
| Walkway: a Box physics object, motion type `EG_MOTION_ANIMATED_WALKWAY`, spawned/removed by speed; no script moves or turns a walker on it | `EGDataItems.lua:1148-1157`; `EGDataShipPlayer.lua:452-485` | C (absence of steering) |

## 6. What Sol did differently (the causes) and what changed

| # | Sol before | Rodina | Change (file) |
|---|---|---|---|
| 1 | Ramp: walkers over its upper part were switched into the interior frame, lifted up to ~1 m onto it and boxed in by its 1.8 m width; exit only at its far end | A physics box; ordinary walking | Ramp is an outside floor with solid sides; inside/outside at the doorway with heading and velocity kept; ramp end re-fitted every tick (`src/game/game_session.gd`, `src/interior/ship_hull_collision.gd`, `src/interior/interior_layout.gd`) |
| 2 | Below 400 m (full at 150 m) pitch and roll rate driven toward planet-up when not pitching/rolling | Roll-only levelling in the air, by acceleration; none for pitch | Removed `level_assist`; Rodina roll levelling + setting (`flight_model.gd`, `planet_body.gd`, `game_settings.gd`, `pause_menu.gd`) |
| 3 | No thrust: each axis braked to zero (also in vacuum) | No input: nothing applied | Rodina rule (`flight_model.gd`) |
| 4 | Speed over the cap bled off in ~0.33 s | Drag only above DragSpeed | Rodina rule |
| 5 | Atmosphere scaled top speed 0.25..1 (`max_speed_factor`) | No such rule | Removed |
| 6 | Gravity 1 x planet, cancelled by the assist (ship hovered) | 3.5 x planet, 0.33 g floor, never cancelled | `PlanetBody.ship_gravity_at` |
| 7 | Turn input = target rate, 8 rad/s^2 up, 10 rad/s^2 down (a spin stopped in 0.15 s) | Input = angular acceleration; friction only coasting, only in air | Rodina rule (`flight_model.gd`) |
| 8 | Caps 1.5/1.5/2.5 rad/s; one axis-strength vector for all gears | 2.5 combined pitch+yaw, 5 roll; per-gear table | `ship_tuning.gd` |
| 9 | Re-entry heat: any speed over 5000 m/s anywhere in the air | Resistance only while entering, by dive angle and speed; push on the nose | `ship_damage.gd`, `flight_model.gd`, `ship_effects.gd` |
| 10 | Touching (not landed): no friction at all | Hull friction 0.4 | `ground_contact.gd` |
| 11 | AI turn demand went through the same rate controller | AI sets the rate directly; AI mover locks velocity | `face_direction` path, `move_lock` (`flight_model.gd`, `ai_pilot_source.gd`) |

Verified unchanged: a frame switch converts only position and velocity (`src/game/world_runtime.gd:54`); the frames do
not rotate, so orientation and spin pass through untouched. Rotation is integrated once per 60 Hz tick from ship-local
spin with a normalised quaternion step (`flight_model.gd`); the camera only reads the ship transform.

## 6b. Gears (flight-speed modes)

| Rule | Source | Tag |
|---|---|---|
| Four gears: 1 dock/landing, 2 combat, 3 cruise, 4 Limnal (table in §2) | `EGDataShipPlayer.lua:131-233` | C |
| The player's chosen gear lives in the player behaviour; every update the vehicle is set to the highest **allowed** gear, and the choice is kept | `EGBehaviorPlayer.lua:97-156`, `EGShipPlayer:GetAllowedGear` `EGDataShipPlayer.lua:52-81` | C |
| Gating is by story and items only (cruise needs `CruiseEngineAcquired`, Limnal needs Diaconium and a clear path), never by altitude | `EGDataShipPlayer.lua:52-81` | C |
| Shifting: hold CLUTCH (right mouse) and press SHIFT UP/DOWN (W/S); a refused shift plays "ShiftGrind" | `EGBehaviorPlayer.lua:102-148`; `EGDataActionBindings.lua:97-98` | C |
| Cruise MoveSpeed 5000 m/s at the surface rising to 10000 m/s at 20 km, lowered near other ships | `EGDataShipPlayer.lua:169-170` | C |
| In the air relative time is forced to 1; while entering (not yet "in") MoveSpeed <= 5000 and DragSpeed <= 6000 | `EGVehicle.lua:944-958` | C |
| Above the air, cruise speed is multiplied by relative time `min(CruiseMax, CruiseMult x (d / cruiseRadius)^CruiseExponent)` | `EGDataShipPlayer.lua:178-195` | C |
| The HUD shows the current gear | `EGMenuHUD.lua:516-536` | C |

**Sol (`src/flight/flight_model.gd`, `src/planet/planet_body.gd`, `src/flight/ship_tuning.gd`):** four gears. Gear 3
is Sol's WARP/Limnal mode: it is gated by the installed warp coil and the system-frame environment, uses a 6.7x
distance-scaled cap and burns fuel faster than cruise. It is deliberately not a direct port of Rodina's gear-4
relative-time model because Sol's cruise is already distance-scaled. `ShipState.selected_gear` keeps the choice and
`gear` is the gear in effect, as Rodina does; both are saved. Cruise is allowed at any height (Sol had refused it below 2 km and
capped it at 0.3 x altitude: 600 m/s at 2 km, the main cause of the slow climb), with Rodina's in-air speeds and entry
cap; above the air Sol's distance-scaled limit stands in for relative time. Combat is Rodina's unchanged.
**Sol's own, not Rodina's [I]:** gear 0 is a *precision* gear - Rodina's dock gear scaled to Sol's ship (30 m/s, up/down
0.4 so full descent is 12 m/s, under the touchdown damage limit) with station keeping (no input drives the velocity
to zero and the engines hold up to 60 m/s^2 of gravity); small airless worlds keep Sol's 0.3 x altitude cruise limit;
`[ ]` shift directly (no clutch). The drag above DragSpeed is applied once (Rodina writes it twice; how the engine
combines the two is engine-side).

## 7. Open questions (not settled by the scripts)

1. **[E] How Havok combines `SetMovementVelocity` with `AddLocalAcceleration`.** Sol assumes gravity and drag act on
   top of the drive's velocity (the next update reads the result back as inertia, `:1406`), so a hands-off ship falls.
   If the engine instead re-applies the movement velocity after gravity with full authority, Rodina ships would
   hover. Test: in Rodina, release all keys at 1 km in dock gear and time the fall.
2. **[E] Restitution 0.8 and the terrain's own friction.** Sol has no bounce; hull friction uses 0.4 x 1.
3. **[E] `SetVelocityControl(control, terrainControl)`** after impacts (`:847-884`): not modelled.
4. **[E] The AI mover's MoveLock value.** Sol uses 1 for AI and scripted pilots.
5. **[I] Update rate of the entry push** (`AddRotationVelocity` per update, not x dt). Sol scales it to 60 Hz.
6. **Cruise relative time** (Rodina's distance-scaled time compression) is replaced by Sol's distance-scaled speed limit,
   with any excess shed at Rodina's relative-time fall-off rate (2/s, `:1462-1464`).
7. Rodina footage was not available in this session: feel has been checked with telemetry and tests, not against video.
