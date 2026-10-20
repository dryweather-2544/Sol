# 0009 — Authored planet definitions are Godot resources

**Status:** accepted (N10).

**Context.** `StarSystem.default_system()` constructed every body, orbit, atmosphere and terrain
profile in code. That kept the first five worlds simple but made content changes code changes and
gave the same class both authoring and runtime responsibilities. Saves and the runtime need stable
`BodyDef` ids, not a new serialization format.

**Decision.** Add `PlanetDefinition extends Resource` as the authored content record and ship one
`.tres` per body under `data/planets/`. `StarSystem` loads definitions by id and converts them to the
existing runtime `BodyDef` with `to_body_def()`. The previous in-code construction remains as a
fallback when a file is missing or invalid. `BodyDef`, `PlanetBody`, visual style selection, terrain
generation, frame conversion and saves continue to use the same runtime types and body ids.

**Consequences.**
- A body can be edited without editing star-system assembly; invalid definitions are rejected by
  `validation_error()` and fall back rather than producing a broken system.
- Existing save identity (`sol`, `planet`, `selene`, `cinder`, `verdant`, `pebble`) is unchanged.
- There are now two representations and a conversion boundary; tests assert that every shipped
  definition loads and that identity/terrain survive the round trip.
- New worlds should add a `.tres` and a `BODY_DEFINITIONS` entry. The fallback is a safety net, not
  the long-term authoring path.
