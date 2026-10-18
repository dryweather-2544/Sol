# 0003 — Ship interior: ship-local kinematic walking against layout data

**Context.** ARCHITECTURE §7.1 planned a `SubViewport` with `own_world_3d` holding interior collision
and a `CharacterBody3D`, with a fallback of a ship-relative kinematic controller. M3.0 asks for a
spike to decide.

**Decision.** Neither physics option. Sol already moves everything on foot (M2) without physics
shapes, so the interior does the same: `InteriorBody` walks in **ship-local coordinates** against
`InteriorLayout` (room rectangles, portal openings, a ramp region, one floor height per spot).
Because the body lives in ship-local space it is unaffected by ship speed, rotation or origin
rebases by construction; the visual avatar/camera is simply a child of the ship node.

**Spike evidence.** No second `World3D` was built, so nothing was measured about one. The reasons
for skipping it are design reasons (no physics engine is used for walking anywhere in Sol; a second
world adds per-frame transform copying and a rendering-disabled viewport for no gain), not test results.

**Consequences.** Interior walkability is data: doors and the walkway change what is walkable
(`Portal.is_passable`, `WalkwayController`). No rigid-body props inside the ship; carried/dropped
items (M9) will need their own kinematic handling. Ceilings and multi-deck ships need a floor-height
lookup per deck, which `InteriorLayout.floor_height_at` already abstracts. Revisit if physics
objects inside a moving ship become a requirement.
