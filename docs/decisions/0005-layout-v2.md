# 0005 — Ship layout v2: six rooms in a line, still single-deck rectangles (resolves R3)

**Context.** NEXT_PHASE R3 asked whether ADR 0003's ship-local rectangle rooms are enough once the ship has
engineering, a turret room and cargo, and what moves with a bigger hull.

**Decision.** Yes, still enough. The player ship is now cockpit, cabin, engineering, turret room, cargo and airlock
in a line, 0.2 m door gaps between them (nose z = -7.3, tail z = +10.9, about 18 m). Walls are generated from the room
rectangles and portal openings (`ShipVisuals`), not hand-placed. Stations are authored `interact_points` plus a
`stations` map (id -> role, room); the gunner seat is a second seat in `SeatManager`. Everything that depended on the
old rear (ground-contact support points, hull push-out box, chase camera, nacelles, airlock and ramp) was moved with it.

**Consequence.** The airlock and ramp moved +4.6 m aft, so save v10 migrates saved interior positions at z >= 3.4 by
+4.6 and `SaveGame.restore` puts anyone saved inside a wall at the pilot seat. Rooms are still one deck: a second deck
needs `floor_height_at` per room and stairs (not planned). The reactor panel, engine station, extinguisher locker and
gunner seat exist and can be walked to but do nothing yet (N4, N6). A longer ship lands on a longer wheelbase; landing
on slopes steeper than before is slightly harder (unmeasured).
