# Rodina visual specification from observed media

Companion to `VISUAL_REFERENCE_INDEX.md` and `VISUAL_FIDELITY_REVIEWS.md`. Tags:
**[OBS]** directly visible in a reference frame/sequence; **[INF]** inference from the image;
**[C]** corroborated by the recovered code/assets.

## 1. High-speed flight

| Property | Observation | Trigger/state | Likely implementation |
|---|---|---|---|
| Ship scale | [OBS] The player ship is a small dark shape at the frame centre during trailer COMBAT SPEED and CRUISE SPEED sequences. | Chase view while moving fast | Far chase-camera offset; dark hull values |
| Exhaust | [OBS] Two long lime/yellow dotted trails extend far behind the ship at CRUISE SPEED; they persist and follow the velocity direction. | High cruise/combat speed | Two ship-local particle trails/ribbons emitted from the nacelles, additive, colour-over-life |
| Speed streaks | [OBS] COMBAT SPEED has a large stepped blue/white streak field on the left plus green curved weapon trails. | Combat speed / high acceleration | Additive camera- or ship-space streaks at high speed; do not use a single flash |
| Planet relation | [OBS] A planet can fill the background; it does not occlude or clip the ship. | Orbit/approach | Correct depth and camera rebase (N12); planet remains behind |
| WARP | [MISSING] No labeled WARP sequence found | — | Do not invent distinct WARP visuals from these frames; verify by running Rodina |

## 2. Camera and composition

- [OBS] Reference chase framing leaves large negative space; the ship is roughly a tenth of the frame
  height, not half. Current Sol's 17 m offset makes it much larger.
- [OBS] The camera stays behind/above the ship and follows its heading; in COMBAT SPEED the ship stays
  near centre while the world streaks past.
- [INF] Use a style-specific chase offset (roughly 80–100 m) and keep the current rigid translation;
  do not add camera lag that would make the ship slide at speed.

## 3. Ship silhouette and materials

- [OBS] External player ship reads as a dark/black silhouette with small cyan/blue emissive details,
  even against a bright planet.
- [OBS] The top hull is much darker than the lit ground; side panels catch only a little coloured light.
- [C] Rodina's simple light model has low ambient/backside terms; it is not a glossy PBR look.
- Implemented: Rodina hull tint darkened to `(0.28,0.30,0.34)`; chase offset moved to 85 m.
- Still open: the reference ship's actual shape/detail and the exact black/cyan balance need a
  closer camera-matched capture.

## 4. Engines and entry effects

- [OBS] Ordinary engine output is a small blue/purple plume; the long green trails are the dominant
  motion effect at cruise.
- [OBS] Entry fire is large, blocky, additive purple/orange and screen-filling around the silhouette;
  Sol's current entry is a smooth orange sheath.
- [INF] Entry should remain gameplay-state driven (`atmosphere_resistance`), but the visual style is a
  separate effect-quality pass; do not tune entry from a single still.

## 5. Space, sky and planet

- [OBS] Space is near-black violet with crisp stars; planets have saturated ochre/salmon/cyan fields
  and thin coloured limbs.
- [OBS] Surface skies are flat, highly saturated two-colour gradients with a hard sun and visible
  stars; cloud layers are not visible in the inspected reference.
- [C] Recovered shaders implement two-colour atmosphere blends, simple sun/halo and particle bloom.
- Sol's `rodina` style already targets this; current orbit capture is close in palette, but lacks the
  painted Milky Way/dust band and has a smaller planet framing than the official screenshot.

## 6. HUD and interiors

- [OBS] Cyan/angular bitmap HUD, low-resolution UI blocks, sparse dark interiors and strong local
  colour.
- Not changed in this pass: current Sol HUD is a debug overlay and is a larger redesign than a
  single visual-fidelity fix.

## 7. Implementation constraints

- Never change flight physics, saves, collision, terrain height or gameplay state for a visual style.
- A style change must be reversible (`VisualStyle` / pause-menu setting).
- High-speed effects must use the actual `ShipState` speed/gear and must not hide a transform bug.
- Visual verification: capture the same scenario in `SOL_VISUAL_STYLE=rodina`; compare against the
  reference frame; inspect timing over a sequence, not just one still.
