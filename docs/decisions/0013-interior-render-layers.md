# 0013 — Safe camera planes, and the interior drawn by render layers instead of hiding nodes

**Status:** accepted (ship interior overhaul, 2026-10-22). Refines ADR 0012; the bigger-on-the-inside layout is unchanged.

## Root cause of the invisible interior

Commit 2f9b74e gave the walking camera the flight cameras' far plane (so the planet would show through the pocket
windows) while keeping its 0.05 m near plane: in orbit that is near 0.05 m, far 4,000 km. Godot builds the projection
in 32-bit floats. With far / near that large, `far + near` and `far - near` round to the same float, the projection's z
row becomes exactly -1, and the frustum's far plane (row 3 minus row 2) has a zero normal. Frustum culling then rejects
every mesh; the sky and the HUD still draw. From inside a pocket room (hull not drawn) the whole ship vanishes.

Evidence (Linux Godot 4.7.2, `tools/interior_tour.tscn`, software GL):
- With near 0.1 m and the orbit far plane every interior view is empty space and stars, cockpit and airlock included.
- `Projection.create_perspective(75, 1.78, 0.05, 4e6).z.z` is exactly -1.0 (far plane normal 0); with far 40 km it is
  -1.0000025 and the far plane sits at 39.9 km. `tests/unit/camera_range_test.gd` pins this.
- Culling happens on the CPU in `RendererSceneCull`, the same code for Forward+ and Compatibility, which is why the
  cloud's Compatibility renderer shows the same fault the owner saw with Forward+ on the Mac.

The previous handoff blamed depth precision; depth was never the problem. The revert to far 40 km in the working tree
did remove the fault, at the cost of clipping the planet out of the windows.

## Decision

1. `CameraRange` keeps every camera's far / near at or under 4e6. The walking camera's near plane rises with the far
   plane it needs (at most 0.25 m, inside a person's 0.3 m radius from a wall) and its far plane is capped to what that
   near plane allows (1,000 km at most), so the planet from orbit shows through the windows. The flight cameras' far
   plane is capped by the cockpit/turret near plane. The cockpit camera starts with safe planes.
2. Hardening of ADR 0012's drawing: no ship geometry is hidden to manage inside/outside. `ShipVisuals._assign_layers`
   puts the pocket on layer 2, the hull on layer 3 and the cockpit and airlock shells on layers 4 and 5 (lamps included).
   `main.gd` sets every camera's `cull_mask` each physics tick from where that camera is (`ShipVisuals.cull_mask_for`),
   whichever camera is current. Pocket lamps do not light the hull (`light_cull_mask`). This removes a global `visible`
   flag decided from last tick's camera, and keeps physics interpolation (which skips hidden branches) seeing the whole
   ship.

## Consequences
- Layers 2–5 are reserved for the ship.
- The walking camera's near plane is up to 0.25 m in orbit: pressing your face into a wall at an angle can clip it.
- Anything that sets a camera plane must go through `CameraRange`.
