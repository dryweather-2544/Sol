# Sol physics: defects ranked, what was done, what is next

Evidence for every item: `docs/RODINA_PHYSICS_AUDIT.md`. Telemetry before/after: `docs/physics_telemetry/`
(`godot --headless --path . -s res://tools/flight_telemetry.gd`). Ranked by how much each one shaped the feel or
broke a requested behaviour; dependencies in brackets.

| Rank | Defect (cause) | Status | Proof |
|---|---|---|---|
| 1 | No-input braking on every axis: momentum vanished in vacuum and gravity was cancelled (ship weightless) | **Fixed** (Rodina: no input applies nothing; ship gravity 3.5 x) | telemetry `thrust_release_space` 450 -> 0 m/s in 2 s became 500 m/s held; `hands_off_hover_1000m` 0.2 m/s sink became a 42 m/s^2 fall; `flight_model_test` |
| 2 | Rotation as a fast rate target: a spin stopped in 0.15 s, started in 0.2 s | **Fixed** (input = angular acceleration; friction only coasting and only in air) [needs 1 for the same input path] | `yaw_release_space`: 86 deg/s gone in 0.15 s became 100 deg/s kept in vacuum; `yaw_release_atmosphere` decays at the air's friction |
| 3 | Altitude levelling: below 400 m, pitch and roll forced to planet-up | **Fixed** (removed; Rodina roll-only levelling, setting, off when landed) | `pitched_up_hands_off_300m`: pitch 30 -> 0 deg in 2.5 s became 30 deg held; `flight_boundary_test` (5 tests, all fail on the old model) |
| 4 | Ramp pulled walkers in and channelled them | **Fixed** (ramp is an outside floor, doorway transition, ramp end re-fitted) | `ramp_walk_test` (6 tests; 4 failed on the old code); playthrough |
| 5 | Atmosphere speed multiplier and 0.33 s overspeed bleed (momentum lost on gear change / entering air) | **Fixed** (drag only above DragSpeed; cruise excess decays at 2/s) [1] | `gear_down_from_cruise`: 5000 -> 0 in 4 s became 5000 -> 1483 m/s, then kept |
| 6 | One axis-strength vector and turn caps for all gears | **Fixed** (Rodina gear table) [1, 2] | `flight_model_test::test_sideways_vertical_and_reverse_are_weaker_per_gear` |
| 7 | Re-entry heat by speed alone, anywhere in the air | **Fixed** (Rodina entry resistance, damage above 0.85, nose push) [1] | `survival_test::test_damage_curves` (hand-computed) |
| 8 | Frictionless sliding when touching but not landed | **Fixed** (hull friction 0.4) [1] | `ground_contact_test` |
| 9 | AI turned through the player's controller | **Fixed** (AI sets the rate directly, holds velocity with `move_lock`) [2] | `flight_model_test::test_ai_facing_sets_the_turn_rate_directly`; `slice_scenario_test` raider fight |
| 10 | No bounce (Rodina restitution 0.8) and no post-impact control ramp (`UpdateMovementControl`) | **Open** - engine-side in Rodina, needs footage to match | audit §7.2-7.3 |
| 11 | Cruise: Sol's distance-scaled speed limit, not Rodina's relative time | **Kept on purpose** (Sol's scale is far smaller; research 02 §10.6) | audit §7.6 |
| 12 | Hover vs fall when hands-off (depends on how Havok mixes velocity and acceleration) | **Open question** - Sol follows the script literally (falls) | audit §7.1; check in Rodina: release keys at 1 km in dock gear |

## Round 2b: WARP gear

| Problem | Fix | Evidence |
|---|---|---|
| The gear table ended at CRUISE; the warp coil only multiplied cruise speed and there was no separate high-speed mode | WARP gear above CRUISE, drive-gated and open-space-only, 6.7x distance-scaled cap, 0.01 fuel/s | `flight_model_test::test_warp_gear_has_a_higher_cap_than_cruise`; `progress_test` gating; `pilot_controller_test` shift reachability; save/fuel tests |

## Round 2: speeds, escape, low-speed control, gears

Telemetry: `docs/physics_telemetry/modes_before.txt` and `after.txt` (scenarios `escape_*`, `precision_*`,
`combat_tap_and_release`, `gear_switch_continuity`, `cruise_out_to_5000km`).

| Problem | Cause found | Change | Before -> after |
|---|---|---|---|
| Climb out takes ages | Cruise refused below 2 km AGL and limited to 0.3 x altitude (600 m/s at 2 km, 8 km/s cap in the air); a ] pressed below 2 km was forgotten, leaving the ship in combat (500 m/s, or 150 m/s on Space) | Cruise at any height with Rodina's in-air speeds (5 to 10 km/s, 5 km/s cap while entering); selected gear kept | surface to 200 km, nose up: 34.7 s -> 21.9 s; on Space: 114.8 s -> 70.4 s; stuck in combat: ~400 s (nose up) / ~1300 s (Space) -> not possible any more |
| Too fast near the ground | Dock gear was Rodina's 100 m/s with 66 m/s^2, no braking on release and no hover (the ship coasted and fell) | Precision gear: 30 m/s, 19.8 m/s^2, station keeping and hover | 0.25 s tap: fell 47 m and hit at 62 m/s -> 4.95 m/s peak, 1.24 m travelled, stopped in 0.52 s; hands-off 5 s at 50 m: -47 m (crash) -> -0.07 m; brake from 20 m/s: 1.02 s over 9.9 m |
| Gears may not work | Gear forgotten when refused (above); HUD showed only the name; altitude gate | Selection kept and shown ("CRUISE selected: no fuel"), HUD shows the gear's top speed, gate removed | `flight_model_test::test_gear_selection_is_clamped_to_what_is_allowed_and_comes_back` |
| Down-shift at speed | Rodina drag applied twice | Applied once | 5000 m/s, cruise to combat: 7500 -> 3750 m/s^2, smooth (`test_shifting_down_at_speed_changes_velocity_smoothly`) |

Unchanged on purpose: combat gear (Rodina's numbers; a 0.25 s tap gives 250 m/s and it coasts), cruise above the air
(200 km to 5000 km in 12.4 s before and 12.6 s after), Rodina's 0.3 up/down strength in cruise (nose-up is the fast way out).

## Order used (each stage tested before the next)

1. Baseline: full suite 273 tests / 6 pre-existing failures (`audio_library_test` parse error, 5 decal-name asserts),
   telemetry `before.txt`.
2. Ramp (`53b48d1`) - suite 273 / same 6.
3. Levelling + translation + rotation + gravity + atmosphere entry + contact friction (`b6e0f5a`) - suite 285 / same 6.
   Scripted pilots in tests and tools were given `move_lock` and `stop_rotation`, as Rodina's AI holds velocity and
   facing; no assertion was loosened. The replay snapshot was re-recorded (its own instructions say so for a
   deliberate tuning change).
4. Playthrough in the real scene (`tools/playthrough.gd`) after each stage.

## Next, highest impact first

1. Fly it on the Mac against Rodina and settle open question 12 (hover vs fall) - it decides how landing feels.
2. Collision response: restitution and the control-authority ramp after impacts (rank 10).
3. A landing aid that is explicit (a key or HUD mode), if hands-off falling proves too hard - never an automatic one.
4. Mouse scaling: Sol turns mouse pixels into turn input at 0.04 per pixel per tick; Rodina's `LOOK_MOUSE` scaling is
   engine-side. Tune by feel once 1 is settled.
