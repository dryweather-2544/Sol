# Rodina visual observations — text-only index

This is the text-only companion to the local reference library used for the visual pass. The
original library (screenshots, trailer, videos and contact sheets) is kept outside the repository
and is not redistributed.

## Contents

- `sources.csv` — every selected reference frame, its public source URL, timestamp/index,
  category, observation and confidence.
- `palette_report.csv` — approximate per-frame mean RGB/HSV and dominant colours, for the selected
  Rodina frames and the current Sol comparison frames.

## Corpus represented

- 13 official Steam screenshots for app 314230.
- Steam 1.4.2 trailer, sampled at 3-second intervals.
- Steam “Ultimate Rodina Guide” images.
- Five gameplay videos sampled at fixed intervals:
  T90Pw7FcJx8, RdXAbinofDE, oVyZD1wo0vs, 0Idoe7EjOZU, yLfsaJK63wo.
- Current-Sol comparison frames under matching orbit/high/low/ground conditions.

## Key visual conclusions

- Near-black purple space; crisp stars; no broad white atmospheric veil.
- Flat two-colour planetary sky driven by body-specific palettes.
- Hard coloured sun disc (cyan/red/orange/white), not a white overexposed blob.
- Strongly saturated planetary colour fields; broad low-frequency landforms; sparse surface detail.
- Dark ship silhouettes with small emissive accents.
- Dark grey/green interiors with strong local coloured practicals.
- Pixelated/stepped effects and cyan angular bitmap UI.
- Simple extracted lighting/atmosphere/particle shaders; no PBR/GI/volumetric atmosphere in the
  recovered Rodina rendering path.

See `../../docs/RODINA_VISUAL_RESEARCH.md` for the full analysis and evidence citations.
