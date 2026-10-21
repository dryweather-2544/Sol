# Rodina visual comparisons (N14)

Reference corpus: `/Users/arielbowyer/Documents/Deepseek workspace/rodina-visual-research/` (trailer, five
gameplay videos, Steam screenshots, selected frames, palettes). Sol captures: `docs/n13_shots/`,
`docs/n13_shots/sky/`, and the N14 terrain captures in `/tmp/n14_terrain_aurelia2/`.

## Current N14 terrain comparison

- Rodina reference: `frames/selected/surface/steam01_salmon_sky_mountains.jpg` (Jarilo-like salmon sky, dark
  layered ridges, thin star field).
- Sol N14, Rodina style: `/tmp/n14_terrain_aurelia2/rodina_planet_ground.png` and
  `/tmp/n14_terrain_aurelia2/rodina_planet_orbit.png`.
- Observed result: the new Jarilo grammar gives real relief and a dark near ridge instead of the old generic
  noise; the ground capture is dominated by a tall close ridge, so it is not a camera-matched comparison.
- Next capture: place the free camera at the same altitude/pitch as the reference, sample a lowland/ridge
  boundary, and compare mean HSV/dominant colours (`palette_compare.py`) in addition to shape.

## Existing N13 comparisons to preserve

- `docs/n13_shots/v8/` — palette-calibrated ground/sky captures.
- `docs/n13_shots/sky/<world>/` — orbit/approach/low/ground for each Sol world.
- Rodina reference frames copied under `docs/rodina_reference/` by N13.

## Cautions

The N13 port's shader formulas are source-derived, but its Voronoi point buffer and engine particle semantics
are inferred. Do not describe those adaptations as exact ports. The user-supplied Rodina frames are the
authority for composition; source data is the authority for formulae.
