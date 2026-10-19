# Rodina technical research — flight, camera, entry and transitions

Status: working engineering reference for Sol. This document records **what is actually supported by
the available evidence**, what is inferred, and what remains unknown. It is not a claim that the
original engine has been decompiled.

## 1. Sources and provenance

### Direct evidence

Extracted, read-only Rodina 1.6.2 Lua tree:

`/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/Scripts`

The files carry Elliptic Games copyright headers. They are proprietary source material. Sol does
not copy the Lua implementation; the recovered functions are used to establish observable equations,
state relationships and constants, and Sol implements an independent Godot equivalent.

Existing research archive (read-only, not modified):

- `Documents/Deepseek workspace/rodina-starfall-reference/02_SPACESHIP_AND_PILOTING.md`
- `.../04_PLANETS_AND_TERRAIN.md`
- `.../06_AI_AND_NAVIGATION.md`
- `.../08_STARFALL_IMPLEMENTATION_GUIDE.md`
- `.../09_SOURCE_EVIDENCE_INDEX.md`
- `.../10_OPEN_QUESTIONS.md`
- `.../CORRECTIONS.md`

Secondary public source:

- Hotel Kilo, “Ultimate Rodina Guide”, Steam Community (updated 2019):
  https://steamcommunity.com/sharedfiles/filedetails/?id=298884536
  Used for player-visible behaviour (atmosphere damage/fire, combat-speed safety), not for code.
- Official site: https://elliptic-games.com/?page_id=45 (fetch failed during this session).
- Store page: https://store.steampowered.com/app/314230/

### Not available

- The Rodina engine/C++ camera implementation is not in the extracted tree.
- No compiled-engine decompilation is present in the workspace.
- No local Rodina gameplay recording was available. The community guide is the only direct
  player-observation source used in this pass.
- Exact `.egm` model-space axis conventions cannot be proven from the Lua alone, although the
  vehicle input/interface semantics are explicit.

## 2. Confirmed architecture

### 2.1 One pilot interface

`Scripts/Gameplay/EGBehavior.lua:57-83` defines the shared pilot contract. Both the human player and
AI behaviours fill the same structure. `EGVehicle:ApplyMovement()` consumes it
(`Scripts/Gameplay/EGVehicle.lua:594-620`).

Fields relevant to Sol:

- `Gear`
- `MoveVector` — **local X right, Y forward, Z up**
- `MoveLock`
- `FaceVector` (AI/facing) or `TurnVector` (human angular demand)
- `Clutch`
- `LockLinearMovement`

`Scripts/Gameplay/EGBehaviorPlayer.lua:206-235` fills these from `MOVE_SHIP` and `LOOK_SHIP`.
This is confirmed by two independent call paths consuming the same interface.

### 2.2 Gear table

`Scripts/DataGameplay/EGDataShipPlayer.lua:131-177` gives the player gear settings:

| Gear | Use | MoveSpeed | DragSpeed | Acceleration | Deceleration | MoveStrengths (X right, Y forward, Z up) | RotationHardness |
|---|---|---|---|---|---|---|---|
| 1 | Dock/land | 100 | 1500 | 0.66 | 0.9 | (.3, .3, 1) | 0.35 |
| 2 | Combat | 500 | 1500 | 2 | 0.75 | (.3, .6, .3) | 0.7 |
| 3 | Cruise | 5000–10000 by distance | MoveSpeed × 1.25 | 0.5 | 0 | (.3, .6, .3) | 0.7 |
| 4 | Limnal | 30000 | ∞ | 1 | 0 | (0, 0, 0) | 0.3 |

`EGShipPlayer.RotationSpeed` is **2.5** (`EGDataShipPlayer.lua:11`); base `EGVehicle.RotationSpeed`
is 2.

### 2.3 Linear movement

`EGVehicle:SetDesiredMovement` (`EGVehicle.lua:1390-1568`):

1. Reads local inertia and divides by `LastRelativeTime` to remove warp scaling.
2. Computes `movementAccordance = dot(desiredMovement, inertiaDirection)`, `driveFactor` and
   `brakeFactor` from it.
3. Applies drag only when `inertiaSpeed > DragSpeed`:
   `dragForce = -inertia * min(1, Deceleration)`.
4. Scales lateral and vertical desired movement by `MoveStrengths`; forward (Y) is not scaled.
5. `targetVelocity = desiredMovement * MoveSpeed`.
6. Acceleration is `Acceleration * MoveSpeed`, or `max(Acceleration, Deceleration) * speed` when
   braking above move speed.
7. Moves inertia toward target velocity by at most `acceleration * dt`.
8. Gravity is added as a local acceleration, scaled by `relativeTime`.
9. `LockFactor` can force exact velocity matching.

Important: the movement is **target-velocity with inertia**, not a direct teleport to a speed, and
sideways/vertical trust is intentionally weaker than forward.

### 2.4 Rotation

`EGVehicle:SetDesiredRotation` (`EGVehicle.lua:1247-1387`):

- Reads local angular velocity, its yaw/pitch part, and desired strength.
- Applies friction **only when not turning**:
  `frictionFactor = (1 - desiredStrength)^2`, `friction *= dt`, inertia *= (1-friction).
- Analogue precision: desired rotation is scaled by strength (effectively strength² after length
  normalization).
- Angular acceleration:
  - pitch/yaw: `desired * RotationSpeedOption * hardness`;
  - roll: `desired * rollSpeedOption * rollHardness * BarrelRollFactor * 3`.
  - multiplied by `RotationSpeed * dt`.
- Adds acceleration to inertia.
- Clamps the yaw/pitch angular-speed vector to `RotationSpeed`.
- Clamps roll angular velocity to ±`RotationSpeed * 2`.
- Atmospheric gravity-look / auto-level is separate (`UpdateLevel`, `EGVehicle.lua:1152-1198`):
  roll-only, with a maximum roll speed derived from altitude, gravity and horizon-roll option.
- `SetDesiredFacing` (`EGVehicle.lua:1204-1243`) is different: it computes a facing rotation
  directly, scales by `RotationSpeed`, applies a small arrival falloff (~0.1 rad) and **sets**
  angular velocity. It bypasses the player's inertia path. AI uses this.

The key player-visible consequences are: rotation accelerates, has inertia, and does not magically
stop in vacuum. Facing control is crisp and direct.

### 2.5 Camera

The engine owns the flight camera; there is no Lua camera controller for flight. Lua exposes:

- `SetCameraFollow(distance, angle, stiffness)` (`EGDataShipPlayer.lua:344-348`)
- defaults 200 m, 10°, stiffness 5 (`EGVehicle.lua:40-43`)
- FOV: base option, up to +30° during Limnal warp; distance 200→125 and angle 10→15 during warp
- first-person eye offset `(0,0,1.65)` (`EGPlayer.lua:5`)
- free look sends `SetFreeLookVelocity` and zeroes ship turn (`EGBehaviorPlayer.lua:215-222`)
- camera vibration is registered as a camera actor effect, e.g. atmospheric vibration
  (`EGVehicle.lua:536-538`) and weapon fire.

No lateral offset parameter exists. Any side offset is a Sol composition choice, not a Rodina
camera feature. The exact spring/filter inside the engine is **unknown**.

### 2.6 Atmosphere entry

From `EGVehicle.lua` and research `02_SPACESHIP_AND_PILOTING.md:240-330`:

- `altitudeRatio = (distance - radius) / atmosphereAltitude`.
- Entering:
  - ratio < 1 and not inside/entering → `EnteringAtmosphere = true`, autosave.
  - ratio < 0.5 and not inside → `InPlanetAtmosphere = true`, `EntryCompleteTimer = 4`.
  - no atmosphere and ratio < 1 → inside immediately.
  - ratio > 1 → both false.
- `EntryCompleteTimer` counts down from 4 s. “Success” is timer > 2 (half the entry window).
- Atmospheric resistance:
  - `strengthFactor = analogue(ratio, 1.0, 0.9, 0, 1)`, multiplied by entry timer fraction while
    entering.
  - `intoAtmoFactor = analogue(dot(velocityDir, towardPlanet), -0.5, 0.75, 0, 1)`.
  - `speedFactor = analogue(speed, 0, 10000, 0, 2)`.
  - `AtmosphereResistance = intoAtmoFactor * strength * speedFactor`.
- Damage only above resistance 0.85: up to 15% max health/s, scaled by movement difficulty.
  Warning “STEEP REENTRY” when damage factor > 0.1 and entry timer ≤ 0.
- Atmosphere pushes rotation away from the planet by
  `0.005 * MovementDifficulty * AtmosphereEntryPush * resistance`.
- Entry effects: `SetAtmoEntryEffects(wind, flames)` attaches wind/flame particles and plays
  `AtmosphereWind`/`AtmosphereFire`; flames ramp from resistance 0.3–0.8, wind from 0–0.5.
- Planet-specific atmosphere damage (radiation/heat/acid) is separate.
- No heat bar, hull-temperature model or entry corridor UI in the recovered Lua.
- The official/community guide says a high-speed fire visual may not itself damage, while a too-steep
  entry does; the exact relationship is not fully clear. Treat this as **observed/inferred**.

### 2.7 Landing

`EGVehicle:UpdateLanding` (`EGVehicle.lua:2009-2047`):

- After a terrain contact, stores `TerrainContactSurfaceDistance` and impact speed.
- Landing allowed when `surfaceDistance <= contactDistance + 1` and speed < 4 m/s.
- No gear/snap; contact-relative, robust on slopes.
- Impact damage is computed from incidence and speed (`EGVehicle.lua:759-789`), not a fixed fall
  height.
- `UpdatePhysicsType` switches the engine physics mode at MoveSpeed 10000 and relativeTime 1.

### 2.8 Planets, gravity and scale

- `EGPlanet:GetAltitude/GetAltitudeRatio` (`EGPlanet.lua:115-137`): altitude is distance − radius;
  ratio uses atmosphere altitude.
- Gravity (`EGPlanet.lua:150-158`): `surfaceGravity / (distance/radius)²`, optionally with a
  minimum planet gravity of 0.33 enforced by the vehicle.
- Atmosphere pressure ramps from 0 at ratio 1 to 1 at ratio 0.5 (`EGPlanet.lua:139-148`).
- Planet atmosphere friction is a per-planet data value; vacuum is 0. Existing research documents
  full-size planets, 200 km atmospheres and a non-rotating planet frame.
- Sol keeps a planet-frame `WorldPos` and a floating render origin; Rodina uses engine-scale
  positions with its own precision strategy.

## 3. What Sol now does

- One `PilotCommand` consumed by one `FlightModel`; player, AI and scripted tests share it.
- Sol axes: **+X right, +Y up, −Z forward**. Rodina `(X right, Y forward, Z up)` maps to
  Sol `(X right, Y up, −Z forward)` in `PlayerPilotSource`; the visual hull, cockpit camera,
  muzzle and camera all use the same Sol convention.
- Per-gear strengths are mapped: DOCK `(0.30, 1.00, 0.30)`, COMBAT/CRUISE `(0.30, 0.30, 0.60)`.
- Rotation is inertia-driven with `rotation_speed = 2.5`, hardness 0.35/0.7/0.7, atmospheric friction
  by density, no vacuum self-stop for player input, and direct facing for AI.
- Chase camera is centred with no lateral offset. Position follows the current ship centreline;
  orientation follows with stiffness 5. Rodina's exact engine filter remains unknown.
- Entry is an independent `AtmosphericEntry` model using actual velocity angle, density proxy,
  drag, heat, corridor classification, warnings, hull/subsystem damage and recovery. This is a
  deliberate Sol design that goes beyond the recovered Lua's 4-second entry timer. It is not claimed
  to be the original implementation.
- Landing uses support points and contact; entry and landing preserve the existing hull/subsystem
  damage path.

## 4. Differences that still matter

| Area | Rodina evidence | Sol | Status |
|---|---|---|---|
| Player rotation | inertia, friction only while coasting, vacuum preserves angular velocity | same model/parameters; atmospheric density drives friction | Implemented |
| Facing/AI | direct angular velocity, arrival falloff | direct facing path | Implemented |
| Gear thrust axes | (.3,.3,1) / (.3,.6,.3) | mapped correctly | Implemented |
| Camera | distance/angle/stiffness, no lateral offset | centred offset, stiffness 5; exact filter unknown | Partial |
| Entry | 4 s state, resistance, particles, steep warning | richer heat/corridor model | Different by design |
| Landing | contact distance + 1 m, speed < 4 | support-point contact; own thresholds | Equivalent concept |
| Planet motion | non-rotating frame, full-size planets | non-rotating planet frame, floating origin | Equivalent concept |
| Warp | gear 4 / Limnal, relative time | warp flag + high cruise limit | Partial/different |
| Visual hull | cargo exterior from canonical Sol work | preserved | Implemented |

## 5. Testable implications

- Input axis mapping: forward input must produce world velocity opposite local `basis.z`.
- Rotating while coasting must not rotate world velocity.
- Gear strengths must produce forward > lateral/vertical in COMBAT/CRUISE.
- Player rotation must accelerate and retain angular velocity in vacuum; atmospheric friction must
  reduce it.
- Facing control must settle without inertia.
- Camera position must remain on the ship centreline; its right axis follows the ship; orientation
  may lag by stiffness.
- Entry must depend on velocity angle/speed/density, not nose direction.
- Landing must remain stable through entry and takeoff; full loop must pass.
- Floating origin must not jump.

## 6. Open questions

1. Exact engine camera spring/filter and roll-stabilisation rule. Requires a decompiled engine or
   controlled frame-by-frame gameplay measurement.
2. Exact `.egm` model forward/up axes; the Lua input semantics and observed ship composition are
   consistent with Sol's −Z forward, but no model file was inspected.
3. Whether Rodina's high-speed entry flames are purely visual or also damage; the Lua says damage
   above resistance 0.85, the community guide says fire may not hurt.
4. The exact Limnal relative-time interaction with combat/entry; Sol deliberately uses a readable
   warp gate rather than copying relative time.
5. Planet-specific atmosphere damage and friction values are data-driven; Sol currently uses one
   density proxy.
