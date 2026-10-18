# 0006 — Crew are ship-local actors beside the player, not a generalised GameSession (resolves R2)

**Context.** `GameSession` is built around one person who can be seated, inside or outside. NEXT_PHASE R2 asked how
to add several actors without a rewrite that would leak into saves and the fuzz tests.

**Decision.** The player keeps `GameSession.Mode`. Crew are a separate list (`ShipCrew`, `CrewMember`) that live only
inside the ship, in ship-local coordinates like the player's interior body (same `InteriorBody`, ADR 0003). They use the
*same* `ShipSystems` calls as the player (`toggle_door`, `seats.try_sit`), so one seat has one occupant and a door
never closes on a person (crew mark `occupied_portals` too). Crew never use the airlock or go outside, so frame
switches, flight and landing cannot move them. Routes are a breadth-first search over rooms with line-up waypoints at
each door (`CrewNavigator`); no navmesh. Crew open a door when within 1.3 m of it, without walking to its panel.

**Consequence.** Crew cannot yet follow the player outside or fight outside; that needs `CrewMember` to gain an exterior
mode (not planned this phase). The save has a top-level `crew` list (absent in older saves, which keep the starting
crew). `GameSession.validate()` checks crew are never inside a wall and seat holders match `SeatManager`.
