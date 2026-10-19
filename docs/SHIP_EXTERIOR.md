# Player ship exterior (heavy VTOL transport / gunship)

Code: `src/flight/ship_exterior.gd` (design and parts), `src/flight/hull_mesh_builder.gd` (mesh helpers),
wired in by `src/flight/ship_visuals.gd`. Photos: `tools/ship_shots.gd` (see the end of this file).

## Rules it keeps
- **The interior is untouched.** Rooms, walls, doors, seats and panels are still built from `InteriorLayout.player_ship()`.
  The hull is a shell around them. Every room's wall, ceiling and floor corner is inside the hull by at least 3 cm
  (checked with a script against `STATIONS`; if you change `STATIONS`, re-check the cargo room's rear top corner first,
  it is the tightest).
- **What lands is what you see.** The four foot pads' undersides are `ShipTuning.support_points[0..3]` (read at build time).
  Gear, support points and `GroundContact` are unchanged.
- **Gameplay numbers are unchanged:** ramp footprint and slope, walkway timings, door portals, turret and gun muzzle points.
  The visible turret sits 0.74 m above `ShipTurret.muzzle_offset` (y 1.9 is inside the new roof); shots still start at 1.9.
- `ShipHullCollision` (keeps a person outside from walking into the hull) was resized to the new hull: x +-3.8, z -8.95..10.98,
  y -1.32..2.25. The engine pods are not solid; their underside (y -0.05) is above a standing person's head.

## Design
| Part | What it is for | Build |
|---|---|---|
| Pressure hull | crew volume around the six rooms | one loft through 5 stations; sides lean in above and below the chine (widest line); chine steps in 0.13 m |
| Visor face | cockpit view | window band (x +-1.95, y 0.15..1.5, 4 panes) between a thick brow and the prow; liner hides back faces seen through the cockpit glass wall |
| Prow | sensors, landing lights | lower hull carried forward to z -8.95 with a centre ridge |
| Engine pods | main/VTOL thrust | octagonal pods on swept pylons, intake with stator vanes forward, nozzle aft, collar + tilt actuator at the pylon |
| Lift-fan grilles | VTOL balance forward | two belly grilles under the cabin |
| Chassis rails | carry the gear, protect the belly | lofted rails along the lower hull |
| Landing gear | ground contact | oleo legs (graphite cylinder, polished piston, orange torque link), drag brace, octagonal pads |
| Ramp | boarding | two leaves hinged at the sill. Stowed: leaf 1 closes the doorway, leaf 2 folds down over it. Deployed: one straight deck on the walkway slope. Two hydraulic rams. Rails with orange tops, treads, orange toe plate |
| Dorsal | cooling, gun | heat-exchanger spine with louvres, turret barbette, cargo roof hatch with orange lift points |

Doors now slide sideways into the wall (`ShipVisuals.DOOR_SLIDE`); sliding up pushed them out through the roof.
The exhaust discs show a cold, dark nozzle throat at idle and switch to the engine glow, fading up with thrust
(`ShipExterior.update_exhaust`, driven by `Ship.last_command`; visual only).

## Materials (one texture set)
Hull: `mat_hull_plating`. Panel, structure (blue-grey) and graphite are copies of it with a tint, so seams and fasteners are
consistent everywhere. Recess (near-black, only inside openings), safety orange, polished metal, cyan lights, red/green nav
lights and the visor glass are small code materials. With asset materials off, all fall back to flat code colours.

## Cost
All static parts are one MeshInstance3D: 10 surfaces (one per material), 8,684 triangles. Moving parts: 2 ramp leaves,
4 ram cylinders, turret head, 2 nozzles + 2 discs, visor glass. One extra light (ramp work light, no shadows, only while
the ramp is open). Whole ship including the interior, counted from the built node tree: 135 mesh surfaces and about
14k triangles, against 119 surfaces and about 4.5k triangles for the old blockout. Frame time was not measured on the Mac.

## Photos
`godot --path . -s res://tools/ship_shots.gd -- <out_dir> [view_name_part]` (needs a display). Lands the ship, puts the
player beside it and saves 13 views (front/rear three-quarter, side, top, low, beside player, ramp deployed/stowed,
front, rear, far, the gameplay chase camera, the pilot's view). Progress goes to `<out_dir>/progress.log`.
