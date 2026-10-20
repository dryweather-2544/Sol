# 0007 — Switchable visual styles (`sol` | `rodina`) that change colour and light, never geometry

**Context.** The Rodina art-style mission asks for a Rodina-inspired look with distinct per-world families, while the
original Sol look stays available and unchanged, and switching must not touch flight, entry physics, saves, scale,
gameplay state, ship orientation, collision or landing. Before this change every world shared one hard-coded blue
sky and fog, terrain colours came from one rule in `ChunkMesher._color_for`, and tonemapping was Filmic everywhere.

**Decision.** A static `VisualStyle` (`src/world/visual_style.gd`) picks the active style: a test override, then the
`SOL_VISUAL_STYLE=sol|rodina` environment variable, then `GameSettings.visual_style` (saved as `video/visual_style`,
unknown values fall back to `sol`). For each world it returns a `PlanetLook` (`src/world/planet_look.gd`): a data
object holding the terrain colour features, detail-texture tiling, sky, fog, light and impostor colours.
- The `sol` look is built from the body's own data and reproduces the original constants; `PlanetBody.look` stays
  `null` in the `sol` style, so terrain uses the untouched original colour rule.
- Shader uniforms added for the `rodina` style default to the original Sol values, so the `sol` style renders the same.
- Switching bumps `VisualStyle.revision`; `main.gd` notices and calls `_restyle()`, which rebuilds terrain colours
  (vertex colours are baked when a chunk is meshed), restyles impostors and the hull, and re-applies the look.
- `HeightFunction` stays the only source of terrain shape. Rodina-like landforms (dunes, plates, Voronoi plateaus)
  would change collision, walking, POIs and saves, so they are a world-generation decision for later, not a style.
- Rodina-only ship effects (`ShipEffects`: engine plumes, entry heat sheath and streaks) are hidden in the `sol` style.

**Consequence.** A style switch costs one terrain rebuild. Colours in the `rodina` looks are Sol's own inferences from
the text research (no Rodina frames, code or data were available or copied; see `docs/RODINA_ART_STYLE_TECHNICAL_SPEC.md`).
`tests/unit/visual_style_test.gd` checks the `sol` style keeps the original rules and that styles never change heights
or vertices; `tools/style_switch_check.gd` checks a live switch leaves ship state, mode, world and terrain height unchanged.
