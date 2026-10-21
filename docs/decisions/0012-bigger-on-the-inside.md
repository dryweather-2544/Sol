# 0012 — The ship is bigger on the inside (Rodina's separate interior)

**Status:** accepted (N13 follow-up).

**Context.** The project owner asked for the ship to be "big on the inside, small on the outside", as in Rodina.
Rodina keeps the hull model and the walkable interior in separate files (`EGDataShipPlayer.lua:7-9`:
`Path = "Ship1.ShipOpen.egm"`, `InteriorPath = "DefaultMap.egi"`, `EntrancePath = "Airlock.egi"`); the interior is
its own entity (`EGInterior.lua:3-7`) the player is parented into (`EGGame.lua:335-340`), the engine builds entrance
bounds from the airlock map (`EGDataItems.lua:2076`), and the renderer has portal passes that discard what lies behind
a portal surface (research rendering_notes §6.6). How the engine hides one space from the other is C++ and was not
recovered. Sol's interior (ADR 0003) is a set of room rectangles in ship-local metres that the exterior hull was built
to enclose.

**Decision.**
- The interior is split in two by the airlock, the one place where inside and outside meet. The **threshold** rooms
  (cockpit, airlock) stay inside the hull and are always drawn. The other rooms are the **pocket**: they may be larger
  than the hull and are drawn only while the camera is inside the ship.
- Visibility follows the camera, not the player: with the camera in a pocket room the exterior hull is hidden (so it
  cannot cut through the larger rooms); with the camera outside (on foot, chase view) the pocket is hidden (so it
  cannot poke through the hull); in the cockpit or the airlock both are drawn (the pocket rooms are reached through a
  door, and the hull's inside faces are back-face culled). The airlock's two doors are never open together
  (AirlockController), so nobody standing outside can look through into the pocket.
- Pocket rooms are widened past the 7.6 m hull. Walking, doors, crew, saves and collision keep using the same
  ship-local rectangles (ADR 0003, 0005); only the numbers change, and wall panels move to the new walls.
- Both visual styles get the larger interior: it is layout, not style.

**Consequences.**
- Room ids, portal ids, seat ids and save data are unchanged; old saves load (a body saved at an old wall position
  is still inside the wider room).
- The outside hull collision (ShipHullCollision) is unchanged, so walking round the ship outside is as before.
- Anything that draws inside the pocket (room lights, fires, smoke, decals, crew) is hidden from outside with it.
