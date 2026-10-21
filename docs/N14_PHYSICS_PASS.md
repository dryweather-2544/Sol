# N14 physics pass — contact restitution and control authority

Sources: `Scripts/Gameplay/EGVehicle.lua:736-884` (`OnCollision`, `UpdateMovementControl`) and
`Scripts/DataGameplay/EGDataShipPlayer.lua:26-38` (hull friction/restitution).

## Implemented

- `GroundContact.HULL_RESTITUTION = 0.8` and a minimum bounce speed. A non-landed first impact above the
  threshold reflects the normal velocity; a resting/landed ship is still absorbed so it does not jitter.
- `ShipState.control_timer`, `terrain_contact_timer`, `control_authority` and
  `terrain_control_authority` record the script-side timers.
- `FlightModel._update_control_authority` ramps `ControlTimer` with Rodina's 0.5–1.5 s analogue and
  feeds control authority into the drive rate. Gravity/inertia always act.
- `GroundContact` resets `terrain_contact_timer` on terrain contact.
- Tests: `test_hull_impact_restitution_matches_rodina`,
  `test_control_authority_ramps_after_a_collision`, and the slow-settle test now drops at 3 m/s while the
  high-speed bounce remains a separate test.

## Remaining uncertainty

The actual Havok `SetVelocityControl(control, terrainControl)` semantics are engine-side. Sol's
application of `control` to the drive rate is an ADAPT; `terrain_control_authority` is retained as
telemetry but not applied to takeoff because doing so made a landed ship unable to lift off. This needs a
real Rodina flight comparison before being called exact.

Tests after this pass: 361 tests / 105,038 assertions / 0 failures.
