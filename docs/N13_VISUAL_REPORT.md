# N13 visual fidelity report

Branch: `n13-visual-fidelity`, based on the actual `n12-render-flicker` HEAD (`b82d316`).
Reference archive: `/Users/arielbowyer/Documents/Deepseek workspace/rodina-visual-research/`.

## Reference evidence used

- Trailer 78–92 s **COMBAT SPEED** sequence, extracted at 2 fps; representative still
  `frames/selected/effects/trailer029_combat_speed.jpg`.
- Trailer 96–110 s **CRUISE SPEED** sequence; representative still
  `frames/selected/space/trailer035_dark_planet_trails.jpg`.
- Official orbit screenshot `frames/selected/space/steam06_orbit_ochre.jpg`.
- Entry stills `frames/selected/entry/trailer004_purple_entry_fire.jpg` and `trailer005_entry_fire.jpg`.
- Cockpit still `frames/selected/cockpit/steam02_cockpit_sunset.jpg` and the T90 gameplay contact sheets.
- Official/guide surface, space and interior images listed in `VISUAL_REFERENCE_INDEX.md`.

No labelled WARP sequence was found in the trailer or the five gameplay videos. WARP work is limited
to the existing gear/trail colour and is explicitly not claimed as reference-matched.

## Implemented (Rodina style only unless noted)

| Area | Change |
|---|---|
| Chase presentation | 85 m style-specific offset, dark hull tint, small silhouette/negative space |
| Cruise/combat | Two speed/gear-driven dotted exhaust trails; lime for cruise/combat, blue-white for WARP |
| COMBAT speed | Left-weighted blue/white streak layer gated to the real 180–500 m/s combat band |
| Entry | Large hard-edged orange/purple particle blocks, purple exposure wash, speed effects suppressed during entry |
| Sky | Broad Rodina-only dust band fallback when the starfield asset switch is off |
| Seated HUD | Cyan mode tab, hull/fuel/speed bottom bar, prompt/objective |
| On foot/inside | Cyan `ON FOOT`/`INSIDE SHIP` suit telemetry instead of the developer overlay |
| Reticle/targets | Central cyan reticle, orange hostile corner brackets, amber `HOSTILE/LOCKED` panel |
| Cockpit | Forward pilot camera removes the bright interior obstruction; canopy/dash geometry and raised instrument housing added |
| Combat feedback | Emissive projectile bolts, short muzzle flash, pooled impact particles/flash quads |
| Style integrity | Sol style unchanged: no Rodina HUD/streaks/entry/galaxy/impact effects, original chase camera retained |

## Verification captures

- Cruise HUD: `/tmp/n13_hud_final.png`
- Combat HUD/streaks: `/tmp/n13_combat_streak2.png`
- Entry fire: `/tmp/n13_entry_probe/entry4.png`
- Cockpit: `/tmp/n13_cockpit_probe/cockpit11.png`
- Orbit fallback band: `/tmp/n13_galaxy/rodina_planet_orbit.png`
- Impact probe: `/tmp/n13_impact_probe/impact4.png`
- Direct side-by-sides: `/tmp/n13_compare_cruise_final.jpg`, `n13_compare_combat_final.jpg`,
  `n13_compare_cockpit_final.jpg`, `n13_compare_entry_final.jpg`

## Tests

`Godot 4.7.2-stable | files 60 | tests 326 | assertions 97,140 | failures 0`.

## Known remaining gaps

1. No unambiguous WARP visual reference; no invented warp tunnel/FOV claim.
2. COMBAT streaks are still sparser than the trailer's screen-filling mass; current capture is over an
   orange planet, so colour composition is not directly comparable.
3. Cockpit vent/screen detail is still hard to read; dash housing is present but not reference-level.
4. Impact/muzzle flash tests are code-level; the synthetic captures did not show them cleanly.
5. User's persisted settings keep `asset_materials`, `decals`, `terrain_detail` and `starfield` off, so
   the integrated textures are not part of the current playtest captures. The pause menu now exposes
   a single "Full visual assets" toggle with an explicit applies-after-restart label.
6. Full human visual playtest is pending.
