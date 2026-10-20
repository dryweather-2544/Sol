# Guide for LLM agents

If you are an LLM continuing this work, read in this order:

1. `../docs/RODINA_TECHNICAL_RESEARCH.md` — technical findings and uncertainty labels.
2. `../docs/RODINA_VISUAL_RESEARCH.md` and the visual roadmap — aesthetic target and evidence.
3. `../docs/RODINA_VISUAL_P1_RESULTS.md` and `../docs/RODINA_VISUAL_P23_RESULTS.md` — what was
   implemented, what was rejected, current tests/performance and remaining gaps.
4. `rodina-starfall-reference/` — the wider systems research archive.
5. The Sol source itself. Do not assume the research is a replacement for the actual code.

Rules:

- Verify the current branch/HEAD/working tree before changing anything.
- Keep the `sol` and `rodina` visual profiles reversible; do not replace the Sol appearance.
- Preserve flight physics, entry mechanics, saves, collision, cockpit/interior and landing.
- Do not copy Rodina source/assets into Sol; use the evidence to implement independent behaviour.
- Record what is confirmed versus inferred; do not invent Rodina constants or decompiled code.
- Run the full suite and inspect the actual game, not only headless tests.
