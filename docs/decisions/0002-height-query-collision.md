# 0002 — Terrain collision by height query, not collision meshes (for now)

**Context.** ARCHITECTURE §4.2 planned `ConcavePolygonShape3D` collision for max-LOD chunks near
physics actors, with direct height queries only as a backstop for the ship.

**Decision.** Until a feature needs it, nothing collides with terrain through physics shapes.
The ship (`GroundContact`) and the on-foot controller (M2) ask `HeightFunction` /
`PlanetBody.surface_radius_xyz` directly. The same function builds the visual mesh, so visual and
collision heights agree by construction (error = mesh chord, centimetres at 1 m spacing).

**Consequence.** No collision-mesh generation thread, no collision lag under fast descent, no
fall-through gaps. Props (POIs, M5) will need ordinary colliders placed on top of the height
function; large overhangs/caves are impossible with a pure height field. Revisit if caves or
vehicles with physics bodies are added.
