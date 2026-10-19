# Visual pass — before/after frames

All shots are 1600 × 900, Forward+, macOS Apple M4, captured from the running project with
`tools/screenshot.gd`. They are review material, not shipping assets.

| Pair | Frame |
|---|---|
| Ship / landing approach | `before_ship.png` → `after_ship.png` |
| Cockpit | `before_cockpit.png` → `after_cockpit.png` |
| Interior | `before_interior.png` → `after_interior.png` |
| Orbit | `before_space.png` → `after_space.png` |

- **Before** is the untouched `n9-art-audio` tree at `c968598` with only two Godot 4.7.2 type
  annotations added so the branch compiles. The N9 art switches were off, matching the state that
  produced the primitive look.
- **After** is `visual/n9-art-pass`, with the N9 art switches migrated on, the new hull shell,
  cockpit, HUD, atmosphere/terrain grade and rock scatter.
- The ship is at ~29 m AGL in the approach shots; the cockpit is at ~119 m AGL; the interior shot
  is after a short, gentle landing.


## Flight/entry pass

- `entry_controlled_heat.png`, `entry_controlled_critical.png`, `entry_controlled_low.png`
  — 6 km/s, -30 deg coast: heat, warnings and drag.
- `entry_steep_heat.png`, `entry_steep_critical.png`, `entry_steep_low.png`
  — 12 km/s, -70 deg: too-fast/steep failure, hull 0.
- `entry_recovery_low.png` — the same 6 km/s, -30 deg entry after braking above 55% heat:
  heat 0%, hull 100%.
- The entry frames are 1280 × 720; the earlier ship/cockpit/interior frames are 1600 × 900.

## Rodina orientation / 6-DOF pass

- `orientation_before_space.png` — old chase camera with the 3.8 m side offset: the ship reads as
  a rear-quarter/sideways view.
- `orientation_after_space.png` — centred chase camera: the rear door and wings are symmetrical.
- `orientation_start_after.png` — fixed default spawn basis; no world-up roll.
- `orientation_level.png`, `orientation_yaw90.png`, `orientation_pitch30.png`,
  `orientation_roll45.png` — real-scene camera through level/yaw/pitch/roll.
- `flight_demo_00.png` … `flight_demo_05.png` — actual scene: stationary, acceleration, yaw while
  coasting, lateral translation, braking.


## Canonical merge verification

- `merged_space.png` — merged cargo hull, cloud layer and centred chase camera at 300 km.
- `merged_low.png` — merged build on the ground; cargo exterior, clouds and no entry HUD clutter.
- `merged_entry_heat.png`, `merged_entry_critical.png`, `merged_entry_low.png` — merged entry at
  6 km/s, -30°: plasma envelope, streaks, HUD warning and post-entry airframe.
- The merged canonical suite is 300 tests / 0 failures; the 37-second ascent and cargo hull are
  preserved.
