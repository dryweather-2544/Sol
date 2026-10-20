# 0008 — The flight model follows Rodina's EGVehicle rules; no hidden assists

**Context.** Flight felt light and fake, the ship levelled itself below 400 m, and the ramp steered walkers. The
extracted Rodina 1.6.2 scripts became available (private repo `dryweather-2544/rodina`, read as evidence only).
They show a simple arcade model built on a few strong rules, none of which Sol had: no input applies no force, turn
input is angular acceleration, spin friction exists only in air, ships feel 3.5 x planet gravity, and the only
automatic attitude help is a roll-only levelling in the atmosphere.

**Decision.** `FlightModel` re-implements those rules in Sol's own code and axes (`docs/RODINA_PHYSICS_AUDIT.md` maps
every rule to its Rodina function and line). `ShipTuning` carries Rodina's player-ship gear table. The altitude
levelling (`PlanetBody.level_assist`) and the atmospheric speed multiplier (`max_speed_factor`) are removed. Player
input and AI intent stay separate paths, as in Rodina: players push the spin; AI facing sets the turn rate directly
(`face_direction`), and AI/scripted pilots hold a velocity with `PilotCommand.move_lock` (Rodina's `MoveLock`). Sol
keeps its own pieces where Rodina's do not fit: distance-scaled cruise speed instead of relative time, the brake key
(at Rodina's reverse-thrust rate), boost, the landed state (gear brakes, no pitch/roll while resting), and support-
point ground contact (now with Rodina's 0.4 hull friction while touching). The deployed ramp is an outside floor and
the inside/outside switch is at the doorway (`GameSession`), so walking on it follows the input.

**Consequence.** A hands-off ship falls and keeps its momentum and spin; landing needs throttle control. Scripted
pilots in tests and tools set `move_lock` and `stop_rotation`. The engine-side parts of Rodina (Havok contact,
restitution 0.8, the velocity-control authority timers, the AI mover's lock value) are not in the scripts and are
listed as open questions in the audit. Saves are unchanged: the new state (entry timer, roll smoothing) is derived.
