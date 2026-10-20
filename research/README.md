# Rodina research archive for Sol

This directory is the entry point for the Rodina reverse-engineering, visual research and Sol
implementation findings produced during this project. It is intended to be readable by humans and
LLM agents without requiring the original proprietary game assets.

## Start here

1. `../docs/RODINA_TECHNICAL_RESEARCH.md` — flight model, camera, atmospheric entry, landing,
   planets and AI, with source-line evidence and explicit confidence.
2. `../docs/RODINA_IMPLEMENTATION_PLAN.md` — prioritised implementation plan and current status.
3. `../docs/RODINA_FLIGHT_ORIENTATION_2026-10-19.md` — flight-axis/camera orientation findings and
   the original fix rationale.
4. `../docs/RODINA_VISUAL_RESEARCH.md` — Rodina visual identity, palette/lighting/terrain/UI
   analysis and Sol comparison.
5. `../docs/RODINA_VISUAL_ROADMAP.md` — P0–P6 visual plan.
6. `../docs/RODINA_VISUAL_P1_RESULTS.md` — reversible Sol/Rodina visual profile results.
7. `../docs/RODINA_VISUAL_P23_RESULTS.md` — ship silhouette and terrain pass results, tests and
   performance.
8. `rodina-starfall-reference/` — the existing full research archive: file inventory, spaceship,
   interiors, planets, procedural content, AI, formats, implementation guide, evidence index,
   open questions and quality check.
9. `rodina-visual-observations/` — source URLs, timestamp/frame provenance, sampled palette data
   and the visual-reference-library README.

## What is not in this repository

The following remain **local research material only**, because they are copyrighted third-party
content and are not redistributed:

- extracted Rodina 1.6.2 Lua, shaders, data and models;
- Steam/guide screenshots and the trailer;
- downloaded gameplay videos and extracted frames;
- the local `rodina-visual-research` media library and contact sheets.

See `PROVENANCE.md` for the exact boundary and the public source URLs.

## Evidence conventions

- **Confirmed** = directly read in an extracted file or directly visible in a released capture.
- **Inferred** = a behavioural interpretation not directly visible in the extracted code.
- **Unknown** = unavailable evidence (notably the engine-side camera implementation and exact
  decompiled renderer).

Do not treat line-number references as a claim that the proprietary source has been relicensed.
They are inspection notes for independent reimplementation.

## Current implementation state

- Sol repository branch for the full merged work: `flight/canonical-rodina`.
- Active branch of the known local checkout remains `play-combined`.
- Reversible visual profiles: `sol` (original) and `rodina` (alternate).
- Last reported full suite at the time of this archive: **313 tests / 98,944 assertions / 0 failures**
  on the P2/P3 build.
- No remote push had been performed before this research-publishing step.
