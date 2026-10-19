# Rodina alignment: flight axes, six-DOF and chase camera — 2026-10-19

Branch: **`flight/rodina-orientation`** (uncommitted work; based on the committed
`flight/entry-pass`).

## Evidence used

Read-only extracted Rodina 1.6.2 Lua under
`/Users/arielbowyer/Downloads/Rodina.v1.6.2/Rodina.v1.6.2/Scripts`, plus the existing research
archive in `Documents/Deepseek workspace/rodina-starfall-reference` (not modified):

- `Gameplay/EGBehaviorPlayer.lua:206-235` — human input fills the same `PilotInterface` as AI;
  `MoveVector` is `controls:GetCompoundAction("MOVE_SHIP")`.
- Research `02_SPACESHIP_AND_PILOTING.md:50-75` and the actual data table establish the
  convention: **local X right, Y forward, Z up**.
- `DataGameplay/EGDataShipPlayer.lua:131-177` — gear speeds, acceleration, `MoveStrengths`
  `(.3,.3,1)` for DOCK and `(.3,.6,.3)` for COMBAT/CRUISE, and rotation hardness.
- `DataGameplay/EGDataShipPlayer.lua:315-348` — third-person camera is set by
  `SetCameraFollow(distance, angle, stiffness)`, default **distance 200, angle 10°, stiffness 5**;
  FOV 60…90 and warp FOV +30. There is no lateral offset parameter.
- `Gameplay/EGVehicle.lua:1247-1387` and `:1390-1568` — local-axis rotation/velocity integration,
  inertia, assisted target velocity, drag, and gravity.

The engine-side camera implementation is not in the recovered Lua. Its exact roll/stiffness
filtering is therefore a **gap**; Sol follows the exposed distance/angle/stiffness parameters and
keeps the camera on the ship centreline. No proprietary source was copied into Sol; the Lua was
used as behavioural evidence only.

## What was wrong in Sol

The controller, hull, interior, muzzle and cockpit all already used one convention:
**+X right, +Y up, -Z forward**. The visual model did **not** need a corrective rotation.

Two independent presentation bugs made the ship read as sideways:

1. **Chase camera had a lateral offset.** `ChaseCamera.offset_behind_up` was
   `(3.8, 2.25, 18)`: 3.8 m to the right of the centreline. With the camera looking 16–18 m
   ahead, a level ship was framed from the rear quarter. Rodina's follow API exposes distance,
   elevation angle and stiffness — not a side offset — so this was not a Rodina-style camera.
   It is the direct cause of the “flying sideways” composition.
2. **Startup orientation used world-up.** `scenes/main.gd` built the initial basis with
   `Basis.looking_at(-start_up, Vector3.UP)`. The roll of the spawned ship therefore depended on
   where the spawn point was on the planet; near a pole it degenerates. The up hint is now a
   planet-local tangent, and the camera starts from the same ship basis.

The camera pivot is not a child of the ship, so it has no inherited-transform mismatch. The
`ChaseCamera` uses the ship's basis directly; cockpit camera, hull nose, interior cockpit and muzzle
all use local `-Z` forward.

## Coordinate mapping

Rodina `(x right, y forward, z up)` maps to Sol `(x right, y up, -z forward)`:

```
right        = +X
forward(Y)   = -Z
up(Z)        = +Y
```

`PlayerPilotSource` performs that mapping explicitly; no physics root rotation or camera-only
workaround is used. `ShipTuning.gear_axis_strength` stores the mapped
`MoveStrengths` as `(right, up, back)`.

## Changes

- Chase camera: centred offset `(0, 4.2, 22)`, look-ahead 18 m, 10.8° elevation, scaled from
  Rodina's 200 m/10° follow. Position is anchored to the current ship basis (no lateral crab),
  while orientation uses Rodina's stiffness 5 for the soft swing.
- Startup: tangent up hint instead of world-up; no arbitrary camera rotation.
- Per-gear axis strengths:
  - DOCK `(0.30, 1.00, 0.30)` — vertical-led landing control.
  - COMBAT `(0.30, 0.30, 0.60)` — forward-led, weaker lateral/vertical.
  - CRUISE `(0.30, 0.30, 0.60)`.
- COMBAT acceleration increased to 1000 m/s² (the recovered gear-2 relationship), while DOCK
  stays at the existing 60 m/s² because 66 m/s² and 60 are effectively the same feel.
- CRUISE no-thrust damping reduced from 0.12× to 0.01× so releasing thrust preserves most
  momentum; `X` remains the explicit high-authority brake. DOCK/COMBAT retain assisted damping
  for precise low-speed work.
- Added `gear_axis_strength_for()` rather than a single flat axis multiplier.
- Added a camera/orientation regression test and 6-DOF rotation/translation/braking tests.
- Hid the entry HUD when landed/slow (it previously showed `ENTRY STEEP path -90° 0.0 km/s` while
  parked because vertical velocity was a tiny negative number).

## Measurements

`tools/flight_feel_probe.gd`:

```
axis strengths dock=(0.3, 1.0, 0.3) combat=(0.3, 0.3, 0.6) cruise=(0.3, 0.3, 0.6)
gear 0 forward after 5s: 30 m/s
gear 1 forward after 5s: 300 m/s
gear 2 forward after 5s: 7200 m/s
combat lateral/vertical after 3s: 150 m/s
cruise coast 10s: 6800 m/s
cruise brake to 1 m/s: 0.85 s
yaw angular velocity after 1s: 1.75 rad/s (CRUISE hardness 0.7; DOCK is 0.875)
```

The 12 km/s near-world cap remains, but the effective full-thrust cruise speed is now 7.2 km/s
because Rodina's forward strength is 0.6. The cap is reachable while coasting and is still the
distance-scaled ceiling; warp unlocks the larger interplanetary range.

`tools/orientation_probe.gd` (real scene, real chase camera):

```
ORIENT level   lateral=0.0000 behind=22.0 right_dot=1.0000
ORIENT yaw90   lateral=-0.0000 behind=22.0 right_dot=1.0000
ORIENT pitch30 lateral=0.0000 behind=22.0 right_dot=1.0000
ORIENT roll45  lateral=0.0000 behind=22.0 right_dot=1.0000
```

In the static rig probe the camera is exactly on the centreline and its right axis matches the
ship's. In motion the orientation uses stiffness 5, so the view swings rather than snapping; the
position remains on the centreline. The roll case tilts the world with the ship (no independent
camera stabilisation), because the recovered API does not expose a roll-stabilisation rule.

`tools/flight_demo.gd` runs the actual scene with scripted commands: stationary, acceleration,
yaw while coasting, lateral translation and braking. The camera remains on the centreline and the
ship's rear/wings stay symmetrical through the yaw. Position is anchored to the current basis;
orientation lags at stiffness 5, which is the recovered camera parameter but not its exact
internal filter. The orientation probe uses a level start for judging yaw/roll.

## Verification

- Full suite: **284 tests, 98,822 assertions, 2 failures** — the same two pre-existing audio tests
  (`audio_library_test.gd` sample length and headless `AudioService` tree insertion). All flight,
  replay, floating-origin, scene, descent, full-loop, frame-switch, combat, entry and new
  orientation/6-DOF tests pass.
- 1600×900 performance: orbit/descent ~100 fps average, p95 ~12 ms; ground 93 fps average with a
  69 ms worst frame; max 1020 draw calls, 606k primitives, 2.56 ms physics. The ground hitch is
  still visible and remains a known issue.
- Actual game scene was run through the orientation and flight demo probes; captures are in
  `artifacts/`.

## Remaining gaps / honest limits

- The recovered Lua does not contain the engine camera; exact Rodina stiffness/roll filtering is
  not observable from the available material, only its exposed distance/angle/stiffness. Sol uses
  a centred position, stiffness 5 orientation and ship-up rolling.
- Rodina's `MoveStrengths` and acceleration relationships are translated, but collision, terrain
  and the custom landing contact are Sol systems, not Rodina systems.
- Cruise's effective 7.2 km/s is lower than the previous 12 km/s. This is deliberate fidelity to
  the forward 0.6 strength, not a claim that 7.2 is a magic number; it should be re-evaluated by
  playtesting.
- Rotation is now inertia-based and does not self-stop in vacuum, matching the recovered player
  model. That is deliberate; the player has to counter-rotate. Atmospheric density supplies
  friction, and the facing controller bypasses inertia as Rodina's `SetDesiredFacing` does.
- The two audio failures are unrelated and pre-existing in this branch.
- Exact Rodina camera stiffness filtering remains the largest unrecoverable unknown; Sol matches
  the exposed parameter but not a decompiled engine implementation.
