# N12 — ship flicker / ghosting at a planet and at speed

Branch `n12-render-flicker`, based on the N11 audio head.

## Confirmed cause

The camera and ship had different interpolation histories after a floating-origin rebase.

`FloatingOrigin.update()` told the ship and the chase camera about the new render origin. The ship
updated its own transform and reset interpolation correctly. `ChaseCamera.apply_origin_shift()`
only called `reset_physics_interpolation()` while the camera still had its **old pre-rebase**
transform; its new transform was not written until the later `_physics_process()`. That left one
stale camera sample, which Godot interpolated against the ship's new post-rebase sample. The camera
could therefore be placed on the wrong side/far side of the ship for a frame. At 5,000 m/s this
happened on many rebases (threshold 1,024 m), producing intermittent loss/ghosting; against a
planet the disappearing ship is much easier to see.

The planet was not an independent depth/occlusion bug. A stationary, rotating test with the planet
filling the background produced **0.001 px** projection movement over 200 frames and no rebases;
the same camera setup at speed reproduced the fault only when a rebase occurred.

## Evidence

Real `main.tscn`, chase camera, planet filling the frame, 5,000 m/s cruise, graphical Metal run:

Before the fix, at a rebase frame:

```text
ship_interp=(0.000012, -0.000024, 0)
camera_interp=(111.8423, -127.999, 0)
camera gap (physics)=17.336
forward dot to_ship=-0.9968   (ship behind the rendered camera)
worst projected screen jump=1125 px
ship off-screen; frame 0120 showed no ship
```

After the fix:

```text
ship_interp=(0,0,0)
camera_interp=(-8.3228, 15.2082, 0)
forward dot to_ship=0.9905
worst projected screen jump=68.8 px (normal motion between samples)
ship visible in frame 0120
```

Stationary rotating/planet-behind probe after the fix:

```text
projection jump over 200 frames = 0.0010 px
rebases = 0
```

## Fix

- `src/core/floating_origin.gd`: apply the anchor **first**, then the other origin-shift nodes.
  This guarantees the chase camera sees the new ship transform.
- `src/camera/chase_camera.gd`:
  - `apply_origin_shift()` recomputes the camera from the already-shifted target, then resets
    interpolation history;
  - `snap_to_target()` also resets after writing its new transform.
- `tests/scenario/floating_origin_test.gd`: regression test for camera position after a rebase.

The flight model, WARP/gear behaviour, camera smoothing and origin threshold are unchanged.

## Validation

```text
Godot 4.7.2 | files 60 | tests 322 | assertions 97,116 | failures 0
```

Graphical checks used the real main scene with Metal and the chase camera. No human long-session
playtest was performed; the remaining item is a normal game playtest at COMBAT, CRUISE and WARP
against a planet and in open space.
